---
date: 2026-10-27
phase: modelling
topic: Geography hierarchies and spatial relationships
---

# Geography hierarchies and spatial relationships

*Data modelling and warehousing*

## Concept

Geography hierarchies organize spatial data into nested levels—country → region → city → postal code—so queries can aggregate meaningfully at any grain. Without this structure, a `job_location` column containing "San Francisco, CA" or "remote" forces analysts to parse strings, handle duplicates ("SF" vs "San Francisco"), and choose arbitrary aggregation levels. A proper hierarchy separates concerns: location names live in a dimension table with standardized codes, parent references, and metadata (timezone, cost-of-living index); facts reference only the lowest grain they know, then JOIN upward as needed.

This matters when your business asks questions like "which regions are hiring the most" or "compare coastal vs inland salaries"—answers that require rollup logic embedded in your schema, not buried in application code. It also prevents silent errors: if someone forgets to handle nulls in a location string, their analysis silently excludes remote workers. A dimension-based approach makes that ambiguity explicit and testable.

Without hierarchy design, you'll eventually have conflicting definitions of regions across teams, analyses that can't be compared, and schemas that don't scale beyond a single country or business context.

## Practice

**Problem:** Your team needs to compare average salary by state and determine whether remote jobs are skewing results. Currently, `job_location` is a free-text string like "San Francisco, CA", "Remote", or "United States". A simple `GROUP BY job_location` produces 500+ rows, mixes cities and states, and treats "Remote" as a location. Design a schema that lets non-analysts write correct queries.

```sql
-- Geography Dimension
CREATE TABLE dim_location (
    location_id INT PRIMARY KEY,
    location_name VARCHAR(100),
    location_type VARCHAR(20), -- 'city', 'state', 'country', 'remote'
    parent_location_id INT REFERENCES dim_location(location_id),
    state_code CHAR(2),
    country_code CHAR(2),
    is_remote BOOLEAN DEFAULT FALSE
);

-- Fact table with location reference
ALTER TABLE job_postings_fact
ADD COLUMN location_id INT REFERENCES dim_location(location_id),
ADD COLUMN is_remote BOOLEAN;

-- Query: Average salary by state (excludes remote, or includes it as a separate row)
SELECT 
    l_state.location_name AS state,
    ROUND(AVG(jpf.salary_year_avg)) AS avg_salary,
    COUNT(*) AS job_count
FROM job_postings_fact jpf
JOIN dim_location l_city ON jpf.location_id = l_city.location_id
LEFT JOIN dim_location l_state ON l_city.parent_location_id = l_state.location_id
WHERE l_state.location_type = 'state' OR jpf.is_remote = TRUE
GROUP BY l_state.location_name
ORDER BY avg_salary DESC;
```

## Notes

- **Mistake:** Storing location as a single flat dimension. Always include a parent reference and location_type so hierarchies stay queryable at any level without string parsing.
- **Mistake:** Treating "remote" as a location. Remote is a *work mode*, not a geography; store it separately and let analysts choose whether to include it in geographic aggregations.
- **Connection:** Conforms dimensional modeling (Kimball); similar pattern applies to product hierarchies (category → subcategory → SKU) and organizational structures (company → division → team).
- **Revisit:** Handling late-arriving geography data (e.g., a city's state assignment changes after hiring); use SCD Type 2 (slowly changing dimensions) if history matters.
- **Scalability:** Pre-compute common rollups (e.g., state-level salary stats) in aggregate tables or materialized views to avoid expensive JOIN chains when analysts work at coarse grains.
