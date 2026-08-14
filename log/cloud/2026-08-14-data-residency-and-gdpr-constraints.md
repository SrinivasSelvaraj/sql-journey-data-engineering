---
date: 2026-08-14
phase: cloud
topic: Data residency and GDPR constraints
---

# Data residency and GDPR constraints

*Cloud platforms and storage*

## Concept

Data residency requirements mandate that certain data must be stored and processed within specific geographic regions. GDPR (General Data Protection Regulation) enforces this for EU personal data: you cannot store or process EU resident information outside the EU without explicit legal mechanisms like Standard Contractual Clauses or adequacy decisions. This becomes critical when your cloud infrastructure spans multiple regions—a query that joins EU customer data with US analytics servers violates GDPR unless architecturally separated.

The cost and performance implications are real. Cross-region data movement incurs egress charges (often $0.02–$0.12 per GB) and adds latency. More importantly, queries that unknowingly transfer personal data across borders can trigger compliance violations and fines up to €20 million or 4% of global revenue. Without explicit residency controls, a "simple" analytics join becomes a legal liability when traced through audit logs showing data leaving its allowed region.

## Practice

**Problem:** Your `job_postings_fact` table contains job location and applicant email addresses (personal data). EU jobs are being processed in a US-region data warehouse, and a reporting query joins this with anonymized salary data. How do you ensure EU job data stays in the EU region?

```sql
-- SOLUTION: Use view/table partitioning with region-aware access control

-- 1. Create region-partitioned tables
CREATE TABLE job_postings_eu (
  job_id INT,
  job_title_short VARCHAR,
  salary_year_avg INT,
  job_work_from_home BOOLEAN,
  job_posted_date DATE,
  job_location VARCHAR,
  region_residency VARCHAR DEFAULT 'EU'
) PARTITION BY LIST (region_residency)
STORED AS PARQUET
LOCATION 's3://eu-only-bucket/job_postings_eu/'
WITH (external_location = 's3://eu-bucket/');

CREATE TABLE job_postings_us (
  job_id INT,
  job_title_short VARCHAR,
  salary_year_avg INT,
  job_work_from_home BOOLEAN,
  job_posted_date DATE,
  job_location VARCHAR,
  region_residency VARCHAR DEFAULT 'US'
)
LOCATION 's3://us-bucket/job_postings_us/';

-- 2. Query only the residency-appropriate table
SELECT job_title_short, AVG(salary_year_avg) as avg_salary
FROM job_postings_eu  -- explicitly EU region
WHERE job_posted_date >= CURRENT_DATE - INTERVAL 30 DAY
GROUP BY job_title_short;

-- 3. Enforce via row-level security (Snowflake example)
CREATE ROW ACCESS POLICY region_policy ON job_postings_fact AS
  (region_residency VARCHAR) RETURNS BOOLEAN ->
    CASE 
      WHEN CURRENT_ROLE() = 'ANALYST_EU' THEN region_residency = 'EU'
      WHEN CURRENT_ROLE() = 'ANALYST_US' THEN region_residency = 'US'
      ELSE FALSE
    END;
```

## Notes

- **Egress costs compound silently:** A daily 50GB cross-region transfer costs ~$1.50/day or $550/year per job—multiply by 100 jobs and budget overruns go unnoticed until month-end.
- **GDPR scope creeps:** Any identifier (email, IP, job applicant ID, hiring manager name) counts as personal data. Anonymization must be irreversible; hashing salary + location often re-identifies through cross-reference.
- **"It's stored in EU but processed in US" is still a violation:** The moment data leaves the EU region for computation, you've transferred it. Plan architecture around compute locality, not just storage.
- **Audit trails matter more than tech:** Most fines come from undocumented data flows. Ensure query logs show which region queries touched; use `information_schema.query_history` or Cloudtrail religiously.
- **Related: data classification, PII tagging, cross-border data transfer agreements**—these form the policy layer that tech controls enforce.
