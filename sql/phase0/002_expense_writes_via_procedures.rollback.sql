/*
    Undo for 002_expense_writes_via_procedures.sql: puts back the original trigger and
    sp_InsertExpense exactly as on Azure (from FinancePowerApp database/005_powerapp_baseline.sql),
    and drops the procedures and function it added. Staging only, like the script it undoes.
    sp_InsertExpense is dropped and recreated so its text matches Azure exactly: re-grant EXECUTE
    on it afterwards if a user had it.
*/

DROP PROCEDURE IF EXISTS dbo.sp_AssignExpensePeriod, dbo.sp_UpdateExpense, dbo.sp_ApproveExpense, dbo.sp_RejectExpense, dbo.sp_DeleteExpense;
GO

DROP PROCEDURE IF EXISTS dbo.sp_InsertExpense;
GO
EXEC(N'CREATE PROCEDURE sp_InsertExpense
    @Amount DECIMAL(12,2),
    @Category VARCHAR(50),
    @ExpenseDate DATE,
    @Vendor VARCHAR(100),
    @Description VARCHAR(255)
AS
BEGIN
    SET NOCOUNT ON;
    IF @Amount <= 0
    BEGIN
        RAISERROR (''Amount must be greater than zero'', 16, 1);
        RETURN;
    END
    BEGIN TRY
        BEGIN TRAN;
        INSERT INTO Expenses (Amount, Category, ExpenseDate, Vendor, Description, Status)
        VALUES (@Amount, @Category, @ExpenseDate, @Vendor, @Description, ''Pending'');
        COMMIT TRAN;
    END TRY
    BEGIN CATCH
        ROLLBACK TRAN;
        THROW;
    END CATCH
END;');
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

DROP FUNCTION IF EXISTS dbo.fn_IsPeriodClosed;
GO
