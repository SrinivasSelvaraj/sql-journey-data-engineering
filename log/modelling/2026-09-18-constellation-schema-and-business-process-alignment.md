---
date: 2026-09-18
phase: modelling
topic: Constellation schema and business process alignment
---

# Constellation schema and business process alignment

*Data modelling and warehousing*

## Concept

A constellation schema is a fact table connected to multiple dimension tables that model different business processes or analytical perspectives—without forcing all logic into a single massive star schema. It differs from a simple star schema by allowing dimension tables to be reused and queried from multiple fact tables, creating a flexible network rather than isolated stars.

This matters because real business questions rarely fit one process. A recruiting team asks "how long do engineering roles stay open?" (job_postings_fact) *and* "which hiring managers approve the most positions?" (hiring_approvals_fact), both needing location and job_family dimensions. Without constellation design, you either duplicate dimensions (breaking DRY), denormalize ruthlessly (breaking clarity), or force unrelated facts into one table (breaking query intent).

Without it, analysts start asking you what columns mean because the schema structure doesn't communicate intent. A column like `job_posted_date` in a fact table muddled with `job_filled_date`, `job_archived_date`, and `days_open` suggests poor grain definition. A constellation forces you to name separate fact tables for posting events, closing events, and applications—each with clean, self-documenting grain.

## Practice

**Problem:** Your job_postings_fact mixes posting lifecycle events (when posted) with job attributes (salary, remote flag). An analyst wants "average time to hire by location and job family" but your fact table grains don't separate the event of posting from the event of hiring. Adding a `days_to_hire` column is a band-aid; you need a second fact table.

```sql
-- Constellated schema: separate concerns, reuse dimensions

CREATE TABLE job_postings_fact (
  job_posting_id INT,
  job_id INT,
  location_key INT,
  job_family_key INT,
  posted_date DATE,
  salary_year_avg INT,
  work_from_home BOOLEAN
);

CREATE TABLE job_hiring_fact (
  hiring_event_id INT,
  job_posting_id INT,
  job_id INT,
  location_key INT,
  job_family_key INT,
  filled_date DATE,
  days_to_hire INT
);

CREATE TABLE dim_location (
  location_key INT PRIMARY KEY,
  location_name VARCHAR,
  region VARCHAR,
  country VARCHAR
);

CREATE TABLE dim_job_family (
  job_family_key INT PRIMARY KEY,
  job_family_name VARCHAR,
  department VARCHAR
);

-- Now query time-to-hire without contaminating posting volume metrics
SELECT 
  l.region,
  jf.job_family_name,
  AVG(h.days_to_hire) AS avg_days_to_hire
FROM job_hiring_fact h
JOIN dim_location l ON h.location_key = l.location_key
JOIN dim_job_family jf ON h.job_family_key = jf.job_family_key
GROUP BY l.region, jf.job_family_name;
```

## Notes

- **Grain confusion is the biggest pitfall:** don't add `days_to_hire` as a calculated column in a fact table; instead, create a separate fact table for hiring events with a clear grain (one row per hire).
- **Dimension reuse is the payoff:** location_key and job_family_key appear in both job_postings_fact and job_hiring_fact, so you maintain one dim_location and get consistent region rollups across both processes.
- **Watch for slowly changing dimensions:** job titles and salaries evolve; decide whether dim_job_family is Type 1 (overwrite) or Type 2 (time-track with effective dates). A constellation makes this decision clearer because multiple facts depend on it.
- **Bridges vs. constellations:** if job_family has many-to-many relationships (one posting targets multiple families), add a bridge table (job_posting_to_family). Constellation allows this pattern naturally.
- **Adjacent skills:** constellation design overlaps with fact table grain definition (Kimball), bus matrices (which business processes share dimensions), and dimensional modelling maturity (constellations emerge after you've built 3+ star schemas and see the overlaps).
