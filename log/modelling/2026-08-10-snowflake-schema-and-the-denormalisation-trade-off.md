---
date: 2026-08-10
phase: modelling
topic: Snowflake schema and the denormalisation trade-off
---

# Snowflake schema and the denormalisation trade-off

*Data modelling and warehousing*

## Concept

A snowflake schema is a normalized dimensional model that extends star schema by breaking dimension tables into further normalized sub-dimensions. Instead of denormalization into a single wide table, you create hierarchies—for example, a location dimension splits into city, state, and country tables, each linked by foreign keys. This reduces storage redundancy and simplifies updates: if a city's region changes, you fix it in one place, not thousands of fact rows.

The trade-off is query complexity. Snowflake requires more joins to answer basic questions; a star schema answers the same question in one or two joins. For read-heavy analytics warehouses where analysts run ad-hoc queries, this extra cognitive load and query planning overhead can hurt adoption. Teams end up either writing more complex SQL or asking the data engineer for the "right" join path, defeating the goal of self-service analytics.

The schema matters most when your dimension data is large, volatile, or hierarchical. A jobs table with 50M rows where "software engineer" appears 2M times wastes space if job_title is denormalized into every fact row. It also matters when data quality is fragile—storing "New York, NY, USA" in one place is safer than spreading it across millions of rows. Beyond a certain volume or change frequency, the storage and consistency wins outweigh query overhead.

## Practice

**Problem:** Your job_postings_fact table repeats job titles, locations, and work-from-home policies millions of times. A salary analysis query must filter on both job_title_short and job_location, but typos in location names (e.g., "New York" vs "New york") cause silent data loss. You want to normalize without making every query a pain.

```sql
-- Snowflake schema: separate dimension tables
CREATE TABLE job_dim (
  job_key INT PRIMARY KEY,
  job_id INT UNIQUE,
  job_title_short VARCHAR,
  job_work_from_home BOOLEAN
);

CREATE TABLE location_dim (
  location_key INT PRIMARY KEY,
  job_location VARCHAR UNIQUE,
  city VARCHAR,
  state VARCHAR,
  country VARCHAR
);

-- Fact table now references keys, not strings
CREATE TABLE job_postings_fact (
  job_posting_id INT PRIMARY KEY,
  job_key INT REFERENCES job_dim(job_key),
  location_key INT REFERENCES location_dim(location_key),
  salary_year_avg NUMERIC,
  job_posted_date DATE
);

-- Query: Average salary by state (still readable, typos eliminated)
SELECT 
  ld.state,
  AVG(jpf.salary_year_avg) AS avg_salary
FROM job_postings_fact jpf
JOIN job_dim jd ON jpf.job_key = jd.job_key
JOIN location_dim ld ON jpf.location_key = ld.location_key
WHERE jd.job_title_short = 'Data Engineer'
GROUP BY ld.state;
```

## Notes

- **Over-normalization trap:** Don't snowflake everything. If a dimension has <10K rows and never changes, keep it denormalized in the star schema. Snowflake shines on large, hierarchical, or frequently-updated dimensions only.

- **Self-service breaks with complexity:** Analysts without SQL expertise hit a wall at 3+ joins. Document join paths explicitly or provide views/marts that hide the snowflake structure beneath a star-like interface.

- **Adjacent topics:** Slowly Changing Dimensions (SCD) become essential in snowflake schemas—you must track how job titles or locations change over time without breaking historical analyses. Also connects to fact table grain: ensure all dimensions join at the same grain, or you'll get Cartesian products.

- **Common mistake—surrogate key confusion:** Don't use natural keys (job_id, location string) in facts; use surrogate keys (job_key, location_key). Natural keys are fragile, and joins on strings are slower. Surrogate keys also make SCD handling straightforward.

- **Revisit when:** If queries slow down or analysts complain about complexity, consider rolling back to star schema or adding materialized views / summary tables that flatten the snowflake into digestible marts for specific use cases.
