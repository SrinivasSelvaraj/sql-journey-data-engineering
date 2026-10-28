---
date: 2026-10-28
phase: pipelines
topic: Data validation gates between pipeline stages
---

# Data validation gates between pipeline stages

*Pipelines and orchestration*

## Concept

Data validation gates are checkpoints inserted between pipeline stages that verify data quality, schema integrity, and business logic before allowing downstream processing. They catch issues early—malformed records, schema violations, or nonsensical values—preventing bad data from cascading through dependent systems and corrupting dashboards or ML features.

Without validation gates, you discover problems too late: a ETL job succeeds silently despite ingesting nulls where they shouldn't exist, or salary values become negative after a transformation, and weeks later an analyst notices the metrics are wrong. Validation gates make pipelines "fail loudly"—they stop immediately when assumptions are violated, triggering alerts and reruns.

Effective gates check three layers: *schema* (column types, presence), *quality* (nullness, ranges, uniqueness), and *business logic* (salary > 0, job_posted_date ≤ today). They should live as explicit stage transitions in your orchestration tool (dbt tests, Airflow sensors, or SQL assertions) so they're visible, versioned, and rerunnable.

## Practice

**Problem:** Your `job_postings_fact` loads raw data daily. Recently, a data quality issue slipped through: some records have `salary_year_avg = -1`, `job_posted_date` in the future, or `job_work_from_home` as string values instead of boolean. By the time a dashboard showed negative salaries, 3 days of bad data had been published.

**Solution:** Insert a validation gate before materializing the fact table.

```sql
-- Validation gate: run before fact table load
WITH validation AS (
  SELECT
    COUNT(*) as total_rows,
    SUM(CASE WHEN salary_year_avg IS NOT NULL 
             AND salary_year_avg <= 0 THEN 1 ELSE 0 END) as invalid_salaries,
    SUM(CASE WHEN job_posted_date > CURRENT_DATE THEN 1 ELSE 0 END) as future_dates,
    SUM(CASE WHEN job_work_from_home NOT IN (true, false) 
             OR job_work_from_home IS NULL THEN 1 ELSE 0 END) as invalid_booleans
  FROM staging.job_postings_raw
)
SELECT
  CASE
    WHEN invalid_salaries > 0 THEN 'FAIL: ' || invalid_salaries || ' rows with salary <= 0'
    WHEN future_dates > 0 THEN 'FAIL: ' || future_dates || ' rows with future posted_date'
    WHEN invalid_booleans > 0 THEN 'FAIL: ' || invalid_booleans || ' rows with invalid work_from_home'
    ELSE 'PASS: All validations succeeded. Rows: ' || total_rows
  END as validation_result,
  total_rows
FROM validation
HAVING validation_result LIKE 'FAIL%';
-- If this query returns rows, the pipeline stops and alerts.
```

## Notes

- **Threshold tuning:** Set allowances for small percentages of bad data (e.g., allow 0.1% nulls if expected) to avoid hair-trigger failures; document thresholds in your validation logic.
- **Version your checks:** Store validation rules in version control alongside transformations; changes to validation logic are as important as code reviews.
- **Connect to orchestration:** Expose validation results as task dependencies in Airflow/dbt Cloud so failed gates block downstream jobs; avoid silent passes.
- **Rerun safety:** Design validation gates to be idempotent—running twice with the same input should produce identical results, enabling safe retries without side effects.
- **Adjacent topics:** ties closely to *data lineage tracking* (knowing which gate failed helps trace root cause), *SLA monitoring* (gates feed alerting), and *schema versioning* (validation catches schema drift early).
