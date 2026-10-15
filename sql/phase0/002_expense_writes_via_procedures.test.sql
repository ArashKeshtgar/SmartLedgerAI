/*
    Tests for 002_expense_writes_via_procedures.sql. THROWAWAY DATABASE ONLY: it adds two periods
    (9999-01 closed, 9999-02 and 9999-03 open) and expenses in them, and removes what it can at the end.
    Prints PASS/FAIL per case and raises an error if any case failed.
*/
SET NOCOUNT ON;

DECLARE @Closed INT, @Open INT, @Fail INT = 0, @Id INT, @InClosed INT, @Err NVARCHAR(400);
DECLARE @New TABLE (ExpenseId INT);

INSERT dbo.AccountingPeriods ([Year], [Month], IsClosed) VALUES (9999, 1, 0);
SET @Closed = SCOPE_IDENTITY();
INSERT dbo.AccountingPeriods ([Year], [Month], IsClosed) VALUES (9999, 2, 0);
SET @Open = SCOPE_IDENTITY();

-- An expense that sits in the closed month: written while the month was open, then the month is closed.
INSERT @New EXEC dbo.sp_InsertExpense 50, 'Rent', '9999-01-15', 'Landlord', 'January', @Closed;
SELECT @InClosed = ExpenseId FROM @New; DELETE @New;
UPDATE dbo.AccountingPeriods SET IsClosed = 1 WHERE PeriodId = @Closed;

-- 1. Insert into an open month works and returns the id.
INSERT @New EXEC dbo.sp_InsertExpense 100, 'Supplies', '9999-02-03', 'Vendor', 'Gloves', @Open;
SELECT @Id = ExpenseId FROM @New;
IF EXISTS (SELECT 1 FROM dbo.Expenses WHERE ExpenseId = @Id AND Amount = 100 AND Status = 'Pending' AND PeriodId = @Open)
    PRINT 'PASS 1 insert into open month';
ELSE BEGIN PRINT 'FAIL 1 insert into open month'; SET @Fail += 1; END;

-- 2. Insert into a closed month is refused.
BEGIN TRY EXEC dbo.sp_InsertExpense 100, 'Supplies', '9999-01-03', 'Vendor', 'x', @Closed; PRINT 'FAIL 2 insert into closed month'; SET @Fail += 1; END TRY
BEGIN CATCH PRINT 'PASS 2 insert into closed month: ' + ERROR_MESSAGE(); END CATCH;

-- 3. Update in an open month works.
EXEC dbo.sp_UpdateExpense @Id, 120, 'Supplies', '9999-02-04', 'Vendor', 'Gloves (box)', @Open;
IF EXISTS (SELECT 1 FROM dbo.Expenses WHERE ExpenseId = @Id AND Amount = 120 AND Description = 'Gloves (box)')
    PRINT 'PASS 3 update in open month';
ELSE BEGIN PRINT 'FAIL 3 update in open month'; SET @Fail += 1; END;

-- 4. Moving an open-month expense into a closed month is refused.
BEGIN TRY EXEC dbo.sp_UpdateExpense @Id, 120, 'Supplies', '9999-01-04', 'Vendor', 'x', @Closed; PRINT 'FAIL 4 move into closed month'; SET @Fail += 1; END TRY
BEGIN CATCH PRINT 'PASS 4 move into closed month: ' + ERROR_MESSAGE(); END CATCH;

-- 5. Moving a closed-month expense out (to an open month or NULL) is refused. Hole in the old trigger.
BEGIN TRY EXEC dbo.sp_UpdateExpense @InClosed, 50, 'Rent', '9999-02-15', 'Landlord', 'moved', @Open; PRINT 'FAIL 5a move out of closed month'; SET @Fail += 1; END TRY
BEGIN CATCH PRINT 'PASS 5a move out of closed month: ' + ERROR_MESSAGE(); END CATCH;
BEGIN TRY EXEC dbo.sp_UpdateExpense @InClosed, 50, 'Rent', '9999-01-15', 'Landlord', 'moved', NULL; PRINT 'FAIL 5b clear period of closed-month expense'; SET @Fail += 1; END TRY
BEGIN CATCH PRINT 'PASS 5b clear period of closed-month expense: ' + ERROR_MESSAGE(); END CATCH;

