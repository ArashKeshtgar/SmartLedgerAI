/*
    SmartLedgerAI review queue: schema `audit`.

    Gate: NOT to be run on the Azure production database. Run it on staging first
    (phase 0/3 of the finance plan), confirm the Power App still works there, and
    only then promote with the owner's sign-off.

    It touches nothing in `dbo`: SmartLedgerAI only reads the ledger and only ever
    writes into this queue, and only through the two procedures below.
    Idempotent: safe to re-run.
*/

IF SCHEMA_ID(N'audit') IS NULL
    EXEC(N'CREATE SCHEMA audit AUTHORIZATION dbo;');
GO

IF OBJECT_ID(N'audit.Exception', N'U') IS NULL
BEGIN
    CREATE TABLE audit.Exception
    (
        ExceptionId   BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT PK_audit_Exception PRIMARY KEY,
        Fingerprint   NVARCHAR(300)  NOT NULL,                 -- RuleCode:SourceType:SourceId
        RuleCode      VARCHAR(50)    NOT NULL,
        Severity      VARCHAR(10)    NOT NULL CONSTRAINT CK_audit_Exception_Severity CHECK (Severity IN ('Low', 'Medium', 'High')),
        BusinessUnit  NVARCHAR(100)  NOT NULL,
        SourceType    VARCHAR(50)    NOT NULL,
        SourceId      NVARCHAR(200)  NOT NULL,
        Details       NVARCHAR(2000) NOT NULL,
        SubjectUser   NVARCHAR(256)  NULL,                     -- whose work triggered it; may not close it
        Explanation   NVARCHAR(2000) NULL,                     -- optional language-model summary, never the verdict
        DetectedAt    DATETIMEOFFSET(0) NOT NULL CONSTRAINT DF_audit_Exception_DetectedAt DEFAULT SYSDATETIMEOFFSET(),
        Status        VARCHAR(10)    NOT NULL CONSTRAINT DF_audit_Exception_Status DEFAULT 'Open'
                                     CONSTRAINT CK_audit_Exception_Status CHECK (Status IN ('Open', 'Closed')),
        ClosedBy      NVARCHAR(256)  NULL,
        ClosedAt      DATETIMEOFFSET(0) NULL,
        Resolution    NVARCHAR(2000) NULL,
        ValidFrom     DATETIME2(0) GENERATED ALWAYS AS ROW START HIDDEN NOT NULL,
        ValidTo       DATETIME2(0) GENERATED ALWAYS AS ROW END   HIDDEN NOT NULL,
        PERIOD FOR SYSTEM_TIME (ValidFrom, ValidTo),

        CONSTRAINT UQ_audit_Exception_Fingerprint UNIQUE (Fingerprint),
        -- A closed exception always says who closed it, when, and why. (IS NOT NULL: a CHECK lets UNKNOWN through.)
        CONSTRAINT CK_audit_Exception_Closure CHECK (
            (Status = 'Open'   AND ClosedBy IS NULL     AND ClosedAt IS NULL     AND Resolution IS NULL) OR
            (Status = 'Closed' AND ClosedBy IS NOT NULL AND ClosedAt IS NOT NULL AND Resolution IS NOT NULL AND LEN(LTRIM(RTRIM(Resolution))) > 0)
        ),
        -- Nobody closes an exception raised on their own work.
        CONSTRAINT CK_audit_Exception_NotSelfClosed CHECK (ClosedBy IS NULL OR SubjectUser IS NULL OR ClosedBy <> SubjectUser)
    )
    WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = audit.ExceptionHistory));

    CREATE INDEX IX_audit_Exception_Open
        ON audit.Exception (BusinessUnit, Severity)
        INCLUDE (RuleCode, DetectedAt)
        WHERE Status = 'Open';
END
GO

-- Exceptions are closed, never deleted, even by an administrator.
CREATE OR ALTER TRIGGER audit.trg_Exception_NoDelete
ON audit.Exception
AFTER DELETE
AS
BEGIN
    SET NOCOUNT ON;
    IF EXISTS (SELECT 1 FROM deleted)
        THROW 51000, 'audit.Exception rows cannot be deleted; close them with audit.sp_CloseException.', 1;
END
GO

