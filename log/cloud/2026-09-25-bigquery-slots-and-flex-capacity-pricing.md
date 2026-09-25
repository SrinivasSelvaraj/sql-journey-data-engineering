---
date: 2026-09-25
phase: cloud
topic: BigQuery slots and flex capacity pricing
---

# BigQuery slots and flex capacity pricing

*Cloud platforms and storage*

## Concept

BigQuery pricing operates on two models: on-demand (pay per TB scanned) and slots (fixed hourly cost for reserved compute). Slots are pre-purchased compute capacity (100-slot minimum, ~$2,400/month) that covers all queries and operations in a project, while flex slots allow hourly commitment without monthly minimums. Query slowness often stems from either insufficient slots (queuing) or data scanning inefficiency—slots solve the first problem, but not the second. Understanding which model you're on is critical because a slow query under on-demand might cost you $100+ due to full table scans, while the same query on slots may already be paid for but still returns late results due to poor partition or clustering strategy.

Slots measure execution time, not data volume. If you have 100 slots and run four parallel 4-minute queries, they complete in 4 minutes total. If you run one 100-minute query, slots are fully consumed for that duration. This means slots benefit repeating workloads and concurrent query patterns, but a single inefficient scan still blocks others. The real trap: slots create a false sense of cost control while masking structural query problems that flex slots will expose the moment you drop back to on-demand billing.

## Practice

**Problem:** Your analytics team runs daily reports on `job_postings_fact` (500 GB uncompressed). The salary report queries all rows to calculate averages by location, taking 8 minutes on flex slots. You're considering annual slots but want to confirm this is necessary.

**Solution:** Add clustering and partitioning, then measure true slot consumption:

```sql
-- Original slow query (full scan)
SELECT 
  job_location,
  AVG(salary_year_avg) as avg_salary,
  COUNT(*) as job_count
FROM job_postings_fact
WHERE job_posted_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 90 DAY)
GROUP BY job_location;

-- Optimized: partition by date, cluster by location
CREATE OR REPLACE TABLE job_postings_fact
PARTITION BY DATE(job_posted_date)
CLUSTER BY job_location AS
SELECT * FROM job_postings_fact;

-- Same query now scans only 90 days of data (~50 GB vs 500 GB)
-- Slot time drops from 8 min to ~45 sec; flex cost drops from $250 to ~$25
-- Decision: flex slots remain sufficient; no annual commitment needed
```

## Notes

- **Slot consumption ≠ query cost.** A 10-minute query on 100 slots costs the same whether it scans 1 GB or 100 GB; on-demand billing is the opposite. Never assume slots justify unoptimized queries.
- **Flex slots are the diagnostic tool.** Before committing to annual slots, run your workload on hourly flex to measure true slot-hours needed; multiply by ~$6/slot-hour to validate ROI.
- **Partitioning and clustering are free optimization.** They reduce bytes scanned without consuming compute; always apply them before scaling slots horizontally.
- **Reservation scope matters.** Slots apply to a project; if you have dev, staging, and prod projects, one badly tuned dev query can starve production queries of compute.
- **Adjacent concern: materialized views and BI Engine cache.** These layer *before* slots and can cut slot demand by 50–90% for repetitive dashboards; evaluate before buying slots.
