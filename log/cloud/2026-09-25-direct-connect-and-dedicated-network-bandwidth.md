---
date: 2026-09-25
phase: cloud
topic: Direct Connect and dedicated network bandwidth
---

# Direct Connect and dedicated network bandwidth

*Cloud platforms and storage*

## Concept

Direct Connect (AWS) or Interconnect (GCP/Azure) establishes a dedicated network path between your on-premises infrastructure and cloud resources, bypassing the public internet. Unlike standard internet connectivity, which shares bandwidth with competing traffic, dedicated connections guarantee consistent throughput and lower latency—critical when moving terabytes of data or running latency-sensitive queries against cloud databases.

Without dedicated bandwidth, large data transfers (ETL pipelines, bulk analytics queries, backups) compete for shared internet capacity. A 10 GB file that should transfer in seconds can take minutes during peak hours. For analytics, this means slow query results even if your database engine is fast; the bottleneck is the network pipe, not compute. You pay per unit of bandwidth on public internet (egress charges pile up), whereas Direct Connect charges a fixed port fee plus minimal data transfer costs—a significant savings if moving petabytes monthly.

The decision tree is simple: if you're scanning millions of rows across regions, syncing data lakes, or running frequent cross-region queries, measure your network latency and throughput first. High egress costs or query plans showing "wait for network" are red flags that dedicated bandwidth will pay for itself.

## Practice

**Problem:** Your analytics team runs a nightly job that joins `job_postings_fact` (500 million rows) from your on-premises PostgreSQL cluster with a cloud data warehouse for salary analysis. The query completes in 30 seconds on-premises but takes 15 minutes after adding a cloud JOIN step. The database logs show no wait time, but ETL logs show the 8 GB result set is trickling over public internet at 1.5 MB/s.

**Solution:**
```sql
-- Identify data volume being moved
SELECT 
  COUNT(*) as row_count,
  ROUND(SUM(OCTET_LENGTH(job_title_short::TEXT) 
    + OCTET_LENGTH(job_location::TEXT)) / 1024.0 / 1024.0, 2) as estimated_mb
FROM job_postings_fact
WHERE job_posted_date >= CURRENT_DATE - INTERVAL '1 day';

-- Result: 2.1M rows, ~180 MB daily
-- At 1.5 MB/s over public internet: 120 seconds per day
-- Direct Connect (10 Gbps dedicated): 0.14 seconds
-- Annual cost: Fixed port (~$0.30/hour) vs egress charges (~$0.02/GB × 180 MB/day × 365 = $1,314/year)
-- Direct Connect ROI: 3–4 months
```

## Notes

- **Egress cost blindness:** Many teams don't realize they're paying $0.02–$0.09 per GB for data leaving the cloud; dedicated connections cost ~$0.001/GB. Always audit egress spend before dismissing Direct Connect as expensive.
- **Region placement matters:** Direct Connect reduces latency only between specific endpoints; a query pulling from three regions still waits for the slowest link. Use region-local replicas or co-locate data.
- **Shared port contention:** Direct Connect is dedicated but shared among all workloads on that port; a single runaway job can starve others. Implement QoS and connection pooling.
- **Adjacent topic—compression:** Before committing to dedicated bandwidth, compress result sets (Parquet, gzip). A 10:1 compression ratio eliminates the need for costly upgrades.
- **Revisit:** Measure actual vs. theoretical bandwidth monthly; cloud providers may throttle or degrade shared capacity. Re-baseline after major job changes.
