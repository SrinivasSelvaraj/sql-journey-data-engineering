---
date: 2026-10-20
phase: reliability
topic: MTTR measurement and blameless post-mortems
---

# MTTR measurement and blameless post-mortems

*Quality, reliability and the professional layer*

## Concept

MTTR (Mean Time To Recovery) is the average duration between when a data pipeline failure is detected and when it's restored to normal operation. It's a hard metric that separates junior builders from owners: you can write correct code, but ownership means reducing the time your team spends in production chaos. MTTR matters most in downstream-dependent systems—when your transformation job fails at 2am and three analytics dashboards go dark, recovery time directly impacts business decisions.

Blameless post-mortems are the structural practice that *makes* MTTR improvement possible. They separate the person from the failure, focusing investigation on *why the system allowed this to happen* rather than *who made the mistake*. Without this culture, engineers hide failures, avoid automation, and repeat incidents. With it, you systematically eliminate root causes: Did monitoring miss the failure? Was there a manual handoff that should be automated? Was the test suite insufficient?

Together, they form a feedback loop: measure recovery time honestly, investigate without fear, automate the recovery steps or add safeguards, and repeat. An owner tracks MTTR trends over quarters and sees it decline not through heroic firefighting, but through compounding infrastructure improvements.

## Practice

**Problem**: Your `job_postings_fact` table is updated daily via an external API, but the refresh sometimes fails silently—the table stops updating but no alert fires. When discovered 3 days later, analysts have been building reports on stale data. You need to detect this failure *immediately* and quantify what "stale" means.

```sql
-- Create a monitoring query that flags when the table hasn't refreshed
-- Run this hourly via your orchestrator (Airflow, dbt Cloud, etc.)

SELECT
  CURRENT_TIMESTAMP() as check_time,
  MAX(job_posted_date) as latest_job_date,
  CURRENT_TIMESTAMP() - MAX(job_posted_date) as hours_since_last_update,
  CASE 
    WHEN CURRENT_TIMESTAMP() - MAX(job_posted_date) > INTERVAL '26 hours'
    THEN 'ALERT: Data is stale'
    ELSE 'OK'
  END as status
FROM job_postings_fact
GROUP BY 1;

-- On failure: automated alert goes to your team's channel with MTTR timer starting
-- On recovery: log the actual recovery time and store in an incidents table
-- Post-mortem question: Why didn't we catch this in 1 hour instead of 72?
-- Possible answers: alerting wasn't configured, DAG failure wasn't visible, 
-- no one was on-call. Each becomes a task.
```

## Notes

- **Common mistake**: Treating MTTR as a speed metric rather than a systemic one. Heroic 10-minute recoveries mask a broken pipeline; the goal is preventing failures, not recovering from them faster.
- **Adjacent topic**: Observability and monitoring—you can't improve MTTR without visibility into when failures occur. Logs, metrics, and data freshness checks are prerequisites.
- **Adjacent topic**: Runbooks and automation—blameless post-mortems often surface manual steps. Automating recovery (retry logic, circuit breakers, fallback data sources) is how MTTR actually improves.
- **Revisit quarterly**: Track MTTR per job or per data product. Trends matter more than absolute numbers; declining MTTR signals a maturing data infrastructure.
- **Cultural dependency**: Blameless post-mortems only work if leadership genuinely doesn't punish failure. One person blamed for an outage and the practice collapses; everyone stops reporting incidents early.
