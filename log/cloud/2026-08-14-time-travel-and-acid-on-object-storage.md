---
date: 2026-08-14
phase: cloud
topic: Time travel and ACID on object storage
---

# Time travel and ACID on object storage

*Cloud platforms and storage*

## Concept

Time travel and ACID guarantees on object storage (S3, GCS, Azure Blob) enable you to query historical snapshots of data and trust that concurrent writes won't corrupt your tables. Without time travel, you lose audit trails and must rebuild entire datasets to recover from bad writes. Without ACID, concurrent inserts can silently drop rows, readers can see partial transactions, or metadata can fall out of sync with actual files—all invisible until you spot data loss weeks later.

Lakehouse formats like Delta Lake and Apache Iceberg solve this by storing immutable manifest files that track which data files belong to each table version. When you write, the format commits atomically—either the manifest updates or nothing does. This is why querying `SELECT * FROM job_postings_fact TIMESTAMP AS OF '2024-01-15'` works: you're asking the format engine to reconstruct the table as it existed on that date by reading the appropriate manifest, not the live files.

The cost trade-off is real: every write must serialize metadata changes, and every read must parse more manifest history. On high-velocity pipelines (thousands of writes per day), manifest bloat can slow queries. Compaction and vacuum operations clean up old snapshots but add operational overhead. Cloud bill impact: more API calls to list/read manifests, and longer query planning time eating into your compute budget.

## Practice

**Problem:** Your analytics team accidentally loaded duplicate job postings on 2024-03-10, inflating salary averages. You need to restore the table to 2024-03-09 11:59 PM without losing data loaded after the bad batch, and audit which jobs were duplicated.

```sql
-- Restore the table to the last known good state
RESTORE TABLE job_postings_fact TO VERSION AS OF 45;

-- Or use timestamp (Delta Lake syntax)
SELECT * FROM job_postings_fact 
TIMESTAMP AS OF '2024-03-09 23:59:00' 
WHERE job_location LIKE '%Remote%';

-- Identify what was lost: rows in current version but not in snapshot
SELECT current.job_id, current.job_title_short
FROM job_postings_fact current
LEFT JOIN (
  SELECT job_id FROM job_postings_fact 
  VERSION AS OF 45
) snapshot ON current.job_id = snapshot.job_id
WHERE snapshot.job_id IS NULL
  AND current.job_posted_date >= '2024-03-10';

-- Manually re-insert good data loaded after the bad batch
INSERT INTO job_postings_fact
SELECT * FROM staging_clean_job_postings 
WHERE job_posted_date > '2024-03-10';
```

## Notes

- **Manifest bloat is invisible until query planning tanks:** Monitor manifest file count and vacuum aggressively on high-write tables. Delta Lake's `OPTIMIZE` is cheap; skipping it compounds debt.
- **Time travel queries are slower than live queries:** Manifest reconstruction adds latency. Pin critical dashboards to recent versions rather than arbitrary historical dates.
- **ACID failures don't always crash—they corrupt silently:** A botched merge during concurrent writes may succeed but skip rows. Always validate row counts after large batch operations before declaring success.
- **Connects to:** partition pruning (manifests index by partition), snapshot isolation (how writers don't block readers), and compaction strategies (why small files hurt cost more than just storage).
- **Revisit when:** your cloud bill spikes after adding time-travel queries, or you need compliance audits that require immutable change logs—this is where lakehouse formats earn their overhead.
