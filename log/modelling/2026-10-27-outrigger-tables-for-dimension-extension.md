---
date: 2026-10-27
phase: modelling
topic: Outrigger tables for dimension extension
---

# Outrigger tables for dimension extension

*Data modelling and warehousing*

## Concept

An outrigger table is a normalized dimension table that extends another dimension without cluttering the fact table or main dimension. When a dimension has attributes that are rarely queried together or apply to only a subset of records, splitting them into a separate table reduces redundancy and keeps queries readable.

Without outriggers, you either denormalize everything into one dimension (bloating it with sparse attributes), add too many columns to the fact table (breaking the single-responsibility principle), or create confusing many-to-many relationships. For example, if only some job postings have recruiter details, and those details change independently of the job itself, storing them in the fact table wastes space and creates update anomalies.

The outrigger sits between the fact table and main dimension, connected via a surrogate key. It's especially valuable when a sub-entity has its own lifecycle, is queried in isolation, or appears as a degenerate dimension (low cardinality but domain-specific context).

## Practice

**Problem:** Your `job_postings_fact` contains `job_work_from_home` and `job_location`, but location also has rich attributes (region, cost_of_living_index, visa_sponsorship_available) that only apply to some jobs, change independently, and clutter queries when analysts only need "is it remote?"

**Solution:** Create an outrigger `job_location_dim` and reference it from the fact table:

```sql
CREATE TABLE job_location_dim (
  job_location_id INT PRIMARY KEY,
  job_location VARCHAR(100),
  region VARCHAR(50),
  cost_of_living_index DECIMAL(5,2),
  visa_sponsorship_available BOOLEAN
);

CREATE TABLE job_postings_fact (
  job_id INT PRIMARY KEY,
  job_title_short VARCHAR(50),
  salary_year_avg DECIMAL(10,2),
  job_work_from_home BOOLEAN,
  job_posted_date DATE,
  job_location_id INT,
  FOREIGN KEY (job_location_id) REFERENCES job_location_dim(job_location_id)
);

-- Analysts can now query without bloat:
SELECT f.job_id, f.job_title_short, l.region, l.cost_of_living_index
FROM job_postings_fact f
JOIN job_location_dim l ON f.job_location_id = l.job_location_id
WHERE l.visa_sponsorship_available = TRUE;
```

## Notes

- **Don't over-normalize:** Use outriggers only when sub-attributes have independent change frequency or are queried separately; otherwise you create unnecessary joins.
- **Name clearly:** Include the parent dimension in the outrigger name (`job_location_dim`, not just `location_dim`) so relationships are self-documenting.
- **Connects to:** conformed dimensions (when the same outrigger serves multiple facts), slowly changing dimensions (Type 2 SCD often lives in outriggers to preserve history), and junk dimensions (opposite approach—combine low-cardinality attributes instead of splitting them).
- **Common mistake:** Creating an outrigger for every attribute that *might* be queried separately; discipline yourself to materialized views or ad-hoc queries for truly rare needs.
- **Revisit:** When deciding between outrigger vs. bridge table (many-to-many) vs. degenerate dimension (fact-only attribute), sketch the cardinality and change frequency first.
