---
date: 2026-10-26
phase: modelling
topic: Role-playing dimensions and multiple hierarchies
---

# Role-playing dimensions and multiple hierarchies

*Data modelling and warehousing*

## Concept

Role-playing dimensions allow a single dimension table to be referenced multiple times in a fact table, each time playing a different semantic role. A classic example: a fact table can join to an `employee` dimension as both "manager_id" and "employee_id," letting you analyze facts from both perspectives without duplicating the dimension. Multiple hierarchies within a single dimension—like a product dimension containing both "category → subcategory → product" and "brand → product line → product"—let users drill down through different organizational structures without creating separate dimension tables or denormalized wide tables.

This matters because without it, you either duplicate dimension logic (creating maintenance nightmares and inconsistent keys), or you flatten hierarchies into wide tables with redundant columns that break under change. Users then can't navigate your data cleanly: they'll either ask you "which column is the real category?" or write messy self-joins and case statements. Clean role-playing and hierarchies make queries self-documenting and dimensional navigation intuitive.

## Practice

**Problem:** You have a job postings fact table and a locations dimension. You need to analyze salary by job location (where the job is posted) *and* by company headquarters location (where hiring decisions are made), but you only have one locations table.

```sql
-- Solution: role-playing dimension with foreign key aliases
CREATE TABLE locations_dim (
  location_id INT PRIMARY KEY,
  city VARCHAR,
  state VARCHAR,
  country VARCHAR,
  region VARCHAR  -- hierarchy level
);

CREATE TABLE job_postings_fact (
  job_id INT PRIMARY KEY,
  job_title_short VARCHAR,
  salary_year_avg DECIMAL,
  job_work_from_home BOOLEAN,
  job_posted_date DATE,
  job_location_id INT,           -- role 1: where job is posted
  company_hq_location_id INT,    -- role 2: where company is based
  FOREIGN KEY (job_location_id) REFERENCES locations_dim(location_id),
  FOREIGN KEY (company_hq_location_id) REFERENCES locations_dim(location_id)
);

-- Query using both roles
SELECT 
  jl.region AS job_region,
  chq.region AS hq_region,
  AVG(f.salary_year_avg) AS avg_salary,
  COUNT(*) AS job_count
FROM job_postings_fact f
JOIN locations_dim jl ON f.job_location_id = jl.location_id
JOIN locations_dim chq ON f.company_hq_location_id = chq.location_id
GROUP BY jl.region, chq.region;
```

## Notes

- **Naming is critical:** use suffixes like `_location_id` and `_hq_location_id` (not just `location_1` and `location_2`) so the role is obvious to anyone reading the schema.
- **Hierarchies in dimensions reduce query complexity:** instead of writing recursive CTEs or multiple self-joins, denormalize the hierarchy levels (region, country, category, subcategory) into the dimension so users can group by any level directly.
- **Watch for slowly-changing dimensions (SCD):** if hierarchies or role assignments change over time, you need SCD Type 2 (effective dates) to preserve historical accuracy in your facts.
- **Document the dimension's natural hierarchy in a data dictionary:** unclear which column represents which level in the hierarchy, and your self-service BI tool becomes useless.
- **Constellations of facts share dimensions:** multiple fact tables often role-play the same dimension (e.g., dates as "order_date," "ship_date," "delivery_date"), so consistency across fact tables is a design-quality signal.
