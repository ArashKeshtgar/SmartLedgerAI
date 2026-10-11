namespace SmartLedgerAI.Functions.Controls;

// Same three bands the anomaly view emits for RiskLevel.
public enum Severity { Low, Medium, High }

// One row in the review queue (audit.Exception). Detection is always a
// deterministic rule; the language model only ever explains, never decides.
public sealed record ControlException(
    string RuleCode,
    Severity Severity,
    string BusinessUnit,
    string SourceType,
    string SourceId,
    string Details,
    string? SubjectUser)
{
    // Re-running a scan over the same data must not open the same exception twice;
    // audit.Exception has a unique index on this value.
    public string Fingerprint => $"{RuleCode}:{SourceType}:{SourceId}";
}

public sealed record Payment(
    string PaymentId,
    string BusinessUnit,
    string VendorId,
    string InvoiceNumber,
    decimal Amount,
    DateOnly PaidOn,
    string EnteredBy);

public sealed record JournalLine(string AccountCode, decimal Debit, decimal Credit);

// PostedAtLocal is the clinic's local (Ontario) time, not UTC: business hours,
// weekends and month-end are all judged on the wall clock.
public sealed record JournalEntry(
    string EntryId,
    string BusinessUnit,
    DateTime PostedAtLocal,
    bool IsManual,
    string CreatedBy,
    IReadOnlyList<JournalLine> Lines);

// Anything that goes through an approval limit: an expense, a manual journal entry.
public sealed record ApprovableItem(
    string SourceType,
    string SourceId,
    string BusinessUnit,
    decimal Amount,
    string SubmittedBy);

public sealed record ControlScanInput(
    IReadOnlyList<Payment> Payments,
    IReadOnlyList<JournalEntry> JournalEntries,
    IReadOnlyList<ApprovableItem> ApprovableItems);
