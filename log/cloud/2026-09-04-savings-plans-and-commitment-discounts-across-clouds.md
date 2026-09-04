---
date: 2026-09-04
phase: cloud
topic: Savings plans and commitment discounts across clouds
---

# Savings plans and commitment discounts across clouds

*Cloud platforms and storage*

## Concept

Savings plans and commitment discounts are mechanisms offered by cloud providers (AWS, Azure, GCP) to reduce compute and storage costs in exchange for upfront financial commitment or usage guarantees. Rather than paying on-demand rates, you commit to a dollar amount (flexible) or specific instance type/region (standard) for 1–3 years, receiving 20–70% discounts. This matters because cloud bills often grow invisibly—queries scan unnecessary data, storage accumulates unused backups, and on-demand rates compound quickly at scale. Without commitment planning, your data engineering pipeline becomes expensive and slow; with poor commitment choices, you over-provision resources you don't use or under-provision and lose discount benefits. The key trade-off is predictability and cost savings versus flexibility to scale up or shift workloads.

## Practice

**Problem:** Your analytics team runs daily aggregations on job postings, but you notice query costs spike unpredictably. You want to estimate baseline compute costs to justify a 3-year commitment discount, assuming you'll run equivalent queries at least 20 times per month.

```sql
-- Estimate baseline usage: count rows scanned per daily aggregation
SELECT 
  DATE_TRUNC(job_posted_date, MONTH) AS month,
  COUNT(*) AS total_jobs,
  COUNT(DISTINCT job_location) AS unique_locations,
  ROUND(AVG(salary_year_avg), 2) AS avg_salary,
  SUM(CASE WHEN job_work_from_home THEN 1 ELSE 0 END) AS remote_jobs,
  ROUND((COUNT(*) * 8) / 1024.0, 2) AS approx_gb_scanned
FROM job_postings_fact
WHERE job_posted_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 12 MONTH)
GROUP BY month
ORDER BY month DESC;

-- Output: If avg is 50 GB/query × 20 queries/month × 12 months = 12,000 GB/year
-- Use this volume to model commitment discount ROI
```

This query reveals your actual data footprint. Multiply by query frequency and compare on-demand costs versus 1- or 3-year commitment tiers to decide whether to commit.

## Notes

- **Over-committing locks you in:** Choose flexible or smaller commitments first if your workload is experimental or seasonal; scale up once patterns stabilize.
- **Commitment doesn't cover everything:** Discounts apply to compute and reserved storage, but data transfer, API calls, and specialized services (ML, analytics) often remain on-demand—audit line items separately.
- **Region/instance mismatch wastes discounts:** A commitment to `us-east-1` doesn't help if you query from `eu-west-1`; ensure your ETL architecture and commitment zones align.
- **Connects to query optimization:** Before committing, profile your actual query patterns with `EXPLAIN` and cost estimation tools; slow or redundant queries inflate your baseline and waste committed capacity.
- **Revisit quarterly:** Cloud pricing changes, workloads shift, and new commitment terms emerge—reassess whether your commitment still matches reality rather than letting stale commitments drift.
