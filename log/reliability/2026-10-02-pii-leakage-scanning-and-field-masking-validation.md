---
date: 2026-10-02
phase: reliability
topic: PII leakage scanning and field masking validation
---

# PII leakage scanning and field masking validation

*Quality, reliability and the professional layer*

## Concept

PII (Personally Identifiable Information) leakage occurs when sensitive data—names, emails, phone numbers, addresses, SSNs, or derived location/salary details—persists in pipelines where it shouldn't. Unlike a schema bug that breaks logic, PII leaks silently: queries run, dashboards populate, and compliance violations accumulate. The risk compounds in data warehouses because raw tables are often more permissive than production systems; a junior analyst querying job_postings might inadvertently expose candidate contact info to the wrong stakeholder group.

Field masking validation means systematically verifying that sensitive columns are redacted, hashed, or excluded *before* data reaches consumers. This isn't one-time scrubbing—it's a repeatable contract: "Does this field meet our masking spec *every time* the pipeline runs?" Without validation, a schema drift, upstream change, or oversight can reintroduce unmasked PII into a table that was previously clean, and you won't know until audit or incident.

The professional layer distinguishes between "I built a pipeline that works" and "I built a pipeline I'd trust with regulated data." Masking validation is that checkpoint: automated assertions on sensitive columns, clear ownership of masking logic, and confidence that your data is safe to share.

## Practice

**Problem:** Your job_postings_fact table contains job_location (e.g., "San Francisco, CA, USA") and salary_year_avg. When salary is linked to a specific location and job title, it can re-identify individuals in small geographies. You need to validate that locations are generalized (e.g., to city or state level only, not street addresses) and that salary is rounded before export to the analytics layer.

```sql
-- Add validation checks in your post-load transformation
WITH validation_checks AS (
  SELECT
    job_id,
    job_location,
    salary_year_avg,
    CASE 
      WHEN job_location LIKE '%,%,%' THEN 'FAIL: address contains street-level detail'
      WHEN job_location IS NULL THEN 'FAIL: location missing'
      ELSE 'PASS'
    END AS location_validation,
    CASE 
      WHEN salary_year_avg % 1000 <> 0 THEN 'FAIL: salary not rounded to nearest 1000'
      WHEN salary_year_avg IS NULL THEN 'PASS: null salary acceptable'
      ELSE 'PASS'
    END AS salary_validation
  FROM job_postings_fact
)
SELECT 
  COUNT(*) AS total_records,
  COUNTIF(location_validation = 'FAIL') AS location_failures,
  COUNTIF(salary_validation = 'FAIL') AS salary_failures
FROM validation_checks
HAVING location_failures > 0 OR salary_failures > 0
  THEN RAISE_ERROR('PII masking validation failed; check job_postings_fact')
```

Run this assertion as a dbt test or in your orchestrator's post-load step. If it surfaces failures, halt the pipeline and investigate the source.

## Notes

- **Common mistake:** Treating masking as a one-time ETL step instead of continuous validation. Upstream schema changes and new fields introduce risk; assume every run is a re-audit.
- **Rounding vs. hashing:** Rounding (salary to nearest 1000) preserves analytical utility; hashing (one-way encryption) is cryptographically safe but makes analysis impossible. Choose based on your use case and governance rules.
- **Adjacent topics:** Data lineage tracking (who has access to unmasked data?), role-based access control (RBAC), and audit logging. Masking validation is useless if PII flows through unmonitored intermediate tables.
- **Common false sense of security:** Removing column names (renaming salary_year_avg to col_5) is *obfuscation*, not masking. Combine with actual redaction or hashing.
- **Worth revisiting:** Test your masking logic against realistic adversarial cases—what happens if someone joins your rounded salary table with external census data? Can re-identification still occur? This is where domain knowledge and threat modeling matter.
