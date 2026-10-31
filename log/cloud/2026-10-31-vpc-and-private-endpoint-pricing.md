---
date: 2026-10-31
phase: cloud
topic: VPC and private endpoint pricing
---

# VPC and private endpoint pricing

*Cloud platforms and storage*

## Concept

A VPC (Virtual Private Cloud) isolates your cloud resources in a private network, and a private endpoint allows services to communicate within that network without traversing the public internet. The cost implications are significant: data transfer *out* of a VPC to the internet incurs egress charges (typically $0.02–$0.09 per GB depending on the cloud provider), while data moving within a VPC or through a private endpoint is either free or heavily discounted. This matters enormously when you're querying external data sources, pulling results across regions, or streaming large datasets—a misconfigured architecture can cost thousands monthly in egress fees alone.

Without proper private endpoints, queries that should stay internal get routed through the public internet. For example, if your analytics database in `us-east-1` queries a data lake in `us-west-2` without a VPC endpoint, you pay egress charges on both ends. Similarly, a Lambda function pulling data from S3 across availability zones or regions without VPC Gateway endpoints will incur per-GB costs that dwarf the compute itself. Understanding which data flows are "free" (same AZ, VPC endpoint, or managed service pairing) versus "paid" (cross-region, public internet) is essential for cost optimization and debugging slow queries that are actually just expensive data movement.

## Practice

**Problem:** Your job postings analytics job runs daily, querying `job_postings_fact` from a Redshift cluster in `us-east-1` and writing results to S3 in `us-west-2`. The query completes but costs spike on egress fees. Design a solution using private endpoints.

```sql
-- Original: expensive cross-region transfer without VPC endpoint
-- SELECT job_id, job_title_short, AVG(salary_year_avg) as avg_salary
-- FROM job_postings_fact
-- WHERE job_work_from_home = true
-- GROUP BY job_id, job_title_short;

-- Solution: Create S3 Gateway Endpoint in Redshift VPC (free data transfer)
-- Then write results to same-region S3 first, then replicate if needed

CREATE EXTERNAL TABLE job_postings_summary AS
SELECT 
  job_id, 
  job_title_short, 
  AVG(salary_year_avg) as avg_salary,
  COUNT(*) as posting_count
FROM job_postings_fact
WHERE job_work_from_home = true
  AND job_posted_date >= CURRENT_DATE - INTERVAL '7 days'
GROUP BY job_id, job_title_short;

-- Write to us-east-1 S3 bucket (same region as Redshift, uses VPC Gateway Endpoint = free)
UNLOAD (SELECT * FROM job_postings_summary) 
TO 's3://my-bucket-us-east-1/analytics/job_summary/'
CREDENTIALS 'aws_iam_role=arn:aws:iam::ACCOUNT:role/RedshiftRole'
PARQUET;

-- Cross-region sync handled async with S3 Replication (one-time egress cost, not per-query)
```

## Notes

- **VPC Gateway Endpoints vs. Interface Endpoints**: S3 and DynamoDB have free Gateway Endpoints; most other services use Interface Endpoints (PrivateLink) which charge ~$7/month per endpoint plus data transfer. Know which applies to your use case.
- **Same-AZ is free, same-region is free (with endpoint), cross-region costs**: Always check whether your data pipeline crosses region boundaries—a "slow query" is often a symptom of unintended egress.
- **Managed service pairings matter**: Redshift-to-S3, Glue-to-S3, and Lambda-to-RDS via VPC endpoints avoid egress; without them you're paying per GB even within the same AWS account.
- **Monitor with VPC Flow Logs and Cost Explorer**: Enable VPC Flow Logs to see which traffic is leaving your VPC; cross-reference with AWS Cost Explorer's egress breakdown to identify surprise charges before they hit your bill.
- **Related: data locality, cross-region replication, NAT gateway costs**: Private endpoints are one layer; also consider whether your *tables* should be replicated or partitioned by region to avoid unnecessary movement in the first place.
