---
date: 2026-09-29
phase: streaming
topic: Window side outputs and tagged streams
---

# Window side outputs and tagged streams

*Streaming and distributed processing*

## Concept

Window side outputs and tagged streams allow you to split a single input stream into multiple output streams based on conditions, typically within windowed computations. In Apache Beam or Flink, you classify each element (often during aggregation) and route it to different outputs—for example, sending high-salary jobs to one stream and low-salary jobs to another. This matters because real-world streaming data often needs different handling paths: alerting pipelines, data quality checks, dead-letter queues, and business logic branches all operate on the same raw events. Without side outputs, you'd have to read the same source multiple times or perform redundant filtering downstream, wasting compute and creating consistency risks.

Side outputs become critical when you need to capture anomalies or edge cases without losing the main pipeline's throughput. If you're aggregating job postings by location in 1-hour windows and some windows arrive late or exceed a threshold, you can emit those to a separate "late_windows" or "anomalies" stream while the clean data flows to the primary output. This separation makes monitoring, debugging, and downstream handling explicit and efficient.

## Practice

**Problem:** You aggregate salary data by job title over 1-hour tumbling windows. Most windows complete normally, but you need to capture (1) windows with fewer than 5 postings (low-volume), (2) windows where the average salary exceeds $200k (high-value alert), and (3) windows that arrive more than 10 minutes late.

```sql
-- Conceptual approach (Beam-style pseudocode expressed in SQL logic):
-- Main pipeline: aggregate and tag outputs

WITH windowed_agg AS (
  SELECT
    job_title_short,
    WINDOW_START(job_posted_date, INTERVAL '1' HOUR) AS window_start,
    WINDOW_END(job_posted_date, INTERVAL '1' HOUR) AS window_end,
    COUNT(*) AS posting_count,
    AVG(salary_year_avg) AS avg_salary,
    CURRENT_TIMESTAMP AS processing_time
  FROM job_postings_fact
  WHERE job_posted_date >= CURRENT_DATE - INTERVAL '7' DAY
  GROUP BY job_title_short, WINDOW_START(job_posted_date, INTERVAL '1' HOUR), WINDOW_END(job_posted_date, INTERVAL '1' HOUR)
),
tagged_output AS (
  SELECT
    job_title_short,
    window_start,
    window_end,
    posting_count,
    avg_salary,
    processing_time,
    CASE
      WHEN posting_count < 5 THEN 'low_volume'
      WHEN avg_salary > 200000 THEN 'high_value_alert'
      WHEN CURRENT_TIMESTAMP > window_end + INTERVAL '10' MINUTE THEN 'late_arrival'
      ELSE 'normal'
    END AS output_tag
  FROM windowed_agg
)
-- Split into side outputs:
SELECT * FROM tagged_output WHERE output_tag = 'normal';       -- main output
SELECT * FROM tagged_output WHERE output_tag = 'low_volume';   -- side output 1
SELECT * FROM tagged_output WHERE output_tag = 'high_value_alert'; -- side output 2
SELECT * FROM tagged_output WHERE output_tag = 'late_arrival'; -- side output 3
```

## Notes

- **Common mistake:** Emitting side outputs but not consuming them. Tag-and-forget creates technical debt; pair side outputs with explicit downstream handlers (alerts, logging, schema registration).
- **Late-data handling:** Window side outputs are your primary tool for managing watermarks and late arrivals. Know whether your framework uses allowed lateness vs. explicit late-output tags.
- **Connects to:** Windowing strategies (tumbling, sliding, session), watermarking, and backpressure. Side outputs complement these by giving you a valve to redirect problematic or noteworthy batches.
- **Rewindow when needed:** Don't overload a single window with too many output tags; consider a two-stage pipeline where stage 1 classifies and stage 2 rewindows by classification.
- **Ordering guarantees:** Side outputs do not guarantee order relative to the main output; use timestamps or sequence IDs if downstream needs correlation.
