---
date: 2026-08-09
phase: python
topic: Chunked processing of files larger than memory
---

# Chunked processing of files larger than memory

*Python for data engineering*

## Concept

Chunked processing reads large files in fixed-size blocks rather than loading them entirely into memory. This is essential when file size exceeds available RAM—a common scenario in data pipelines ingesting logs, CSVs, or JSON streams. Without chunking, your process crashes with `MemoryError` or hangs the system; with it, you trade memory for iteration overhead and gain predictable, bounded resource consumption.

The pattern works by maintaining a buffer (typically 1–100 MB), reading one chunk at a time, processing it, writing results, then discarding it before reading the next. This keeps memory usage constant regardless of input size. For data engineering, chunking pairs naturally with streaming aggregations, batch inserts, and checkpointing—allowing you to resume mid-file if a pipeline fails.

## Practice

**Problem:** You have a 5 GB CSV of job postings and need to load it into `job_postings_fact`, but your server has 2 GB RAM. Write a SQL pattern that inserts data in batches while Python feeds chunks.

```sql
-- Prepare for chunked inserts
CREATE TEMP TABLE job_postings_staging (
  job_id INT,
  job_title_short VARCHAR(50),
  salary_year_avg INT,
  job_work_from_home BOOLEAN,
  job_posted_date DATE,
  job_location VARCHAR(100)
);

-- Insert one chunk at a time (Python loop calls this)
INSERT INTO job_postings_staging 
  (job_id, job_title_short, salary_year_avg, job_work_from_home, job_posted_date, job_location)
VALUES 
  (?, ?, ?, ?, ?, ?),
  (?, ?, ?, ?, ?, ?);

-- After all chunks loaded, merge into fact table
INSERT INTO job_postings_fact
SELECT * FROM job_postings_staging
ON CONFLICT (job_id) DO UPDATE SET salary_year_avg = EXCLUDED.salary_year_avg;

-- Clean staging for next run
TRUNCATE TABLE job_postings_staging;
```

## Notes

- **Off-by-one in chunk boundaries**: Ensure your read loop doesn't skip or double-process rows at chunk edges; use line-aware reading (e.g., `TextIOWrapper`) or explicit offset tracking.
- **Type safety & validation before insert**: Parse and validate each chunk's data (dates, nulls, numeric bounds) before passing to SQL; catching errors early prevents partial inserts and rollback storms.
- **Connects to**: streaming ETL, backpressure handling, and exactly-once semantics in distributed pipelines.
- **Generator pattern**: Use Python generators (`yield`) to make chunk processing lazy and composable—avoid building intermediate lists of chunks.
- **Revisit**: connection pooling (don't open/close per chunk), checkpoint files (write offset to disk to resume), and testing with synthetic large files.
