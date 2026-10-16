---
date: 2026-10-16
phase: cloud
topic: Reserved capacity: discount tiers and commitment periods
---

# Reserved capacity: discount tiers and commitment periods

*Cloud platforms and storage*

## Concept

Reserved capacity commitments lock in compute or storage resources at a discount—typically 1–3 year contracts offering 25–70% off on-demand rates. Cloud providers (AWS, GCP, Azure) use tiered discounts: longer commitments and larger upfront purchases yield steeper savings. This matters immediately when you graduate from prototyping to steady-state workloads; a warehouse running the same query suite every day at 9 AM becomes predictable enough to reserve.

The trap is over-committing: you pay whether you use the capacity or not. Without careful measurement of your baseline load, you burn money on unused slots. Conversely, under-committing forces expensive on-demand overflow, canceling savings gains. Query performance itself rarely improves from reservation—what improves is cost predictability and per-query amortization, which affects how you justify downstream infrastructure.

## Practice

**Problem:** You run a daily job at 8 AM that aggregates job postings by location and salary band. The query processes ~2M rows and takes 45 seconds on-demand. Your team runs this same query 250 times per month (roughly 10 per business day). Calculate annual cost difference between pure on-demand and a 1-year reservation.

```sql
-- Baseline on-demand cost estimate
-- Assume BigQuery: $6.25 per TB scanned
-- Query scans ~10 GB per run (5M rows × 2KB avg row)

SELECT
  job_location,
  salary_band,
  COUNT(*) AS job_count,
  AVG(salary_year_avg) AS avg_salary
FROM job_postings_fact
WHERE job_posted_date >= DATE_TRUNC(CURRENT_DATE(), MONTH)
GROUP BY job_location, salary_band
ORDER BY job_count DESC;

-- Cost calculation (pseudocode):
-- On-demand: 250 runs/month × 12 months × 10 GB × $6.25/TB = $187.50/year
-- Reserved 100 slot-months: $2,000/year flat (example), covers ~333 GB/month scanned
-- Break-even at ~32 GB/month. Your 120 GB/month makes reservation worthwhile.
```

The solution: measure your actual monthly scan volume, compare to reservation thresholds, then commit for 1 year if utilization is stable.

## Notes

- **Measurement first:** Track slot/storage usage for 2–4 weeks before committing; cloud cost platforms (CloudZero, Kubecost) automate this but manual logs work too.
- **Flex slots vs. annual:** GCP BigQuery offers monthly flex slots as middle ground; lower commitment risk than 1-year, discount less steep than annual.
- **Idle reservation leakage:** Reserved slots don't auto-scale down during low-traffic periods (weekends, holidays)—budget for that waste or size conservatively.
- **Connects to:** cost allocation (chargeback models), query optimization (smaller scans reduce both on-demand *and* reserved costs), capacity planning (matching team growth to commitments).
- **Revisit quarterly:** business query patterns shift; over-reserved slots from last year's roadmap become sunk cost if demand drops; build review cycles into your cost governance.
