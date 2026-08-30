---
date: 2026-08-30
phase: modelling
topic: Grain declaration and documentation enforcement
---

# Grain declaration and documentation enforcement

*Data modelling and warehousing*

## Concept

**Grain** is the atomic level of detail at which a fact table stores one row. It answers: *What does each row represent?* Without explicit grain declaration, team members query the same table with conflicting assumptions—one person believes each row is "one job posting," another thinks it's "one job posting per day," and a third assumes it's "one posting per location." This ambiguity causes duplicate-counting bugs, incorrect aggregations, and wasted time debugging.

Grain enforcement means documenting the grain *and* validating it in code. For `job_postings_fact`, if the grain is "one row per unique job posting," then `job_id` must be unique (or composite keys like `job_id + job_posted_date` must clearly define uniqueness). Without this check, someone might load the same posting twice under different dates, silently breaking downstream reports.

Documentation alone fails because schemas evolve and people forget. Enforcement—via unique constraints, dbt model tests, or data quality checks—catches grain violations at load time, not at 3 am when a VP questions revenue numbers.

## Practice

**Problem:** A junior analyst ran `SELECT COUNT(DISTINCT job_id), SUM(salary_year_avg) FROM job_postings_fact` and compared it to a report from yesterday. The count dropped 15%, but salary sum stayed flat. They panicked, then discovered duplicates were loaded for jobs posted on different dates. The grain was never stated, so they didn't know whether duplicates were valid.

**Solution:**

```sql
-- 1. Declare grain in model metadata (dbt example)
-- job_postings_fact.yml
models:
  - name: job_postings_fact
    description: "One row per unique job posting. Grain: job_id."
    columns:
      - name: job_id
        description: "Primary key, unique identifier for each job posting."
        tests:
          - unique
          - not_null

-- 2. Enforce grain via unique constraint
ALTER TABLE job_postings_fact
ADD CONSTRAINT job_postings_grain_pk UNIQUE (job_id);

-- 3. Test for duplicates in pipeline
SELECT job_id, COUNT(*) as cnt
FROM job_postings_fact
GROUP BY job_id
HAVING COUNT(*) > 1;
-- Expected: 0 rows. If > 0, grain is violated; halt pipeline.
```

## Notes

- **Composite grains are valid but must be explicit:** If grain is "one row per job posting per day," document `(job_id, job_posted_date)` as the composite key and test accordingly.
- **Grain creep:** A table designed at job-posting grain might later be asked to hold job-posting-plus-application data. This breaks queries silently. Use version control and code review to catch grain changes.
- **Conforms to Kimball dimensional modeling:** Grain declaration is foundational to fact table design; fact-less fact tables and slowly-changing dimensions hinge on clear grain definition.
- **Adjacent: cardinality and fanout.** Understanding grain helps you spot when joins will explode row counts (many-to-many) or unintentionally suppress data (filtering at the wrong grain level).
- **Revisit when:** Adding new columns (e.g., applicant_id), joining new sources, or discovering historical duplicates. Always ask: *Does this change the grain?*
