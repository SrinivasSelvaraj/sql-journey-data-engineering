---
date: 2026-10-10
phase: modelling
topic: Effective dating and validity periods in dimensions
---

# Effective dating and validity periods in dimensions

*Data modelling and warehousing*

## Concept

Effective dating and validity periods track *when* a dimension record is valid. Without them, you cannot distinguish whether a salary change represents a real market shift, a job reclassification, or simply a correction to yesterday's data. When a job title changes from "Senior Engineer" to "Staff Engineer" or a location shifts from "Remote" to "San Francisco," you need to know not just that the change happened, but *when* it applied.

In practice, you add `effective_date` (when a record becomes valid) and `end_date` (when it stops being valid, often `NULL` for current records) to your dimension tables. This allows fact records to join correctly to the version of the dimension that was valid on the transaction date. Without these columns, updates to dimension attributes overwrite history—you lose the ability to analyze trends, audit changes, or correctly allocate facts to the dimension state that existed when the event occurred.

This matters most in star schemas where dimensions change slowly (SCD Type 2). A job posting from March should always join to the job title that existed in March, not the title it has today.

## Practice

**Problem:** Your `job_postings_fact` table has postings from six months ago alongside new postings. During this time, `job_title_short` for data engineering roles shifted from "Data Engineer" to "Analytics Engineer," and salary ranges increased. You need to analyze whether median salary growth is real or driven by role redefinition.

**Solution:** Introduce a job dimension with SCD Type 2 tracking:

```sql
CREATE TABLE job_dimension (
  job_sk INT PRIMARY KEY,
  job_id INT NOT NULL,
  job_title_short VARCHAR(100),
  salary_year_avg DECIMAL(10, 2),
  job_work_from_home BOOLEAN,
  job_location VARCHAR(100),
  effective_date DATE NOT NULL,
  end_date DATE,
  is_current BOOLEAN
);

-- Fact table now joins on both key and date validity
CREATE TABLE job_postings_fact (
  posting_id INT PRIMARY KEY,
  job_sk INT NOT NULL,
  job_posted_date DATE NOT NULL,
  FOREIGN KEY (job_sk) REFERENCES job_dimension(job_sk)
);

-- Query that respects validity periods
SELECT 
  jd.job_title_short,
  AVG(jpf.salary_year_avg) as avg_salary
FROM job_postings_fact jpf
JOIN job_dimension jd 
  ON jpf.job_sk = jd.job_sk
  AND jpf.job_posted_date >= jd.effective_date
  AND (jpf.job_posted_date < jd.end_date OR jd.end_date IS NULL)
WHERE jd.job_location = 'San Francisco'
GROUP BY jd.job_title_short;
```

## Notes

- **Joining by date range is mandatory:** A simple `ON fact.job_sk = dim.job_sk` ignores validity—your analysis will mix old and new versions. Always include `fact.transaction_date >= dim.effective_date AND fact.transaction_date < dim.end_date`.

- **SCD Type 2 vs. Type 1 trade-off:** Type 2 (new row per change) preserves history but doubles dimension rows; Type 1 (overwrite) loses history but keeps queries simple. Choose based on audit requirements and query complexity tolerance.

- **NULL end_date convention:** Use `NULL` for the current record, not `'9999-12-31'`. It signals "still valid" and simplifies `IS_CURRENT` flags; some tools expect this pattern.

- **Connections to conformed dimensions, audit tables, and temporal databases:** Effective dating is the foundation for slowly-changing dimensions and feeds into data lineage. It also maps to SQL standard temporal tables (`VALID_TIME`).

- **Revisit when:** Adding this layer later is expensive (historical data backfill). Design it in from the start if change frequency is predictable (job titles, locations, classifications usually are).
