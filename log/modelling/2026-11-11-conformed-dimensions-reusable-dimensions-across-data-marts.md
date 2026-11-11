---
date: 2026-11-11
phase: modelling
topic: Conformed dimensions: reusable dimensions across data marts
---

# Conformed dimensions: reusable dimensions across data marts

*Data modelling and warehousing*

## Concept

A conformed dimension is a reusable, consistent dimension table shared across multiple data marts or fact tables. Instead of each team building their own `location` or `company` table with different grain, keys, or business logic, everyone references the same source of truth. This eliminates "dimension drift"—the problem where Marketing's definition of "active customer" differs from Sales', breaking cross-functional reporting.

Conformed dimensions matter when you have multiple fact tables that need to join on the same entity. Without them, you either duplicate dimension logic (creating maintenance nightmares) or, worse, build incompatible dimensions that can't be joined together. A single `dim_date` used across all your fact tables means everyone agrees on what "fiscal quarter" means. A fragmented approach means reconciliation failures and lost trust in dashboards.

When dimensions aren't conformed, you get silent mismatches: one mart filters on `is_active = true` in the employee dimension while another uses `employment_status = 'current'`. Queries that should roll up cleanly instead produce unexplained variance. Teams stop trusting the warehouse and build their own extracts.

## Practice

**Problem:** You have `job_postings_fact` and need to build a second fact table, `job_applications_fact`, that tracks applications per job. Both tables need location-level filtering and reporting. If you build location differently in each mart (one with state-level detail, one without), analysts can't combine job volume and application rate by geography.

```sql
-- Create conformed dimension once
CREATE TABLE dim_job_location (
  location_key INT PRIMARY KEY,
  location_name VARCHAR(255),
  city VARCHAR(100),
  state_province VARCHAR(100),
  country VARCHAR(100),
  is_remote BOOLEAN,
  created_at TIMESTAMP,
  updated_at TIMESTAMP
);

-- Both fact tables reference the same dimension key
CREATE TABLE job_postings_fact (
  job_posting_key INT PRIMARY KEY,
  job_id INT,
  location_key INT NOT NULL REFERENCES dim_job_location(location_key),
  salary_year_avg DECIMAL(10, 2),
  job_posted_date DATE
);

CREATE TABLE job_applications_fact (
  application_key INT PRIMARY KEY,
  job_posting_key INT,
  location_key INT NOT NULL REFERENCES dim_job_location(location_key),
  application_date DATE,
  applicant_count INT
);

-- Now any query joining across these facts is consistent
SELECT 
  l.state_province,
  COUNT(DISTINCT jp.job_posting_key) as job_count,
  SUM(ja.applicant_count) as total_applications
FROM job_postings_fact jp
JOIN job_applications_fact ja ON jp.job_posting_key = ja.job_posting_key
JOIN dim_job_location l ON jp.location_key = l.location_key
GROUP BY l.state_province;
```

## Notes

- **Dimension key vs. natural key:** Always use a surrogate key (location_key, not concatenating city+state). This survives name changes and lets you track history via SCD Type 2.
- **Conformed dimensions enable federated governance:** Build once, document once, monitor once. Decentralized dimensions lead to duplicate work and conflicting definitions.
- **Common mistake:** Treating conformed dimensions as "one-size-fits-all." Some marts need finer grain (e.g., product-by-warehouse), others need aggregates. Use conformed *core* attributes + mart-specific extensions.
- **Connects to:** Slowly Changing Dimensions (SCD), bus matrix (mapping which dimensions touch which facts), and data lineage—track where conformed dimensions are used to prevent orphaning old versions.
- **Revisit:** Measure adoption: do analysts actually use the conformed dimension or do they keep building local copies? If low adoption, the dimension definition may not match real requirements.
