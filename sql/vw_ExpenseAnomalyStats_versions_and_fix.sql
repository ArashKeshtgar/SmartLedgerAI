/* =============================================================================
   اصلاح باگ RiskLevel  —  'Normal'  →  'Low'
   دیتابیس: FinancePowerApp  (Azure SQL)

   به ترتیب اجرا کن. مرحله‌ی ۱ و ۲ فقط می‌خونن — هیچی رو عوض نمی‌کنن.
   قبل از مرحله‌ی ۳ حتماً نتیجه‌ی مرحله‌ی ۲ رو ببین.
   ============================================================================= */


/* -----------------------------------------------------------------------------
   مرحله ۱ — تعریف فعلی هر دو ویو رو ببین

   ویو تو فایل ذخیره نمی‌شه؛ تعریفش داخل خود دیتابیسه.
   این کوئری متن واقعی‌ای که الان تو Azure SQL هست رو برمی‌گردونه.
----------------------------------------------------------------------------- */

SELECT
    v.name                AS ViewName,
    m.definition          AS ViewDefinition
FROM sys.views AS v
JOIN sys.sql_modules AS m ON m.object_id = v.object_id
WHERE v.name IN ('vw_ExpenseAnomalyStats', 'vw_ExpenseAnomalyStats_v2');

-- 💡 تو SSMS: رو نتیجه‌ی ستون ViewDefinition کلیک کن تا متن کامل باز شه.
--    یا راست‌کلیک رو ویو در Object Explorer:
--    Script View as → ALTER To → New Query Editor Window


/* -----------------------------------------------------------------------------
   مرحله ۲ — ⚠️ مهم‌ترین مرحله: تأیید فرض

   من فرض کردم ویوی اصلی 'Low' برمی‌گردونه و فقط v2 هست که 'Normal' می‌ده.
   این رو باید با چشم خودت ببینی، نه با حرف من.
----------------------------------------------------------------------------- */

SELECT 'ORIGINAL' AS Source, RiskLevel, COUNT(*) AS RowCnt
FROM dbo.vw_ExpenseAnomalyStats
GROUP BY RiskLevel

UNION ALL

SELECT 'V2 (window)' AS Source, RiskLevel, COUNT(*) AS RowCnt
FROM dbo.vw_ExpenseAnomalyStats_v2
GROUP BY RiskLevel

ORDER BY Source, RiskLevel;

/*  نتیجه‌ی مورد انتظار:

    Source        RiskLevel   RowCnt
    ------------  ----------  ------
    ORIGINAL      High             1
    ORIGINAL      Low             12     ← اگه اینجا 'Low' دیدی، فرض درست بود
    V2 (window)   High             1
    V2 (window)   Normal          12     ← و اینجا 'Normal' — همون باگ

    ❗ اگه ویوی ORIGINAL هم 'Normal' داد، یعنی باگ تو ویوی اصلیه
       و کد C# همین الان هم برای هر رکورد Azure OpenAI رو صدا می‌زنه.
       اون موقع مرحله‌ی ۳ رو روی ویوی اصلی هم اجرا کن.

    ❗ اگه آستانه‌ها هم فرق داشتن (مثلاً ویوی اصلی 1.5 و 2.5 باشه نه 2 و 3)،
       بگو تا اسکریپت دمو رو اصلاح کنم — الان توش گفتم «زیر دو، دو تا سه».
*/


/* -----------------------------------------------------------------------------
   مرحله ۳ — اصلاح ویو v2

   جواب سؤالت: نه، ویو رو "ویرایش" نمی‌کنی — کل تعریفش رو دوباره می‌نویسی.
   `CREATE OR ALTER VIEW` این کار رو یه‌جا انجام می‌ده:
   اگه ویو نبود می‌سازتش، اگه بود جایگزینش می‌کنه.

   مزیتش به DROP + CREATE:  مجوزهای GRANT شده روی ویو حفظ می‌شن.
   با DROP همه‌ی مجوزها می‌پرن و باید دوباره بدی.

   ✅ `CREATE OR ALTER` تو Azure SQL Database کاملاً پشتیبانی می‌شه.
----------------------------------------------------------------------------- */

