---
date: 2026-09-20
phase: pipelines
topic: Backpressure and flow control in pipelines
---

# Backpressure and flow control in pipelines

*Pipelines and orchestration*

## Concept

Backpressure is the mechanism that prevents a data pipeline from overwhelming downstream systems when producers generate data faster than consumers can process it. Without it, you accumulate unbounded queues, memory bloat, and cascading failures that are hard to trace. In orchestration tools like Airflow or dbt, backpressure manifests as task dependency constraints, connection pooling limits, and explicit rate-limiting logic that force producers to slow down or pause until consumers catch up.

Flow control operationalizes backpressure by setting concrete boundaries: max task parallelism, batch sizes, retry policies with exponential backoff, and queue depth monitoring. A real scenario: your CDC pipeline ingests 100k job posting records/minute, but your fact table denormalization job can only handle 10k/minute. Without flow control, rows queue endlessly in Kafka or your staging layer, memory spills to disk, and latency balloons to hours. With it, the ingestion task waits or throttles until the denormalization task finishes its batch.

The key insight is that **failure under backpressure is visible and recoverable**—tasks block or timeout predictably—whereas silent resource exhaustion causes phantom failures downstream. This ties directly to "fail loudly": backpressure forces you to acknowledge capacity constraints explicitly in your DAG design.

## Practice

**Problem:** Your job postings pipeline receives a spike of 50k new postings in one hour. The `job_postings_fact` table gets updated via a merge job that runs every 5 minutes, but each merge takes 8 minutes during peak load. Without flow control, staging tables overflow, the merge job times out sporadically, and downstream salary analyses see stale data for hours.

**Solution:** Implement a staged ingestion with explicit batch sizing and backpressure check:

```sql
-- Stage 1: Ingest into a bounded landing layer
INSERT INTO job_postings_landing
SELECT job_id, job_title_short, salary_year_avg, job_work_from_home, 
       job_posted_date, job_location, CURRENT_TIMESTAMP() AS ingested_at
FROM external_feed
WHERE ingested_at > (SELECT MAX(ingested_at) FROM job_postings_landing)
LIMIT 5000;  -- Batch size: 5k rows per ingest task

-- Stage 2: Merge only if landing layer is within backpressure threshold
BEGIN TRANSACTION;
IF (SELECT COUNT(*) FROM job_postings_landing WHERE processed = FALSE) <= 10000 THEN
  MERGE INTO job_postings_fact t
  USING (
    SELECT * FROM job_postings_landing 
    WHERE processed = FALSE
    ORDER BY ingested_at
    LIMIT 5000
  ) s
  ON t.job_id = s.job_id
  WHEN MATCHED THEN UPDATE SET 
    job_title_short = s.job_title_short, 
    salary_year_avg = s.salary_year_avg,
    job_work_from_home = s.job_work_from_home,
    job_posted_date = s.job_posted_date,
    job_location = s.job_location
  WHEN NOT MATCHED THEN INSERT *;
  
  UPDATE job_postings_landing SET processed = TRUE WHERE processed = FALSE;
ELSE
  -- Backpressure: pause ingest, alert ops
  ROLLBACK;
END IF;
END TRANSACTION;
```

In Airflow: set `max_active_tasks=2` on the ingest DAG, make the merge task a hard dependency, and configure task pool to `job_pipeline_pool: 5`.

## Notes

- **Mistaking queue depth for latency:** A 50k-row queue with 10k/min throughput means 5 minutes of backlog, not instant stale data. Monitor queue depth explicitly in your observability stack.
- **Exponential backoff vs. linear retry:** Default Airflow retries are linear (fixed delay). Switch to exponential backoff for external API calls and database contention to avoid thundering herd when a system recovers.
- **Connection pooling is backpressure:** Setting `pool_size=10` on your database connection forces tasks to queue for connections; this is a form of backpressure, not a bug. Size it based on your database's max connections, not your task count.
- **Relates to:** SLA enforcement (backpressure without SLAs is just queueing), idempotency (without it, retries on backpressure cause duplicates), and circuit-breaker patterns (fail fast when downstream is saturated).
- **Worth revisiting:** How to emit backpressure metrics to monitoring (queue depth, task wait time, pool utilization) and tune batch sizes empirically rather than by guesswork.
