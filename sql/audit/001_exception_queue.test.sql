/*
    Tests for 001_exception_queue.sql. THROWAWAY DATABASE ONLY: rows in audit.Exception can't be
    deleted, so what this adds stays. Needs dbo.Expenses to exist (the Power App schema).
    Prints PASS/FAIL per case and raises an error if any case failed.
*/
SET NOCOUNT ON;

DECLARE @Fail INT = 0, @Err NVARCHAR(400), @Fp NVARCHAR(300) = CONCAT(N'TEST:Expense:', NEWID());
DECLARE @R TABLE (ExceptionId BIGINT, IsNew BIT);
DECLARE @Id BIGINT, @IsNew BIT;

-- 1. Raising a new exception adds it, open.
INSERT @R EXEC audit.sp_RaiseException @Fp, 'TEST', 'High', N'Clinic A', 'Expense', N'1', N'Test details', N'clerk@example.com';
SELECT @Id = ExceptionId, @IsNew = IsNew FROM @R; DELETE @R;
IF @IsNew = 1 AND EXISTS (SELECT 1 FROM audit.Exception WHERE ExceptionId = @Id AND Status = 'Open')
    PRINT 'PASS 1 raise new';
ELSE BEGIN PRINT 'FAIL 1 raise new'; SET @Fail += 1; END;

-- 2. Raising it again (a re-scan) returns the same row and adds nothing.
INSERT @R EXEC audit.sp_RaiseException @Fp, 'TEST', 'High', N'Clinic A', 'Expense', N'1', N'Test details', N'clerk@example.com';
IF (SELECT ExceptionId FROM @R) = @Id AND (SELECT IsNew FROM @R) = 0
   AND (SELECT COUNT(*) FROM audit.Exception WHERE Fingerprint = @Fp) = 1
    PRINT 'PASS 2 re-raise is a no-op';
ELSE BEGIN PRINT 'FAIL 2 re-raise is a no-op'; SET @Fail += 1; END;
DELETE @R;

-- 3. It shows in the open summary.
IF EXISTS (SELECT 1 FROM audit.vw_OpenExceptionSummary WHERE BusinessUnit = N'Clinic A' AND OpenHigh >= 1)
    PRINT 'PASS 3 open summary';
ELSE BEGIN PRINT 'FAIL 3 open summary'; SET @Fail += 1; END;

-- 4. Closing needs a resolution.
BEGIN TRY EXEC audit.sp_CloseException @Id, N'reviewer@example.com', N'  '; PRINT 'FAIL 4 close without resolution'; SET @Fail += 1; END TRY
BEGIN CATCH PRINT 'PASS 4 close without resolution: ' + ERROR_MESSAGE(); END CATCH;

