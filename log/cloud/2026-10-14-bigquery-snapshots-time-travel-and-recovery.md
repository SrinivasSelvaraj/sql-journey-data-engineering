---
date: 2026-10-14
phase: cloud
topic: BigQuery snapshots: time-travel and recovery
---

# BigQuery snapshots: time-travel and recovery

*Cloud platforms and storage*

## Concept

BigQuery Table Snapshots allow you to query a table as it existed at a specific point in time, enabled by BigQuery's native time-travel feature (up to 7 days by default). This works because BigQuery retains table metadata and data versions; when you DELETE or UPDATE rows, the original data isn't immediately purged—it's marked as no longer current but remains retrievable. Without snapshots, accidental deletes are permanent, data lineage is lost, and debugging "why did the metric change yesterday?" becomes impossible.

The mechanism is straightforward: append a `FOR SYSTEM_TIME AS OF` clause with a timestamp or an interval. This is essential when production ETL jobs fail silently, when analysts overwrite critical tables, or when you need to reconstruct state for a specific reporting date. It also directly impacts cost and query debugging—you can re-run slow queries against an older snapshot to isolate whether slowness is data-dependent or infrastructure-related.

Keep in mind that snapshots are *not* backups; they're temporary versioning within the table's retention window. After 7 days (or your configured retention period), the old versions are garbage-collected. For long-term recovery needs, you must export snapshots to Cloud Storage or replicate to a separate dataset.

## Practice

**Problem:** Your `job_postings_fact` table was accidentally truncated yesterday at 14:30 UTC. You need to restore the row count and verify salary data from 13:00 UTC (before the incident).

```sql
-- Query the table as it was at 13:00 UTC yesterday
SELECT 
  COUNT(*) as row_count,
  AVG(salary_year_avg) as avg_salary,
  COUNT(DISTINCT job_id) as unique_jobs
FROM 
  `project.dataset.job_postings_fact`
  FOR SYSTEM_TIME AS OF TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 25 HOUR)
WHERE 
  job_posted_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY);

-- Restore the snapshot into a recovery table
CREATE TABLE `project.dataset.job_postings_fact_recovered` AS
SELECT * FROM `project.dataset.job_postings_fact`
FOR SYSTEM_TIME AS OF TIMESTAMP('2024-01-15 13:00:00 UTC');
```

## Notes

- **Retention is not infinite:** The default 7-day window is configurable but has limits. Plan exports or CDC strategies for audit-grade durability; snapshots are operational safety, not compliance backups.
- **`FOR SYSTEM_TIME` syntax varies by tool:** Terraform, dbt, and SQL clients all support it, but check your driver's BigQuery library version—older versions may not parse the clause.
- **Adjacent topics:** Table cloning (fast, zero-copy duplicates), change data capture (CDCs) with Datastream, and query result caching all intersect here; together they form a recovery and debugging toolkit.
- **Cost implication:** Querying old snapshots is cheap (you're just reading existing blocks), but *restoring* a large snapshot with `CREATE TABLE AS SELECT` incurs the same scan cost as any query—monitor slot usage and duration.
- **Staging vs. production:** Test snapshot queries on non-critical tables first; a wide time-travel query on a 10 TB table can run long and consume significant resources.
