---
date: 2026-09-02
phase: pipelines
topic: Health checks and liveness probes for pipeline services
---

# Health checks and liveness probes for pipeline services

*Pipelines and orchestration*

## Concept

Health checks and liveness probes are automated signals that tell orchestrators whether a pipeline service is alive, responsive, and ready to process data. A health check is typically a lightweight HTTP endpoint or script that returns success/failure; a liveness probe is an orchestrator's periodic call to that endpoint (e.g., Kubernetes checking `/health` every 10 seconds). Without them, failed services sit silently—tasks queue indefinitely, downstream dependencies starve, and you discover the outage hours later in a Slack alert rather than during incident.

This matters most when pipelines are containerized or distributed across multiple workers. A service can be "running" (process alive) but actually deadlocked, out of memory, or stuck in an infinite loop. Liveness probes detect these zombie states and trigger restarts before data loss propagates. For a data pipeline, a failed health check should immediately halt new task assignments and trigger alerting, not wait for a timeout.

Without health checks, you lose observability into the *readiness* of your pipeline infrastructure. A warehouse loader might crash silently, a Spark cluster might exhaust memory but keep accepting jobs, or a database connection pool might be exhausted. The pipeline definition itself looks correct, but tasks fail mysteriously or hang. Health checks turn this into: "service became unhealthy at 14:32, auto-restarted, recovered by 14:33, see the log."

## Practice

**Problem:** Your daily job posting ingestion pipeline loads data into `job_postings_fact` from an API. The API client service runs in a container and can silently deadlock when the upstream API is slow. Tasks submitted to the service timeout without clear feedback, leaving data gaps. You need a health check endpoint and orchestrator probe to catch deadlock before it affects downstream reporting.

```sql
-- Health check stored procedure: verifies connectivity, recent data freshness, and transaction log
CREATE OR REPLACE PROCEDURE check_pipeline_health()
LANGUAGE plpgsql
AS $$
DECLARE
  v_last_load_time TIMESTAMP;
  v_row_count INT;
  v_status TEXT := 'healthy';
BEGIN
  -- Test 1: connectivity & permissions
  SELECT COUNT(*) INTO v_row_count FROM job_postings_fact LIMIT 1;
  
  -- Test 2: data freshness (last load within 25 hours)
  SELECT MAX(job_posted_date) INTO v_last_load_time FROM job_postings_fact;
  IF v_last_load_time < NOW() - INTERVAL '25 hours' THEN
    v_status := 'stale';
    RAISE WARNING 'Last load was %.', v_last_load_time;
  END IF;
  
  -- Test 3: transaction log is not bloated (proxy for service backlog)
  SELECT COUNT(*) INTO v_row_count FROM pg_stat_activity WHERE state = 'active';
  IF v_row_count > 10 THEN
    v_status := 'degraded';
    RAISE WARNING 'Too many active transactions: %', v_row_count;
  END IF;
  
  -- Return status so HTTP wrapper can respond with 200 (healthy) or 503 (unhealthy)
  RAISE NOTICE 'Pipeline health: %', v_status;
  RETURN;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'Health check failed: %', SQLERRM;
  -- Orchestrator interprets exception as unhealthy
END;
$$;
```

Then wrap this in a simple HTTP service (Python Flask or similar) that calls this procedure on `/health`, returns 200 if status='healthy', 503 otherwise. Configure your orchestrator (Airflow, Prefect, K8s) to call this every 30 seconds; if 3 probes fail, mark the service unhealthy and stop scheduling new jobs.

## Notes

- **Mistake:** Making health checks too heavy. A 30-second DB query that locks tables defeats the purpose. Keep probes lightweight: a simple connection ping, a cached timestamp check, or a heartbeat table update.

- **Mistake:** Confusing health checks (is it alive?) with data quality checks (is the data correct?). A service can be healthy but producing garbage. Health checks catch infrastructure failures; validation tests catch logic bugs.

- **Adjacency:** Ties directly to circuit breakers—if a service fails its health check, the circuit should open to prevent cascading failures downstream. Also connects to exponential backoff and retry policies for when services recover.

- **Restart strategy:** Liveness probes should trigger *quick* restarts (e.g., container restart, not a full pipeline re-run). Pair with idempotent writes or transaction isolation to ensure restart safety. A health-check-triggered restart is different from a job retry; the former fixes infrastructure, the latter retries work.

- **Worth revisiting:** Synthetic probes (injecting test data and verifying it flows through) are more reliable than passive checks but more expensive. As pipeline criticality grows, combine both: passive health checks for responsiveness, synthetic probes for correctness.
