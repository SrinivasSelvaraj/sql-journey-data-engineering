---
date: 2026-10-14
phase: cloud
topic: Snowflake clustering keys: pruning and query performance
---

# Snowflake clustering keys: pruning and query performance

*Cloud platforms and storage*

## Concept

Clustering keys are physical orderings of table data on disk that enable **partition pruning**—Snowflake skips entire micro-partitions during scans when filter predicates match the clustering key. Without clustering, full table scans are necessary even when filtering on high-cardinality columns. This matters most for large fact tables (100GB+) where filtering on a few rows still reads gigabytes of data.

Clustering becomes critical when your WHERE clauses consistently filter on columns with non-uniform distribution or when join predicates align with table organization. A well-chosen clustering key can reduce scan cost by 50–90% because Snowflake avoids reading irrelevant micro-partitions entirely. Without it, you pay for I/O on data you never use, and query latency suffers even on powerful warehouses.

The catch: clustering key maintenance has cost. Snowflake automatically re-clusters tables, but this background work consumes credits. Over-clustering or clustering on low-selectivity columns wastes both storage and maintenance overhead.

## Practice

**Problem:** `job_postings_fact` has 50M rows. Queries filtering by `job_posted_date` and `job_location` are slow. A typical query:

```sql
SELECT job_id, job_title_short, salary_year_avg
FROM job_postings_fact
WHERE job_posted_date >= '2024-01-01'
  AND job_location = 'New York, NY'
LIMIT 100;
```

Without clustering, Snowflake scans all micro-partitions. With clustering, it prunes partitions outside the date range and location.

**Solution:**

```sql
ALTER TABLE job_postings_fact 
CLUSTER BY (job_posted_date, job_location);

-- Verify clustering depth (lower is better; <2 is ideal)
SELECT SYSTEM$CLUSTERING_DEPTH('job_postings_fact', '(job_posted_date, job_location)');

-- Query now prunes micro-partitions by both columns
SELECT job_id, job_title_short, salary_year_avg
FROM job_postings_fact
WHERE job_posted_date >= '2024-01-01'
  AND job_location = 'New York, NY'
LIMIT 100;
```

## Notes

- **Order matters:** cluster by most selective (high cardinality, frequently filtered) columns first; `(job_posted_date, job_location)` prunes date ranges first, then location within those partitions.
- **Watch clustering depth:** `SYSTEM$CLUSTERING_DEPTH()` returns a ratio. Depth > 4 signals poor clustering; consider re-clustering or choosing different columns.
- **Clustering credits aren't free:** automatic re-clustering runs in background; monitor `AUTOMATIC_CLUSTERING_ON` and consider disabling if maintenance cost exceeds query savings.
- **Common mistake:** clustering on low-cardinality columns (e.g., `job_work_from_home BOOLEAN`) provides minimal pruning benefit and wastes credits.
- **Adjacent concept:** materialized views and search optimization are alternatives when clustering isn't viable; understand when each pays for itself via `QUERY_ACCELERATION_CREDIT`.