CREATE OR ALTER VIEW [dbo].[vw_ExpenseAnomalyStats_v2] AS
SELECT
    ExpenseId,
    Category,
    Amount,
    AvgAmount,
    StdDevAmount,
    SampleSize,
    ZScore,
    CASE
        WHEN ABS(ZScore) < 2 THEN 'Low'      -- ← تنها تغییر: 'Normal' بود
        WHEN ABS(ZScore) < 3 THEN 'Medium'
        ELSE 'High'
    END AS RiskLevel
FROM (
    SELECT
        ExpenseId,
        Category,
        Amount,
        AVG(Amount)   OVER (PARTITION BY Category, YEAR(ExpenseDate), MONTH(ExpenseDate)) AS AvgAmount,
        STDEV(Amount) OVER (PARTITION BY Category, YEAR(ExpenseDate), MONTH(ExpenseDate)) AS StdDevAmount,
        COUNT(*)      OVER (PARTITION BY Category, YEAR(ExpenseDate), MONTH(ExpenseDate)) AS SampleSize,
        CASE
            WHEN STDEV(Amount) OVER (PARTITION BY Category, YEAR(ExpenseDate), MONTH(ExpenseDate)) = 0
                 OR STDEV(Amount) OVER (PARTITION BY Category, YEAR(ExpenseDate), MONTH(ExpenseDate)) IS NULL THEN 0
            ELSE (Amount - AVG(Amount) OVER (PARTITION BY Category, YEAR(ExpenseDate), MONTH(ExpenseDate)))
                 / STDEV(Amount) OVER (PARTITION BY Category, YEAR(ExpenseDate), MONTH(ExpenseDate))
        END AS ZScore
    FROM Expenses
    WHERE Status = 'Approved' AND PeriodId IS NOT NULL
) AS base;
GO


/* -----------------------------------------------------------------------------
   مرحله ۴ — تأیید اینکه حالا دو ویو واقعاً یکی شدن

   این همون تستیه که کامنت پایین فایل اصلی ادعاش رو کرده بود
   ولی هیچ‌وقت اجرا نشده بود. اگه صفر ردیف برگشت، ادعا درست شد.
----------------------------------------------------------------------------- */

SELECT
    o.ExpenseId,
    o.RiskLevel   AS Original_Risk,
    v.RiskLevel   AS V2_Risk,
    o.ZScore      AS Original_Z,
    v.ZScore      AS V2_Z
FROM dbo.vw_ExpenseAnomalyStats     AS o
JOIN dbo.vw_ExpenseAnomalyStats_v2  AS v ON v.ExpenseId = o.ExpenseId
WHERE o.RiskLevel <> v.RiskLevel
   OR ABS(o.ZScore - v.ZScore) > 0.0001;   -- تلورانس اعشار شناور

-- ✅ صفر ردیف = دو ویو دقیقاً یکی محاسبه می‌کنن.
--    حالا کامنت «نتیجه‌ی دو تا ویو باید یکی باشه» واقعاً درسته.
--
-- ⚠️ ردیف برگشت؟ فقط RiskLevel فرق داره یا ZScore هم؟
--    اگه ZScore هم فرق داره، یعنی خودِ محاسبه بین دو نسخه فرق داره
--    (احتمالاً WHERE یا PARTITION متفاوته) — بگو تا با هم دربیاریمش.


/* =============================================================================
   اختیاری — اگه خواستی نسخه‌ی Window Function جایگزین اصلی بشه
   =============================================================================

   کد C# از `dbo.vw_ExpenseAnomalyStats` می‌خونه (خط ۱۲۴ فایل AnalyzeExpense.cs).
   پس اگه می‌خوای نسخه‌ی Window Function عملاً استفاده بشه، سه راه داری:

   راه ۱ (توصیه‌ی من) — بدنه‌ی ویوی اصلی رو با نسخه‌ی Window Function عوض کن،
   اسم رو دست نزن. هیچ تغییری تو C# لازم نیست، و ویوی v2 به‌عنوان مستند
   «این رو دو جور ساختم» تو ریپو می‌مونه — که برای مصاحبه ارزش داره.

       CREATE OR ALTER VIEW [dbo].[vw_ExpenseAnomalyStats] AS
       ... (همون بدنه‌ی بالا) ...

   راه ۲ — رشته‌ی کوئری تو C# رو به `vw_ExpenseAnomalyStats_v2` عوض کن.
   ساده‌ست ولی اسم `_v2` تو کد پروداکشن بوی نصفه‌کاره بودن می‌ده.

   راه ۳ — هیچ‌کدوم. ویوی اصلی بمونه و v2 فقط به‌عنوان تمرین تو ریپو باشه.
   ⚠️ اگه این رو انتخاب کردی، **کامنت بالای فایل SQL رو عوض کن** —
      الان می‌گه «بعد اگه خواستی جایگزین اصلی کنی»، که یعنی هر کی
      اون کار رو بکنه باگ رو فعال می‌کنه.


   =============================================================================
   اختیاری ۲ — نسخه‌ی تمیزتر (جواب «چی رو بهتر می‌کردی؟»)
   =============================================================================

   تو نسخه‌ی فعلی، `STDEV(...) OVER (...)` چهار بار تکرار شده.
   SQL Server معمولاً بهینه‌ش می‌کنه، ولی خوندنش سخته.
   با یه لایه‌ی nesting اضافه، هر پنجره فقط یه بار نوشته می‌شه:
*/

