---
date: 2026-08-06
phase: sql
topic: Common table expressions and readability
---

# Common table expressions and readability

*SQL for analytics and engineering*

## Concept

A Common Table Expression (CTE) is a named temporary result set defined with a `WITH` clause that exists only for the duration of a single query. CTEs improve readability by breaking complex logic into named, sequential steps—each CTE represents a logical transformation you can reference later. This is especially critical in analytics and interview settings where your query may chain 3–5 aggregations or filters; without CTEs, you'd nest subqueries deeply, making the query hard to scan and debug.

CTEs matter most when you need to reference the same intermediate result multiple times, or when you're building a query incrementally during an interview and need to reason about each step. Without them, nested subqueries become visually tangled and errors propagate up; with them, you can test each CTE independently and compose logic clearly. They also make your intent explicit—a well-named CTE like `remote_high_earners` documents what that step computes far better than a nested SELECT ever could.

One pitfall: CTEs do not inherently optimize performance. The database still executes them as a logical unit; if a CTE is referenced multiple times, the optimizer may or may not materialize it separately. In an interview, prioritize clarity first—optimize only if asked about performance or if you spot an obvious redundancy.

## Practice

**Problem:** Find the average salary for remote job postings by job title, but only for titles that have at least 10 postings and where the average salary exceeds $100k. Rank these titles by average salary descending.

```sql
WITH remote_jobs AS (
  SELECT
    job_title_short,
    salary_year_avg,
    job_posted_date
  FROM job_postings_fact
  WHERE job_work_from_home = TRUE
    AND salary_year_avg IS NOT NULL
),
salary_by_title AS (
  SELECT
    job_title_short,
    COUNT(*) AS posting_count,
    AVG(salary_year_avg) AS avg_salary
  FROM remote_jobs
  GROUP BY job_title_short
),
filtered_titles AS (
  SELECT
    job_title_short,
    posting_count,
    avg_salary
  FROM salary_by_title
  WHERE posting_count >= 10
    AND avg_salary > 100000
)
SELECT
  job_title_short,
  posting_count,
  avg_salary,
  ROW_NUMBER() OVER (ORDER BY avg_salary DESC) AS salary_rank
FROM filtered_titles
ORDER BY salary_rank;
```

## Notes

- **Naming is critical**: Use descriptive CTE names (`remote_jobs`, `salary_by_title`) so your query reads like prose; avoid generic names like `temp` or `x`.
- **Order matters**: CTEs are evaluated top-to-bottom and can reference earlier CTEs but not later ones. Plan your logic flow before writing.
- **Test incrementally**: In an interview, build and validate each CTE step separately; once `remote_jobs` works, move to the next layer. This catches bugs early and shows structured thinking.
- **CTEs vs. subqueries**: Both are valid; CTEs win on readability when you have 2+ logical steps. Subqueries are fine for single nested filters—use judgment, not dogma.
- **Recursive CTEs**: A more advanced pattern (using `WITH RECURSIVE`) useful for hierarchies or iterative logic; not common in analytics, but worth knowing exists.
