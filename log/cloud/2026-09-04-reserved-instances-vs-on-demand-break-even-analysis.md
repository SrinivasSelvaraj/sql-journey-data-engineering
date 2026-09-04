---
date: 2026-09-04
phase: cloud
topic: Reserved instances vs on-demand: break-even analysis
---

# Reserved instances vs on-demand: break-even analysis

*Cloud platforms and storage*

## Concept

Reserved instances (RIs) require upfront commitment (1–3 years) for lower per-hour rates, while on-demand instances charge full price with no commitment. Break-even analysis determines the point where RI savings exceed the upfront cost. For example, if an on-demand compute instance costs $0.50/hour and an RI costs $2,000 upfront plus $0.20/hour, you break even at 6,667 hours (~9 months). This matters because workloads with predictable, sustained usage (batch jobs, always-on dashboards, production databases) save 30–70% with RIs, while bursty or experimental workloads waste money on unused reservations. Without this calculation, teams either overpay for steady workloads or lock capital into unused reservations.

## Practice

**Problem:** Your analytics team runs a daily ETL job that processes job postings data. The job runs 24/7 on a `db.m6i.2xlarge` RDS instance costing $1.52/hour on-demand. You're considering a 1-year RI at $7,700 upfront + $0.55/hour. Should you buy the RI? Calculate break-even and total annual cost for both options.

```sql
-- Break-even analysis for RDS Reserved Instance
WITH cost_comparison AS (
  SELECT
    'on_demand' AS pricing_model,
    0 AS upfront_cost,
    1.52 AS hourly_rate,
    (24 * 365) AS annual_hours,
    1.52 * (24 * 365) AS annual_cost
  
  UNION ALL
  
  SELECT
    'reserved_1yr' AS pricing_model,
    7700 AS upfront_cost,
    0.55 AS hourly_rate,
    (24 * 365) AS annual_hours,
    7700 + (0.55 * (24 * 365)) AS annual_cost
)
SELECT
  pricing_model,
  upfront_cost,
  hourly_rate,
  annual_hours,
  ROUND(annual_cost, 2) AS annual_cost,
  ROUND(7700 / (1.52 - 0.55), 2) AS breakeven_hours,
  ROUND(7700 / (1.52 - 0.55) / 24, 2) AS breakeven_days
FROM cost_comparison
ORDER BY annual_cost;
```

**Result:** On-demand costs $13,323/year; RI costs $12,530/year (savings of $793, or 6%). Break-even occurs at ~10,989 hours (~458 days). If the job runs continuously, buy the RI.

## Notes

- **Mistake:** Calculating break-even based on list price instead of *your actual negotiated on-demand rate*; use CloudWatch or billing reports to verify real usage costs before committing.
- **Mistake:** Forgetting to account for scaling; if your workload grows mid-year, RIs don't scale—you'll still pay on-demand for excess capacity, offsetting savings.
- **Adjacent topic:** Spot instances (60–90% cheaper) are worth pairing with RIs for fault-tolerant batch jobs; RIs cover baseline load, Spot handles spikes.
- **Worth revisiting:** Commitment-level decisions (1-yr vs 3-yr) depend on cloud roadmap uncertainty and forecasting confidence; 3-yr RIs cost less per hour but lock you in longer.
- **Practical connector:** Break-even analysis feeds into capacity planning and chargeback models—knowing true cost per job informs whether to optimize queries or buy more compute.
