---
date: 2026-10-03
phase: sql
topic: Subquery materialization vs inline execution trade-offs
---

# Subquery materialization vs inline execution trade-offs

*SQL for analytics and engineering*

## Concept

A **subquery materialization** occurs when a database optimizer executes a subquery once, stores its result in memory or a temporary table, then joins or filters against it. By contrast, **inline execution** pushes the subquery logic into the outer query, treating it as a derived table that may be re-evaluated multiple times. The trade-off hinges on:

- **Materialization wins** when the subquery is expensive (aggregation over millions of rows) and referenced multiple times, or when the outer query filters heavily—compute once, reuse cheaply.
- **Inline wins** when the subquery is trivial or the optimizer can push predicates down, reducing the rows entering the subquery in the first place. Materializing a tiny result wastes memory and CPU setup.

This matters acutely in analytics because a single poorly-chosen strategy can turn a 2-second query into a 30-second one. Most modern optimizers (Postgres, BigQuery, Snowflake) make smart choices automatically, but under interview conditions or with legacy systems, explicit writing (CTEs, temporary tables) gives you control and makes the plan readable.

## Practice

**Problem:** Find job postings where the salary is above the average salary for that job title, but only consider postings from the last 90 days and only for remote jobs. Return job_id, job_title_short, and salary_year_avg.

```sql
-- Materialized approach (explicit, efficient for large data)
WITH title_avg AS (
  SELECT 
    job_title_short,
    AVG(salary_year_avg) AS avg_salary
  FROM job_postings_fact
  WHERE job_posted_date >= CURRENT_DATE - INTERVAL '90 days'
    AND job_work_from_home = TRUE
  GROUP BY job_title_short
)
SELECT 
  jp.job_id,
  jp.job_title_short,
  jp.salary_year_avg
FROM job_postings_fact jp
INNER JOIN title_avg ta
  ON jp.job_title_short = ta.job_title_short
WHERE jp.job_posted_date >= CURRENT_DATE - INTERVAL '90 days'
  AND jp.job_work_from_home = TRUE
  AND jp.salary_year_avg > ta.avg_salary;

-- Inline approach (relies on optimizer push-down)
SELECT 
  job_id,
  job_title_short,
  salary_year_avg
FROM job_postings_fact jp
WHERE job_posted_date >= CURRENT_DATE - INTERVAL '90 days'
  AND job_work_from_home = TRUE
  AND salary_year_avg > (
    SELECT AVG(salary_year_avg)
    FROM job_postings_fact
    WHERE job_title_short = jp.job_title_short
      AND job_posted_date >= CURRENT_DATE - INTERVAL '90 days'
      AND job_work_from_home = TRUE
  );
```

The **CTE version** materializes the per-title average once; the **inline version** recalculates it per row. For 100k rows and 50 titles, materialize wins. For 1k rows and 1 title, inline wins or breaks even.

## Notes

- **Correlated subqueries are dangerous**: they execute once *per outer row*. The inline example above is correlated (references `jp.job_title_short`); in a large table, this triggers O(n×m) behavior. Always prefer JOIN or CTE unless the outer set is tiny.
- **EXPLAIN is your friend**: run `EXPLAIN ANALYZE` before and after refactoring. You'll see `Seq Scan` vs `Index Scan`, cache hits, and actual row counts—the truth about whether your intuition was right.
- **Database-specific optimizers vary**: Postgres' planner is conservative and benefits from explicit CTEs; BigQuery and Snowflake are aggressive and often choose well on their own. Know your engine's reputation.
- **Common mistake: over-materializing trivial subqueries**: if your subquery is `SELECT 1` or a tiny lookup table, inline it. The CTE overhead exceeds the benefit.
- **Adjacent topic**: query optimization ties to cardinality estimation, join order, and predicate push-down. Understanding why a plan is *bad* requires reading the estimated vs. actual row counts at each step.
