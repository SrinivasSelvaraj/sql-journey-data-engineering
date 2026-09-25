---
date: 2026-09-25
phase: cloud
topic: Databricks DBUs and autoscaling costs
---

# Databricks DBUs and autoscaling costs

*Cloud platforms and storage*

## Concept

DBUs (Databricks Units) are the currency of Databricks compute consumption—one DBU = one virtual machine core running for one hour. Every cluster you spin up burns DBUs whether actively querying or idle. Autoscaling compounds this: a cluster can grow from 2 to 10 nodes based on workload, multiplying your DBU burn rate instantly.

Understanding DBU cost matters because a poorly tuned job can cost 10× more than necessary. A query that runs on 8 nodes instead of 2, or a cluster left running overnight, directly translates to wasted budget. Slow queries aren't just slow—they're expensive, especially when autoscaling kicks in and you're charged for resources you don't need.

Without DBU visibility, you ship a job that works correctly but costs $200/day instead of $20/day. You don't notice until the bill arrives. The fix requires identifying which operations triggered autoscaling, which queries are inefficient, and whether you're holding cluster resources between jobs unnecessarily.

## Practice

**Problem:** Your job_postings_fact table has 500M rows. A daily job filters for remote positions and high salaries, but it's taking 45 minutes and causing your autoscaling cluster to jump from 2 to 8 nodes. You need to reduce cost and execution time.

```sql
-- Inefficient: full table scan without partitioning benefit
SELECT job_id, job_title_short, salary_year_avg
FROM job_postings_fact
WHERE job_work_from_home = TRUE
  AND salary_year_avg > 120000
  AND job_posted_date >= CURRENT_DATE - INTERVAL 7 DAYS;

-- Efficient: add partition pruning and caching
-- Assume job_postings_fact is partitioned by job_posted_date
CREATE TEMP VIEW recent_remote_jobs AS
SELECT job_id, job_title_short, salary_year_avg
FROM job_postings_fact
WHERE job_posted_date >= CURRENT_DATE - INTERVAL 7 DAYS  -- hits partition pruning first
  AND job_work_from_home = TRUE
  AND salary_year_avg > 120000;

-- Cache the result if queried repeatedly within a session
CACHE TABLE recent_remote_jobs;

SELECT * FROM recent_remote_jobs;
```

The fix: push partition filters first (prunes 99% of data before scanning), use caching to avoid re-scanning, and keep the cluster at 2–3 nodes with autoscaling disabled if job runs predictably.

## Notes

- **Autoscaling lag is invisible cost:** Clusters don't shrink instantly; a 10-minute query can hold 8 nodes for 20 minutes while draining DBUs during cooldown.
- **Partition pruning > query optimization:** A WHERE clause on an unpartitioned column forces a full scan; reorganizing by job_posted_date is cheaper than rewriting the query.
- **Idle clusters compound costs:** A stopped cluster costs $0; a running idle cluster still burns 2 DBU/hour. Always use job clusters (auto-terminate) instead of all-purpose clusters for production jobs.
- **Caching trades storage for compute:** CACHE TABLE is cheap if the table fits in memory; spilling to disk negates the benefit and wastes more DBUs than the original scan.
- **Adjacent topic:** Cluster sizing vs. query parallelism—DBU cost is a function of both; a 4-node cluster running a serial query is wasteful, while a 10-node cluster on a small filter is also wasteful.
