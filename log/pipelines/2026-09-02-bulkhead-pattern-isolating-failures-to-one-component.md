---
date: 2026-09-02
phase: pipelines
topic: Bulkhead pattern: isolating failures to one component
---

# Bulkhead pattern: isolating failures to one component

*Pipelines and orchestration*

## Concept

The bulkhead pattern isolates work into independent containers so that failure in one doesn't cascade to others. In data pipelines, this means separating concerns—compute, storage, connections, threads, processes—so that a slow external API, a malformed dataset, or resource exhaustion doesn't bring down your entire system. Without it, one stalled task blocks downstream jobs, resource contention causes cascading timeouts, or a single bad transformation corrupts the entire pipeline run.

In practice, bulkheads manifest as separate connection pools for different data sources, dedicated compute slots for different job types, independent retry logic per stage, and isolated staging tables rather than shared scratch space. When a third-party job posting API times out, your bulkhead ensures it doesn't starve the local database transformation or block the email notification service. The pipeline fails loudly in that one component—visible and fixable—rather than silently propagating corruption downstream.

## Practice

**Problem:** A nightly pipeline loads job postings from three sources: an internal database, a REST API (flaky, slow), and a CSV upload. All three stages write to the same staging table and share a single connection pool. When the API is slow, it blocks the CSV loader; when the CSV loader encounters bad dates, it corrupts the staging table and breaks the final merge into `job_postings_fact`.

**Solution:**

```sql
-- Bulkhead 1: Separate staging tables per source
CREATE TABLE job_postings_stg_internal AS
SELECT job_id, job_title_short, salary_year_avg, job_work_from_home, job_posted_date, job_location
FROM internal_db.jobs
WHERE job_posted_date >= CURRENT_DATE - INTERVAL 7 DAY;

-- Bulkhead 2: Isolated error handling for flaky API source
CREATE TABLE job_postings_stg_api AS
SELECT 
  job_id, job_title_short, salary_year_avg, job_work_from_home, 
  TRY_CAST(job_posted_date AS DATE) AS job_posted_date,
  job_location
FROM (
  SELECT * FROM api_json_extract WHERE source = 'external_api' AND loaded_at = CURRENT_DATE
)
WHERE job_posted_date IS NOT NULL; -- Reject bad rows, don't fail the whole stage

-- Bulkhead 3: Separate path for CSV with strict validation
CREATE TABLE job_postings_stg_csv AS
SELECT job_id, job_title_short, salary_year_avg, job_work_from_home, job_posted_date, job_location
FROM csv_upload
WHERE job_posted_date >= '1900-01-01' AND salary_year_avg > 0; -- Validate, skip bad records

-- Bulkhead 4: Independent merge, each source can fail independently
INSERT INTO job_postings_fact
SELECT * FROM job_postings_stg_internal
UNION ALL
SELECT * FROM job_postings_stg_api
UNION ALL
SELECT * FROM job_postings_stg_csv;
```

## Notes

- **Separate by failure domain, not just by table.** Use different connection pools, thread pools, or worker processes for each source. Set timeouts per source based on SLA, not globally.
- **Failing loudly means incomplete is better than corrupt.** The CSV bulkhead skips bad rows instead of failing the entire stage; the API bulkhead time-outs and logs rather than retrying forever.
- **Connects to circuit breakers and retry strategies.** A bulkhead isolates scope; a circuit breaker stops retrying; backpressure and queues prevent resource starvation. Use together.
- **Revisit resource allocation.** Bulkheads only work if each compartment has its own quota (memory, CPU, connections). Shared resources defeat the pattern.
- **Monitor per-bulkhead metrics.** Track success rate, latency, and row counts per source/stage. This is how you know *which* bulkhead failed, not just that something went wrong.
