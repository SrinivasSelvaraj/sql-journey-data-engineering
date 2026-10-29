---
date: 2026-10-29
phase: pipelines
topic: Distributed task execution and resource allocation
---

# Distributed task execution and resource allocation

*Pipelines and orchestration*

## Concept

Distributed task execution allocates work across multiple workers (processes, containers, nodes) while resource allocation ensures each task gets the CPU, memory, and time it needs without starving or crashing the system. In data pipelines, this matters because a single machine often cannot process terabytes of data or run hundreds of jobs simultaneously. Without proper distribution, bottlenecks emerge: long-running transformations block downstream tasks, resource contention causes out-of-memory failures, and uneven load distribution leaves some workers idle while others melt down.

The key tension is *dependency awareness*—tasks that depend on each other must run in order, but independent tasks should run in parallel. A scheduler (Airflow, dbt, Spark) tracks these DAG edges and assigns tasks to available resources. Poor allocation manifests as: tasks queued indefinitely (undersized worker pool), memory spikes that crash containers (no per-task limits), or cascading failures where one retry loops consume all retry budget, blocking the entire pipeline.

Real-world example: if you parallelize 50 job_postings aggregations without setting memory limits, 30 may run at once and exhaust system RAM, killing the process. With proper queuing and per-task resource requests, you run only 5 at a time, each getting 2GB memory, and finish safely in more time but without crashes.

## Practice

**Problem:** You have 100,000 job postings loaded daily. You need to compute three summaries in parallel: (1) average salary by job_title_short, (2) count of remote jobs by location, (3) salary percentiles by job_title_short. Each can take 30–60 seconds. Currently all three run sequentially on one worker, taking 2–3 minutes total. Design an allocation that runs them in parallel but prevents memory overflow.

```sql
-- Run these three jobs in parallel tasks with memory/timeout constraints
-- Task 1: Salary by title (low memory footprint)
CREATE TEMP TABLE salary_by_title AS
SELECT 
  job_title_short,
  COUNT(*) as job_count,
  AVG(salary_year_avg) as avg_salary,
  PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY salary_year_avg) as p25_salary,
  PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY salary_year_avg) as p75_salary
FROM job_postings_fact
WHERE job_posted_date >= CURRENT_DATE - INTERVAL '1 day'
GROUP BY job_title_short;

-- Task 2: Remote jobs by location (parallel, filtered)
CREATE TEMP TABLE remote_by_location AS
SELECT 
  job_location,
  COUNT(*) as remote_job_count
FROM job_postings_fact
WHERE job_posted_date >= CURRENT_DATE - INTERVAL '1 day'
  AND job_work_from_home = TRUE
GROUP BY job_location;

-- Task 3: Job title distribution (aggregate only)
CREATE TEMP TABLE title_distribution AS
SELECT 
  job_title_short,
  COUNT(*) as total_postings,
  ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) as pct_of_total
FROM job_postings_fact
WHERE job_posted_date >= CURRENT_DATE - INTERVAL '1 day'
GROUP BY job_title_short
ORDER BY total_postings DESC;

-- Wait for all three to complete, then join results (if needed downstream)
-- Scheduler marks each as independent, assigns to separate worker slots
-- Each task gets: memory_limit=512MB, timeout=120s, retries=2
```

## Notes

- **Resource request mismatch**: Over-requesting (asking for 4GB when you need 500MB) wastes cluster capacity; under-requesting causes OOM kills. Profile tasks once in production to set realistic limits.
- **Retry storms**: A failed task set to retry infinitely can consume all worker slots. Always set finite retry counts and exponential backoff; use dead-letter queues for tasks that exceed retry budget.
- **Scheduler affinity and data locality**: Pushing computation to where data lives (same zone/node) reduces network I/O by 10–100×. Connect this to partition pruning and broadcast joins.
- **Monitoring the DAG**: Use task duration histograms and resource utilization traces to spot skew (one task 10× slower than peers). This often reveals missing indexes or data distribution issues.
- **Cold starts and warm pools**: Container startup latency (1–5s per task) compounds quickly; pre-warming worker pools or using persistent executors (like Kubernetes StatefulSets) trades memory for latency savings.
