---
date: 2026-10-08
phase: modelling
topic: Conformed dimensions across multiple facts
---

# Conformed dimensions across multiple facts

*Data modelling and warehousing*

## Concept

A conformed dimension is a shared lookup table used consistently across multiple fact tables, ensuring the same business entity (customer, product, location, date) has one authoritative definition. When a dimension is conformed, any join on that dimension produces consistent results regardless of which fact table you're querying—no conflicting definitions of "active customer" or "product category" across different analytical queries.

Without conformed dimensions, teams end up with duplicated logic scattered across reports. One analyst defines "job_location" as city-only; another includes state and country. Queries on the same business event produce different answers depending on which person wrote the SQL. This breaks trust in the warehouse and forces people to ask you "which version of location should I use?"

Conformed dimensions become critical once you have 3+ fact tables that share entities. The upfront effort to build `dim_location`, `dim_job_title`, and `dim_date` tables pays off immediately: every stakeholder queries the same definition, and code review catches semantic drift early.

## Practice

**Problem:** The `job_postings_fact` table stores location as a single string and job title as a shortened code. Two teams are building dashboards: one wants to analyze postings by state, another by country. They're writing their own parsing logic in each query. A third team notices the job title codes are inconsistent (some uppercase, some mixed case). How do you make this maintainable?

**Solution:** Extract dimensions and link via surrogate keys.

```sql
-- Create conformed dimensions
CREATE TABLE dim_location (
  location_key INT PRIMARY KEY,
  location_raw VARCHAR(100),
  city VARCHAR(50),
  state VARCHAR(50),
  country VARCHAR(50),
  region VARCHAR(50),
  dbt_updated_at TIMESTAMP
);

CREATE TABLE dim_job_title (
  job_title_key INT PRIMARY KEY,
  job_title_short VARCHAR(50),
  job_title_full VARCHAR(200),
  job_category VARCHAR(50),
  dbt_updated_at TIMESTAMP
);

-- Refactor fact table to use dimension keys
CREATE TABLE job_postings_fact (
  job_id INT,
  job_title_key INT REFERENCES dim_job_title(job_title_key),
  location_key INT REFERENCES dim_location(location_key),
  salary_year_avg DECIMAL(10,2),
  job_work_from_home BOOLEAN,
  job_posted_date DATE
);

-- Now every analyst uses the same definitions
SELECT 
  djt.job_category,
  dl.state,
  COUNT(*) as posting_count
FROM job_postings_fact jpf
JOIN dim_job_title djt ON jpf.job_title_key = djt.job_title_key
JOIN dim_location dl ON jpf.location_key = dl.location_key
GROUP BY djt.job_category, dl.state;
```

## Notes

- **Late-binding vs. early-binding views:** Conformed dimensions use early binding (join at query time to dimension tables). This is more flexible than embedding denormalized attributes in the fact table, but costs a join. Balance readability and performance with your query volume.

- **Surrogate keys are essential:** Use synthetic integer keys (not job titles or location strings) to link facts to dimensions. This lets you fix dimension definitions without reloading fact data.

- **Watch out for slowly changing dimensions:** If a job title's category changes or a city's state assignment changes, decide whether to keep historical records (SCD Type 2: new row + effective dates) or overwrite (SCD Type 1). Document this choice.

- **Common mistake—"almost conformed" dimensions:** Don't create `dim_location_job` and `dim_location_customer` that diverge slightly. One dimension per entity. If two teams need different attributes, add columns to the dimension; don't split it.

- **Relates to:** grain of the fact table (what does one row represent?), dimensional modeling (Kimball method), dbt snapshot macros (for SCD tracking), and data lineage documentation.
