---
date: 2026-11-06
phase: sql
topic: Query compilation: parsing, optimization and code generation
---

# Query compilation: parsing, optimization and code generation

*SQL for analytics and engineering*

## Concept

Query compilation transforms SQL text into an executable plan through three stages: the **parser** converts text into an abstract syntax tree (AST), the **optimizer** rewrites the logical plan using cost-based heuristics (join order, predicate pushdown, index selection), and the **code generator** produces physical operators (scans, hash joins, sorts) that the execution engine runs. This process is invisible to you but critical: a poorly optimized query can execute 100× slower than a well-reasoned one, even though both return identical results.

Understanding query plans matters most when you hit performance cliffs—a query that ran in 2 seconds yesterday now takes 30 seconds because the optimizer chose a bad join order or full table scan instead of an index. You reason about plans by reading EXPLAIN output (or EXPLAIN ANALYZE in PostgreSQL), spotting expensive operations like nested-loop joins or sequential scans on large tables, and rewriting your SQL to give the optimizer better hints: adding predicates earlier, restructuring joins, or materializing subqueries to reduce cardinality before expensive operations.

Without a mental model of compilation, you write queries that are "correct" but wasteful—selecting 50 columns when you need 3, joining before filtering, or using correlated subqueries that run once per row instead of once total. This is where the gap between "works" and "production-ready" lives.

## Practice

**Problem:** You have 500k job postings. Find the average salary for each job title, but only for US-based remote jobs posted in the last 90 days, ranked by count of postings (descending). Your first attempt is slow.

```sql
SELECT 
  job_title_short,
  COUNT(*) as posting_count,
  ROUND(AVG(salary_year_avg), 2) as avg_salary
FROM job_postings_fact
WHERE 
  job_work_from_home = TRUE
  AND job_location LIKE '%US%'
  AND job_posted_date >= CURRENT_DATE - INTERVAL '90 days'
  AND salary_year_avg IS NOT NULL
GROUP BY job_title_short
ORDER BY posting_count DESC;
```

**Why this works:** Predicates (WHERE clause) filter earliest, reducing rows before the expensive GROUP BY aggregation. NULL filtering on salary_year_avg prevents misleading averages. The LIKE is a known weakness (indexes can't optimize it well), but job_posted_date and job_work_from_home filter first and should have indexes. GROUP BY happens only on filtered data. ROUND in SELECT is cheap. If this still runs slow, check EXPLAIN—if you see a Seq Scan on job_postings_fact, you're missing an index on (job_work_from_home, job_posted_date, salary_year_avg).

## Notes

- **Predicate pushdown:** Always filter as early as possible. A WHERE clause on raw data beats the same filter applied after a JOIN or aggregation—it reduces cardinality, enabling smaller intermediate results and better index use.

- **Index alignment:** Your WHERE and JOIN predicates should match indexed columns; adding an index on (job_work_from_home, job_posted_date) lets the optimizer use a range scan instead of a full table scan. Check EXPLAIN to confirm the plan uses it.

- **Join order matters:** A query with three joins can have 12 different execution orders. Cost-based optimizers choose well most of the time, but if your stats are stale (ANALYZE not run recently), the optimizer guesses wrong. Reorder JOINs by selectivity: filter most-restrictive tables first.

- **Cardinality estimation:** Optimizers rely on row count estimates (from table statistics). If estimates are wildly wrong, so is the plan. Run ANALYZE regularly; if one table has changed a lot, ANALYZE just that table before a large query.

- **Adjacent concepts:** Query plans connect to indexing strategy, statistics/ANALYZE behavior, and execution models (cost vs. rule-based); understanding one illuminates the others. Revisit after studying execution engines or when debugging slow queries in production.
