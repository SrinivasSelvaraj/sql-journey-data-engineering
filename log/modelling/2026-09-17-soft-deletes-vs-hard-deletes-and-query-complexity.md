---
date: 2026-09-17
phase: modelling
topic: Soft deletes vs hard deletes and query complexity
---

# Soft deletes vs hard deletes and query complexity

*Data modelling and warehousing*

## Concept

A **soft delete** marks a record as inactive (typically with an `is_deleted` or `valid_from`/`valid_to` timestamp) without removing it from the database. A **hard delete** permanently removes the row. In data warehousing, soft deletes are usually the right choice because they preserve historical accuracy and audit trails—you can still answer "what jobs were active on 2024-01-15?" even if they're no longer hiring.

The tradeoff is query complexity. Every query must filter `WHERE is_deleted = FALSE` or check date ranges, or you'll accidentally include stale data in your reports. Without disciplined design, analysts will write incorrect aggregations and you'll spend time debugging why job counts are inflated. Hard deletes are simpler for queries but catastrophic for analytics: you lose the ability to reconstruct history, debug data issues, or comply with audit requirements.

This matters most when your data changes state (jobs close, employees leave, prices adjust). A well-designed schema makes the correct filter so obvious that mistakes become rare—this is the "design schemas a team can query without asking you" principle.

## Practice

**Problem:** You're asked to report total active job postings by month. The `job_postings_fact` table has been in production for two years and some jobs have been deleted. Without soft deletes, you can't distinguish "jobs never existed" from "jobs existed but were removed," so your historical counts are wrong.

```sql
-- Assume schema includes: is_deleted BOOLEAN, job_posted_date DATE, job_closed_date DATE (NULL if still open)

SELECT
  DATE_TRUNC('month', job_posted_date) AS month,
  COUNT(DISTINCT job_id) AS active_jobs
FROM job_postings_fact
WHERE is_deleted = FALSE
  AND job_posted_date <= DATE_TRUNC('month', DATE_TRUNC('month', CURRENT_DATE) + INTERVAL '1 month')
  AND (job_closed_date IS NULL OR job_closed_date >= DATE_TRUNC('month', DATE_TRUNC('month', CURRENT_DATE)))
GROUP BY 1
ORDER BY 1 DESC;
```

Better yet, use a `valid_from`/`valid_to` pattern so the filter is implicit in business logic:

```sql
-- job_postings_fact includes: valid_from TIMESTAMP, valid_to TIMESTAMP (NULL if current)

SELECT
  DATE_TRUNC('month', valid_from) AS month,
  COUNT(DISTINCT job_id) AS active_jobs
FROM job_postings_fact
WHERE valid_to IS NULL
GROUP BY 1
ORDER BY 1 DESC;
```

## Notes

- **Common mistake:** Adding `is_deleted` *after* data has been hard-deleted in production. Start with soft deletes on day one; retroactively recovering deleted data is nearly impossible.
- **Adjacent concept:** Slowly Changing Dimensions (SCD Type 2) uses `valid_from`/`valid_to` for handling historical changes to dimension tables—soft deletes are a special case of this.
- **Query readability > brevity:** A 3-line WHERE clause is better than a 1-line clause if the longer version is self-documenting. Name your columns `is_logically_deleted` if it reduces confusion.
- **Compliance angle:** Many industries (finance, healthcare, legal) require audit trails. Hard deletes can violate regulations; soft deletes with immutable timestamps often do not.
- **Revisit:** Think about whether you need *versioning* (SCD 2 with full row history) vs. just soft deletes (single current row + tombstone).
