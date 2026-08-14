---
date: 2026-08-14
phase: cloud
topic: Encryption at rest and in transit
---

# Encryption at rest and in transit

*Cloud platforms and storage*

## Concept

Encryption at rest protects data stored in databases, data lakes, and backups by converting it into unreadable form using cryptographic keys. Encryption in transit protects data moving between services—client to database, database to data warehouse, or within a replication pipeline—using TLS/SSL protocols. Without encryption, attackers with network access or storage access can read sensitive salary data, personal identifiers, or proprietary business logic directly.

In cloud platforms (AWS, GCP, Azure), encryption at rest is often enabled by default but may use shared keys or require key management configuration for compliance. Encryption in transit is nearly universal for cloud APIs but can be misconfigured in internal pipelines or custom ETL scripts. The cost is minimal CPU overhead (typically <5%), but the operational cost is significant: key rotation, key storage (KMS), audit logging, and access control become your responsibility.

Without encryption, you lose compliance certifications (SOC2, HIPAA, PCI-DSS), expose yourself to regulatory fines, and cannot detect which users or services accessed sensitive data when a breach occurs.

## Practice

**Problem:** Your job_postings_fact table contains salary_year_avg values that should never be readable by unauthorized services. A junior engineer wrote an ETL script that copies data over unencrypted HTTP to a staging bucket. You need to identify unencrypted data flows and enforce encryption.

```sql
-- Identify jobs with high salaries that may be exposed
SELECT 
  job_id,
  job_title_short,
  salary_year_avg,
  job_location
FROM job_postings_fact
WHERE salary_year_avg > 150000
  AND job_posted_date >= CURRENT_DATE - INTERVAL 30 DAY
ORDER BY salary_year_avg DESC;

-- Audit: Check which role can access salary data
-- (This query structure applies to most cloud data warehouses)
SELECT 
  grantee,
  privilege,
  table_name
FROM information_schema.role_table_grants
WHERE table_name = 'job_postings_fact'
  AND privilege IN ('SELECT', 'UPDATE')
ORDER BY grantee;
```

**Solution:** Enable column-level encryption on salary_year_avg, enforce TLS 1.3 for all data pipeline connections, and use KMS key IDs in your infrastructure-as-code to rotate keys quarterly. Restrict SELECT on salary_year_avg to specific roles and log all access.

## Notes

- **KMS vs. transparent encryption:** Cloud KMS (key management service) costs per API call; transparent encryption is often free but offers less control. Know your compliance requirement before choosing.
- **Encryption overhead is deceptive:** CPU cost is low, but key lookup latency adds up when querying billions of rows. Profile before and after enabling encryption.
- **In-transit gaps are common:** JDBC drivers, CSV uploads, and cross-region replication can silently skip TLS if not explicitly enforced; audit your ETL logs.
- **Connects to:** role-based access control (RBAC), secrets management, audit logging, and key rotation policies—encryption is just the lock; RBAC is the door.
- **Revisit:** Test decryption latency under your typical query volume; encryption that makes queries 2x slower may require caching or materialized views to remain cost-effective.
