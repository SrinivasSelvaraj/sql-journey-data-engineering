---
date: 2026-08-06
phase: sql
topic: INNER JOIN vs LEFT JOIN and when each drops rows
---

# INNER JOIN vs LEFT JOIN and when each drops rows

*SQL for analytics and engineering*

## Concept

**INNER JOIN** returns only rows where a match exists in *both* tables. If a row in the left table has no corresponding row in the right table (based on the join condition), that row is dropped entirely. This is the most restrictive join type and is appropriate when you need a complete pairing—for example, matching job postings to applicants only where an application actually exists.

**LEFT JOIN** returns all rows from the left table, regardless of whether a match exists in the right table. Unmatched rows from the left table appear in the result set with NULL values in all columns from the right table. This is essential for analytics when you need to count or measure the absence of something—like identifying job postings with zero applicants, or calculating application rates.

The choice between them determines whether "no match" becomes a dropped row (INNER) or a NULL row (LEFT). In analytics queries, this distinction directly affects counts, averages, and business logic. A single wrong join type can silently produce an incorrect answer: an INNER JOIN on postings-to-applications will undercount total postings; a LEFT JOIN when you need strict pairs can introduce NULLs that break downstream aggregations.

## Practice

**Problem:** List all job postings from 2024 with their application count, showing postings even if they have zero applications. Include the job title, salary, and remote eligibility.

```sql
SELECT 
    jp.job_id,
    jp.job_title_short,
    jp.salary_year_avg,
    jp.job_work_from_home,
    COUNT(ja.application_id) AS application_count
FROM job_postings_fact jp
LEFT JOIN job_applications_fact ja
    ON jp.job_id = ja.job_id
WHERE YEAR(jp.job_posted_date) = 2024
GROUP BY jp.job_id, jp.job_title_short, jp.salary_year_avg, jp.job_work_from_home
ORDER BY application_count DESC;
```

**Why LEFT JOIN:** We want all 2024 postings in the result. If we used INNER JOIN, postings with zero applications would disappear, making it impossible to measure posting effectiveness. The LEFT JOIN keeps all postings; those without applications show `application_count = 0`.

## Notes

- **NULL handling in aggregates:** COUNT(column) ignores NULLs, so COUNT(ja.application_id) correctly returns 0 for unmatched postings. Use COUNT(*) only if you're certain no NULLs exist or want to include them.
- **Row explosion risk:** LEFT JOIN can multiply rows if the right table has duplicates or multiple matches per left row. Always validate cardinality before joining; use GROUP BY carefully to avoid inflated counts.
- **INNER JOIN as a filter:** INNER JOIN is often used defensively to filter out incomplete records. If you only want postings that *have* applications, switch to INNER—this is valid, but document the intent.
- **Query plan insight:** INNER JOINs often perform slightly better because the database can use hash joins or nested loops more aggressively. LEFT JOINs may require outer join algorithms; indexes on join keys matter even more.
- **Related topics:** FULL OUTER JOIN (all rows from both tables), CROSS JOIN (Cartesian product), and subqueries as an alternative to LEFT JOIN when you want conditional logic rather than all-or-nothing row retention.
