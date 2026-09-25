---
date: 2026-09-25
phase: cloud
topic: Concurrent execution limits and queuing
---

# Concurrent execution limits and queuing

*Cloud platforms and storage*

## Concept

Cloud data warehouses (Snowflake, BigQuery, Redshift) limit how many queries can execute simultaneously on shared compute resources. This concurrency limit exists because compute is finite—whether you're using on-demand slots or provisioned clusters, only N queries can truly run in parallel before others queue. When you hit the limit, new queries wait in a queue, and you'll see increased latency even if each individual query would be fast.

This matters most in production systems where multiple applications, dashboards, or scheduled jobs compete for the same warehouse. A slow dashboard query isn't always slow because the query is inefficient—it might be slow because 30 other queries are ahead of it in line. Understanding concurrency also directly impacts cost: running 100 small queries serially costs more in wall-clock time than running them in parallel, and some platforms charge per slot or compute unit, making idle queuing expensive.

Without concurrency limits (or proper management of them), you lose predictability and control. Unbounded concurrent access can crash a warehouse, cascade failures across dependent jobs, and make it impossible to diagnose performance—you won't know if a 2-minute query is slow because the logic is bad or because it waited 90 seconds in a queue behind 50 other jobs.

## Practice

**Problem:** You run a daily reporting job that joins `job_postings_fact` with three other large tables. At 6 AM, it takes 8 minutes. At 9 AM during business hours, the same query takes 25 minutes. Your query logic hasn't changed. What's likely happening, and how do you diagnose and mitigate it?

```sql
-- Likely diagnosis: concurrency queue buildup during business hours
-- Solution 1: Use a dedicated compute resource (Snowflake warehouse, BigQuery reserved slots)
ALTER SESSION SET USE_WAREHOUSE = 'ANALYTICS_BATCH_WH';

-- Solution 2: Rewrite to materialize intermediate results during off-peak hours
CREATE OR REPLACE TABLE job_postings_enriched AS
SELECT 
  jp.job_id,
  jp.job_title_short,
  jp.salary_year_avg,
  jp.job_work_from_home,
  jp.job_posted_date,
  jp.job_location,
  c.company_name,
  s.skill_category
FROM job_postings_fact jp
LEFT JOIN companies c ON jp.job_id = c.job_id
LEFT JOIN skills s ON jp.job_id = s.job_id
WHERE jp.job_posted_date >= CURRENT_DATE - 30;

-- Solution 3: Check actual concurrency and queue times (Snowflake example)
SELECT query_id, user_name, query_text, total_elapsed_time, queued_provisioning_time
FROM snowflake.account_usage.query_history
WHERE DATE(start_time) = CURRENT_DATE
  AND queued_provisioning_time > 0
ORDER BY queued_provisioning_time DESC;
```

## Notes

- **Queue time is invisible in slow query logs**: Many platforms don't distinguish between query execution time and queue wait time—you see total time, so a 2-second query waiting 8 seconds looks like a 10-second query.
- **Materialized views and incremental loads reduce contention**: Pre-compute expensive joins or aggregations during off-peak hours, then serve from simpler tables during peak traffic.
- **Concurrency isn't always linear**: Adding more concurrent queries can slow each one down disproportionately due to shared I/O, cache contention, and spilling to disk.
- **Platform-specific terminology matters**: Snowflake uses "warehouse sizing" and "scaling policy," BigQuery uses "reserved slots" and "flex slots," Redshift uses "workload management queues"—learn your platform's model.
- **Cost optimization intersects with concurrency**: Bursting compute during peak hours costs more than batching work during off-peak; prioritize critical queries with QoS policies rather than letting all queries compete equally.
