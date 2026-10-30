---
date: 2026-10-30
phase: cloud
topic: Metadata service costs and query metadata
---

# Metadata service costs and query metadata

*Cloud platforms and storage*

## Concept

Metadata services track information *about* your data—schema definitions, table statistics, partition information, column types—rather than the data itself. In cloud platforms like Snowflake, BigQuery, or Athena, querying metadata incurs costs (API calls, scans) and directly impacts query planning and execution speed. Without accurate metadata, the query optimizer makes poor decisions: it may full-scan a partitioned table instead of pruning to relevant partitions, or estimate join cardinality incorrectly and choose a slow execution plan.

Understanding what metadata exists and keeping it fresh is critical because stale statistics lead to slow queries and wasted compute dollars. For example, if a table's row count is wildly underestimated, the optimizer may choose a nested-loop join over a hash join. Metadata also powers partition elimination and predicate pushdown—two of the biggest cost savers in columnar databases—so neglecting metadata updates can double or triple your cloud bill.

## Practice

**Problem:** You notice that queries on `job_postings_fact` filtered by `job_posted_date` are running slowly, even though the table is partitioned by that column. You suspect the optimizer isn't pruning partitions and is scanning the entire dataset.

```sql
-- Check table metadata and partition statistics
SHOW TABLE EXTENDED IN default LIKE 'job_postings_fact';

-- Examine column statistics (Hive/Spark)
ANALYZE TABLE job_postings_fact COMPUTE STATISTICS FOR COLUMNS job_posted_date, job_location;

-- View statistics
DESC FORMATTED job_postings_fact;

-- Query with partition pruning (should only scan 2024 data)
SELECT job_id, job_title_short, salary_year_avg
FROM job_postings_fact
WHERE job_posted_date >= '2024-01-01' AND job_posted_date < '2024-02-01'
AND job_location = 'New York, NY';

-- Check actual partition files scanned (Spark/Athena EXPLAIN)
EXPLAIN SELECT job_id, job_title_short
FROM job_postings_fact
WHERE job_posted_date >= '2024-01-01';
```

## Notes

- **Stale statistics poison plans:** Run `ANALYZE TABLE` regularly (daily/weekly for fact tables) or enable auto-analyze to prevent optimizer decisions based on month-old cardinality estimates.
- **Metadata overhead is real:** Listing millions of S3 objects in Athena or scanning Iceberg manifest files costs money; use partition projection and columnar metadata formats (Parquet, ORC) to minimize metadata scans.
- **Partition pruning only works if the optimizer knows about it:** Without statistics or explicit partition columns in `WHERE` clauses, the engine assumes it must scan everything, defeating the purpose of partitioning.
- **Adjacent topics:** Iceberg and Delta Lake tables manage metadata automatically with hidden partition columns and manifest files—worth learning if you're tired of manual `ANALYZE` calls.
- **Revisit query plans regularly:** Use `EXPLAIN` before and after metadata updates to verify the optimizer actually changed its strategy; a fast query on your laptop may be slow in production due to different statistics.
