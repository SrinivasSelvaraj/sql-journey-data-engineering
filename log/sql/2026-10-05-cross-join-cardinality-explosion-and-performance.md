---
date: 2026-10-05
phase: sql
topic: CROSS JOIN cardinality explosion and performance
---

# CROSS JOIN cardinality explosion and performance

*SQL for analytics and engineering*

## Concept

A CROSS JOIN produces the Cartesian product of two tables: every row from the left table paired with every row from the right table. If the left table has *m* rows and the right table has *n* rows, the result contains *m × n* rows. This explosive growth is rarely intentional in analytics queries and often signals a logic error—either a missing JOIN condition or incorrect table relationships.

CROSS JOINs matter because they can silently produce millions or billions of rows, consuming massive amounts of memory and CPU before you realize the mistake. A query that should return 100 rows might return 10 million instead, causing timeouts, memory exhaustion, or inflated aggregate results. In an interview setting, recognizing when a CROSS JOIN is about to happen and preventing it demonstrates understanding of relational logic and query optimization.

The fix is always: identify the correct JOIN key (foreign key / business logic) that relates the two tables. If no natural join key exists, reconsider whether you actually need both tables or if you need a different approach (e.g., window functions, subqueries, or aggregation). CROSS JOINs are legitimate only in narrow cases like generating calendar tables or combinatorial analyses, and these should be intentional and documented.

## Practice

**Problem:** You need to find the average salary for each job title, but you want to include a row count of how many postings exist in the dataset overall (for context). A junior engineer writes:

```sql
SELECT 
  jp.job_title_short,
  AVG(jp.salary_year_avg) AS avg_salary,
  COUNT(*) AS posting_count
FROM job_postings_fact jp
CROSS JOIN (SELECT COUNT(*) AS total_postings FROM job_postings_fact) t
GROUP BY jp.job_title_short;
```

This accidentally CROSS JOINs every row to the subquery before grouping, inflating `posting_count`. The solution avoids the join entirely:

```sql
SELECT 
  job_title_short,
  AVG(salary_year_avg) AS avg_salary,
  COUNT(*) AS posting_count,
  (SELECT COUNT(*) FROM job_postings_fact) AS total_postings
FROM job_postings_fact
GROUP BY job_title_short;
```

Or, if you must join for other reasons, use a subquery with GROUP BY:

```sql
SELECT 
  jp.job_title_short,
  AVG(jp.salary_year_avg) AS avg_salary,
  COUNT(*) AS posting_count,
  t.total_postings
FROM job_postings_fact jp
CROSS JOIN (SELECT COUNT(*) AS total_postings FROM job_postings_fact) t
GROUP BY jp.job_title_short, t.total_postings;
```

## Notes

- **Silent killer:** CROSS JOINs don't error; they just balloon row counts. Always sanity-check result cardinality against source table sizes.
- **Interview red flag:** If you see a query result 10× larger than expected, suspect missing JOIN conditions or accidental CROSS JOINs before blaming data quality.
- **Window functions prevent CROSS JOINs:** Use `COUNT(*) OVER()` or `SUM() OVER()` to attach global aggregates to detail rows without joining and duplicating.
- **Related concepts:** LEFT/RIGHT JOIN outer matches, self-joins on multiple keys, and implicit CROSS JOINs from missing WHERE conditions all interact with cardinality differently.
- **Query plan tell:** Look for `Nested Loop` or large row estimates in EXPLAIN output; a dramatic jump in rows after a join step suggests a CROSS JOIN or missing filter.
