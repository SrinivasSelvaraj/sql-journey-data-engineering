---
date: 2026-10-31
phase: cloud
topic: Data residency and compliance requirements
---

# Data residency and compliance requirements

*Cloud platforms and storage*

## Concept

Data residency requirements mandate that certain data must be stored and processed within specific geographic regions or jurisdictions, driven by regulations like GDPR (EU), CCPA (California), and industry standards (HIPAA, PCI-DSS). When you query data across regions or move it to a cheaper storage tier in a non-compliant location, you create legal liability and operational risk. Without understanding your platform's data placement guarantees, you might unknowingly violate compliance, incur unexpected egress charges when moving data between regions, or suffer query slowdowns from cross-region latency.

In cloud platforms (BigQuery, Redshift, Snowflake), data residency isn't just about where files sit—it's about replication, backup locations, and processing zones. A query that runs fast in us-east-1 may timeout when queried from eu-west-1 if the data isn't replicated there, forcing a cross-region transfer. You also pay egress costs (often $0.02–$0.20 per GB) when data leaves its region, which can be 10× your storage cost. Compliance violations carry fines up to 4% of global revenue under GDPR.

## Practice

**Problem:** Your EU-based job recruitment team queries `job_postings_fact` containing candidate locations and salary data. The data currently lives in a us-east-1 bucket, but GDPR requires personal data to stay in the EU. Queries are slow (5+ minutes) and your monthly cloud bill shows €8,000 in egress charges. How do you fix this?

```sql
-- 1. Create EU-compliant replica with location constraint
CREATE TABLE `eu_project.job_postings_fact` AS
SELECT *
FROM `us_project.job_postings_fact`
WHERE job_location LIKE '%EU%' OR job_location LIKE '%UK%';

-- 2. Set explicit region in query configuration
-- BigQuery: Add @run_region = 'eu-west1' to query job config
-- Redshift: CREATE TABLE in eu-cluster only
-- Snowflake: ALTER TABLE SET REGION = 'eu-west-1'

-- 3. Query the compliant replica for EU users
SELECT 
  job_id, 
  job_title_short, 
  salary_year_avg,
  job_location
FROM `eu_project.job_postings_fact`
WHERE job_posted_date >= CURRENT_DATE() - 30
ORDER BY salary_year_avg DESC;

-- 4. Log data lineage for audit trail
-- Ensure column-level encryption for salary_year_avg (PII)
```

## Notes

- **Egress charges are hidden costs**: Always check your cloud bill's "data transfer" line item—it's often larger than storage. Moving 1 TB daily across regions costs ~$600/month.
- **Replication ≠ compliance**: Having a copy in the EU doesn't help if the primary is still in the US and backups replicate globally. Check your platform's backup and replica settings.
- **Query slowness often signals residency violations**: 5+ minute queries on small datasets usually mean cross-region network latency, not query complexity. Profile with `EXPLAIN` and check region metadata.
- **Related: data classification and tagging**—you must know which columns are PII (salary, location) before you can enforce residency rules.
- **Revisit the cost equation**: Sometimes paying for redundant storage in two regions is cheaper than egress fees; calculate your actual usage patterns (queries/month × GB transferred).
