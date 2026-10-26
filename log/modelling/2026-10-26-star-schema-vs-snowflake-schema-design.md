---
date: 2026-10-26
phase: modelling
topic: Star schema vs snowflake schema design
---

# Star schema vs snowflake schema design

*Data modelling and warehousing*

## Concept

A **star schema** has one central fact table connected directly to denormalized dimension tables, while a **snowflake schema** normalizes dimensions further into hierarchies. Star schemas denormalize data—job locations might store city, state, and country in one row—making queries simpler and faster. Snowflake schemas split those into separate tables (city → state → country), reducing storage and update anomalies but requiring more joins.

Choose star for **self-service analytics**: business users write queries without needing you to explain join logic. Choose snowflake when dimensions change frequently (e.g., organizational hierarchies) or storage is constrained. Without intentional schema design, analysts either ask you repeatedly "what does this column mean?" or build fragile queries that break when upstream data changes.

The tradeoff is real: star schemas optimize for query speed and clarity at the cost of redundancy; snowflake optimizes for maintainability and consistency at the cost of query complexity.

## Practice

**Problem:** Your `job_postings_fact` stores `job_location` as a text field (e.g. "San Francisco, CA, United States"). Analysts keep asking whether filters on location are case-sensitive, how to find all US jobs, and whether you're storing city or region. Multiple analysts write conflicting location queries.

**Solution:** Build a snowflake-style location dimension and star back to it:

```sql
CREATE TABLE dim_location (
  location_id INT PRIMARY KEY,
  city VARCHAR,
  state_code VARCHAR,
  country_code VARCHAR,
  location_name VARCHAR UNIQUE  -- "San Francisco, CA, United States"
);

CREATE TABLE job_postings_fact (
  job_id INT PRIMARY KEY,
  job_title_short VARCHAR,
  salary_year_avg DECIMAL,
  job_work_from_home BOOLEAN,
  job_posted_date DATE,
  location_id INT REFERENCES dim_location(location_id)
);

-- Now analysts write unambiguous queries:
SELECT COUNT(*) 
FROM job_postings_fact f
JOIN dim_location l ON f.location_id = l.location_id
WHERE l.country_code = 'US' AND l.state_code = 'CA';
```

## Notes

- **Denormalization is not evil:** star schemas repeat data intentionally. If dimension updates are rare (job titles, locations), denormalizing into the fact table is faster and clearer than storing IDs only.
- **Conformed dimensions:** if multiple facts reference the same dimension (jobs and candidate profiles both use location), build one shared `dim_location`. Consistency wins.
- **Query performance vs. maintenance cost:** star schemas read fast; snowflake schemas maintain easily. Hybrid approaches are common—denormalize slowly-changing dimensions, normalize fast-moving ones.
- **Metadata and documentation matter equally:** even with perfect schema design, add comments and a data dictionary. "Is `job_posted_date` when the job was posted or indexed?" should never need asking.
- **Revisit when:** dimensions grow (100+ attributes), facts become redundant copies, or analysts report conflicting answers from the same table.
