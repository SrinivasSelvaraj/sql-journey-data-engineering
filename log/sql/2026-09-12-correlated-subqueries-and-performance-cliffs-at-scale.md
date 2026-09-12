---
date: 2026-09-12
phase: sql
topic: Correlated subqueries and performance cliffs at scale
---

# Correlated subqueries and performance cliffs at scale

*SQL for analytics and engineering*

## Concept

A **correlated subquery** is a subquery that references columns from the outer query—it executes *once per row* of the outer result set. This is fundamentally different from a join or non-correlated subquery, which execute once. Correlated subqueries are useful for row-by-row comparisons (e.g., "show me jobs that pay above the average for their location") but become a severe performance cliff at scale: on a 1M-row table, a correlated subquery can trigger 1M+ inner scans instead of one.

Without understanding when to recognize and replace correlated subqueries, you write code that passes small test cases but times out in production. Query planners often execute them naively (especially in older databases or when statistics are stale). The key insight: **correlated subqueries belong in reporting scripts on small tables; for analytical queries on large fact tables, rewrite using joins, window functions, or CTEs with aggregations.**

The performance cliff happens because the subquery condition (e.g., `WHERE salary_year_avg > (SELECT AVG(...) WHERE location = outer.location)`) forces the database to re-evaluate the subquery for each outer row rather than computing aggregations once and joining.

## Practice

**Problem:** Find all job postings that pay more than the average salary for their job title, ordered by title and salary descending. Do *not* use a correlated subquery.

```sql
WITH title_avg AS (
  SELECT 
    job_title_short,
    AVG(salary_year_avg) AS avg_salary_for_title
  FROM job_postings_fact
  WHERE salary_year_avg IS NOT NULL
  GROUP BY job_title_short
)
SELECT 
  j.job_id,
  j.job_title_short,
  j.salary_year_avg,
  ta.avg_salary_for_title,
  j.job_posted_date
FROM job_postings_fact j
INNER JOIN title_avg ta
  ON j.job_title_short = ta.job_title_short
WHERE j.salary_year_avg > ta.avg_salary_for_title
ORDER BY j.job_title_short, j.salary_year_avg DESC;
```

*(Correlated version—avoid in production: `WHERE salary_year_avg > (SELECT AVG(salary_year_avg) FROM job_postings_fact WHERE job_title_short = j.job_title_short)`)*

## Notes

- **Spotting the trap in interviews:** If you write `WHERE col > (SELECT ... WHERE outer_col = ...)`, pause and ask: "Will this scale?" Usually the answer is no; pivot to a CTE + join or window function.
- **Window functions often replace correlated subqueries elegantly:** Use `ROW_NUMBER() OVER (PARTITION BY job_title_short ORDER BY salary_year_avg DESC)` to rank within groups without a subquery.
- **Execution plan literacy:** Learn to read EXPLAIN output and spot "Nested Loop" with high iteration counts—a red flag for correlated subqueries at scale.
- **Adjacent topic:** Understand the difference between *scalar* subqueries (return one value, can be correlated) and *table* subqueries; scalar ones in WHERE clauses are most dangerous.
- **Revisit:** CTEs (WITH clauses) are the modern, readable alternative; master them alongside EXISTS/IN for existence checks, which can be more efficient than joins for certain cardinalities.
