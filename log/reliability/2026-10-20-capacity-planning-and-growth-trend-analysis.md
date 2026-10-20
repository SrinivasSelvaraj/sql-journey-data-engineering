---
date: 2026-10-20
phase: reliability
topic: Capacity planning and growth trend analysis
---

# Capacity planning and growth trend analysis

*Quality, reliability and the professional layer*

## Concept

Capacity planning is the discipline of forecasting resource demand—compute, storage, network—against growth trends in your data pipeline. Without it, systems fail silently under load: queries timeout, ingestion lags, costs spiral unexpectedly. It's the difference between building a pipeline that works today and one trusted to work at 10x scale tomorrow.

Growth trend analysis means understanding *how* your data grows: linearly, exponentially, seasonally. A job posting pipeline might grow 5% monthly but spike 300% in hiring season. If you don't quantify this, you'll either over-provision (waste), under-provision (outages), or make infrastructure decisions on intuition rather than evidence.

When ownership matters: a pipeline builder delivers something that works. An owner predicts failure before it happens, provisions headroom proactively, and communicates trade-offs to stakeholders. This requires baselining current consumption, extrapolating trends, identifying bottlenecks, and documenting assumptions—all before the system breaks.

## Practice

**Problem:** Your `job_postings_fact` table grows by ~500K rows/month. You need to:
1. Quantify monthly growth rate over the past 6 months
2. Identify which columns drive storage impact
3. Forecast table size 12 months from now
4. Flag if growth is accelerating (nonlinear)

```sql
-- Monthly growth analysis and 12-month forecast
WITH monthly_counts AS (
  SELECT 
    DATE_TRUNC('month', job_posted_date)::DATE AS month,
    COUNT(*) AS row_count,
    APPROX_QUANTILES(OCTET_LENGTH(job_title_short), 100)[OFFSET(50)] AS median_title_bytes,
    APPROX_QUANTILES(OCTET_LENGTH(job_location), 100)[OFFSET(50)] AS median_location_bytes
  FROM job_postings_fact
  WHERE job_posted_date >= CURRENT_DATE - INTERVAL 6 MONTH
  GROUP BY 1
),
growth_metrics AS (
  SELECT 
    month,
    row_count,
    LAG(row_count) OVER (ORDER BY month) AS prev_month_count,
    ROUND(
      100.0 * (row_count - LAG(row_count) OVER (ORDER BY month)) 
      / LAG(row_count) OVER (ORDER BY month), 2
    ) AS pct_growth,
    -- Estimate row size: 8 (job_id) + title + salary (8) + boolean (1) + location + date (8)
    (16 + median_title_bytes + median_location_bytes)::INT64 AS estimated_bytes_per_row
  FROM monthly_counts
)
SELECT 
  month,
  row_count,
  pct_growth,
  estimated_bytes_per_row,
  ROUND(row_count * estimated_bytes_per_row / POW(10,9), 2) AS monthly_storage_gb,
  -- Linear forecast: use avg growth rate from last 3 months
  ROUND(
    (SELECT row_count FROM growth_metrics WHERE month = CURRENT_DATE - INTERVAL 1 MONTH) 
    * POW(1 + (SELECT AVG(pct_growth)/100 FROM growth_metrics WHERE month >= CURRENT_DATE - INTERVAL 3 MONTH), 12),
    0
  ) AS projected_12month_rows,
  CASE 
    WHEN pct_growth > LAG(pct_growth, 1) OVER (ORDER BY month) THEN 'ACCELERATING'
    WHEN pct_growth < LAG(pct_growth, 1) OVER (ORDER BY month) * 0.8 THEN 'DECELERATING'
    ELSE 'STABLE'
  END AS growth_pattern
FROM growth_metrics
ORDER BY month;
```

## Notes

- **Mistake:** Extrapolating linear growth in exponential systems. Job postings during economic booms don't grow steadily—they spike. Always test fit (linear vs. polynomial vs. seasonal decomposition).
- **Mistake:** Planning only for storage; compute headroom matters equally. A 10x growth in rows might mean 100x growth in aggregation queries if query patterns change.
- **Adjacent skill:** Cost allocation and chargeback models—capacity planning feeds directly into showing teams what their growth actually costs.
- **Revisit:** Seasonal decomposition (STL, Prophet) once you have 12+ months of history. Hiring pipelines are textbook seasonal workloads.
- **Communication:** Document your assumptions (e.g., "assumes 5% monthly growth, does not account for M&A events") so stakeholders understand when the forecast breaks and who to notify.
