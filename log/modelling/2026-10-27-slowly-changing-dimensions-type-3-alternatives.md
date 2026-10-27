---
date: 2026-10-27
phase: modelling
topic: Slowly changing dimensions type 3 alternatives
---

# Slowly changing dimensions type 3 alternatives

*Data modelling and warehousing*

## Concept

Slowly Changing Dimension (SCD) Type 3 tracks *limited history* by adding "current" and "previous" columns to a dimension table, rather than creating new rows (Type 2) or overwriting (Type 1). When a job title changes from "Junior Developer" to "Senior Developer," you store both the old and new value in separate columns, keeping only one row per entity.

This matters when you need to answer questions like "how did job titles shift over time?" without maintaining a full audit trail. It's economical—fewer rows than Type 2—but it only preserves *one previous state*, making it unsuitable for tracking frequent changes or analyzing multi-step transitions. Without it, you either lose historical context entirely or bloat your warehouse with redundant historical rows.

Type 3 breaks down when stakeholders ask "what was the job title two updates ago?" or when dimensions change frequently; in those cases, Type 2 (versioning with surrogate keys and effective dates) becomes necessary.

## Practice

**Problem:** Your `job_postings_fact` currently overwrites `job_title_short` each time a posting is updated. You need to report on how job titles evolved without losing the ability to join to the current posting record.

```sql
CREATE TABLE job_dim (
    job_id INT PRIMARY KEY,
    job_title_short_current VARCHAR(100),
    job_title_short_previous VARCHAR(100),
    salary_year_avg_current INT,
    salary_year_avg_previous INT,
    job_work_from_home BOOLEAN,
    last_updated DATE
);

-- On update: shift current → previous, insert new value into current
UPDATE job_dim
SET job_title_short_previous = job_title_short_current,
    salary_year_avg_previous = salary_year_avg_current,
    job_title_short_current = 'Senior Developer',
    salary_year_avg_current = 145000,
    last_updated = CURRENT_DATE
WHERE job_id = 42;

-- Query shows both states in one row
SELECT job_id, job_title_short_previous, job_title_short_current, last_updated
FROM job_dim
WHERE job_id = 42;
```

## Notes

- **Mistake:** Using Type 3 for high-cardinality changes (e.g., stock prices, sensor readings); Type 2 or a fact table snapshot is better.
- **Mistake:** Forgetting to null-check `_previous` columns on first insert; initialize them as NULL or with the same value as `_current`.
- **Adjacent topic:** Compare to Type 2 (surrogate keys + effective date ranges) when you need full audit trails; Type 3 is the middle ground between Type 1 (no history) and Type 2 (full history).
- **Revisit:** When modeling, ask "do we ever need to report on more than one previous value?" If yes, switch to Type 2 immediately.
- **Implementation note:** Type 3 works well for "current vs. previous" KPI comparisons in dashboards; pair it with a `dbt` macro to automate the shift logic.
