---
date: 2026-08-10
phase: modelling
topic: Data vault modelling: hubs, links, satellites
---

# Data vault modelling: hubs, links, satellites

*Data modelling and warehousing*

## Concept

Data Vault 2.0 is a modeling technique that separates *what* entities are (hubs), *how* they relate (links), and *how* they change over time (satellites). This matters because it decouples business logic from the warehouse schema: you can add new attributes, relationships, or slowly-changing dimensions without restructuring existing tables. Without this separation, every new business rule triggers schema refactoring that breaks downstream queries and BI tools.

The core idea is immutability at the hub and link layer—once a customer or product is recorded, their entity record never changes. Attributes and their histories live in satellites, timestamped and versioned. This design handles slowly-changing dimensions (SCD Type 2) naturally and makes audit trails explicit. It scales well when requirements evolve: new satellite tables are additive, not disruptive.

## Practice

**Problem:** Your `job_postings_fact` conflates entity identity (job_id), attributes that change slowly (job_title_short, job_location), and attributes that change rapidly (salary_year_avg, posted_date). Adding new job attributes or tracking title changes requires altering the fact table. How do you redesign this for maintainability?

```sql
-- Hub: what jobs exist (immutable core)
CREATE TABLE h_job (
    job_key SERIAL PRIMARY KEY,
    job_id VARCHAR UNIQUE NOT NULL,
    load_date DATE NOT NULL,
    record_source VARCHAR NOT NULL
);

-- Link: relationships (e.g., job to location, job to company)
CREATE TABLE l_job_location (
    link_key SERIAL PRIMARY KEY,
    job_key INT REFERENCES h_job(job_key),
    location_key INT REFERENCES h_location(job_key),
    load_date DATE NOT NULL,
    record_source VARCHAR NOT NULL
);

-- Satellite: job attributes + history (SCD Type 2)
CREATE TABLE s_job_details (
    job_key INT REFERENCES h_job(job_key),
    load_date DATE NOT NULL,
    load_end_date DATE,
    record_source VARCHAR NOT NULL,
    job_title_short VARCHAR,
    salary_year_avg NUMERIC,
    job_work_from_home BOOLEAN,
    is_current BOOLEAN,
    PRIMARY KEY (job_key, load_date)
);

-- Query: find current job titles and salaries
SELECT h.job_id, s.job_title_short, s.salary_year_avg
FROM h_job h
JOIN s_job_details s ON h.job_key = s.job_key AND s.is_current = TRUE;
```

## Notes

- **Common mistake:** treating hubs as slowly-changing tables. Hubs are immutable once inserted—if a job_id is a hub, its identity never changes. Move mutable attributes to satellites immediately.
- **Confusing with 3NF:** Vault is *more* normalized than dimensional modeling (which uses conformed dimensions). It's designed for source-system agility, not query simplicity; combine it with a dimensional layer for BI.
- **SCD Type 2 is built-in:** Satellites naturally track effective/end dates and `is_current` flags. You don't need a separate audit table; history is queryable.
- **Revisit:** Hash keys (MD5 hashes of business keys) are often used instead of surrogate keys to handle late-arriving facts and distributed load. Also explore "point-in-time" tables for analytics if Vault queries become slow.
- **Adjacent topic:** Data lineage and record_source tracking are core to Vault's audit capability—always populate these fields from your ELT pipeline.
