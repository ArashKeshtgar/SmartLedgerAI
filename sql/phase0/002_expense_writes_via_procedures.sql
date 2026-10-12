/*
    Option A for the closed-period guard: the Power App writes dbo.Expenses only through procedures.

    Gate: STAGING ONLY (FinancePowerApp-staging). Not for production until the Power App copy on
    staging records, edits, approves and deletes through these procedures and the owner signs off.
    Undo: 002_expense_writes_via_procedures.rollback.sql puts the original trigger back.

    Why: trg_BlockChangesOnClosedPeriod is INSTEAD OF INSERT, UPDATE. The Power Apps SQL connector
    sends Patch as INSERT/UPDATE ... OUTPUT, which SQL Server refuses on a table with any enabled
    trigger (Msg 334), so every Patch fails. The trigger also checks only the new PeriodId, ignores
    DELETE, and copies a fixed column list.

    What this does:
      1. Procedures for every write the app makes; each checks the period the expense is in now
         AND the period it is moved to:
           sp_InsertExpense  (same five parameters as before; new optional ones at the end)
           sp_UpdateExpense, sp_ApproveExpense, sp_DeleteExpense
      2. Replaces the INSTEAD OF trigger with an AFTER INSERT, UPDATE, DELETE trigger: the second
         line of defence for anything that still writes to the table directly. No column list.
      3. (Commented out) takes direct write rights on dbo.Expenses away from the app's database user.

    Nothing else in dbo changes. Idempotent: safe to re-run.
*/

CREATE OR ALTER FUNCTION dbo.fn_IsPeriodClosed (@PeriodId INT)
RETURNS BIT
AS
BEGIN
    RETURN ISNULL((SELECT IsClosed FROM dbo.AccountingPeriods WHERE PeriodId = @PeriodId), 0);
END;
GO

CREATE OR ALTER PROCEDURE dbo.sp_InsertExpense
    @Amount      DECIMAL(12,2),
    @Category    VARCHAR(50),
    @ExpenseDate DATE,
    @Vendor      VARCHAR(100),
    @Description VARCHAR(255),
    @PeriodId    INT           = NULL,
    @CategoryId  INT           = NULL,
    @TaxAmount   DECIMAL(12,2) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF @Amount IS NULL OR @Amount <= 0
        THROW 50001, 'Amount must be greater than zero.', 1;
    IF dbo.fn_IsPeriodClosed(@PeriodId) = 1
        THROW 50002, 'Accounting period is closed. No changes allowed.', 1;

    INSERT INTO dbo.Expenses (Amount, Category, ExpenseDate, Vendor, Description, Status, PeriodId, CategoryId, TaxAmount)
    VALUES (@Amount, @Category, @ExpenseDate, @Vendor, @Description, 'Pending', @PeriodId, @CategoryId, @TaxAmount);

    SELECT CAST(SCOPE_IDENTITY() AS INT) AS ExpenseId;
END;
GO

CREATE OR ALTER PROCEDURE dbo.sp_UpdateExpense
    @ExpenseId   INT,
    @Amount      DECIMAL(12,2),
    @Category    VARCHAR(50),
    @ExpenseDate DATE,
    @Vendor      VARCHAR(100),
    @Description VARCHAR(255),
    @PeriodId    INT           = NULL,
    @CategoryId  INT           = NULL,
    @TaxAmount   DECIMAL(12,2) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF @Amount IS NULL OR @Amount <= 0
        THROW 50001, 'Amount must be greater than zero.', 1;

    BEGIN TRY
        BEGIN TRAN;
        DECLARE @OldPeriodId INT;
        SELECT @OldPeriodId = PeriodId FROM dbo.Expenses WITH (UPDLOCK, HOLDLOCK) WHERE ExpenseId = @ExpenseId;
        IF @@ROWCOUNT = 0
            THROW 50003, 'Expense not found.', 1;
        IF dbo.fn_IsPeriodClosed(@OldPeriodId) = 1 OR dbo.fn_IsPeriodClosed(@PeriodId) = 1
            THROW 50002, 'Accounting period is closed. No changes allowed.', 1;

        UPDATE dbo.Expenses
           SET Amount = @Amount, Category = @Category, ExpenseDate = @ExpenseDate, Vendor = @Vendor,
               Description = @Description, PeriodId = @PeriodId, CategoryId = @CategoryId, TaxAmount = @TaxAmount
         WHERE ExpenseId = @ExpenseId;
        COMMIT;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        THROW;
    END CATCH;
