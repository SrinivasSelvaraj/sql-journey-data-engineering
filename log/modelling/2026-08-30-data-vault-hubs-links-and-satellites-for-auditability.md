---
date: 2026-08-30
phase: modelling
topic: Data vault: hubs, links and satellites for auditability
---

# Data vault: hubs, links and satellites for auditability

*Data modelling and warehousing*

## Concept

Data Vault is a dimensional modeling technique that separates business keys (Hubs), relationships (Links), and descriptive attributes (Satellites) to create an audit trail and handle slowly changing dimensions without redundancy. A Hub holds unique business entities and their load dates; a Link tracks relationships between Hubs with temporal context; a Satellite stores all attribute changes with effective dates, allowing you to query "what did we know on this date?" Hubs use natural keys (like `job_id`, `company_id`), while Links and Satellites use surrogate keys to reference them, creating a traceable chain from raw data to final values.

This matters when regulatory compliance, data lineage, or handling Type 2 changes (full history) is essential. Without it, you either lose change history (overwriting old values), create denormalized fact tables that hide which attributes changed when, or end up with wide, expensive slowly-changing-dimension logic that becomes unmaintainable. Data Vault keeps auditable history as a first-class citizen, making it easier for analysts to understand not just *what* is true now, but *when* and *why* it changed.

## Practice

**Problem:** Your `job_postings_fact` table mixes slowly changing attributes (job title, location might be updated) with point-in-time facts (posted date, salary). When a job posting is reposted with a new salary or location, you can't tell if you're analyzing the original posting or an updated one, and reporting queries need special logic to handle duplicates.

```sql
-- Hub: Core job entity with natural key and load timestamp
CREATE TABLE job_hub (
  job_hk BINARY(16),           -- hash key of job_id
  job_id VARCHAR(100) NOT NULL,
  load_date DATE NOT NULL,
  UNIQUE (job_id)
);

-- Link: Relationship between job and company (if company_id exists)
CREATE TABLE job_company_link (
  job_company_lk BINARY(16),
  job_hk BINARY(16),
  company_hk BINARY(16),
  load_date DATE NOT NULL,
  UNIQUE (job_hk, company_hk)
);

-- Satellite: Job attributes with version history
CREATE TABLE job_sat (
  job_hk BINARY(16),
  load_date DATE NOT NULL,
  load_end_date DATE,
  job_title_short VARCHAR(100),
  salary_year_avg INT,
  job_work_from_home BOOLEAN,
  job_location VARCHAR(200),
  UNIQUE (job_hk, load_date)
);

-- Query: "Get current job attributes"
SELECT h.job_id, s.job_title_short, s.salary_year_avg, s.job_location
FROM job_hub h
JOIN job_sat s ON h.job_hk = s.job_hk
WHERE s.load_end_date IS NULL;

-- Query: "What salary was posted on a specific date?"
SELECT h.job_id, s.salary_year_avg, s.load_date
FROM job_hub h
JOIN job_sat s ON h.job_hk = s.job_hk
WHERE h.job_id = '12345' AND s.load_date <= '2024-01-15'
ORDER BY s.load_date DESC LIMIT 1;
```

## Notes

- **Hash key trap:** Don't try to use hash keys (job_hk, job_company_lk) as your reporting key—they're for deduplication and lineage. Always join back to the Hub to get readable business keys like `job_id` for end users.
- **Load date discipline:** Every row's load_date must match the actual ETL run date; drift here makes audits unreliable. Use pipeline timestamps, not system clock time, to maintain consistency across runs.
- **Satellite versioning:** Use `load_end_date IS NULL` to mark current records, not `MAX(load_date)` queries—it's faster and clearer for analysts reading the schema.
- **Connects to:** Temporal tables / CDC (Change Data Capture), SCD Type 2 logic, and data lineage tracking; also pairs naturally with Kimball slowly-changing dimensions but with more rigorous separation of concerns.
- **Revisit:** Whether you need micro-batch vs. real-time Hub/Link/Satellite loads, and how to handle late-arriving facts or corrections in the audit trail without creating false "changes."
