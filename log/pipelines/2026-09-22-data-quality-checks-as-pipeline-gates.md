---
date: 2026-09-22
phase: pipelines
topic: Data quality checks as pipeline gates
---

# Data quality checks as pipeline gates

*Pipelines and orchestration*

## Concept

Data quality checks are validation rules inserted into pipeline stages that block downstream processing when data falls outside acceptable bounds. They act as circuit breakers: if salary_year_avg is NULL for 40% of records, the pipeline halts rather than poisoning downstream analytics. Quality gates transform silent data rot into visible failures, making debugging fast and impact obvious.

Without gates, bad data propagates. A malformed date cascades into incorrect aggregations; a NULL salary silently becomes zero in some systems and excluded in others. Teams waste cycles tracking phantom bugs in logic when the real issue sits in the source. Gates shift the problem left: catch it at ingestion, fail the job, alert the owner, fix once.

Effective gates balance strictness with practicality. A "job_posted_date must be in the last 90 days" gate will catch clock skew; "salary_year_avg > 0" catches data entry errors. Gates should be versioned alongside schema changes and monitored—a gate that triggers 10 times a week has become noise and needs refinement.

## Practice

**Problem:** job_postings_fact loads daily. Over time, you notice salary_year_avg has growing NULLs, job_location contains "REMOTE" and actual city names inconsistently, and job_posted_date occasionally lands in the future. You need a gate that prevents loading when data quality drops.

```sql
WITH data_quality_checks AS (
  SELECT
    COUNT(*) AS total_rows,
    COUNT(CASE WHEN salary_year_avg IS NULL THEN 1 END) AS null_salary_count,
    COUNT(CASE WHEN salary_year_avg <= 0 THEN 1 END) AS invalid_salary_count,
    COUNT(CASE WHEN job_posted_date > CURRENT_DATE THEN 1 END) AS future_date_count,
    COUNT(CASE WHEN job_location IS NULL OR job_location = '' THEN 1 END) AS null_location_count
  FROM job_postings_fact
  WHERE job_posted_date >= CURRENT_DATE - INTERVAL '1 day'
)
SELECT
  CASE
    WHEN null_salary_count / total_rows::FLOAT > 0.15 THEN 'FAIL: >15% null salary'
    WHEN invalid_salary_count / total_rows::FLOAT > 0.05 THEN 'FAIL: >5% salary ≤ 0'
    WHEN future_date_count > 0 THEN 'FAIL: future-dated postings detected'
    WHEN null_location_count / total_rows::FLOAT > 0.10 THEN 'FAIL: >10% null location'
    ELSE 'PASS'
  END AS quality_gate_result,
  total_rows,
  null_salary_count,
  invalid_salary_count,
  future_date_count,
  null_location_count
FROM data_quality_checks;
```

If result is not 'PASS', the orchestrator (Airflow/dbt test) halts and alerts—no bad data loads.

## Notes

- **Thresholds are learned, not guessed.** Run baselines for 2 weeks, find the 95th percentile of "normal" variance, set gates slightly beyond that. Adjust as data source improves.
- **Gate failure needs context.** Log the check query result to a metadata table; include row counts, which columns failed, when it started failing. "FAIL" alone is not actionable.
- **Connect to observability.** Tie gates to alerting and SLOs. A gate firing for salary is a P2; job_location drift might be P4. Route alerts accordingly.
- **Versioning matters.** When you tighten a gate, document it in your pipeline DAG or dbt YAML. Six months later, junior engineers should understand *why* the gate exists.
- **Test your gates.** Inject bad data in dev; confirm the gate catches it. A gate that doesn't fail on intentionally broken data is worse than no gate.
