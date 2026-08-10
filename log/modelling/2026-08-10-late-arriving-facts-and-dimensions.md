---
date: 2026-08-10
phase: modelling
topic: Late arriving facts and dimensions
---

# Late arriving facts and dimensions

*Data modelling and warehousing*

## Concept

Late arriving facts are data points (measurements, metrics) that arrive after the fact event has already been loaded into your warehouse—a salary correction arrives three weeks after a job posting, or a job's actual hire date becomes known months later. Late arriving dimensions are attributes of entities (like a company's industry classification or a candidate's verified skill level) that change or become known after the initial dimension record was created.

Without handling these, you face two problems: stale queries that don't reflect reality, and broken dimensional integrity where a fact references a dimension state that didn't exist when the fact occurred. A job posting recorded on 2024-01-15 might get a salary correction on 2024-02-01, but if your fact table is immutable, downstream reports show wrong numbers. Worse, if you update the dimension retroactively, historical queries become non-reproducible.

The solution depends on your dimensional model maturity. For late facts, add an `is_corrected` flag and load the corrected row as a new fact with a `correction_type` attribute, or use a Type 2 slowly changing dimension pattern. For dimensions, use Type 2 SCD (add `effective_date` and `end_date`) so every version of a dimension is queryable at its point-in-time.

## Practice

**Problem:** A job posting is loaded with `salary_year_avg = NULL` on 2024-01-15 because salary wasn't disclosed. On 2024-02-01, the recruiter posts the salary as 95,000. Your fact table is append-only. How do you preserve the original load state while making the corrected salary queryable without duplicating business logic?

```sql
-- Solution: add metadata columns and load corrections as separate rows
ALTER TABLE job_postings_fact 
ADD COLUMN salary_year_avg_corrected INT,
ADD COLUMN salary_correction_date DATE,
ADD COLUMN correction_source VARCHAR(50);

-- Original row (2024-01-15 load)
INSERT INTO job_postings_fact 
VALUES (1, 'Software Engineer', NULL, TRUE, '2024-01-15', 'Remote', NULL, NULL, NULL);

-- Correction row (2024-02-01 arrival)
INSERT INTO job_postings_fact 
VALUES (1, 'Software Engineer', 95000, TRUE, '2024-01-15', 'Remote', 95000, '2024-02-01', 'recruiter_update');

-- Query: always prefer corrected value if it exists, else original
SELECT job_id, job_title_short,
  COALESCE(salary_year_avg_corrected, salary_year_avg) AS salary_final,
  job_posted_date, salary_correction_date
FROM job_postings_fact
WHERE job_posted_date >= '2024-01-01'
  AND (salary_correction_date IS NULL OR salary_correction_date <= CURRENT_DATE);
```

## Notes

- **Immutability first:** resist the urge to UPDATE facts retroactively; always INSERT corrections. This preserves audit trail and makes point-in-time queries reproducible for compliance.
- **Type 2 SCD for dimensions:** add `effective_date`, `end_date`, and `is_current` columns so you can join a fact to the dimension version that was true on `fact_date`, not today.
- **Reconciliation is a separate concern:** late arrivals need a reconciliation process (daily/weekly) to detect corrections; this lives in your data quality layer, not the warehouse schema itself.
- **Grain and granularity matter:** a fact table at job-posting grain cannot easily absorb a salary correction for a single application; clarify what your fact represents before deciding how to handle late data.
- **Adjacent topics:** slowly changing dimensions (SCD), temporal tables, bi-temporal modeling, and data lineage/lineage tracking all support this pattern—revisit them together.
