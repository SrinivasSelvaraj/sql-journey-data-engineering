---
date: 2026-09-02
phase: pipelines
topic: Circuit breakers for downstream dependency failures
---

# Circuit breakers for downstream dependency failures

*Pipelines and orchestration*

## Concept

A circuit breaker is a pattern that detects repeated failures from a downstream dependency (API, database, service) and automatically stops sending requests to it, failing fast instead of cascading delays. In data pipelines, this prevents a single slow or broken source from hanging your entire orchestration—you'd rather fail loudly in 30 seconds than timeout after 15 minutes waiting for a third-party API that's already down.

Without circuit breakers, your pipeline enters a zombie state: tasks queue up, retry logic hammers the broken dependency, orchestrator resources pile up, and by the time you notice, your entire DAG is blocked. Circuit breakers typically have three states: *closed* (normal operation), *open* (stop trying, fail immediately), and *half-open* (test if the dependency recovered). They're especially critical when pulling from job boards, weather services, or vendor APIs that you don't control.

The implementation pattern is simple: track consecutive failures or response time thresholds, trip the breaker after hitting a threshold (e.g., 5 failures), then periodically test recovery. Most orchestrators (Airflow, dbt) support this via sensor tasks or custom operators; some data platforms bake it into connectors.

## Practice

**Problem:** Your `job_postings_fact` table ingests from an external careers API that occasionally goes down for maintenance. Every time it fails, your downstream analytics jobs wait and retry, blocking the whole pipeline for hours. You need to detect this quickly and skip the load, allowing dependent jobs to handle stale data gracefully.

```sql
-- Circuit breaker logic in a staging table
CREATE TABLE IF NOT EXISTS api_circuit_breaker (
  dependency_name STRING,
  status STRING,  -- 'closed', 'open', 'half-open'
  failure_count INT,
  last_failure_time TIMESTAMP,
  opened_at TIMESTAMP,
  next_test_time TIMESTAMP
);

-- Check circuit state before attempting load
INSERT INTO job_postings_fact
SELECT 
  job_id, job_title_short, salary_year_avg, 
  job_work_from_home, job_posted_date, job_location
FROM external_careers_api_source
WHERE (
  SELECT status FROM api_circuit_breaker 
  WHERE dependency_name = 'careers_api'
) = 'closed'
  OR (
  SELECT status FROM api_circuit_breaker 
  WHERE dependency_name = 'careers_api'
) = 'half-open' 
  AND CURRENT_TIMESTAMP > (SELECT next_test_time FROM api_circuit_breaker WHERE dependency_name = 'careers_api')
;

-- Update circuit breaker on successful load
UPDATE api_circuit_breaker 
SET status = 'closed', failure_count = 0 
WHERE dependency_name = 'careers_api';

-- On failure, increment and potentially trip
UPDATE api_circuit_breaker 
SET failure_count = failure_count + 1, 
    last_failure_time = CURRENT_TIMESTAMP,
    status = CASE WHEN failure_count >= 5 THEN 'open' ELSE status END,
    opened_at = CASE WHEN failure_count >= 5 THEN CURRENT_TIMESTAMP ELSE opened_at END,
    next_test_time = CASE WHEN failure_count >= 5 THEN DATE_ADD(CURRENT_TIMESTAMP, INTERVAL 5 MINUTE) ELSE next_test_time END
WHERE dependency_name = 'careers_api';
```

## Notes

- **Common mistake:** Only implementing retry logic without circuit breaking; this masks the real problem and wastes orchestrator resources. Always pair them—retry fast paths, circuit-break persistent failures.
- **State management matters:** Store circuit state in a durable location (metadata table, Redis, Airflow Variable) so all tasks see the same state; in-memory state is useless across distributed workers.
- **Half-open testing:** Set a reasonable recovery window (5–10 min) before exiting the open state; too short means thrashing the broken dependency, too long means unnecessary downtime.
- **Adjacent topics:** Ties directly to backpressure handling, graceful degradation, and fallback logic (e.g., using cached data when the API is open). Also relates to monitoring and alerting—circuit trips should trigger a page.
- **Orchestrator native support:** Airflow's `ExternalTaskSensor` with timeout + Airflow Variables can implement this; dbt's `require_select_statement` gates downstream models; both save you from hand-rolling.
