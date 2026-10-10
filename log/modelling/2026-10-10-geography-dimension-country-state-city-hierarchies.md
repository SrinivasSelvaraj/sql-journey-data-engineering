---
date: 2026-10-10
phase: modelling
topic: Geography dimension: country-state-city hierarchies
---

# Geography dimension: country-state-city hierarchies

*Data modelling and warehousing*

## Concept

A geography dimension organizes locations into a strict hierarchy—country → state/province → city—enabling aggregations at any level without string parsing or repeated lookups. Instead of storing "San Francisco, CA, USA" as a single text field in your fact table, you reference a `dim_geography` table where each row is a unique city with foreign keys pointing to its parent state and country.

This matters when business questions span multiple granularities: "revenue by country," "top 10 cities in California," "growth rate state-over-state." Without a proper hierarchy, you either duplicate hierarchical logic across queries, struggle with inconsistent abbreviations (CA vs California vs calif.), or end up with brittle string operations in SQL. The dimension also makes it trivial to add attributes like timezone, region code, or population—once—rather than scattering them across fact tables.

Breaking it: if job_location is a VARCHAR blob, you'll spend weeks reconciling "New York" vs "New York, NY" vs "NEW YORK, NEW YORK", you can't easily filter by state without regex, and adding a new attribute means updating every table that touches geography.

## Practice

**Problem:** You need to answer "What is the average salary for work-from-home jobs posted in each state?" and also "Which countries have the most job postings?" Your current job_postings_fact has a messy job_location column mixing formats.

```sql
-- Create the geography dimension
CREATE TABLE dim_geography (
    geography_id INT PRIMARY KEY,
    city_name VARCHAR(100),
    state_code VARCHAR(2),
    state_name VARCHAR(50),
    country_code VARCHAR(2),
    country_name VARCHAR(100),
    UNIQUE(city_name, state_code, country_code)
);

-- Populate with cleaned data (sample)
INSERT INTO dim_geography VALUES
(1, 'San Francisco', 'CA', 'California', 'US', 'United States'),
(2, 'New York', 'NY', 'New York', 'US', 'United States'),
(3, 'Toronto', 'ON', 'Ontario', 'CA', 'Canada');

-- Rebuild fact table with foreign key
ALTER TABLE job_postings_fact 
ADD COLUMN geography_id INT REFERENCES dim_geography(geography_id);

-- Query: average salary by state
SELECT 
    g.state_name,
    COUNT(j.job_id) AS posting_count,
    AVG(j.salary_year_avg) AS avg_salary
FROM job_postings_fact j
JOIN dim_geography g ON j.geography_id = g.geography_id
WHERE j.job_work_from_home = FALSE
GROUP BY g.state_name
ORDER BY avg_salary DESC;

-- Query: postings by country
SELECT 
    g.country_name,
    COUNT(j.job_id) AS posting_count
FROM job_postings_fact j
JOIN dim_geography g ON j.geography_id = g.geography_id
GROUP BY g.country_name
ORDER BY posting_count DESC;
```

## Notes

- **Normalization trap:** Don't create separate `dim_state` and `dim_city` tables unless you have thousands of cities or attributes that vary independently. A flat `dim_geography` with denormalized state and country fields is usually cleaner and faster.
- **Data quality first:** Invest heavily in ETL validation and a canonical location master before building the dimension. Misspellings and abbreviation inconsistencies poison the entire warehouse.
- **Slowly Changing Dimension (SCD):** When a city gets renamed or moves between states (rare but possible), decide your strategy: Type 1 (overwrite), Type 2 (add versioned row with effective dates), or Type 3 (keep current + previous value). Document it.
- **Adjacent patterns:** This dimension sits alongside `dim_date`, `dim_employee`, and similar lookup tables in a star schema. Fact tables radiate outward to multiple dimensions to enable flexible slicing.
- **Revisit:** Once you have a robust geography dimension, consider consolidating other location-like fields (office_location, warehouse_location, customer_region) into the same dimension to avoid duplication.
