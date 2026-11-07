---
date: 2026-11-07
phase: sql
topic: Deduplication: row_number and qualify clause patterns
---

# Deduplication: row_number and qualify clause patterns

*SQL for analytics and engineering*

## Concept

Deduplication using `row_number()` and `qualify` removes duplicate rows based on a partition key while preserving one canonical record. `row_number()` assigns a sequential number within each partition ordered by a column; `qualify` filters the result set *after* the window function evaluates, keeping only rows meeting the condition (typically `row_number() = 1`). This is superior to `group by` + aggregation when you need to retain all columns from a single row rather than collapse values.

The pattern matters in data pipelines where source systems produce duplicates from replication lag, ETL reruns, or multi-source joins. Without deduplication, analytics inflate metrics (counting the same user twice) and warehouse joins produce Cartesian explosions. The `qualify` clause is cleaner than a CTE + window function because it pushes the filter into the execution plan rather than materializing intermediate results.

## Practice

**Problem:** You have `job_postings_fact` with duplicate rows (same `job_id`, posted on different dates due to reposting). Deduplicate to keep only the most recent posting per job, retaining all columns.

```sql
select 
  job_id,
  job_title_short,
  salary_year_avg,
  job_work_from_home,
  job_posted_date,
  job_location
from job_postings_fact
qualify row_number() over (partition by job_id order by job_posted_date desc) = 1;
```

## Notes

- **Order matters in the window:** `order by job_posted_date desc` ensures the most recent date gets `row_number() = 1`; reversing it changes which duplicate survives.
- **Qualify vs. CTE trade-off:** `qualify` is more readable but older SQL engines (pre-2020) require a CTE wrapper with `where row_number() = 1`; always check dialect support in interviews.
- **Tiebreaker columns:** If two postings share the same date, add a secondary sort key (`job_id`, `job_location`) to make deduplication deterministic and testable.
- **Performance consideration:** Window functions scan the entire table; combine with `where` predicates *before* the qualify to filter partitions early (filter-then-window beats window-then-filter).
- **Related patterns:** `rank()` and `dense_rank()` handle ties differently; use `rank()` if ties should both receive position 1, or `dense_rank()` if you need compact numbering across ties.
