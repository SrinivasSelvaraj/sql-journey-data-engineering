---
date: 2026-09-24
phase: cloud
topic: Backup retention policies and incremental backups
---

# Backup retention policies and incremental backups

*Cloud platforms and storage*

## Concept

Backup retention policies define how long snapshots or copies of data are kept before deletion, directly impacting storage costs and recovery windows. Incremental backups capture only changed data since the last backup, reducing storage footprint and transfer time compared to full backups. Without a retention policy, backups accumulate indefinitely—a common hidden cost in cloud platforms where you pay per GB-month stored.

The interaction matters most when recovering from accidental deletes or corruption: if your retention window is too short, you cannot recover; if too long, you're paying for backups you'll never use. Incremental backups are only useful if you maintain a full backup baseline and can replay the chain of increments—breaking the chain (e.g., deleting an intermediate increment) makes later increments unrecoverable. Cloud platforms (AWS S3, Google Cloud Storage, Azure Blob) charge per GB stored, so a naive "keep everything forever" approach can cost 2–3× your active dataset.

## Practice

**Problem:** You back up a `job_postings_fact` table daily. Full backups are 50 GB; incremental backups are 2 GB daily. After 90 days, you realize you're storing 50 + (88 × 2) = 226 GB. Your retention policy should keep only the last 30 days of increments plus one full baseline. Write a query to identify which backup snapshots to retain and which to delete.

```sql
WITH backup_log AS (
  SELECT 
    backup_date,
    backup_type, -- 'FULL' or 'INCREMENTAL'
    size_gb,
    ROW_NUMBER() OVER (ORDER BY backup_date DESC) AS recency_rank
  FROM backups
  WHERE backup_date >= CURRENT_DATE - 30
),
retention_plan AS (
  SELECT 
    backup_date,
    backup_type,
    size_gb,
    CASE
      WHEN backup_type = 'FULL' AND recency_rank = 1 THEN 'RETAIN - Latest full baseline'
      WHEN backup_type = 'INCREMENTAL' AND recency_rank <= 30 THEN 'RETAIN - Within 30-day window'
      ELSE 'DELETE'
    END AS action
  FROM backup_log
)
SELECT 
  action,
  COUNT(*) AS backup_count,
  SUM(size_gb) AS total_gb
FROM retention_plan
GROUP BY action
ORDER BY action;
```

## Notes

- **Off-by-one in chain breaks:** Deleting a full backup while increments exist orphans those increments; always delete from oldest to newest, verifying the chain before cleanup.
- **Hidden costs:** A 2 GB daily increment × 365 days = 730 GB/year; at $0.023/GB-month on S3, that's ~$170/year—easily overlooked in cost audits.
- **RPO vs. RTO:** Retention policy defines recovery point objective (how old can restored data be); incremental frequency defines recovery time objective (how fast you can restore); set both consciously.
- **Test restore paths:** Incremental backups only work if you can replay the full chain; regularly validate restore procedures to catch chain breaks early.
- **Adjacent topic:** Understand your platform's snapshot mechanisms (AWS EBS snapshots are incremental by default; S3 versioning is separate from backups); conflate them at your cost.
