# SQL objects — `FinancePowerApp`

The database schema for both projects. Scripts are written to run against Azure SQL Database.

## In this folder

| File | Object | Status |
|---|---|---|
| `vw_ExpenseAnomalyStats_WindowFunctionVersion.sql` | `vw_ExpenseAnomalyStats_v2` | ✅ committed |
| `audit/001_exception_queue.sql` | schema `audit`: `audit.Exception` review queue, `sp_RaiseException`, `sp_CloseException`, `vw_OpenExceptionSummary`, role `smartledger_app` | ✅ committed — staging only until signed off; tested by `audit/001_exception_queue.test.sql` |
| `phase0/check_app_writes.sql` | read only: has anything been created or approved since the trigger was put in place; `Status` values in use | ✅ safe on production |
| `phase0/002_expense_writes_via_procedures.sql` | Option A for the closed-period guard: `sp_InsertExpense` (extended), `sp_AssignExpensePeriod`, `sp_UpdateExpense`, `sp_ApproveExpense`, `sp_RejectExpense`, `sp_DeleteExpense`, `AFTER` trigger; `.rollback.sql` undoes it | ✅ committed — approved for staging (not production); tested by `.test.sql` |
| _(to add)_ | `vw_ExpenseAnomalyStats` — the CTE + self-join version the function reads | ⏳ |
| _(to add)_ | `sp_InsertExpense` — validation, `TRY/CATCH`, transaction | ⏳ |
| _(to add)_ | table definitions: `Expenses`, `AccountingPeriods`, `ExpenseCategories` | ⏳ |
| _(to add)_ | reporting views: `vw_ExpenseKPI`, `vw_ExpenseList`, `vw_TaxLedger`, `vw_AnnualTaxSummary`, `vw_AccountingPeriodsDisplay`, `vw_ExpenseStats` | ⏳ |

## Tests

`tests/sql/run.sh` runs every script above, twice (they must be idempotent), then its `.test.sql`, on throwaway
databases in a SQL Server container; CI runs it on every pull request. The `.test.sql` files leave rows behind:
never run them on staging or production.

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
