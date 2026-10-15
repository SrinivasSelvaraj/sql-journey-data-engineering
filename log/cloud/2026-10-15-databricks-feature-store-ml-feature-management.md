---
date: 2026-10-15
phase: cloud
topic: Databricks feature store: ML feature management
---

# Databricks feature store: ML feature management

*Cloud platforms and storage*

## Concept

A feature store is a centralized repository that manages, versions, and serves pre-computed features for ML models. Databricks Feature Store integrates with Delta Lake to let teams define features once (e.g., "average salary by job title") and reuse them across multiple models and pipelines, eliminating duplicate transformation logic. Without a feature store, data scientists compute the same aggregations independently, leading to training-serving skew, inconsistent definitions, and unnecessary warehouse compute.

The cost and performance impact is direct: redundant feature computation wastes query resources and storage, while skew between training and production predictions damages model performance. Feature Store solves this by enforcing a single source of truth, enabling feature caching, and tracking lineage so you understand exactly which transformations cost money and why your queries slowed down after a model update.

## Practice

**Problem:** Your ML team trains three separate models predicting job salary, likelihood of remote work, and time-to-hire. Each model independently computes "average salary by job title" and "% remote jobs by title." You're paying 3× for identical transformations, and when definitions drift, models give conflicting predictions.

```sql
-- Create a reusable feature table in Databricks Feature Store
CREATE TABLE job_title_features (
  job_title_short STRING NOT NULL,
  avg_salary_by_title DOUBLE,
  pct_remote_by_title DOUBLE,
  job_count INT,
  feature_date DATE,
  PRIMARY KEY(job_title_short)
)
USING DELTA
TBLPROPERTIES (
  'delta.enableChangeDataFeed' = 'true',
  'quality' = 'production'
);

-- Compute once, serve to all models
INSERT INTO job_title_features
SELECT 
  job_title_short,
  AVG(salary_year_avg) as avg_salary_by_title,
  SUM(CASE WHEN job_work_from_home THEN 1 ELSE 0 END) / COUNT(*) as pct_remote_by_title,
  COUNT(*) as job_count,
  CURRENT_DATE as feature_date
FROM job_postings_fact
WHERE job_posted_date >= DATE_SUB(CURRENT_DATE, 90)
GROUP BY job_title_short;
```

Now all three models query `job_title_features`, reducing compute and ensuring consistency.

## Notes

- **Lineage tracking matters for cost:** Feature Store logs which features each model uses; when a query slows, check if a feature computation's underlying table grew or if a join became expensive. Delta's Change Data Feed helps you compute only deltas.
- **Refresh strategy determines spend:** Batch refresh (daily/hourly) is cheap but risks staleness; on-demand (compute per request) is fresh but can spike costs during high-traffic periods. Version your features to A/B test refresh strategies.
- **Training-serving skew is silent:** A feature computed differently in batch vs. online inference will degrade model performance in production without obvious error messages. Use Feature Store's built-in serving endpoints to guarantee consistency.
- **Connects to Delta optimization:** Feature tables are Delta tables, so `OPTIMIZE` and `VACUUM` apply. Unused historical versions accumulate cost; set retention policies explicitly.
- **Governance + security overlap:** Feature Store integrates with Unity Catalog for access control and data lineage auditing—critical when features contain PII or high-cardinality data that shouldn't be cached publicly.
