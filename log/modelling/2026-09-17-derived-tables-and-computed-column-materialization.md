---
date: 2026-09-17
phase: modelling
topic: Derived tables and computed column materialization
---

# Derived tables and computed column materialization

*Data modelling and warehousing*

## Concept

A derived table is a temporary named result set created from a query, used to simplify complex logic or break down multi-step transformations. Computed column materialization means storing the result of a calculation (like a derived metric or transformed value) physically in the warehouse rather than computing it on-the-fly every query. Together, they solve a critical schema design problem: when business logic is buried in application code or repeated across dozens of queries, teammates either duplicate effort, introduce inconsistencies, or become dependent on you for interpretation.

Materialization matters most when a computed value is queried frequently, requires expensive calculations, or represents a single source of truth for how the business defines something (e.g., "seniority level" inferred from job title, "salary band" bucketed from raw salary, or "days since posting"). Without it, each analyst writes their own version of the calculation, metrics disagree across reports, and onboarding becomes painful.

The cost of not materializing is technical debt: slow queries that recalculate the same thing millions of times, schema documentation that lives in Slack messages, and subtle bugs when someone's bucketing logic drifts from the standard.

## Practice

**Problem:** Your analytics team needs to segment jobs by seniority level (inferred from title keywords), salary competitiveness (percentile rank within location), and whether they're "fresh" (posted in last 7 days). These are queried in 80% of reports but computed differently each time.

```sql
-- Materialized derived table approach: create a view or physical table
CREATE TABLE job_postings_enriched AS
SELECT
  job_id,
  job_title_short,
  job_location,
  salary_year_avg,
  job_work_from_home,
  job_posted_date,
  -- Seniority derived column (materialized as a new column)
  CASE
    WHEN job_title_short ILIKE '%Senior%' OR job_title_short ILIKE '%Lead%' THEN 'Senior'
    WHEN job_title_short ILIKE '%Junior%' THEN 'Junior'
    ELSE 'Mid'
  END AS seniority_level,
  -- Salary percentile within location (window function materialized)
  PERCENT_RANK() OVER (PARTITION BY job_location ORDER BY salary_year_avg) AS salary_percentile_local,
  -- Days since posted
  CURRENT_DATE - job_posted_date AS days_since_posted,
  -- Boolean flag for freshness
  (CURRENT_DATE - job_posted_date) <= 7 AS is_fresh_posting
FROM job_postings_fact;

-- Now queries are simple and consistent
SELECT seniority_level, job_location, ROUND(AVG(salary_year_avg), 2) AS avg_salary
FROM job_postings_enriched
WHERE is_fresh_posting = TRUE
GROUP BY seniority_level, job_location;
```

## Notes

- **Materialization trade-off:** Storage and refresh cost vs. query speed and consistency. Materialize when queried >5× per week or when computation is expensive (window functions, regex, ML model scoring); leave as view-only for rarely-used one-off transformations.

- **Refresh strategy matters:** Use incremental materialization (only recompute new/changed rows) rather than full refresh when the base table is large. Consider scheduling materialization during off-peak hours or triggering it after upstream ETL completes.

- **Dimension vs. fact:** Derived columns in fact tables (like `seniority_level` here) are fine; consider extracting highly reusable dimensions (e.g., `job_seniority_dim`) if that column is needed in multiple fact tables—avoids duplication.

- **Documentation is the point:** Materialization forces you to document *why* a column exists and *how* it's calculated. Add a comment block to every derived column explaining business logic and valid values; this is what makes self-service querying possible.

- **Related:** Slowly Changing Dimensions (SCD) for tracking how derived attributes change over time, dbt macro-driven materialization for DRY logic, and data quality tests on computed columns to catch drift early.
