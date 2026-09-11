---
date: 2026-09-11
phase: sql
topic: DISTINCT vs GROUP BY performance on wide tables
---

# DISTINCT vs GROUP BY performance on wide tables

*SQL for analytics and engineering*

## Concept

`DISTINCT` and `GROUP BY` both eliminate duplicates, but they behave differently on wide tables—tables with many columns. `DISTINCT` compares *all* columns in the SELECT list for uniqueness, while `GROUP BY` groups by only the specified columns and requires aggregate functions for the rest. On wide tables, `DISTINCT` must hash or sort the entire row width, making it slower and memory-intensive. `GROUP BY` is more explicit: you control which columns participate in the uniqueness check and aggregate non-grouped columns intentionally.

The performance gap widens dramatically as table width increases. A `SELECT DISTINCT *` on a 50-column table must compare all 50 columns; a `GROUP BY job_id` on the same table only groups by one column and forces you to decide how to combine the other 49 (via `MAX()`, `MIN()`, `ARRAY_AGG()`, etc.). When you forget this distinction, you either write slow queries (`DISTINCT` on wide tables) or incorrect ones (`GROUP BY` without aggregates on non-grouped columns—which some databases reject, others allow with unpredictable results).

## Practice

**Problem:** Find the distinct job titles and their earliest posting date for jobs in each location that allow remote work. The result should have one row per unique (job_location, job_title_short) pair.

```sql
-- ❌ Inefficient: DISTINCT compares all columns, including salary_year_avg
SELECT DISTINCT
  job_location,
  job_title_short,
  job_posted_date,
  salary_year_avg
FROM job_postings_fact
WHERE job_work_from_home = TRUE;

-- ✅ Correct and efficient: GROUP BY controls uniqueness, aggregates narrow the result
SELECT
  job_location,
  job_title_short,
  MIN(job_posted_date) AS earliest_posting_date,
  AVG(salary_year_avg) AS avg_salary
FROM job_postings_fact
WHERE job_work_from_home = TRUE
GROUP BY job_location, job_title_short;
```

## Notes

- **DISTINCT on SELECT \*:** Never use `SELECT DISTINCT *` on wide tables in production. It's a hidden performance trap—the query must materialize and compare every column, defeating index use and overwhelming memory.
- **GROUP BY forces intentionality:** `GROUP BY` requires you to aggregate non-grouped columns explicitly (`MAX`, `MIN`, `SUM`, `ARRAY_AGG`), which catches logic errors early. This is a feature, not a bug.
- **Query plan inspection:** Always `EXPLAIN` both approaches on real data. Watch for hash/sort spills and memory warnings; they're red flags that `DISTINCT` is thrashing.
- **Window functions as an alternative:** Sometimes neither works cleanly—use `ROW_NUMBER() OVER (PARTITION BY ... ORDER BY ...)` and filter for rank 1 to get one row per group with full control over tie-breaking.
- **Connects to:** indexing strategy (GROUP BY can use index-only scans if columns are indexed), cardinality estimation, and aggregation function semantics (why `MAX(salary)` on grouped text columns is nonsensical).
