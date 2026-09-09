---
date: 2026-09-09
phase: reliability
topic: Audit logging: what to capture and how to query it
---

# Audit logging: what to capture and how to query it

*Quality, reliability and the professional layer*

## Concept

Audit logging captures *who did what, when, and why* in your data systems—not just what data changed, but the metadata of the change itself. This includes user identity, timestamp, operation type (INSERT/UPDATE/DELETE), affected records, and ideally the business justification. Without it, you cannot answer critical questions: Did someone corrupt this metric intentionally or by accident? Which pipeline run introduced bad data? Who has actually accessed sensitive columns?

Audit logs become non-negotiable once your pipeline owns decisions that affect business outcomes. A data engineer who owns a pipeline must be able to prove data lineage, explain anomalies, and defend against accusations of negligence or manipulation. This is the difference between "it broke" and "here's exactly what happened and why."

The absence of audit trails forces you to debug blind—you'll re-run entire pipelines, re-process months of data, or worse, serve stale or incorrect answers to stakeholders. It also creates compliance risk; many regulated industries (finance, healthcare, ads) legally require audit trails. Start logging early; retrofitting it is exponentially harder.

## Practice

**Problem:** Your `job_postings_fact` table is the source of truth for compensation analysis. Over the past week, some salary_year_avg values were updated, but you don't know which rows changed, who changed them, or whether it was a legitimate correction or a data quality issue. You need to investigate and prove the integrity of your data to your analytics lead.

```sql
-- Create audit log table (runs alongside your pipeline)
CREATE TABLE job_postings_audit (
  audit_id BIGINT PRIMARY KEY,
  job_id INT,
  operation VARCHAR(10),  -- INSERT, UPDATE, DELETE
  old_salary_year_avg INT,
  new_salary_year_avg INT,
  changed_by VARCHAR(100),  -- user, service account, or pipeline name
  changed_at TIMESTAMP,
  reason VARCHAR(500),  -- why the change happened
  source_system VARCHAR(50)  -- which pipeline/tool made the change
);

-- Query: Find all salary changes in the last 7 days
SELECT 
  job_id,
  old_salary_year_avg,
  new_salary_year_avg,
  (new_salary_year_avg - old_salary_year_avg) AS delta,
  changed_by,
  changed_at,
  reason
FROM job_postings_audit
WHERE operation = 'UPDATE'
  AND changed_at >= CURRENT_DATE - INTERVAL 7 DAY
  AND old_salary_year_avg IS NOT NULL
ORDER BY ABS(new_salary_year_avg - old_salary_year_avg) DESC;

-- Query: Identify which user/pipeline made the largest changes
SELECT 
  changed_by,
  COUNT(*) AS change_count,
  AVG(ABS(new_salary_year_avg - old_salary_year_avg)) AS avg_delta
FROM job_postings_audit
WHERE operation = 'UPDATE'
  AND changed_at >= CURRENT_DATE - INTERVAL 7 DAY
GROUP BY changed_by
ORDER BY change_count DESC;
```

## Notes

- **Log too much, not too little.** Include old and new values, not just the new state. Include reason/justification as a required field—it forces accountability and makes debugging faster. Store raw user ID and timestamp, not derived fields.
- **Separate audit tables from operational tables.** Audit logs should be immutable and isolated. Do not log to the fact table itself; use a dedicated append-only table or event stream. This prevents accidental deletion and makes retention policies cleaner.
- **Connects to:** data lineage tracking, compliance/GDPR (right to audit), observability (distinguishing data bugs from pipeline bugs), role-based access control (RBAC).
- **Common mistake:** Logging only at the table level, not the column level. If salary_year_avg changed, log the old and new value for that column specifically. Broad "row updated" messages are useless for debugging.
- **Revisit:** retention policies (how long to keep audit logs), performance of audit queries on high-volume tables, and automating alerts when unusual patterns appear (e.g., one user updated 10,000 rows in one run).
