---
date: 2026-09-30
phase: reliability
topic: PII detection and masking in test data
---

# PII detection and masking in test data

*Quality, reliability and the professional layer*

## Concept

PII (Personally Identifiable Information) detection and masking is the process of identifying sensitive data fields in datasets and obscuring them so they cannot be traced back to individuals. In data engineering, this sits at the intersection of compliance (GDPR, CCPA, HIPAA), security, and operational responsibility. When test data escapes into non-production environments—logs, analytics sandboxes, developer laptops—unmasked PII becomes a legal and reputational liability.

The distinction between "someone who builds pipelines" and someone trusted to own them often comes down to whether PII leaks. A junior engineer might build a working ETL pipeline; an owner ensures it never exposes customer email, phone, address, or behavioral patterns in places it shouldn't. Without masking, a single misconfigured S3 bucket or a developer debugging a production query can become a data breach incident.

Detection requires both rule-based patterns (regex for emails and phone numbers) and semantic understanding (job_location might contain city names that identify someone). Masking strategies range from hashing (irreversible but deterministic), tokenization (reversible with a key), truncation, or synthetic replacement. The choice depends on whether downstream consumers need to join on the original value or just need data that "looks real."

## Practice

**Problem:** The `job_postings_fact` table includes `job_location` which often contains specific cities or remote work indicators tied to individuals posting jobs. Additionally, salary ranges combined with location can re-identify applicants. You need to create a test dataset that removes direct identifiers while preserving analytical utility.

```sql
CREATE TABLE job_postings_fact_masked AS
SELECT
  job_id,
  job_title_short,
  CASE 
    WHEN salary_year_avg IS NOT NULL 
    THEN ROUND(salary_year_avg / 10000) * 10000  -- bucket to nearest 10k
    ELSE NULL 
  END AS salary_year_avg,
  job_work_from_home,
  job_posted_date,
  CASE 
    WHEN job_location = 'Anywhere' THEN 'Remote'
    WHEN job_location IS NOT NULL THEN 
      CONCAT(SPLIT_PART(job_location, ',', 2), ' (masked)')  -- keep state/country only
    ELSE 'Unknown'
  END AS job_location
FROM job_postings_fact
WHERE job_posted_date >= CURRENT_DATE - INTERVAL '90 days';
```

This masks by: (1) bucketing salary to reduce re-identification risk, (2) removing city names from location, (3) preserving geographic trend analysis. Add row-level access controls in your warehouse so only authorized roles can see the unmasked version.

## Notes

- **Mistake: Over-masking.** Hashing everything renders data useless for legitimate analysis. Mask strategically—salary ranges are fine; exact salary + exact address + exact hire date is not.
- **Mistake: Static masking rules.** PII patterns evolve (new name formats, phone structures). Embed detection logic in a reusable function or library rather than hardcoding regex in each pipeline.
- **Audit trail.** Log which fields were masked, when, and by whom. If a breach occurs, you need to prove you followed protocol. This connects to data lineage and observability.
- **Adjacent topics:** data contracts (which fields are PII), column-level encryption at rest, differential privacy for aggregate queries, and tag-based access control (marking columns as sensitive at the metadata layer).
- **Revisit when:** adding new source systems, updating compliance frameworks, or designing data products for external sharing. PII scope creeps; make masking a standard checkpoint in your data review process.
