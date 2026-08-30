---
date: 2026-08-30
phase: modelling
topic: Partition key selection for query and storage optimization
---

# Partition key selection for query and storage optimization

*Data modelling and warehousing*

## Concept

A partition key divides a table into logical or physical segments, typically on a column with high cardinality and strong query patterns (dates, regions, user IDs). Choosing well means queries scan only relevant partitions, dramatically reducing I/O and compute costs—especially in cloud warehouses where you pay per byte scanned. Poor choices force full table scans even on filtered queries, inflate storage overhead, and create skewed partition sizes that stall parallel execution.

Partition keys should align with your most frequent filter predicates. If 80% of queries filter by `job_posted_date`, partition there. If you partition by low-cardinality columns (e.g., job_title_short with 5 unique values), you create imbalanced partitions; if you partition by too many distinct values, you fragment metadata and lose performance gains. The sweet spot is usually date ranges, geographic regions, or tenant IDs that naturally segment your data and match real access patterns.

## Practice

**Problem:** Your analytics team runs daily reports filtering `job_postings_fact` by the last 30 days, and they scan the full 2-year table every time, costing $200/month in unnecessary cloud warehouse queries.

```sql
-- Partition by job_posted_date (monthly granularity)
CREATE TABLE job_postings_fact (
  job_id INT,
  job_title_short VARCHAR,
  salary_year_avg DECIMAL(10,2),
  job_work_from_home BOOLEAN,
  job_posted_date DATE,
  job_location VARCHAR
)
PARTITION BY RANGE(YEAR(job_posted_date), MONTH(job_posted_date));

-- Query now prunes to 1 month of partitions, not 24 months
SELECT job_title_short, AVG(salary_year_avg)
FROM job_postings_fact
WHERE job_posted_date >= CURRENT_DATE - INTERVAL 30 DAY
GROUP BY job_title_short;
```

## Notes

- **Cardinality trap:** Avoid partitioning on Boolean or low-cardinality enums (like `job_work_from_home`); create clustered indexes on those instead.
- **Skew risk:** If jobs cluster in certain months (hiring surges), partition sizes become uneven; consider dynamic partitioning or subpartitioning by region.
- **Clustering complement:** Partition for access patterns (rows to exclude), cluster for query speed within selected partitions (sort within).
- **Maintenance cost:** More partitions = more metadata overhead; monthly or quarterly granularity usually beats daily for fact tables; revisit as data volume grows.
- **Adjacent skill:** Time-series bucketing and range pruning in query engines; also connects to incremental loading and CDC strategies (new partitions for new data).
