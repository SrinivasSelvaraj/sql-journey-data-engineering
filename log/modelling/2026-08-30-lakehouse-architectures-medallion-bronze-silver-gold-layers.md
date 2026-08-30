---
date: 2026-08-30
phase: modelling
topic: Lakehouse architectures: medallion bronze-silver-gold layers
---

# Lakehouse architectures: medallion bronze-silver-gold layers

*Data modelling and warehousing*

## Concept

A medallion lakehouse organizes data into three layers, each progressively refined: **Bronze** ingests raw data as-is (preserving history, minimal transformation); **Silver** cleanses, deduplicates, and standardizes it into conformed dimensions and facts; **Gold** aggregates Silver into domain-specific, business-ready tables optimized for analytics and reporting.

This matters because raw data is messy—typos, nulls, inconsistent formats, duplicates—and forcing analysts to handle cleanup in every query kills productivity and invites errors. Without layered governance, you'll see columns named ambiguously (is `salary` annual or hourly? USD or local?), calculations repeated across dashboards with different logic, and no audit trail of where numbers came from.

The medallion pattern enforces a contract: Gold tables are self-documenting enough that analysts query them without asking you what a column means. Silver acts as the single source of truth for cleaning logic, so fixes propagate everywhere. Bronze preserves raw history, letting you replay transformations if business rules change.

## Practice

**Problem:** You inherit `job_postings_fact` with `salary_year_avg` that includes nulls, outliers (e.g., $50M for an entry-level role), and inconsistent currency. Three dashboards are calculating "average salary" differently. You need a Gold-layer table analysts can trust.

```sql
-- GOLD layer: job_market_summary
CREATE TABLE gold.job_market_summary AS
SELECT
  DATE_TRUNC(job_posted_date, MONTH) AS job_posted_month,
  job_location,
  job_title_short,
  ROUND(
    AVG(salary_year_avg) FILTER (
      WHERE salary_year_avg BETWEEN 30000 AND 300000
    ),
    2
  ) AS median_salary_usd,
  COUNT(DISTINCT job_id) AS job_count,
  ROUND(
    100.0 * COUNTIF(job_work_from_home) / COUNT(*),
    1
  ) AS remote_job_pct,
  CURRENT_TIMESTAMP() AS dbt_loaded_at
FROM silver.job_postings
WHERE job_posted_date >= '2023-01-01'
GROUP BY 1, 2, 3;

COMMENT ON TABLE gold.job_market_summary IS
  'Monthly job market trends by location & title. Salary outliers (>$300k) excluded per business rule v2.1.';
COMMENT ON COLUMN gold.job_market_summary.median_salary_usd IS
  'USD, outlier-filtered, IQR method applied in Silver layer.';
```

## Notes

- **Over-normalizing Silver:** Don't copy OLTP schema into Silver; conform dimensions and facts so Gold queries are simple. If you're still joining 5 tables in Gold, Silver design needs work.
- **No lineage metadata:** Tag each Gold column with which Silver table(s) feed it. Crucial when business questions about data provenance arise (e.g., "why did Q3 revenue drop?").
- **Bridging to dbt:** dbt models map cleanly to medallion layers—use staging for Bronze→Silver, intermediate for logic, marts for Gold. Makes version control and testing automatic.
- **Timestamp discipline:** Add load timestamps (`dbt_loaded_at`) and source-data timestamps (`job_posted_date`) separately; analysts conflate them otherwise, breaking trend analysis.
- **Revisit:** Test cardinality assumptions in Silver (e.g., is `job_id` unique per row?); Gold aggregations fail silently if Silver dimensions are wrong.
