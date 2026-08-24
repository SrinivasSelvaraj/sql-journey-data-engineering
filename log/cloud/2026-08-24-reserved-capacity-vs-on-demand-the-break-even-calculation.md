---
date: 2026-08-24
phase: cloud
topic: Reserved capacity vs on-demand: the break-even calculation
---

# Reserved capacity vs on-demand: the break-even calculation

*Cloud platforms and storage*

## Concept

Reserved capacity (RIs, commitments, reserved slots) locks you into a fixed resource allocation at a discount—typically 25–40% cheaper than on-demand—but you pay upfront or monthly whether you use it or not. On-demand pricing is pay-as-you-go: higher per-unit cost, but zero waste if workload is unpredictable. The break-even calculation asks: at what usage threshold does the upfront discount outweigh the on-demand premium?

Break-even matters most when your workload has a predictable *baseline* (e.g., daily reports, continuous ETL) but also spikes unpredictably. Running everything on-demand wastes money on idle capacity; running everything on reserved capacity forces you to pay for peaks you don't always hit. The right strategy is hybrid: reserve the floor, burst on-demand above it.

Without this calculation, teams either over-commit (paying for unused reserved slots) or under-commit (missing cost optimization and paying full on-demand rates on most traffic). Either way, you're leaving money on the table and making cloud budgets unpredictable.

## Practice

**Problem:** You run a BigQuery job daily that scans `job_postings_fact` to generate salary insights. On-demand costs $6.25 per TB scanned. A 1-year commitment for equivalent capacity costs $10,000 upfront, supports 100 TB/month of queries, and your average scan is 2 TB per run (22 business days/month = 44 TB/month). Should you buy the commitment?

```sql
-- Calculate on-demand cost for 44 TB/month
SELECT 
  44 * 6.25 AS monthly_on_demand_cost,
  44 * 6.25 * 12 AS annual_on_demand_cost;
-- Result: $275/month, $3,300/year

-- Commitment cost
SELECT 10000 AS annual_commitment_cost;

-- Break-even: commitment pays for itself if annual usage exceeds:
SELECT 10000 / 6.25 AS breakeven_tb_per_year;
-- Result: 1,600 TB/year or ~133 TB/month

-- Your usage is 44 TB/month (528 TB/year) << 1,600 TB/year
-- Decision: Do NOT buy the commitment; stay on-demand.
-- Savings: $3,300/year vs $10,000 upfront.
```

## Notes

- **Common mistake:** Committing based on *peak* usage instead of *baseline*. If your workload hits 500 TB one month, don't reserve for 500 TB year-round; reserve for your consistent 60 TB and burst the rest on-demand.
- **Idle capacity is real cost:** Reserved slots you don't fill each month are pure waste. Monitor actual utilization monthly against your commitment to detect mis-sizing early.
- **Related: autoscaling and slots vs scan pricing.** BigQuery and Snowflake offer flex slots and autoscaling; these bridge on-demand and reserved by letting you scale reserve size dynamically. Recalculate break-even if using these products.
- **Commitment lengths matter.** 1-year commitments are cheaper per unit than monthly, but 3-year commitments (where available) are cheaper still. Trade flexibility for savings based on how stable your baseline is.
- **Don't forget egress and storage.** Break-even applies to compute, but reserved capacity rarely covers egress and storage; factor those costs separately to get true TCO.
