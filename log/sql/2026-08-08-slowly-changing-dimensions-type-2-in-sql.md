---
date: 2026-08-08
phase: sql
topic: Slowly changing dimensions type 2 in SQL
---

# Slowly changing dimensions type 2 in SQL

*SQL for analytics and engineering*

## Concept

A Slowly Changing Dimension Type 2 (SCD2) tracks *all* historical versions of a dimension record, assigning each version a unique surrogate key and adding effective date ranges (`valid_from`, `valid_to`) or version flags. This differs from Type 1 (overwrite) and Type 3 (limited history columns). SCD2 is essential when you need to join facts to the *correct version* of a dimension as it existed at transaction time—e.g., joining a job posting to the job title *as it was when posted*, not the current title if it changed later.

Without SCD2, you lose auditability and temporal accuracy. A salary correction or title change in your dimension table overwrites history, breaking retroactive analysis: "What was the median salary for 'Data Analyst' roles posted in Q1 2023?" becomes impossible if titles were renamed. SCD2 forces you to decide: do facts reference a dimension's *current* state (Type 1 risky) or its *historical* state (Type 2 correct)?

Implementation typically involves:
- Adding `valid_from` (start date) and `valid_to` (end date or NULL for current)
- Inserting new rows when attributes change, not updating existing ones
- Joining facts to dimensions on both the fact's date and the dimension's date range
- Using window functions (`ROW_NUMBER()`, `LEAD()`) or temporal joins to identify changes

## Practice

**Problem:** You have a `job_postings_fact` table and need to build a `jobs_dim` that tracks title and location changes over time. A job posting on 2024-01-15 should use the job title/location that was *current on 2024-01-15*, even if the job was updated later. Write a query that joins postings to the correct dimension version and reports average salary by job title *as it was at posting time*.

```sql
-- Build SCD2 dimension from raw job updates
WITH job_changes AS (
  SELECT 
    job_id,
    job_title_short,
    job_location,
    job_posted_date,
    LEAD(job_posted_date) OVER (PARTITION BY job_id ORDER BY job_posted_date) AS next_change_date
  FROM job_postings_fact
  WHERE job_posted_date IS NOT NULL
)
SELECT 
  jp.job_id,
  jp.job_title_short AS title_at_posting,
  jp.job_location AS location_at_posting,
  ROUND(AVG(jp.salary_year_avg), 0) AS avg_salary
FROM job_postings_fact jp
INNER JOIN job_changes jd
  ON jp.job_id = jd.job_id
  AND jp.job_posted_date >= jd.job_posted_date
  AND (jp.job_posted_date < jd.next_change_date OR jd.next_change_date IS NULL)
GROUP BY jp.job_title_short, jp.job_location
ORDER BY avg_salary DESC;
```

## Notes

- **Off-by-one pitfall:** Test boundary conditions carefully—is a fact valid from `valid_from` inclusive and `valid_to` exclusive (standard) or inclusive on both ends? Misalignment causes missing/duplicate joins.
- **Performance cost:** SCD2 queries often require range joins (`BETWEEN` or `>=` + `<`), which can slow down without proper indexing on date columns; consider clustered columnstore indexes or materialized intermediate tables for large warehouses.
- **Adjacent topics:** Temporal tables (SQL Server, PostgreSQL), bi-temporal modeling (valid time vs. transaction time), and fact table grain—verify facts and dimensions share the same granularity before joining.
- **Common mistake:** Forgetting to handle the "current" record (last `valid_to` is NULL or `9999-12-31`) separately in WHERE clauses; filter explicitly or use `ISNULL(valid_to, GETDATE()) >= fact_date`.
- **Revisit:** Compare SCD2 to bridge tables for many-to-many dimensions and to Kimball's conformed dimension patterns; know when to denormalize dimension history into fact tables instead.
