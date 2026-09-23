---
date: 2026-09-23
phase: cloud
topic: Reserved capacity and commitment discounts
---

# Reserved capacity and commitment discounts

*Cloud platforms and storage*

## Concept

Reserved capacity and commitment discounts are pricing models offered by cloud platforms (AWS, GCP, Azure) where you pay upfront for guaranteed compute or storage resources over a fixed term (1–3 years) in exchange for 30–70% cost savings versus on-demand rates. This is critical for data engineering because query performance and cost are often intertwined: reserved capacity ensures your jobs don't get throttled during peak load, while commitment discounts prevent surprise bills when scaling analytics workloads. Without reservations, you face two risks: unpredictable spikes in cost when demand surges, and query queuing or failure when on-demand slots are exhausted (common in BigQuery, Redshift, and Snowflake).

The trade-off is inflexibility—you must forecast your minimum baseline usage accurately. Overcommit and you pay for unused capacity; undercommit and you revert to expensive on-demand rates for overflow queries. Most data teams find the sweet spot by analyzing historical query volume and cost patterns, then reserving 60–80% of peak concurrent needs while allowing on-demand overflow for spikes.

## Practice

**Problem:** Your job_postings_fact table grows by 50K rows daily. Analysts run hourly salary aggregations and location-based reports. On-demand Snowflake costs have hit $8K/month with unpredictable spikes. You need to estimate whether a 1-year capacity commitment will save money.

```sql
-- Step 1: Measure current on-demand cost and concurrency
SELECT
  DATE_TRUNC('hour', job_posted_date) AS hour_posted,
  COUNT(DISTINCT job_id) AS jobs_posted,
  APPROXIMATE_PERCENTILE_CONT(salary_year_avg, 0.5) AS median_salary
FROM job_postings_fact
WHERE job_posted_date >= CURRENT_DATE - INTERVAL '90 days'
GROUP BY 1
ORDER BY 1 DESC;

-- Step 2: Estimate baseline vs. peak compute usage
SELECT
  'baseline' AS usage_tier,
  PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY hourly_credits) AS p25_credits,
  'peak' AS usage_tier_2,
  PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY hourly_credits) AS p95_credits
FROM (
  SELECT
    DATE_TRUNC('hour', job_posted_date) AS hour_posted,
    COUNT(*) / 100.0 AS hourly_credits  -- rough estimate: 100 rows ≈ 1 credit
  FROM job_postings_fact
  WHERE job_posted_date >= CURRENT_DATE - INTERVAL '90 days'
  GROUP BY 1
);

-- Step 3: Calculate payback: reserve at p50, keep on-demand for p95 overflow
-- Assumption: $4/credit on-demand, $1.20/credit reserved (70% discount)
-- If p50 ≈ 150 credits/hr and p95 ≈ 400 credits/hr:
-- Reserved annual cost = 150 * 730 hrs/yr * $1.20 = $131,400
-- On-demand savings = (400 - 150) * 730 * ($4 - $1.20) = $608,100 avoided at peak
```

## Notes

- **Forecast conservatively**: Use 90-day or 1-year historical percentiles (p50, p75) for reservation size, not peak, or you lock in dead capacity during quiet periods.
- **Multi-cluster is your escape hatch**: Snowflake and Redshift let you scale clusters dynamically; reserve the base cluster, spin up transient ones for spikes to avoid overcommitment.
- **Commitment discounts pair with storage**: BigQuery and Redshift offer separate commitments for compute and storage; storage is more predictable (reserve 100%), compute needs headroom (reserve 60–80%).
- **Watch query patterns by job_title_short**: Different teams may have distinct peak times (e.g., HR reports mid-month, exec dashboards EOD). Pool reservations across teams or use cost allocation tags to right-size per-group commitments.
- **Revisit quarterly**: Usage patterns shift; re-baseline every 3 months against actual spend and adjust reservations to avoid paying premium on-demand rates that signal underreserved capacity.
