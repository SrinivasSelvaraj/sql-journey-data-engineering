---
date: 2026-09-04
phase: cloud
topic: Compliance: SOC2, HIPAA, GDPR requirements and auditing
---

# Compliance: SOC2, HIPAA, GDPR requirements and auditing

*Cloud platforms and storage*

## Concept

Compliance frameworks (SOC2, HIPAA, GDPR) establish security, privacy, and audit requirements that directly impact how you design data pipelines and infrastructure. SOC2 requires documented access controls and change tracking; HIPAA mandates encryption and audit logs for healthcare data; GDPR requires data minimization, retention policies, and the ability to delete personal data on request. Without compliance-aware design, you face legal liability, failed vendor audits, customer churn, and inability to operate in regulated industries.

In cloud environments, compliance breaks down when: (1) PII is logged in plaintext query results or CloudWatch; (2) data retention policies aren't enforced and old records persist indefinitely; (3) access audit trails are incomplete or logs are deleted; (4) third-party tools query production data without encryption in transit. Compliance isn't just security—it's about proving you *know* what data you have, who accessed it, when, and why.

## Practice

**Problem:** Your analytics team runs frequent salary queries on `job_postings_fact` for reporting. However, salary data is sensitive in some jurisdictions. You need to: (1) log all access to salary columns, (2) prevent salary export to non-production environments, (3) ensure queries are encrypted, and (4) retain audit records for 2 years.

```sql
-- Create audit-logged view masking salary in non-prod
CREATE VIEW job_postings_audit AS
SELECT 
  job_id,
  job_title_short,
  CASE 
    WHEN current_setting('app.environment') = 'prod' 
      THEN salary_year_avg 
    ELSE NULL 
  END AS salary_year_avg,
  job_work_from_home,
  job_posted_date,
  job_location
FROM job_postings_fact;

-- Log access via trigger (PostgreSQL example)
CREATE TABLE audit_log (
  audit_id BIGSERIAL PRIMARY KEY,
  table_name TEXT,
  query_text TEXT,
  user_name TEXT,
  accessed_at TIMESTAMP DEFAULT NOW(),
  environment TEXT
);

CREATE OR REPLACE FUNCTION audit_salary_access()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.salary_year_avg IS NOT NULL THEN
    INSERT INTO audit_log (table_name, query_text, user_name, environment)
    VALUES ('job_postings_fact', current_query(), current_user, current_setting('app.environment'));
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Query with audit context
SET app.environment = 'prod';
SELECT * FROM job_postings_audit WHERE job_location = 'New York';
```

## Notes

- **Audit log inflation:** Logging every query creates massive storage costs. Sample high-risk queries (salary, PII) rather than logging everything; filter by user role and environment.
- **Encryption scope confusion:** Encryption *at rest* (S3 SSE) ≠ encryption *in transit* (TLS). Compliance requires both; GDPR auditors check both. Know what your cloud provider encrypts by default.
- **Data retention vs. GDPR right-to-delete:** Setting a 2-year retention policy doesn't satisfy GDPR if you can't physically delete rows on request. Design with soft-delete columns and partition by date for efficient purging.
- **Adjacent topics:** Query performance logging (slow query logs leak sensitive data—scrub them); data lineage (tracking where PII flows); role-based access control (RBAC) in warehouses; cost allocation (compliance features cost money—audit logging, encryption, replication).
- **Revisit:** Check your cloud provider's latest compliance report annually (SOC2 Type II, FedRAMP, etc.). Compliance frameworks evolve; what was sufficient last year may not be this year.
