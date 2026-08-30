---
date: 2026-08-30
phase: modelling
topic: Kimball vs Inmon: dimensional vs normalized comparison
---

# Kimball vs Inmon: dimensional vs normalized comparison

*Data modelling and warehousing*

## Concept

Kimball and Inmon represent two architectural philosophies for organizing data warehouses. **Inmon's normalized approach** (third normal form) eliminates redundancy by splitting data into many tables—useful for OLTP systems and when storage is precious, but requires complex joins that slow analytical queries. **Kimball's dimensional approach** (star schema) denormalizes strategically into fact tables (transactions/events) and dimension tables (descriptive attributes), optimizing for fast aggregations and readability. The choice matters because it shapes every query your analysts write. Without clarity, you'll either have analysts constantly asking "which table has the customer region?" or they'll perform slow full-table scans. Kimball dominates modern data warehouses because business users and BI tools expect simple, fast queries; Inmon still appears in highly regulated environments where normalized audit trails matter more than query speed.

## Practice

**Problem:** Your `job_postings_fact` table mixes grain (one row per job posting) with location and job title attributes. When analysts want salary trends by remote status across regions, they must decode location strings and worry about title variations. Additionally, you can't track job title changes over time, and filtering on job level requires expensive string parsing.

**Solution (Kimball dimensional redesign):**

```sql
-- Fact table: one row per job posting, only measures and FK to dimensions
CREATE TABLE job_postings_fact (
  job_posting_id INT PRIMARY KEY,
  job_id INT,
  location_dim_id INT,
  job_title_dim_id INT,
  salary_year_avg DECIMAL(10,2),
  job_posted_date DATE,
  is_remote BOOLEAN,
  FOREIGN KEY (location_dim_id) REFERENCES dim_location,
  FOREIGN KEY (job_title_dim_id) REFERENCES dim_job_title
);

-- Dimension tables: fully denormalized lookup tables
CREATE TABLE dim_location (
  location_dim_id INT PRIMARY KEY,
  location_name VARCHAR(100),
  region VARCHAR(50),
  country VARCHAR(50),
  is_remote BOOLEAN
);

CREATE TABLE dim_job_title (
  job_title_dim_id INT PRIMARY KEY,
  job_title_short VARCHAR(100),
  job_level VARCHAR(50),
  job_category VARCHAR(50)
);

-- Now a simple aggregation query without joins to raw tables
SELECT 
  l.region,
  j.job_level,
  f.is_remote,
  COUNT(*) as posting_count,
  AVG(f.salary_year_avg) as avg_salary
FROM job_postings_fact f
JOIN dim_location l ON f.location_dim_id = l.location_dim_id
JOIN dim_job_title j ON f.job_title_dim_id = j.job_title_dim_id
GROUP BY l.region, j.job_level, f.is_remote;
```

## Notes

- **Dimensional tables are denormalized by design:** It's normal (and expected) to repeat "North America" in `dim_location` across rows. The storage savings don't justify the query complexity you'd add normalizing it away.
- **Grain confusion kills dimensional models:** Every fact table must have one clear, documented grain (e.g., "one row per job posting"). Mixed grains force convoluted joins and wrong aggregations.
- **Slowly Changing Dimensions (SCD):** Job titles and regions change. Track this with SCD Type 2 (add effective_date and is_current columns to dimensions) so historical salary comparisons stay accurate.
- **Surrogate keys matter:** Use surrogate IDs (location_dim_id) not natural keys (location_name). Locations rename; your fact table should remain stable.
- **Adjacent topics:** Conformed dimensions (shared dim_location across multiple fact tables), star schema validation tools, and incremental dimension loads via upsert patterns.
