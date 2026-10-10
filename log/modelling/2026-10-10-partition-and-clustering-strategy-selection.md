---
date: 2026-10-10
phase: modelling
topic: Partition and clustering strategy selection
---

# Partition and clustering strategy selection

*Data modelling and warehousing*

## Concept

Partition and clustering strategies determine how data is physically organized on disk and which queries run efficiently without full table scans. Partitioning divides large tables into smaller chunks (usually by date or categorical column); clustering reorganizes rows within partitions by sort order (usually by low-cardinality columns frequently filtered). This matters most when tables exceed 1–10 GB and queries filter on consistent columns—without strategy, every query reads the entire table, wasting compute and money in cloud warehouses.

Without intentional partitioning, a 500M-row fact table forces Snowflake or BigQuery to scan all historical data even for a single week's report. Without clustering, filtering on `job_work_from_home` still requires scanning millions of rows. The cost is real: in BigQuery, an unpartitioned table scan costs $6.25 per TB; partitioning can reduce that by 90%.

Choose partition columns based on filter frequency and cardinality (date ranges, regions, departments). Choose cluster columns based on equality filters that appear in most queries and have moderate cardinality (20–1000 unique values). Over-partitioning (100+ partitions) fragments too aggressively; under-clustering leaves query performance flat.

## Practice

**Problem:** Your `job_postings_fact` table grows to 50M rows. Analysts query salary ranges and remote-work status across specific date ranges (last 30 days, last quarter). Current query takes 45 seconds. Design a partitioning and clustering strategy.

```sql
-- Partition by job_posted_date (time-series analysis is standard)
-- Cluster by job_work_from_home and job_location (common filters, low–moderate cardinality)

CREATE TABLE job_postings_fact (
  job_id INT64,
  job_title_short STRING,
  salary_year_avg NUMERIC,
  job_work_from_home BOOLEAN,
  job_posted_date DATE,
  job_location STRING
)
PARTITION BY job_posted_date
CLUSTER BY job_work_from_home, job_location
OPTIONS (
  description = "Fact table for job postings; partitioned by date for time-series queries; clustered by remote status and location for rapid filtering on common dimensions."
);

-- Result: queries filtering by date range + remote status now scan only relevant partitions + clusters
-- Example query (now ~3 seconds instead of 45):
SELECT 
  job_location,
  job_work_from_home,
  COUNT(*) as posting_count,
  AVG(salary_year_avg) as avg_salary
FROM job_postings_fact
WHERE job_posted_date BETWEEN '2024-01-01' AND '2024-01-31'
  AND job_work_from_home = TRUE
GROUP BY job_location, job_work_from_home;
```

## Notes

- **Mistake: over-partitioning on high-cardinality columns** (e.g., `job_id`). This creates too many partitions, increasing metadata overhead and query planning time. Stick to low–moderate cardinality (date, region, category).
- **Mistake: clustering on columns never filtered in WHERE clauses.** Clustering has overhead; only cluster on columns that appear in >70% of queries. Monitor query patterns first.
- **Adjacent topic: materialized views and incremental refresh.** After partitioning, consider pre-aggregating common queries (e.g., daily salary by location) to avoid scanning partitions repeatedly.
- **Revisit column naming:** partition/cluster columns should be self-documenting (e.g., `job_posted_date` not `date`). See phase goal: "Design schemas a team can query without asking you."
- **Monitoring:** BigQuery's `INFORMATION_SCHEMA.TABLE_STORAGE` and `JOBS_BY_PROJECT` let you measure partition effectiveness. If 80% of queries still scan all partitions, re-evaluate strategy.
