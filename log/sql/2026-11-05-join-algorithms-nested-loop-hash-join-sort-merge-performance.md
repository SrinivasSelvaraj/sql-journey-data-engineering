---
date: 2026-11-05
phase: sql
topic: Join algorithms: nested loop, hash join, sort-merge performance
---

# Join algorithms: nested loop, hash join, sort-merge performance

*SQL for analytics and engineering*

## Concept

Join algorithms determine *how* the database physically combines rows from two tables—this choice can mean the difference between a query finishing in milliseconds or timing out. The three main algorithms are **nested loop** (iterate outer table, scan inner table for each row—O(n×m), slowest but works anywhere), **hash join** (build hash table on smaller table, probe with larger table—O(n+m), fastest when hash table fits in memory), and **sort-merge** (sort both tables, merge in single pass—O(n log n + m log m), optimal when data is already sorted or join columns have indexes). Query planners choose based on table sizes, available indexes, memory, and selectivity; understanding these tradeoffs lets you write queries that naturally guide the optimizer toward efficient plans rather than fighting it.

Without this knowledge, you'll write logically correct SQL that executes slowly because you're forcing a nested loop on a million-row join, or you'll wonder why adding an index didn't help when the real bottleneck is a hash join spilling to disk. In interviews and production, you need to predict rough performance before running EXPLAIN—recognizing that `WHERE conditions_on_join_key` + `JOIN ON indexed_column` usually triggers a hash or merge join, while `WHERE conditions_after_join` or `ON non-indexed_columns` risks nested loops.

## Practice

**Problem:** You need to find all job postings from data engineers that offer work-from-home *and* have salaries above the median salary for that title. Write a query that minimizes nested loops.

```sql
-- Less optimal: nested loop likely (correlated subquery)
SELECT DISTINCT j1.job_id, j1.job_title_short, j1.salary_year_avg
FROM job_postings_fact j1
WHERE j1.job_title_short = 'Data Engineer'
  AND j1.job_work_from_home = TRUE
  AND j1.salary_year_avg > (
    SELECT AVG(salary_year_avg)
    FROM job_postings_fact
    WHERE job_title_short = 'Data Engineer'
  );

-- Better: hash join on pre-aggregated stats
WITH salary_stats AS (
  SELECT job_title_short, AVG(salary_year_avg) AS median_salary
  FROM job_postings_fact
  WHERE job_title_short = 'Data Engineer'
  GROUP BY job_title_short
)
SELECT j.job_id, j.job_title_short, j.salary_year_avg
FROM job_postings_fact j
INNER JOIN salary_stats s
  ON j.job_title_short = s.job_title_short
WHERE j.job_title_short = 'Data Engineer'
  AND j.job_work_from_home = TRUE
  AND j.salary_year_avg > s.median_salary;
```

The second query allows the planner to hash-join the small `salary_stats` result with the filtered `job_postings_fact`, avoiding a row-by-row subquery evaluation.

## Notes

- **Cardinality estimation matters**: if the optimizer underestimates rows after a WHERE clause, it may pick nested loop; validate with `EXPLAIN` and filter early.
- **Index on join keys is critical**: hash joins still benefit from indexes on the probe side for final lookups; sort-merge *requires* indexes or pre-sorted data to avoid sorts.
- **Memory pressure**: hash joins fail or degrade to disk spill if the hash table exceeds `work_mem` (PostgreSQL) or buffer pool; use `EXPLAIN ANALYZE` to spot this.
- **Common mistake**: joining on expressions like `YEAR(date_col) = YEAR(other_date)` prevents index use and forces nested loops—materialize or use indexed range predicates instead.
- **Adjacent skills**: query plan reading (EXPLAIN output), statistics freshness (ANALYZE/UPDATE STATISTICS), and partitioning strategies all influence which algorithm runs; revisit these when a query suddenly becomes slow after data volume changes.
