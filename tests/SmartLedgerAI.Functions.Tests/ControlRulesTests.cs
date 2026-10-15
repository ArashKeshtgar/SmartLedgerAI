using SmartLedgerAI.Functions.Controls;

namespace SmartLedgerAI.Functions.Tests;

public class ControlRulesTests
{
    private static readonly ControlRuleOptions Options = new();

    private static Payment Pay(string id, string vendor, string invoice, decimal amount, DateOnly paidOn, string unit = "Clinic-A") =>
        new(id, unit, vendor, invoice, amount, paidOn, EnteredBy: "clerk@clinic");

    private static JournalEntry Manual(string id, DateTime postedAtLocal, params JournalLine[] lines) =>
        new(id, "Clinic-A", postedAtLocal, IsManual: true, CreatedBy: "accountant@clinic", lines);

    private static readonly JournalLine Expense = new("6100", 500m, 0m);
    private static readonly JournalLine Payable = new("2000", 0m, 500m);

    // --- Duplicate payments ---

    [Fact]
    public void DuplicatePayments_FlagsSecondPayment_WithinWindow()
    {
        var payments = new[]
        {
            Pay("P1", "V1", "INV-001", 250m, new DateOnly(2026, 1, 10)),
            Pay("P2", "V1", "inv 001", 250m, new DateOnly(2026, 3, 1)),
        };

        var result = Assert.Single(ControlRules.DuplicatePayments(payments, Options));

        Assert.Equal(RuleCodes.DuplicatePayment, result.RuleCode);
        Assert.Equal(Severity.High, result.Severity);
        Assert.Equal("P2", result.SourceId);
        Assert.Contains("P1", result.Details);
    }

    [Fact]
    public void DuplicatePayments_Ignores_PaymentsOutsideWindow()
    {
        var payments = new[]
        {
            Pay("P1", "V1", "INV-001", 250m, new DateOnly(2026, 1, 1)),
            Pay("P2", "V1", "INV-001", 250m, new DateOnly(2026, 4, 2)), // 91 days
        };

        Assert.Empty(ControlRules.DuplicatePayments(payments, Options));
    }

    [Theory]
    [InlineData("V2", "INV-001", 250)]   // different vendor
    [InlineData("V1", "INV-002", 250)]   // different invoice
    [InlineData("V1", "INV-001", 250.01)] // different amount
    public void DuplicatePayments_RequiresVendorInvoiceAndAmountToMatch(string vendor, string invoice, decimal amount)
    {
        var payments = new[]
        {
            Pay("P1", "V1", "INV-001", 250m, new DateOnly(2026, 1, 10)),
            Pay("P2", vendor, invoice, amount, new DateOnly(2026, 1, 11)),
        };

        Assert.Empty(ControlRules.DuplicatePayments(payments, Options));
    }

    [Fact]
    public void DuplicatePayments_Ignores_PaymentsWithoutInvoiceNumber()
    {
        var payments = new[]
        {
            Pay("P1", "V1", " - ", 250m, new DateOnly(2026, 1, 10)),
            Pay("P2", "V1", "", 250m, new DateOnly(2026, 1, 11)),
        };

        Assert.Empty(ControlRules.DuplicatePayments(payments, Options));
    }

    // --- New vendor, large first payment ---

    [Fact]
    public void NewVendorLargePayments_FlagsOnlyTheFirstPayment()
    {
        var payments = new[]
        {
            Pay("P2", "V9", "B", 7_000m, new DateOnly(2026, 2, 1)),
            Pay("P1", "V9", "A", 6_000m, new DateOnly(2026, 1, 1)),
            Pay("P3", "V8", "C", 4_999.99m, new DateOnly(2026, 1, 1)),
        };

        var result = Assert.Single(ControlRules.NewVendorLargePayments(payments, Options));

        Assert.Equal("P1", result.SourceId);
    }

    // --- Manual entry timing ---

    [Fact]
    public void ManualEntryTiming_IgnoresWeekdayBusinessHours()
    {
        var entry = Manual("JE1", new DateTime(2026, 10, 14, 10, 30, 0), Expense, Payable); // Wednesday

        Assert.Empty(ControlRules.ManualEntryTiming([entry], Options));
    }

    [Theory]
    [InlineData(2026, 10, 14, 7, 59, "outside business hours")]
    [InlineData(2026, 10, 14, 18, 0, "outside business hours")]
    [InlineData(2026, 10, 17, 11, 0, "Saturday")]
    [InlineData(2026, 9, 30, 11, 0, "last day of the month")]
    public void ManualEntryTiming_FlagsUnusualTimes(int y, int m, int d, int hh, int mm, string expected)
    {
        var entry = Manual("JE1", new DateTime(y, m, d, hh, mm, 0), Expense, Payable);

        var result = Assert.Single(ControlRules.ManualEntryTiming([entry], Options));

        Assert.Equal(Severity.Low, result.Severity);
        Assert.Contains(expected, result.Details);
    }

    [Fact]
    public void ManualEntryTiming_IgnoresSystemGeneratedEntries()
    {
        var entry = Manual("JE1", new DateTime(2026, 10, 17, 2, 0, 0), Expense, Payable) with { IsManual = false };

        Assert.Empty(ControlRules.ManualEntryTiming([entry], Options));
    }

    // --- Manual entries to cash / control accounts ---

