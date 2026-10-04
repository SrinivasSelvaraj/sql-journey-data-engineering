---
date: 2026-10-04
phase: sql
topic: HAVING vs WHERE clause placement and performance
---

# HAVING vs WHERE clause placement and performance

*SQL for analytics and engineering*

## Concept

**WHERE** filters rows *before* aggregation; **HAVING** filters groups *after* aggregation. This distinction is critical for both correctness and performance. WHERE is evaluated early in the query execution pipeline, reducing the dataset before expensive GROUP BY operations. HAVING operates on aggregate results (COUNT, SUM, AVG, etc.) and can only reference columns in the GROUP BY clause or aggregate functions.

The performance implication is significant: a WHERE clause that eliminates 90% of rows before grouping will dramatically reduce computation cost compared to grouping everything first, then filtering with HAVING. Conversely, you *cannot* use WHERE to filter on an aggregate—attempting `WHERE COUNT(*) > 5` will fail. This forces you to use HAVING when your filter depends on a computed aggregate value.

Common mistake: writing `WHERE job_salary_year_avg > 100000 GROUP BY job_title_short HAVING COUNT(*) > 10` when you could write `WHERE job_salary_year_avg > 100000 GROUP BY job_title_short` if the salary filter doesn't need to reference an aggregate. Every row-level filter belongs in WHERE for optimal execution.

## Practice

**Problem:** Find job titles with more than 50 postings, where the average salary is above $120k, and only count postings from the last 6 months.

```sql
SELECT 
  job_title_short,
  COUNT(*) as posting_count,
  AVG(salary_year_avg) as avg_salary
FROM job_postings_fact
WHERE job_posted_date >= CURRENT_DATE - INTERVAL '6 months'
  AND salary_year_avg IS NOT NULL
GROUP BY job_title_short
HAVING COUNT(*) > 50
  AND AVG(salary_year_avg) > 120000
ORDER BY posting_count DESC;
```

The WHERE clause eliminates null salaries and old postings early. HAVING filters groups by their computed aggregates (count and average), which cannot be evaluated until after GROUP BY completes.

## Notes

- **WHERE on aggregates fails**: `WHERE COUNT(*) > 5` throws a syntax error; must use HAVING. Remember: aggregate functions are not allowed in WHERE.
- **Row-level filters always go in WHERE**: Even if you're later grouping, any filter on raw column values (salary, date, location) belongs in WHERE for query optimizer benefit.
- **HAVING without GROUP BY is valid but rare**: Filters the entire result set as a single group; useful for aggregate constraints on non-grouped queries, but often confusing.
- **Query plan insight**: Run EXPLAIN ANALYZE to confirm WHERE filters execute before the aggregation node; this visual proof helps internalize the performance difference.
- **Adjacent topics**: Index selectivity (putting selective WHERE predicates first helps index usage), query optimizer statistics (the planner uses row estimates to decide whether to filter early), and aggregate pushdown in distributed systems (Spark/Presto push filters into GROUP BY when possible).
