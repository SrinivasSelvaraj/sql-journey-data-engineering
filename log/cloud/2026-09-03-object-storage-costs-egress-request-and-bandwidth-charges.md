---
date: 2026-09-03
phase: cloud
topic: Object storage costs: egress, request and bandwidth charges
---

# Object storage costs: egress, request and bandwidth charges

*Cloud platforms and storage*

## Concept

Object storage (S3, GCS, Azure Blob) charges accumulate in three ways beyond storage size: **egress** (data leaving the region), **request fees** (API calls), and **bandwidth** (inter-region transfer). Egress is often the largest hidden cost—transferring 1 TB across regions can cost $20–50 depending on provider and destination. Request charges ($0.0004–0.004 per 1000 calls) multiply fast with frequent small reads; a scan of 10 million objects costs $40–400 in request fees alone. These costs matter because a "slow query" isn't always latency—it's often that your job is making thousands of unnecessary API calls or pulling data cross-region, draining budget while running. Understanding these dimensions prevents both performance collapse and bill shock.

## Practice

**Problem:** You query job postings daily from S3 in us-east-1, but your analytics team in eu-west-1 reads the results. The raw data is 50 GB, you filter to 5 GB, and run 20 queries daily. Calculate egress cost and identify the culprit.

**Solution:**
```sql
-- Egress cost: 5 GB × 20 queries/day × 30 days × $0.02/GB (us-east-1 to eu-west-1)
-- = 5 × 20 × 30 × 0.02 = $600/month just for egress
-- Request cost: 50 GB ÷ 128 MB per request ≈ 400 requests per query
-- = 400 × 20 × 30 × $0.0004 = $96/month

-- Fix: cache filtered results in eu-west-1 or replicate data
CREATE TABLE job_postings_eu AS
SELECT job_id, job_title_short, salary_year_avg, job_work_from_home, job_posted_date, job_location
FROM job_postings_fact
WHERE job_posted_date >= CURRENT_DATE - INTERVAL 90 DAY
  AND job_location IS NOT NULL;
-- Now queries hit local storage, eliminating $600 egress; trade storage redundancy (~$1.50/month) for 400× cost savings.
```

## Notes

- **Request fee blindness:** Listing 1M objects (common in incremental jobs) costs $400 in requests alone; use object prefixes and lifecycle policies to reduce API surface.
- **Egress is regional:** Free within zone, expensive cross-region; design pipelines to process data where it lands.
- **Connects to:** query optimization (fewer full scans = fewer requests), data partitioning (reduce objects scanned), and CDN strategy (offload egress to cached edge).
- **Common mistake:** Assuming storage cost dominates; in mature systems, egress + requests often exceed storage 3–5×.
- **Revisit:** S3 Select and columnar formats (Parquet) reduce egress by pushing filtering to the storage layer.