    [Fact]
    public void ManualCashOrControlAccount_FlagsEntryTouchingCash()
    {
        var entry = Manual("JE1", new DateTime(2026, 10, 14, 10, 0, 0),
            new JournalLine("1000", 0m, 900m), new JournalLine("6100", 900m, 0m));

        var result = Assert.Single(ControlRules.ManualCashOrControlAccount([entry], Options));

        Assert.Equal(Severity.Medium, result.Severity);
        Assert.Contains("1000", result.Details);
    }

    [Fact]
    public void ManualCashOrControlAccount_IgnoresOrdinaryAccounts()
    {
        var entry = Manual("JE1", new DateTime(2026, 10, 14, 10, 0, 0), Expense, Payable);

        Assert.Empty(ControlRules.ManualCashOrControlAccount([entry], Options));
    }

    // --- Threshold proximity / round amounts ---

    [Theory]
    [InlineData(975.50)]
    [InlineData(999.99)]
    [InlineData(9_800)]
    public void ThresholdProximity_FlagsAmountsJustBelowALimit_AsMedium(decimal amount)
    {
        var item = new ApprovableItem("Expense", "E1", "Clinic-A", amount, "staff@clinic");

        var result = Assert.Single(ControlRules.ThresholdProximity([item], Options));

        Assert.Equal(Severity.Medium, result.Severity);
        Assert.Contains("approval limit", result.Details);
    }

    [Fact]
    public void ThresholdProximity_FlagsLargeRoundAmount_AsLow()
    {
        var item = new ApprovableItem("Expense", "E1", "Clinic-A", 4_500m, "staff@clinic");

        var result = Assert.Single(ControlRules.ThresholdProximity([item], Options));

        Assert.Equal(Severity.Low, result.Severity);
        Assert.Contains("round amount", result.Details);
    }

    [Theory]
    [InlineData(123.45)]
    [InlineData(900)]      // round, but under the round-amount floor
    [InlineData(1_000.01)] // just above a limit is the next approver's job, not a dodge
    public void ThresholdProximity_IgnoresOrdinaryAmounts(decimal amount)
    {
        var item = new ApprovableItem("Expense", "E1", "Clinic-A", amount, "staff@clinic");

        Assert.Empty(ControlRules.ThresholdProximity([item], Options));
    }

    // --- Benford ---

    [Theory]
    [InlineData(1, 1)]
    [InlineData(0.042, 4)]
    [InlineData(987_654.32, 9)]
    [InlineData(-25, 2)]
    public void FirstDigit_IsScaleIndependent(decimal amount, int expected)
    {
        Assert.Equal(expected, ControlRules.FirstDigit(amount));
    }

    [Fact]
    public void Benford_Conforms_ForAGeometricSeries()
    {
        // A geometric series covering a whole number of decades follows Benford closely.
        var payments = Enumerable.Range(0, 500)
            .Select(i => Pay($"P{i}", $"V{i}", $"I{i}", Math.Round(10m * (decimal)Math.Pow(10, 4.0 * i / 500), 2), new DateOnly(2026, 5, 1)))
            .ToList();

        Assert.True(ControlRules.BenfordFirstDigitMad(payments.Select(p => p.Amount).ToList()) < 0.006);
        Assert.Empty(ControlRules.Benford(payments, Options));
    }

    [Fact]
    public void Benford_FlagsAPopulationThatAvoidsLowDigits()
    {
        // Everything between 400 and 900: no 1s, 2s or 3s at all.
        var payments = Enumerable.Range(0, 400)
            .Select(i => Pay($"P{i}", $"V{i}", $"I{i}", 400m + i, new DateOnly(2026, 5, 1)))
            .ToList();

        var result = Assert.Single(ControlRules.Benford(payments, Options));

        Assert.Equal("Clinic-A:2026-05", result.SourceId);
        Assert.Null(result.SubjectUser);
    }

    [Fact]
    public void Benford_SkipsSmallPopulations()
    {
        var payments = Enumerable.Range(0, 299)
            .Select(i => Pay($"P{i}", $"V{i}", $"I{i}", 500m, new DateOnly(2026, 5, 1)))
            .ToList();

        Assert.Empty(ControlRules.Benford(payments, Options));
    }

    // --- Engine ---

    [Fact]
    public void RunAll_IsDeterministic_AndFingerprintsAreUnique()
    {
        var input = new ControlScanInput(
            Payments:
            [
                Pay("P1", "V1", "INV-001", 6_000m, new DateOnly(2026, 1, 10)),
                Pay("P2", "V1", "INV-001", 6_000m, new DateOnly(2026, 1, 12)),
            ],
            JournalEntries:
            [
                Manual("JE1", new DateTime(2026, 1, 31, 22, 0, 0), new JournalLine("1000", 0m, 50m), new JournalLine("6100", 50m, 0m)),
            ],
            ApprovableItems: [new ApprovableItem("Expense", "E1", "Clinic-A", 990m, "staff@clinic")]);

        var first = ControlRules.RunAll(input, Options);
        var second = ControlRules.RunAll(input, Options);

        Assert.Equal(first, second);
        Assert.Equal(
            [RuleCodes.DuplicatePayment, RuleCodes.NewVendorLargePayment, RuleCodes.ManualEntryTiming,
             RuleCodes.ManualCashOrControlAccount, RuleCodes.ThresholdProximity],
            first.Select(e => e.RuleCode));
        Assert.Equal(first.Count, first.Select(e => e.Fingerprint).Distinct().Count());
    }
}
