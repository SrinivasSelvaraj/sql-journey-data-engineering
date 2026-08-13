---
date: 2026-08-13
phase: cloud
topic: Separation of storage and compute
---

# Separation of storage and compute

*Cloud platforms and storage*

## Concept

Separation of storage and compute means decoupling where data lives from where queries execute. In modern cloud platforms (Snowflake, BigQuery, Redshift Spectrum), you pay separately for storage (GB/month) and compute (query execution time or slots). This matters because a query can be slow due to inefficient compute (poorly written SQL, wrong index strategy) or inefficient storage access (reading unnecessary columns, scanning cold data tiers), and you need to distinguish between them to optimize costs and performance.

Without separation, you're forced into either over-provisioning (buying a powerful cluster that sits idle) or under-provisioning (queries timeout during peaks). With separation, you scale compute independently of storage—a small query reads from shared storage using minimal resources, while a large aggregation can burst compute without moving data or waiting for infrastructure to spin up.

The key insight: just because a query is *fast* doesn't mean it's *cheap*. A query might complete in 2 seconds but scan 500 GB of uncompressed data, costing $2.50. Conversely, a query running for 30 seconds on 1 GB of compressed, partitioned data might cost $0.10.

## Practice

**Problem:** Your analytics team queries `job_postings_fact` daily to find average salary by job title and work-from-home status. The query runs in 8 seconds but costs $3 per execution. You're investigating why.

```sql
-- SLOW & EXPENSIVE: Scans entire table, all columns
SELECT 
  job_title_short,
  job_work_from_home,
  AVG(salary_year_avg) as avg_salary
FROM job_postings_fact
WHERE job_posted_date >= CURRENT_DATE - INTERVAL 90 DAY
GROUP BY job_title_short, job_work_from_home;

-- FAST & CHEAP: Partitioned on job_posted_date, only necessary columns
-- Assumes table is partitioned by job_posted_date and clustered by job_title_short
SELECT 
  job_title_short,
  job_work_from_home,
  AVG(salary_year_avg) as avg_salary
FROM job_postings_fact
WHERE job_posted_date >= CURRENT_DATE - INTERVAL 90 DAY
GROUP BY job_title_short, job_work_from_home;
-- Same query, but infrastructure (partitioning) reduces scan from 5 TB to 400 GB → $0.30
```

The difference isn't the SQL—it's whether storage is organized to support the access pattern.

## Notes

- **Partition pruning is free:** Add `PARTITION BY job_posted_date` when creating the table. Queries with date filters automatically skip irrelevant partitions, cutting costs by 80%+ with zero query rewrite.
- **Clustering hints at compute waste:** If a query completes instantly but the bill is high, you're likely reading too many columns or scanning uncompressed data. Compression (Snappy, Zstd) and column pruning solve this.
- **Slot vs. on-demand tradeoff:** BigQuery slots commit you to fixed compute cost; on-demand charges per TB scanned. Separation lets you choose the model that fits your query pattern and budget.
- **Adjacent concept—data warehouse schema design:** Fact tables (normalized, many joins) often hide storage costs because compute must read many tables. Denormalized schemas (wide fact tables) reduce compute but increase storage; the separation model forces you to measure both.
- **Revisit this when:** Querying fails due to "slot pool limit exceeded" (compute bottleneck) or when a 1-TB query suddenly costs $5 instead of $0.50 (storage access pattern changed; time to re-partition).
