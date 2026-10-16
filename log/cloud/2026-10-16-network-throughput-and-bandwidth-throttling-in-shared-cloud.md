---
date: 2026-10-16
phase: cloud
topic: Network throughput and bandwidth throttling in shared cloud
---

# Network throughput and bandwidth throttling in shared cloud

*Cloud platforms and storage*

## Concept

Network throughput is the rate at which data moves between your compute instance and storage (or between services). In shared cloud environments, your throughput is not guaranteed—it's often a soft limit that degrades under contention. When you query a 100 GB table, you're not just waiting for CPU; you're waiting for that data to travel from storage to your instance at whatever bandwidth the cloud provider allocates to you at that moment.

Bandwidth throttling happens silently. A query that completes in 30 seconds during off-peak hours may take 3 minutes at 9 AM because other tenants on the same physical network are competing for the same pipes. You won't see an error message; you'll see a slow query and blame the query planner. The real culprit is often egress volume, cross-region transfers, or hitting per-instance network limits.

This matters most when you're scanning large tables, exporting results, or moving data between regions. A 1 TB daily export that was never a problem becomes a bottleneck when you add another job. Ignoring this forces you to add unnecessary indexes, partition aggressively, or throw compute at the wrong problem.

## Practice

**Problem:** You're running a nightly job that exports all job postings from the last 90 days to a data warehouse in a different region. The query itself is fast (2 seconds), but the export takes 45 minutes. You suspect the query is the issue, but data volume is actually 8 GB and your instance has a 100 Mbps network limit during peak hours.

**Solution:** Break the export into smaller, sequential batches instead of one massive pull. This reduces per-request data volume and allows prioritization:

```sql
-- Instead of: SELECT * FROM job_postings_fact WHERE job_posted_date >= CURRENT_DATE - 90
-- Do this in batches, or apply compression:

EXPORT DATA OPTIONS(
  uri='gs://my-warehouse/job_postings/batch_*.parquet',
  format='PARQUET',
  overwrite=false
) AS
SELECT 
  job_id, 
  job_title_short, 
  salary_year_avg,
  job_work_from_home,
  job_posted_date,
  job_location
FROM job_postings_fact
WHERE job_posted_date >= CURRENT_DATE - 90
  AND MOD(FARM_FINGERPRINT(CAST(job_id AS STRING)), 10) = 0  -- Export 10% per run
ORDER BY job_posted_date DESC;
```

Run this 10 times with different modulo values (0–9) to spread the load over time, or use native compression to reduce egress volume by 60–80%.

## Notes

- **Confusing slow queries with slow networks:** Always check data volume (bytes transferred) before blaming the query plan. A 5-second query moving 50 GB is network-bound; a 5-second query moving 100 MB might be CPU-bound.
- **Egress charges compound the pain:** Cloud providers charge for data leaving their network. Throttling forces you to move data slowly, increasing costs and wall-clock time together.
- **Cross-region transfers are the silent killer:** Moving 1 GB within a region costs nothing and is fast; moving it across regions costs 0.02/GB and often hits lower throughput caps. Check your destination before designing exports.
- **Instance-level network limits exist but aren't documented clearly.** A small instance (t2.micro, e2-small) may have 100–200 Mbps; a large instance (m5.2xlarge, n2-highmem-8) may have 10 Gbps. Verify your instance type's network specifications.
- **Reconnect to query optimization:** Reduce bytes transferred first (projection, filtering, compression), then optimize the query. In shared clouds, moving less data often beats moving it faster.
