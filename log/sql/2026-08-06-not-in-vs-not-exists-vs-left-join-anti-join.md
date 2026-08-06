---
date: 2026-08-06
phase: sql
topic: NOT IN vs NOT EXISTS vs LEFT JOIN anti-join
---

# NOT IN vs NOT EXISTS vs LEFT JOIN anti-join

*SQL for analytics and engineering*

## Concept

An **anti-join** finds rows in one table that have no matching rows in another—a critical pattern for "find what's missing" queries. Three syntaxes exist: `NOT IN`, `NOT EXISTS`, and `LEFT JOIN` with a null filter. Performance varies dramatically depending on nullability and cardinality.

`NOT IN` is intuitive but dangerous: if the subquery contains *any* NULL, the entire result becomes empty (NULL comparisons always return UNKNOWN in SQL). `NOT EXISTS` is explicit and null-safe by construction—it checks existence, not equality. `LEFT JOIN` with an anti-join filter (`WHERE table2.id IS NULL`) is typically the fastest on modern optimizers because it's explicit about the join strategy and allows the planner to push predicates aggressively.

When it matters: large datasets, nullable foreign keys, or subqueries filtering millions of rows. A misunderstood anti-join can silently return zero rows or perform a full table scan when an index-backed join would complete in milliseconds.

## Practice

**Problem:** Find all job postings that have *never* been applied to (no record exists in an applications table).

Given schema extension:
- `applications_fact(application_id, job_id, application_date)`

Return job_id, job_title_short, and job_posted_date for jobs with zero applications, sorted by job_posted_date DESC.

```sql
-- Solution: LEFT JOIN anti-join (most performant)
SELECT 
    j.job_id,
    j.job_title_short,
    j.job_posted_date
FROM job_postings_fact j
LEFT JOIN applications_fact a ON j.job_id = a.job_id
WHERE a.job_id IS NULL
ORDER BY j.job_posted_date DESC;

-- Alternative: NOT EXISTS (also safe, explicit intent)
SELECT 
    j.job_id,
    j.job_title_short,
    j.job_posted_date
FROM job_postings_fact j
WHERE NOT EXISTS (
    SELECT 1 FROM applications_fact a WHERE a.job_id = j.job_id
)
ORDER BY j.job_posted_date DESC;
```

## Notes

- **NOT IN gotcha:** `WHERE job_id NOT IN (SELECT job_id FROM applications_fact WHERE job_id IS NULL)` returns 0 rows even if applications_fact is empty, because NULL breaks the logic. Avoid unless you're certain the subquery column is non-nullable.
- **Query plan inspection:** `EXPLAIN` the three approaches on your target database (PostgreSQL, Snowflake, BigQuery); the planner often prefers LEFT JOIN because it's join-order-agnostic and better at cardinality estimation.
- **Correlated vs. uncorrelated:** NOT EXISTS uses a correlated subquery (inner query references outer table); optimizer may rewrite it as a join anyway, but the syntax makes intent clear.
- **Nullable vs. non-nullable keys:** If the join column is nullable on either side, NULL rows won't match—verify schema. This is correct for true anti-joins but a common source of surprises.
- **Related patterns:** EXCEPT/MINUS (set difference), FULL OUTER JOIN for reconciliation tasks, and SEMI-JOIN (the dual—find what *does* exist); all share optimization considerations.
