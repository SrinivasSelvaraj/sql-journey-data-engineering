---
date: 2026-09-04
phase: cloud
topic: Network architecture: VPC, subnets and private endpoints
---

# Network architecture: VPC, subnets and private endpoints

*Cloud platforms and storage*

## Concept

A VPC (Virtual Private Cloud) is your isolated network boundary in the cloud—think of it as a gated neighborhood where you control all the traffic rules. Within a VPC, you create subnets to partition resources further (public subnets face the internet; private subnets do not). Private endpoints allow services within your private network to communicate with AWS managed services (RDS, S3, Redshift) without traversing the public internet, which improves security and can reduce data transfer costs.

This matters because data engineering workloads move terabytes between compute and storage. If your analytics database sits in a private subnet but queries S3 through the public internet, you're paying for data transfer out of the VPC (typically $0.02/GB) *and* introducing latency and security exposure. Private endpoints eliminate that charge for same-region traffic and keep sensitive data off the public routing layer. Without proper network architecture, a single slow query might stem not from query logic but from your EC2 instance reaching S3 across a bottlenecked NAT gateway.

## Practice

**Problem:** Your Redshift cluster in a private subnet queries the `job_postings_fact` table stored in S3. The query takes 3× longer than expected, and your AWS bill shows unexpected data transfer charges. You suspect the cluster is routing S3 traffic through a public NAT gateway instead of using a private endpoint.

```sql
-- Redshift query that triggers S3 Spectrum scan
SELECT 
  job_location,
  COUNT(*) as posting_count,
  AVG(salary_year_avg) as avg_salary
FROM job_postings_fact
WHERE job_posted_date >= CURRENT_DATE - INTERVAL '30 days'
  AND salary_year_avg IS NOT NULL
GROUP BY job_location
ORDER BY posting_count DESC;

-- Solution: Ensure S3 VPC endpoint exists and Redshift security group allows it
-- AWS CLI: aws ec2 create-vpc-endpoint \
--   --vpc-id vpc-xxxxx \
--   --service-name com.amazonaws.region.s3 \
--   --route-table-ids rtb-xxxxx
```

The fix avoids NAT gateway charges and keeps traffic within AWS's private backbone.

## Notes

- **Subnet routing mistake:** Public subnets need a route to an Internet Gateway; private subnets often route through a NAT, which charges per GB. Verify your route tables or you'll pay for every S3 read.
- **Data transfer costs hide query performance issues:** A "slow" query might actually be network-bound. Check VPC Flow Logs and CloudWatch metrics before optimizing SQL.
- **Cross-region endpoints cost more:** S3 private endpoints are free within a region but incur standard data transfer rates across regions—always co-locate compute and storage.
- **Security group whitelisting:** A private endpoint won't help if your security group blocks traffic. Ensure Redshift's SG allows HTTPS (port 443) to the S3 endpoint.
- **Adjacent topics:** NAT gateway high-availability, gateway vs. interface endpoints, VPC peering for multi-account queries, and PrivateLink for third-party data sources.
