---
date: 2026-09-29
phase: reliability
topic: Soda: simple data quality checks and SLO enforcement
---

# Soda: simple data quality checks and SLO enforcement

*Quality, reliability and the professional layer*

## Concept

Soda is a data quality orchestration framework that embeds SLO (Service Level Objective) checks into data pipelines, catching issues before they propagate downstream. Unlike ad-hoc validation, Soda enforces deterministic quality gates: freshness, completeness, accuracy, and custom business rules. It integrates with dbt, Airflow, and cloud warehouses, making checks repeatable and discoverable.

The difference between a builder and an owner shows here. A builder ships pipelines that *sometimes* work. An owner ships pipelines with explicit contracts: "this table will have zero nulls in salary_year_avg" or "new rows appear within 2 hours of posting." When those contracts break, Soda fails fast and loud, preventing silent data corruption downstream—when a BI tool shows inflated salary averages or missing job locations reach stakeholders.

Without quality checks, bad data compounds: incorrect aggregations feed dashboards, dashboards drive decisions, and nobody knows the foundation cracked. Soda makes quality visible and enforced, shifting it from hope to infrastructure.

## Practice

**Problem:** Your job_postings_fact table is the source of truth for a recruiting analytics dashboard. Stakeholders notice salary calculations are sometimes wrong, job_posted_date occasionally null, and remote work flags missing for entire geographies. You need to guarantee data quality before it hits reports.

```sql
-- Soda checks configuration (YAML, typically in dbt project)
checks for job_postings_fact:
  - freshness(job_posted_date) < 2h:
      name: "job postings updated within 2 hours"
  - missing_count(salary_year_avg) = 0:
      name: "no null salaries allowed"
  - missing_count(job_work_from_home) = 0:
      name: "remote work flag must be complete"
  - invalid_count(salary_year_avg) = 0:
      valid min: 20000
      valid max: 500000
      name: "salary in plausible range"
  - row_count > 1000:
      name: "posting table not suspiciously empty"
  - duplicate_count(job_id) = 0:
      name: "job_id is unique primary key"
```

Run Soda after your dbt models complete; if any check fails, the pipeline stops and alerts fire. No silent data quality drift.

## Notes

- **Threshold creep:** Avoid setting SLOs so loose they're meaningless. "Salary can be anything from $1 to $10M" doesn't catch real errors. Ground thresholds in actual business requirements and historical patterns.
- **Freshness vs. latency:** Soda's freshness check (how old is the newest row?) differs from pipeline latency. Know which one matters; often you need both.
- **Connects to:** dbt tests (unit/integration), Great Expectations (deeper profiling), and observability platforms (Datadog, Monte Carlo). Soda fills the orchestration gap between dbt and dashboards.
- **Common mistake:** Treating Soda as a one-time audit tool. It's only valuable when embedded in every run, with tight alerting loops and defined SLOs, not sporadic manual checks.
- **Revisit:** How to set SLOs for skewed distributions (median vs. mean salary), handle expected nulls (e.g., salary_year_avg null for unpaid internships), and prioritize checks by business impact when you have many.
