---
date: 2026-09-04
phase: cloud
topic: Compute optimization: CPU vs memory vs GPU vs accelerators
---

# Compute optimization: CPU vs memory vs GPU vs accelerators

*Cloud platforms and storage*

## Concept

Cloud compute resources come with different cost and performance profiles. CPU handles general workloads and is the default; memory (RAM) scales linearly and is often the bottleneck in joins and aggregations; GPU accelerates matrix operations and is critical for ML workloads; specialized accelerators (TPU, FPGA) optimize specific patterns but require architectural buy-in. Understanding which resource is constraining your query prevents overpaying for the wrong dimension—a poorly-written join might waste $100/hour on CPU when the real problem is insufficient memory to avoid disk spills.

Slow queries rarely fail visibly; they just drain your budget. If a 10GB aggregation runs on a 4GB-memory instance, it spills to disk repeatedly, becoming 100× slower. If you run sequential loops instead of vectorized operations on CPU, you leave GPU sitting idle while paying full price. Cloud bills expose these inefficiencies ruthlessly: same query, same data, different instance shape = wildly different costs and latency.

## Practice

**Problem:** You're aggregating salary data by job title for 50 million postings. The query completes but takes 8 minutes on a 4-core/16GB instance but only 90 seconds on an 8-core/64GB instance. Why, and what's the real bottleneck?

```sql
-- Slow version: memory spill due to large GROUP BY
SELECT 
  job_title_short,
  COUNT(*) as job_count,
  AVG(salary_year_avg) as avg_salary,
  COUNT(CASE WHEN job_work_from_home THEN 1 END) as remote_count
FROM job_postings_fact
WHERE job_posted_date >= '2024-01-01'
GROUP BY job_title_short
ORDER BY job_count DESC;

-- Fast version: pre-filter and use approx aggregates if needed
SELECT 
  job_title_short,
  COUNT(*) as job_count,
  AVG(salary_year_avg) as avg_salary,
  SUM(CASE WHEN job_work_from_home THEN 1 ELSE 0 END) as remote_count
FROM job_postings_fact
WHERE job_posted_date >= '2024-01-01'
  AND salary_year_avg IS NOT NULL
GROUP BY job_title_short
ORDER BY job_count DESC
LIMIT 100;
```

The first version creates a massive hash table for every unique job title; on 16GB, it spills to disk. The second narrows the dataset and caps output, keeping the working set in memory.

## Notes

- **Memory is the hidden villain:** CPU cores sit idle waiting for data from disk. Monitor spill metrics (Spark shuffle write bytes, Redshift query plan memory usage) before adding cores.
- **GPU/TPU ROI is poor for SQL:** Unless you're running ML inference or matrix-heavy analytics, GPUs waste money. Confirm your workload is embarrassingly parallel (deep learning, image processing) before upgrading.
- **Instance right-sizing compounds:** A 4-core/128GB instance wastes memory on light workloads; an 8-core/16GB instance causes spilling. Cloud cost optimization is 70% picking the right shape, 30% query tuning.
- **Cross-platform comparison is essential:** Same query on Snowflake (shared compute pool) vs. Redshift (reserved nodes) vs. BigQuery (on-demand slots) produces different costs even for identical SQL—measure your actual platform.
- **Cardinality and skew matter more than volume:** 1M rows with 100K distinct job titles is harder than 100M rows with 50 distinct titles; the GROUP BY hash table size drives memory pressure, not raw row count.
