---
date: 2026-10-09
phase: modelling
topic: Grain and atomicity: fact table granularity
---

# Grain and atomicity: fact table granularity

*Data modelling and warehousing*

## Concept

Grain is the level of detail at which a fact table records events or measurements—the "one row represents" rule. If your fact table's grain is unclear, users will misinterpret sums and counts. For example, a fact table with one row per job posting must never mix in job application counts or salary ranges; those belong in separate fact tables at different grains or in dimensions.

Atomicity means each row represents the finest-grained, non-decomposable business event you'll record. A fact table at job-posting grain stores salary_year_avg, but if postings come with salary bands or multiple salary values, you've broken atomicity—you can't cleanly aggregate without risking double-counting or nulls. The grain must match your source of truth: if you're tracking "one posting, one snapshot in time," then job_id + job_posted_date is your natural key.

Without explicit grain, queries fail silently. Users sum salary_year_avg across 10 postings and assume they have the average for 10 different roles, when in reality three of those rows are re-postings of the same job. Fact table design that ignores grain is the fastest way to produce confident, wrong answers.

## Practice

**Problem:** Your job_postings_fact has one row per job posting. A recruiter asks: "What's the average salary by location?" You run `SELECT job_location, AVG(salary_year_avg) FROM job_postings_fact GROUP BY job_location`. The result is nonsense because the same job was posted 3 times in New York, inflating that location's average.

**Solution:** Clarify grain in your fact table design and handle duplicates at load time:

```sql
-- Define atomic fact table: one row = one unique job posting on one date
CREATE TABLE job_postings_fact (
  job_posting_id INT PRIMARY KEY,  -- unique posting, not repost
  job_date DATE NOT NULL,
  salary_year_avg DECIMAL(10,2),
  job_work_from_home BOOLEAN,
  job_location_id INT NOT NULL REFERENCES location_dim,
  CONSTRAINT pk_job_grain UNIQUE (job_posting_id, job_date)
);

-- Correct query: aggregate at the right grain
SELECT 
  ld.location_name,
  AVG(jpf.salary_year_avg) AS avg_salary,
  COUNT(DISTINCT jpf.job_posting_id) AS unique_postings
FROM job_postings_fact jpf
JOIN location_dim ld ON jpf.job_location_id = ld.location_id
WHERE jpf.job_date >= CURRENT_DATE - INTERVAL '90 days'
GROUP BY ld.location_name;
```

## Notes

- **Repostings are poison.** If the same job is reposted weekly, decide upfront: is each posting a separate row (one grain) or is deduplication part of ETL? Document it in your schema metadata.
- **Grain mismatches create measure ambiguity.** A salary column is useless if rows represent both new postings and re-postings—use a `posting_type` dimension or split into two fact tables.
- **Connects to slowly-changing dimensions.** If job_title or location changes mid-posting, your grain (and SCD strategy) must account for it; otherwise time-travel queries fail.
- **Watch for semi-additive measures.** Salary is non-additive (you can't sum salaries across 10 jobs); use COUNT or AVG, never SUM, and always document this in your metadata layer.
- **Grain appears in your primary key.** A fact table's grain is almost always visible in its natural key (job_posting_id + job_date here). If you're unsure what your key should be, you haven't nailed the grain yet.
