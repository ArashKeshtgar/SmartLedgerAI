using Microsoft.Azure.Functions.Worker;
using Microsoft.Azure.Functions.Worker.Http;
using Microsoft.Extensions.Logging;
using Microsoft.Data.SqlClient;
using System.Data;
using System.Diagnostics;
using System.Net;
using System.Text.Json;

namespace SmartLedgerAI.Functions;

public class AnalyzeExpense
{
    private readonly ILogger<AnalyzeExpense> _logger;

    public AnalyzeExpense(ILogger<AnalyzeExpense> logger)
    {
        _logger = logger;
    }

    [Function("AnalyzeExpense")]
    public async Task<HttpResponseData> Run(
        [HttpTrigger(AuthorizationLevel.Function, "post", Route = "analyze-expense")]
        HttpRequestData req)
    {
        var correlationId = Guid.NewGuid().ToString();
        var sw = Stopwatch.StartNew();

        _logger.LogInformation("START | CorrelationId={CorrelationId}", correlationId);

        try
        {
            // Input is now just ExpenseId, not manual stat fields
            var input = await JsonSerializer.DeserializeAsync<ExpenseIdRequest>(req.Body);

            if (!ExpenseRequestValidator.IsValid(input))
            {
                var bad = req.CreateResponse(HttpStatusCode.BadRequest);
                await bad.WriteStringAsync("Invalid request body. Expecting { \"ExpenseId\": 101 }");
                return bad;
            }

            // Read real stats from the view instead of trusting the caller
            var expenseId = input!.ExpenseId;
            var stats = await GetExpenseStatsAsync(expenseId);

            if (stats is null)
            {
                var notFound = req.CreateResponse(HttpStatusCode.NotFound);
                await notFound.WriteStringAsync($"No stats found for ExpenseId {expenseId}.");
                return notFound;
            }

            // RiskLevel comes from the view itself (already computed from ZScore)
            string risk = stats.RiskLevel;

            string? explanation = null;

            if (risk != "Low")
            {
                explanation = await ExplainWithAI(stats, risk);

                var publisher = new AnomalyEventPublisher(_logger);
                await publisher.PublishAsync(
                    new AnomalyDetectedEvent(
                        stats.ExpenseId, stats.Category, stats.Amount, stats.ZScore,
                        risk, explanation, DateTime.UtcNow),
                    correlationId);
            }

            var result = new
            {
                stats.ExpenseId,
                stats.Category,
                stats.Amount,
                stats.ZScore,
                RiskLevel = risk,
                Explanation = explanation,
                EvaluatedAt = DateTime.UtcNow
            };

            sw.Stop();

            _logger.LogInformation(
                "END | CorrelationId={CorrelationId} | Risk={Risk} | Time={Elapsed}",
                correlationId,
                risk,
                sw.ElapsedMilliseconds
            );

            var response = req.CreateResponse(HttpStatusCode.OK);
            await response.WriteAsJsonAsync(result);
            return response;
        }
        catch (JsonException ex)
        {
            _logger.LogWarning(ex, "BAD_JSON | CorrelationId={CorrelationId}", correlationId);

            var bad = req.CreateResponse(HttpStatusCode.BadRequest);
            await bad.WriteStringAsync("Invalid JSON payload");
            return bad;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "UNHANDLED_ERROR | CorrelationId={CorrelationId}", correlationId);

            var err = req.CreateResponse(HttpStatusCode.InternalServerError);
            await err.WriteStringAsync(ex.ToString());
            return err;
        }
    }

    private async Task<ExpenseStatsRow?> GetExpenseStatsAsync(int expenseId)
    {
        // Local dev: local.settings.json -> "Values" -> "SqlConnectionString"
        // Azure: Function App -> Configuration -> Application settings -> SqlConnectionString
        var connectionString = Environment.GetEnvironmentVariable("SqlConnectionString");
        if (string.IsNullOrWhiteSpace(connectionString))
            throw new InvalidOperationException("SqlConnectionString app setting is not configured.");

        const string query = @"
            SELECT TOP 1
                ExpenseId,
                Category,
                Amount,
                AvgAmount,
                StdDevAmount,
                SampleSize,
                ZScore,
                RiskLevel
            FROM dbo.vw_ExpenseAnomalyStats
            WHERE ExpenseId = @ExpenseId;";

        using var connection = new SqlConnection(connectionString);
        using var command = new SqlCommand(query, connection);
        command.Parameters.Add(new SqlParameter("@ExpenseId", SqlDbType.Int) { Value = expenseId });

        await connection.OpenAsync();
        using var reader = await command.ExecuteReaderAsync();

        if (!await reader.ReadAsync())
            return null;

        return new ExpenseStatsRow(
            ExpenseId: reader.GetInt32(reader.GetOrdinal("ExpenseId")),
            Category: reader.GetString(reader.GetOrdinal("Category")),
            Amount: Convert.ToDecimal(reader.GetValue(reader.GetOrdinal("Amount"))),
            ZScore: Convert.ToDecimal(reader.GetValue(reader.GetOrdinal("ZScore"))),
            RiskLevel: reader.GetString(reader.GetOrdinal("RiskLevel"))
        );
    }

    private async Task<string> ExplainWithAI(ExpenseStatsRow stats, string risk)
    {
        var endpoint = Environment.GetEnvironmentVariable("OPENAI_ENDPOINT")?.TrimEnd('/');
        var key = Environment.GetEnvironmentVariable("OPENAI_KEY");
        var deployment = Environment.GetEnvironmentVariable("OPENAI_DEPLOYMENT");

        _logger.LogInformation("OPENAI_ENDPOINT={Endpoint}", endpoint);
        _logger.LogInformation("OPENAI_DEPLOYMENT={Deployment}", deployment);

        var url =
            $"{endpoint}/openai/deployments/{deployment}/chat/completions?api-version=2025-01-01-preview";

        _logger.LogInformation("OPENAI_URL={Url}", url);

        using var httpClient = new HttpClient();
        httpClient.DefaultRequestHeaders.Add("api-key", key);

        var prompt = PromptBuilder.BuildAnomalyExplanationPrompt(stats, risk);

        var body = new
        {
            messages = new[]
            {
                new { role = "user", content = prompt }
            },
            max_completion_tokens = 50,
            temperature = 0.2
        };

        var json = JsonSerializer.Serialize(body);
        _logger.LogInformation("OPENAI_REQUEST={Request}", json);

        var response = await httpClient.PostAsync(
            url,
            new StringContent(json, System.Text.Encoding.UTF8, "application/json")
        );

        var content = await response.Content.ReadAsStringAsync();

        _logger.LogInformation("OPENAI_STATUS={Status}", (int)response.StatusCode);
        _logger.LogInformation("OPENAI_RESPONSE={Response}", content);

        if (!response.IsSuccessStatusCode)
        {
            return $"OPENAI_ERROR: {(int)response.StatusCode} - {content}";
        }

        using var doc = JsonDocument.Parse(content);

        return doc.RootElement
            .GetProperty("choices")[0]
            .GetProperty("message")
            .GetProperty("content")
            .GetString() ?? "No response";
    }
}

// DTOs
public record ExpenseIdRequest(int ExpenseId);

public record ExpenseStatsRow(
    int ExpenseId,
    string Category,
    decimal Amount,
    decimal ZScore,
    string RiskLevel
);

// Pure, unit-testable helpers — no I/O, so they can be exercised without a real
// Function host, database, or OpenAI endpoint.
public static class ExpenseRequestValidator
{
    public static bool IsValid(ExpenseIdRequest? request) =>
        request is not null && request.ExpenseId > 0;
}

public static class PromptBuilder
{
    public static string BuildAnomalyExplanationPrompt(ExpenseStatsRow stats, string risk) => $"""
        Expense category: {stats.Category}
        Amount: {stats.Amount}
        Z-Score: {stats.ZScore}
        Risk: {risk}

        Explain in one short sentence why this expense might be unusual.
        """;
}
