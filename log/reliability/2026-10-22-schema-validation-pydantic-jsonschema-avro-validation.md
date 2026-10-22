---
date: 2026-10-22
phase: reliability
topic: Schema validation: pydantic, jsonschema, avro validation
---

# Schema validation: pydantic, jsonschema, avro validation

*Quality, reliability and the professional layer*

## Concept

Schema validation is the automated enforcement of data structure, type, and constraint rules at ingestion, transformation, or output points. Without it, invalid data silently corrupts downstream analytics, trains bad ML models, and creates debugging nightmares three layers deep in your pipeline. Pydantic (Python objects), jsonschema (JSON documents), and Avro (serialized records) each solve this differently: Pydantic is best for application-layer validation before data enters the pipeline; jsonschema works for semi-structured APIs and logs; Avro embeds the schema with the data itself, making it portable and versioned.

The critical moment is *choice of enforcement point*. Validating at ingestion catches garbage before it lands in your warehouse—cheap and fast. Validating at transformation means you're already paying to move bad data. Validating output before it reaches stakeholders is too late; trust is already broken. Without schema validation, you'll spend 30% of incident response time just confirming "yes, the data really is that corrupted" instead of fixing the root cause.

## Practice

**Problem:** Your `job_postings_fact` table receives data from three sources with inconsistent formats. Some send `salary_year_avg` as a string ("120000"), some as null when missing, some as 0. `job_posted_date` arrives as timestamps, dates, and unparseable strings. `job_work_from_home` is sometimes 1/0, sometimes true/false, sometimes 'yes'/'no'. You need to reject invalid records and log why.

```sql
CREATE TABLE job_postings_fact (
  job_id INT PRIMARY KEY,
  job_title_short VARCHAR(100) NOT NULL,
  salary_year_avg DECIMAL(10,2) NOT NULL CHECK (salary_year_avg > 0),
  job_work_from_home BOOLEAN NOT NULL,
  job_posted_date DATE NOT NULL CHECK (job_posted_date <= CURRENT_DATE),
  job_location VARCHAR(255) NOT NULL
);

CREATE TABLE job_postings_staging_invalid (
  job_id INT,
  raw_payload JSONB,
  validation_error VARCHAR(500),
  ingested_at TIMESTAMP DEFAULT NOW()
);

-- Validation logic (pseudo-code for a dbt model or stored procedure)
-- INSERT INTO job_postings_fact
-- SELECT 
--   job_id,
--   TRIM(job_title_short),
--   salary_year_avg::DECIMAL,
--   CASE WHEN job_work_from_home IN ('true', '1', 'yes') THEN TRUE ELSE FALSE END,
--   job_posted_date::DATE,
--   job_location
-- FROM staging
-- WHERE salary_year_avg::DECIMAL > 0
--   AND job_posted_date::DATE IS NOT NULL
--   AND job_title_short IS NOT NULL;

-- ON CONSTRAINT VIOLATION, INSERT INTO job_postings_staging_invalid
-- to preserve the rejected record and error message for audit.
```

## Notes

- **Pydantic over raw parsing**: Define a `JobPosting` model with field validators; reject at the Python entry point before any database touch. This is non-negotiable for APIs and event streams.
- **Schema versioning is invisible until it isn't**: Avro solves this by evolving schemas with compatibility rules. If you use Avro, you can add optional fields without breaking old consumers. Without it, one careless change breaks all downstream code.
- **Validation ≠ transformation**: A schema validator says "is this valid?" A transformer says "make this valid." Don't conflate them. Validate first; if invalid, either reject or transform in a separate, auditable step.
- **Alert on validation failures, not just on counts**: A pipeline that silently drops 5% of records daily will kill your credibility. Log every validation failure with its cause and source; set alerts when failure rate spikes.
- **Connects to**: data lineage (track which records failed and why), contract testing (schemas as SLAs between teams), and idempotency (validation ensures re-runs produce identical results).
