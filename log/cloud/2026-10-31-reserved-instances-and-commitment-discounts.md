---
date: 2026-10-31
phase: cloud
topic: Reserved instances and commitment discounts
---

# Reserved instances and commitment discounts

*Cloud platforms and storage*

## Concept

Reserved instances (RIs) and commitment discounts are purchasing models where you commit to using a certain amount of cloud compute, storage, or database capacity over a fixed term (1–3 years) in exchange for 20–70% discounts versus on-demand pricing. Without them, variable workloads can become expensive quickly; with them, you trade flexibility for predictability. The key tension: overcommitting leaves you paying for unused capacity, while undercommitting means you pay full on-demand rates for overflow—so accurate baseline forecasting matters.

For data engineering specifically, RIs apply to compute (BigQuery slots, Redshift reserved nodes), storage (S3, GCS at volume tiers), and databases (RDS, DynamoDB). A slow query often isn't just a code problem; it's a resource contention problem born from inadequate capacity planning. If your RI commitment is too small, queries queue. If too large, you're subsidizing idle resources. Understanding your cost structure forces you to profile actual usage patterns and identify whether slowness is architectural or financial.

## Practice

**Problem:** Your analytics team runs daily aggregations on `job_postings_fact` that take 90 seconds on-demand but you're seeing them timeout in production. You suspect cost is driving underprovisioned capacity. Forecast monthly query cost and determine if a 1-year RI would be justified.

```sql
-- Calculate daily query cost and RI ROI
WITH daily_scans AS (
  SELECT
    CURRENT_DATE() as analysis_date,
    COUNT(*) as row_count,
    ROUND(COUNT(*) * 200 / 1e9, 2) as gb_scanned  -- approximate bytes per row
  FROM job_postings_fact
  WHERE job_posted_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY)
)
SELECT
  gb_scanned,
  ROUND(gb_scanned * 6.25, 2) as daily_cost_usd,  -- $6.25/TB on-demand
  ROUND(gb_scanned * 6.25 * 30, 2) as monthly_cost_usd,
  ROUND(gb_scanned * 6.25 * 365, 2) as annual_cost_usd,
  ROUND((gb_scanned * 6.25 * 365) * 0.33, 2) as annual_cost_with_1yr_ri,  -- 67% discount
  ROUND((gb_scanned * 6.25 * 365) * 0.33 / 12, 2) as monthly_amortized_ri_cost
FROM daily_scans;
```

If annual on-demand cost exceeds $10k, a 1-year commitment typically breaks even within 6–8 months.

## Notes

- **Overcommitment trap:** Forecast based on 90th percentile usage, not peak. Your March hiring surge shouldn't lock you into 12 months of excess capacity.
- **Blended rate blindness:** RIs often hide in cloud bills as discounts applied to entire account; audit which workloads actually benefit vs. which subsidize others.
- **Flex slots vs. flat commitment:** BigQuery Flex Slots charge per 100ms, useful for bursty queries; RIs suit baseline predictable loads. Mix both if your DAG has steady + spike patterns.
- **Regional arbitrage:** On-demand and RI prices vary by region; committing to a region locks you in—verify data locality assumptions first.
- **Connects to:** capacity planning, query profiling (EXPLAIN/ANALYZE), workload cost attribution, and auto-scaling triggers for managed services.
