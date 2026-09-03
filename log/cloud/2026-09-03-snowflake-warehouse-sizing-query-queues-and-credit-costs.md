---
date: 2026-09-03
phase: cloud
topic: Snowflake: warehouse sizing, query queues and credit costs
---

# Snowflake: warehouse sizing, query queues and credit costs

*Cloud platforms and storage*

## Concept

Snowflake charges per *compute credit* (typically $2–4 per credit depending on edition and region), and warehouse size determines both the number of credits consumed per second and query concurrency behavior. A warehouse with 1 credit per second costs roughly $2.6K/month if running continuously; larger warehouses scale linearly but enable parallel query execution, while smaller ones serialize work behind a queue. Query queues form when concurrent queries exceed the warehouse's parallelism capacity—your fast 5-second query may wait 30 seconds if other jobs are running. Understanding this tradeoff is essential: oversizing wastes money on idle compute, undersizing creates bottlenecks and user frustration, while right-sizing requires measuring both peak load and acceptable query latency.

The cost appears immediately in your Snowflake bill and is non-negotiable once a query starts—a runaway join or full table scan on a large warehouse becomes expensive fast. Query queuing is invisible in logs but visible in user complaints; it's often mistaken for a "slow query" when the query plan is fine but execution is blocked. Without warehouse right-sizing, teams either bleed budget or suffer performance regressions that nobody can explain.

## Practice

**Problem:** Your analytics team runs 15–20 concurrent queries during morning standup (9–10 AM). A standard 2-credit warehouse processes them sequentially, causing users to wait 3–5 minutes. You want to reduce wait time without doubling your monthly spend.

```sql
-- Check query queue depth and execution time during peak hours
SELECT 
  DATE_TRUNC('minute', START_TIME) as query_minute,
  WAREHOUSE_NAME,
  COUNT(*) as concurrent_queries,
  AVG(QUEUED_PROVISIONING_TIME) as avg_queue_secs,
  AVG(EXECUTION_TIME) as avg_exec_secs,
  SUM(CREDITS_USED) as total_credits_used
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
WHERE START_TIME >= CURRENT_DATE - 7
  AND HOUR(START_TIME) BETWEEN 9 AND 10
  AND WAREHOUSE_NAME IS NOT NULL
GROUP BY 1, 2
ORDER BY query_minute DESC;

-- Scale warehouse from 2 to 4 credits for morning hours only
ALTER WAREHOUSE analytics_wh SET WAREHOUSE_SIZE = 'LARGE';  -- 8 credits instead of 2

-- Then switch back after 11 AM to save money
ALTER WAREHOUSE analytics_wh SET WAREHOUSE_SIZE = 'SMALL';   -- back to 2 credits
```

## Notes

- **Queuing vs. slowness:** High `QUEUED_PROVISIONING_TIME` in `QUERY_HISTORY` means the warehouse was busy, not that your query is slow. Check `EXECUTION_TIME` separately; optimize queries, not just warehouse size.
- **Elastic scaling:** Use warehouse size changes or auto-suspend/auto-resume to match workload patterns (e.g., large during business hours, tiny or off during nights). Dynamic scaling costs nothing but saves thousands monthly.
- **Spillover and disk I/O:** Very large result sets spill to local SSD; monitor `BYTES_SCANNED` and `BYTES_PRODUCED` to catch inefficient queries that scale worse on bigger warehouses.
- **Credit burn vs. concurrency:** 1 large warehouse is cheaper than 3 small ones for the same workload, but limits fault isolation. Multi-warehouse strategies (separate OLAP vs. reporting) require governance.
- **Adjacent skills:** Learn to read `QUERY_HISTORY.QUERY_PROFILING_DATA` for task-level bottlenecks, and practice partitioning/clustering to reduce `BYTES_SCANNED` before scaling compute.
