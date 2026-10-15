/*
    Tests for 003_closed_period_constraints.sql. THROWAWAY DATABASE ONLY: it adds two periods and
    expenses in them, and removes them at the end.
    Writes the way Power Apps does (INSERT/UPDATE ... OUTPUT), which is what the old trigger broke.
    Prints PASS/FAIL per case, KNOWN for the gaps this option leaves, and raises an error on any FAIL.
*/
SET NOCOUNT ON;

DECLARE @Closed INT, @Open INT, @Open2 INT, @Fail INT = 0, @Id INT, @InClosed INT, @Err NVARCHAR(400);
DECLARE @Out TABLE (ExpenseId INT);

INSERT dbo.AccountingPeriods ([Year], [Month], IsClosed) VALUES (9999, 1, 0);
SET @Closed = SCOPE_IDENTITY();
INSERT dbo.AccountingPeriods ([Year], [Month], IsClosed) VALUES (9999, 2, 0);
SET @Open = SCOPE_IDENTITY();
INSERT dbo.AccountingPeriods ([Year], [Month], IsClosed) VALUES (9999, 3, 0);
SET @Open2 = SCOPE_IDENTITY();

-- An expense in January, then January is closed (as the Close Month button does).
INSERT dbo.Expenses (Amount, Category, ExpenseDate, Vendor, Description, Status, PeriodId)
OUTPUT inserted.ExpenseId INTO @Out VALUES (50, 'Rent', '9999-01-15', 'Landlord', 'January', 'Pending', @Closed);
SELECT @InClosed = ExpenseId FROM @Out; DELETE @Out;
BEGIN TRY
    UPDATE dbo.AccountingPeriods SET IsClosed = 1, ClosedDate = GETDATE() OUTPUT inserted.PeriodId WHERE PeriodId = @Closed;
    PRINT 'PASS 1 close a month that has expenses';
END TRY
BEGIN CATCH PRINT 'FAIL 1 close a month that has expenses: ' + ERROR_MESSAGE(); SET @Fail += 1; END CATCH;

-- 2. Submit expense: Patch with no period, OUTPUT straight to the client.
BEGIN TRY
    INSERT dbo.Expenses (Amount, Category, ExpenseDate, Vendor, Description, Status, TaxAmount)
    OUTPUT inserted.ExpenseId, inserted.Amount
    VALUES (100, 'Supplies', '9999-02-03', 'Vendor', 'Gloves', 'Pending', 13);
    SET @Id = SCOPE_IDENTITY();
    PRINT 'PASS 2 submit (Patch with OUTPUT)';
END TRY
BEGIN CATCH PRINT 'FAIL 2 submit (Patch with OUTPUT): ' + ERROR_MESSAGE(); SET @Fail += 1; END CATCH;

-- 3. AssignPeriod to an open month, then to another open month.
BEGIN TRY
    UPDATE dbo.Expenses SET PeriodId = @Open  OUTPUT inserted.ExpenseId WHERE ExpenseId = @Id;
    UPDATE dbo.Expenses SET PeriodId = @Open2 OUTPUT inserted.ExpenseId WHERE ExpenseId = @Id;
    PRINT 'PASS 3 assign open months (UpdateIf with OUTPUT)';
END TRY
BEGIN CATCH PRINT 'FAIL 3 assign open months: ' + ERROR_MESSAGE(); SET @Fail += 1; END CATCH;

-- 4. Approve in an open month.
BEGIN TRY
    UPDATE dbo.Expenses SET Status = 'Approved', ApprovedBy = N'Approver', ApprovedDate = GETDATE()
    OUTPUT inserted.ExpenseId WHERE ExpenseId = @Id;
    PRINT 'PASS 4 approve in open month';
END TRY
BEGIN CATCH PRINT 'FAIL 4 approve in open month: ' + ERROR_MESSAGE(); SET @Fail += 1; END CATCH;

-- 5. Insert straight into a closed month.
BEGIN TRY
    INSERT dbo.Expenses (Amount, Category, Status, PeriodId) OUTPUT inserted.ExpenseId VALUES (1, 'x', 'Pending', @Closed);
    PRINT 'FAIL 5 insert into closed month'; SET @Fail += 1;
