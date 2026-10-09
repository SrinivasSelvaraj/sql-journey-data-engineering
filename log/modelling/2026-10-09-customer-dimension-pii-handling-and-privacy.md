---
date: 2026-10-09
phase: modelling
topic: Customer dimension: PII handling and privacy
---

# Customer dimension: PII handling and privacy

*Data modelling and warehousing*

## Concept

A customer dimension requires deliberate PII (Personally Identifiable Information) handling to balance analytical utility with privacy compliance. You must decide upfront which personal attributes (email, phone, full name, address, SSN) live in the warehouse, which are hashed or tokenized, and which stay in a separate secure vault. Without this design, downstream users either ask you repeatedly what's safe to query, or worse, accidentally expose sensitive data in reports or exports.

The tension is real: you want analysts to segment customers by geography and contact frequency, but storing full addresses and phone numbers creates liability under GDPR, CCPA, and your own data governance policy. A well-modeled customer dimension declares this boundary explicitly—through column naming, documentation, and access controls—so a junior analyst doesn't need to ask "can I put customer_email in a dashboard?"

Without PII strategy, you end up with schema drift: some systems store full names, others use hashes; some tables retain emails indefinitely, others purge them. This inconsistency breaks reproducibility and invites compliance violations.

## Practice

**Problem:** You're building a `job_applicant_fact` table that joins `job_postings_fact` to a customer dimension. Analysts need to identify which customers apply for which roles (for conversion funnels), but you also need to ensure customer email and phone are never exposed in standard queries. Design a customer dimension schema that allows location-based and job-title-based segmentation without leaking contact details.

```sql
-- customer_dimension: PII-aware design
CREATE TABLE customer_dim (
    customer_id INT PRIMARY KEY,
    customer_name_masked VARCHAR(100),  -- "Cust_12345" or similar
    customer_email_hash VARCHAR(64),    -- SHA256 hash for dedup, not readable
    customer_phone_hash VARCHAR(64),    -- hashed; contact_team owns real number
    country_code CHAR(2),               -- geography safe for queries
    state_province_code CHAR(2),        -- coarse location
    job_search_intent_category VARCHAR(50),  -- "early_career", "senior", etc.
    account_created_date DATE,
    dbt_updated_at TIMESTAMP,
    _pii_restricted BOOLEAN DEFAULT TRUE  -- flag for access control
);

-- job_applicant_fact: joins dim without exposing PII
CREATE TABLE job_applicant_fact (
    applicant_event_id BIGINT PRIMARY KEY,
    job_id INT,
    customer_id INT,
    application_date DATE,
    application_status VARCHAR(20),
    FOREIGN KEY (job_id) REFERENCES job_postings_fact(job_id),
    FOREIGN KEY (customer_id) REFERENCES customer_dim(customer_id)
);

-- Safe analyst query: geography + role conversion
SELECT 
    j.job_title_short,
    c.country_code,
    COUNT(DISTINCT c.customer_id) AS applicant_count
FROM job_applicant_fact a
JOIN customer_dim c ON a.customer_id = c.customer_id
JOIN job_postings_fact j ON a.job_id = j.job_id
WHERE c._pii_restricted = TRUE  -- enforced in row-level security
  AND j.job_posted_date >= CURRENT_DATE - INTERVAL '90 days'
GROUP BY j.job_title_short, c.country_code;
```

## Notes

- **Naming signals intent:** Columns ending `_hash` or `_masked` tell readers "this is not the raw value." Avoid ambiguity like `email` (is it hashed?). Use `email_hash` or keep real email out of the warehouse entirely.
- **Hashing ≠ encryption:** SHA256 is one-way and fast for deduplication but offers no privacy if someone has the original value. Consider tokenization (reversible by a vault service) or encryption for values analysts might need to unmask through proper channels.
- **Connects to:** data governance frameworks (which columns need access approval?), row-level security policies (who can see which customer segments?), and data retention schedules (how long do hashed emails live in the warehouse?).
- **Common mistake:** Storing "anonymized" customer_id alongside all demographic details. A determined person can re-identify. Use truly coarse attributes (country, job intent) or keep high-cardinality details (exact hire date, salary history) separate.
- **Revisit when:** regulations change (new CCPA amendments, GDPR updates), your company enters new markets, or analytics requests push for finer customer segmentation—all trigger a PII boundary review.
