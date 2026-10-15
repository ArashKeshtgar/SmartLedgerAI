/*
    Phase 0: schema snapshot. Read-only — reads catalog views only, no table data.

    Run the same query on the Azure database (Portal → SQL database → Query editor)
    and on the local copy (SSMS), export each result as CSV, then compare:

        dotnet run --project tools/SmartLedgerAI.SchemaDiff -- azure.csv local.csv

    DefinitionHash fingerprints the source of views, procedures, triggers and
    functions, so a changed object shows up without exporting its code.
*/
SELECT
    s.name                                          AS SchemaName,
    o.name                                          AS ObjectName,
    o.type_desc                                     AS ObjectType,
    c.column_id                                     AS ColumnId,
    c.name                                          AS ColumnName,
    TYPE_NAME(c.user_type_id)                       AS DataType,
    c.max_length                                    AS MaxLength,
    c.precision                                     AS [Precision],
    c.scale                                         AS Scale,
    c.is_nullable                                   AS IsNullable,
    CONVERT(VARCHAR(64), HASHBYTES('SHA2_256', m.definition), 2) AS DefinitionHash
FROM sys.objects AS o
JOIN sys.schemas AS s       ON s.schema_id = o.schema_id
LEFT JOIN sys.columns AS c  ON c.object_id = o.object_id
LEFT JOIN sys.sql_modules AS m ON m.object_id = o.object_id
WHERE o.is_ms_shipped = 0
  AND o.type IN ('U', 'V', 'P', 'TR', 'FN', 'IF', 'TF')
ORDER BY s.name, o.name, c.column_id;