END TRY
BEGIN CATCH PRINT 'PASS 5 insert into closed month: ' + ERROR_MESSAGE(); END CATCH;

-- 6. Assign an open-month expense into a closed month.
BEGIN TRY
    UPDATE dbo.Expenses SET PeriodId = @Closed OUTPUT inserted.ExpenseId WHERE ExpenseId = @Id;
    PRINT 'FAIL 6 assign into closed month'; SET @Fail += 1;
END TRY
BEGIN CATCH PRINT 'PASS 6 assign into closed month: ' + ERROR_MESSAGE(); END CATCH;

-- 7. Approve in a closed month (the update doesn't touch PeriodId).
BEGIN TRY
    UPDATE dbo.Expenses SET Status = 'Approved', ApprovedBy = N'Approver', ApprovedDate = GETDATE()
    OUTPUT inserted.ExpenseId WHERE ExpenseId = @InClosed;
    PRINT 'FAIL 7 approve in closed month'; SET @Fail += 1;
END TRY
BEGIN CATCH PRINT 'PASS 7 approve in closed month: ' + ERROR_MESSAGE(); END CATCH;

-- 8. Reject in a closed month.
BEGIN TRY
    UPDATE dbo.Expenses SET Status = 'Rejected', ApprovedBy = N'Approver', ApprovedDate = GETDATE()
    OUTPUT inserted.ExpenseId WHERE ExpenseId = @InClosed;
    PRINT 'FAIL 8 reject in closed month'; SET @Fail += 1;
END TRY
BEGIN CATCH PRINT 'PASS 8 reject in closed month: ' + ERROR_MESSAGE(); END CATCH;

-- 9. Change the amount of a closed-month expense.
BEGIN TRY
    UPDATE dbo.Expenses SET Amount = 1 OUTPUT inserted.ExpenseId WHERE ExpenseId = @InClosed;
    PRINT 'FAIL 9 edit in closed month'; SET @Fail += 1;
END TRY
BEGIN CATCH PRINT 'PASS 9 edit in closed month: ' + ERROR_MESSAGE(); END CATCH;

-- 10. Submit as Approved straight away (the Status dropdown), with no approver.
BEGIN TRY
    INSERT dbo.Expenses (Amount, Category, Status) OUTPUT inserted.ExpenseId VALUES (1, 'x', 'Approved');
    PRINT 'FAIL 10 submit as Approved without approver'; SET @Fail += 1;
END TRY
BEGIN CATCH PRINT 'PASS 10 submit as Approved without approver: ' + ERROR_MESSAGE(); END CATCH;

-- 11. Gaps this option leaves (option A closes them). Reported, not failed.
BEGIN TRY
    UPDATE dbo.Expenses SET PeriodId = @Open OUTPUT inserted.ExpenseId WHERE ExpenseId = @InClosed;
    PRINT 'KNOWN 11a moving an expense out of a closed month is not blocked';
END TRY
BEGIN CATCH PRINT 'PASS 11a move out of closed month blocked: ' + ERROR_MESSAGE(); END CATCH;
PRINT 'KNOWN 11b deleting is not blocked by the database; DENY DELETE to the app user';

IF @@TRANCOUNT = 0 PRINT 'PASS 12 no open transaction';
ELSE BEGIN PRINT 'FAIL 12 open transaction'; SET @Fail += 1; ROLLBACK; END;

-- Clean up: reopen the months so their expenses can go, then remove the test periods.
UPDATE dbo.AccountingPeriods SET IsClosed = 0 WHERE PeriodId IN (@Closed, @Open, @Open2);
DELETE dbo.Expenses WHERE PeriodId IN (@Closed, @Open, @Open2) OR ExpenseId = @Id
    OR (PeriodId IS NULL AND ExpenseDate IS NULL AND Category = 'x');
DELETE dbo.AccountingPeriods WHERE PeriodId IN (@Closed, @Open, @Open2);

IF @Fail > 0
BEGIN
    SET @Err = CONCAT(@Fail, ' case(s) failed.');
    THROW 50099, @Err, 1;
END;
PRINT 'All cases passed.';
