---
date: 2026-08-16
phase: reliability
topic: Observability: freshness, volume, schema, distribution
---

# Observability: freshness, volume, schema, distribution

*Quality, reliability and the professional layer*

## Concept

Observability in data pipelines means instrumenting your system to continuously measure four dimensions of data quality: **freshness** (how current is the data?), **volume** (are we getting the expected row counts?), **schema** (are columns present and correctly typed?), and **distribution** (does the data look statistically normal or has something shifted?). Without these signals, you discover problems reactively—a downstream dashboard breaks, a model fails silently, or a business decision gets made on stale data. With observability, you catch degradation before it reaches users.

The difference between someone who *builds* pipelines and someone *trusted to own* them is whether they tolerate surprise failures. Builders assume upstream data is stable; owners assume it will break in weird ways. Observability transforms data pipelines from black boxes into systems with visible health—you can answer "is this pipeline healthy right now?" in seconds, not hours. This requires embedding monitoring logic directly into your ELT/ETL workflows, not bolting it on afterward.

Freshness checks (how old is the newest record?), volume anomalies (did we lose 50% of rows?), schema validation (did a new NULL column appear?), and distribution shifts (did salary suddenly drop 30%?) each catch different failure modes. A pipeline can pass schema validation, have correct volumes, and still be dangerous if the distribution of sensitive fields has drifted or freshness has silently degraded. Ownership means instrumenting all four.

## Practice

**Problem:** Your `job_postings_fact` table is used by a salary prediction model. Last week, a deploy broke upstream ingestion but your pipeline still ran—it loaded yesterday's data, passing volume and schema checks. The model made predictions on stale data for two days before anyone noticed. How do you prevent this?

```sql
-- Observability checks integrated into your pipeline
WITH data_quality AS (
  SELECT
    -- Freshness: max date should be today or yesterday
    MAX(job_posted_date) as latest_post_date,
    CURRENT_DATE - MAX(job_posted_date) as days_stale,
    
    -- Volume: check row count hasn't dropped unexpectedly
    COUNT(*) as row_count,
    COUNT(*) - LAG(COUNT(*)) OVER (ORDER BY CURRENT_DATE) as volume_change,
    
    -- Schema: validate key columns exist and have content
    COUNT(DISTINCT job_id) as unique_jobs,
    COUNT(CASE WHEN salary_year_avg IS NULL THEN 1 END) as null_salaries,
    
    -- Distribution: detect shifts in salary range
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY salary_year_avg) as median_salary,
    PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY salary_year_avg) as p95_salary
  FROM job_postings_fact
  WHERE job_posted_date >= CURRENT_DATE - 7
)
SELECT
  CASE
    WHEN days_stale > 1 THEN 'ALERT: Data is stale'
    WHEN volume_change < -0.2 * LAG(row_count) OVER (ORDER BY CURRENT_DATE) THEN 'ALERT: Volume dropped >20%'
    WHEN null_salaries > 0.1 * row_count THEN 'ALERT: >10% nulls in salary'
    WHEN median_salary < (SELECT median_salary FROM data_quality LIMIT 1 OFFSET 7) * 0.8 THEN 'ALERT: Median salary dropped 20%+'
    ELSE 'PASS'
  END as data_quality_status,
  *
FROM data_quality;
```

Embed this as a post-load check in your DAG. Fail the pipeline or alert ops if status != 'PASS'. Log these metrics to your observability backend (Datadog, New Relic, etc.) so you see trends, not just snapshots.

## Notes

- **Common mistake:** Checking only volume and schema. A pipeline can have correct counts and structure while distributions shift silently. Salary could drop 40%, freshness could drift by 6 hours—both invisible to basic schema validation.

- **Freshness is non-negotiable for ownership.** If your pipeline depends on upstream data that updates daily, a stale check (MAX date < TODAY) is your smoke test. It catches 80% of production failures.

- **Distribution drift connects to model monitoring.** If your data distribution shifts, downstream ML models will degrade. This is why data owners and ML engineers must share observability infrastructure—they're watching the same signal.

- **Volume baselines must account for seasonality.** A 10% drop on weekends is normal; a 10% drop mid-week is a problem. Use rolling averages or historical percentiles, not fixed thresholds.

- **Revisit:** SLA definition (what does "healthy" mean for your use case?), alerting fatigue (avoid alarm bells that cry wolf), and instrument-as-you-build (observability bolted on later is maintenance debt).
