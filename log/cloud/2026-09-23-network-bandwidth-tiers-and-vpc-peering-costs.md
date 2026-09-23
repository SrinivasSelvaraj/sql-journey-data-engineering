---
date: 2026-09-23
phase: cloud
topic: Network bandwidth tiers and VPC peering costs
---

# Network bandwidth tiers and VPC peering costs

*Cloud platforms and storage*

## Concept

Network bandwidth tiers determine the cost of data movement *between* cloud resources and regions. Most cloud providers (AWS, GCP, Azure) charge egress—data leaving a resource or region—at tiered rates that escalate as volume increases. VPC peering establishes private, high-bandwidth connections between virtual networks at lower cost than internet egress, but introduces cross-account or cross-region latency and routing complexity. Understanding these costs is critical because a poorly architected query can trigger unexpectedly high egress charges by moving terabytes across regions or repeatedly shuffling data through NAT gateways instead of direct peering.

Without awareness of bandwidth tiers, teams often assume data movement is "free" within the cloud. In reality, a JOIN across two RDS instances in different regions may route through the public internet, incurring egress charges on both sides. Similarly, a nightly batch export of 500 GB from a data warehouse to S3 in a different region can cost $20–50 per job. Slow queries often signal inefficient data placement: if a query takes 3 minutes and moves 100 GB cross-region at $0.02/GB, you are paying $2 in bandwidth alone before compute costs.

## Practice

**Problem:** A reporting job joins `job_postings_fact` (hosted in us-east-1 RDS) with a `company_details` table in us-west-2 S3, pulling 50 million rows monthly. The query is slow and billing shows $800/month in unexpected data transfer charges.

**Solution:** Replicate `company_details` to us-east-1 via S3 + Redshift COPY, or use VPC peering + RDS read replica to eliminate cross-region egress:

```sql
-- Option 1: Replicate data locally (cheapest for repeated access)
-- Copy company_details parquet from us-west-2 S3 to us-east-1 Redshift
COPY company_details 
FROM 's3://company-bucket-us-east-1/company_details/' 
CREDENTIALS 'aws_iam_role=arn:aws:iam::ACCOUNT:role/RedshiftRole'
FORMAT AS PARQUET;

-- Then run JOIN in us-east-1 with no cross-region egress
SELECT 
  j.job_id,
  j.job_title_short,
  c.company_name,
  j.salary_year_avg
FROM job_postings_fact j
INNER JOIN company_details c ON j.company_id = c.company_id
WHERE j.job_posted_date >= CURRENT_DATE - INTERVAL '30 days';
```

## Notes

- **Egress is directional:** moving 100 GB from RDS (us-east-1) to S3 (us-west-2) charges egress on the RDS side; moving it back charges again. Bidirectional queries double the cost.
- **VPC peering reduces but does not eliminate latency:** peering lowers egress charges by ~30–50% versus internet routing, but inter-region peering still adds 20–100 ms latency; use it for infrastructure, not real-time queries.
- **Compression and columnar storage matter:** Parquet in S3 compresses 80–95% versus CSV; a 500 GB CSV becomes 25–100 GB Parquet, drastically cutting bandwidth costs.
- **Common mistake:** exporting full tables for "local analysis" daily; instead, push filtering and aggregation to the database and export only results.
- **Adjacent topics:** understand your cloud provider's data transfer diagram (inter-AZ vs. inter-region vs. internet), S3 transfer acceleration, and CloudFront for repeated reads of large files.
