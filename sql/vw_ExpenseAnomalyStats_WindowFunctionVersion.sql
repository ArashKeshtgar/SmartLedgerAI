-- نسخه‌ی جایگزین vw_ExpenseAnomalyStats با استفاده از Window Functions
-- به‌جای CTE + GROUP BY + JOIN
-- می‌تونی این رو به‌عنوان ویو دومی کنار ویو اصلی بسازی (اسم فرق داره)، تست کنی، بعد اگه خواستی جایگزین اصلی کنی

CREATE VIEW [dbo].[vw_ExpenseAnomalyStats_v2] AS
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
    SELECT
        ExpenseId,
        Category,
        Amount,
        AVG(Amount) OVER (PARTITION BY Category, YEAR(ExpenseDate), MONTH(ExpenseDate)) AS AvgAmount,
        STDEV(Amount) OVER (PARTITION BY Category, YEAR(ExpenseDate), MONTH(ExpenseDate)) AS StdDevAmount,
        COUNT(*) OVER (PARTITION BY Category, YEAR(ExpenseDate), MONTH(ExpenseDate)) AS SampleSize,
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

-- برای تست:
-- SELECT * FROM vw_ExpenseAnomalyStats_v2 ORDER BY ExpenseId;
-- SELECT * FROM vw_ExpenseAnomalyStats ORDER BY ExpenseId;
-- نتیجه‌ی دو تا ویو باید یکی باشه (فقط روش محاسبه فرق داره)
