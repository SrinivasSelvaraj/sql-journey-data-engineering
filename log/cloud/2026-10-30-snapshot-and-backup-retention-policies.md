---
date: 2026-10-30
phase: cloud
topic: Snapshot and backup retention policies
---

# Snapshot and backup retention policies

*Cloud platforms and storage*

## Concept

Snapshot and backup retention policies define how long historical versions of data are kept and at what cost. In cloud storage (S3, GCS, Azure Blob), snapshots capture point-in-time states of datasets; backups preserve deleted or corrupted data. Without a policy, storage costs grow unbounded—a table that doubles in size monthly will accumulate snapshots that cost 3–5× the live dataset within a year. Retention policies matter most when you have high-velocity data (frequent writes, deletes) or regulatory requirements (HIPAA, GDPR mandate 7-year retention). They also directly impact query performance: searching across 100 unneeded snapshots slows discovery and metadata operations.

The policy trade-off is simple: keep snapshots long enough to recover from accidents or audit requirements, but short enough that storage bills remain predictable. Most teams set daily snapshots for 30 days, weekly for 90 days, then archive older versions to cold storage or delete them. Without explicit policies, teams either delete too aggressively (losing ability to debug data quality issues) or too conservatively (paying thousands monthly for snapshots no one uses).

## Practice

**Problem:** Your `job_postings_fact` table grows by ~2GB daily. You want to keep daily snapshots for 30 days, weekly snapshots for the next 90 days, then delete older snapshots. You also need to audit job postings from exactly 45 days ago. How do you structure the retention logic and query the historical snapshot?

```sql
-- Define retention policy (pseudocode for your orchestration tool)
-- Daily snapshots: keep for 30 days
-- Weekly snapshots: keep for 30–120 days (one per week)
-- Older snapshots: delete after 120 days

-- Query historical snapshot from 45 days ago (falls in weekly range)
-- Assuming snapshots stored as partitions: s3://data-lake/job_postings_fact/snapshot_date=YYYY-MM-DD/

SELECT 
  job_id,
  job_title_short,
  salary_year_avg,
  job_location
FROM job_postings_fact
WHERE snapshot_date = DATE_SUB(CURRENT_DATE(), INTERVAL 45 DAY)
  AND job_posted_date < DATE_SUB(CURRENT_DATE(), INTERVAL 45 DAY)
LIMIT 100;

-- Calculate storage cost: 2GB/day × 30 days + (13 weekly snapshots × 2GB × 0.7 ratio) ≈ 78GB
-- At $0.023/GB/month in S3 Standard = ~$1.80/month for this table
```

## Notes

- **Tiered retention is cheaper than uniform retention.** Keep hot snapshots (7–30 days) in Standard storage; move warm snapshots (30–120 days) to Intelligent-Tiering or Glacier. Archive compliance snapshots separately.
- **Confusion with version control:** Git snapshots (commits) are not the same as data snapshots. Data snapshots are immutable copies; version control is incremental deltas.
- **Deletion lag:** Deleting a snapshot does not immediately free cloud storage; bills reflect the end-of-month usage. Budget for at least one extra billing cycle when reducing retention.
- **Adjacent topics:** This connects to time-travel queries (Iceberg, Delta Lake), WAL (write-ahead logs) for durability, and RTO/RPO (recovery time/point objectives) in disaster recovery planning.
- **Common mistake:** Setting retention policy globally without considering table size or change frequency. A 500GB reference table needs different retention than a 2GB event stream.
