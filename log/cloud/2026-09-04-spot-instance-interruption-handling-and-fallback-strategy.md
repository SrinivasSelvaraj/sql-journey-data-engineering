---
date: 2026-09-04
phase: cloud
topic: Spot instance interruption handling and fallback strategy
---

# Spot instance interruption handling and fallback strategy

*Cloud platforms and storage*

## Concept

Spot instances offer 70–90% cost savings on cloud compute by letting cloud providers reclaim capacity with minimal notice (often seconds to minutes). However, interruptions are inevitable—AWS can terminate a Spot instance at any time, and workloads without fallback logic fail mid-execution, losing progress and money.

A fallback strategy combines stateless job design, checkpointing, and automatic retry with On-Demand escalation. When a Spot instance is interrupted, the job either resumes from a saved checkpoint or reruns entirely on On-Demand capacity. This matters for long-running analytics jobs, ETL pipelines, and batch queries where interruption probability is non-zero over hours of execution.

Without fallback handling, you face data inconsistency (partial writes), wasted compute spend (retrying from scratch), and SLA violations. With it, interruptions become transparent overhead rather than failures.

## Practice

**Problem:** A nightly batch job aggregates job postings data and computes average salary by location. The job runs on Spot instances to save costs, but interruptions cause the aggregation to fail, leaving the daily report incomplete.

```sql
-- Checkpointing approach: write intermediate results to a durable table
CREATE TABLE job_salary_agg_checkpoint (
  location VARCHAR,
  avg_salary DECIMAL,
  record_count INT,
  processed_date DATE,
  checkpoint_time TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Main aggregation: insert or overwrite from checkpoint
INSERT INTO job_salary_agg_checkpoint
SELECT 
  job_location,
  AVG(salary_year_avg) AS avg_salary,
  COUNT(*) AS record_count,
  CAST(job_posted_date AS DATE) AS processed_date,
  CURRENT_TIMESTAMP
FROM job_postings_fact
WHERE CAST(job_posted_date AS DATE) = CURRENT_DATE
  AND salary_year_avg IS NOT NULL
GROUP BY job_location, CAST(job_posted_date AS DATE);

-- Fallback: if Spot fails, query reruns on On-Demand and resumes from checkpoint
-- Application logic: catch interruption signal, write state, retry with On-Demand flag
```

## Notes

- **Statelessness first**: Design jobs to be restartable—avoid relying on local ephemeral storage or in-memory state.
- **Checkpoint granularity matters**: Too frequent checkpoints waste I/O; too infrequent means large replay overhead. Partition by time or batch size.
- **Cost vs. reliability tradeoff**: Spot + fallback to On-Demand is cheaper than pure On-Demand but more complex. Estimate interruption probability for your region/instance type.
- **Monitor Spot pricing and capacity**: Use CloudWatch for interruption rates and price history; set Spot price cap alerts to avoid surprise On-Demand escalations.
- **Adjacent topics**: Retry logic and exponential backoff, multi-region failover, data idempotency (ensure re-running aggregations doesn't double-count), and infrastructure-as-code for fast On-Demand provisioning.