-- 5. Nobody closes an exception on their own work.
BEGIN TRY EXEC audit.sp_CloseException @Id, N'clerk@example.com', N'Mine, fine'; PRINT 'FAIL 5 self-close'; SET @Fail += 1; END TRY
BEGIN CATCH PRINT 'PASS 5 self-close: ' + ERROR_MESSAGE(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;

-- 6. Unknown exception.
BEGIN TRY EXEC audit.sp_CloseException -1, N'reviewer@example.com', N'x'; PRINT 'FAIL 6 unknown exception'; SET @Fail += 1; END TRY
BEGIN CATCH PRINT 'PASS 6 unknown exception: ' + ERROR_MESSAGE(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;

-- 7. Someone else closes it with a resolution.
EXEC audit.sp_CloseException @Id, N'reviewer@example.com', N'Invoice checked; amount is right.';
IF EXISTS (SELECT 1 FROM audit.Exception WHERE ExceptionId = @Id AND Status = 'Closed' AND ClosedBy = N'reviewer@example.com' AND ClosedAt IS NOT NULL)
    PRINT 'PASS 7 close';
ELSE BEGIN PRINT 'FAIL 7 close'; SET @Fail += 1; END;

-- 8. Closing twice is refused.
BEGIN TRY EXEC audit.sp_CloseException @Id, N'reviewer@example.com', N'again'; PRINT 'FAIL 8 close twice'; SET @Fail += 1; END TRY
BEGIN CATCH PRINT 'PASS 8 close twice: ' + ERROR_MESSAGE(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;

-- 9. The open row is kept in history.
IF EXISTS (SELECT 1 FROM audit.ExceptionHistory WHERE ExceptionId = @Id AND Status = 'Open')
    PRINT 'PASS 9 history keeps the open row';
ELSE BEGIN PRINT 'FAIL 9 history keeps the open row'; SET @Fail += 1; END;

-- 10. Rows can't be deleted, even by dbo.
BEGIN TRY DELETE audit.Exception WHERE ExceptionId = @Id; PRINT 'FAIL 10 delete'; SET @Fail += 1; END TRY
BEGIN CATCH PRINT 'PASS 10 delete: ' + ERROR_MESSAGE(); END CATCH;

-- 11. The constraints hold even for a direct update.
BEGIN TRY UPDATE audit.Exception SET Resolution = NULL WHERE ExceptionId = @Id; PRINT 'FAIL 11 closed without resolution'; SET @Fail += 1; END TRY
BEGIN CATCH PRINT 'PASS 11 closed without resolution: ' + ERROR_MESSAGE(); END CATCH;

-- 12. The app role: reads dbo and the queue, raises through the procedure, nothing else.
IF DATABASE_PRINCIPAL_ID(N'smartledger_test_app') IS NULL CREATE USER smartledger_test_app WITHOUT LOGIN;
ALTER ROLE smartledger_app ADD MEMBER smartledger_test_app;
DECLARE @Fp2 NVARCHAR(300) = CONCAT(N'TEST:Expense:', NEWID());

EXECUTE AS USER = N'smartledger_test_app';
BEGIN TRY
    DECLARE @n INT = (SELECT COUNT(*) FROM dbo.Expenses) + (SELECT COUNT(*) FROM audit.Exception);
    INSERT @R EXEC audit.sp_RaiseException @Fp2, 'TEST', 'Low', N'Clinic B', 'Expense', N'2', N'Role test';
    PRINT 'PASS 12a role reads and raises';
END TRY
BEGIN CATCH PRINT 'FAIL 12a role reads and raises: ' + ERROR_MESSAGE(); SET @Fail += 1; END CATCH;
BEGIN TRY INSERT audit.Exception (Fingerprint, RuleCode, Severity, BusinessUnit, SourceType, SourceId, Details) VALUES (NEWID(), 'X', 'Low', N'x', 'x', N'x', N'x'); PRINT 'FAIL 12b role inserts directly'; SET @Fail += 1; END TRY
BEGIN CATCH PRINT 'PASS 12b role inserts directly: ' + ERROR_MESSAGE(); END CATCH;
BEGIN TRY EXEC audit.sp_CloseException @Id, N'app', N'x'; PRINT 'FAIL 12c role closes'; SET @Fail += 1; END TRY
BEGIN CATCH PRINT 'PASS 12c role closes: ' + ERROR_MESSAGE(); END CATCH;
BEGIN TRY UPDATE dbo.Expenses SET Vendor = Vendor WHERE 1 = 0; PRINT 'FAIL 12d role writes dbo'; SET @Fail += 1; END TRY
BEGIN CATCH PRINT 'PASS 12d role writes dbo: ' + ERROR_MESSAGE(); END CATCH;
REVERT;

ALTER ROLE smartledger_app DROP MEMBER smartledger_test_app;
DROP USER smartledger_test_app;

IF @@TRANCOUNT = 0 PRINT 'PASS 13 no open transaction';
ELSE BEGIN PRINT 'FAIL 13 open transaction'; SET @Fail += 1; ROLLBACK; END;

IF @Fail > 0
BEGIN
    SET @Err = CONCAT(@Fail, ' case(s) failed.');
    THROW 50099, @Err, 1;
END;
PRINT 'All cases passed.';
