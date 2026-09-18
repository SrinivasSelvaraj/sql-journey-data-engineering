---
date: 2026-09-18
phase: modelling
topic: Hierarchical attributes and level metadata
---

# Hierarchical attributes and level metadata

*Data modelling and warehousing*

## Concept

Hierarchical attributes are dimensional properties that form natural parent–child relationships: country → region → city, or job category → subcategory → skill level. Level metadata describes *what each attribute means* and *how it relates to others*—it's the difference between a column called `location` and one labeled `job_location_city (finest grain; roll up to job_location_region, then job_location_country)`.

Without explicit hierarchy documentation, analysts write queries wrong. They join on ambiguous keys, aggregate at the wrong grain, or create contradictory rollups. A salary fact keyed only to `job_location` creates ambiguity: does it represent city-level, regional, or country-level truth? When new team members inherit your schema, they guess—and guessing means bugs.

Level metadata also prevents double-counting in aggregations and enables graceful drill-down reporting. It's the contract that says: "This column is atomic; that one is derived; these three form a rollup path."

## Practice

**Problem:** Your team queries `job_postings_fact` and struggles with `job_location`. Some analysts filter by country, others by city. Salary comparisons become unreliable because two identical job titles in "New York" might mean the state or the city, and salary_year_avg is unclear at which geographic grain it applies.

**Solution:** Create a conformed dimension with explicit hierarchy levels and add a metadata reference to the fact table:

```sql
-- Conformed dimension with hierarchy levels
CREATE TABLE dim_job_location (
  location_key INT PRIMARY KEY,
  location_country VARCHAR NOT NULL,
  location_region VARCHAR NOT NULL,
  location_city VARCHAR NOT NULL,
  location_grain VARCHAR NOT NULL
    CHECK (location_grain IN ('country', 'region', 'city'))
);

-- Fact table with foreign key + documented grain
CREATE TABLE job_postings_fact (
  job_id INT,
  job_title_short VARCHAR,
  salary_year_avg DECIMAL,
  salary_grain VARCHAR NOT NULL 
    CHECK (salary_grain IN ('country', 'region', 'city')),
  job_work_from_home BOOLEAN,
  job_posted_date DATE,
  location_key INT REFERENCES dim_job_location(location_key)
);

-- Query example: safe aggregation at declared grain
SELECT 
  location_country,
  AVG(salary_year_avg) as avg_salary
FROM job_postings_fact f
JOIN dim_job_location d ON f.location_key = d.location_key
WHERE f.salary_grain = 'country'  -- Enforce grain match
GROUP BY location_country;
```

## Notes

- **Grain mismatch is silent and deadly.** A salary fact recorded at city level rolled up as country-level overweights dense cities. Always document and validate grain in queries.
- **Conformed dimensions enforce consistency.** Multiple fact tables can safely reference the same `dim_job_location`, so all teams see one "source of truth" for geographic rollups.
- **Metadata belongs in the DDL, not in a README.** Use `CHECK` constraints, comments, and a metadata table (schema name, grain, rollup path) so queries are self-documenting.
- **This connects to slowly changing dimensions (SCD).** If job categories evolve over time, your hierarchy needs a validity window; grain metadata must account for historical changes.
- **Revisit this when you add new attributes.** Every new dimension column should declare its grain and rollup parent; if it doesn't fit a hierarchy, document why it's atomic instead.
