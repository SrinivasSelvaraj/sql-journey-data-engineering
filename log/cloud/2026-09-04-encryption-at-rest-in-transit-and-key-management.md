---
date: 2026-09-04
phase: cloud
topic: Encryption: at-rest, in-transit and key management
---

# Encryption: at-rest, in-transit and key management

*Cloud platforms and storage*

## Concept

Encryption protects data at three critical points: **at-rest** (stored in databases, S3, data warehouses), **in-transit** (moving between services, over networks), and **key management** (controlling who accesses encryption keys). In cloud platforms, you pay for encryption overhead—compute for encrypt/decrypt operations, key storage, and audit logging—so understanding where encryption is mandatory versus optional affects both security posture and cost.

Without encryption at-rest, a compromised database or stolen storage drive exposes raw data. Without encryption in-transit, credentials and sensitive columns leak across network boundaries. Weak key management means attackers who breach your infrastructure can decrypt everything anyway, making the encryption theater rather than protection. This matters most for PII (salaries, locations, job seeker contact info), compliance requirements (GDPR, HIPAA), and multi-tenant cloud environments where data isolation relies on cryptography.

## Practice

**Problem:** Your job_postings_fact table contains salary_year_avg (sensitive compensation data) and job_location (PII). You're migrating to AWS and need to ensure salary data is encrypted at-rest in Redshift, transmitted securely to your BI tool, and accessible only to authorized analysts. How do you configure this and what does it cost?

```sql
-- 1. Create table with column-level encryption (AWS KMS)
CREATE TABLE job_postings_fact (
  job_id INT,
  job_title_short VARCHAR(50),
  salary_year_avg INT ENCODE RAW,  -- disable compression to encrypt
  job_work_from_home BOOLEAN,
  job_posted_date DATE,
  job_location VARCHAR(100)
)
DISTSTYLE KEY DISTKEY (job_id)
SORTKEY (job_posted_date);

-- 2. Enable cluster encryption with AWS KMS
-- (done at cluster creation; adds ~5-10% query latency, costs per key operation)
-- ALTER SYSTEM SET ssl = on;

-- 3. Create IAM role restricting data access by analyst
CREATE ROLE analyst_read_only;
GRANT SELECT ON job_postings_fact TO analyst_read_only;
-- Deny direct S3 access; route through Redshift only

-- 4. Use TLS for in-transit: require SSL connections from BI tool
-- In connection string: sslmode=require

-- 5. Audit key access
-- CloudTrail logs all KMS decrypt calls (costs per log entry)
-- Query: identify who decrypted salary data and when
SELECT eventtime, useragent, requestparameters 
FROM cloudtrail_logs 
WHERE eventname = 'Decrypt' AND resources LIKE '%salary%';
```

## Notes

- **Column-level vs. cluster-level encryption**: Column encryption (encrypting only salary_year_avg) is more granular but slower; cluster encryption is transparent but encrypts everything, including metadata. Choose based on sensitivity and performance budget.
- **KMS costs scale with key operations**: Each encrypt/decrypt call incurs a fee ($0.03 per 10K requests on AWS); high-throughput queries against encrypted columns become expensive. Monitor CloudWatch metrics for unexpected encrypt/decrypt spikes.
- **In-transit encryption adds latency but is non-negotiable**: TLS handshakes and cipher operations cost ~2-5% throughput. Tools like DBeaver and Tableau support `sslmode=require` natively; ensure your ETL scripts enforce it too (`psycopg2` requires explicit `sslmode` parameter).
- **Key rotation and access revocation**: Encrypted data is only as secure as key access. Implement key rotation policies (AWS recommends annual); when an analyst leaves, revoking their IAM role doesn't retroactively hide data they already decrypted—assume compromise.
- **Adjacent topics**: Token expiration (temporary credentials with TTL), row-level security (RLS) for finer-grained access control, and tokenization (replacing salary values with proxies) as alternatives to full encryption for analytics.
