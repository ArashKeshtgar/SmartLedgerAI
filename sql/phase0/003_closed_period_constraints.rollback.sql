/*
    Undo for 003_closed_period_constraints.sql: drops the two constraints and the function it added,
    and puts back the original trigger exactly as on Azure (from FinancePowerApp
    database/005_powerapp_baseline.sql). Staging only, like the script it undoes.
*/

ALTER TABLE dbo.Expenses DROP CONSTRAINT IF EXISTS CK_Expenses_PeriodOpen, CK_Expenses_DecisionHasApprover;
GO

DROP FUNCTION IF EXISTS dbo.fn_ExpenseRowWritable;
GO

-- Shared with 002: dropped only if nothing else uses it.
IF OBJECT_ID(N'dbo.fn_IsPeriodClosed', N'FN') IS NOT NULL
   AND NOT EXISTS (SELECT 1 FROM sys.sql_expression_dependencies WHERE referenced_id = OBJECT_ID(N'dbo.fn_IsPeriodClosed'))
    DROP FUNCTION dbo.fn_IsPeriodClosed;
GO

DROP TRIGGER IF EXISTS dbo.trg_BlockChangesOnClosedPeriod;
GO
EXEC(N'CREATE TRIGGER [dbo].[trg_BlockChangesOnClosedPeriod]
ON [dbo].[Expenses]
INSTEAD OF INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    IF EXISTS (SELECT 1 FROM inserted i JOIN AccountingPeriods p ON i.PeriodId = p.PeriodId WHERE p.IsClosed = 1)
    BEGIN
        RAISERROR (''Accounting period is closed. No changes allowed.'', 16, 1);
        RETURN;
    END
    IF NOT EXISTS (SELECT 1 FROM deleted)
    BEGIN
        INSERT INTO Expenses (Amount, Category, ExpenseDate, Vendor, Description, Status, PeriodId, ApprovedBy, ApprovedDate, CategoryId, TaxAmount)
        SELECT Amount, Category, ExpenseDate, Vendor, Description, Status, PeriodId, ApprovedBy, ApprovedDate, CategoryId, TaxAmount FROM inserted;
    END
    ELSE
    BEGIN
        UPDATE e SET e.Amount = i.Amount, e.Category = i.Category, e.ExpenseDate = i.ExpenseDate, e.Vendor = i.Vendor,
            e.Description = i.Description, e.Status = i.Status, e.PeriodId = i.PeriodId, e.ApprovedBy = i.ApprovedBy,
            e.ApprovedDate = i.ApprovedDate, e.CategoryId = i.CategoryId, e.TaxAmount = i.TaxAmount
        FROM Expenses e JOIN inserted i ON e.ExpenseId = i.ExpenseId;
    END
END;');
GO
