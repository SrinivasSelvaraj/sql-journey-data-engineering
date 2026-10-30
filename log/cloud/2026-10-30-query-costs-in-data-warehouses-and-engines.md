---
date: 2026-10-30
phase: cloud
topic: Query costs in data warehouses and engines
---

# Query costs in data warehouses and engines

*Cloud platforms and storage*

## Concept

Query costs in cloud data warehouses depend on **what data you scan**, not what you return. Snowflake charges per TB scanned; BigQuery charges per TB queried; Redshift charges per node-hour. A query that filters 1 million rows from a 100 GB table still scans the full 100 GB if columns aren't pruned or partitions aren't eliminated. Understanding cost means recognizing that `SELECT *` on a wide table costs more than `SELECT job_id, salary_year_avg`, and a full table scan costs the same whether your WHERE clause matches 10 rows or 10 million.

Performance and cost are tightly linked. A slow query often means unnecessary data movement—scanning unpartitioned tables, joining before filtering, or reading columns you don't need. In cloud engines, slow = expensive. Without visibility into scan patterns, you might run a query that takes 30 seconds and costs $50, when a rewritten version takes 3 seconds and costs $2. Cost awareness forces you to think about cardinality, partition elimination, and column selection from the start.

## Practice

**Problem:** You need to find the average salary for remote software engineering jobs posted in the last 30 days. Your first query is slow and expensive.

```sql
-- ❌ Expensive: scans entire table, all columns
SELECT AVG(salary_year_avg)
FROM job_postings_fact
WHERE job_title_short LIKE '%Software Engineer%'
  AND job_work_from_home = TRUE
  AND job_posted_date >= CURRENT_DATE - INTERVAL 30 DAY;

-- ✅ Better: partition-aware, only necessary columns
SELECT AVG(salary_year_avg)
FROM job_postings_fact
WHERE job_posted_date >= CURRENT_DATE - INTERVAL 30 DAY  -- Partition elimination
  AND job_work_from_home = TRUE
  AND job_title_short = 'Software Engineer'  -- Exact match, not LIKE
```

The second query scans only the last 30 days of data (partition pruning), avoids regex matching on job_title_short (slower), and only materializes two columns instead of six.

## Notes

- **SELECT * is a cost leak.** Every unused column gets scanned and moved across the network. Always name columns explicitly.
- **WHERE clause order matters for cost, not just speed.** Put partition columns and high-selectivity filters first to enable early pruning.
- **LIKE queries are expensive.** Pattern matching like `LIKE '%text%'` requires full column scans; use exact matches or dictionary lookups when possible.
- **Joins before filters double-scan cost.** Filter each table first, then join smaller result sets; never join large tables then filter.
- **Cost analysis tools are essential.** Use `EXPLAIN` in Snowflake, query statistics in BigQuery, or STL tables in Redshift to see actual bytes scanned, not just execution time.