-- 6. Approve in an open month works; approving twice is refused.
EXEC dbo.sp_ApproveExpense @Id, N'approver@example.com';
IF EXISTS (SELECT 1 FROM dbo.Expenses WHERE ExpenseId = @Id AND Status = 'Approved' AND ApprovedBy = N'approver@example.com' AND ApprovedDate IS NOT NULL)
    PRINT 'PASS 6a approve';
ELSE BEGIN PRINT 'FAIL 6a approve'; SET @Fail += 1; END;
BEGIN TRY EXEC dbo.sp_ApproveExpense @Id, N'approver@example.com'; PRINT 'FAIL 6b approve twice'; SET @Fail += 1; END TRY
BEGIN CATCH PRINT 'PASS 6b approve twice: ' + ERROR_MESSAGE(); END CATCH;

-- 7. Approve in a closed month is refused.
BEGIN TRY EXEC dbo.sp_ApproveExpense @InClosed, N'approver@example.com'; PRINT 'FAIL 7 approve in closed month'; SET @Fail += 1; END TRY
BEGIN CATCH PRINT 'PASS 7 approve in closed month: ' + ERROR_MESSAGE(); END CATCH;

-- 8. Delete in a closed month is refused. Hole in the old trigger.
BEGIN TRY EXEC dbo.sp_DeleteExpense @InClosed; PRINT 'FAIL 8 delete in closed month'; SET @Fail += 1; END TRY
BEGIN CATCH PRINT 'PASS 8 delete in closed month: ' + ERROR_MESSAGE(); END CATCH;

-- 9. The trigger alone stops direct writes that skip the procedures.
BEGIN TRY DELETE dbo.Expenses WHERE ExpenseId = @InClosed; PRINT 'FAIL 9a direct delete in closed month'; SET @Fail += 1; END TRY
BEGIN CATCH PRINT 'PASS 9a direct delete in closed month: ' + ERROR_MESSAGE(); END CATCH;
BEGIN TRY UPDATE dbo.Expenses SET PeriodId = @Open WHERE ExpenseId = @InClosed; PRINT 'FAIL 9b direct move out of closed month'; SET @Fail += 1; END TRY
BEGIN CATCH PRINT 'PASS 9b direct move out of closed month: ' + ERROR_MESSAGE(); END CATCH;
BEGIN TRY INSERT dbo.Expenses (Amount, Category, Status, PeriodId) VALUES (1, 'x', 'Pending', @Closed); PRINT 'FAIL 9c direct insert into closed month'; SET @Fail += 1; END TRY
BEGIN CATCH PRINT 'PASS 9c direct insert into closed month: ' + ERROR_MESSAGE(); END CATCH;

-- 10. Bad input is refused.
BEGIN TRY EXEC dbo.sp_InsertExpense 0, 'x', '9999-02-01', 'v', 'd', @Open; PRINT 'FAIL 10a zero amount'; SET @Fail += 1; END TRY
BEGIN CATCH PRINT 'PASS 10a zero amount: ' + ERROR_MESSAGE(); END CATCH;
BEGIN TRY EXEC dbo.sp_UpdateExpense -1, 1, 'x', '9999-02-01', 'v', 'd', @Open; PRINT 'FAIL 10b unknown expense'; SET @Fail += 1; END TRY
BEGIN CATCH PRINT 'PASS 10b unknown expense: ' + ERROR_MESSAGE(); END CATCH;

-- 11. Reject: works on a pending expense; refused twice, on an approved one, and in a closed month.
DECLARE @Rej INT;
INSERT @New EXEC dbo.sp_InsertExpense 30, 'Meals', '9999-02-05', 'Cafe', 'Lunch', @Open;
SELECT @Rej = ExpenseId FROM @New WHERE ExpenseId <> @Id; DELETE @New;
EXEC dbo.sp_RejectExpense @Rej, N'reviewer@example.com';
IF EXISTS (SELECT 1 FROM dbo.Expenses WHERE ExpenseId = @Rej AND Status = 'Rejected' AND ApprovedBy = N'reviewer@example.com' AND ApprovedDate IS NOT NULL)
    PRINT 'PASS 11a reject pending';
