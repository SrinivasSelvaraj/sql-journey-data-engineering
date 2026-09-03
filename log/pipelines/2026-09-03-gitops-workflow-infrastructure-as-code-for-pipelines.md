---
date: 2026-09-03
phase: pipelines
topic: GitOps workflow: infrastructure as code for pipelines
---

# GitOps workflow: infrastructure as code for pipelines

*Pipelines and orchestration*

## Concept

GitOps applies version control discipline to infrastructure and pipeline definitions: your DAGs, orchestration configs, and deployment manifests live in git as the single source of truth. Changes flow through pull requests, code review, and automated validation before reaching production. This matters because pipeline logic and infrastructure drift silently—a manual tweak to a scheduler config or a forgotten environment variable propagates inconsistently across environments, making failures irreproducible and blame diffuse.

Without GitOps, you lose auditability (who changed what, when?) and reproducibility (spinning up a second environment becomes guesswork). Pipelines become stateful black boxes; re-running a job may succeed or fail depending on undocumented side effects. The practice forces you to declare everything: retry logic, SLAs, resource requests, secrets rotation policies—all reviewable and versionable before deployment.

## Practice

**Problem:** Your analytics team runs a daily job that joins job postings to salary data, but the job sometimes fails silently when `salary_year_avg` is NULL, and no one knows why the join cardinality changed last month. You need to version the logic, define explicit failure handling, and make the transformation auditable.

**Solution:** Store your transformation in git with documented assumptions and tests:

```sql
-- dags/analytics/fact_salary_by_title.sql
-- Version: 1.2 | Owner: analytics-team | Last reviewed: 2024-01-15
-- Failure mode: Fail loudly if salary cardinality < previous run by 10%

WITH job_facts AS (
  SELECT
    job_id,
    job_title_short,
    salary_year_avg,
    job_work_from_home,
    job_posted_date,
    job_location,
    ROW_NUMBER() OVER (PARTITION BY job_id ORDER BY job_posted_date DESC) AS rn
  FROM job_postings_fact
  WHERE salary_year_avg IS NOT NULL
    AND job_posted_date >= CURRENT_DATE - INTERVAL 90 DAY
)
SELECT
  job_id,
  job_title_short,
  salary_year_avg,
  job_work_from_home,
  job_posted_date,
  job_location
FROM job_facts
WHERE rn = 1
  AND salary_year_avg > 0
HAVING COUNT(*) >= (
  SELECT COUNT(*) * 0.9 
  FROM job_postings_fact 
  WHERE salary_year_avg IS NOT NULL
);
```

Pair this with git-tracked orchestration config (Airflow DAG or dbt manifest) that includes SLA assertions, alert thresholds, and rollback procedures—all reviewable before merge.

## Notes

- **Drift detection:** Use automated validation to catch when deployed state diverges from git (config drift scanners, state file reconciliation in Terraform/Pulumi). Fail the pipeline if drift is detected.
- **Secrets management:** Never commit credentials; use external secret stores (Vault, cloud KMS) referenced by git-tracked manifests. Rotate keys on a schedule decoupled from code deployments.
- **Related: CI/CD for data.** GitOps is the foundation—pair it with data quality tests, schema contracts, and lineage tracking so failures are caught before they corrupt downstream tables.
- **Common mistake:** Treating git as a backup rather than the source of truth. If you allow manual edits to production configs outside git, you've broken the model; enforce deployments *only* via PR merges.
- **Revisit:** Data observability and incident response—GitOps enables rapid rollback, but you still need strong alerting and runbooks to act on failures quickly.
