# Schema comparison: azure vs local

azure: 18 objects · local: 34 objects · 29 difference(s)

## Only in azure (3)

| Object | Detail |
|---|---|
| `dbo.AccountingPeriods_Backup_v6` | USER_TABLE |
| `dbo.Expenses_Backup_v6` | USER_TABLE |
| `dbo.vw_ExpenseAnomalyStats_v3` | VIEW |

## Only in local (19)

| Object | Detail |
|---|---|
| `ap.ExpensePosting` | USER_TABLE |
| `ap.Item` | USER_TABLE |
| `ar.Item` | USER_TABLE |
| `ar.vw_Aging` | VIEW |
| `dbo.ErpMigration` | USER_TABLE |
| `gl.Account` | USER_TABLE |
| `gl.CashMap` | USER_TABLE |
| `gl.CategoryMap` | USER_TABLE |
| `gl.ControlMap` | USER_TABLE |
| `gl.JournalEntry` | USER_TABLE |
| `gl.JournalLine` | USER_TABLE |
| `gl.vw_LedgerLines` | VIEW |
| `gl.vw_PeriodMovement` | VIEW |
| `integ.Document` | USER_TABLE |
| `org.Entity` | USER_TABLE |
| `org.EntitySource` | USER_TABLE |
| `org.Party` | USER_TABLE |
| `tax.TaxCode` | USER_TABLE |
| `tax.vw_HstReturn` | VIEW |

## Views / procedures / triggers / functions whose code differs (7)

| Object | Detail |
|---|---|
| `dbo.vw_AccountingPeriodsDisplay` | VIEW |
| `dbo.vw_AnnualTaxSummary` | VIEW |
| `dbo.vw_ExpenseAnomalyStats` | VIEW |
| `dbo.vw_ExpenseAnomalyStats_v2` | VIEW |
| `dbo.vw_ExpenseKPI` | VIEW |
| `dbo.vw_ExpenseList` | VIEW |
| `dbo.vw_TaxLedger` | VIEW |

