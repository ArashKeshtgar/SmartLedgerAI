/*
    Phase 0: source code of the views whose DefinitionHash differs between
    Azure and the local copy (see docs/phase-0/schema-diff-2026-10-11.md).
    Read-only. Run on both databases, export as CSV, and compare.
*/
SELECT
    s.name AS SchemaName,
    o.name AS ObjectName,
    m.definition AS Definition
FROM sys.sql_modules AS m
JOIN sys.objects AS o ON o.object_id = m.object_id
JOIN sys.schemas AS s ON s.schema_id = o.schema_id
WHERE s.name = 'dbo'
  AND o.name IN (
      'vw_AccountingPeriodsDisplay', 'vw_AnnualTaxSummary', 'vw_ExpenseAnomalyStats',
      'vw_ExpenseAnomalyStats_v2', 'vw_ExpenseAnomalyStats_v3', 'vw_ExpenseKPI',
      'vw_ExpenseList', 'vw_TaxLedger')
ORDER BY o.name;