ELSE BEGIN PRINT 'FAIL 11a reject pending'; SET @Fail += 1; END;
BEGIN TRY EXEC dbo.sp_RejectExpense @Rej, N'reviewer@example.com'; PRINT 'FAIL 11b reject twice'; SET @Fail += 1; END TRY
BEGIN CATCH PRINT 'PASS 11b reject twice: ' + ERROR_MESSAGE(); END CATCH;
BEGIN TRY EXEC dbo.sp_RejectExpense @Id, N'reviewer@example.com'; PRINT 'FAIL 11c reject approved'; SET @Fail += 1; END TRY
BEGIN CATCH PRINT 'PASS 11c reject approved: ' + ERROR_MESSAGE(); END CATCH;
BEGIN TRY EXEC dbo.sp_RejectExpense @InClosed, N'reviewer@example.com'; PRINT 'FAIL 11d reject in closed month'; SET @Fail += 1; END TRY
BEGIN CATCH PRINT 'PASS 11d reject in closed month: ' + ERROR_MESSAGE(); END CATCH;

-- 12. Assign period, as the app does: a new expense has none; it can be given an open month and moved
--     between open months, never into or out of a closed one.
DECLARE @Asg INT, @Open2 INT;
INSERT dbo.AccountingPeriods ([Year], [Month], IsClosed) VALUES (9999, 3, 0);
SET @Open2 = SCOPE_IDENTITY();
INSERT @New EXEC dbo.sp_InsertExpense 40, 'Fuel', '9999-02-06', 'Station', 'Fill-up';
SELECT @Asg = ExpenseId FROM @New; DELETE @New;
EXEC dbo.sp_AssignExpensePeriod @Asg, @Open;
EXEC dbo.sp_AssignExpensePeriod @Asg, @Open2;
IF EXISTS (SELECT 1 FROM dbo.Expenses WHERE ExpenseId = @Asg AND PeriodId = @Open2 AND Amount = 40 AND Status = 'Pending')
    PRINT 'PASS 12a assign and move between open months';
ELSE BEGIN PRINT 'FAIL 12a assign and move between open months'; SET @Fail += 1; END;
BEGIN TRY EXEC dbo.sp_AssignExpensePeriod @Asg, @Closed; PRINT 'FAIL 12b assign into closed month'; SET @Fail += 1; END TRY
BEGIN CATCH PRINT 'PASS 12b assign into closed month: ' + ERROR_MESSAGE(); END CATCH;
BEGIN TRY EXEC dbo.sp_AssignExpensePeriod @InClosed, @Open; PRINT 'FAIL 12c assign out of closed month'; SET @Fail += 1; END TRY
BEGIN CATCH PRINT 'PASS 12c assign out of closed month: ' + ERROR_MESSAGE(); END CATCH;
BEGIN TRY EXEC dbo.sp_AssignExpensePeriod @Asg, -1; PRINT 'FAIL 12d unknown period'; SET @Fail += 1; END TRY
BEGIN CATCH PRINT 'PASS 12d unknown period: ' + ERROR_MESSAGE(); END CATCH;

-- 13. Delete in an open month works.
EXEC dbo.sp_DeleteExpense @Id;
IF NOT EXISTS (SELECT 1 FROM dbo.Expenses WHERE ExpenseId = @Id)
    PRINT 'PASS 13 delete in open month';
ELSE BEGIN PRINT 'FAIL 13 delete in open month'; SET @Fail += 1; END;

-- 14. No transaction left open by any failure above.
IF @@TRANCOUNT = 0 PRINT 'PASS 14 no open transaction';
ELSE BEGIN PRINT 'FAIL 14 open transaction'; SET @Fail += 1; ROLLBACK; END;

-- Clean up: reopen the month so its expense can go, then remove the test periods.
UPDATE dbo.AccountingPeriods SET IsClosed = 0 WHERE PeriodId = @Closed;
DELETE dbo.Expenses WHERE PeriodId IN (@Closed, @Open, @Open2) OR ExpenseId = @Asg;
DELETE dbo.AccountingPeriods WHERE PeriodId IN (@Closed, @Open, @Open2);

IF @Fail > 0
BEGIN
    SET @Err = CONCAT(@Fail, ' case(s) failed.');
    THROW 50099, @Err, 1;
END;
PRINT 'All cases passed.';
