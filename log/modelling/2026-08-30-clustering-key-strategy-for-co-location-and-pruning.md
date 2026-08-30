---
date: 2026-08-30
phase: modelling
topic: Clustering key strategy for co-location and pruning
---

# Clustering key strategy for co-location and pruning

*Data modelling and warehousing*

## Concept

A clustering key physically orders rows on disk by one or more columns, enabling the query engine to skip entire blocks of data that don't match filter conditions—this is *pruning*. It also co-locates related data, reducing I/O when joining or scanning. Unlike a sort key (which is a guarantee) or an index (which is a lookup structure), clustering is a *storage optimization hint* that the warehouse uses to organize micropartitions or blocks.

Clustering matters most when your queries filter heavily on the same columns, or when you're scanning large fact tables repeatedly with predictable predicates. Without it, every query scans all blocks; with it, a query for jobs posted in January skips blocks from February–December. It breaks when you choose a column with low cardinality or when your access patterns shift—clustering on `job_work_from_home` (binary) helps nobody, but clustering on `job_posted_date` (high cardinality, frequently filtered) pays dividends.

The cost is write amplification: inserts and updates must respect the clustering order, slowing ingestion. Use clustering sparingly on high-cardinality, frequently-filtered columns, and only after you've measured query patterns. Overuse turns a warehouse into a bottleneck.

## Practice

**Problem:** Analysts run daily queries like "Show me all remote jobs posted in the last 7 days, grouped by location." Without clustering, every query scans the entire job_postings_fact table regardless of date range, even if only 2% of rows are relevant.

```sql
-- Create or cluster the fact table on job_posted_date and job_work_from_home
-- (Snowflake example; Redshift uses DISTKEY + SORTKEY, BigQuery uses CLUSTER BY)

CREATE TABLE job_postings_fact (
  job_id INT,
  job_title_short VARCHAR,
  salary_year_avg DECIMAL(10,2),
  job_work_from_home BOOLEAN,
  job_posted_date DATE,
  job_location VARCHAR
)
CLUSTER BY (job_posted_date, job_work_from_home);

-- Query now prunes to only blocks matching the date range
SELECT job_location, COUNT(*) as count
FROM job_postings_fact
WHERE job_posted_date >= CURRENT_DATE - 7
  AND job_work_from_home = TRUE
GROUP BY job_location;
```

## Notes

- **Cardinality trap:** Clustering on `job_work_from_home` alone is almost useless (only two values); combine it with a high-cardinality column like `job_posted_date` or `job_location`.
- **Order matters:** Place the most-filtered column first in the cluster key, then the next most-filtered. The example puts date first because time-range filters appear in ~80% of queries.
- **Connects to:** partitioning (often complementary—partition by month, cluster by location within each month), statistics and query optimization, and cost modeling (fewer blocks scanned = lower compute spend).
- **Common mistake:** Setting a cluster key and never revisiting it. Query patterns evolve; re-cluster or drop clustering if access patterns shift.
- **Revisit:** Measure `SYSTEM$CLUSTERING_DEPTH()` (Snowflake) or equivalent tools to verify clustering is actually helping; a poorly maintained cluster can hurt more than it helps.
