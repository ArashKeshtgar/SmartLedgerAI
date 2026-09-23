using SmartLedgerAI.Functions;
using Xunit;

namespace SmartLedgerAI.Functions.Tests;

public class ExpenseRequestValidatorTests
{
    [Fact]
    public void IsValid_ReturnsFalse_WhenRequestIsNull()
    {
        Assert.False(ExpenseRequestValidator.IsValid(null));
    }

    [Theory]
    [InlineData(0)]
    [InlineData(-1)]
    [InlineData(-100)]
    public void IsValid_ReturnsFalse_WhenExpenseIdIsNotPositive(int expenseId)
    {
        var request = new ExpenseIdRequest(expenseId);

        Assert.False(ExpenseRequestValidator.IsValid(request));
    }

    [Theory]
    [InlineData(1)]
    [InlineData(101)]
    [InlineData(int.MaxValue)]
    public void IsValid_ReturnsTrue_WhenExpenseIdIsPositive(int expenseId)
    {
        var request = new ExpenseIdRequest(expenseId);

        Assert.True(ExpenseRequestValidator.IsValid(request));
    }
}

public class PromptBuilderTests
{
    [Fact]
    public void BuildAnomalyExplanationPrompt_IncludesAllStatFields()
    {
        var stats = new ExpenseStatsRow(
            ExpenseId: 42,
            Category: "Travel",
            Amount: 1234.56m,
            ZScore: 3.2m,
            RiskLevel: "High"
        );

        var prompt = PromptBuilder.BuildAnomalyExplanationPrompt(stats, "High");

        Assert.Contains("Travel", prompt);
        Assert.Contains("1234.56", prompt);
        Assert.Contains("3.2", prompt);
        Assert.Contains("High", prompt);
    }

    [Fact]
    public void BuildAnomalyExplanationPrompt_UsesThePassedRiskLevel_NotTheStatsRiskLevel()
    {
        // The Function calls this with a risk value it already computed from the view,
        // not stats.RiskLevel directly — this test pins that contract so a future
        // refactor can't silently swap the two.
        var stats = new ExpenseStatsRow(1, "Office Supplies", 50m, 0.1m, RiskLevel: "Low");

        var prompt = PromptBuilder.BuildAnomalyExplanationPrompt(stats, "Medium");

        Assert.Contains("Risk: Medium", prompt);
        Assert.DoesNotContain("Risk: Low", prompt);
    }
}
