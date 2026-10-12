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

## تست Power App روی staging (۱۲ اکتبر) — ثبت و ویرایش رد می‌شود

تست ۱ و ۲ روی staging شکست خورد. علت در تعریف تریگر است (`database/005_powerapp_baseline.sql` در مخزن FinancePowerApp):

- `trg_BlockChangesOnClosedPeriod` یک تریگر **INSTEAD OF INSERT, UPDATE** روی `dbo.Expenses` است.
- اتصال SQL در Power Apps ثبت و ویرایش را با `INSERT/UPDATE … OUTPUT` می‌فرستد، و SQL Server روی جدولی که تریگر فعال دارد `OUTPUT` بدون `INTO` را رد می‌کند. پس هر Patch از Power App خطا می‌دهد، چه ماه باز باشد چه بسته — و پیام «Accounting period is closed» هرگز به کاربر نمی‌رسد.
- همان تریگر روی production هم هست؛ باید معلوم شود اپ اصلی امروز می‌تواند هزینه ثبت کند یا نه.

### حفره‌های کنترلی همین تریگر

| حالت | امروز |
|---|---|
| ثبت یا ویرایش با `PeriodId` ماه بسته | رد می‌شود ✅ |
| ویرایش هزینه‌ای که **الان** در ماه بسته است و `PeriodId` آن به ماه باز یا `NULL` عوض شود | **مجاز** — تریگر فقط مقدار جدید را چک می‌کند، نه قدیم |
| حذف هزینه در ماه بسته | **مجاز** — تریگر DELETE را پوشش نمی‌دهد |
| ستون تازه در `dbo.Expenses` | بی‌صدا نادیده گرفته می‌شود — تریگر فهرست ستون ثابت دارد |

### راه‌حل پیشنهادی (تصمیم با مالک)

**الف (پیشنهاد):** Power App به‌جای Patch مستقیم، از stored procedure ثبت/ویرایش/حذف استفاده کند (`sp_InsertExpense` همین حالا هست). پروسیجرها هم مقدار قدیم و هم جدید را چک می‌کنند؛ دسترسی مستقیم نوشتن روی جدول از کاربر اپ گرفته می‌شود؛ تریگر به‌عنوان لایهٔ دوم اصلاح می‌شود تا DELETE و مقدار قدیم را هم بگیرد. نیاز به تغییر فرمول‌های اپ دارد.

**ب:** تریگر حذف و به‌جایش یک CHECK constraint با تابع «ماه باز است» گذاشته شود. فرمول‌های اپ دست نمی‌خورد، ولی فقط مقدار جدید را چک می‌کند؛ دو حفرهٔ بالا (جابه‌جایی از ماه بسته و حذف) باز می‌ماند.

هر کدام اول روی staging آزموده می‌شود.

## راه‌حل الف آماده است (۱۲ اکتبر) — فقط برای staging

| فایل | کار |
|---|---|
| [`sql/phase0/002_expense_writes_via_procedures.sql`](../../sql/phase0/002_expense_writes_via_procedures.sql) | چهار پروسیجر ثبت، ویرایش، تأیید و حذف، به‌علاوهٔ تریگر تازه |
| [`…rollback.sql`](../../sql/phase0/002_expense_writes_via_procedures.rollback.sql) | تریگر و `sp_InsertExpense` اصلی را عیناً برمی‌گرداند |
| [`…test.sql`](../../sql/phase0/002_expense_writes_via_procedures.test.sql) | ۱۷ حالت. **فقط روی دیتابیس دورریختنی**، نه staging |

- **پروسیجرها:** `sp_InsertExpense` همان پنج پارامتر قبلی را دارد، به‌علاوهٔ پارامترهای اختیاری `PeriodId`، `CategoryId` و `TaxAmount`، و شناسهٔ هزینهٔ تازه را برمی‌گرداند. پروسیجرهای `sp_UpdateExpense`، `sp_ApproveExpense` و `sp_DeleteExpense` هم ماهِ فعلی هزینه را چک می‌کنند و هم ماهی را که هزینه به آن منتقل می‌شود.
- **تریگر:** حالا `AFTER INSERT, UPDATE, DELETE` است. هم مقدار قدیم و هم مقدار جدید را چک می‌کند و فهرست ستون ثابت ندارد. هر سه حفره بسته می‌شود.
- **آزمون محلی:** روی SQL Server 2022 با اسکیمای `005_powerapp_baseline.sql` تست شد:
  - خطای Power App با تریگر فعلی بازتولید شد (Msg 334).
  - بعد از اسکریپت، هر ۱۷ حالت تست درست بود.
  - اسکریپت‌های ERP (از `010` تا `040`) روی آن بی‌خطا اجرا شدند.
  - rollback متن هر دو شیء را عیناً به نسخهٔ اصلی برگرداند.

### قدم‌های staging

1. در Query editor دیتابیس **`FinancePowerApp-staging`**، اسکریپت `002_expense_writes_via_procedures.sql` را اجرا کنید.
2. در **کپی** Power App: Data ← Add data ← SQL Server ← همان connection staging ← زبانهٔ **Stored procedures** ← هر چهار پروسیجر را اضافه کنید.
3. هر `Patch` یا `Remove` روی `Expenses` را با فراخوانی پروسیجر عوض کنید و بعدش `Refresh(Expenses)` بگذارید. نمونه (اسم connection و کنترل‌ها مال اپ شماست):

   ```
   FinanceStaging.dbosp_InsertExpense({Amount: Value(txtAmount.Text), Category: ddCategory.Selected.Value,
       ExpenseDate: dpDate.SelectedDate, Vendor: txtVendor.Text, Description: txtDesc.Text,
       PeriodId: ddPeriod.Selected.PeriodId});
   Refresh(Expenses)

   FinanceStaging.dbosp_ApproveExpense({ExpenseId: gal.Selected.ExpenseId, ApprovedBy: User().Email})
   FinanceStaging.dbosp_DeleteExpense({ExpenseId: gal.Selected.ExpenseId})
   ```

4. آزمون: هزینه را ثبت، ویرایش، تأیید و حذف کنید. بعد در ماه بسته همین چهار کار را امتحان کنید؛ هر چهار باید با پیام «Accounting period is closed» رد شوند.
5. اگر نشد: `…rollback.sql` را روی staging اجرا کنید.

**یک نکته:** اگر اپ وضعیت دیگری غیر از Pending و Approved دارد، مثلاً Rejected، بگویید تا پروسیجرش را اضافه کنم.
