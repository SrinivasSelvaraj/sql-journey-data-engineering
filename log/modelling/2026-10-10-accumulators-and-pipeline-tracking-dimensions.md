---
date: 2026-10-10
phase: modelling
topic: Accumulators and pipeline tracking dimensions
---

# Accumulators and pipeline tracking dimensions

*Data modelling and warehousing*

## Concept

Accumulators are numeric columns in fact tables that store cumulative or aggregated values—sums, counts, or running totals—that support fast analytical queries without requiring joins or subqueries at query time. Pipeline tracking dimensions are metadata columns (like `load_date`, `source_system`, `data_quality_flag`) that document *how* and *when* data entered the warehouse, enabling you to filter for clean data, audit lineage, and debug pipeline failures without separate lookup tables.

Together, they solve a critical problem: making your schema self-documenting and production-ready. Without accumulators, analysts write expensive aggregation queries repeatedly. Without tracking dimensions, you lose visibility into which records are fresh, which source fed them, and whether they passed validation—forcing analysts to ask you "is this data good?" instead of querying with confidence.

Schemas without these patterns become fragile. A join to a slowly-changing dimension breaks if the dimension changes. A metric calculated differently by two teams creates conflicting reports. A pipeline breaks silently and nobody knows for a week. Accumulators and tracking dimensions prevent these by embedding decisions *into the schema itself*.

## Practice

**Problem:** Your analytics team runs dozens of queries to answer "How many job postings per location per month, and what's the average salary?" Currently, they join fact to location dimension, group, aggregate, and filter—over and over. When the pipeline loads bad data, nobody notices until a report looks wrong.

**Solution:** Add an accumulator column and tracking dimensions:

```sql
CREATE TABLE job_postings_fact (
  job_id INT,
  job_title_short VARCHAR,
  salary_year_avg DECIMAL(10,2),
  job_work_from_home BOOLEAN,
  job_posted_date DATE,
  job_location VARCHAR,
  
  -- Accumulators: pre-calculated, ready to sum/avg
  salary_sum DECIMAL(15,2),
  salary_count INT,
  
  -- Pipeline tracking dimensions
  load_date DATE,
  source_system VARCHAR,
  data_quality_score DECIMAL(3,2),  -- 0.0-1.0, reject if <0.95
  is_valid BOOLEAN
);

-- Now analysts write fast, clear queries
SELECT
  job_location,
  DATE_TRUNC('month', job_posted_date) AS month,
  COUNT(*) AS posting_count,
  SUM(salary_sum) / SUM(salary_count) AS avg_salary
FROM job_postings_fact
WHERE is_valid = TRUE
  AND data_quality_score >= 0.95
  AND load_date >= CURRENT_DATE - INTERVAL '7 days'
GROUP BY job_location, DATE_TRUNC('month', job_posted_date);
```

## Notes

- **Accumulator anti-pattern:** Don't create an accumulator for every possible metric. Only pre-calculate when the same aggregation runs in >50% of queries; otherwise you waste storage and create update complexity. `salary_sum` and `salary_count` together are better than a single `avg_salary` because they compose.

- **Tracking dimensions and compliance:** `load_date` and `source_system` are non-negotiable for GDPR/CCPA audits. When you delete or correct a record, you can trace *which pipeline load* introduced bad data and propagate fixes downstream.

- **Common mistake—mixing concerns:** Don't store business logic (like `is_premium_location`) in tracking dimensions. Tracking dimensions answer "*where did this come from?*" and "*is it clean?*"; business logic belongs in conformed dimensions or calculated columns in views.

- **Adjacent topic: Slowly Changing Dimensions (SCDs):** When job_location names change (e.g., "Bay Area" → "San Francisco Bay Area"), accumulators remain stable, but your location dimension may use SCD Type 2. Keep them separate; the fact table's location key points to a dimension version, not the string itself.

- **Revisit:** Test how your pipeline handles late-arriving data. If a job posting loads 30 days late, does `load_date` differ from `job_posted_date`? Your tracking dimensions must capture this, or analysts will misinterpret trends.