CREATE OR ALTER VIEW [dbo].[vw_ExpenseAnomalyStats_v3] AS
SELECT
    ExpenseId,
    Category,
    Amount,
    AvgAmount,
    StdDevAmount,
    SampleSize,
    ZScore,
    CASE
        WHEN ABS(ZScore) < 2 THEN 'Low'
        WHEN ABS(ZScore) < 3 THEN 'Medium'
        ELSE 'High'
    END AS RiskLevel
FROM (
    -- لایه ۲: حالا AvgAmount و StdDevAmount به‌عنوان ستون در دسترسن،
    -- پس ZScore رو یه بار و خوانا می‌نویسیم
    SELECT
        ExpenseId,
        Category,
        Amount,
        AvgAmount,
        StdDevAmount,
        SampleSize,
        CASE
            WHEN StdDevAmount IS NULL OR StdDevAmount = 0 THEN 0
            ELSE (Amount - AvgAmount) / StdDevAmount
        END AS ZScore
    FROM (
        -- لایه ۱: هر window function دقیقاً یه بار
        SELECT
            ExpenseId,
            Category,
            Amount,
            AVG(Amount)   OVER (PARTITION BY Category, YEAR(ExpenseDate), MONTH(ExpenseDate)) AS AvgAmount,
            STDEV(Amount) OVER (PARTITION BY Category, YEAR(ExpenseDate), MONTH(ExpenseDate)) AS StdDevAmount,
            COUNT(*)      OVER (PARTITION BY Category, YEAR(ExpenseDate), MONTH(ExpenseDate)) AS SampleSize
        FROM Expenses
        WHERE Status = 'Approved' AND PeriodId IS NOT NULL
    ) AS windowed
) AS scored;
GO

/*
   چرا دو لایه لازمه و نه یکی:
   تو SQL نمی‌تونی یه alias رو تو همون SELECT که تعریفش کردی استفاده کنی.
   یعنی نمی‌شه نوشت `AVG(...) OVER (...) AS AvgAmount` و بلافاصله
   تو همون SELECT بگی `(Amount - AvgAmount)`. برای همین باید یه لایه پایین‌تر
   حسابش کنی و لایه‌ی بالا ازش استفاده کنه.
   ← این خودش یه سؤال رایج مصاحبه‌ی SQL ـه.

   🔷 نکته‌ی Azure SQL: از SQL Server 2022 و Azure SQL Database به بعد
   یه راه تمیزتر هم هست — عبارت WINDOW که پنجره رو یه بار نام‌گذاری می‌کنه:

       SELECT
           AVG(Amount)   OVER w AS AvgAmount,
           STDEV(Amount) OVER w AS StdDevAmount,
           COUNT(*)      OVER w AS SampleSize
       FROM Expenses
       WHERE Status = 'Approved' AND PeriodId IS NOT NULL
       WINDOW w AS (PARTITION BY Category, YEAR(ExpenseDate), MONTH(ExpenseDate));

   Azure SQL Database پشتیبانیش می‌کنه (چون همیشه آخرین نسخه‌ست).
   اگه یه SQL Server لوکال قدیمی‌تر از 2022 هم داری، اونجا کار نمی‌کنه.
   دونستن این تو مصاحبه امتیاز مثبته — نشون می‌ده T-SQL جدید رو دنبال می‌کنی.
*/


/* =============================================================================
   پاک‌سازی (اگه v3 رو فقط برای تست ساختی و نمی‌خوایش)
   ============================================================================= */
-- DROP VIEW IF EXISTS dbo.vw_ExpenseAnomalyStats_v3;
