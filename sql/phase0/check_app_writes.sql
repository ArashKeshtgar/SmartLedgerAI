/*
    Read only. Does the Power App still record and approve expenses on this database?

    The closed-period trigger blocks every Patch from Power Apps (Msg 334). If expenses were
    created or approved AFTER the trigger was created or last changed, something wrote to the table
    after it was in place: most likely the app (through sp_InsertExpense, or a path we haven't seen).
    If nothing was created since, and the app has been in use, the app is not saving.

    Run it on production in the Azure Portal Query editor; it changes nothing.
*/
SET NOCOUNT ON;

DECLARE @TriggerSince DATETIME =
    (SELECT modify_date FROM sys.triggers WHERE name = N'trg_BlockChangesOnClosedPeriod');

SELECT
    @TriggerSince                                                         AS TriggerInPlaceSince,
    (SELECT MAX(CreatedAt)    FROM dbo.Expenses)                          AS LastCreated,
    (SELECT MAX(ApprovedDate) FROM dbo.Expenses)                          AS LastApproved,
    (SELECT COUNT(*) FROM dbo.Expenses WHERE CreatedAt    > @TriggerSince) AS CreatedSinceTrigger,
    (SELECT COUNT(*) FROM dbo.Expenses WHERE ApprovedDate > @TriggerSince) AS ApprovedSinceTrigger;

-- The most recent ten, to see what they look like (no amounts or vendors).
SELECT TOP (10) ExpenseId, CreatedAt, Status, ApprovedDate, PeriodId
FROM dbo.Expenses
ORDER BY ExpenseId DESC;

-- Which values Status takes today (tells us if 'Rejected' is already in use, and its spelling).
SELECT Status, COUNT(*) AS Expenses FROM dbo.Expenses GROUP BY Status ORDER BY Status;
