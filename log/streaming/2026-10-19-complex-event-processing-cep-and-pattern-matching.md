---
date: 2026-10-19
phase: streaming
topic: Complex event processing: CEP and pattern matching
---

# Complex event processing: CEP and pattern matching

*Streaming and distributed processing*

## Concept

Complex event processing (CEP) detects meaningful patterns across streams of events arriving out of order and at variable rates. Rather than storing all data then querying it, CEP maintains stateful windows and rules that trigger actions when sequences or conditions match—critical for real-time fraud detection, system anomalies, trading signals, and operational alerts where latency kills value.

Without CEP, you either miss patterns entirely (batch processing lag) or build fragile, ad-hoc logic in application code that doesn't handle out-of-order arrival, late data, or state management. CEP engines (Kafka Streams, Flink, Esper) abstract away the complexity of maintaining partial matches, expiring old state, and correctly correlating events across time windows and multiple streams.

The hard part is defining what "pattern" means in your domain. A job posting anomaly might be: *five postings with the same title, salary >$200k, and remote work within 2 hours*—a signal of salary inflation or coordinated hiring. Without CEP you'd write brittle joins and GROUP BYs that fail when events arrive 30 minutes apart or out of order.

## Practice

**Problem:** Detect rapid salary escalation patterns in job postings. Alert when the same job_title_short has 3+ postings within a 1-hour window where each successive posting's salary_year_avg is at least 15% higher than the previous one.

```sql
WITH ordered_postings AS (
  SELECT
    job_title_short,
    salary_year_avg,
    job_posted_date,
    ROW_NUMBER() OVER (
      PARTITION BY job_title_short 
      ORDER BY job_posted_date ASC
    ) AS event_seq,
    LAG(salary_year_avg) OVER (
      PARTITION BY job_title_short 
      ORDER BY job_posted_date ASC
    ) AS prev_salary
  FROM job_postings_fact
  WHERE salary_year_avg IS NOT NULL
),
with_growth_rate AS (
  SELECT
    job_title_short,
    salary_year_avg,
    prev_salary,
    job_posted_date,
    event_seq,
    CASE 
      WHEN prev_salary IS NULL THEN 1
      WHEN salary_year_avg / prev_salary >= 1.15 THEN 1
      ELSE 0
    END AS meets_growth_threshold
  FROM ordered_postings
),
pattern_matches AS (
  SELECT
    job_title_short,
    job_posted_date,
    salary_year_avg,
    SUM(CASE WHEN meets_growth_threshold = 0 THEN 1 ELSE 0 END)
      OVER (
        PARTITION BY job_title_short 
        ORDER BY job_posted_date 
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
      ) AS pattern_group,
    ROW_NUMBER() OVER (
      PARTITION BY job_title_short, 
        SUM(CASE WHEN meets_growth_threshold = 0 THEN 1 ELSE 0 END)
          OVER (
            PARTITION BY job_title_short 
            ORDER BY job_posted_date 
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
          )
      ORDER BY job_posted_date
    ) AS seq_in_pattern
  FROM with_growth_rate
  WHERE meets_growth_threshold = 1
)
SELECT
  job_title_short,
  COUNT(*) AS escalation_count,
  MIN(job_posted_date) AS pattern_start,
  MAX(job_posted_date) AS pattern_end,
  DATEDIFF(MINUTE, MIN(job_posted_date), MAX(job_posted_date)) AS window_minutes,
  STRING_AGG(salary_year_avg, ' → ') AS salary_progression
FROM pattern_matches
WHERE seq_in_pattern >= 3
GROUP BY job_title_short, pattern_group
HAVING DATEDIFF(MINUTE, MIN(job_posted_date), MAX(job_posted_date)) <= 60
ORDER BY pattern_start DESC;
```

## Notes

- **State explosion:** CEP state grows with cardinality of keys and window size. Partition aggressively (by job_title_short, location) and set explicit TTLs or max window bounds to prevent memory overflow in long-running streams.

- **Out-of-order handling:** Use event timestamps (job_posted_date), not processing time. Most CEP tools allow a grace period for late-arriving data; set it based on your SLA—too short and you miss events, too long and you delay pattern triggers unnecessarily.

- **Overlapping patterns:** One event can belong to multiple concurrent patterns. A salary-surge pattern may trigger an alert while simultaneously matching a hiring-volume pattern—use pattern IDs or correlation keys to track which rules fired.

- **Connects to:** watermarking (how late is too late?), session windows (grouping related events by inactivity), stateful stream processors (Flink
