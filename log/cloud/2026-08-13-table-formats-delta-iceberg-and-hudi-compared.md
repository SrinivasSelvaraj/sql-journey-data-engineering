---
date: 2026-08-13
phase: cloud
topic: Table formats: Delta, Iceberg and Hudi compared
---

# Table formats: Delta, Iceberg and Hudi compared

*Cloud platforms and storage*

## Concept

Delta, Iceberg, and Hudi are open table formats that add ACID transactions, schema evolution, and time-travel capabilities on top of object storage (S3, GCS, ADLS). Without them, you're managing raw Parquet files—which means no easy rollbacks, no concurrent writes, no schema changes without rewriting everything, and query engines can't efficiently prune old data or enforce constraints.

They matter most when your data lake grows beyond a single daily batch job. Once multiple teams write to the same tables, schemas change mid-month, or you need to recover from a bad load, format choice becomes a cost lever. A slow query might be slow not because of computation, but because the table format is scanning every file instead of using partition statistics or data skipping.

The differences are real: Delta (Databricks) is mature and tightly integrated with Spark; Iceberg (Netflix/Apache) has better partition evolution and hidden partitioning; Hudi (Uber) excels at incremental processing and upserts. They all solve the same core problem—making object storage behave like a database—but with different trade-offs in metadata overhead, write latency, and query optimization support.

## Practice

**Problem:** Your `job_postings_fact` table grows daily, partitioned by `job_posted_date`. After six months, queries on recent data are slow even though you're filtering to a single day. You suspect old partition metadata is slowing scans.

**Solution (Delta example):**

```sql
-- Enable partition pruning and data skipping
CREATE TABLE job_postings_fact (
  job_id INT,
  job_title_short STRING,
  salary_year_avg INT,
  job_work_from_home BOOLEAN,
  job_posted_date DATE,
  job_location STRING
)
USING DELTA
PARTITIONED BY (job_posted_date)
TBLPROPERTIES (
  'delta.dataSkippingNumIndexedCols' = '3',  -- Index salary, location, remote flag
  'delta.enableDeletionVectors' = 'true'     -- Efficient soft deletes
);

-- Check table statistics
DESCRIBE DETAIL job_postings_fact;

-- Vacuum old metadata (removes files older than 7 days)
VACUUM job_postings_fact RETAIN 7 DAYS;

-- Query now skips partition metadata and uses column statistics
SELECT job_title_short, AVG(salary_year_avg)
FROM job_postings_fact
WHERE job_posted_date = '2024-01-15'
  AND job_work_from_home = true
GROUP BY job_title_short;
```

## Notes

- **Metadata explosion:** Each write creates metadata entries. Iceberg and Hudi can accumulate thousands of manifest files; Delta's log can grow large too. Vacuum/compaction strategies differ per format and directly affect query planning time.
- **Hidden partitioning (Iceberg advantage):** Partition columns don't appear in data files—you can evolve partitioning (e.g., `job_posted_date` → `job_posted_year_month`) without rewriting. Delta and Hudi require more manual effort.
- **Upsert patterns:** Hudi's "merge-on-read" mode is faster for writes but slower for reads; Iceberg's `MERGE` is simpler syntax; Delta requires `MERGE INTO` with explicit join logic. Your cost model changes based on read/write ratio.
- **Schema evolution watch:** All three support it, but Delta is most forgiving; Iceberg enforces stricter type safety. Test with `ALTER TABLE ADD COLUMN` in your target format before committing.
- **Cloud cost tie-in:** More metadata = more S3 LIST/HEAD API calls = higher bill. Partition pruning and data skipping directly reduce data scanned and bytes transferred, cutting both query time and egress costs.
