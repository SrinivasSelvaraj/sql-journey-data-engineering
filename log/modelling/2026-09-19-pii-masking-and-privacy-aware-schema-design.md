---
date: 2026-09-19
phase: modelling
topic: PII masking and privacy-aware schema design
---

# PII masking and privacy-aware schema design

*Data modelling and warehousing*

## Concept

PII (Personally Identifiable Information) masking removes or obfuscates sensitive data at the schema design stage so analysts can safely query without exposing individuals' private details. This matters because unmasked PII creates compliance risk (GDPR, CCPA), enables data breaches, and limits who can access tables—forcing bottlenecks where only trusted engineers can run queries. Without masking, a job_postings table might retain applicant names, email addresses, or phone numbers; querying salary trends becomes impossible without granting access to sensitive rows.

Privacy-aware schema design prevents PII exposure by deciding *at modeling time* what information stays, what gets hashed, and what gets dropped entirely. This is harder than it sounds: job location might seem safe, but combined with job title and date, it can re-identify a person. The goal is to make tables "self-service"—analysts can explore freely without needing approval from security, and you avoid the embarrassment of discovering PII in production after it's already public.

## Practice

**Problem:** Your job_postings_fact table is queried by a self-service analytics team. The raw data includes applicant_email and applicant_phone, but these should never appear in the warehouse. Additionally, you want to prevent analysts from identifying individuals by cross-referencing job_title with job_location and job_posted_date.

**Solution:**

```sql
CREATE TABLE job_postings_fact (
  job_id INT PRIMARY KEY,
  job_title_short VARCHAR(50),  -- generalized category, not exact title
  salary_year_avg DECIMAL(10, 2),
  job_work_from_home BOOLEAN,
  job_posted_date DATE,
  job_location_region VARCHAR(50),  -- region only, not city
  -- applicant_email dropped entirely
  -- applicant_phone dropped entirely
  applicant_id_hashed CHAR(64)  -- SHA-256 hash for internal joins only
);

-- If exact job_title is needed downstream, store in separate access-controlled table
CREATE TABLE job_postings_sensitive (
  job_id INT PRIMARY KEY,
  job_title_exact VARCHAR(255),
  applicant_email_hashed CHAR(64),
  applicant_phone_hashed CHAR(64),
  -- Restricted: grant access only to privacy/HR team
);
```

## Notes

- **Generalization vs. hashing:** Hashing (applicant_id_hashed) preserves uniqueness for joins but prevents reverse-lookup; generalization (region instead of city) reduces risk but loses granularity. Use hashing for IDs, generalization for attributes.
- **Re-identification risk:** Even "anonymized" data can leak identity if you leave quasi-identifiers like exact job_title + location + date. Model defensively—assume someone outside your org has a side dataset.
- **Schema documentation:** Add a `_pii_level` metadata column or data dictionary noting which fields are masked and why. Helps future teammates understand design intent.
- **Connects to:** role-based access control (RBAC), data lineage tracking, and encryption-at-rest. Masking is part of a broader defense-in-depth strategy.
- **Revisit:** When business asks for "more detail"—e.g., exact city instead of region—push back with a re-identification impact assessment, not a reflex "yes."
