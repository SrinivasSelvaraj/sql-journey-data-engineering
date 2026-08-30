---
date: 2026-08-30
phase: modelling
topic: Nullability decisions: required vs optional vs unknown
---

# Nullability decisions: required vs optional vs unknown

*Data modelling and warehousing*

## Concept

Nullability decisions—marking columns as `NOT NULL`, nullable, or explicitly unknown—are about encoding business intent into schema structure. A `NOT NULL` constraint says "this value always exists and is meaningful"; nullable says "this may not apply"; and unknown (often represented as a sentinel value like -1 or a dedicated unknown category) says "we don't know the value, but we know it's supposed to exist." Without clear nullability rules, queries become fragile: you either filter out NULLs defensively everywhere (adding friction), misinterpret missing data as "not applicable," or accidentally include incomplete records. This is especially critical in fact tables where aggregations can silently undercount.

The choice depends on three factors: whether the attribute is inherent to every entity (job title always exists for a posted job), whether missing data is analyzable vs. problematic (unknown salary might be informative; NULL could hide incomplete scrapes), and whether your downstream consumers need to distinguish "not applicable" from "not collected." A well-designed schema makes these distinctions explicit in the structure itself, so queries don't have to be defensive.

## Practice

**Problem:** You're building a BI dashboard on `job_postings_fact`. Salary data comes from multiple sources; some jobs list a range, some list nothing, and some are intentionally remote-only with no geographic location. Your analytics team keeps asking: "Should I count these nulls as missing data or filter them out?" And your aggregations are inconsistent because different analysts handle NULLs differently.

```sql
-- Better schema design: make nullability explicit
CREATE TABLE job_postings_fact (
    job_id INT NOT NULL PRIMARY KEY,
    job_title_short VARCHAR NOT NULL,
    salary_year_avg INT,  -- nullable: legitimate when salary not disclosed
    salary_data_quality VARCHAR NOT NULL DEFAULT 'unknown',  -- explicit flag
    job_work_from_home BOOLEAN NOT NULL DEFAULT FALSE,  -- assume false if not stated
    job_posted_date DATE NOT NULL,
    job_location VARCHAR,  -- nullable: remote roles may have no location
    job_location_is_unknown BOOLEAN NOT NULL DEFAULT FALSE  -- explicit flag
);

-- Query that's self-documenting and handles intent
SELECT 
    COUNT(*) as total_jobs,
    COUNT(salary_year_avg) as jobs_with_salary,
    AVG(salary_year_avg) as avg_salary,
    COUNT(CASE WHEN job_location_is_unknown THEN 1 END) as remote_or_unspecified
FROM job_postings_fact
WHERE salary_data_quality != 'unreliable';
```

## Notes

- **Avoid silent NULLs in fact tables:** If a NULL could be misread as zero or "not applicable," add an explicit Boolean flag (`is_unknown`, `is_remote`, etc.) so the next person doesn't have to guess your intent.
- **Sentinel values vs. NULLs:** For categorical columns (e.g., location = 'Unknown'), use a category; for numeric (e.g., salary), decide whether NULL or -1 is clearer to your team and stick with it.
- **NOT NULL has performance benefits:** Most query engines optimize better when nullability is restricted; use it liberally on dimensions and keys, sparingly on measurements.
- **Connects to data contracts and documentation:** Nullability rules should live in your schema documentation or data dictionary, not as tribal knowledge; this is part of making columns queryable without asking you.
- **Revisit after first ingestion:** Requirements often shift once data arrives; if you're discovering "oh, 40% of salary values are actually unknown," consider redesigning to flag that explicitly.
