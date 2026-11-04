---
date: 2026-11-04
phase: reliability
topic: Data retention policies: deletion and archival schedules
---

# Data retention policies: deletion and archival schedules

*Quality, reliability and the professional layer*

## Concept

Data retention policies define *when* data should be deleted or archived, not just *that* it should be. Without explicit schedules, pipelines accumulate unbounded storage costs, breach compliance requirements (GDPR, HIPAA, SOX), and slow down queries scanning irrelevant historical data. Retention becomes a professional concern the moment you own a system in production: it's the difference between "the data is there" and "the data is managed."

Archival moves cold data to cheaper storage (S3 Glacier, BigQuery archive tables) while maintaining queryability through federation or scheduled exports. Deletion is permanent and often regulatory (PII expiration windows, right-to-be-forgotten). The policy must answer: *How long does each dataset live?* *What triggers removal?* *Who audits it?* Without these answers, you inherit technical debt and liability.

Breaking without retention policies manifests as runaway costs, failed compliance audits, queries timing out on bloated tables, and the inability to prove data was deleted when required. It's invisible until it isn't.

## Practice

**Problem:** You maintain `job_postings_fact`. Job postings older than 2 years should be archived to cold storage; personal candidate contact info (if added) must be purged after 1 year for compliance. You need to track what was archived and when.

```sql
-- Create audit table to track retention actions
CREATE TABLE job_postings_archive_log (
  archived_at TIMESTAMP,
  job_id INT,
  archive_reason STRING,
  row_count INT
);

-- Archive old postings (>2 years) to Parquet in S3
INSERT INTO job_postings_archive_log
SELECT 
  CURRENT_TIMESTAMP() as archived_at,
  COUNT(DISTINCT job_id) as row_count,
  'age >2 years' as archive_reason,
  COUNT(*) as row_count
FROM job_postings_fact
WHERE job_posted_date < DATE_SUB(CURRENT_DATE(), INTERVAL 2 YEAR);

EXPORT DATA OPTIONS(
  uri='s3://data-archive/job_postings/*.parquet',
  format='PARQUET',
  overwrite=true
) AS
SELECT * FROM job_postings_fact
WHERE job_posted_date < DATE_SUB(CURRENT_DATE(), INTERVAL 2 YEAR);

-- Delete archived rows from hot table
DELETE FROM job_postings_fact
WHERE job_posted_date < DATE_SUB(CURRENT_DATE(), INTERVAL 2 YEAR);

-- Purge any contact fields (if present) older than 1 year
UPDATE job_postings_fact
SET contact_email = NULL, contact_phone = NULL
WHERE job_posted_date < DATE_SUB(CURRENT_DATE(), INTERVAL 1 YEAR)
  AND contact_email IS NOT NULL;
```

## Notes

- **Mistake:** Setting retention policies without consulting legal/compliance first. GDPR and sector-specific rules often mandate minimum retention, not just maximum—don't delete too early.
- **Mistake:** Archiving without an audit trail. Log *what* was archived, *when*, and *why*. You'll need this for compliance reviews and debugging accidental deletions.
- **Adjacent:** Cost optimization (archival = cheaper storage), data governance (who approves retention rules?), and incremental loading (archival patterns reduce full-table scans).
- **Worth revisiting:** Retention as code—store policies in a config table, not hardcoded TTLs. Allows audit and rapid policy changes without redeploying pipelines.
- **Consider:** Soft deletes (flag a `is_deleted` column) for non-compliance data; easier to recover from mistakes and audit, though it doubles storage temporarily.
