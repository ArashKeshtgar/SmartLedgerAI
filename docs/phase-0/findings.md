# فاز ۰ — یافته‌ها (۱۱ اکتبر ۲۰۲۶)

مقایسهٔ اسکیمای دیتابیس `FinancePowerApp` روی Azure با کپی محلی. گزارش خام: [`schema-diff-2026-10-11.md`](schema-diff-2026-10-11.md).

## خلاصه

| موضوع | Azure | محلی | نتیجه |
|---|---|---|---|
| جدول‌های Power App (`Expenses`، `AccountingPeriods`، `ExpenseCategories`) | — | — | **یکسان** (همهٔ ستون‌ها، نوع و NULL) |
| پروسیجرها و تریگر `trg_BlockChangesOnClosedPeriod` | — | — | **یکسان** |
| اسکیماهای ERP (`gl`، `ar`، `ap`، `org`، `tax`، `integ`) و `ErpMigration` | ندارد | دارد | انتظار می‌رفت؛ نصب ERP روی Azure = فاز ۱ |
| `Expenses_Backup_v6`، `AccountingPeriods_Backup_v6`، `vw_ExpenseAnomalyStats_v3` | دارد | ندارد | پشتیبان/نسخهٔ قدیمی؛ دست نمی‌زنیم |
| ۵ ویو (`vw_AccountingPeriodsDisplay`، `vw_AnnualTaxSummary`، `vw_ExpenseKPI`، `vw_ExpenseList`، `vw_TaxLedger`) | — | — | **منطق یکسان**؛ فقط فاصله‌گذاری/`[dbo].` فرق دارد |
| `vw_ExpenseAnomalyStats` و `vw_ExpenseAnomalyStats_v2` | `'Low'` | `'Normal'` | **کپی محلی باگ قدیمی را دارد** |

## باگ `'Normal'` روی کپی محلی

تابع SmartLedgerAI فقط وقتی `RiskLevel != "Low"` باشد مدل زبانی را صدا می‌زند. روی کپی محلی هر هزینهٔ عادی `'Normal'` برمی‌گرداند، پس هر تراکنش به مدل می‌رود. Azure درست است. کپی محلی از فایل قدیمی `sql/vw_ExpenseAnomalyStats_WindowFunctionVersion.sql` ساخته شده بود که هنوز `'Normal'` داشت؛ آن فایل هم اصلاح شد.

**اقدام:** [`sql/phase0/local_sync_anomaly_views.sql`](../../sql/phase0/local_sync_anomaly_views.sql) را **فقط روی کپی محلی** اجرا کنید. آخرش یک کوئری بررسی دارد که باید فقط Low/Medium/High نشان دهد.

## پیامد برای فاز ۱

- اسکریپت‌های ERP روی کپی محلی ساخته و تست شده‌اند و جدول‌های مشترک دو طرف یکی است؛ پس از نظر اسکیما مانعی برای اجرای آن‌ها روی staging نیست.
- هنوز باید کد `deploy.ps1` دیده شود تا معلوم شود آیا به ویوها یا جدول‌های `dbo` دست می‌زند (مخزن `FinancePowerApp` هنوز خالی است).
- دروازهٔ فاز ۰ هنوز باز نشده: staging ساخته و Power App روی آن آزموده نشده است.
