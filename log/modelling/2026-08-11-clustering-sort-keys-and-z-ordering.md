---
date: 2026-08-11
phase: modelling
topic: Clustering, sort keys and Z-ordering
---

# Clustering, sort keys and Z-ordering

*Data modelling and warehousing*

## Concept

Clustering, sort keys, and Z-ordering are physical table optimization techniques that physically reorder rows on disk to accelerate queries without changing the logical schema. A sort key (Redshift) or clustering key (BigQuery, Snowflake) orders all rows by one or more columns; Z-ordering (Delta Lake) interleaves values across multiple columns to optimize range queries on any axis. These matter because they dramatically reduce the data scanned per query—a clustered table on `job_location` and `job_posted_date` skips entire blocks when filtering by those columns, cutting scan time from minutes to seconds.

Without clustering or sorting, every query must scan the entire table sequentially, regardless of selectivity. This becomes critical at scale: a 10 GB unordered table querying for remote jobs posted in the last month touches all 10 GB; the same query on a table clustered by location and date may touch only 500 MB. The trade-off is write cost: inserts and updates must maintain sort order, so clustering benefits read-heavy workloads (analytics) more than write-heavy ones (operational databases).

## Practice

**Problem:** You need to support fast queries filtering by job location and posting date, while also allowing ad-hoc filtering on salary ranges. Choose a clustering strategy and explain the trade-offs.

```sql
-- Redshift: sort key on location and date (most selective filters)
CREATE TABLE job_postings_fact (
  job_id BIGINT,
  job_title_short VARCHAR(50),
  salary_year_avg INTEGER,
  job_work_from_home BOOLEAN,
  job_posted_date DATE,
  job_location VARCHAR(100)
)
SORTKEY (job_location, job_posted_date);

-- Query benefits: filters on location + date skip unnecessary blocks
SELECT COUNT(*) FROM job_postings_fact 
WHERE job_location = 'New York, NY' 
  AND job_posted_date >= CURRENT_DATE - INTERVAL '30 days';

-- Trade-off: salary range queries still scan many blocks (not in sort key)
-- Alternative for multi-axis queries: Snowflake CLUSTERING or Delta Z-order
ALTER TABLE job_postings_fact CLUSTER BY (job_location, job_posted_date, salary_year_avg);
```

## Notes

- **Sort key order matters:** Put the most selective, frequently filtered column first. Queries filtering only by `job_posted_date` benefit from a key ordered `(job_posted_date, job_location)`, but queries filtering both benefit from either order if selectivity is similar.
- **Z-ordering (Delta Lake) vs. sort keys:** Z-ordering optimizes range queries on *any* combination of columns without imposing a strict order; use this when query patterns are unpredictable or multi-dimensional.
- **Hidden cost of clustering:** Write amplification during inserts and compaction; uncompacted tables lose clustering benefits. Monitor clustering ratio (% of data in optimal blocks) and recluster periodically.
- **Adjacent topic:** Distribution keys (Redshift) and partitioning (Hive, Iceberg) solve different problems—they split data across nodes/files, not reorder within. Combine partitioning + clustering for best effect on large tables.
- **Revisit:** Profile actual query patterns before committing to a sort key; wrong clustering is worse than none (high write cost, minimal read gain). Use `EXPLAIN` and scan statistics to validate.
