---
date: 2026-09-18
phase: modelling
topic: Geography hierarchies: country, state, city
---

# Geography hierarchies: country, state, city

*Data modelling and warehousing*

## Concept

A geography hierarchy organizes location data into nested levels—country → state → city—so that queries and aggregations work consistently at any grain. Without it, you store `job_location` as free text ("New York, NY" vs "NY, New York" vs "New York"), forcing every analyst to clean and standardize before joining to other location-keyed tables (population, cost-of-living, tax rates).

A proper hierarchy uses surrogate keys: a `location_dim` table with `location_id`, `city`, `state`, `country`, `state_code`, `country_code`, and a `location_key` that uniquely identifies each city-state-country combo. Your fact table then references `location_id`, not text. This makes filtering, joining, and aggregation predictable—"show me job volume by state" works in one join, not five regex passes.

Without hierarchy, you lose drill-down capability and create silent data quality issues. A city named "Springfield" could exist in multiple states; latitude/longitude alone doesn't tell you which one. Hierarchy forces you to decide once, version it, and everyone queries the same truth.

## Practice

**Problem:** You need to report average salary by state and identify which state has the most remote-capable job postings, but `job_location` contains values like "New York, NY", "New York, New York", "NY", and "Remote".

```sql
-- Build a location dimension
CREATE TABLE location_dim AS
SELECT
  ROW_NUMBER() OVER (ORDER BY country, state, city) AS location_id,
  city,
  state,
  state_code,
  country,
  country_code
FROM (
  SELECT DISTINCT
    SPLIT_PART(job_location, ',', 2)::VARCHAR AS state,
    SPLIT_PART(job_location, ',', 1)::VARCHAR AS city,
    'US' AS country_code,
    'United States' AS country,
    (SELECT state_code FROM us_state_lookup WHERE state_name = TRIM(SPLIT_PART(job_location, ',', 2))) AS state_code
  FROM job_postings_fact
  WHERE job_location NOT ILIKE '%remote%'
) AS parsed;

-- Query: avg salary by state + remote job count
SELECT
  l.state,
  ROUND(AVG(j.salary_year_avg), 2) AS avg_salary,
  COUNT(CASE WHEN j.job_work_from_home THEN 1 END) AS remote_jobs
FROM job_postings_fact j
LEFT JOIN location_dim l ON j.location_id = l.location_id
GROUP BY l.state
ORDER BY remote_jobs DESC;
```

## Notes

- **Ambiguity trap:** Cities repeat across states; always include state+country in your unique key, not just city name alone.
- **Late-arriving geography:** Build the hierarchy *before* populating fact tables; retroactively joining location text to a new dimension creates join failures and duplicates.
- **Conformed dimensions:** Use the same `location_dim` across all fact tables (sales, HR, logistics). Consistency matters more than perfection.
- **Related topics:** Slowly changing dimensions (SCD Type 2) track when boundaries change; star schemas depend on dimension tables; data governance owns the hierarchy definition.
- **Revisit:** Test how your hierarchy handles edge cases—territories, postal code changes, renamed cities—before it grows to 10M rows.
