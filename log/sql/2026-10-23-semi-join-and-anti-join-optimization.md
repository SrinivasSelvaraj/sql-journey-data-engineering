---
date: 2026-10-23
phase: sql
topic: Semi-join and anti-join optimization
---

# Semi-join and anti-join optimization

*SQL for analytics and engineering*

## Concept

A **semi-join** returns rows from the left table where at least one match exists in the right table, without duplicating rows or returning any columns from the right table. An **anti-join** returns rows from the left table where *no* match exists in the right table. Both are optimization opportunities because they short-circuit: a semi-join stops scanning the right table once a match is found per left row, and an anti-join can use NOT EXISTS with an early exit condition.

In analytics, semi-joins appear when you want to filter one table by the existence of records in another (e.g., "show me job postings from companies that have posted remote work roles"). Anti-joins appear when you want exclusions (e.g., "show me postings that have never received an application"). Without optimization, you might inadvertently write a LEFT JOIN followed by WHERE right_id IS NULL, which forces a full join and then filtering—wasteful and prone to cardinality bugs.

The key difference from an INNER JOIN: semi/anti joins don't multiply rows. If one job_posting matches five companies, an INNER JOIN explodes to five rows; a semi-join returns one. This matters enormously for large fan-out scenarios and is why query optimizers (Postgres, Snowflake, BigQuery) recognize semi/anti patterns and rewrite them efficiently.

## Practice

**Problem:** List all job postings from the last 30 days that are in locations where at least one remote-work-eligible role has been posted, but exclude postings from companies that have never posted a salary.

```sql
SELECT 
  job_id,
  job_title_short,
  job_location,
  job_posted_date
FROM job_postings_fact j
WHERE job_posted_date >= CURRENT_DATE - INTERVAL '30 days'
  -- Semi-join: location must appear in a remote posting
  AND job_location IN (
    SELECT DISTINCT job_location
    FROM job_postings_fact
    WHERE job_work_from_home = TRUE
  )
  -- Anti-join: exclude postings where salary_year_avg is NULL
  AND NOT EXISTS (
    SELECT 1
    FROM job_postings_fact j2
    WHERE j2.job_id = j.job_id
      AND j2.salary_year_avg IS NULL
  )
ORDER BY job_posted_date DESC;
```

Alternatively, using explicit semi-join syntax (Postgres 9.6+, most modern engines):
```sql
SELECT 
  job_id,
  job_title_short,
  job_location,
  job_posted_date
FROM job_postings_fact j
WHERE job_posted_date >= CURRENT_DATE - INTERVAL '30 days'
  AND salary_year_avg IS NOT NULL
  AND EXISTS (
    SELECT 1
    FROM job_postings_fact j_remote
    WHERE j_remote.job_location = j.job_location
      AND j_remote.job_work_from_home = TRUE
  );
```

## Notes

- **Mistake:** Writing `LEFT JOIN … WHERE right_id IS NOT NULL` instead of `EXISTS` or `IN`—you lose the semi-join optimization and materialize the entire right table.
- **Mistake:** Using `IN (SELECT …)` with NULL values in the subquery; NULL makes the condition unknown, filtering out rows unexpectedly. Always filter nulls in semi-join subqueries or use `EXISTS`.
- **Connection:** Semi/anti-join optimization is closely tied to **subquery unnesting** and **query rewriting**. Optimizers convert `IN` to `EXISTS` and decide whether to hash-join or nested-loop based on cardinality estimates.
- **Interview note:** When asked to optimize a slow query, look for LEFT/INNER JOINs that could be semi/anti-joins. Mention cardinality and index selectivity; it signals you understand execution cost.
- **Revisit:** Understand how your specific database handles these—Postgres EXPLAIN shows "Semi Join" nodes, Snowflake and BigQuery abstract it, but the principle is identical.
