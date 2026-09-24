---
date: 2026-09-24
phase: cloud
topic: API call charges and request pricing
---

# API call charges and request pricing

*Cloud platforms and storage*

## Concept

API call charges are per-request fees levied by cloud platforms (BigQuery, Snowflake, Redshift Spectrum, etc.) for data scanned or operations executed, regardless of whether results are cached or filtered. Unlike traditional databases with flat licensing, cloud platforms charge *by usage*—scanning 100 GB costs the same whether you retrieve 10 rows or 10 million. This model incentivizes writing efficient queries and understanding what data your query actually touches before execution.

When you ignore API pricing, runaway queries can generate unexpected bills in minutes. A poorly written query scanning an entire unpartitioned table daily can cost thousands monthly. Understanding request pricing forces you to think about query execution plans, partitioning strategies, and whether a full table scan is necessary—the same discipline that makes queries *fast*.

Without awareness of pricing mechanics, you lose visibility into cost drivers. A query that "works" but scans 50 GB unnecessarily trains bad habits. Cloud platforms expose query execution details (bytes scanned, slot usage, cache hits) precisely so you can see the financial and performance impact of your SQL choices.

## Practice

**Problem:** You're analyzing job postings and run this query daily to find average salaries by location. It's slow and expensive.

```sql
-- INEFFICIENT: Full table scan, no partition pruning
SELECT 
  job_location,
  AVG(salary_year_avg) AS avg_salary,
  COUNT(*) AS job_count
FROM job_postings_fact
WHERE salary_year_avg > 50000
GROUP BY job_location;

-- EFFICIENT: Partition by job_posted_date, filter recent data only
SELECT 
  job_location,
  AVG(salary_year_avg) AS avg_salary,
  COUNT(*) AS job_count
FROM job_postings_fact
WHERE job_posted_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 90 DAY)
  AND salary_year_avg > 50000
GROUP BY job_location;
```

The optimized version adds a date filter that leverages partition pruning, scanning only 90 days of data instead of all years. On a billion-row table, this reduces scanned bytes by 95%, cutting both query time and cost proportionally.

## Notes

- **Partition and cluster your tables intentionally.** Without date-based partitioning, every query scans the full table. BigQuery, Snowflake, and Redshift all support partitioning—use it.
- **Cached results are free or cheap.** If the same query runs twice within minutes, the second execution may hit cache (zero cost in BigQuery). Monitor cache hit rates.
- **SELECT * is your enemy.** Scanning columns you don't need wastes money. Always specify only needed columns; the cost difference is real on wide tables.
- **Estimate before executing.** Most cloud platforms show query plan and estimated bytes *before* you run it. Check the estimate; if it's 500 GB and you expected 5 GB, rewrite before submitting.
- **This connects to:** query optimization, indexing strategy, data modeling (fact vs. dimension tables), and monitoring/alerting—set cost thresholds to catch runaway jobs early.
