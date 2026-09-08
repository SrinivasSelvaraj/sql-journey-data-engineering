---
date: 2026-09-08
phase: streaming
topic: Side outputs for split event streams by condition
---

# Side outputs for split event streams by condition

*Streaming and distributed processing*

## Concept

Side outputs enable splitting streaming event data into multiple paths based on conditions, allowing different processing logic for subsets of the same unbounded stream. Rather than filtering the entire stream multiple times or creating separate pipelines, a single source branches into tagged outputs—one main output and one or more side outputs—each following independent downstream transformations.

This matters because streaming data arrives continuously and out of order. Without side outputs, you either duplicate source reads (wasteful), write conditional logic into every downstream operator (brittle), or lose data that doesn't match your primary filter. Side outputs preserve all events while routing them efficiently to their appropriate handlers in a single pass.

Breaks without it: alerting systems miss critical anomalies routed to side outputs; cost calculations use incomplete data because expensive events were filtered out before reaching the accounting pipeline; compliance audits fail when certain event classes vanish into conditional dead-ends.

## Practice

**Problem:** A job posting stream arrives continuously. You must:
- Route remote-eligible jobs (work_from_home = true AND salary > $80k) to the main output for recommendation engine
- Send all high-salary jobs (salary > $150k) to a side output for executive alerts
- Send all postings without salary data to a deadletter side output

```sql
-- Kafka source with side outputs (Flink SQL / Beam-style pseudocode pattern)
SELECT 
  job_id,
  job_title_short,
  salary_year_avg,
  job_work_from_home,
  job_posted_date,
  job_location,
  CASE 
    WHEN salary_year_avg IS NULL THEN 'deadletter'
    WHEN salary_year_avg > 150000 THEN 'executive_alert'
    ELSE 'main'
  END AS _sideoutput_tag
FROM job_postings_fact
WHERE TRUE;

-- Downstream: filter main output
SELECT * FROM job_postings_fact 
WHERE _sideoutput_tag = 'main'
  AND job_work_from_home = true 
  AND salary_year_avg > 80000;

-- Downstream: filter executive alerts
SELECT job_id, job_title_short, salary_year_avg, job_posted_date
FROM job_postings_fact 
WHERE _sideoutput_tag = 'executive_alert'
INTO executive_alerts_topic;

-- Downstream: filter deadletter
SELECT * FROM job_postings_fact 
WHERE _sideoutput_tag = 'deadletter'
INTO deadletter_topic;
```

## Notes

- **Tag explosion:** Overusing side outputs for fine-grained filtering defeats the purpose—use 2–4 outputs max; beyond that, push filtering logic downstream into consumer applications.
- **Watermarking and late data:** Side-output routing happens *before* windowing; if an event arrives late (out-of-order), it still tags correctly but may miss the window it should have joined—design your routing condition independent of time semantics.
- **Schema consistency:** All side outputs should share the same schema (or a compatible superset); diverging schemas cause downstream deserialization failures and make lineage tracking opaque.
- **Monitoring & observability:** Tag counts as a metric—if executive_alert side output suddenly stops receiving events, it's a signal something upstream broke, not that there are no alerts to send.
- **Adjacent topics:** Connect to backpressure handling (side outputs must have capacity), multi-way splits (union vs. side outputs), and flatMap patterns (which can replace side outputs if logic is simple enough).
