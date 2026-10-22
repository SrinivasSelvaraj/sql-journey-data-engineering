---
date: 2026-10-22
phase: sql
topic: Join order optimization and cardinality estimation
---

# Join order optimization and cardinality estimation

*SQL for analytics and engineering*

## Concept

Join order optimization determines the sequence in which tables are combined in a multi-table query. The optimizer uses cardinality estimation—predictions of how many rows pass each filter and intermediate join—to choose a join order that minimizes total cost (I/O, CPU, memory). A query joining three tables can execute in six different orders; choosing poorly can mean scanning millions of unnecessary rows.

Cardinality estimation feeds directly into join order decisions. If the optimizer underestimates how many rows survive a WHERE clause, it may choose a join order that processes huge intermediate result sets. If it overestimates, it might build a hash table in memory that spills to disk. Predicate pushdown—filtering early—reduces cardinality before expensive joins, but only if the optimizer correctly estimates the selectivity of your WHERE conditions.

Without proper join order and accurate cardinality estimates, queries that *should* run in seconds run in minutes or hours. This is especially painful in analytics: a dashboard query with three joins and a few filters can become unusable if the optimizer picks the wrong starting table or misestimates a date range filter.

## Practice

**Problem:** Write a query that finds job titles posted in the last 30 days with above-median salary, joined with a count of total postings per title. Ensure the query filters early and consider join order.

```sql
WITH salary_stats AS (
  SELECT PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY salary_year_avg) AS median_salary
  FROM job_postings_fact
  WHERE salary_year_avg IS NOT NULL
),
recent_high_pay AS (
  SELECT 
    job_title_short,
    COUNT(*) AS posting_count,
    ROUND(AVG(salary_year_avg)) AS avg_salary
  FROM job_postings_fact
  WHERE job_posted_date >= CURRENT_DATE - INTERVAL '30 days'
    AND salary_year_avg IS NOT NULL
  GROUP BY job_title_short
  HAVING AVG(salary_year_avg) > (SELECT median_salary FROM salary_stats)
)
SELECT 
  job_title_short,
  posting_count,
  avg_salary
FROM recent_high_pay
ORDER BY avg_salary DESC;
```

**Why this works:** The WHERE clause filters by date *first* (reducing cardinality dramatically before aggregation), NULL checks prevent mismatches in salary calculation, and the subquery (cardinality: one row) joins via HAVING after grouping. A naive left-join approach would aggregate the full fact table, then filter—orders of magnitude slower.

## Notes

- **Selectivity estimation**: Predicates with unknown value distributions (LIKE patterns, complex expressions) confuse optimizers. Write simple, sargable conditions when possible (e.g., `date >= X` beats `EXTRACT(YEAR FROM date) = 2024`).
- **Statistics and table hints**: Cardinality estimation depends on up-to-date table statistics. In interviews, mention `ANALYZE TABLE` or optimizer hints if performance seems obviously wrong despite correct logic.
- **Join vs. GROUP BY**: Joining a fact table to a dimension with a many-to-one relationship then grouping is often slower than grouping first. Pre-aggregate or use window functions to avoid bloated intermediate sets.
- **Subqueries and CTEs**: A CTE or inline subquery that returns one row (like a MAX or MEDIAN) is cheap to join; mention this when explaining join order choices to show cardinality awareness.
- **Revisit:** Query plan reading (EXPLAIN), index design for join columns, and filter selectivity tuning; these three topics form a feedback loop with join optimization.
