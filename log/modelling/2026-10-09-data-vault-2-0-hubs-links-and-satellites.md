---
date: 2026-10-09
phase: modelling
topic: Data vault 2.0: hubs, links and satellites
---

# Data vault 2.0: hubs, links and satellites

*Data modelling and warehousing*

## Concept

Data Vault 2.0 is a dimensional modeling technique that organizes data into three entity types: **hubs** (business keys and their surrogates), **links** (relationships between business entities), and **satellites** (descriptive attributes and their history). Unlike star schemas that denormalize facts around dimensions, Data Vault 2.0 normalizes around business entities first, making it resilient to requirement changes and enabling independent loading of different data streams without redesign.

This matters when your warehouse must be audit-compliant, support slowly-changing dimensions without ETL complexity, or ingest data from multiple source systems at different cadences. The hub-link-satellite structure makes lineage explicit: you always know which system loaded what, when it changed, and which entities it affects. Without this separation, adding a new attribute forces you to modify fact tables, restate historical data, or create ad-hoc views that obscure your data's true structure.

Breaking it means mixing business keys with descriptions in the same table, losing the ability to track when attributes changed, creating circular dependencies in your schema, or burying entity relationships inside fact tables where they can't be reused. Teams end up asking "what does this column actually mean?" because no single table documents the complete lineage of a business entity.

## Practice

**Problem:** Your `job_postings_fact` table mixes stable job identifiers with volatile salary data and mutable location attributes. When a job's remote-work policy changes or salary data gets corrected, you can't record the change without restating history or creating multiple fact rows with identical job_ids. New analysts can't tell whether `job_location` is the posting location or company HQ.

**Solution:** Restructure into hub, link, and satellites:

```sql
-- Hub: the job posting business key
CREATE TABLE hub_job_posting (
  hub_job_posting_id INT PRIMARY KEY,
  job_id VARCHAR UNIQUE NOT NULL,  -- business key
  load_dts TIMESTAMP NOT NULL,
  record_source VARCHAR NOT NULL
);

-- Satellite: job descriptors that change slowly
CREATE TABLE sat_job_posting_details (
  hub_job_posting_id INT,
  load_dts TIMESTAMP,
  end_dts TIMESTAMP,
  job_title_short VARCHAR,
  job_location VARCHAR,
  record_source VARCHAR,
  is_current BOOLEAN,
  PRIMARY KEY (hub_job_posting_id, load_dts),
  FOREIGN KEY (hub_job_posting_id) REFERENCES hub_job_posting
);

-- Satellite: compensation (loaded on different schedule)
CREATE TABLE sat_job_posting_compensation (
  hub_job_posting_id INT,
  load_dts TIMESTAMP,
  end_dts TIMESTAMP,
  salary_year_avg DECIMAL,
  record_source VARCHAR,
  is_current BOOLEAN,
  PRIMARY KEY (hub_job_posting_id, load_dts),
  FOREIGN KEY (hub_job_posting_id) REFERENCES hub_job_posting
);

-- Satellite: work arrangement facts
CREATE TABLE sat_job_posting_work_arrangement (
  hub_job_posting_id INT,
  load_dts TIMESTAMP,
  end_dts TIMESTAMP,
  job_work_from_home BOOLEAN,
  record_source VARCHAR,
  is_current BOOLEAN,
  PRIMARY KEY (hub_job_posting_id, load_dts),
  FOREIGN KEY (hub_job_posting_id) REFERENCES hub_job_posting
);

-- Query current state (analysts don't ask what fields mean—schema documents it)
SELECT
  jp.job_id,
  d.job_title_short,
  d.job_location,
  c.salary_year_avg,
  w.job_work_from_home
FROM hub_job_posting jp
LEFT JOIN sat_job_posting_details d 
  ON jp.hub_job_posting_id = d.hub_job_posting_id 
  AND d.is_current = TRUE
LEFT JOIN sat_job_posting_compensation c 
  ON jp.hub_job_posting_id = c.hub_job_posting_id 
  AND c.is_current = TRUE
LEFT JOIN sat_job_posting_work_arrangement w 
  ON jp.hub_job_posting_id = w.hub_job_posting_id 
  AND w.is_current = TRUE;
```

## Notes

- **Mistake: confusing satellites with slowly-changing dimensions.** SCD2 (type 2) is a technique; satellites are a *structure* that makes SCD2 inevitable and clean. Don't add end_dts to a fact table and call it Data Vault.
- **Mistake: putting too much in one satellite.** If job title, location, and industry classification load on different schedules or from different sources, they belong in separate satellites. Coupling unrelated changes defeats the purpose.
- **Connects to:** dimensional modeling (stars vs. normalized), slowly-changing dimensions (SCD1/2/3), time-variant schemas, and source system integration patterns. Data Vault trades query simplicity for schema stability.
- **Revisit:** how
