---
date: 2026-09-05
phase: cloud
topic: Data residency requirements and regional constraints
---

# Data residency requirements and regional constraints

*Cloud platforms and storage*

## Concept

Data residency requirements mandate that certain data must be stored and processed within specific geographic regions due to regulatory compliance (GDPR, CCPA, HIPAA) or contractual obligations. Cloud platforms like AWS, Azure, and GCP offer region-specific storage and compute services, but moving data across regions incurs egress costs and latency penalties. When you query data across regions without awareness of these constraints, you trigger expensive cross-region transfers, slow query performance, and potential compliance violations.

Understanding your data's residency requirements means knowing: (1) which tables must stay in which regions, (2) what happens when you join tables across regions, and (3) how your cloud bill explodes when you don't plan for it. A query that works fine locally becomes prohibitively slow and expensive when it pulls data from a distant region or aggregates results across multiple regional endpoints.

## Practice

**Problem:** Your job_postings_fact table is split across two regions: EU jobs (stored in eu-west-1) and US jobs (stored in us-east-1) due to GDPR restrictions on EU employee data. A manager wants a global salary report by job_title_short, but querying across regions without planning causes timeouts and unexpected egress charges.

```sql
-- WRONG: Forces cross-region data movement and slow federation
SELECT job_title_short, AVG(salary_year_avg) as avg_salary
FROM job_postings_fact
WHERE job_posted_date >= '2024-01-01'
GROUP BY job_title_short;

-- CORRECT: Query each region separately, aggregate locally
WITH eu_summary AS (
  SELECT job_title_short, AVG(salary_year_avg) as avg_salary, COUNT(*) as count
  FROM eu_west_1.job_postings_fact
  WHERE job_posted_date >= '2024-01-01'
  GROUP BY job_title_short
),
us_summary AS (
  SELECT job_title_short, AVG(salary_year_avg) as avg_salary, COUNT(*) as count
  FROM us_east_1.job_postings_fact
  WHERE job_posted_date >= '2024-01-01'
  GROUP BY job_title_short
)
SELECT 
  COALESCE(eu.job_title_short, us.job_title_short) as job_title_short,
  ROUND((eu.avg_salary * eu.count + us.avg_salary * us.count) / 
         (eu.count + us.count), 2) as global_avg_salary
FROM eu_summary eu
FULL OUTER JOIN us_summary us ON eu.job_title_short = us.job_title_short;
```

## Notes

- **Egress costs dominate hidden bills**: Transferring 1 TB across regions often costs $0.02/GB; a careless join can cost hundreds of dollars in seconds.
- **Latency compounds with federation**: Cross-region queries add 50–500ms per hop; always filter and aggregate before moving data.
- **Compliance violations aren't just fines**: Accidentally copying GDPR-protected job_location or salary data out of EU regions can trigger audit flags and legal action.
- **Multi-region queries need explicit routing**: Most cloud warehouses (Redshift Spectrum, BigQuery federated queries) require explicit dataset/region specification; implicit queries default to the "nearest" region, which may not exist for your data.
- **Related topics**: Data partitioning strategies (partition by region first), read replicas vs. cross-region backup, and cost allocation across organizational units.
