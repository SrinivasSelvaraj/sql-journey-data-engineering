---
date: 2026-10-04
phase: sql
topic: Expression simplification and constant folding
---

# Expression simplification and constant folding

*SQL for analytics and engineering*

## Concept

Expression simplification and constant folding are query optimization techniques where the database (or you, during code review) reduces redundant or computable expressions into their simplest form *before* execution. Instead of evaluating `WHERE 1 = 1 AND salary > 50000` at every row, the optimizer simplifies it to `WHERE salary > 50000`. Constant folding collapses arithmetic: `WHERE hire_date > CURRENT_DATE - INTERVAL '365 days'` becomes a concrete date comparison like `WHERE hire_date > '2023-06-15'`.

This matters in analytics SQL because poorly written conditions—nested case statements, repeated subexpressions, OR chains with overlapping ranges—force the engine to do redundant work. Modern optimizers (PostgreSQL, Snowflake, BigQuery) handle many cases automatically, but *you* should write simplified queries to ensure portability, readability, and predictable plan behavior. Without deliberate simplification, you risk slow plans on less sophisticated engines, unclear intent in production code, and difficulty debugging performance issues.

Understanding what *doesn't* simplify is equally important: non-deterministic functions like `RAND()` or `CURRENT_TIMESTAMP` won't fold; correlated subqueries resist simplification; and overly complex CASE logic can block optimizations entirely. In interviews, demonstrating awareness of this—"I'm avoiding the OR trap by using IN or BETWEEN"—signals engineering discipline.

## Practice

**Problem:** You're analyzing remote job postings. Write a query that counts jobs posted in the last 90 days where salary is between $80k and $150k, OR salary is above $200k AND the role is remote. Avoid expressions that prevent optimization or are redundant.

```sql
SELECT 
  COUNT(*) as job_count,
  job_work_from_home
FROM job_postings_fact
WHERE job_posted_date >= CURRENT_DATE - INTERVAL '90 days'
  AND (
    (salary_year_avg >= 80000 AND salary_year_avg <= 150000)
    OR (salary_year_avg > 200000 AND job_work_from_home = TRUE)
  )
GROUP BY job_work_from_home
ORDER BY job_count DESC;
```

**Why this works:** The date arithmetic is folded once (not per row). The salary conditions are grouped logically—overlapping ranges in separate branches prevent double-counting. The OR is unavoidable here (two separate salary bands), but it's written clearly. Avoid: `WHERE NOT (salary < 80000 OR salary > 150000)` (double negation), `WHERE salary BETWEEN 80000 AND 150000 OR salary >= 200000` (overlapping logic), or `WHERE salary_year_avg > 0` as a safety check (unnecessary, wastes optimization).

## Notes

- **OR traps:** `salary > 80000 OR salary > 100000` simplifies to `salary > 80000`; the optimizer may miss this if written carelessly. Use UNION (set subtraction) to partition logic when distinct result sets are needed.
- **CASE simplification:** Deeply nested CASE statements resist folding and confuse the planner. Pre-compute flags in CTEs or flatten logic into WHERE clauses where feasible.
- **Correlated subquery killer:** `WHERE col IN (SELECT ... WHERE outer_col = ...)` can't fold constants; rewrite as a JOIN or window function to expose optimization opportunities.
- **Function volatility:** `WHERE created_at > NOW() - INTERVAL '7 days'` is *not* folded because NOW() is volatile. Use `CURRENT_DATE` (stable per query) or explicitly bind it (`DECLARE @cutoff = ...`) to enable constant folding.
- **Adjacent:** Connects directly to predicate pushdown, join reordering, and index selectivity; revisit when query plans show unexpected full scans despite seemingly tight filters.
