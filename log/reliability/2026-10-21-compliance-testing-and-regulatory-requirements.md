---
date: 2026-10-21
phase: reliability
topic: Compliance testing and regulatory requirements
---

# Compliance testing and regulatory requirements

*Quality, reliability and the professional layer*

## Concept

Compliance testing validates that data pipelines meet regulatory and business requirements—not just that they work, but that they work *correctly under audit*. This spans GDPR retention windows, SOX financial accuracy, PII handling, data lineage documentation, and contractual SLAs. Without it, you inherit legal liability, failed audits, and customer trust erosion. A pipeline that passes functional tests but violates data residency rules, retains PII beyond its purpose, or lacks audit trails is a liability wearing a success badge.

The shift from "builder" to "owner" means taking responsibility for what the data *enables others to do*. You must know: who touches this data downstream, what they're legally allowed to do with it, what retention policies apply, and how to prove compliance happened. This requires moving beyond unit tests into contract testing, schema validation, and immutable audit logging.

## Practice

**Problem:** Your `job_postings_fact` table is used by the HR Analytics team to make hiring decisions. EU candidates' location data must be deleted 90 days after job posting closes (GDPR right to erasure). You need to test that:
1. Records older than 90 days have `job_location` nulled out
2. Deletion events are logged with timestamp and reason
3. No job_location data leaks to downstream schemas

```sql
-- Compliance test: GDPR retention window enforcement
WITH compliance_audit AS (
  SELECT 
    job_id,
    job_posted_date,
    CURRENT_DATE - job_posted_date AS days_since_post,
    job_location,
    CASE 
      WHEN CURRENT_DATE - job_posted_date > 90 THEN 'SHOULD_BE_NULLED'
      ELSE 'RETAIN'
    END AS compliance_status
  FROM job_postings_fact
  WHERE job_location IS NOT NULL
    AND job_posted_date < CURRENT_DATE - INTERVAL '90 days'
)
SELECT 
  COUNT(*) AS violation_count,
  ARRAY_AGG(DISTINCT job_id) AS violating_job_ids
FROM compliance_audit
WHERE compliance_status = 'SHOULD_BE_NULLED'
  AND job_location IS NOT NULL;

-- Expected result: 0 violations
-- Log every deletion for audit trail
INSERT INTO data_compliance_log (table_name, operation, affected_rows, timestamp, reason)
SELECT 'job_postings_fact', 'LOCATION_NULLIFY', COUNT(*), NOW(), 'GDPR_90DAY_RETENTION'
FROM job_postings_fact
WHERE CURRENT_DATE - job_posted_date > 90 AND job_location IS NOT NULL;
```

## Notes

- **Schema contracts matter as much as data contracts:** Document *who is allowed to see what columns* at the table level. A downstream analyst shouldn't have access to `job_location` if it's subject to retention rules.

- **Audit logging is not optional.** Every DELETE, UPDATE, or sensitive data access needs a timestamp, user, and reason. This is how you prove compliance during an audit—not by assertions, but by immutable logs.

- **Compliance testing runs *before* deployment.** Unlike functional tests that can sometimes fail in production safely, compliance violations compound. Test retention windows, PII masking, and data lineage in staging with production-like datasets.

- **Adjacent skills:** Data governance frameworks (which tables are sensitive?), data classification (PII vs. non-sensitive), lineage tracking (does this column propagate downstream?), and privacy impact assessments (what can go wrong?).

- **Revisit:** The difference between *encryption at rest* (ops concern) and *field-level encryption* (your responsibility as a pipeline owner); the relationship between SLAs and compliance (uptime vs. correctness); and how to handle conflicting requirements (e.g., "keep data for 7 years" vs. "GDPR right to erasure").
