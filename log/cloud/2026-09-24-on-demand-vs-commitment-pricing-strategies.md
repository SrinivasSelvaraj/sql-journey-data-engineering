---
date: 2026-09-24
phase: cloud
topic: On-demand vs commitment pricing strategies
---

# On-demand vs commitment pricing strategies

*Cloud platforms and storage*

## Concept

On-demand pricing charges per unit of compute, storage, or queries executed—you pay only for what you use, with no upfront commitment. Commitment pricing (reserved instances, annual contracts) requires you to pay in advance for a capacity block, offering 20–70% discounts in exchange for lock-in. This matters because a slow query on an on-demand system costs money per second of execution, while a commitment model spreads costs across a fixed period regardless of efficiency.

The trade-off surfaces sharply in data warehouses: Snowflake's on-demand credits burn fast on unoptimized queries; BigQuery's on-demand pricing ($6.25/TB scanned) punishes full-table scans; reserved capacity (slots) forces you to pre-buy throughput but rewards efficient, batched work. Without understanding your pricing model, you optimize for the wrong thing—on-demand favors speed and small result sets, while commitment favors batching and resource utilization.

## Practice

**Problem:** You notice monthly cloud spend spiking unpredictably. A business analyst runs ad-hoc queries joining `job_postings_fact` against three other large tables, scanning billions of rows to find average salaries by location. You're on BigQuery on-demand. How do you identify the cost driver and rewrite the query for efficiency?

```sql
-- INEFFICIENT: scans full tables, ~2TB+ per run
SELECT 
  job_location,
  AVG(salary_year_avg) as avg_salary
FROM job_postings_fact
WHERE job_posted_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 90 DAY)
GROUP BY job_location;

-- EFFICIENT: partition pruning + pre-aggregate + materialized view
CREATE MATERIALIZED VIEW job_salary_summary AS
SELECT 
  job_location,
  AVG(salary_year_avg) as avg_salary,
  COUNT(*) as job_count
FROM job_postings_fact
WHERE job_posted_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 90 DAY)
GROUP BY job_location;

-- Query now scans only the view (~100MB), not raw data
SELECT job_location, avg_salary 
FROM job_salary_summary 
WHERE job_count > 10
ORDER BY avg_salary DESC;
```

## Notes

- **Partition by date**: On-demand systems charge per byte scanned; partitioning your tables on `job_posted_date` lets queries skip entire partitions (partition pruning = immediate savings).
- **Full-table scans are expensive on-demand but "free" under commitment**: If you're on reserved slots, you might miss the incentive to index or filter, wasting allocated capacity.
- **Materialized views and incremental updates are your friends**: Pre-compute aggregates and refresh them nightly rather than scanning raw data 50 times per day.
- **Monitor query execution plans**: Tools like BigQuery's EXPLAIN or Snowflake's QUERY_PROFILE show you bytes scanned; cost attribution starts there, not in the billing invoice.
- **Blended cost matters**: Commitment pricing is only cheaper if you use ≥70% of reserved capacity; monitor utilization monthly to know if you should downgrade or move back to on-demand.
