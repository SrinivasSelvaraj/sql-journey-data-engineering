---
date: 2026-08-13
phase: cloud
topic: Snowflake architecture: warehouses, caching and credits
---

# Snowflake architecture: warehouses, caching and credits

*Cloud platforms and storage*

## Concept

Snowflake's architecture separates **compute** (virtual warehouses) from **storage**, meaning you pay for both independently. A warehouse is a cluster of compute nodes that executes queries; when you run a query, you consume credits based on warehouse size and duration. This separation is powerful—you can scale compute without moving data—but it means a slow query doesn't necessarily mean bad data; it might mean an undersized warehouse, a full table scan, or both running simultaneously and competing for resources.

Snowflake also caches query results and data in two layers: the **result cache** (24 hours, query-identical matches) and the **local disk cache** (per-warehouse, ~1GB per credit of compute). A repeated query hits result cache almost instantly; a similar query on the same warehouse hits disk cache. Both are free. However, if you resize a warehouse or restart it, you lose the disk cache, forcing re-reads from cloud storage—this is expensive and slow.

Understanding this matters because a query that took 10 seconds yesterday might take 2 minutes today if the warehouse was resized or restarted, or if concurrent queries pushed you beyond cache capacity. You're also paying for every second a warehouse runs, even if idle; a 3XL warehouse costs 12× more per second than a Small one. Choosing the right size and knowing when to suspend it directly impacts both latency and cost.

## Practice

**Problem:** Your analytics team runs daily reports on `job_postings_fact`. The same report runs every morning and is fast (5 seconds), but a slightly different report run on a resized warehouse takes 45 seconds, and you're unsure if it's the data or the infrastructure.

**Solution:**
```sql
-- Original fast query (hits result cache or warm disk cache)
SELECT job_title_short, COUNT(*) as count
FROM job_postings_fact
WHERE job_posted_date >= CURRENT_DATE - 7
GROUP BY job_title_short
ORDER BY count DESC;

-- Slower variant on resized warehouse: avoid full table scan, use pruning
SELECT job_title_short, COUNT(*) as count
FROM job_postings_fact
WHERE job_posted_date >= CURRENT_DATE - 7
  AND job_work_from_home = TRUE  -- Added filter reduces rows scanned
GROUP BY job_title_short
ORDER BY count DESC;

-- Check warehouse cache status and query history
SELECT query_id, query_text, execution_time, credits_used, queued_provisioning_time
FROM snowflake.account_usage.query_history
WHERE user_name = CURRENT_USER()
ORDER BY start_time DESC
LIMIT 10;
```

The key: smaller filters and pruning on `job_posted_date` (if it's a clustering key) reduce data scanned; resizing the warehouse alone won't help if you're doing a full table scan. Warm cache masks inefficient queries.

## Notes

- **Warehouse idle cost**: A running warehouse costs credits every second, even with zero queries. Set auto-suspend to 5–10 minutes in non-production; you lose disk cache but regain it in seconds on next query.
- **Result cache is strict**: `SELECT * FROM table` and `SELECT * FROM table LIMIT 10` are different cached queries. Adding `CURRENT_DATE()` or `RANDOM()` in the SELECT list defeats cache (intentional or not).
- **Clustering and statistics**: Snowflake doesn't require explicit indexing, but clustered columns (e.g., `job_posted_date`) enable pruning; poor clustering means scanning unnecessary micro-partitions even with WHERE filters.
- **Concurrency and queue time**: If many queries run on the same Small warehouse, you'll see `queued_provisioning_time` > 0 in query history. This is not cache loss; it's contention. Scale warehouse size or use multiple warehouses.
- **Cross-database cost**: Reading from a different database in the same region costs the same; cross-region queries incur transfer charges. Always check your `account_usage` for surprise spending.
