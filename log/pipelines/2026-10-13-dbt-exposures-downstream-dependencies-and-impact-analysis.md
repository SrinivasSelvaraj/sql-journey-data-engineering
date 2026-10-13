---
date: 2026-10-13
phase: pipelines
topic: dbt exposures: downstream dependencies and impact analysis
---

# dbt exposures: downstream dependencies and impact analysis

*Pipelines and orchestration*

## Concept

dbt exposures are downstream dependencies that consume your dbt models—dashboards, reports, ML models, or business processes. By declaring these exposures in your dbt project, you create a lineage map that shows not just how data flows upstream through transformations, but also *where* that data lands and what depends on it. This is critical because a breaking change to a core model can silently corrupt a dashboard that drives business decisions, and without exposure tracking, you won't know until someone notices.

Exposures matter most when your dbt models feed multiple downstream consumers with different SLAs and risk profiles. A stale model might be acceptable for exploratory dashboards but unacceptable for an ML feature store or a customer-facing report. Without exposures, you lose visibility into impact radius—you can't answer "if I deprecate this column, what breaks?" or "which dashboards depend on this fact table?" This becomes especially painful in larger organizations where data producers and consumers don't communicate directly.

Without exposures, teams make changes in isolation: a dbt developer refactors a model, CI passes, code merges, and hours later a critical dashboard goes blank. Exposures, combined with proper testing and documentation, give you "fail loud" capability—you can tag exposures with ownership and criticality, integrate them into incident response workflows, and catch breaking changes before production deployment.

## Practice

**Problem:** You've refactored `job_postings_fact` to split salary data into a separate `job_salary_bridge` table. The HR dashboard queries `job_postings_fact.salary_year_avg` directly. You need to declare that exposure so the team knows the change will break downstream reporting, and you can plan a migration before merging.

```sql
-- models/marts/job_postings_fact.yml
version: 2

models:
  - name: job_postings_fact
    columns:
      - name: salary_year_avg
        tests:
          - not_null
        meta:
          deprecation_date: "2025-02-01"
          migration_guide: "Use job_salary_bridge.salary_year_avg instead"

exposures:
  - name: hr_salary_dashboard
    type: dashboard
    maturity: production
    owner:
      name: HR Analytics Team
      email: hr-analytics@company.com
    description: "Tableau dashboard showing salary ranges by job title and location"
    depends_on:
      - ref('job_postings_fact')
    tags:
      - critical
      - bi
    meta:
      sla_minutes: 120
      refresh_frequency: daily
```

Now `dbt parse` will surface this exposure in your DAG. When you run `dbt test --select +job_postings_fact`, it warns that a critical exposure depends on this model. Your CI/CD can fail the build if deprecations touch critical exposures without an owner sign-off.

## Notes

- **Common mistake:** Declaring exposures but never using them—they sit dormant in YML files. Integrate exposures into your CI pipeline (via API or custom tests) to actually block breaking changes; otherwise, they're just documentation theater.
- **Maturity levels matter:** Mark exposures as `draft`, `validated`, or `production` based on SLA and reliability. A prototype dashboard shouldn't trigger the same alert rigor as a customer-facing report.
- **Connects to:** data contracts (schema versioning and backward compatibility), impact analysis tooling (Lineage API in dbt Cloud), and incident response runbooks (exposure owner is your first escalation point).
- **Revisit:** How to sync exposure metadata (owner, SLA, criticality) into your data catalog or incident-management system so on-call engineers know what matters when a model fails.
- **Watch for:** Exposure creep—every analyst dashboard shouldn't be marked critical; be ruthless about what actually has business SLA. Separate "nice to have" visibility from "this breaks revenue."
