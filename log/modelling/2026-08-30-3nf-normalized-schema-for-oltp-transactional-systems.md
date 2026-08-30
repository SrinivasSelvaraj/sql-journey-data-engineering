---
date: 2026-08-30
phase: modelling
topic: 3NF normalized schema for OLTP transactional systems
---

# 3NF normalized schema for OLTP transactional systems

*Data modelling and warehousing*

## Concept

Third Normal Form (3NF) eliminates redundant data and ensures every non-key column depends on the primary key, the whole key, and nothing but the key. In OLTP systems handling frequent inserts, updates, and deletes, 3NF prevents update anomalies—situations where changing one value requires updates across multiple rows, risking inconsistency. Without normalization, a jobs table storing both job title and job category in every row means renaming a category requires touching thousands of records; missing even one creates silent data corruption that breaks downstream queries and reports.

3NF matters most when data changes frequently and consistency is non-negotiable. OLTP systems prioritize correctness over query speed because transactions must be atomic and reliable. A well-normalized schema forces intentional design: if `job_location` contains both city and country, that's a sign country should be a separate dimension with a surrogate key. This structure makes schema intent explicit—anyone querying the database immediately understands relationships through foreign keys rather than guessing from column names.

## Practice

**Problem:** The `job_postings_fact` table stores `job_location` as a single text field. When the same location appears 50,000 times and you need to correct a misspelling or standardize a region code, you either update all 50,000 rows (slow, risky) or live with inconsistent location data. Additionally, queries filtering by region require string parsing, and you cannot enforce valid locations.

**Solution:**

```sql
-- Create normalized dimension table
CREATE TABLE dim_location (
  location_id SERIAL PRIMARY KEY,
  city VARCHAR(100) NOT NULL,
  state_province VARCHAR(100),
  country VARCHAR(100) NOT NULL,
  region_code VARCHAR(10),
  UNIQUE(city, state_province, country)
);

-- Create normalized fact table
CREATE TABLE job_postings (
  job_id SERIAL PRIMARY KEY,
  job_title_short VARCHAR(255) NOT NULL,
  salary_year_avg DECIMAL(10, 2),
  job_work_from_home BOOLEAN,
  job_posted_date DATE NOT NULL,
  location_id INTEGER NOT NULL REFERENCES dim_location(location_id)
);

-- Update location once, reflects everywhere
UPDATE dim_location SET region_code = 'NYC' WHERE city = 'New York' AND country = 'USA';
```

## Notes

- **Mistake:** Over-normalizing into 5+ tables when 3NF is sufficient; this adds join overhead without clarity gains. Stop normalizing when further decomposition would require joins that hurt readability or performance without solving a real update anomaly.
- **Mistake:** Storing derived or calculated data (like `total_applications` on a job posting) instead of computing it at query time; this breaks if source data changes and violates 3NF's dependency rule.
- **Adjacent topic:** OLAP/data warehouse schemas intentionally denormalize (star schema, snowflake schema) for analytical query speed, trading update safety for scan efficiency—the opposite trade-off from OLTP 3NF.
- **Revisit:** Foreign key constraints; they're essential to enforce 3NF guarantees. Without them, orphaned location_ids silently break referential integrity.
- **Worth noting:** Surrogate keys (location_id) are standard in 3NF; they're stable, narrow, and decouple your primary key from business logic that may change.
