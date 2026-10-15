using System.Globalization;

namespace SmartLedgerAI.Functions.Controls;

public static class RuleCodes
{
    public const string DuplicatePayment = "DUPLICATE_PAYMENT";
    public const string ManualEntryTiming = "MANUAL_ENTRY_TIMING";
    public const string ThresholdProximity = "THRESHOLD_PROXIMITY";
    public const string ManualCashOrControlAccount = "MANUAL_CASH_CONTROL_ACCOUNT";
    public const string NewVendorLargePayment = "NEW_VENDOR_LARGE_PAYMENT";
    public const string Benford = "BENFORD_FIRST_DIGIT";
}

// Pure functions over already-loaded ledger data: no I/O, so every rule is
// unit-testable and the same input always yields the same exceptions.
public static class ControlRules
{
    public static IReadOnlyList<ControlException> RunAll(ControlScanInput input, ControlRuleOptions options) =>
    [
        .. DuplicatePayments(input.Payments, options),
        .. NewVendorLargePayments(input.Payments, options),
        .. ManualEntryTiming(input.JournalEntries, options),
        .. ManualCashOrControlAccount(input.JournalEntries, options),
        .. ThresholdProximity(input.ApprovableItems, options),
        .. Benford(input.Payments, options),
    ];

    // Same vendor, same amount, same invoice number within the window.
    // The later payment is the one flagged; the details point back at the first.
    public static IEnumerable<ControlException> DuplicatePayments(
        IEnumerable<Payment> payments, ControlRuleOptions options)
    {
        var groups = payments
            .Where(p => NormalizeInvoice(p.InvoiceNumber).Length > 0)
            .GroupBy(p => (p.VendorId, Invoice: NormalizeInvoice(p.InvoiceNumber), p.Amount));

        foreach (var group in groups)
        {
            var ordered = group.OrderBy(p => p.PaidOn).ThenBy(p => p.PaymentId, StringComparer.Ordinal).ToList();
            for (var i = 1; i < ordered.Count; i++)
            {
                var previous = ordered[i - 1];
                var current = ordered[i];
                var days = current.PaidOn.DayNumber - previous.PaidOn.DayNumber;
                if (days > options.DuplicatePaymentWindowDays)
                    continue;

                yield return new ControlException(
                    RuleCodes.DuplicatePayment,
                    Severity.High,
                    current.BusinessUnit,
                    "Payment",
                    current.PaymentId,
                    $"Vendor {current.VendorId}, invoice {current.InvoiceNumber}, amount {Money(current.Amount)} " +
                    $"was already paid by {previous.PaymentId} {days} day(s) earlier.",
                    current.EnteredBy);
            }
        }
    }

    // A vendor's first-ever payment above the limit. Callers must pass the full
    // payment history, otherwise an old vendor looks new.
    public static IEnumerable<ControlException> NewVendorLargePayments(
        IEnumerable<Payment> payments, ControlRuleOptions options)
    {
        var firstPayments = payments
            .GroupBy(p => p.VendorId)
            .Select(g => g.OrderBy(p => p.PaidOn).ThenBy(p => p.PaymentId, StringComparer.Ordinal).First());

        foreach (var p in firstPayments)
        {
            if (p.Amount < options.NewVendorLargeFirstPayment)
                continue;

            yield return new ControlException(
                RuleCodes.NewVendorLargePayment,
                Severity.Medium,
                p.BusinessUnit,
                "Payment",
                p.PaymentId,
                $"First payment to vendor {p.VendorId} is {Money(p.Amount)}, " +
                $"at or above {Money(options.NewVendorLargeFirstPayment)}.",
                p.EnteredBy);
        }
    }

    public static IEnumerable<ControlException> ManualEntryTiming(
        IEnumerable<JournalEntry> entries, ControlRuleOptions options)
    {
        foreach (var e in entries.Where(e => e.IsManual))
        {
            var reasons = new List<string>();
            var time = TimeOnly.FromDateTime(e.PostedAtLocal);
            var date = e.PostedAtLocal.Date;

            if (date.DayOfWeek is DayOfWeek.Saturday or DayOfWeek.Sunday)
                reasons.Add($"posted on a {date.DayOfWeek}");
            else if (time < options.BusinessDayStart || time >= options.BusinessDayEnd)
                reasons.Add($"posted at {time:HH\\:mm}, outside business hours");

            if (date.Day == DateTime.DaysInMonth(date.Year, date.Month))
                reasons.Add("posted on the last day of the month");

            if (reasons.Count == 0)
                continue;

            yield return new ControlException(
                RuleCodes.ManualEntryTiming,
                Severity.Low,
                e.BusinessUnit,
                "JournalEntry",
                e.EntryId,
                $"Manual entry {string.Join("; ", reasons)}.",
                e.CreatedBy);
        }
    }

