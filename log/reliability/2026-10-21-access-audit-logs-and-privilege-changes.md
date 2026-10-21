---
date: 2026-10-21
phase: reliability
topic: Access audit logs and privilege changes
---

# Access audit logs and privilege changes

*Quality, reliability and the professional layer*

## Concept

Audit logs and privilege change tracking form the accountability backbone of data systems. They record who accessed what data, when, and what permissions changed—creating an immutable record of system behavior. Without this layer, you cannot answer critical questions during incidents: Did someone modify production data? When did access permissions shift? Which service account performed this transformation?

In the quality and reliability phase, audit logging separates hobbyist pipelines from production systems. A pipeline that silently transforms data without traceability is a liability. When a dashboard shows incorrect numbers or a regulatory audit demands proof of data lineage, audit logs become your only defense. They enable root-cause analysis, compliance reporting, and detection of unauthorized changes before they cascade into downstream failures.

Most data engineers skip this until forced. The cost is steep: undetected permission escalations, inability to reconstruct who deleted what, compliance violations, and loss of stakeholder trust. The fix becomes exponentially harder retroactively.

## Practice

**Problem:** You need to track which analysts accessed the `job_postings_fact` table and when salary data was modified. Additionally, you must alert if anyone with read-only access attempts to update records, and log all privilege grants to this table.

```sql
-- 1. Create audit log table
CREATE TABLE audit_log (
  audit_id BIGINT GENERATED ALWAYS AS IDENTITY,
  table_name VARCHAR,
  operation VARCHAR, -- INSERT, UPDATE, DELETE, SELECT
  user_name VARCHAR,
  timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  old_values JSONB,
  new_values JSONB,
  status VARCHAR -- SUCCESS, FAILED, UNAUTHORIZED
);

-- 2. Create trigger to log all changes to job_postings_fact
CREATE OR REPLACE FUNCTION log_job_postings_changes()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO audit_log (table_name, operation, user_name, old_values, new_values, status)
  VALUES (
    'job_postings_fact',
    TG_OP,
    CURRENT_USER,
    to_jsonb(OLD),
    to_jsonb(NEW),
    'SUCCESS'
  );
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER job_postings_audit_trigger
AFTER INSERT OR UPDATE OR DELETE ON job_postings_fact
FOR EACH ROW EXECUTE FUNCTION log_job_postings_changes();

-- 3. Create privilege change log
CREATE TABLE privilege_audit (
  privilege_id BIGINT GENERATED ALWAYS AS IDENTITY,
  grantee VARCHAR,
  table_name VARCHAR,
  permission VARCHAR, -- SELECT, INSERT, UPDATE, DELETE
  granted_by VARCHAR,
  granted_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  revoked_at TIMESTAMP
);

-- 4. Query: Who accessed salary data in the last 24 hours?
SELECT DISTINCT user_name, COUNT(*) as access_count, MAX(timestamp) as last_access
FROM audit_log
WHERE table_name = 'job_postings_fact'
  AND operation = 'SELECT'
  AND timestamp > CURRENT_TIMESTAMP - INTERVAL '24 hours'
GROUP BY user_name;

-- 5. Alert: Read-only users attempting writes
SELECT user_name, timestamp, operation
FROM audit_log
WHERE table_name = 'job_postings_fact'
  AND operation IN ('INSERT', 'UPDATE', 'DELETE')
  AND user_name IN (
    SELECT grantee FROM privilege_audit
    WHERE table_name = 'job_postings_fact'
      AND permission = 'SELECT'
      AND revoked_at IS NULL
  )
  AND timestamp > CURRENT_TIMESTAMP - INTERVAL '1 hour';
```

## Notes

- **Audit log bloat is real.** Don't log every SELECT unless required; filter by sensitivity level. Use partitioning by date to keep queries fast as logs grow.
- **Immutability matters.** Audit logs must themselves be tamper-proof (append-only, restricted delete permissions, ideally in a separate database or data lake). A compromised audit table is worse than none.
- **Connected to data lineage and observability.** Audit logs answer "who," lineage answers "where did this data come from," and observability answers "did the pipeline behave as expected." All three are needed for trust.
- **Regulatory compliance requires this.** SOX, HIPAA, GDPR, and internal policies typically mandate audit trails. Document your logging strategy explicitly; regulators want to see it.
- **Revisit privilege models regularly.** Audit logs show access patterns; use them quarterly to revoke stale permissions (principle of least privilege decay prevention).
