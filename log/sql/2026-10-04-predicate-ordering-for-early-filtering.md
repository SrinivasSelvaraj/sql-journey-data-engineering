---
date: 2026-10-04
phase: sql
topic: Predicate ordering for early filtering
---

# Predicate ordering for early filtering

*SQL for analytics and engineering*

## Concept

Predicate ordering determines which filter conditions execute earliest in a query execution plan. Modern query optimizers reorder predicates automatically, but understanding the logical order helps you reason about performance and write queries the optimizer can better understand. Early filtering—applying the most selective predicates first—reduces the dataset size before joins, aggregations, or expensive operations occur, directly lowering CPU, memory, and I/O costs.

In practice, place predicates that eliminate the most rows earliest in your WHERE clause, and push filters as close to the data source as possible (into subqueries, CTEs, or join conditions rather than after aggregation). Filtering *after* a join or GROUP BY is almost always slower than filtering before, because you've already computed results on a larger dataset. Without deliberate predicate ordering, you risk full table scans, cartesian products, or aggregating millions of rows only to discard 99% of them.

## Practice

**Problem:** You need to find the average salary for data engineer roles posted in the last 90 days that allow remote work. The job_postings_fact table has 2 million rows, with 40% remote-eligible and 15% posted in the last 90 days. Write a query that filters efficiently.

```sql
SELECT 
  job_title_short,
  AVG(salary_year_avg) AS avg_salary,
  COUNT(*) AS job_count
FROM job_postings_fact
WHERE job_posted_date >= CURRENT_DATE - INTERVAL '90 days'
  AND job_work_from_home = TRUE
  AND salary_year_avg IS NOT NULL
  AND job_title_short ILIKE '%Data Engineer%'
GROUP BY job_title_short
ORDER BY avg_salary DESC;
```

The predicates are ordered from most to least selective: date filter (15% pass), then remote flag (40% of remainder), then non-null salary check, then title match. This reduces the working set before GROUP BY.

## Notes

- **Optimizer limitations:** Some databases (especially older versions or certain engines) don't reorder predicates well; writing them in logical order is defensive and makes your intent clear.
- **JOIN predicates matter more:** Push filters into ON clauses when possible rather than WHERE; `ON t1.id = t2.id AND t2.status = 'active'` is faster than joining first then filtering.
- **NULL checks are selective:** `IS NOT NULL` and `IS NULL` are cheap absolute filters; place them early if they eliminate significant rows.
- **String pattern matching is expensive:** ILIKE, LIKE, and regex are slower than equality; move them later in the predicate chain if other filters are more selective.
- **Revisit:** EXPLAIN ANALYZE to verify predicate order in your actual plan; sometimes indexes change which order the optimizer chooses.
