---
date: 2026-09-16
phase: modelling
topic: Conformed dimensions across multiple data marts
---

# Conformed dimensions across multiple data marts

*Data modelling and warehousing*

## Concept

A conformed dimension is a reusable, standardized dimension table that maintains the same structure, grain, and key values across multiple data marts and fact tables. Instead of creating separate location or date tables for each mart, you build one canonical version that every fact table references. This eliminates semantic confusion: when a business user joins job_postings_fact to a location dimension via job_location_id, they get the same city, state, and region codes as when querying a hiring_analytics_mart.

Without conformed dimensions, different teams create their own versions of "Location"—one rolls up cities to states, another to regions, another to time zones. A single job posting might have contradictory location attributes depending on which mart you query. Reconciliation becomes impossible, and every new fact table forces you to build or maintain redundant dimension logic.

Conformed dimensions matter most when you have multiple fact tables that should join consistently (job postings, applicant flows, hiring outcomes) or when non-technical stakeholders need to trust row-level data without asking a data engineer what a column "really" means. They're the foundation of a self-service analytics layer.

## Practice

**Problem:** You've built job_postings_fact with free-text job_location strings ("San Francisco, CA" vs "SF, California" vs "San Francisco"). Now you're adding a hiring_outcomes_fact for the same jobs, and analysts want to slice both tables by region. Without a conformed dimension, location logic diverges, and a job's region differs between marts.

```sql
-- Create conformed location dimension (build once, use everywhere)
CREATE TABLE dim_location (
  location_id INT PRIMARY KEY,
  city VARCHAR(100),
  state_code VARCHAR(2),
  region VARCHAR(50),
  country VARCHAR(100)
);

-- Standardize job_postings_fact to use location_id
ALTER TABLE job_postings_fact
  ADD COLUMN location_id INT,
  DROP COLUMN job_location;

ALTER TABLE job_postings_fact
  ADD CONSTRAINT fk_location
    FOREIGN KEY (location_id) REFERENCES dim_location(location_id);

-- Now hiring_outcomes_fact uses the same dimension
ALTER TABLE hiring_outcomes_fact
  ADD COLUMN location_id INT,
  ADD CONSTRAINT fk_location
    FOREIGN KEY (location_id) REFERENCES dim_location(location_id);

-- Single query across both marts, guaranteed consistency
SELECT
  dl.region,
  COUNT(DISTINCT jpf.job_id) AS postings,
  COUNT(DISTINCT hof.hire_id) AS hires
FROM job_postings_fact jpf
JOIN hiring_outcomes_fact hof ON jpf.job_id = hof.job_id
JOIN dim_location dl ON jpf.location_id = dl.location_id
GROUP BY dl.region;
```

## Notes

- **Grain matters**: a conformed dimension must have consistent granularity across all its uses. If one mart needs hourly timestamps and another needs daily, split into separate dimensions rather than force a compromise that fits neither.
- **Change over time**: use Slowly Changing Dimension (SCD) Type 2 (surrogate key + validity dates) for conformed dimensions when attributes change. A region code that was "West" in 2022 but "Pacific" in 2024 must maintain historical accuracy in all dependent marts.
- **Bridge tables for many-to-many**: some real-world relationships don't fit star schema perfectly (e.g., one job posting applies to multiple locations). Use conformed bridge dimensions to keep fact tables normalized without explosion.
- **Connects to data governance**: conformed dimensions are where you enforce business rules and naming conventions. Document them in a data catalog or lineage tool so analysts find them before reinventing a "Location" table.
- **Test for drift**: periodically audit fact tables to ensure they all reference the same dimension version and grain; schema creep (adding columns only to one mart's usage) degrades conformance over time.
