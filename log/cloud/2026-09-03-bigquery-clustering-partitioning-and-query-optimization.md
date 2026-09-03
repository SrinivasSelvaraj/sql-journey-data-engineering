---
date: 2026-09-03
phase: cloud
topic: BigQuery: clustering, partitioning and query optimization
---

# BigQuery: clustering, partitioning and query optimization

*Cloud platforms and storage*

## Concept

Partitioning and clustering are table organization strategies that reduce the data BigQuery scans during queries, directly lowering costs and improving speed. **Partitioning** divides a table into smaller segments based on a single column (usually a date or timestamp), and BigQuery can skip entire partitions when your WHERE clause filters on that column—this is *partition pruning*. **Clustering** sorts rows within partitions by up to 4 columns, making range and equality filters faster by localizing related data physically. Without these, BigQuery performs full table scans even on heavily filtered queries; a million-row table filtered to 1,000 rows still charges you for scanning all million rows if not partitioned or clustered.

The decision between them matters for your bill and latency. Partitioning is most effective for time-series data or queries that consistently filter on date ranges; clustering is better when you filter on high-cardinality columns (many unique values like job titles or locations) or when partition granularity would be too fine. Using both together—partitioning by date and clustering by frequently filtered columns—gives maximum efficiency but adds complexity to maintenance.

## Practice

**Problem**: You query `job_postings_fact` daily to analyze remote positions posted in the last 30 days with salaries above $100k. The table has 10M rows and grows monthly. Every query scans the entire table, costing $50/month. Optimize it.

```sql
CREATE TABLE job_postings_fact_optimized
PARTITION BY DATE(job_posted_date)
CLUSTER BY job_work_from_home, job_location, job_title_short
AS
SELECT * FROM job_postings_fact;

-- Now this query scans only ~3 days of data, not 10M rows:
SELECT job_title_short, AVG(salary_year_avg)
FROM job_postings_fact_optimized
WHERE job_posted_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY)
  AND job_work_from_home = TRUE
  AND salary_year_avg > 100000
GROUP BY job_title_short;
```

## Notes

- **Partitioning is not free**: each partition (file) has overhead; don't over-partition—avoid daily partitions on small tables. Aim for monthly or quarterly unless you have millions of daily rows.
- **Cluster cardinality matters**: cluster on columns with moderate-to-high cardinality (100s to 1000s of distinct values); clustering on binary flags or 2-value enums is wasteful.
- **Slot commitment vs. on-demand**: partitioning/clustering reduces data scanned but doesn't affect slot consumption; they're cost optimizations for on-demand billing, not latency silver bullets under slots.
- **Partition key must be queried frequently**: if you partition by `job_posted_date` but rarely filter by date, pruning won't help; choose columns that appear in your typical WHERE clauses.
- **Adjacent topics**: understand table expiration (auto-delete old partitions), re-clustering (BigQuery does this automatically), and materialized views (can pre-cluster aggregates).
