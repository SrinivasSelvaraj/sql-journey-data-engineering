---
date: 2026-09-10
phase: sql
topic: Index selection and statistics freshness in optimizers
---

# Index selection and statistics freshness in optimizers

*SQL for analytics and engineering*

## Concept

Query optimizers rely on **index selection** and **statistics freshness** to generate efficient execution plans. An index is useful only if the optimizer knows about it and understands the data distribution; stale statistics cause the planner to make wrong cardinality estimates, leading to poor join orders, incorrect parallelism, and full table scans when index seeks would be faster. When statistics are out of date, the optimizer may choose a nested-loop join over a hash join, or route millions of rows through a slow path because it thought the filter would eliminate 99% of rows (but didn't).

This matters most in analytical queries with multiple joins, large fact tables, and selective filters. In production systems, statistics drift occurs naturally: new data arrives, old data is deleted, and the distribution shifts. Without periodic refreshes, plans degrade silently—queries that ran in 2 seconds now take 20 seconds, but no error is raised. Index selection itself is straightforward: B-tree indexes speed up range scans and equality lookups; composite indexes help if the leading columns match your WHERE and JOIN predicates. The hard part is trusting that the optimizer *sees* these indexes and the data accurately.

## Practice

**Problem:** You have a query that joins `job_postings_fact` to itself to find competing job postings (same title, location, posted within 7 days) and filters for remote work. The query runs slowly even though an index exists on `(job_title_short, job_location, job_posted_date)`. Statistics show the index is never used.

```sql
-- Slow query: optimizer doesn't trust the index because stats are stale
SELECT 
  a.job_id,
  b.job_id AS competing_job_id,
  ABS(EXTRACT(DAY FROM a.job_posted_date - b.job_posted_date)) AS days_apart
FROM job_postings_fact a
JOIN job_postings_fact b
  ON a.job_title_short = b.job_title_short
  AND a.job_location = b.job_location
  AND ABS(EXTRACT(DAY FROM a.job_posted_date - b.job_posted_date)) <= 7
WHERE a.job_work_from_home = TRUE
  AND b.job_work_from_home = TRUE
  AND a.job_id < b.job_id
ORDER BY a.job_id, days_apart;

-- Solution: refresh statistics on the fact table and rewrite to push filters early
ANALYZE TABLE job_postings_fact COMPUTE STATISTICS;
ANALYZE TABLE job_postings_fact COMPUTE STATISTICS FOR COLUMNS 
  job_title_short, job_location, job_posted_date, job_work_from_home;

-- Rewritten query: filter before join, use index-friendly predicates
WITH remote_postings AS (
  SELECT job_id, job_title_short, job_location, job_posted_date, salary_year_avg
  FROM job_postings_fact
  WHERE job_work_from_home = TRUE
)
SELECT 
  a.job_id,
  b.job_id AS competing_job_id,
  ABS(EXTRACT(DAY FROM a.job_posted_date - b.job_posted_date)) AS days_apart,
  a.salary_year_avg,
  b.salary_year_avg
FROM remote_postings a
JOIN remote_postings b
  ON a.job_title_short = b.job_title_short
  AND a.job_location = b.job_location
  AND a.job_posted_date BETWEEN b.job_posted_date - 7 AND b.job_posted_date + 7
WHERE a.job_id < b.job_id
ORDER BY a.job_id, days_apart;
```

## Notes

- **Stale stats hide index availability:** The optimizer won't use an index if it thinks a full table scan is cheaper; outdated cardinality estimates make it misjudge cost. Always run `ANALYZE TABLE` or equivalent after bulk loads, deletes, or schema changes.
- **Leading column order matters:** Composite indexes are only useful if your WHERE/JOIN predicates reference leading columns. `(title, location, date)` helps if you filter on title first; reversing to `(date, location, title)` may not be used the same way.
- **Statistics freshness ≠ index existence:** You can have a perfect index that the planner ignores because statistics are 6 months old. Check `EXPLAIN PLAN` output; if the index isn't mentioned, refresh stats before blaming the schema.
- **Connects to:** Query plan analysis (EXPLAIN), cardinality estimation, filter pushdown optimization, and cost-based vs. rule-based optimization.
- **Interview tip:** When a query is slow, always ask: "When were statistics last updated?" and "What does EXPLAIN show?" before assuming the index is missing or poorly designed.
