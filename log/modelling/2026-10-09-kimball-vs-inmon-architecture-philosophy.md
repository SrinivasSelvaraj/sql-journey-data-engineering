---
date: 2026-10-09
phase: modelling
topic: Kimball vs Inmon architecture philosophy
---

# Kimball vs Inmon architecture philosophy

*Data modelling and warehousing*

## Concept

Kimball and Inmon represent two opposing philosophies for structuring data warehouses. **Inmon's approach** (top-down) builds a normalized Enterprise Data Warehouse (EDW) first, then creates denormalized data marts for specific business units. **Kimball's approach** (bottom-up) builds dimensional models directly—fact tables with foreign keys to slowly-changing dimension tables—optimized for query performance and analytics from day one.

The practical difference: Inmon prioritizes data governance and single source of truth across the enterprise but requires ETL pipelines between the EDW and every analytics layer. Kimball prioritizes query speed and analyst autonomy by embedding business logic into star schemas. Choose Kimball when you need fast time-to-insight and have a smaller scope; choose Inmon when you're integrating disparate sources and need strict governance.

Without this clarity, teams drift toward the worst of both worlds: normalized schemas that are slow to query (confusing analysts who don't understand the joins), or denormalized tables with cryptic column names and hidden business rules (forcing analysts to ask you what `job_work_from_home` really means).

## Practice

**Problem:** Your `job_postings_fact` table violates Kimball principles. The `job_title_short` is stored redundantly in the fact table; location and date handling make filtering awkward; there's no conformed dimension for job categories, so different teams define "remote" differently.

**Solution—Kimball-style redesign:**

```sql
-- Dimension tables (conformed, reusable)
CREATE TABLE dim_job_title (
  job_title_key SERIAL PRIMARY KEY,
  job_title_short VARCHAR(100),
  job_category VARCHAR(50)
);

CREATE TABLE dim_location (
  location_key SERIAL PRIMARY KEY,
  location_name VARCHAR(100),
  region VARCHAR(50),
  is_remote BOOLEAN
);

CREATE TABLE dim_date (
  date_key INT PRIMARY KEY,
  full_date DATE,
  year INT,
  month INT,
  quarter INT
);

-- Fact table (additive, grain-level clear)
CREATE TABLE fact_job_postings (
  job_posting_id BIGINT PRIMARY KEY,
  job_title_key INT REFERENCES dim_job_title,
  location_key INT REFERENCES dim_location,
  posted_date_key INT REFERENCES dim_date,
  salary_year_avg NUMERIC(10,2),
  posting_count INT DEFAULT 1
);

-- Now queries are self-documenting and fast
SELECT dt.year, dl.region, COUNT(*)
FROM fact_job_postings fjp
JOIN dim_date dt ON fjp.posted_date_key = dt.date_key
JOIN dim_location dl ON fjp.location_key = dl.location_key
WHERE dl.is_remote = TRUE
GROUP BY dt.year, dl.region;
```

## Notes

- **Denormalization trade-off:** Kimball trades storage and ETL complexity for query simplicity; resist normalizing dimensions because it kills the whole point.
- **Conformed dimensions:** The same `dim_location` table used in HR, Finance, and Marketing analytics prevents "different definitions of remote"—this is Kimball's killer feature.
- **Grain clarity:** Always declare your fact table's grain upfront (e.g., "one row per job posting"). Mixing grains (adding job application counts to the same fact) breaks aggregations.
- **Adjacent topics:** Slowly Changing Dimensions (SCD Types 1–4) are essential Kimball mechanics; star schema design; bus matrix for enterprise alignment.
- **Revisit:** Kimball shines in OLAP; revisit this if you're building real-time operational systems (OLTP) where normalization is correct.
