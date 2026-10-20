---
date: 2026-10-20
phase: reliability
topic: On-call rotations and alert fatigue management
---

# On-call rotations and alert fatigue management

*Quality, reliability and the professional layer*

## Concept

On-call rotations distribute operational responsibility across a team, ensuring someone is always available to respond to production incidents. Alert fatigue—the state where so many alerts fire that engineers ignore them—destroys this system. The goal is *signal over noise*: every alert should represent a real decision point that requires human judgment or intervention.

Without proper alert design, two failures occur simultaneously. First, the on-call engineer burns out from context-switching on false positives, missing actual problems in the noise. Second, the team loses trust in their observability—when alerts cry wolf, engineers respond slower to genuine incidents, increasing MTTR (mean time to resolve). This is why on-call ownership is often the first place data engineering moves from "builder" to "owner": you can't own what you won't stay awake for.

The practical baseline: alert on *impact and actionability*, not on symptoms. A slow query is a symptom; a job missing its SLA is impact. An alert should either trigger an automated remediation or answer "what do I do now?" clearly enough that a tired engineer at 3 AM can act.

## Practice

**Problem:** Your job posting pipeline runs daily at 6 AM UTC. You've deployed alerts for:
- Query execution time > 30 seconds
- Any row count change from previous day
- Memory usage > 80%

In the first week, you get 40 alerts; 37 are false positives. By week two, engineers stop checking Slack.

**Solution:**

```sql
-- Instead, alert on business impact: missing data at SLA boundary
-- Fire alert only if:
-- 1. Job hasn't completed by 7 AM UTC (1 hour past schedule)
-- 2. AND row count is materially below expected range (not just different)

WITH expected_rows AS (
  SELECT 
    PERCENTILE_CONT(0.25) OVER () as p25,
    PERCENTILE_CONT(0.75) OVER () as p75
  FROM job_postings_fact
  WHERE job_posted_date >= CURRENT_DATE - INTERVAL '30 days'
    AND job_posted_date < CURRENT_DATE
)
SELECT 
  COUNT(*) as current_row_count,
  (SELECT p25 FROM expected_rows) as expected_min,
  (SELECT p75 FROM expected_rows) as expected_max,
  CASE 
    WHEN COUNT(*) < (SELECT p25 FROM expected_rows) * 0.8 THEN 'ALERT: Row count critically low'
    WHEN COUNT(*) > (SELECT p75 FROM expected_rows) * 1.2 THEN 'ALERT: Row count critically high'
    ELSE 'OK'
  END as alert_status
FROM job_postings_fact
WHERE job_posted_date = CURRENT_DATE;
```

This fires only when actual data delivery is at risk—not when a query is slow but completing, or when row counts fluctuate naturally.

## Notes

- **Alert on outcomes, not metrics.** "Latency spiked" is a metric. "Jobs are missing their SLA" is an outcome. Always work backward from what users see.
- **Automate remediation where possible.** If your alert can trigger a retry, cache clear, or scale-up automatically, do it—that's not alert fatigue, that's the system fixing itself.
- **On-call ownership connects to incident postmortems.** Every alert that fires should feed learning; if you're not reviewing alert performance monthly, you're not improving signal quality.
- **The cost of on-call is real.** Sleep disruption, context loss, and burnout directly impact code quality during the day. Protecting on-call engineers from noise is an investment in team retention and incident response speed.
- **Revisit thresholds seasonally.** Job posting volume changes with hiring cycles; your alert thresholds from January may be useless by September. Quarterly threshold review prevents slow drift into fatigue.
