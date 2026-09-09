---
date: 2026-09-09
phase: reliability
topic: Regulatory compliance for data engineers: SOC2, HIPAA, GDPR
---

# Regulatory compliance for data engineers: SOC2, HIPAA, GDPR

*Quality, reliability and the professional layer*

## Concept

Regulatory compliance frameworks (SOC2, HIPAA, GDPR) define who can access data, how it moves, where it's stored, and how long it's kept. As a data engineer, you're not the compliance officer—but you're the person who *enforces* compliance through architecture and controls. SOC2 covers system security and availability for service providers; HIPAA protects health information with encryption and audit trails; GDPR gives individuals rights to access, correct, and delete their personal data.

Without compliance built into your pipelines, you create liability. A data warehouse query that leaks PII in logs, a backup that persists deleted records, or a pipeline that doesn't encrypt salary data in transit—these aren't just engineering failures, they're legal failures. Compliance moves from "someone else's problem" to your responsibility the moment you own a production system.

The difference between junior and senior data engineers often comes down to this: juniors build pipelines that work; trusted engineers build pipelines that work *and can be audited*. That means logging who accessed what, when; ensuring deletions actually cascade; encrypting sensitive columns; and designing schemas that respect data residency rules.

## Practice

**Problem:** Your `job_postings_fact` table contains salary and location data. GDPR compliance requires that if a user requests deletion of their data, you remove all traces. However, your downstream analytics tables and backups still hold copies. How do you design a deletion pipeline that respects this requirement?

```sql
-- Add audit columns to track compliance
ALTER TABLE job_postings_fact ADD COLUMN 
  (created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
   deleted_at TIMESTAMP NULL,
   data_subject_id VARCHAR(255) NULL);  -- Maps to GDPR subject

-- Soft delete for audit trail (not purge)
UPDATE job_postings_fact 
SET deleted_at = CURRENT_TIMESTAMP 
WHERE job_id IN (SELECT job_id FROM deletion_requests WHERE processed = FALSE);

-- Ensure downstream views respect deletion
CREATE OR REPLACE VIEW job_postings_active AS
SELECT * FROM job_postings_fact 
WHERE deleted_at IS NULL;

-- Purge after retention period (e.g., 90 days for backups)
DELETE FROM job_postings_fact 
WHERE deleted_at < CURRENT_TIMESTAMP - INTERVAL 90 DAY
  AND job_id NOT IN (SELECT job_id FROM legal_hold);

-- Log the deletion for audit
INSERT INTO compliance_audit_log (table_name, action, affected_rows, timestamp)
SELECT 'job_postings_fact', 'GDPR_DELETION', COUNT(*), CURRENT_TIMESTAMP
FROM job_postings_fact WHERE deleted_at = CURRENT_TIMESTAMP;
```

## Notes

- **Mistake:** Conflating "encrypted at rest" with "compliance." Encryption is necessary but not sufficient—you also need key rotation, access controls, and audit logging.
- **Mistake:** Thinking deletion means `DELETE`. GDPR deletions require purging from backups and replicas within a defined window; soft deletes alone don't satisfy the requirement.
- **Connects to:** Data governance (lineage, PII tagging), infrastructure as code (audit controls must version-controlled), and observability (audit logs are data too—they need monitoring).
- **Worth revisiting:** Your organization's data retention policy. Compliance frameworks *allow* you to keep data; your policy defines *how long*. Align with legal before you build.
- **Worth revisiting:** The difference between user consent (GDPR) and regulatory mandate (HIPAA). Design your logging differently for each.
