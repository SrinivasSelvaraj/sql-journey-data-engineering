---
date: 2026-11-02
phase: reliability
topic: Freshness SLA: maximum acceptable data staleness
---

# Freshness SLA: maximum acceptable data staleness

*Quality, reliability and the professional layer*

## Concept

A Freshness SLA (Service Level Agreement) defines the maximum acceptable age of data in a system—the longest delay between when a real-world event occurs and when it's reliably queryable. For a hiring dashboard, this might be "job postings appear within 4 hours of posting." Without an explicit SLA, stakeholders assume real-time data, leading to broken decisions when a report shows yesterday's snapshot instead of today's market.

Freshness differs from completeness and accuracy: data can be fresh, wrong, and incomplete simultaneously. A stale SLA breach typically matters most when the data drives operational decisions (hiring freezes, pricing changes, real-time alerts) rather than historical analysis. The cost of violation ranges from embarrassment (showing closed jobs as open) to financial loss (missing market windows) to compliance violations (regulatory reporting delays).

Operationalizing freshness requires: (1) defining SLA by use case, not by available infrastructure, (2) instrumenting pipelines to emit refresh timestamps and alert on breach, and (3) communicating trade-offs—tighter freshness usually means higher cost, more frequent runs, and larger failure surface.

## Practice

**Problem:** Your hiring analytics team needs to report on job postings in real time for a recruiter dashboard. Currently, the `job_postings_fact` table updates nightly (23:00 UTC). New postings are critical within 2 hours of posting for competitive advantage. How do you detect and enforce a 2-hour freshness SLA?

```sql
-- Add instrumentation columns to track freshness
ALTER TABLE job_postings_fact 
ADD COLUMN pipeline_load_time TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
ADD COLUMN job_posted_to_loaded_minutes INT GENERATED ALWAYS AS 
  (EXTRACT(EPOCH FROM (pipeline_load_time - job_posted_date)) / 60);

-- Monitor SLA compliance
SELECT 
  COUNT(*) as total_records,
  SUM(CASE WHEN job_posted_to_loaded_minutes <= 120 THEN 1 ELSE 0 END) as within_sla,
  MAX(job_posted_to_loaded_minutes) as max_staleness_minutes,
  ROUND(100.0 * SUM(CASE WHEN job_posted_to_loaded_minutes <= 120 THEN 1 ELSE 0 END) 
    / COUNT(*), 2) as sla_compliance_pct
FROM job_postings_fact
WHERE job_posted_date >= CURRENT_DATE - INTERVAL '7 days';

-- Alert query: identify recent postings at risk of SLA breach
SELECT job_id, job_title_short, job_posted_date, 
  CURRENT_TIMESTAMP - job_posted_date as age
FROM job_postings_fact
WHERE job_posted_date > CURRENT_TIMESTAMP - INTERVAL '2 hours 30 minutes'
  AND job_posted_date <= CURRENT_TIMESTAMP - INTERVAL '2 hours'
ORDER BY job_posted_date DESC;
```

## Notes

- **Conflating freshness with frequency:** Running a job every 5 minutes doesn't guarantee 5-minute freshness if upstream delays or query time aren't accounted for. Measure end-to-end latency, not schedule interval.
- **SLA creep:** Stakeholders often request "as fresh as possible" because the cost is invisible to them. Push back with explicit requirements tied to business outcomes; "within 2 hours" beats "real-time."
- **Freshness by dimension:** Consider tiering—some tables (reference data) can be daily; others (event streams) need hourly or sub-minute cadence. Don't enforce uniform SLAs across a warehouse.
- **Adjacent: observability & alerting.** Freshness SLAs are worthless without automated breach detection. Pair with monitoring on `pipeline_load_time` lag and dead-letter queues for late or malformed records.
- **Revisit during incident postmortems:** When stakeholders discover stale data caused a problem, that's the moment to lock in an explicit, funded SLA and the infrastructure to support it.
