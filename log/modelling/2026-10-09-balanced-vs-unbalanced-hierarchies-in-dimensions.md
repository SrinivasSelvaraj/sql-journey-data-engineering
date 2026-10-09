---
date: 2026-10-09
phase: modelling
topic: Balanced vs unbalanced hierarchies in dimensions
---

# Balanced vs unbalanced hierarchies in dimensions

*Data modelling and warehousing*

## Concept

A **balanced hierarchy** is one where every path from root to leaf has the same depth—think of a perfect tree. An **unbalanced hierarchy** has varying depths; some branches are deeper than others. In dimensional modeling, this matters because your aggregation logic, drill-down navigation, and query complexity depend on it.

When hierarchies are unbalanced (e.g., a Geography dimension with Country → Region → City, but some countries skip the Region level), queries that assume uniform depth will either fail or produce misleading results. A user drilling from "USA" expects to see states; if Canada has no province level in your data, your reporting logic breaks or requires special handling.

Without clarity on balance, teams either over-aggregate (losing detail) or over-normalize (creating sparse, confusing hierarchies). The cost is paid at query time—convoluted CASE statements, self-joins, or recursive CTEs to handle missing levels. Good dimensional design makes the hierarchy's structure explicit, allowing straightforward GROUP BY operations and predictable drill-down behavior.

## Practice

**Problem:** You're building a fact table for job postings. The `job_location` column contains values like "New York, NY" and "Remote". You need to support queries that aggregate by city, state, and country, but not all jobs have complete location data—remote jobs have no geography, and some older posts only list state. Without a proper unbalanced hierarchy design, your roll-up queries will either drop rows or produce inflated numbers.

```sql
-- Create a balanced dimension with a "Unknown" level for missing values
CREATE TABLE dim_job_location (
  location_key SMALLINT PRIMARY KEY,
  country VARCHAR(50),
  state_province VARCHAR(50),
  city VARCHAR(100),
  is_remote BOOLEAN,
  location_type VARCHAR(20)  -- 'city', 'state', 'remote', 'unknown'
);

INSERT INTO dim_job_location VALUES
(1, 'USA', 'NY', 'New York', FALSE, 'city'),
(2, 'USA', 'NY', NULL, FALSE, 'state'),
(3, 'USA', NULL, NULL, FALSE, 'country'),
(4, NULL, NULL, NULL, TRUE, 'remote'),
(5, NULL, NULL, NULL, NULL, 'unknown');

-- Now your fact table references the dimension key, ensuring consistent hierarchy levels
ALTER TABLE job_postings_fact ADD COLUMN location_key SMALLINT REFERENCES dim_job_location;

-- Queries now aggregate cleanly without logic branching
SELECT d.country, d.state_province, COUNT(*) as job_count
FROM job_postings_fact f
JOIN dim_job_location d ON f.location_key = d.location_key
WHERE d.location_type IN ('city', 'state')  -- explicit level filtering
GROUP BY d.country, d.state_province;
```

## Notes

- **Mistake:** Treating hierarchies as always-filled. Remote jobs, "TBD" locations, and historical data gaps are common—design for these with placeholder rows ("Unknown", "Remote", "Not Applicable") rather than NULLs in the dimension.
- **Mistake:** Confusing hierarchies with attributes. If you have both location hierarchy (Country → State → City) and attributes (timezone, cost_of_living), keep them separate to avoid unbalanced traversal.
- **Connection:** This relates directly to **slowly changing dimensions (SCD)** and **conformed dimensions**—when a hierarchy changes (e.g., a new region is added), you need to version it without breaking existing drill-down paths.
- **Revisit:** The distinction between "balanced by design" and "balanced by reporting"—sometimes your source data is unbalanced, but you artificially balance it in the warehouse for query consistency. This is intentional and good.
- **Edge case:** Parent-child tables (storing hierarchy relationships explicitly) are an alternative for highly unbalanced hierarchies; they're more flexible but slower to query and require recursive CTEs.
