---
date: 2026-09-23
phase: cloud
topic: Storage class transitions: hot, warm, cold, archive
---

# Storage class transitions: hot, warm, cold, archive

*Cloud platforms and storage*

## Concept

Storage class transitions move data between cost and access tiers automatically based on age or access patterns. Cloud providers (AWS S3, Azure Blob, GCP Cloud Storage) charge drastically different rates: hot storage is expensive but instantly queryable; warm is intermediate; cold is cheap but retrieval has latency and egress costs; archive is for compliance holds and rarely accessed data. Without transitions, you pay premium rates for data that hasn't been queried in months—a common leak in data warehouses where historical fact tables sit untouched.

The transition decision hinges on your query access patterns and SLA. If you query job posting data daily for the last 90 days but only monthly for older data, transition everything beyond 90 days to warm, then to cold at 1 year. This cuts storage costs 60–80% with minimal query impact if you're willing to accept a few seconds of retrieval latency for older aggregations. Without thoughtful transitions, a 5TB historical fact table costs $115/month in hot storage; transitioned intelligently, it costs $12/month.

## Practice

**Problem:** Your `job_postings_fact` table grows 50GB monthly. Analysts query last 3 months heavily (daily dashboards) but access older data rarely (quarterly trend reports). Hot storage costs $23/TB/month; cold costs $4/TB/month. Design a transition strategy to reduce costs without breaking dashboards.

**Solution:**

```sql
-- Partition fact table by job_posted_date to enable per-partition transitions
CREATE TABLE job_postings_fact (
    job_id INT,
    job_title_short VARCHAR(100),
    salary_year_avg DECIMAL(10,2),
    job_work_from_home BOOLEAN,
    job_posted_date DATE,
    job_location VARCHAR(100)
)
PARTITION BY RANGE (YEAR(job_posted_date), MONTH(job_posted_date));

-- Partitions < 90 days old: HOT (queryable immediately)
-- Partitions 90–365 days old: WARM (moved automatically, ~100ms retrieval)
-- Partitions > 365 days old: COLD (moved automatically, acceptable for quarterly reports)

-- Example transition rule (pseudocode for AWS S3 Lifecycle Policy):
-- IF object_age > 90 days THEN transition to STANDARD_IA
-- IF object_age > 365 days THEN transition to GLACIER
-- IF object_age > 2555 days THEN transition to DEEP_ARCHIVE

-- Query pattern 1: Dashboard (last 90 days, hot access)
SELECT job_title_short, AVG(salary_year_avg)
FROM job_postings_fact
WHERE job_posted_date >= CURRENT_DATE - INTERVAL 90 DAY
GROUP BY job_title_short;

-- Query pattern 2: Trend report (all history, acceptable latency)
SELECT YEAR(job_posted_date), COUNT(*)
FROM job_postings_fact
GROUP BY YEAR(job_posted_date);
```

## Notes

- **Partition key matters most:** If your warehouse can't partition by date or access pattern, transitions help less; unpartitioned tables require full scans that may time out retrieving from cold storage.
- **Egress costs hide the savings:** Moving data to cold storage is cheap, but querying it incurs retrieval + egress charges ($0.02–0.05/GB on AWS). A 10GB cold query costs $200–500 in egress alone; factor this into transition thresholds.
- **Archive for compliance, not performance:** Deep archive (year+ latency) is only for regulatory holds or backups; never transition active historical data there if you need quarterly reporting.
- **Connects to:** partitioning strategy, query predicate pushdown, columnar formats (Parquet compresses cold data 10:1), and monitoring slow queries by storage tier.
- **Revisit:** Check quarterly whether your 90-day "hot" threshold still matches analyst behavior; schema changes or new dashboards can shift access patterns, rendering old transitions counterproductive.
