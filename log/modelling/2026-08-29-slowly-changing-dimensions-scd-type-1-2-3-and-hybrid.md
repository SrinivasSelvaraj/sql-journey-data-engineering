---
date: 2026-08-29
phase: modelling
topic: Slowly changing dimensions: SCD type 1, 2, 3 and hybrid
---

# Slowly changing dimensions: SCD type 1, 2, 3 and hybrid

*Data modelling and warehousing*

## Concept

A Slowly Changing Dimension (SCD) is a strategy for handling updates to dimension table attributes when source data changes infrequently but meaningfully. Without an SCD strategy, you either overwrite history (losing what was true before) or create duplicate keys (breaking referential integrity). The choice between SCD types determines what your fact tables can answer: "What was the job title *when this application happened*?" requires SCD Type 2; "Just give me the current title" works with SCD Type 1.

Most data warehouses need mixed approaches. A job posting's location might use Type 1 (overwrite, we don't care about historical moves), while a candidate's seniority level uses Type 2 (track changes with effective dates so we know *when* they were promoted). Without explicit SCD handling, you end up with fact records pointing to dimension rows that no longer reflect the business reality at fact time, breaking temporal queries and audit trails.

## Practice

**Problem:** Your `job_postings_fact` tracks applications over time. Job titles are updated by recruiters (`job_title_short` changes from "Senior Engineer" to "Staff Engineer"). You need to know which title was current *when an applicant applied*, not just today's title. How do you structure `job_postings_dim`?

```sql
-- SCD Type 2: Track all versions with effective dates
CREATE TABLE job_postings_dim (
  job_posting_key INT PRIMARY KEY,  -- Surrogate key (new per version)
  job_id INT NOT NULL,              -- Natural key (same across versions)
  job_title_short VARCHAR(100),
  salary_year_avg INT,
  job_location VARCHAR(100),
  job_work_from_home BOOLEAN,
  effective_date DATE NOT NULL,
  end_date DATE NOT NULL DEFAULT '9999-12-31',
  is_current BOOLEAN DEFAULT TRUE,
  dw_insert_ts TIMESTAMP
);

-- Fact table now references surrogate key
CREATE TABLE application_fact (
  application_id INT PRIMARY KEY,
  job_posting_key INT REFERENCES job_postings_dim(job_posting_key),
  candidate_key INT,
  application_date DATE,
  applied_ts TIMESTAMP
);

-- When job_title_short changes: close old version, insert new
INSERT INTO job_postings_dim 
VALUES (9001, 12345, 'Staff Engineer', 185000, 'San Francisco', TRUE, '2024-03-15', '9999-12-31', TRUE, NOW());

UPDATE job_postings_dim 
SET end_date = '2024-03-14', is_current = FALSE 
WHERE job_id = 12345 AND is_current = TRUE;

-- Query: "What title was posted when this person applied?"
SELECT a.application_id, j.job_title_short, j.effective_date
FROM application_fact a
JOIN job_postings_dim j ON a.job_posting_key = j.job_posting_key
WHERE a.application_date BETWEEN j.effective_date AND j.end_date;
```

## Notes

- **Type 1 (overwrite):** Use for attributes you don't care about historically (job_work_from_home policy, standardized job category codes). Simple but permanently erases prior state.
- **Type 2 (versioning):** Use for business-critical attributes (title, salary band, location) where temporal accuracy matters for fact interpretation. Creates more rows; requires effective/end dates and surrogate keys.
- **Type 3 (limited history):** Keep current *and* previous value only (e.g., `current_title`, `previous_title`). Rare; useful for slowly-changing attributes where you only need one step back.
- **Hybrid approach:** Most real warehouses mix all three—use Type 2 on candidate seniority (frequent queries on historical role), Type 1 on internal data quality flags (never needed for analysis), Type 3 on manager assignments (track last change only). Document the strategy per dimension.
- **Watch for:** Fact records applied *before* the effective_date of dimension versions (data quality check). Surrogate keys must be assigned at insert time, not regenerated. Always populate `end_date` explicitly even if defaulted; queries filter on it heavily.
