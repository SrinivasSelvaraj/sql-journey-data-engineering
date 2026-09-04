---
date: 2026-09-04
phase: cloud
topic: Data transfer costs: intra-region vs cross-region vs internet
---

# Data transfer costs: intra-region vs cross-region vs internet

*Cloud platforms and storage*

## Concept

Cloud providers charge for data movement based on direction and distance. **Intra-region transfers** (within the same datacenter or region) are free or near-free. **Cross-region transfers** cost $0.01–0.02 per GB. **Internet egress** (data leaving the cloud entirely) costs $0.08–0.12 per GB—10× more expensive. This matters because a query joining a 100 GB table across regions costs $1–2; the same query across the internet costs $8–12. Without understanding these costs, you'll build architectures that work correctly but drain budgets. A slow query might not be slow because of computation—it might be slow because data is traveling across the planet at network speed rather than disk speed.

The cost structure incentivizes **data locality**: keep compute and storage in the same region, replicate strategically, and avoid streaming large datasets to external systems. Many performance problems blamed on query inefficiency are actually network I/O bottlenecks. A job that takes 30 minutes might be 25 minutes of waiting for bytes to arrive from another region.

## Practice

**Problem:** Your analytics team in us-west-2 needs to join `job_postings_fact` (stored in us-east-1) with a local salary benchmark table weekly. The join runs, but costs spike and latency is high. You want to minimize transfer costs without duplicating data unnecessarily.

```sql
-- Option 1: Move aggregation to source region (us-east-1), transfer only result
CREATE TABLE us_west_2.job_salary_summary AS
SELECT 
  job_title_short,
  AVG(salary_year_avg) as avg_salary,
  COUNT(*) as job_count
FROM us_east_1.job_postings_fact
WHERE job_posted_date >= CURRENT_DATE - INTERVAL 7 DAY
GROUP BY job_title_short;
-- Transfer: ~1 MB instead of 100 GB

-- Option 2: Replicate compressed snapshot to us-west-2 for joins
CREATE TABLE us_west_2.job_postings_fact_replica AS
SELECT job_id, job_title_short, salary_year_avg, job_location
FROM us_east_1.job_postings_fact
WHERE job_posted_date >= CURRENT_DATE - INTERVAL 30 DAY;
-- One-time transfer cost, then all local queries are free
```

## Notes

- **Aggregation pushdown is your friend:** Always filter, group, and reduce before transferring. Moving 100 GB across regions to then aggregate down to 1 MB is wasteful.
- **Cross-region replication has a place:** If you query the same dataset repeatedly, replicate a snapshot (with retention policy) rather than querying across regions every time.
- **Internet egress is the silent killer:** Exporting results to S3 in a different region, or to an external data warehouse, multiplies costs. Always check your egress destination in CloudTrail/cost explorer.
- **Connects to:** query optimization (network I/O vs CPU/disk I/O trade-offs), columnar storage and compression (smaller transfers), and multi-region architecture (when replication is justified vs. when it's just overhead).
- **Revisit if:** your cloud bill spikes unexpectedly, you notice queries slow down at specific times, or you're building a data pipeline that touches multiple regions.
