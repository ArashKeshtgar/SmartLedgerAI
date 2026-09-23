namespace SmartLedgerAI.AnomalyNotifier;

// Mirrors SmartLedgerAI.Functions.AnomalyDetectedEvent — the two projects don't
// share an assembly (the Function ships as an isolated-worker package, the
// notifier as a plain worker), so the message contract is duplicated
// deliberately rather than adding a cross-project reference for one record.
public record AnomalyDetectedEvent(
    int ExpenseId,
    string Category,
    decimal Amount,
    decimal ZScore,
    string RiskLevel,
    string? Explanation,
    DateTime DetectedAt
);
