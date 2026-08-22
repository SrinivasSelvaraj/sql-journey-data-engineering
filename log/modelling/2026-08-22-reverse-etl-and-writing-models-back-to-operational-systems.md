---
date: 2026-08-22
phase: modelling
topic: Reverse ETL and writing models back to operational systems
---

# Reverse ETL and writing models back to operational systems

*Data modelling and warehousing*

## Concept

Reverse ETL inverts the traditional data flow: instead of extracting data from operational systems into a warehouse, you push modeled insights back into those systems where they drive decisions and automations. A well-designed schema makes this handoff possible because downstream teams—marketing, sales, product—can consume your models without needing you to translate column names, business logic, or data quality rules.

Without clear schema design, Reverse ETL breaks at the integration layer. A column named `pred_churn_prob` means nothing to a CRM that expects a field called `risk_score`; a `salary_year_avg` that includes outliers will poison a compensation system. Your schema becomes the contract between the warehouse and operational tools, so naming, data types, and documentation must be unambiguous enough for a non-technical stakeholder to build a workflow on top of it.

This matters most when models drive action at scale: automated outreach lists, real-time pricing updates, lead scoring routed to sales. A poorly documented schema creates a bottleneck—every integration requires you to be the translator. A well-modeled fact or dimension table is self-service.

## Practice

**Problem:** Your sales team wants to automatically flag high-value job postings to recruiters within 24 hours of posting. They need a simple, reliable field in your data warehouse that tells them which postings are "high-value." Using the schema above, design a fact table that can be pushed back to the CRM without ambiguity about what "high-value" means.

```sql
CREATE TABLE job_postings_fact_enriched AS
SELECT
  job_id,
  job_title_short,
  salary_year_avg,
  job_work_from_home,
  job_posted_date,
  job_location,
  CASE 
    WHEN salary_year_avg >= 120000 
      AND job_work_from_home = TRUE 
      AND DATEDIFF(DAY, job_posted_date, CURRENT_DATE) <= 1
    THEN TRUE 
    ELSE FALSE 
  END AS is_high_value_posting,
  CASE 
    WHEN salary_year_avg >= 120000 THEN 'above_threshold'
    WHEN salary_year_avg >= 80000 THEN 'mid_range'
    ELSE 'entry_level'
  END AS salary_band,
  CURRENT_TIMESTAMP AS model_refresh_timestamp
FROM job_postings_fact
WHERE job_posted_date >= DATEADD(DAY, -1, CURRENT_DATE);
```

This schema includes the *rule* (`is_high_value_posting`) as a explicit column, salary bands for nuance, and a refresh timestamp so the CRM knows when the data was computed.

## Notes

- **Naming is load-bearing:** Boolean fields should start with `is_` or `has_`; avoid domain jargon (use `customer_lifetime_value`, not `ltv`) unless it's already the business standard.
- **Document the threshold:** Reverse ETL schemas must include a data dictionary showing *why* `is_high_value_posting = TRUE`. Thresholds without context become technical debt.
- **Timestamp every enrichment:** Add `model_refresh_timestamp` and `valid_from`/`valid_to` columns so downstream systems never sync stale predictions or miss updates.
- **Version your models in schema names:** `job_postings_fact_v2` signals breaking changes; easier to maintain two fact tables during migration than corrupt an active workflow.
- **Test the downstream integration first:** Before publishing, check that your data types, NULL handling, and refresh cadence actually work in the target system (Salesforce, Klaviyo, etc.). Schema beauty means nothing if the webhook fails silently.
