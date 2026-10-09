---
date: 2026-10-09
phase: modelling
topic: Conformed date dimensions and calendar logic
---

# Conformed date dimensions and calendar logic

*Data modelling and warehousing*

## Concept

A conformed date dimension is a single, shared calendar table that every fact table references via a foreign key, rather than storing raw dates directly in facts. It contains pre-computed attributes—day of week, fiscal quarter, is_holiday, week_of_year—so analysts query business logic once, not repeatedly in WHERE clauses.

Without it, teams create inconsistent fiscal calendars across reports. One analyst's "Q1" doesn't match another's because they hardcoded different fiscal year starts. Date arithmetic gets duplicated; someone calculates "days since posting" in one query and "working days since posting" in another, with different results. Maintenance becomes impossible: when the company changes its fiscal calendar, you patch dozens of views and stored procedures.

With a conformed date dimension, the calendar logic lives in one place. A query like `SELECT * FROM job_postings_fact f JOIN date_dim d ON f.job_posted_date_key = d.date_key WHERE d.is_business_day = TRUE` is instantly trustworthy across the entire warehouse.

## Practice

**Problem:** Your team needs to report on job postings by fiscal quarter (fiscal year starts April 1st) and distinguish business days from weekends when calculating "time to fill." Raw dates in job_postings_fact make this scattered and error-prone.

**Solution:**

```sql
-- Create conformed date dimension
CREATE TABLE date_dim (
  date_key INT PRIMARY KEY,
  full_date DATE UNIQUE,
  day_of_week VARCHAR(10),
  is_weekend BOOLEAN,
  is_business_day BOOLEAN,
  fiscal_year INT,
  fiscal_quarter INT,
  fiscal_month INT,
  is_holiday BOOLEAN,
  holiday_name VARCHAR(50)
);

-- Load it with a calendar (April 1 = start of FY)
INSERT INTO date_dim
SELECT 
  CAST(FORMAT_DATE('%Y%m%d', d) AS INT) AS date_key,
  d AS full_date,
  FORMAT_DATE('%A', d) AS day_of_week,
  EXTRACT(DAYOFWEEK FROM d) IN (1, 7) AS is_weekend,
  EXTRACT(DAYOFWEEK FROM d) NOT IN (1, 7) AS is_business_day,
  CASE WHEN EXTRACT(MONTH FROM d) >= 4 
       THEN EXTRACT(YEAR FROM d) 
       ELSE EXTRACT(YEAR FROM d) - 1 END AS fiscal_year,
  CASE WHEN EXTRACT(MONTH FROM d) >= 4 THEN CEIL((EXTRACT(MONTH FROM d) - 3) / 3.0)
       ELSE CEIL((EXTRACT(MONTH FROM d) + 9) / 3.0) END AS fiscal_quarter,
  CASE WHEN EXTRACT(MONTH FROM d) >= 4 THEN EXTRACT(MONTH FROM d) - 3
       ELSE EXTRACT(MONTH FROM d) + 9 END AS fiscal_month,
  FALSE AS is_holiday,
  NULL AS holiday_name
FROM UNNEST(GENERATE_DATE_ARRAY('2020-01-01', '2030-12-31')) AS d;

-- Update job_postings_fact to use a surrogate key
ALTER TABLE job_postings_fact 
ADD COLUMN job_posted_date_key INT,
ADD CONSTRAINT fk_job_posted_date FOREIGN KEY (job_posted_date_key) REFERENCES date_dim(date_key);

-- Now queries are clear and consistent
SELECT 
  d.fiscal_year,
  d.fiscal_quarter,
  COUNT(*) AS postings,
  COUNT(CASE WHEN d.is_business_day THEN 1 END) AS postings_on_business_days
FROM job_postings_fact f
JOIN date_dim d ON f.job_posted_date_key = d.date_key
GROUP BY d.fiscal_year, d.fiscal_quarter
ORDER BY d.fiscal_year, d.fiscal_quarter;
```

## Notes

- **Mistake:** Storing dates as text (`'2024-01-15'` strings) or without a dimension; you lose indexing speed and force every query to parse. Always use DATE type + FK to dimension.
- **Mistake:** Putting business logic in the fact table (e.g., `is_holiday` column in job_postings_fact); the dimension is the single source of truth for calendar rules.
- **Adjacent topic:** Slowly Changing Dimensions (SCD)—if your fiscal calendar changes mid-year, you need SCD Type 2 to version the date_dim and keep historical accuracy.
- **Adjacent topic:** Surrogate keys (date_key INT) vs. natural keys (full_date)—surrogate keys are tiny, fast to join, and decouple the logical calendar from physical implementation.
- **Revisit:** Test your dimension-loading logic for leap years, fiscal year boundaries, and holiday updates; errors here propagate silently into every report.
