---
date: 2026-08-22
phase: pipelines
topic: Rolling schema migrations with zero downtime
---

# Rolling schema migrations with zero downtime

*Pipelines and orchestration*

## Concept

Rolling schema migrations allow you to evolve your data warehouse without stopping pipelines or breaking downstream consumers. The key is deploying schema changes in phases: add the new column/table first, run both old and new logic in parallel, then cut over consumers, then remove old code. This matters because production pipelines are often 24/7, and a schema lock that halts writes for 30 minutes can cascade into SLO breaches, missed data windows, and alerting chaos.

Without rolling migrations, you face a choice: take downtime (acceptable for data lakes, dangerous for real-time systems) or have your ETL fail mid-run when it hits a schema mismatch. The risk is highest when source systems and target schemas diverge—your pipeline reads a new column the warehouse doesn't have yet, or writes to a table mid-restructure. Loud failures matter here: a pipeline should not silently drop data or use NULL as a fallback.

The pattern is: *expand → migrate → contract*. Expand by adding columns as nullable or with defaults. Migrate by backfilling and running dual writes. Contract by removing old columns only after all consumers have moved. Each phase is independently reversible.

## Practice

**Problem:** `job_postings_fact` needs a new column `salary_range_category` (LOW, MID, HIGH) derived from `salary_year_avg`. The warehouse is live, pipelines insert 50k rows/day, and three dashboards query this table. You cannot stop writes.

```sql
-- Phase 1: Expand (safe, deployed immediately)
ALTER TABLE job_postings_fact
ADD COLUMN salary_range_category VARCHAR(10) NULL;

-- Phase 2: Migrate (run alongside existing pipeline)
-- Old pipeline continues writing to job_postings_fact (salary_year_avg only)
-- New pipeline writes both columns:
INSERT INTO job_postings_fact (
  job_id, job_title_short, salary_year_avg, job_work_from_home,
  job_posted_date, job_location, salary_range_category
)
SELECT
  job_id, job_title_short, salary_year_avg, job_work_from_home,
  job_posted_date, job_location,
  CASE
    WHEN salary_year_avg < 60000 THEN 'LOW'
    WHEN salary_year_avg BETWEEN 60000 AND 120000 THEN 'MID'
    ELSE 'HIGH'
  END AS salary_range_category
FROM staging_job_postings
WHERE job_posted_date > CURRENT_DATE - 1;

-- Backfill existing rows (run once in a non-peak window)
UPDATE job_postings_fact
SET salary_range_category = CASE
  WHEN salary_year_avg < 60000 THEN 'LOW'
  WHEN salary_year_avg BETWEEN 60000 AND 120000 THEN 'MID'
  ELSE 'HIGH'
END
WHERE salary_range_category IS NULL;

-- Phase 3: Constraint and switch
-- Once all consumers use salary_range_category, make it NOT NULL
ALTER TABLE job_postings_fact
ALTER COLUMN salary_range_category SET NOT NULL;

-- Phase 4: Contract (remove old logic only after dashboards re-point)
-- Remove old salary-based filtering from upstream; old pipeline can stop.
```

## Notes

- **Nullable columns are your friend:** Always add new columns with NULL defaults; this lets readers ignore them and writers gradually populate. Avoid NOT NULL constraints until backfill is complete and tested.
- **Dual-write complexity:** Running old and new logic in parallel for weeks is operationally expensive; use feature flags in your orchestrator (dbt vars, Airflow branching) to toggle which pipeline runs, and monitor row counts to catch divergence.
- **Versioning and contracts:** Pair schema migrations with data contracts (e.g., Great Expectations validations); your pipeline should fail loudly if a column goes missing or a type changes unexpectedly, not silently cast or drop.
- **Adjacent topic—backward compatibility:** This connects closely to API versioning patterns; treat your warehouse schema as a contract that downstream services depend on, and version it explicitly (v1, v2 suffixes on tables) if you need to support concurrent consumers.
- **Rewind always:** Keep the old table or column around for 1–2 pay periods in case a downstream consumer you didn't know about breaks; use a "deprecated" marker and a date for safe removal.
