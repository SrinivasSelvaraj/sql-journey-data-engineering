---
date: 2026-10-21
phase: reliability
topic: Circuit breaker state and health endpoints
---

# Circuit breaker state and health endpoints

*Quality, reliability and the professional layer*

## Concept

A **circuit breaker** is a pattern that stops your pipeline from hammering a failing downstream service. Instead of retrying infinitely against a dead API or database, it "opens" after N consecutive failures, fast-fails all subsequent requests, and periodically tests if the service has recovered. Without it, you cascade failures: your job gets stuck in retry loops, consumes compute resources, fills logs with noise, and delays detection of the real problem.

**Health endpoints** are lightweight, dedicated routes (often `/health` or `/status`) that your orchestrator or monitoring system polls to determine service readiness *before* sending real traffic. They return structured data: `{"status": "healthy", "checks": {"db": "ok", "cache": "degraded"}}`. This decouples liveness checks from business logic and gives you granular visibility into which dependencies are actually broken.

Together, they form the observability backbone of a production pipeline. Without them, you're flying blind: you don't know why a job hung, whether it's safe to retry, or which downstream team to notify. The professional difference is that amateurs treat failures as exceptions; engineers treat them as signals.

## Practice

**Problem:** Your daily job ingests job postings from an external API. The API has intermittent 5-minute outages. Currently, your pipeline retries 50 times over 2 hours, blocking the entire DAG. You need to fail fast, alert your team, and resume the next day without manual intervention.

```sql
-- Health check query: minimal query to validate connectivity and freshness
SELECT 
  'api_endpoint' AS check_name,
  CASE 
    WHEN last_successful_fetch > CURRENT_TIMESTAMP - INTERVAL '15 minutes' THEN 'healthy'
    ELSE 'degraded'
  END AS status,
  last_successful_fetch,
  error_count_last_hour
FROM pipeline_health_log
WHERE source_name = 'job_postings_api'
LIMIT 1;

-- Circuit breaker state tracking: log failures and decide whether to open the circuit
INSERT INTO circuit_breaker_state (source_name, state, failure_count, last_state_change)
SELECT 
  'job_postings_api',
  CASE 
    WHEN failure_count >= 3 THEN 'OPEN'
    WHEN failure_count > 0 AND CURRENT_TIMESTAMP - last_failure < INTERVAL '5 minutes' THEN 'HALF_OPEN'
    ELSE 'CLOSED'
  END,
  failure_count + 1,
  CURRENT_TIMESTAMP
FROM circuit_breaker_state
WHERE source_name = 'job_postings_api'
ON CONFLICT (source_name) DO UPDATE SET 
  failure_count = EXCLUDED.failure_count,
  state = EXCLUDED.state,
  last_state_change = EXCLUDED.last_state_change;

-- Guard clause in your ingestion job: check state before attempting fetch
SELECT COUNT(*) AS should_proceed
FROM circuit_breaker_state
WHERE source_name = 'job_postings_api'
  AND state != 'OPEN';
```

## Notes

- **Common mistake:** Treating health checks as binary pass/fail. Real systems degrade gracefully. Return partial status (`{"db": "ok", "cache": "timeout"}`) so the caller can make smart decisions, not just abort.

- **Retry vs. circuit breaker:** Retries are for transient errors (network hiccup). Circuit breakers are for systemic failures (service down). Use both: retry 2–3 times with backoff, then check the breaker state before escalating.

- **Connects to:** alerting policies, graceful degradation, observability patterns. A circuit breaker is useless without a dashboard or alert that tells you it opened.

- **State management:** Store circuit breaker state in a table or distributed cache, not in-memory. Your job can restart; the breaker's memory shouldn't.

- **Half-open state matters:** Don't jump from OPEN straight to CLOSED. A half-open state lets you test the service with a single request; only resume full traffic if it succeeds. This prevents thrashing.
