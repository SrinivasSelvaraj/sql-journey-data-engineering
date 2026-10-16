---
date: 2026-10-16
phase: cloud
topic: Auto-scaling policies: metric-based and schedule-based
---

# Auto-scaling policies: metric-based and schedule-based

*Cloud platforms and storage*

## Concept

Auto-scaling policies dynamically adjust cloud compute resources (CPUs, memory, instances) in response to demand, split into two categories: **metric-based** (reactive, triggered by CPU/memory/latency thresholds) and **schedule-based** (proactive, triggered by time). Metric-based scaling handles unpredictable spikes—a sudden surge in queries scales up within seconds to minutes—while schedule-based scaling handles known patterns, like scaling up before 9 AM when data analysts start their day. Without these policies, you either over-provision (waste money 80% of the time) or under-provision (queries timeout at peak hours, users blame you, SLAs break). The cost impact is enormous: a 4-core instance running 24/7 costs ~$300/month; auto-scaling to 2 cores off-peak cuts this by 40–60%.

## Practice

**Problem:** Your analytics cluster runs 100 jobs daily against `job_postings_fact`. Peak load is 8–10 AM (200 concurrent queries, ~5s each) and 2–4 PM (150 concurrent queries, ~3s each). Off-peak (11 PM–6 AM) runs only 10 background jobs. Currently you pay for 8 cores 24/7; metrics show 95% idle time. Design a hybrid auto-scaling policy.

**Solution:**
```sql
-- Schedule-based: scale up 7:30 AM, down 11 AM; scale up 1:30 PM, down 5 PM
-- Metric-based: if CPU > 75% for 2 min, add 2 cores; if < 20% for 5 min, remove 1 core

-- Monitor actual demand to validate policy
SELECT 
  DATE_TRUNC('hour', job_posted_date) AS hour_bucket,
  COUNT(*) AS posting_volume,
  PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY salary_year_avg) AS p95_salary
FROM job_postings_fact
WHERE job_posted_date >= CURRENT_DATE - INTERVAL '30 days'
GROUP BY DATE_TRUNC('hour', job_posted_date)
ORDER BY hour_bucket;

-- Schedule: 2 cores baseline, 6 cores 7:30–11 AM, 5 cores 1:30–5 PM
-- Metric threshold: scale to 8 cores if p95 query latency > 4s (indicates contention)
```

## Notes

- **Schedule-based is cheaper but inflexible:** if traffic pattern shifts unexpectedly, you'll over-pay. Always layer metric-based alarms on top.
- **Metric lag kills you:** it takes 1–2 minutes for CPU data to aggregate and trigger scaling. By then, 100 queries are already queued. Use **predictive scaling** (ML models forecasting demand) if cost justifies it.
- **Scaling down is slower than scaling up:** drain connections gracefully (connection pooling) before removing instances, or queries fail mid-execution. Understand your platform's drain timeout.
- **Cost vs. performance trade-off:** cheaper (scale down aggressively) = slower peak-hour response. Track cost *per SLA miss*, not just raw compute cost; missing 10 SLAs costs more than over-provisioning.
- **Adjacent topics:** reserved instances (buy 1–3 year commitments at 40% discount for baseline), spot/preemptible instances (70% cheaper but can be evicted), and query optimization (fixing slow queries is often cheaper than scaling).
