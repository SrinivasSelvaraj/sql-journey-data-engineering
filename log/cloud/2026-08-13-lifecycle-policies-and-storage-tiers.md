---
date: 2026-08-13
phase: cloud
topic: Lifecycle policies and storage tiers
---

# Lifecycle policies and storage tiers

*Cloud platforms and storage*

## Concept

Lifecycle policies automatically transition data between storage tiers—typically from hot (fast, expensive) to cool (slower, cheap) to archive (slowest, cheapest)—based on age or access patterns. Cloud platforms charge per GB/month for storage *and* per operation (reads, writes, early deletion penalties), so a 2-year-old analytics table sitting in premium tier costs far more than necessary. Without policies, historical data accumulates at full price while queries slow because the platform tries to scan unnecessarily large active datasets. Lifecycle policies reduce both costs and query latency by moving cold data out of the hot path.

The key is matching your access pattern to tier assignment. A fact table with 90% of queries hitting the last 30 days should transition rows older than 60 days to cool tier; archive anything older than 2 years. This requires partitioning by date—unpartitioned tables cannot be selectively tiered. Early deletion penalties (e.g., 30-day minimum in Azure cool tier) mean moving data too aggressively wastes money, but keeping everything hot wastes more.

## Practice

**Problem:** `job_postings_fact` grows by ~50k rows daily. Most reports query the last 90 days; compliance requires 7-year retention. Current queries scanning all 2B rows take 12 minutes. Storage costs $8k/month.

**Solution:**

```sql
-- Partition table by job_posted_date for lifecycle eligibility
CREATE TABLE job_postings_fact (
  job_id INT64,
  job_title_short STRING,
  salary_year_avg FLOAT64,
  job_work_from_home BOOLEAN,
  job_posted_date DATE,
  job_location STRING
)
PARTITION BY job_posted_date
CLUSTER BY job_location;

-- BigQuery lifecycle policy (via Terraform or Cloud Console):
-- Move to cool tier: data older than 90 days
-- Move to archive tier: data older than 2 years
-- Set early deletion warning: 30 days minimum for cool tier

-- Query to verify partition pruning works (scans only last 90 days):
SELECT job_title_short, AVG(salary_year_avg)
FROM job_postings_fact
WHERE job_posted_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 90 DAY)
GROUP BY job_title_short;
```

## Notes

- **Partition key matters most**: Lifecycle policies only work on partitioned tables; an unpartitioned table stays in one tier regardless. Always partition analytics fact tables by date or timestamp.
- **Early deletion penalties bite hard**: Moving data to cool tier, then deleting it after 10 days costs the same as keeping it 30 days. Plan tier transitions around your minimum retention window.
- **Query cost ≠ storage cost**: A query scanning cool-tier data costs more per GB scanned (e.g., $6.25/TB in BigQuery cool vs. $0.02/TB hot), but occurs rarely. Total cost is *storage cost × time + query cost × frequency*—calculate both.
- **Compliance holds override policies**: If regulations require 7-year retention, archive tier is mandatory after year 2. Use retention locks to prevent accidental deletion.
- **Adjacent topics**: columnar compression (Parquet reduces storage 5–10×), partitioning strategy (date vs. geography), and query patterns (why you scan 2B rows instead of 100M)—revisit these before optimizing lifecycle.
