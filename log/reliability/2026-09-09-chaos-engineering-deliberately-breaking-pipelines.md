---
date: 2026-09-09
phase: reliability
topic: Chaos engineering: deliberately breaking pipelines
---

# Chaos engineering: deliberately breaking pipelines

*Quality, reliability and the professional layer*

## Concept

Chaos engineering in data pipelines means deliberately injecting failures—missing data, late arrivals, schema changes, resource exhaustion—to discover brittleness before production does. It separates pipeline *builders* from pipeline *owners*. A builder makes it work; an owner makes it work when it breaks.

Without this discipline, you discover failure modes in production: a job title with an unexpected NULL breaks downstream reporting; a date field arrives as a string instead of DATE; a table grows 10x overnight and your job times out. You react instead of design. Chaos engineering flips this: you *find* these scenarios in controlled environments, then add guards—explicit validates, retry logic, fallback schemas, resource limits.

The professional layer is acknowledging that data pipelines run in chaotic systems. Networks fail. Upstream schemas drift. Servers run out of memory. Your job is not to prevent chaos but to absorb it gracefully: fail fast with clear signals, alert the right people, and preserve data integrity even when something goes wrong.

## Practice

**Problem:** Your `job_postings_fact` table is populated hourly from an upstream API. Last week, the API started occasionally returning NULL for `salary_year_avg` and `job_work_from_home`, and sometimes `job_posted_date` arrives as a string ('2025-01-15') instead of a DATE. Your current pipeline assumes these are always valid. How do you inject chaos and protect against it?

```sql
-- Chaos test: simulate upstream degradation
WITH upstream_chaos AS (
  SELECT 
    job_id,
    job_title_short,
    CASE 
      WHEN RAND() < 0.05 THEN NULL 
      ELSE salary_year_avg 
    END AS salary_year_avg,
    CASE 
      WHEN RAND() < 0.03 THEN NULL 
      ELSE job_work_from_home 
    END AS job_work_from_home,
    CASE 
      WHEN RAND() < 0.02 THEN CAST(job_posted_date AS VARCHAR)
      ELSE job_posted_date 
    END AS job_posted_date,
    job_location
  FROM raw_job_postings
),
-- Protection layer: validate and quarantine bad records
validated AS (
  SELECT 
    job_id,
    job_title_short,
    salary_year_avg,
    COALESCE(job_work_from_home, FALSE) AS job_work_from_home,
    TRY_CAST(job_posted_date AS DATE) AS job_posted_date,
    job_location,
    CASE 
      WHEN salary_year_avg IS NULL THEN 'missing_salary'
      WHEN job_work_from_home IS NULL THEN 'missing_wfh'
      WHEN TRY_CAST(job_posted_date AS DATE) IS NULL THEN 'invalid_date'
      ELSE 'valid'
    END AS data_quality_flag
  FROM upstream_chaos
)
SELECT * FROM validated 
WHERE data_quality_flag = 'valid'
UNION ALL
SELECT *, 'quarantined' FROM validated 
WHERE data_quality_flag != 'valid';
```

The quarantine table lets you inspect failures; the `TRY_CAST` prevents the whole pipeline from crashing; the `COALESCE` for booleans sets a sensible default. Run this test regularly. When real chaos hits, you're ready.

## Notes

- **Confuse chaos testing with load testing.** Chaos is about *failure modes*; load testing is about capacity. Both matter, but they find different problems.
- **Start small and intentional.** Don't randomly corrupt everything. Target the fields and transitions you actually depend on downstream.
- **Connects to: observability, alerting, and SLOs.** You need visible signals (logs, metrics, alerts) so chaos doesn't just hide silently. Define what "acceptable" failure looks like.
- **Common mistake:** Testing only happy paths in dev, then deploying rigid pipelines to prod. Chaos engineering is how you test unhappy paths before they're unhappy.
- **Revisit:** Data contracts (schema versioning), idempotency (running the same job twice should be safe), and circuit breakers (fail gracefully rather than retry forever).
