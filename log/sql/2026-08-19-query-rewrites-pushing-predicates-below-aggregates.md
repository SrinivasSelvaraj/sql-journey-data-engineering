---
date: 2026-08-19
phase: sql
topic: Query rewrites: pushing predicates below aggregates
---

# Query rewrites: pushing predicates below aggregates

*SQL for analytics and engineering*

## Concept

Pushing predicates below aggregates means applying `WHERE` filters *before* the `GROUP BY` and aggregate functions, rather than after them in a `HAVING` clause. This is a critical optimization because `WHERE` filters reduce the dataset size before aggregation happens—you're computing aggregates over fewer rows. `HAVING` filters operate *after* aggregation, so the database must compute the aggregate for every group first, then discard groups that don't match the condition.

Without predicate pushdown, a query scanning millions of job postings will aggregate all groups before filtering, wasting CPU and memory. With pushdown, you filter to only relevant job postings (e.g., from the past 90 days, work-from-home only) *before* grouping and aggregating. The optimizer can't always do this automatically—it depends on whether the predicate is independent of the aggregate function.

The key rule: if your filter depends on raw column values and *not* on an aggregate result, use `WHERE`. If it must compare against a computed aggregate (e.g., "salary > average salary"), use `HAVING`.

## Practice

**Problem:** Find job titles where the average salary is above $100k, but only for jobs posted after 2024-01-01 and in work-from-home roles. Count how many postings fall into each job title group.

**Inefficient (filter after aggregate):**
```sql
SELECT 
  job_title_short,
  COUNT(*) as posting_count,
  AVG(salary_year_avg) as avg_salary
FROM job_postings_fact
GROUP BY job_title_short
HAVING AVG(salary_year_avg) > 100000
  AND job_posted_date > '2024-01-01'
  AND job_work_from_home = TRUE;
```

**Correct (push predicates down):**
```sql
SELECT 
  job_title_short,
  COUNT(*) as posting_count,
  AVG(salary_year_avg) as avg_salary
FROM job_postings_fact
WHERE job_posted_date > '2024-01-01'
  AND job_work_from_home = TRUE
  AND salary_year_avg IS NOT NULL
GROUP BY job_title_short
HAVING AVG(salary_year_avg) > 100000;
```

The second query filters to work-from-home postings after 2024-01-01 *before* grouping, drastically reducing aggregation scope. The `HAVING` clause stays only for the condition that *must* compare across aggregate values.

## Notes

- **Common mistake:** Putting all conditions in `HAVING`. This defeats the optimization—the database still computes aggregates over the entire unfiltered dataset. Check your `EXPLAIN PLAN` to see if filters are pushed below the `GROUP BY`.
- **NULL handling matters:** Include `AND salary_year_avg IS NOT NULL` in `WHERE` to avoid aggregating NULL salaries, which can skew results and slow execution.
- **Adjacent concept:** This pairs with understanding execution order (`FROM` → `WHERE` → `GROUP BY` → `HAVING` → `SELECT`) and reading query plans to verify your intent matches actual execution.
- **HAVING is not redundant:** Use it when you must filter on aggregate results (e.g., `HAVING COUNT(*) > 5` or `HAVING MAX(salary) - MIN(salary) > 50000`). These *cannot* move to `WHERE`.
- **Interview tip:** When asked to optimize a query, audit the `HAVING` clause first—it's one of the quickest wins for performance if predicates are misplaced.
