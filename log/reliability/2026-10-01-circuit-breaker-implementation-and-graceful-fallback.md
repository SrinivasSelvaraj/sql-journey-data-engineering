---
date: 2026-10-01
phase: reliability
topic: Circuit breaker implementation and graceful fallback
---

# Circuit breaker implementation and graceful fallback

*Quality, reliability and the professional layer*

## Concept

A circuit breaker is a pattern that stops calling a failing external service and returns a safe default or cached response instead of repeatedly hitting a wall. In data pipelines, this means detecting when an API, database, or downstream system is degraded and switching to fallback logic—a cached result, a previous successful run's output, or a sensible default—rather than cascading the failure upstream.

This matters because production pipelines touch many systems. When a third-party job board API goes down mid-run, a naive pipeline fails entirely. A circuit breaker detects the failure after a threshold (e.g., 3 consecutive timeouts), stops hammering the service, and either returns stale-but-useful data or skips enrichment gracefully. Without this, you waste compute, hammer struggling services further, and wake up on-call engineers at 2am for problems that didn't need to propagate.

The difference between "someone who builds pipelines" and "someone trusted to own them" is often just this: anticipating and handling the failures that *will* happen, not the ones you hope won't.

## Practice

**Problem:** Your pipeline enriches `job_postings_fact` by calling an external salary API to fill in `salary_year_avg`. The API is flaky—it times out ~5% of the time. Today it's down entirely. Your ETL either waits 30 seconds per row and fails, or skips salary data and reruns tomorrow. You need resilience.

```sql
-- Circuit breaker pattern: detect failure, fall back to last-known-good
WITH job_source AS (
  SELECT job_id, job_title_short, job_posted_date, job_location
  FROM raw.job_postings_staging
  WHERE job_posted_date = CURRENT_DATE
),
salary_attempt AS (
  -- Try enrichment; mark attempts with a status flag
  SELECT 
    job_id,
    TRY_CAST(api_salary_lookup(job_title_short, job_location) AS INT) AS salary_year_avg,
    CASE 
      WHEN api_salary_lookup(job_title_short, job_location) IS NULL THEN 'api_failed'
      ELSE 'api_success'
    END AS lookup_status
  FROM job_source
),
fallback_salary AS (
  -- On API failure, use rolling 30-day median for same title
  SELECT 
    sa.job_id,
    sa.salary_year_avg,
    COALESCE(
      sa.salary_year_avg,
      PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY jpf.salary_year_avg) 
        OVER (PARTITION BY sa.job_title_short 
              ORDER BY CURRENT_DATE ROWS BETWEEN 30 PRECEDING AND 1 PRECEDING)
    ) AS salary_resolved,
    CASE 
      WHEN sa.salary_year_avg IS NOT NULL THEN 'live'
      ELSE 'fallback'
    END AS salary_source
  FROM salary_attempt sa
  LEFT JOIN job_postings_fact jpf 
    ON sa.job_title_short = jpf.job_title_short
),
insert_target AS (
  SELECT 
    fs.job_id,
    js.job_title_short,
    fs.salary_resolved AS salary_year_avg,
    js.job_work_from_home,
    js.job_posted_date,
    js.job_location,
    fs.salary_source,
    CURRENT_TIMESTAMP AS load_ts
  FROM fallback_salary fs
  JOIN job_source js USING (job_id)
)
INSERT INTO job_postings_fact
SELECT job_id, job_title_short, salary_year_avg, job_work_from_home, job_posted_date, job_location
FROM insert_target;

-- Log what happened for observability
INSERT INTO pipeline_metrics (stage, metric_name, metric_value, run_ts)
SELECT 
  'salary_enrichment',
  'fallback_rate',
  COUNT(*) FILTER (WHERE salary_source = 'fallback') * 100.0 / COUNT(*),
  CURRENT_TIMESTAMP
FROM insert_target;
```

## Notes

- **Common mistake:** Setting circuit breaker thresholds too tight (fail after 1 error) or too loose (fail after 100). Start with 3–5 consecutive failures or error rate >10% over a 5-minute window; tune from production metrics.
- **Observability is non-negotiable:** Always log when you activate fallback—which rows, which systems, how stale the data is. Without this, you'll debug blind.
- **Adjacent patterns:** Retry with exponential backoff (try 3 times before opening circuit), bulkheads (isolate salary enrichment failures from location enrichment), and async dead-letter queues (park un-enriched rows for later replay).
- **Fallback strategy matters:** Cached data ages differently than API errors. A salary from 60 days ago may be stale; a salary API
