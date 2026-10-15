-- Test fixture: the Power App objects these SQL scripts touch, exactly as on Azure (phase 0 found the
-- tables, sp_InsertExpense and the trigger identical on both sides). Copied from FinancePowerApp
-- database/005_powerapp_baseline.sql. For tests/sql/run.sh only.

-- The original FinancePowerApp schema (expenses, categories, periods) used by the Power Apps canvas app.
-- On the existing database every object is already there and nothing here runs; on a new database this
-- recreates it exactly, so the ERP scripts that follow always start from the same place.
-- These objects are never changed by later scripts except by adding nullable columns.

IF OBJECT_ID(N'dbo.AccountingPeriods', N'U') IS NULL
CREATE TABLE dbo.AccountingPeriods (
    PeriodId   int IDENTITY(1,1) NOT NULL CONSTRAINT PK_AccountingPeriods PRIMARY KEY,
    [Year]     int NOT NULL,
    [Month]    int NOT NULL,
    IsClosed   bit NOT NULL CONSTRAINT DF_AccountingPeriods_IsClosed DEFAULT ((0)),
    ClosedDate datetime NULL
);
GO
IF OBJECT_ID(N'dbo.ExpenseCategories', N'U') IS NULL
CREATE TABLE dbo.ExpenseCategories (
    CategoryId    int IDENTITY(1,1) NOT NULL CONSTRAINT PK_ExpenseCategories PRIMARY KEY,
    CategoryName  nvarchar(50) NULL,
    TaxDeductible bit NULL
);
GO
IF OBJECT_ID(N'dbo.Expenses', N'U') IS NULL
CREATE TABLE dbo.Expenses (
    ExpenseId    int IDENTITY(1,1) NOT NULL CONSTRAINT PK_Expenses PRIMARY KEY,
    Amount       decimal(12,2) NOT NULL,
    Category     varchar(50) NULL,
    ExpenseDate  date NULL,
    Vendor       varchar(100) NULL,
    [Description] varchar(255) NULL,
    [Status]     varchar(20) NULL,
    CreatedAt    datetime NULL CONSTRAINT DF_Expenses_CreatedAt DEFAULT (getdate()),
    PeriodId     int NULL CONSTRAINT FK_Expenses_AccountingPeriods REFERENCES dbo.AccountingPeriods(PeriodId),
    ApprovedBy   nvarchar(100) NULL,
    ApprovedDate datetime NULL,
    CategoryId   int NULL CONSTRAINT FK_Expenses_Category REFERENCES dbo.ExpenseCategories(CategoryId),
    TaxAmount    decimal(12,2) NULL
);
GO
IF OBJECT_ID(N'dbo.sp_InsertExpense', N'P') IS NULL
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
-- The Power App's guard: expenses in a closed month can't be inserted or changed.
IF OBJECT_ID(N'dbo.trg_BlockChangesOnClosedPeriod', N'TR') IS NULL
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