-- Insert-if-new: a re-scan of the same data leaves the queue unchanged.
CREATE OR ALTER PROCEDURE audit.sp_RaiseException
    @Fingerprint  NVARCHAR(300),
    @RuleCode     VARCHAR(50),
    @Severity     VARCHAR(10),
    @BusinessUnit NVARCHAR(100),
    @SourceType   VARCHAR(50),
    @SourceId     NVARCHAR(200),
    @Details      NVARCHAR(2000),
    @SubjectUser  NVARCHAR(256) = NULL,
    @Explanation  NVARCHAR(2000) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    INSERT INTO audit.Exception
        (Fingerprint, RuleCode, Severity, BusinessUnit, SourceType, SourceId, Details, SubjectUser, Explanation)
    SELECT
        @Fingerprint, @RuleCode, @Severity, @BusinessUnit, @SourceType, @SourceId, @Details, @SubjectUser, @Explanation
    WHERE NOT EXISTS (SELECT 1 FROM audit.Exception WITH (UPDLOCK, HOLDLOCK) WHERE Fingerprint = @Fingerprint);

    DECLARE @IsNew BIT = CASE WHEN @@ROWCOUNT = 1 THEN 1 ELSE 0 END;

    SELECT ExceptionId, @IsNew AS IsNew
    FROM audit.Exception
    WHERE Fingerprint = @Fingerprint;
END
GO

CREATE OR ALTER PROCEDURE audit.sp_CloseException
    @ExceptionId BIGINT,
    @ClosedBy    NVARCHAR(256),
    @Resolution  NVARCHAR(2000)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF LEN(LTRIM(RTRIM(ISNULL(@Resolution, N'')))) = 0
        THROW 51001, 'A resolution is required to close an exception.', 1;

    BEGIN TRANSACTION;

    DECLARE @Status VARCHAR(10), @SubjectUser NVARCHAR(256);

    SELECT @Status = Status, @SubjectUser = SubjectUser
    FROM audit.Exception WITH (UPDLOCK, HOLDLOCK)
    WHERE ExceptionId = @ExceptionId;

    IF @Status IS NULL
        THROW 51002, 'Exception not found.', 1;
    IF @Status <> 'Open'
        THROW 51003, 'Exception is already closed.', 1;
    IF @SubjectUser IS NOT NULL AND @SubjectUser = @ClosedBy
        THROW 51004, 'An exception raised on your own work must be closed by someone else.', 1;

    UPDATE audit.Exception
    SET Status = 'Closed', ClosedBy = @ClosedBy, ClosedAt = SYSDATETIMEOFFSET(), Resolution = @Resolution
    WHERE ExceptionId = @ExceptionId;

    COMMIT TRANSACTION;
END
GO

-- What still blocks month-end close, per unit.
CREATE OR ALTER VIEW audit.vw_OpenExceptionSummary
AS
SELECT
    BusinessUnit,
    SUM(CASE WHEN Severity = 'High'   THEN 1 ELSE 0 END) AS OpenHigh,
    SUM(CASE WHEN Severity = 'Medium' THEN 1 ELSE 0 END) AS OpenMedium,
    SUM(CASE WHEN Severity = 'Low'    THEN 1 ELSE 0 END) AS OpenLow,
    MIN(DetectedAt) AS OldestOpen
FROM audit.Exception
WHERE Status = 'Open'
GROUP BY BusinessUnit;
GO

/*
    Least-privilege role for the SmartLedgerAI Function's managed identity:
    read the ledger, write the queue only through the procedures. Membership is
    added once the identity exists (phase 3), e.g.:

        CREATE USER [<function-app-name>] FROM EXTERNAL PROVIDER;
        ALTER ROLE smartledger_app ADD MEMBER [<function-app-name>];
*/
IF DATABASE_PRINCIPAL_ID(N'smartledger_app') IS NULL
    CREATE ROLE smartledger_app AUTHORIZATION dbo;
GO

GRANT SELECT  ON SCHEMA::dbo TO smartledger_app;
GRANT SELECT  ON audit.Exception TO smartledger_app;
GRANT SELECT  ON audit.vw_OpenExceptionSummary TO smartledger_app;
GRANT EXECUTE ON audit.sp_RaiseException TO smartledger_app;
DENY  INSERT, UPDATE, DELETE ON SCHEMA::dbo TO smartledger_app;
GO
