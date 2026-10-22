---
date: 2026-10-22
phase: reliability
topic: Anomaly detection: statistical and rule-based methods
---

# Anomaly detection: statistical and rule-based methods

*Quality, reliability and the professional layer*

## Concept

Anomaly detection identifies unexpected deviations in data that violate statistical assumptions or business rules. In production pipelines, anomalies signal data quality issues (missing ETL steps, schema drift, upstream corruption), operational problems (sudden traffic spikes, unusual user behavior), or genuine edge cases requiring manual review. Without it, bad data propagates downstream—dashboards mislead stakeholders, ML models train on corrupted signals, and decisions compound errors silently.

Statistical methods (z-score, IQR, isolation forest) detect numeric outliers by measuring deviation from learned distributions. Rule-based methods enforce hard constraints: salary ranges, date validity, cardinality thresholds, regex patterns. The professional difference is *not* building detection—it's owning the threshold tuning, alert fatigue management, and decision logic for what happens when anomalies appear (quarantine, flag, transform, alert).

Without anomaly detection, you own the pipeline but not its trustworthiness. You can't distinguish signal from noise, can't explain degradation to stakeholders, and can't sleep knowing malformed data is in production.

## Practice

**Problem:** The `job_postings_fact` table receives daily incremental loads. You notice salary data occasionally contains impossible values (negatives, >$1M for non-executive roles), and `job_posted_date` sometimes lags the current load date by months (legitimate historical backfill vs. schema bugs). Build detection that flags these without blocking loads.

```sql
WITH salary_stats AS (
  SELECT
    PERCENTILE_CONT(0.25) OVER () AS q1,
    PERCENTILE_CONT(0.75) OVER () AS q3,
    job_id,
    salary_year_avg
  FROM job_postings_fact
  WHERE salary_year_avg IS NOT NULL
    AND job_posted_date >= CURRENT_DATE - INTERVAL '90 days'
),
anomaly_flags AS (
  SELECT
    job_id,
    salary_year_avg,
    job_posted_date,
    CASE
      WHEN salary_year_avg < 0 THEN 'negative_salary'
      WHEN salary_year_avg > 500000 
        AND job_title_short NOT IN ('Executive', 'C-Suite', 'VP') 
        THEN 'extreme_salary_non_executive'
      WHEN salary_year_avg > (q3 + 3 * (q3 - q1)) THEN 'statistical_outlier_iqr'
      WHEN job_posted_date < CURRENT_DATE - INTERVAL '180 days' 
        AND EXTRACT(DAY FROM CURRENT_DATE - job_posted_date) > 365 
        THEN 'stale_historical_backfill'
      ELSE NULL
    END AS anomaly_type
  FROM salary_stats
)
SELECT
  job_id,
  salary_year_avg,
  job_posted_date,
  anomaly_type,
  CURRENT_TIMESTAMP AS detected_at
FROM anomaly_flags
WHERE anomaly_type IS NOT NULL
ORDER BY job_posted_date DESC;
```

## Notes

- **Threshold tuning is iterative**: Set statistical thresholds (z > 3σ, IQR × 3) loosely at first, then tighten based on false positive review. Document *why* each threshold exists—it's your SLA.
- **Alert fatigue kills monitoring**: If 40% of rows trigger anomalies, alerts become noise. Prioritize by impact (missing salary > cosmetic date drift) and separate into tiers: critical (block load), warning (flag for review), info (log only).
- **Rule-based methods scale better operationally**: They're deterministic, explainable, and easy to hand off. Statistical methods need retraining when data distribution shifts legitimately (new market, new job types).
- **Connect this to data quality frameworks**: Anomaly detection is one layer of Great Expectations, dbt tests, or custom validation. Layer it: schema validation → business logic tests → statistical checks.
- **Context matters**: One team's anomaly is another's feature. A spike in remote-work postings during COVID isn't an error. Own the decision: who reviews flags? What's the SLA for response? Who owns false positives?
