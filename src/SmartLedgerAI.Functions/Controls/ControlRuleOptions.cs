namespace SmartLedgerAI.Functions.Controls;

// Defaults follow the clinic group's finance plan. Thresholds marked "placeholder"
// have no agreed value yet and must be confirmed by the owner before go-live.
public sealed record ControlRuleOptions
{
    public int DuplicatePaymentWindowDays { get; init; } = 90;

    public TimeOnly BusinessDayStart { get; init; } = new(8, 0);
    public TimeOnly BusinessDayEnd { get; init; } = new(18, 0);

    // Unit manager up to 1,000; Controller up to 10,000; owner above.
    public IReadOnlyList<decimal> ApprovalThresholds { get; init; } = [1_000m, 10_000m];

    // An amount within this fraction at or below a threshold is "just below" it.
    public decimal JustBelowThresholdMargin { get; init; } = 0.03m;

    public decimal RoundAmountUnit { get; init; } = 100m;
    public decimal RoundAmountFloor { get; init; } = 1_000m;

    // 1000 bank; 1100 / 1140 receivables (incl. OHIP); 1200 drug inventory.
    public IReadOnlySet<string> CashAccounts { get; init; } = new HashSet<string> { "1000" };
    public IReadOnlySet<string> ControlAccounts { get; init; } = new HashSet<string> { "1100", "1140", "1200" };

    // Placeholder.
    public decimal NewVendorLargeFirstPayment { get; init; } = 5_000m;

    // Nigrini: first-digit MAD above 0.015 is nonconformity. Benford is meaningless
    // on small populations, and amounts under 10 are excluded by convention.
    public int BenfordMinimumSample { get; init; } = 300;
    public decimal BenfordMinimumAmount { get; init; } = 10m;
    public double BenfordNonconformityMad { get; init; } = 0.015;
}
