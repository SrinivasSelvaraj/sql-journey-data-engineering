---
date: 2026-09-11
phase: sql
topic: Cross join cardinality explosion and prevention tactics
---

# Cross join cardinality explosion and prevention tactics

*SQL for analytics and engineering*

## Concept

A cross join produces the Cartesian product of two tables: every row in the left table matched with every row in the right table. If left table has M rows and right table has N rows, the result contains M × N rows. This explodes rapidly—joining a 10,000-row table with a 5,000-row table produces 50 million rows, consuming memory, CPU, and time without providing useful information.

Cross joins are rarely intentional in analytics. They occur as bugs when a `WHERE` clause is missing, a join condition is omitted, or when dimension tables lack proper keys. A query that should return 10,000 rows might return millions and crash or hang mid-execution. The cost is hidden until runtime, especially on large datasets where the planner's estimates fail.

Preventing cardinality explosion requires three habits: (1) always verify join conditions in your `ON` clause, (2) check that keys are truly unique before using them (especially in dimension tables), and (3) use `DISTINCT` sparingly and only after confirming it's not masking a missing join condition. Query planning tools and row-count sanity checks catch these early.

## Practice

**Problem:** You need to list all job postings with their salary and all distinct work-from-home values (to show what options exist). A careless approach accidentally creates a cross join.

**Incorrect (cross join):**
```sql
SELECT 
  j.job_id, 
  j.job_title_short, 
  j.salary_year_avg, 
  j.job_work_from_home
FROM job_postings_fact j, 
     (SELECT DISTINCT job_work_from_home FROM job_postings_fact) wfh
ORDER BY j.job_id;
```
This returns every job posting paired with every distinct wfh value (e.g., if 2 wfh values exist, output is 2× input rows).

**Correct:**
```sql
SELECT 
  job_id, 
  job_title_short, 
  salary_year_avg, 
  job_work_from_home
FROM job_postings_fact
ORDER BY job_id;
```
Or, if you actually need to show distinct wfh options separately:
```sql
SELECT DISTINCT job_work_from_home FROM job_postings_fact;
```

## Notes

- **Missing `ON` clause is the #1 cause**: forgetting the join condition turns any join into a cross join. Always double-check your `ON` clause exists and is logically correct.
- **Dimension table cardinality**: if a dimension table (e.g., skills, locations) is not deduplicated before joining, you multiply rows unexpectedly. Use `DISTINCT` *before* the join, or validate uniqueness with `COUNT(DISTINCT key) = COUNT(*)`.
- **Row count sanity check**: before running a long-running query, estimate expected output rows. If actual ≫ expected, investigate. A 10x multiplier is often a cross join.
- **Query plan inspection**: use `EXPLAIN` (PostgreSQL) or equivalent to spot Cartesian products in the plan before execution. Look for missing filter predicates.
- **Adjacent: self-joins and many-to-many**: self-joins and truly many-to-many joins require explicit deduplication or aggregation to avoid inflating row counts. The same discipline applies.
