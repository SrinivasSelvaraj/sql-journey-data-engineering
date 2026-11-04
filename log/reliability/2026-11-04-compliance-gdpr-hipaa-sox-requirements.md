---
date: 2026-11-04
phase: reliability
topic: Compliance: GDPR, HIPAA, SOX requirements
---

# Compliance: GDPR, HIPAA, SOX requirements

*Quality, reliability and the professional layer*

## Concept

Compliance frameworks—GDPR, HIPAA, SOX—aren't optional add-ons; they're constraints baked into how data flows through your system. GDPR enforces the right to erasure and data minimization (collect only what's necessary). HIPAA requires encryption, audit logs, and role-based access for health data. SOX mandates immutable audit trails and segregation of duties for financial systems. Without these, organizations face fines (GDPR: up to €20M or 4% of revenue), legal liability, and loss of customer trust.

The difference between a pipeline builder and a data owner is accountability. A builder asks "does this work?" A steward asks "who can see this, what proof do we have of access, and can we delete it on request?" This means implementing field-level masking, logging every read/write operation, designing for data retention windows, and ensuring schemas document which columns contain regulated data. A compliance failure often isn't technical—it's architectural: the system was never designed to answer "who accessed this PII and when?"

In practice, compliance touches every layer: data collection (consent), storage (encryption, segregation), pipeline logic (transformation audit trails), access (role-based controls), and decommissioning (guaranteed deletion). Skipping this during "MVP" creates technical debt that becomes impossible to retrofit.

## Practice

**Problem:** You have a `job_postings_fact` table that includes `job_location`, which may contain user location data that could be considered personal under GDPR in certain contexts. You need to:
- Mask locations for non-authorized roles
- Log all access to the full location field
- Ensure deletions are propagated if a user requests erasure

**Solution:**

```sql
-- Create masked view for public access
CREATE VIEW job_postings_public AS
SELECT 
  job_id,
  job_title_short,
  salary_year_avg,
  job_work_from_home,
  job_posted_date,
  CASE 
    WHEN current_user_id IN (SELECT user_id FROM authorized_roles WHERE role = 'data_analyst') 
    THEN job_location 
    ELSE CONCAT(SPLIT_PART(job_location, ',', 2), ', ', SPLIT_PART(job_location, ',', 3))
  END AS job_location
FROM job_postings_fact;

-- Create audit log trigger
CREATE TABLE job_access_audit (
  audit_id SERIAL PRIMARY KEY,
  user_id VARCHAR,
  table_name VARCHAR,
  accessed_columns TEXT,
  access_time TIMESTAMP DEFAULT NOW(),
  query_hash VARCHAR
);

-- Log access on SELECT
CREATE TRIGGER log_job_location_access
AFTER SELECT ON job_postings_fact
FOR EACH ROW
EXECUTE FUNCTION log_audit_event('job_location');

-- Support right to erasure with cascade
CREATE PROCEDURE erase_user_data(p_user_identifier VARCHAR) AS $$
BEGIN
  DELETE FROM job_postings_fact 
  WHERE job_location ILIKE CONCAT('%', p_user_identifier, '%');
  
  INSERT INTO data_deletion_log (user_identifier, table_name, row_count, deletion_timestamp)
  VALUES (p_user_identifier, 'job_postings_fact', ROW_COUNT(), NOW());
END;
$$ LANGUAGE plpgsql;
```

## Notes

- **Compliance ≠ security alone.** GDPR is about *governance* (who can access, what can be kept, audit proof). Security stops breaches; compliance proves you operated within the law regardless.
- **Retention windows are non-negotiable.** If you can't articulate why data lives for 7 years vs. 3 months, you're already out of compliance. Schema and jobs should encode TTL as a first-class concept.
- **Audit logs must be immutable.** Write them to append-only tables or external services (Kafka topics, cloud logging). If your audit log can be edited or deleted, you have no audit trail.
- **Data minimization beats masking.** It's better to never collect a field than to mask it downstream. Smaller blast radius, simpler pipelines, less legal exposure.
- **Connects to:** data lineage (GDPR requires tracking transformations), encryption at rest/transit, role-based access control (RBAC), data contracts, and incident response procedures.
