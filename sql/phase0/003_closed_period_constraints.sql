/*
    Option B+ for the closed-period guard: constraints instead of the trigger, so the Power App's own
    Patch/UpdateIf formulas work unchanged. An alternative to 002 (procedures); use one or the other.

    Gate: STAGING ONLY (FinancePowerApp-staging) until the Power App copy on staging records,
    assigns, approves and rejects with its current formulas, and the owner signs off.
    Undo: 003_closed_period_constraints.rollback.sql puts the original trigger back.

    Why: Power Apps sends Patch/UpdateIf as INSERT/UPDATE ... OUTPUT, which SQL Server refuses on a
    table with any enabled trigger (Msg 334). A CHECK constraint doesn't have that limit.

    What this does:
      1. Drops trg_BlockChangesOnClosedPeriod.
      2. CK_Expenses_PeriodOpen: no row can be inserted or changed while its PeriodId is a closed
         month. The function takes every column because SQL Server skips a CHECK when an UPDATE sets
         none of the columns it names: with PeriodId alone, approving in a closed month would pass.
      3. CK_Expenses_DecisionHasApprover: an Approved or Rejected expense names who decided and when,
         so the Submit button can't enter an expense as already Approved.
      Both are added WITH NOCHECK: rows already in closed months, or approved before, stay as they are.

    What it does NOT close (option A, procedures, does):
      - moving an expense OUT of a closed month (AssignPeriod to an open month): a CHECK sees only
        the new value;
      - deleting: the app has no delete; take DELETE away from the app's user (step 4).

    Nothing else in dbo changes. Idempotent: safe to re-run.
*/

DROP TRIGGER IF EXISTS dbo.trg_BlockChangesOnClosedPeriod;
GO

CREATE OR ALTER FUNCTION dbo.fn_IsPeriodClosed (@PeriodId INT)
RETURNS BIT
AS
BEGIN
    RETURN ISNULL((SELECT IsClosed FROM dbo.AccountingPeriods WHERE PeriodId = @PeriodId), 0);
END;
GO

-- Only @PeriodId decides; the other parameters are there so the constraint names every column.
IF OBJECT_ID(N'dbo.fn_ExpenseRowWritable', N'FN') IS NULL
EXEC(N'CREATE FUNCTION dbo.fn_ExpenseRowWritable (
    @PeriodId INT, @Amount DECIMAL(12,2), @Category VARCHAR(50), @ExpenseDate DATE, @Vendor VARCHAR(100),
    @Description VARCHAR(255), @Status VARCHAR(20), @ApprovedBy NVARCHAR(100), @ApprovedDate DATETIME,
    @CategoryId INT, @TaxAmount DECIMAL(12,2))
RETURNS BIT
AS
BEGIN
    RETURN CASE WHEN dbo.fn_IsPeriodClosed(@PeriodId) = 1 THEN 0 ELSE 1 END;
END;');
GO

IF OBJECT_ID(N'dbo.CK_Expenses_PeriodOpen', N'C') IS NULL
    ALTER TABLE dbo.Expenses WITH NOCHECK ADD CONSTRAINT CK_Expenses_PeriodOpen CHECK (
        dbo.fn_ExpenseRowWritable(PeriodId, Amount, Category, ExpenseDate, Vendor, Description, Status,
                                  ApprovedBy, ApprovedDate, CategoryId, TaxAmount) = 1);
GO

IF OBJECT_ID(N'dbo.CK_Expenses_DecisionHasApprover', N'C') IS NULL
    ALTER TABLE dbo.Expenses WITH NOCHECK ADD CONSTRAINT CK_Expenses_DecisionHasApprover CHECK (
        Status IS NULL OR Status NOT IN ('Approved', 'Rejected')
        OR (ApprovedBy IS NOT NULL AND LEN(LTRIM(ApprovedBy)) > 0 AND ApprovedDate IS NOT NULL));
GO

/*
    4. Deletes: take them away from the database user the app's connection signs in as (replace
       [powerapp_user]). Has no effect if that user is db_owner or the server admin.

    DENY DELETE ON dbo.Expenses TO [powerapp_user];
*/
