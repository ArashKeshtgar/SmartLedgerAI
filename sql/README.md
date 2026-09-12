# SQL objects — `FinancePowerApp`

The database schema for both projects. Scripts are written to run against Azure SQL Database.

## In this folder

| File | Object | Status |
|---|---|---|
| `vw_ExpenseAnomalyStats_WindowFunctionVersion.sql` | `vw_ExpenseAnomalyStats_v2` | ✅ committed |
| _(to add)_ | `vw_ExpenseAnomalyStats` — the CTE + self-join version the function reads | ⏳ |
| _(to add)_ | `sp_InsertExpense` — validation, `TRY/CATCH`, transaction | ⏳ |
| _(to add)_ | table definitions: `Expenses`, `AccountingPeriods`, `ExpenseCategories` | ⏳ |
| _(to add)_ | reporting views: `vw_ExpenseKPI`, `vw_ExpenseList`, `vw_TaxLedger`, `vw_AnnualTaxSummary`, `vw_AccountingPeriodsDisplay`, `vw_ExpenseStats` | ⏳ |

## How to export the remaining objects from Azure SQL

In SSMS, connect to the database, then for each object:

**Object Explorer → right-click the view or procedure → Script View as → CREATE To → New Query Editor Window**

Save each as its own `.sql` file in this folder. For the tables, use
**right-click database → Tasks → Generate Scripts** and select only the three tables (schema only, no data).

Or script everything at once:

```sql
SELECT
    o.type_desc,
    o.name,
    m.definition
FROM sys.sql_modules AS m
JOIN sys.objects     AS o ON o.object_id = m.object_id
WHERE o.is_ms_shipped = 0
ORDER BY o.type_desc, o.name;
```

## `RiskLevel` contract

The Azure Function tests `risk != "Low"` before calling Azure OpenAI, so the string emitted
for the normal band is part of the contract between the SQL and C# layers. Both anomaly views
must emit `Low` / `Medium` / `High` — not `Normal`.

| Z-Score | RiskLevel |
|---|---|
| `< 2` | `Low` |
| `2 – 3` | `Medium` |
| `> 3` | `High` |
