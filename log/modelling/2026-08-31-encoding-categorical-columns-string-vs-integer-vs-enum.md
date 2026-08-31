---
date: 2026-08-31
phase: modelling
topic: Encoding categorical columns: string vs integer vs enum
---

# Encoding categorical columns: string vs integer vs enum

*Data modelling and warehousing*

## Concept

Categorical columns store discrete values that repeat across many rows (job titles, locations, employment types). How you encode them—as strings, integers with a lookup table, or enum types—affects query clarity, storage efficiency, and whether teammates can understand results without asking you what "1" means.

String encoding is readable but wastes storage when the same value repeats thousands of times. Integer encoding (foreign key to a dimension table) saves space and enforces consistency, but queries become opaque: `WHERE job_category_id = 7` tells you nothing. Enum types (native database support in PostgreSQL, MySQL 5.1+) sit between: they compress storage like integers but display as readable strings by default.

The real cost appears downstream. If `job_location` is stored as free text, you'll spend weeks discovering that "San Francisco, CA", "San Francisco CA", and "SF, CA" are the same place. If it's a string with no constraints, analysts query directly and get stale or inconsistent results. Without a clean encoding strategy, every schema becomes a puzzle only you can solve.

## Practice

**Problem:** Your `job_postings_fact` table stores `job_location` as TEXT. Analysts run queries like `SELECT COUNT(*) WHERE job_location = 'New York'`, but the raw data contains "New York, NY", "New York, USA", and "NYC". Results are wrong and inconsistent.

**Solution:** Create a dimension table and use a foreign key:

```sql
-- Create dimension table (single source of truth)
CREATE TABLE job_location_dim (
  job_location_id SERIAL PRIMARY KEY,
  location_name VARCHAR(100) NOT NULL UNIQUE,
  city VARCHAR(50),
  state_code CHAR(2),
  country VARCHAR(50)
);

-- Insert standardized locations
INSERT INTO job_location_dim (location_name, city, state_code, country)
VALUES ('New York, NY', 'New York', 'NY', 'USA');

-- Modify fact table to use foreign key
ALTER TABLE job_postings_fact
ADD COLUMN job_location_id INT REFERENCES job_location_dim(job_location_id);

-- Now analysts query with meaning
SELECT ld.location_name, COUNT(*) as count
FROM job_postings_fact jp
JOIN job_location_dim ld ON jp.job_location_id = ld.job_location_id
WHERE ld.city = 'New York'
GROUP BY ld.location_name;
```

## Notes

- **String normalization debt:** Free-text categories accumulate spelling variations and typos; fixing them later requires messy migrations. Normalize at ingestion time or use lookup tables from day one.
- **Enum types aren't portable:** PostgreSQL enums are convenient but trap data in that database; dimension tables with integers are more portable across systems and easier to version.
- **Surrogate vs. natural keys:** Use surrogate keys (auto-increment IDs) in dimension tables to decouple your fact table from upstream data changes (e.g., if a job category name changes, only the dimension table updates).
- **Cardinality matters:** If a category has 2–3 values (boolean concepts like `job_work_from_home`), plain boolean or tiny enum is fine. If it has 100+ values (job titles, locations), always use a dimension table.
- **Query readability is part of the schema:** A dimension table makes joins required but enforces a contract—analysts must engage with the business logic, reducing misinterpretation and support tickets.
