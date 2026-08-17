---
date: 2026-08-17
phase: reliability
topic: PII handling, masking and tokenisation
---

# PII handling, masking and tokenisation

*Quality, reliability and the professional layer*

## Concept

PII (Personally Identifiable Information) handling is the discipline of identifying, protecting, and transforming data that could expose individuals. In data pipelines, this includes names, emails, phone numbers, addresses, IPs, and quasi-identifiers like precise job location + salary that can re-identify someone. Without it, you expose the business to compliance violations (GDPR, CCPA), erode user trust, and create liability that sinks data teams.

Masking replaces sensitive values with fixed obfuscation (e.g., `****@****.com`), useful for development and debugging where you need *shape* but not truth. Tokenization generates deterministic or random tokens that map back to originals via a secure lookup table, used when you need to join on anonymized IDs without exposing the real ones. The choice depends on use case: masking for human-readable logs, tokenization for analytics and long-term storage where reversibility matters operationally.

The difference between a pipeline builder and a trusted owner is recognizing PII *before* it enters your warehouse, not after. This means schema review, data classification at ingestion, and treating PII handling as infrastructure—not an afterthought or compliance checkbox.

## Practice

**Problem:** Your `job_postings_fact` table includes `job_location` (e.g., "San Francisco, CA"), which combined with salary can narrow down or identify individuals in small markets. You need to tokenize location for analytics while preserving join capability and keeping the original in a separate, access-controlled table.

```sql
-- Create a secure reference table (restricted access, encrypted storage)
CREATE TABLE job_location_tokens (
    location_id SERIAL PRIMARY KEY,
    original_location VARCHAR(255) NOT NULL UNIQUE,
    location_token VARCHAR(32) NOT NULL UNIQUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Insert or get token (idempotent, deterministic)
INSERT INTO job_location_tokens (original_location, location_token)
VALUES ('San Francisco, CA', MD5('San Francisco, CA' || 'secret_salt'))
ON CONFLICT (original_location) DO NOTHING;

-- Create anonymized view for analytics team
CREATE VIEW job_postings_analytics AS
SELECT 
    job_id,
    job_title_short,
    salary_year_avg,
    job_work_from_home,
    job_posted_date,
    t.location_token AS job_location  -- Token, not original
FROM job_postings_fact f
LEFT JOIN job_location_tokens t ON f.job_location = t.original_location;

-- Original table remains restricted; only analytics view is shared
GRANT SELECT ON job_postings_analytics TO analytics_role;
REVOKE SELECT ON job_postings_fact FROM analytics_role;
```

## Notes

- **Don't tokenize without a reversible mapping.** Hashing (MD5, SHA) is one-way; if you need to recover the original later (e.g., for customer support), use a proper token store with encryption, not a hash.
- **Quasi-identifiers are often overlooked.** Salary + job level + location + date can re-identify someone even without a name. Always ask: can this combination expose someone?
- **Tokenization ties to data lineage and access control.** The lookup table becomes a critical asset; audit who accesses it, version it, and treat it as a separate security boundary from analytics tables.
- **Masking is for ephemeral use (logs, dev copies); tokenization is for production analytics.** Mixing them leads to accidental exposure when someone unmasks "for debugging."
- **This connects to schema governance and data classification.** Before building, work with legal/privacy to tag columns at source. Let infrastructure enforce policy downstream, not humans remembering to mask.
