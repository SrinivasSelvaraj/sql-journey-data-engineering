---
date: 2026-08-11
phase: modelling
topic: File compaction and the small files problem
---

# File compaction and the small files problem

*Data modelling and warehousing*

## Concept

The small files problem occurs when data is written to storage in many tiny files instead of fewer, larger ones. This typically happens in append-heavy systems where each insert or batch creates a new file. Query engines must open and read file metadata for every file, making queries slow—even if the total data size is small. In a data lake or warehouse, 10,000 files of 1 MB each will perform far worse than 10 files of 1 GB each.

File compaction merges small files into larger ones, reducing metadata overhead and I/O operations. This is critical in columnar formats (Parquet, ORC) where each file has its own footer metadata. Without compaction, your warehouse becomes sluggish even as stored data stays manageable. The problem compounds over time: a fact table receiving daily inserts can degrade from 50ms queries to 10s queries within weeks.

When to act: monitor file count per partition and average file size. If you have >100 files per partition or files <50 MB in a cloud data lake, compaction will likely improve query performance measurably.

## Practice

**Problem:** Your `job_postings_fact` receives new job postings every hour. After 30 days, the partition for `job_posted_date = '2024-01-15'` contains 720 files (one per hour), each 2–5 MB. Queries filtering on that date are slow. Design a compaction strategy.

```sql
-- Compact small files for a specific partition
-- Step 1: Create a temporary table with compacted data
CREATE TABLE job_postings_fact_compacted AS
SELECT 
  job_id,
  job_title_short,
  salary_year_avg,
  job_work_from_home,
  job_posted_date,
  job_location
FROM job_postings_fact
WHERE job_posted_date = '2024-01-15';

-- Step 2: Drop original partition and swap in compacted version
ALTER TABLE job_postings_fact DROP PARTITION (job_posted_date = '2024-01-15');

INSERT INTO job_postings_fact
SELECT * FROM job_postings_fact_compacted;

DROP TABLE job_postings_fact_compacted;
```

**Result:** 720 small files → 2–4 large files. Query latency drops because the engine reads far fewer file headers and performs fewer parallel I/O operations.

## Notes

- **Partition strategy matters:** Partitioning by date is good, but partitioning too finely (by hour, by minute) defeats the purpose. Prefer daily or weekly partitions unless your query patterns demand finer granularity.

- **Compaction cadence:** Schedule nightly or weekly compaction jobs for append-heavy tables. Avoid compacting on-demand during peak hours; use off-peak windows or a separate scheduler (Airflow, dbt, Databricks Jobs).

- **Tool dependency:** Modern engines handle this differently—Delta Lake has `OPTIMIZE`, Iceberg uses `compact()`, Hudi has compaction strategies. Learn your engine's native approach rather than relying on manual rewrites.

- **Trade-off with write latency:** Aggressive compaction increases write-path complexity and cost. A small number of tiny files is often acceptable; compaction is most valuable when file count crosses into hundreds or thousands per partition.

- **Related:** Data skew, partition pruning, statistics gathering, and incremental refresh strategies all interact with compaction decisions. Revisit file layout whenever you redesign partitioning or adjust ingestion batch sizes.
