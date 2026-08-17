---
date: 2026-08-17
phase: reliability
topic: Estimating throughput, storage and cost in an interview
---

# Estimating throughput, storage and cost in an interview

*Quality, reliability and the professional layer*

## Concept

Estimating throughput, storage, and cost separates engineers who ship from those who operate at scale. In interviews, you're often asked to design a system—but naming the data warehouse isn't enough. You need to project: *How many events per second? How much disk space in six months? What's the monthly bill?* These aren't afterthoughts; they determine whether your design is viable.

This matters most when moving from prototype to production. A pipeline that works beautifully on 10GB of test data may become a budget disaster at 1TB/day. Storage decisions compound (retention × cardinality × replication). Throughput bottlenecks surface at peak load, not at design review. Cost surprises kill projects and erode trust. An owner who can say "our fact table grows 500GB weekly, costing $X in storage, Y in compute, and Z in egress" demonstrates maturity. Someone who can't—or hasn't thought about it—signals they've never run something in production.

## Practice

**Problem:** You're building a daily ETL that loads the `job_postings_fact` table. Data arrives from an API in batches. You get roughly 50,000 new postings per day, each record is ~800 bytes. You retain 2 years of history. Your cloud provider charges $0.023 per GB-month for storage, $5 per compute hour, and the job takes 2 hours to run daily. Estimate annual storage cost and total pipeline cost.

```sql
-- Storage estimation
WITH estimates AS (
  SELECT
    50000 AS daily_records,
    800 AS bytes_per_record,
    365 AS days_per_year,
    730 AS days_retained, -- 2 years
    0.023 AS cost_per_gb_month,
    5 AS compute_cost_per_hour,
    2 AS hours_per_run,
    365 AS runs_per_year
)
SELECT
  -- Storage math
  ROUND((daily_records * days_per_year * bytes_per_record / 1024.0 / 1024.0 / 1024.0), 2) 
    AS annual_ingest_gb,
  ROUND((daily_records * days_retained * bytes_per_record / 1024.0 / 1024.0 / 1024.0), 2)
    AS total_retained_gb,
  ROUND(
    (daily_records * days_retained * bytes_per_record / 1024.0 / 1024.0 / 1024.0) * cost_per_gb_month * 12,
    2
  ) AS annual_storage_cost,
  
  -- Compute cost
  ROUND(compute_cost_per_hour * hours_per_run * runs_per_year, 2) 
    AS annual_compute_cost
FROM estimates;
```

**Output reasoning:** ~18.25 GB ingested yearly; ~33.3 GB retained; storage runs ~$9.19/year; compute runs $3,650/year. The compute cost dominates—so investigate parallelization. This also flags: *What about indexes? Compression? Replication factor?* Those multiply your base storage 2–3×.

## Notes

- **Off-by-one in time windows:** Confusing daily vs. hourly ingestion, or retention windows (1 year from today vs. calendar years). Always clarify "rolling 365 days" vs. "2 full calendar years."
- **Forgetting the invisible:** Raw storage is rarely the final bill. Add: compression ratio (often 3–5×), replication (2–3 copies), backups, indexes, and egress fees if queried cross-region. A 10 GB table costs 30–50 GB in practice.
- **Throughput under load, not average:** Peak traffic isn't mean; size for 95th percentile. A job that takes 2 hours at average load may take 6 at peak, breaking your SLA. Test with synthetic load.
- **Cost ownership:** Cloud bills surprise people. Break down: storage, compute, network, managed services (DW slots, streaming ingestion). Know your top 3 cost drivers; propose optimization targets to leadership.
- **Connects to:** capacity planning, SLO/SLA definitions, data retention policies, and partitioning strategy. All feed backward into this estimate.
