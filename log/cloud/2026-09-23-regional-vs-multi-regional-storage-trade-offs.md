---
date: 2026-09-23
phase: cloud
topic: Regional vs multi-regional storage trade-offs
---

# Regional vs multi-regional storage trade-offs

*Cloud platforms and storage*

## Concept

Regional storage (e.g., `us-central1`) keeps data in a single geographic zone, offering lower latency and egress costs for workloads operating within that region. Multi-regional storage replicates data across geographically distant zones, trading higher storage and egress costs for availability and disaster recovery. The choice becomes critical when you scale: a regional setup serving global users incurs massive inter-region transfer fees (often $0.02/GB), while multi-regional setups pay extra upfront but eliminate per-query geo-crossing penalties.

Query performance degrades silently across regions. A job posting search service querying regional US storage from Europe pays both latency (200ms+ round trips) and egress charges ($0.02 per GB transferred out). Without understanding your data residency, you discover the cost problem months into production when invoice spikes arrive.

The decision depends on your read/write patterns and user geography. If 90% of queries originate in one region, regional is cheaper. If queries are globally distributed or compliance requires replication, multi-regional becomes mandatory despite higher base costs.

## Practice

**Problem:** Your job postings table stores 2 years of data (500GB). You run daily analytics queries filtering by `job_location` from offices in both US and Europe, exporting results as CSV. Regional storage in `us-central1` costs $0.02/GB per export; multi-regional costs 20% more in storage but $0 for inter-region reads within Google Cloud.

```sql
-- Query pattern: export jobs posted last 7 days by location
SELECT 
  job_id,
  job_title_short,
  salary_year_avg,
  job_location,
  job_posted_date
FROM job_postings_fact
WHERE job_posted_date >= CURRENT_DATE - 7
  AND job_location IN ('London', 'Berlin', 'New York', 'San Francisco')
ORDER BY salary_year_avg DESC;

-- Cost impact (simplified):
-- Regional: 50GB export × $0.02/GB = $1.00 per query
-- Multi-regional: same query = $0 egress (stays in Google Cloud ecosystem)
-- European office running this daily: $1 × 250 workdays = $250/year (regional)
-- vs. $50/year extra storage + $0 egress (multi-regional) = net $200 savings
```

## Notes

- **Cold data trap:** Regional storage looks cheap until you query from the wrong continent; multi-regional seems expensive until you calculate monthly egress costs on just 100GB/day of exports.
- **Compliance ≠ performance:** GDPR may require data residency by region, but multi-regional within EU still allows replication without serving from US.
- **Hybrid approach:** Store hot (last 90 days) data multi-regional, archive older data regional—requires careful TTL policies and federation logic in queries.
- **Egress cost blind spot:** Engineers often forget egress when comparing. Always calculate: (monthly queries) × (avg data per query) × ($0.02/GB) to justify multi-regional.
- **Adjacent: partition pruning + caching.** Even with multi-regional, partitioning by date/location and caching results reduces egress more than storage architecture alone.
