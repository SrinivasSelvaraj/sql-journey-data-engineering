---
date: 2026-10-19
phase: reliability
topic: Chaos engineering and fault injection testing
---

# Chaos engineering and fault injection testing

*Quality, reliability and the professional layer*

## Concept

Chaos engineering is the practice of deliberately injecting failures into production systems to discover weaknesses before they cause real incidents. In data pipelines, this means simulating network timeouts, corrupted data, missing dependencies, late-arriving facts, and schema changes—then verifying your pipeline handles them gracefully. Without it, you discover fragility in production: a job posting with a NULL salary crashes your aggregation, a delayed upstream table causes downstream reports to serve stale data, or a schema migration breaks your transformation silently.

This matters because pipelines are often treated as "set and forget," yet they're deeply coupled to upstream data quality and downstream business decisions. A pipeline owner doesn't just write code that works on day one; they design systems that fail *visibly and safely* when reality diverges from assumptions. The difference between a pipeline builder and a trusted pipeline owner is that the latter has anticipated failure modes and embedded recovery logic.

Practical chaos engineering for data pipelines involves: testing NULL handling in critical columns, simulating delayed table arrivals, injecting malformed records, verifying alerts trigger before user-facing impact, and documenting recovery procedures. It moves you from "my pipeline works" to "my pipeline works *and I know what breaks it*."

## Practice

**Problem:** Your `job_postings_fact` table feeds a salary dashboard. The `salary_year_avg` column occasionally contains NULL values or outliers (data entry errors, contract roles). Without fault injection testing, these silently distort averages. Design a query that identifies and isolates poisoned records while preserving pipeline continuity.

```sql
-- Chaos engineering test: inject bad data and handle it
WITH raw_data AS (
  SELECT 
    job_id,
    job_title_short,
    salary_year_avg,
    job_work_from_home,
    job_posted_date,
    job_location,
    CASE 
      WHEN salary_year_avg IS NULL THEN 'missing_salary'
      WHEN salary_year_avg < 20000 THEN 'suspiciously_low'
      WHEN salary_year_avg > 500000 THEN 'suspiciously_high'
      ELSE 'valid'
    END AS data_quality_flag
  FROM job_postings_fact
),
valid_records AS (
  SELECT * FROM raw_data
  WHERE data_quality_flag = 'valid'
),
poisoned_records AS (
  SELECT * FROM raw_data
  WHERE data_quality_flag != 'valid'
)
SELECT 
  COUNT(*) as valid_count,
  (SELECT COUNT(*) FROM poisoned_records) as poisoned_count,
  ROUND(100.0 * (SELECT COUNT(*) FROM poisoned_records) / COUNT(*), 2) as poison_percentage
FROM raw_data;

-- Safe aggregation: downstream queries consume only valid_records
-- Alert if poison_percentage > 5%
```

## Notes

- **Silent failures are worse than loud ones:** A pipeline that drops bad records without logging is a liability. Emit data quality metrics to monitoring; let operators decide on thresholds.
- **Chaos testing isn't just for prod:** Run fault injection in staging with synthetic poisoned datasets. Validate recovery paths before they matter.
- **Adjacent topics:** observability (metrics, alerts, logging), contract testing (schema expectations), idempotency (safe retries), and dead-letter queues (where bad records go instead of failing the entire run).
- **Common mistake:** Testing only the happy path. If your pipeline assumes `salary_year_avg` is always numeric and non-null, you haven't tested your pipeline—you've tested ideal data.
- **Worth revisiting:** SLOs (service-level objectives) for pipelines—define acceptable latency, correctness, and completeness, then design chaos scenarios that verify you meet them under stress.
