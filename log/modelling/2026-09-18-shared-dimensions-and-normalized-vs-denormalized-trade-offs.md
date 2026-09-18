---
date: 2026-09-18
phase: modelling
topic: Shared dimensions and normalized vs denormalized trade-offs
---

# Shared dimensions and normalized vs denormalized trade-offs

*Data modelling and warehousing*

## Concept

Shared dimensions are reusable lookup tables that multiple fact tables reference via foreign keys. Instead of storing "Python" as text in every row of a job_postings fact table and a skills fact table, you create a single skills_dim table and join to it. This is the normalized approach.

Denormalization trades join overhead and storage efficiency for query simplicity and speed. You might copy skill names directly into job_postings_fact to avoid a join, accepting redundancy and update risk. The trade-off matters acutely in data warehouses: normalized schemas reduce storage and prevent anomalies (what if one table says "Python" and another says "python"?), but denormalized schemas let analysts query without understanding relationships and execute faster on analytical workloads that rarely update.

Without shared dimensions, you lose the single source of truth. Analysts see conflicting values, maintain separate lists, and your warehouse becomes a trust liability. Without some denormalization, query complexity explodes and scan performance suffers on terabyte-scale tables. The balance depends on query patterns, team maturity, and whether your ETL can keep denormalized copies fresh.

## Practice

**Problem:** Your job_postings_fact table stores full location names ("San Francisco, CA"). Fifty fact tables and 200+ dashboards reference locations. A city rebrands or you need to standardize spelling. You must update thousands of rows across multiple tables, risking inconsistency.

**Solution:** Extract locations to a shared dimension and use a surrogate key:

```sql
CREATE TABLE locations_dim (
  location_id INT PRIMARY KEY,
  city VARCHAR(100),
  state_code VARCHAR(2),
  country VARCHAR(100),
  region VARCHAR(50),
  created_at TIMESTAMP
);

CREATE TABLE job_postings_fact (
  job_id INT PRIMARY KEY,
  job_title_short VARCHAR(100),
  salary_year_avg DECIMAL(10, 2),
  job_work_from_home BOOLEAN,
  job_posted_date DATE,
  location_id INT REFERENCES locations_dim(location_id)
);

-- Analysts query:
SELECT jp.job_id, jp.job_title_short, ld.city, ld.state_code
  FROM job_postings_fact jp
  JOIN locations_dim ld ON jp.location_id = ld.location_id
 WHERE ld.state_code = 'CA';
```

Now update the city name once in locations_dim; all queries reflect the change instantly.

## Notes

- **Denormalize strategically:** Keep dimensions normalized; denormalize only slow-moving attributes (job titles, skill categories) that change rarely and fit the query patterns your team actually runs.
- **Surrogate keys vs. natural keys:** Use integer surrogate keys (location_id) in fact tables for smaller joins and flexibility; keep natural keys (city + state) in dimensions for debugging and audits.
- **Snowflake schemas:** Don't over-normalize. A skills_dim table doesn't need to point to a skill_category_dim; flatten it if skill categories never change independently.
- **Grain mismatch:** Ensure every fact row has exactly one dimension row (or zero for nullable FKs). Ambiguity here breaks aggregates silently.
- **Related: Slowly Changing Dimensions (SCD).** When location attributes *do* change (e.g., region reassignment), you need SCD Type 2 (versioning) to keep historical accuracy—another reason to normalize.
