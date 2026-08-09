---
date: 2026-08-09
phase: python
topic: Polars and lazy evaluation
---

# Polars and lazy evaluation

*Python for data engineering*

## Concept

Lazy evaluation in Polars defers computation until explicitly triggered (`.collect()`), building a logical query plan first rather than executing transformations immediately. This matters because it enables **query optimization**: Polars can reorder operations, prune unused columns, and push filters down the stack before touching data, dramatically reducing memory and runtime for large datasets. Without lazy evaluation, each transformation creates intermediate DataFrames in memory; with it, you describe *what* you want, then Polars figures out the cheapest *how*.

In practice, lazy evaluation becomes critical when piping multiple filters, joins, and aggregations. A pipeline that works on 100 rows may crash on 10 million rows if intermediate steps materialize carelessly. Lazy evaluation also forces you to think declaratively—declaring your intent upfront—which makes pipelines more testable and portable. The catch: debugging becomes harder because errors surface only at `.collect()` time, not during `.filter()` or `.select()`.

## Practice

**Problem:** Find the average salary for remote data engineering roles posted in the last 90 days, grouped by job title short. You must handle null salaries gracefully and only include titles with at least 5 postings.

```sql
SELECT 
  job_title_short,
  COUNT(*) as posting_count,
  AVG(salary_year_avg) as avg_salary
FROM job_postings_fact
WHERE 
  job_work_from_home = TRUE
  AND job_posted_date >= CURRENT_DATE - INTERVAL 90 DAY
  AND salary_year_avg IS NOT NULL
GROUP BY job_title_short
HAVING COUNT(*) >= 5
ORDER BY avg_salary DESC
```

## Notes

- **Lazy doesn't mean free:** you still pay the cost at `.collect()`; laziness shifts *when* and *how*, not the fundamental complexity.
- **Debug with `.collect()` early:** add `.collect()` midway through a long chain to isolate where errors occur; remove it once the logic is sound.
- **Connects to:** query plans (use `.explain()` to inspect optimization), schema validation (lazy pipelines must declare types upfront), and streaming (lazy evaluation enables Polars' streaming mode for data larger than RAM).
- **Common mistake:** mixing eager and lazy operations (e.g., calling `.filter()` after `.collect()` wastes the optimization pass); keep the chain pure until the final `.collect()`.
- **Revisit:** filtering push-down and projection push-down once you hit real performance bottlenecks; understanding the plan helps you write faster pipelines intentionally.
