# فاز ۰ — بررسی بدون تغییر

هدف: پیش از هر تغییری روی دیتابیس Azure، بدانیم دقیقاً با کپی محلی چه فرقی دارد، و یک محیط staging داشته باشیم که Power App روی آن سالم کار کند.

**در این فاز هیچ چیزی روی دیتابیس production عوض نمی‌شود.** فقط خواندن، و ساخت یک کپی جدا.

دروازهٔ عبور به فاز ۱: Power App روی staging سالم کار کند، و گزارش مقایسهٔ اسکیما بررسی و تأیید شده باشد.

## قدم ۱ — عکس اسکیمای Azure (فقط خواندن)

1. Azure Portal ← **SQL databases** ← `FinancePowerApp` ← **Query editor**، و ورود.
2. محتوای [`sql/phase0/schema_snapshot.sql`](../sql/phase0/schema_snapshot.sql) را paste و **Run** کنید.
3. **Export data as ← CSV** و فایل را `azure.csv` بنامید.

## قدم ۲ — عکس اسکیمای کپی محلی

1. در SSMS به دیتابیس محلی وصل شوید و همان کوئری را اجرا کنید.
2. روی نتیجه راست‌کلیک ← **Save Results As…** ← CSV، با نام `local.csv`.
   یا ساده‌تر: همهٔ جدول نتیجه را انتخاب و Copy کنید و در یک فایل `local.tsv` paste کنید — ابزار خروجی بدون سرستون و جداشده با Tab را هم می‌خواند.

## قدم ۳ — مقایسه

```powershell
dotnet run --project tools/SmartLedgerAI.SchemaDiff -- azure.csv local.csv schema-diff.md
```

خروجی یک گزارش Markdown است: اشیای فقط در یک طرف، ستون‌های جدول که نوع یا NULL بودنشان فرق دارد، و ویو/پروسیجر/تریگرهایی که کدشان فرق دارد. کد خروج `0` یعنی یکسان، `1` یعنی تفاوت هست.

این دو فایل CSV فقط ساختار دارند، هیچ دادهٔ مالی ندارند؛ می‌توانید برای بررسی بفرستید.

## قدم ۴ — ساخت staging (هزینه دارد، با تأیید شما)

یک کپی جدا از دیتابیس production، روی همان سرور:

- Portal ← `FinancePowerApp` ← **Copy** ← نام: `FinancePowerApp-staging`، و همان سرور.
- یا با T-SQL روی دیتابیس `master` همان سرور:

```sql
CREATE DATABASE [FinancePowerApp-staging] AS COPY OF [FinancePowerApp];
```

این یک دیتابیس جدید است و در صورتحساب Azure جدا حساب می‌شود. پیش از ساختن، pricing tier آن را پایین‌ترین سطح قابل‌قبول بگذارید.

## قدم ۵ — آزمون Power App روی staging

1. یک کپی از Power App بسازید (یا یک environment جدا) و connection آن را به `FinancePowerApp-staging` بزنید. **خود اپ اصلی را به staging وصل نکنید.**
2. یک هزینه ثبت، تأیید، و ویرایش کنید؛ یک ماه بسته را امتحان کنید (تریگر `trg_BlockChangesOnClosedPeriod` باید جلوی تغییر را بگیرد).
3. اگر همه درست بود، دروازهٔ فاز ۰ باز است.

## بعد از فاز ۰

- اسکریپت‌های ERP (`deploy.ps1` و جدول `ErpMigration`) اول روی staging اجرا می‌شوند — فاز ۱.
- اسکریپت صف استثنا ([`sql/audit/001_exception_queue.sql`](../sql/audit/001_exception_queue.sql)) هم اول روی staging.