END;
GO

CREATE OR ALTER PROCEDURE dbo.sp_ApproveExpense
    @ExpenseId  INT,
    @ApprovedBy NVARCHAR(100)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF NULLIF(LTRIM(@ApprovedBy), N'') IS NULL
        THROW 50004, 'ApprovedBy is required.', 1;

    BEGIN TRY
        BEGIN TRAN;
        DECLARE @PeriodId INT, @Status VARCHAR(20);
        SELECT @PeriodId = PeriodId, @Status = Status FROM dbo.Expenses WITH (UPDLOCK, HOLDLOCK) WHERE ExpenseId = @ExpenseId;
        IF @@ROWCOUNT = 0
            THROW 50003, 'Expense not found.', 1;
        IF dbo.fn_IsPeriodClosed(@PeriodId) = 1
            THROW 50002, 'Accounting period is closed. No changes allowed.', 1;
        IF @Status = 'Approved'
            THROW 50005, 'Expense is already approved.', 1;

        UPDATE dbo.Expenses
           SET Status = 'Approved', ApprovedBy = @ApprovedBy, ApprovedDate = GETDATE()
         WHERE ExpenseId = @ExpenseId;
        COMMIT;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        THROW;
    END CATCH;
END;
GO

CREATE OR ALTER PROCEDURE dbo.sp_DeleteExpense
    @ExpenseId INT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        BEGIN TRAN;
        DECLARE @PeriodId INT;
        SELECT @PeriodId = PeriodId FROM dbo.Expenses WITH (UPDLOCK, HOLDLOCK) WHERE ExpenseId = @ExpenseId;
        IF @@ROWCOUNT = 0
            THROW 50003, 'Expense not found.', 1;
        IF dbo.fn_IsPeriodClosed(@PeriodId) = 1
            THROW 50002, 'Accounting period is closed. No changes allowed.', 1;

        DELETE FROM dbo.Expenses WHERE ExpenseId = @ExpenseId;
        COMMIT;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        THROW;
    END CATCH;
END;
GO

-- Second line of defence. AFTER, not INSTEAD OF: the row is written as sent, so a new column is
-- never dropped; both the old row (deleted) and the new one (inserted) are checked.
CREATE OR ALTER TRIGGER dbo.trg_BlockChangesOnClosedPeriod
ON dbo.Expenses
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;
    IF EXISTS (SELECT 1 FROM inserted i JOIN dbo.AccountingPeriods p ON p.PeriodId = i.PeriodId WHERE p.IsClosed = 1)
    OR EXISTS (SELECT 1 FROM deleted  d JOIN dbo.AccountingPeriods p ON p.PeriodId = d.PeriodId WHERE p.IsClosed = 1)
        THROW 50002, 'Accounting period is closed. No changes allowed.', 1;
END;
GO

/*
    3. Direct writes: once the app on staging works through the procedures, take table writes
       away from the database user its connection signs in as (replace [powerapp_user]).
       Has no effect if that user is db_owner or the server admin: it then needs its own user.

    GRANT EXECUTE ON dbo.sp_InsertExpense  TO [powerapp_user];
    GRANT EXECUTE ON dbo.sp_UpdateExpense  TO [powerapp_user];
    GRANT EXECUTE ON dbo.sp_ApproveExpense TO [powerapp_user];
    GRANT EXECUTE ON dbo.sp_DeleteExpense  TO [powerapp_user];
    DENY INSERT, UPDATE, DELETE ON dbo.Expenses TO [powerapp_user];
*/
