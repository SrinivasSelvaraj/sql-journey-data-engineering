---
date: 2026-11-04
phase: reliability
topic: Audit logging: who accessed what data when
---

# Audit logging: who accessed what data when

*Quality, reliability and the professional layer*

## Concept

Audit logging records *who* accessed *what* data *when*—creating an immutable trail of all data interactions. This is not logging for debugging; it's logging for accountability. In regulated industries (finance, healthcare, government) or when handling sensitive PII, audit logs become compliance requirements. Without them, you cannot answer critical questions: Did someone query customer payment records at 3 AM? Who exported the entire employee salary table? When did unauthorized access occur?

The difference between a pipeline engineer and a data owner is simple: the engineer builds systems that work; the owner builds systems that can be audited. Audit logging is the bridge. It protects both the organization (compliance, forensics) and the individuals writing queries (proof of legitimate access). Without it, a single data breach becomes impossible to investigate, and every team member becomes a suspect.

Audit logs must be tamper-proof (immutable, centralized storage), comprehensive (capture query text, user identity, timestamp, rows affected), and queryable (you need to search them fast when incidents happen). Half-measures—like application logs or query history in your warehouse—get deleted during maintenance or don't capture enough context.

## Practice

**Problem:** Your company stores job postings in `job_postings_fact`. The salary column contains sensitive compensation data. A recruiter reports that historical salary ranges for a competitor's roles disappeared from the dashboard yesterday. You need to identify who queried or modified salary data, when, and how many rows were affected.

```sql
-- Audit log schema (create once, append-only)
CREATE TABLE audit_log_immutable (
  audit_id BIGINT PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
  accessed_at TIMESTAMP NOT NULL,
  accessed_by VARCHAR(255) NOT NULL,
  action VARCHAR(50) NOT NULL, -- SELECT, UPDATE, DELETE, EXPORT
  table_name VARCHAR(255) NOT NULL,
  columns_accessed ARRAY<VARCHAR>,
  filter_condition TEXT, -- WHERE clause or null for full table scans
  rows_affected INT,
  query_hash VARCHAR(64), -- SHA256 of full query
  sensitive_columns_touched BOOLEAN,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
) 
WITH (
  partitioned_by = ['DATE(accessed_at)'],
  clustered_by = ['accessed_by', 'table_name']
);

-- Log entry: recruiter queried salary data
INSERT INTO audit_log_immutable (
  accessed_at, accessed_by, action, table_name, 
  columns_accessed, filter_condition, rows_affected, 
  sensitive_columns_touched
)
VALUES (
  '2024-01-15 14:32:00', 
  'recruiter_jane@company.com', 
  'SELECT', 
  'job_postings_fact',
  ARRAY['job_id', 'job_title_short', 'salary_year_avg'],
  'WHERE job_location LIKE ''%Competitor%''',
  1247,
  TRUE
);

-- Investigation query: who touched salary data in the last 48 hours?
SELECT 
  accessed_by,
  accessed_at,
  action,
  rows_affected,
  filter_condition
FROM audit_log_immutable
WHERE table_name = 'job_postings_fact'
  AND 'salary_year_avg' = ANY(columns_accessed)
  AND accessed_at >= CURRENT_TIMESTAMP - INTERVAL '48 hours'
ORDER BY accessed_at DESC;
```

## Notes

- **Immutability is non-negotiable.** Use append-only tables, write-once cloud storage, or dedicated audit services (Cloudtrail, BigQuery audit logs). Never let analysts or admins modify audit records retroactively.
- **Capture the query, not just metadata.** The *filter condition* or full query text is often more valuable than row counts. It answers "what were they looking for?"—intent matters in investigations.
- **Partition aggressively.** Audit logs grow fast. Partition by date and cluster by user/table so forensic queries don't scan years of data. Archive to cheaper storage after retention period (typically 1–7 years by regulation).
- **Sensitive column tagging.** Flag when salary, SSN, email, or other PII columns are touched. Alert ops in real-time if a non-analyst role accesses them unexpectedly. This is where audit logging connects to data governance and access control.
- **Revisit: data lineage tools (dbt, Collibra), secrets management (who has credentials?), and query federation** (which warehouse actually processed the request?). Audit logging is the outermost layer; these tools fill gaps inside it.
