---
date: 2026-08-24
phase: cloud
topic: Network egress costs and how to avoid surprises
---

# Network egress costs and how to avoid surprises

*Cloud platforms and storage*

## Concept

Network egress—data leaving a cloud region or crossing region/provider boundaries—is often the largest hidden cost in data engineering pipelines. Cloud providers charge per GB transferred out, while ingress and intra-region traffic are typically free. A query that scans efficiently but pulls results across regions, or a pipeline that streams data to an external API, can cost orders of magnitude more than the compute itself. This is especially brutal in analytical workloads where you might scan terabytes to return kilobytes, or when joining datasets split across regions without realizing the cross-region penalty.

Without attention to egress, a cheap-looking query in a dev environment becomes a budget crisis in production. Many engineers discover this only after the bill arrives. Egress costs also function as a proxy for architectural problems: unnecessary data movement often indicates missing indexes, poor partitioning, or services deployed in the wrong region. Controlling egress forces you to think about data residency, compression, and whether a result really needs to leave the database.

## Practice

**Problem:** Your analytics team queries job postings from multiple cloud regions and exports results to a third-party reporting tool daily. The query filters for remote work postings from the last 30 days, but the reporting tool is in a different AWS region, causing unnecessary egress charges.

```sql
-- INEFFICIENT: Exports all columns, uncompressed, across regions
SELECT 
  job_id, job_title_short, salary_year_avg, job_work_from_home, job_posted_date, job_location
FROM job_postings_fact
WHERE job_work_from_home = TRUE
  AND job_posted_date >= CURRENT_DATE - INTERVAL '30 days'
ORDER BY job_posted_date DESC;

-- EFFICIENT: Select only needed columns, pre-aggregate, use co-located export
SELECT 
  job_title_short,
  COUNT(*) as posting_count,
  ROUND(AVG(salary_year_avg), 0) as avg_salary
FROM job_postings_fact
WHERE job_work_from_home = TRUE
  AND job_posted_date >= CURRENT_DATE - INTERVAL '30 days'
GROUP BY job_title_short
ORDER BY posting_count DESC;
-- Export via S3 bucket in same region, then replicate to reporting tool's region as needed
```

The second query reduces egress by ~90%: fewer columns, pre-aggregated, and materialized to local storage before crossing regions.

## Notes

- **Column projection matters**: Selecting 50 columns when you need 5 multiplies egress cost unnecessarily; always `SELECT` only what the downstream system requires.
- **Aggregation before export**: GROUP BY, LIMIT, and pre-filtering push computation closer to the data and shrink the result set before it moves.
- **Partitioning and co-location**: Store related datasets in the same region or availability zone; if your data is already split across regions, query only the relevant partition.
- **Compression and format choice**: Parquet with Snappy compression can cut egress by 50–80% compared to uncompressed CSV; negotiate with your export tool on format.
- **Adjacent topics**: Data residency compliance, data replication strategy, cross-region disaster recovery, and query profiling tools (EXPLAIN plans show scan size, not just runtime).
