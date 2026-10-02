---
date: 2026-10-02
phase: reliability
topic: Data contracts and schema registry enforcement
---

# Data contracts and schema registry enforcement

*Quality, reliability and the professional layer*

## Concept

A data contract is a formal agreement between a data producer and consumer that specifies schema, SLAs, and breaking change policies. A schema registry (like Confluent or AWS Glue) enforces this contract by validating data shape, type, and required fields before it enters downstream systems. Without contracts, schema drift silently breaks analytics pipelines: a nullable field becomes non-nullable, an integer becomes a string, a column vanishes. The cost isn't caught until 48 hours later when a dashboard fails and you're reverse-engineering what changed in the source system.

Contracts matter most when you own data at scale—when multiple teams consume your pipeline and you can't afford to wake up to Slack messages about broken ETLs. They shift accountability from "I hope nobody breaks this" to "I promised nobody would break this." This is the professional layer: you're not just writing SQL that works today; you're designing systems that work reliably while teams evolve the source data independently.

Without schema registry enforcement, breaking changes propagate downstream undetected. With it, you fail fast at ingestion, alert the producer, and enforce backward compatibility rules: new columns must be optional, deletions require deprecation periods, type widening (int → bigint) is safer than narrowing (string → int). This transforms data pipelines from fragile to owned.

## Practice

**Problem:** Your analytics team consumes `job_postings_fact` daily. The source system owner adds a new non-nullable column `job_salary_currency` and removes `job_work_from_home`. Your downstream dbt models and BI tools break silently because the schema changed without warning.

**Solution:** Define a schema contract and enforce it at ingestion:

```sql
-- Define the contract as version 1.0
-- Enforce backward compatibility: no breaking changes without deprecation

CREATE TABLE job_postings_fact (
    job_id BIGINT NOT NULL,
    job_title_short VARCHAR NOT NULL,
    salary_year_avg DECIMAL(10,2),
    job_work_from_home BOOLEAN,  -- Mark as deprecated, will remove in v2.0 (2025-06-01)
    job_posted_date DATE NOT NULL,
    job_location VARCHAR NOT NULL,
    -- New fields must be optional (nullable)
    job_salary_currency VARCHAR DEFAULT 'USD'  -- Added in v1.1, optional
) WITH (
    'schema.registry.subject.name.strategy' = 'TopicNameStrategy',
    'value.schema.id' = 'job_postings_fact-value'
);

-- At ingestion: validate incoming data matches contract
-- Reject records missing required fields or with unexpected types
-- Log schema violations and alert the producer team
SELECT
    job_id,
    job_title_short,
    salary_year_avg,
    job_work_from_home,
    job_posted_date,
    job_location,
    COALESCE(job_salary_currency, 'USD') AS job_salary_currency
FROM raw.job_postings_staging
WHERE _schema_version = 'job_postings_fact-v1.0'
  AND _validation_status = 'PASSED';  -- Reject if schema doesn't match
```

## Notes

- **Common mistake:** Treating contracts as documentation only; they must be *enforced* by tooling, not just written in a spreadsheet. Unenforced contracts are just wishes.
- **Backward compatibility matters:** Allow new optional columns and type widening (int → bigint), but never require existing columns or narrow types without a deprecation window. This is how production systems stay reliable while evolving.
- **Adjacent topic:** This connects directly to data observability—schema validation is part of data quality monitoring. Together they catch drift early and reduce incident response time from hours to minutes.
- **Revisit:** Version your contracts and document deprecation timelines explicitly. When you remove `job_work_from_home` in v2.0, downstream teams need 6+ weeks notice, not surprise failures.
- **Professional ownership:** A schema registry with enforcement is table stakes for any data platform serving more than one team. It's the difference between "we have data pipelines" and "we have a reliable data product."
