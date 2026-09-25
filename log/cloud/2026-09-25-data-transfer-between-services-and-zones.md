---
date: 2026-09-25
phase: cloud
topic: Data transfer between services and zones
---

# Data transfer between services and zones

*Cloud platforms and storage*

## Concept

Data transfer between services and zones incurs egress charges on most cloud platforms—moving data *out* of a region or between services costs money, while ingress is typically free. This becomes a major cost and performance bottleneck when you query across zones, move large datasets between compute and storage layers, or transfer results to external systems. Without awareness, a "cheap" query can become expensive the moment you pull results across a region boundary or join data that lives in different availability zones.

Performance suffers because cross-zone transfers are subject to network latency and bandwidth throttling, turning a millisecond operation into seconds or minutes. A query that runs in 100ms inside a single zone might take 10+ seconds when the underlying tables span multiple regions. Understanding your data's physical location is as critical as understanding its logical schema.

## Practice

**Problem:** Your job_postings_fact table is replicated across us-east-1 and eu-west-1 for redundancy. A dashboard in us-east-1 queries the entire table daily, but half the data physically lives in eu-west-1. You're charged egress fees and seeing 15-second query times. How do you optimize?

```sql
-- BEFORE: Forces cross-zone transfer
SELECT 
  job_title_short,
  AVG(salary_year_avg) AS avg_salary
FROM job_postings_fact
WHERE job_posted_date >= CURRENT_DATE - INTERVAL '30 days'
GROUP BY job_title_short;

-- AFTER: Co-locate compute with data or use a local cache
-- Option 1: Add a region column and filter to local data
SELECT 
  job_title_short,
  AVG(salary_year_avg) AS avg_salary
FROM job_postings_fact
WHERE job_posted_date >= CURRENT_DATE - INTERVAL '30 days'
  AND region = 'us-east-1'  -- Stays in zone
GROUP BY job_title_short;

-- Option 2: Query a materialized view in us-east-1 instead of the source table
SELECT 
  job_title_short,
  avg_salary
FROM job_postings_agg_daily_mv
WHERE date_key >= CURRENT_DATE - INTERVAL '30 days';
```

## Notes

- **Egress ≠ ingress**: Pulling data *out* of a zone costs $0.02–0.05/GB; pulling *in* is free. This asymmetry makes one-directional queries expensive.
- **Materialized views and read replicas**: Pre-aggregate or replicate hot data into the region where queries run most frequently; update on a schedule.
- **Connection pooling and batch transfers**: Moving 1GB in one transfer costs far less than 1,000 small requests; plan your ETL jobs accordingly.
- **Cross-service transfers hidden in joins**: A Redshift query joining data from S3 in a different region, or BigQuery pulling from Cloud Storage outside its dataset location, both incur transfer costs silently.
- **Adjacent: data locality, caching strategies, and query explain plans** — always check `EXPLAIN` output for network operations and use CloudWatch/BigQuery's query execution details to spot zone hops.
