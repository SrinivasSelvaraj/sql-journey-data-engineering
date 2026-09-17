---
date: 2026-09-17
phase: modelling
topic: Bit-sliced indexes and dimensional queries
---

# Bit-sliced indexes and dimensional queries

*Data modelling and warehousing*

## Concept

Bit-sliced indexes store boolean and categorical columns as separate bitmap indexes—one bit per row per distinct value—rather than as dense integer or string columns. This makes dimensional filtering (especially multi-column AND/OR queries) extremely fast because you're doing bitwise operations instead of table scans. A query like "remote work AND salary > 150k AND posted in last 30 days" can be answered by intersecting three bitmaps instead of scanning millions of rows.

The model breaks down when teams don't document what each boolean or categorical field *means*. Without clear naming and a shared dimensional schema, someone queries `job_work_from_home = TRUE` without knowing whether NULL means "unknown," "not specified," or "applicant must be on-site." This compounds when you have dozens of job attributes (visa_sponsored, contract_type, seniority_level). A well-designed dimensional schema with explicit bit assignments and a data dictionary ensures queries are unambiguous and repeatable—no one needs to ask you what a column really contains.

## Practice

**Problem:** The analytics team wants to slice job postings by multiple attributes at once: find the count of remote junior roles with average salary above $100k posted in the last 90 days. Without bit-sliced design, this requires nested filtering and table scans. With it, you can precompute bitmaps and intersect them instantly.

```sql
-- Bit-sliced dimensional query approach
-- (Conceptual: real implementation depends on your warehouse engine)

WITH remote_bitmap AS (
  SELECT bitmap_construct(job_id) AS remote_jobs
  FROM job_postings_fact
  WHERE job_work_from_home = TRUE
),
recent_bitmap AS (
  SELECT bitmap_construct(job_id) AS recent_jobs
  FROM job_postings_fact
  WHERE job_posted_date >= CURRENT_DATE - INTERVAL '90 days'
),
high_salary_bitmap AS (
  SELECT bitmap_construct(job_id) AS high_sal_jobs
  FROM job_postings_fact
  WHERE salary_year_avg > 100000
),
junior_bitmap AS (
  SELECT bitmap_construct(job_id) AS junior_jobs
  FROM job_postings_fact
  WHERE job_title_short LIKE '%Junior%'
)
SELECT
  COUNT(*) AS matching_jobs,
  AVG(salary_year_avg) AS avg_salary
FROM job_postings_fact
WHERE job_id IN (
  SELECT bitmap_intersection(
    remote_bitmap.remote_jobs,
    recent_bitmap.recent_jobs,
    high_salary_bitmap.high_sal_jobs,
    junior_bitmap.junior_jobs
  )
);
```

## Notes

- **Null handling is critical**: decide upfront whether NULL in a boolean column means "not applicable," "unknown," or "false." Encode this in your data dictionary and filter explicitly in queries.
- **Cardinality matters**: bit-sliced indexes shine on low-cardinality dimensions (remote/not-remote, contract_type with <100 values) but waste space on high-cardinality columns (individual job titles). Use surrogate keys + dimensional tables instead.
- **Relates to star schema design**: dimensions (seniority level, work arrangement) belong in separate tables; facts stay in the central table. Bit-slicing optimizes the fact table's dimensional columns specifically.
- **Common mistake**: over-indexing. Not every boolean needs a bitmap; prioritize columns used in 80% of queries. Premature optimization creates maintenance overhead.
- **Revisit cardinality analysis and columnar storage**: understanding column distribution helps you choose between bit-sliced indexes, dictionary encoding, and run-length encoding—all compression + query acceleration techniques.
