---
date: 2026-09-17
phase: modelling
topic: Data vault: hubs, links and satellites architecture
---

# Data vault: hubs, links and satellites architecture

*Data modelling and warehousing*

## Concept

Data Vault is a dimensional modeling approach that separates business keys (Hubs), relationships (Links), and descriptive attributes (Satellites) into distinct tables. This design prioritizes auditability, traceability, and resilience to change—critical in environments where data lineage matters and schemas evolve frequently. Hubs store unique business entities (e.g., customers, products); Links capture many-to-many relationships with load and effective dates; Satellites hold all descriptive and slowly-changing attributes tied to a Hub or Link.

Without this separation, fact tables become monolithic and brittle. When a job title description changes, you lose history; when a new attribute is added, you reshape the entire table. Data Vault isolates these concerns: business keys remain stable in Hubs, relationships are timestamped in Links, and attributes flow into Satellites with load_date and end_date to preserve what was true when. This architecture makes it possible for team members to query with confidence—they know a Satellite row represents a single version of the truth for a specific date range.

## Practice

**Problem:** Your `job_postings_fact` table mixes immutable keys (job_id) with mutable attributes (job_title_short, salary_year_avg, job_work_from_home) and temporal data (job_posted_date). When salary updates or work-from-home policy changes, you cannot tell whether the old record was overwritten or a new job was created. You also have no audit trail.

**Solution:**

```sql
-- Hub: unique job business keys
CREATE TABLE h_job (
    h_job_pk INT PRIMARY KEY,
    job_id VARCHAR(50) UNIQUE NOT NULL,
    load_date DATE NOT NULL,
    record_source VARCHAR(50) NOT NULL
);

-- Satellite: job attributes with history
CREATE TABLE s_job_details (
    s_job_details_pk INT PRIMARY KEY,
    h_job_pk INT NOT NULL REFERENCES h_job(h_job_pk),
    job_title_short VARCHAR(100),
    salary_year_avg DECIMAL(10,2),
    job_work_from_home BOOLEAN,
    job_location VARCHAR(100),
    load_date DATE NOT NULL,
    end_date DATE,
    record_source VARCHAR(50) NOT NULL
);

-- Query: current state of a job and its history
SELECT 
    j.job_id,
    sd.job_title_short,
    sd.salary_year_avg,
    sd.load_date,
    sd.end_date
FROM h_job j
INNER JOIN s_job_details sd ON j.h_job_pk = sd.h_job_pk
WHERE j.job_id = '12345'
ORDER BY sd.load_date DESC;
```

## Notes

- **Hub vs. Satellite confusion:** Don't put temporal attributes in the Hub. The Hub is immutable; Satellites capture *all* change. A job_id belongs in the Hub once; job_title updates belong in a Satellite with load_date and end_date.
- **Many-to-many gets a Link:** If a job can belong to multiple job families or a candidate applies to multiple jobs, create a Link table with composite foreign keys to both Hubs and timestamp columns (load_date, effective_date). Facts then reference Links, not Hubs directly.
- **Slowly Changing Dimensions (SCD):** Data Vault is a SCD Type 2 approach by design. Every attribute change inserts a new Satellite row with an end_date on the prior row. This replaces the need for explicit SCD logic in your ETL.
- **Load date and record source are not optional:** These enable traceability and reconciliation. Without them, you cannot debug why a row exists or audit data quality.
- **Bridges to dimensional modeling:** Data Vault feeds conformed dimensions and facts. Satellites become dimensions; Links + Hubs become grain of a fact table. The separation lets analytics teams build clean star schemas downstream without reshaping raw vault data.
