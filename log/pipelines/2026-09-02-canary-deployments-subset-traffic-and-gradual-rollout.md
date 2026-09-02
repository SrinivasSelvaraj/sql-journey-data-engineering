---
date: 2026-09-02
phase: pipelines
topic: Canary deployments: subset traffic and gradual rollout
---

# Canary deployments: subset traffic and gradual rollout

*Pipelines and orchestration*

## Concept

A canary deployment routes a small percentage of production traffic to a new version of a service or pipeline, monitoring for errors before rolling out to 100%. This catches silent failures—schema mismatches, performance regressions, logic bugs—without taking down the entire system. In data pipelines, it means running your transformation on a subset of incoming data (e.g., 5% of records) in parallel with the old version, comparing outputs to detect drift before the new code touches all records.

It matters most when your pipeline feeds critical downstream dashboards, ML models, or operational systems. Without it, a subtle bug in a new aggregation logic or a breaking change in upstream data can corrupt weeks of historical fact tables. The cost of rollback—recreating derived tables, reprocessing dependencies, notifying stakeholders—is high enough that catching issues at 5% traffic is worth the complexity.

Canary deployments fail silently when you don't instrument them: you need automated alerts on row counts, null rates, schema violations, and output freshness for both the canary and control groups. Without explicit comparison logic, you'll deploy the bug anyway and only notice it three days later in a dashboard.

## Practice

**Problem:** Your `job_postings_fact` table receives 10,000 new rows daily. A refactored ETL pipeline now computes `salary_year_avg` using a new vendor API instead of the old lookup table. You want to deploy this without risking salary corruption for all jobs. Run the new logic on 10% of incoming job postings, compare the results to the old method, and only promote to 100% if medians and null rates match.

```sql
-- Canary: new pipeline runs on 10% sample
WITH canary_sample AS (
  SELECT job_id, job_title_short, job_posted_date, job_location
  FROM job_postings_raw
  WHERE job_posted_date = CURRENT_DATE
    AND FARM_FINGERPRINT(CAST(job_id AS STRING)) % 10 < 1  -- 10% deterministic sample
),
new_salary_logic AS (
  SELECT 
    job_id,
    COALESCE(vendor_api.lookup_salary(job_title_short, job_location), 0) AS salary_year_avg_new
  FROM canary_sample
  LEFT JOIN vendor_api USING (job_title_short, job_location)
),
control_group AS (
  SELECT 
    job_id,
    salary_year_avg AS salary_year_avg_old
  FROM job_postings_fact
  WHERE job_posted_date = CURRENT_DATE
    AND FARM_FINGERPRINT(CAST(job_id AS STRING)) % 10 < 1
),
comparison AS (
  SELECT 
    COUNT(*) AS row_count,
    COUNTIF(salary_year_avg_new IS NULL) AS nulls_new,
    COUNTIF(salary_year_avg_old IS NULL) AS nulls_old,
    APPROX_QUANTILES(salary_year_avg_new, 100)[OFFSET(50)] AS median_new,
    APPROX_QUANTILES(salary_year_avg_old, 100)[OFFSET(50)] AS median_old,
    ABS(APPROX_QUANTILES(salary_year_avg_new, 100)[OFFSET(50)] 
        - APPROX_QUANTILES(salary_year_avg_old, 100)[OFFSET(50)]) / 
        APPROX_QUANTILES(salary_year_avg_old, 100)[OFFSET(50)] AS median_pct_diff
  FROM new_salary_logic n
  FULL OUTER JOIN control_group c ON n.job_id = c.job_id
)
SELECT * FROM comparison
WHERE median_pct_diff > 0.05 OR ABS(nulls_new - nulls_old) > 10
-- Alert if medians diverge >5% or null count shifts by >10 rows
```

## Notes

- **Instrumentation is the canary's spine**: without alerting on medians, null rates, and cardinality, you're flying blind. Automate these checks and fail the pipeline if thresholds breach.
- **Deterministic sampling matters**: use `FARM_FINGERPRINT(job_id) % N` to ensure the same 10% of jobs always go to canary, enabling reproducible comparisons across runs.
- **Connect to feature flags and circuit breakers**: canary deployments pair with runtime feature toggles (e.g., `IF config.use_new_salary_api THEN ... ELSE ...`) so you can kill the rollout without redeploying code.
- **Canary duration depends on SLA**: if your pipeline runs daily, run canary for 3–7 days before promoting. High-volume streaming pipelines might only need hours.
- **Revisit: blue-green deployments for zero-downtime table swaps, and observability hooks** (logging job IDs that diverge between old/new) so root cause analysis is fast when drift appears.
