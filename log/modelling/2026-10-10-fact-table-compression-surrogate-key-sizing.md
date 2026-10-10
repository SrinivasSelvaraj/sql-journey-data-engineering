---
date: 2026-10-10
phase: modelling
topic: Fact table compression: surrogate key sizing
---

# Fact table compression: surrogate key sizing

*Data modelling and warehousing*

## Concept

Surrogate keys are artificial numeric identifiers (usually integers) assigned to dimension table rows to replace natural keys in fact tables. In a fact table, using a small integer surrogate key instead of a large text natural key dramatically reduces storage and improves query performance. For example, storing `job_title_id INT` (4 bytes) instead of `job_title_short VARCHAR(100)` (up to 100 bytes) per row compounds across millions of fact records. When fact tables grow to billions of rows, this difference becomes the difference between a table fitting in memory versus spilling to disk during joins and aggregations.

Sizing the surrogate key wrongly creates two failure modes: too small (INT maxes out at ~2B values, inadequate for high-cardinality dimensions like user IDs at scale), or too large (BIGINT wastes 8 bytes when SMALLINT would suffice for a 500-item dimension). The goal is matching key size to cardinality—the number of distinct dimension values you'll ever need to represent.

## Practice

**Problem:** Your fact table `job_postings_fact` has 50 million rows. You're storing `job_title_short` (average 30 bytes) and `job_location` (average 25 bytes) directly in the fact table. Queries filtering or grouping on these columns are slow, and the table consumes 2.75 GB unnecessarily. Redesign to use surrogate keys.

```sql
-- Create dimension tables with surrogate keys
CREATE TABLE dim_job_title (
  job_title_id SMALLINT PRIMARY KEY,
  job_title_short VARCHAR(100) NOT NULL UNIQUE
);

CREATE TABLE dim_job_location (
  job_location_id SMALLINT PRIMARY KEY,
  job_location VARCHAR(100) NOT NULL UNIQUE
);

-- Redesigned fact table
CREATE TABLE job_postings_fact (
  job_id INT PRIMARY KEY,
  job_title_id SMALLINT NOT NULL REFERENCES dim_job_title(job_title_id),
  job_location_id SMALLINT NOT NULL REFERENCES dim_job_location(job_location_id),
  salary_year_avg DECIMAL(10,2),
  job_work_from_home BOOLEAN,
  job_posted_date DATE
);

-- Query joins dimensions when needed
SELECT 
  dt.job_title_short,
  dl.job_location,
  AVG(f.salary_year_avg)
FROM job_postings_fact f
JOIN dim_job_title dt ON f.job_title_id = dt.job_title_id
JOIN dim_job_location dl ON f.job_location_id = dl.job_location_id
WHERE f.job_posted_date >= '2024-01-01'
GROUP BY dt.job_title_short, dl.job_location;
```

## Notes

- **Cardinality sizing rule:** Use TINYINT (0–255) for <250 values, SMALLINT (0–32K) for <30K, INT for <2B, BIGINT only when necessary. Mismatching wastes storage and CPU cache.
- **Natural vs. surrogate:** Natural keys (e.g., email, SKU) are human-readable but large; surrogate keys are opaque but compress fact tables. Always keep natural keys in the dimension for lineage and debugging.
- **Slowly Changing Dimensions (SCDs):** Surrogate keys let you handle dimension updates (e.g., a job title name changes) without rewriting fact records. The surrogate ID stays constant while the dimension row changes or a new row is added.
- **Star schema prerequisite:** This pattern assumes you've separated dimension tables. Denormalized fact tables defeat the purpose—normalize first, then size keys.
- **Revisit during scale:** Monitor actual cardinalities during growth. A SMALLINT dimension that reaches 40K values at scale will silently overflow; plan upgrades early and test key range limits in load testing.
