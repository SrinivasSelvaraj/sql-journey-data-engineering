---
date: 2026-08-21
phase: modelling
topic: Feature store design: entity keys, time stamps and TTL
---

# Feature store design: entity keys, time stamps and TTL

*Data modelling and warehousing*

## Concept

A feature store requires three foundational design decisions that prevent data quality issues and enable reliable ML pipelines. **Entity keys** uniquely identify the subject of prediction (user_id, job_id, customer_id)—they're the join axis between raw data and models. **Timestamps** mark when a feature became true, distinguishing between feature computation time and feature validity time; without them, you risk training on future information (data leakage). **TTL (time-to-live)** defines how long a feature remains fresh before it must be recomputed, preventing stale features from degrading model performance in production.

These three elements work together: an entity key lets you retrieve features for a specific job posting, a timestamp tells you *when* that feature was computed, and a TTL tells you whether that feature is still valid for today's inference request. Without entity keys, you cannot join features to entities reliably. Without timestamps, you cannot implement point-in-time correctness (the ability to reconstruct what you knew about an entity at a past date). Without TTL, you deploy features that silently decay in production, causing model drift no one notices until business metrics move.

## Practice

**Problem:** Your `job_postings_fact` table has salary and location data, but you're building a model to predict whether a job will fill quickly. You want to compute features like "average_salary_for_location_last_30_days" and reuse them across multiple prediction runs. The table has no way to track *when* each salary value was observed, and no TTL to tell you when to recompute. When you query it on day 50, you don't know if that salary is still representative.

**Solution:**

```sql
CREATE TABLE job_postings_feature_store (
  job_id INT NOT NULL,                           -- entity key
  feature_name VARCHAR NOT NULL,                 -- 'avg_salary_for_location_30d'
  feature_value FLOAT NOT NULL,
  feature_computed_at TIMESTAMP NOT NULL,        -- when computed
  feature_valid_from TIMESTAMP NOT NULL,         -- when feature became true
  feature_ttl_hours INT NOT NULL,                -- 30 days = 720 hours
  feature_expires_at TIMESTAMP GENERATED ALWAYS AS (feature_computed_at + INTERVAL feature_ttl_hours HOUR),
  PRIMARY KEY (job_id, feature_name, feature_valid_from)
);

-- Check if a feature is fresh for today's inference
SELECT job_id, feature_value
FROM job_postings_feature_store
WHERE job_id = 12345
  AND feature_name = 'avg_salary_for_location_30d'
  AND CURRENT_TIMESTAMP < feature_expires_at;  -- still within TTL
```

## Notes

- **Confusing computed_at vs. valid_from:** `feature_computed_at` is when you ran the SQL query; `feature_valid_from` is when that feature value became true in the business (e.g., the start of the 30-day window). Always track both.
- **TTL as a schema contract:** Encode TTL in the schema, not in application logic. If a feature has 24-hour TTL and you query it 25 hours later, the schema should tell you it's expired, not require a comment in Python code.
- **Entity keys prevent accidental cartesian joins:** Composite keys (job_id + feature_name) prevent a feature computed for one job bleeding into another; schema clarity saves debugging hours.
- **Connects to point-in-time correctness:** Without timestamp precision, backtesting and model audits fail. A teammate will ask "what salary data did you use to train?" and you'll have no answer.
- **Revisit when:** Adding new entity types (e.g., company_id features alongside job_id features) or moving from batch to real-time feature serving—both force rethinking TTL and timestamp semantics.
