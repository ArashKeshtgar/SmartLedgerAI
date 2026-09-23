using System.Text;
using System.Text.Json;
using Microsoft.Extensions.Logging;
using RabbitMQ.Client;

namespace SmartLedgerAI.Functions;

public record AnomalyDetectedEvent(
    int ExpenseId,
    string Category,
    decimal Amount,
    decimal ZScore,
    string RiskLevel,
    string? Explanation,
    DateTime DetectedAt
);

// Publishes a durable event whenever AnalyzeExpense flags a non-Low-risk expense,
// so downstream consumers (alerting, audit log, ...) don't have to poll the API.
// Failure to publish never fails the request — messaging is a side channel, not
// the source of truth for the HTTP response.
public class AnomalyEventPublisher
{
    private const string QueueName = "expense-anomalies";
    private readonly ILogger _logger;
    private readonly string _connectionString;

    public AnomalyEventPublisher(ILogger logger)
    {
        _logger = logger;
        _connectionString = Environment.GetEnvironmentVariable("RabbitMqConnectionString")
            ?? "amqp://guest:guest@localhost:5672";
    }

    public async Task PublishAsync(AnomalyDetectedEvent evt, string correlationId)
    {
        try
        {
            var factory = new ConnectionFactory { Uri = new Uri(_connectionString) };
            await using var connection = await factory.CreateConnectionAsync();
            await using var channel = await connection.CreateChannelAsync();

            await channel.QueueDeclareAsync(
                queue: QueueName, durable: true, exclusive: false, autoDelete: false);

            var body = Encoding.UTF8.GetBytes(JsonSerializer.Serialize(evt));

            var props = new BasicProperties
            {
                Persistent = true,
                ContentType = "application/json",
                CorrelationId = correlationId
            };

            await channel.BasicPublishAsync(
                exchange: string.Empty, routingKey: QueueName, mandatory: false,
                basicProperties: props, body: body);

            _logger.LogInformation(
                "PUBLISHED_ANOMALY_EVENT | CorrelationId={CorrelationId} | ExpenseId={ExpenseId} | Risk={Risk}",
                correlationId, evt.ExpenseId, evt.RiskLevel);
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex,
                "ANOMALY_EVENT_PUBLISH_FAILED | CorrelationId={CorrelationId} | ExpenseId={ExpenseId}",
                correlationId, evt.ExpenseId);
        }
    }
}
