/*
    LOCAL COPY ONLY — do not run on Azure; Azure already has these definitions.

    Phase 0 found the local copy's anomaly views still emit 'Normal' for the
    low band, the bug already fixed on Azure (the Function tests risk != "Low",
    so 'Normal' sends every expense to the language model). This brings the
    local copy in line with Azure, copied from Azure's sys.sql_modules on
    2026-10-11. CREATE OR ALTER keeps existing permissions on the views.
*/

CREATE OR ALTER VIEW [dbo].[vw_ExpenseAnomalyStats] AS
WITH BaseData AS (
    SELECT
        ExpenseId,
        Category,
        Amount,
        ExpenseDate
    FROM Expenses
    WHERE Status = 'Approved'
      AND PeriodId IS NOT NULL
),
Stats AS (
    SELECT
        Category,
        YEAR(ExpenseDate) AS Year,
        MONTH(ExpenseDate) AS Month,
        AVG(Amount)    AS AvgAmount,
        STDEV(Amount) AS StdDevAmount,
        COUNT(*)      AS SampleSize
    FROM BaseData
    GROUP BY Category, YEAR(ExpenseDate), MONTH(ExpenseDate)
)
SELECT
    e.ExpenseId,
    e.Category,
    e.Amount,
    s.AvgAmount,
    s.StdDevAmount,
    s.SampleSize,
    CASE
        WHEN s.StdDevAmount = 0 OR s.StdDevAmount IS NULL THEN 0
        ELSE (e.Amount - s.AvgAmount) / s.StdDevAmount
    END AS ZScore,
    CASE
        WHEN ABS(
            CASE
                WHEN s.StdDevAmount = 0 OR s.StdDevAmount IS NULL THEN 0
                ELSE (e.Amount - s.AvgAmount) / s.StdDevAmount
            END
        ) < 2 THEN 'Low'
        WHEN ABS(
            CASE
                WHEN s.StdDevAmount = 0 OR s.StdDevAmount IS NULL THEN 0
                ELSE (e.Amount - s.AvgAmount) / s.StdDevAmount
            END
        ) < 3 THEN 'Medium'
        ELSE 'High'
    END AS RiskLevel
FROM Expenses e
JOIN Stats s
  ON e.Category = s.Category
 AND YEAR(e.ExpenseDate) = s.Year
 AND MONTH(e.ExpenseDate) = s.Month
WHERE e.Status = 'Approved';
GO

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
        WHEN ABS(ZScore) < 2 THEN 'Low'
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

-- Check: both views must now return only Low / Medium / High.
SELECT 'vw_ExpenseAnomalyStats' AS ViewName, RiskLevel, COUNT(*) AS Rows FROM dbo.vw_ExpenseAnomalyStats GROUP BY RiskLevel
UNION ALL
SELECT 'vw_ExpenseAnomalyStats_v2', RiskLevel, COUNT(*) FROM dbo.vw_ExpenseAnomalyStats_v2 GROUP BY RiskLevel;
