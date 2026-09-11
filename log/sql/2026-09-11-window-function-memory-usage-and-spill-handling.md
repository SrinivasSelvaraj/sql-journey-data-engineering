---
date: 2026-09-11
phase: sql
topic: Window function memory usage and spill handling
---

# Window function memory usage and spill handling

*SQL for analytics and engineering*

## Concept

Window functions compute aggregates or rankings over ordered subsets of rows without collapsing the result set. When the window frame is large or the dataset doesn't fit in memory, the database must **spill to disk**—writing intermediate results to temporary storage, which degrades performance dramatically (10–100× slower). Memory usage scales with window size, partition cardinality, and the complexity of the frame (e.g., `ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW` over millions of rows).

Understanding spill behavior is critical in interviews because it separates candidates who write syntactically correct queries from those who reason about resource constraints. A query that runs in 2 seconds on 10K rows may timeout on 10M rows if you've forced a full partition sort or dense-rank computation. The database optimizer has limited ability to push filters below window operations, so your query shape directly determines whether spilling occurs.

Without awareness of memory pressure, you'll produce queries that work locally but fail in production, or that cause resource contention affecting other jobs. Recognizing when to use bounded frames, pre-filtering, or alternative approaches (like subqueries with row_number() + filtering) is a practical skill tested in real performance interviews.

## Practice

**Problem:** Rank job postings by salary within each job_title_short, ordered by job_posted_date (most recent first). Include the posting date and salary. Return only the top 3 salaries per title. Keep only remote jobs posted in the last 90 days.

```sql
WITH filtered_jobs AS (
  SELECT 
    job_id,
    job_title_short,
    salary_year_avg,
    job_posted_date,
    job_location
  FROM job_postings_fact
  WHERE job_work_from_home = TRUE
    AND job_posted_date >= CURRENT_DATE - INTERVAL '90 days'
),
ranked_jobs AS (
  SELECT 
    job_id,
    job_title_short,
    salary_year_avg,
    job_posted_date,
    ROW_NUMBER() OVER (
      PARTITION BY job_title_short 
      ORDER BY salary_year_avg DESC, job_posted_date DESC
    ) AS salary_rank
  FROM filtered_jobs
)
SELECT 
  job_title_short,
  salary_year_avg,
  job_posted_date,
  salary_rank
FROM ranked_jobs
WHERE salary_rank <= 3
ORDER BY job_title_short, salary_rank;
```

**Why this works:** Filters are applied *before* the window function, reducing partition size. ROW_NUMBER() with a bounded partition avoids dense sorting of the full dataset. The final WHERE clause on `salary_rank` is pushed into the subquery (or optimizer does it automatically), keeping result set small.

## Notes

- **Spill happens silently**: Most databases don't warn you; use `EXPLAIN` or execution plans to check for "sort spill" or "hash spill" indicators in production engines (Snowflake, Redshift, BigQuery).
- **Bounded vs. unbounded frames**: `ROWS BETWEEN 1 PRECEDING AND CURRENT ROW` uses O(1) memory per partition; `ROWS UNBOUNDED PRECEDING` forces storage of all prior rows and spills at scale.
- **Pre-filter aggressively**: Apply WHERE clauses before window functions to shrink partitions. Pushing down date filters (e.g., last 90 days) often halves memory consumption.
- **Row_number() vs. rank() vs. dense_rank()**: ROW_NUMBER is fastest (no tie-breaking overhead); use it when ties don't matter. Rank/dense_rank require tie-aware sorting, increasing memory pressure.
- **Adjacent topics**: Understand partition elimination (static partition pruning in columnar stores), query plan reading (EXPLAIN ANALYZE), and when to use subqueries + filtering vs. window functions to control where work happens.
