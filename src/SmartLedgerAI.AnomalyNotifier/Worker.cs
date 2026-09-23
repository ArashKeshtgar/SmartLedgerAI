using System.Text;
using System.Text.Json;
using RabbitMQ.Client;
using RabbitMQ.Client.Events;

namespace SmartLedgerAI.AnomalyNotifier;

// Consumes the "expense-anomalies" queue that AnalyzeExpense publishes to.
// Stands in for what would be a real alerting integration (Slack, email, a
// ticket) — here it logs each anomaly, which is enough to prove the
// publish -> queue -> consume path actually works end to end.
public class Worker : BackgroundService
{
    private const string QueueName = "expense-anomalies";
    private readonly ILogger<Worker> _logger;
    private readonly string _connectionString;
    private IConnection? _connection;
    private IChannel? _channel;

    public Worker(ILogger<Worker> logger)
    {
        _logger = logger;
        _connectionString = Environment.GetEnvironmentVariable("RabbitMqConnectionString")
            ?? "amqp://guest:guest@localhost:5672";
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        var factory = new ConnectionFactory { Uri = new Uri(_connectionString) };

        // RabbitMQ isn't always up yet when this worker starts (docker-compose
        // doesn't guarantee ordering) — retry instead of crash-looping.
        while (!stoppingToken.IsCancellationRequested)
        {
            try
            {
                _connection = await factory.CreateConnectionAsync(stoppingToken);
                _channel = await _connection.CreateChannelAsync(cancellationToken: stoppingToken);
                break;
            }
            catch (Exception ex)
            {
                _logger.LogWarning("RABBITMQ_CONNECT_RETRY | {Message}", ex.Message);
                await Task.Delay(TimeSpan.FromSeconds(5), stoppingToken);
            }
        }

        if (_channel is null) return;

        await _channel.QueueDeclareAsync(
            queue: QueueName, durable: true, exclusive: false, autoDelete: false,
            cancellationToken: stoppingToken);

        var consumer = new AsyncEventingBasicConsumer(_channel);
        consumer.ReceivedAsync += async (_, ea) =>
        {
            try
            {
                var json = Encoding.UTF8.GetString(ea.Body.ToArray());
                var evt = JsonSerializer.Deserialize<AnomalyDetectedEvent>(json);

                _logger.LogInformation(
                    "ANOMALY_RECEIVED | CorrelationId={CorrelationId} | ExpenseId={ExpenseId} | " +
                    "Category={Category} | Amount={Amount} | Risk={Risk} | Explanation={Explanation}",
                    ea.BasicProperties.CorrelationId, evt?.ExpenseId, evt?.Category,
                    evt?.Amount, evt?.RiskLevel, evt?.Explanation);

                await _channel.BasicAckAsync(ea.DeliveryTag, multiple: false);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "ANOMALY_PROCESSING_FAILED");
                await _channel.BasicNackAsync(ea.DeliveryTag, multiple: false, requeue: true);
            }
        };

        await _channel.BasicConsumeAsync(
            queue: QueueName, autoAck: false, consumer: consumer, cancellationToken: stoppingToken);

        _logger.LogInformation("ANOMALY_NOTIFIER_READY | Listening on queue '{Queue}'", QueueName);

        await Task.Delay(Timeout.Infinite, stoppingToken).ContinueWith(_ => { });
    }

    public override async Task StopAsync(CancellationToken cancellationToken)
    {
        if (_channel is not null) await _channel.CloseAsync(cancellationToken);
        if (_connection is not null) await _connection.CloseAsync(cancellationToken);
        await base.StopAsync(cancellationToken);
    }
}