    public static IEnumerable<ControlException> ManualCashOrControlAccount(
        IEnumerable<JournalEntry> entries, ControlRuleOptions options)
    {
        foreach (var e in entries.Where(e => e.IsManual))
        {
            var hit = e.Lines
                .Select(l => l.AccountCode)
                .Where(a => options.CashAccounts.Contains(a) || options.ControlAccounts.Contains(a))
                .Distinct()
                .Order(StringComparer.Ordinal)
                .ToList();

            if (hit.Count == 0)
                continue;

            yield return new ControlException(
                RuleCodes.ManualCashOrControlAccount,
                Severity.Medium,
                e.BusinessUnit,
                "JournalEntry",
                e.EntryId,
                $"Manual entry posts directly to cash/control account(s) {string.Join(", ", hit)}.",
                e.CreatedBy);
        }
    }

    // Amounts just under an approval limit suggest splitting to dodge the next
    // approver; large round amounts suggest estimates rather than invoices.
    public static IEnumerable<ControlException> ThresholdProximity(
        IEnumerable<ApprovableItem> items, ControlRuleOptions options)
    {
        foreach (var item in items)
        {
            var threshold = options.ApprovalThresholds
                .Where(t => item.Amount <= t && item.Amount >= t * (1 - options.JustBelowThresholdMargin))
                .Cast<decimal?>()
                .FirstOrDefault();

            var isRound = item.Amount >= options.RoundAmountFloor && item.Amount % options.RoundAmountUnit == 0;

            if (threshold is null && !isRound)
                continue;

            var reasons = new List<string>();
            if (threshold is not null)
                reasons.Add($"{Money(item.Amount)} is just at or below the {Money(threshold.Value)} approval limit");
            if (isRound)
                reasons.Add($"{Money(item.Amount)} is a round amount");

            yield return new ControlException(
                RuleCodes.ThresholdProximity,
                threshold is not null ? Severity.Medium : Severity.Low,
                item.BusinessUnit,
                item.SourceType,
                item.SourceId,
                string.Join("; ", reasons) + ".",
                item.SubmittedBy);
        }
    }

    // First-digit test per business unit per month, scored by mean absolute
    // deviation (Nigrini). Flags the population, not any single payment.
    public static IEnumerable<ControlException> Benford(
        IEnumerable<Payment> payments, ControlRuleOptions options)
    {
        var populations = payments
            .Where(p => p.Amount >= options.BenfordMinimumAmount)
            .GroupBy(p => (p.BusinessUnit, p.PaidOn.Year, p.PaidOn.Month))
            .OrderBy(g => g.Key);

        foreach (var population in populations)
        {
            var amounts = population.Select(p => p.Amount).ToList();
            if (amounts.Count < options.BenfordMinimumSample)
                continue;

            var mad = BenfordFirstDigitMad(amounts);
            if (mad <= options.BenfordNonconformityMad)
                continue;

            var (unit, year, month) = population.Key;
            var period = $"{year:D4}-{month:D2}";

            yield return new ControlException(
                RuleCodes.Benford,
                Severity.Medium,
                unit,
                "PaymentPopulation",
                $"{unit}:{period}",
                $"First digits of {amounts.Count} payments in {period} deviate from Benford's law " +
                $"(MAD {mad.ToString("0.0000", CultureInfo.InvariantCulture)} > " +
                $"{options.BenfordNonconformityMad.ToString("0.000", CultureInfo.InvariantCulture)}).",
                SubjectUser: null);
        }
    }

    public static double BenfordFirstDigitMad(IReadOnlyCollection<decimal> amounts)
    {
        var counts = new int[10];
        foreach (var amount in amounts)
            counts[FirstDigit(amount)]++;

        double total = amounts.Count;
        double sum = 0;
        for (var d = 1; d <= 9; d++)
            sum += Math.Abs(counts[d] / total - Math.Log10(1 + 1.0 / d));

        return sum / 9;
    }

    public static int FirstDigit(decimal amount)
    {
        amount = Math.Abs(amount);
        if (amount == 0)
            throw new ArgumentOutOfRangeException(nameof(amount), "Zero has no first digit.");

        while (amount >= 10) amount /= 10;
        while (amount < 1) amount *= 10;
        return (int)Math.Truncate(amount);
    }

    private static string NormalizeInvoice(string invoice) =>
        new string(invoice.Where(char.IsLetterOrDigit).ToArray()).ToUpperInvariant();

    private static string Money(decimal amount) => amount.ToString("$#,##0.00", CultureInfo.InvariantCulture);
}
