---
date: 2026-11-03
phase: reliability
topic: Timeliness: when data became available vs expected
---

# Timeliness: when data became available vs expected

*Quality, reliability and the professional layer*

## Concept

Timeliness is the measure of lag between when data actually becomes available in your system versus when it was *expected* to be available. This is distinct from freshness (how old the data is) or latency (how long processing takes). A report might be fresh but late; a pipeline might be fast but unreliable in *when* it completes.

Timeliness failures break trust. A business user schedules a 9am meeting expecting the daily dashboard; if it lands at 10:30am, the decision happens without the data. Unlike correctness issues (which you might catch later), timeliness failures are immediately visible and erode confidence in the entire data platform. They're also insidious: a pipeline that succeeds 95% of the time on schedule trains people to check back later, defeating the point.

When you own pipelines, you're responsible for SLAs—explicit commitments about when data will be ready. This means understanding not just *if* your job runs, but *when*. It forces you to instrument arrival time, set alerts when jobs miss windows, and communicate trade-offs (e.g., "we can be faster or more accurate, not both today").

## Practice

**Problem:** Your `job_postings_fact` table is loaded daily at midnight UTC, and the analytics team expects it refreshed by 6am UTC so their 7am reports work. Recently, jobs posted on Wednesday aren't appearing until Thursday afternoon. You need to detect when the load misses its SLA and measure how often this happens.

```sql
-- Create a metadata table to track load times
CREATE TABLE IF NOT EXISTS job_postings_load_audit (
  load_id INT AUTO_INCREMENT PRIMARY KEY,
  load_date DATE,
  earliest_job_posted_date DATE,
  latest_job_posted_date DATE,
  row_count INT,
  load_completed_at TIMESTAMP,
  load_sla_window TIMESTAMP GENERATED ALWAYS AS (DATE_ADD(load_date, INTERVAL 6 HOUR)),
  sla_met BOOLEAN GENERATED ALWAYS AS (load_completed_at <= DATE_ADD(load_date, INTERVAL 6 HOUR)),
  INDEX idx_load_date (load_date),
  INDEX idx_sla_met (sla_met)
);

-- Insert on each successful load (called by your DAG)
INSERT INTO job_postings_load_audit 
  (load_date, earliest_job_posted_date, latest_job_posted_date, row_count, load_completed_at)
SELECT 
  CURDATE(),
  MIN(job_posted_date),
  MAX(job_posted_date),
  COUNT(*),
  NOW()
FROM job_postings_fact
WHERE job_posted_date = CURDATE();

-- Monitor SLA performance
SELECT 
  load_date,
  sla_met,
  TIMEDIFF(load_completed_at, load_sla_window) AS minutes_late,
  row_count,
  ROUND(100 * SUM(CASE WHEN sla_met THEN 1 ELSE 0 END) 
    OVER (ORDER BY load_date ROWS BETWEEN 6 PRECEDING AND CURRENT ROW) 
    / 7, 1) AS sla_reliability_7day
FROM job_postings_load_audit
ORDER BY load_date DESC;
```

## Notes

- **Confusing timeliness with latency:** A job that takes 2 hours to run but starts at 4am can still hit a 6am SLA. Timeliness is about *arrival*, not duration. Measure wall-clock time from trigger to completion.
- **No visibility into why it's late:** Instrument every stage—extract, transform, load—with timestamps. A job that's late is useless without knowing if it's blocked by source data, compute, or downstream dependencies.
- **SLA drift:** Avoid setting SLAs based on "how fast it usually runs." Build in buffer for variance, and separate your target (what you commit) from your capability (what you measure). Communicate honestly about trade-offs.
- **Connects to:** Observability (alerting on missed SLAs), dependency management (upstream data delays cascade), and stakeholder communication (setting realistic expectations beats over-promising).
- **Revisit when:** You add new data sources, scale to higher volumes, or notice users workaround missing data (a sign SLAs aren't credible).
