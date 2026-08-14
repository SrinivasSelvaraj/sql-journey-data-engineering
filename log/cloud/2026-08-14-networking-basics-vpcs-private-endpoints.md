---
date: 2026-08-14
phase: cloud
topic: Networking basics: VPCs, private endpoints
---

# Networking basics: VPCs, private endpoints

*Cloud platforms and storage*

## Concept

A Virtual Private Cloud (VPC) is an isolated network environment within a cloud provider where you deploy compute, storage, and database resources. Within a VPC, you can create private subnets where resources have no direct internet access, and public subnets with internet-facing gateways. Private endpoints are network interfaces that allow resources *inside* your VPC to communicate with cloud services (like S3, Redshift, or APIs) without routing traffic through the public internet—keeping data within AWS's network backbone.

Why this matters for data engineering: when you query a data warehouse or pull from object storage, the data path determines latency, cost, and security. A query that routes through the public internet incurs data transfer charges and NAT gateway fees (~$0.05/GB). Using private endpoints eliminates those costs and reduces query latency by 10–50ms. If your ETL pipeline suddenly gets expensive or your dashboards slow down at scale, the culprit is often misconfigured routing—data leaking out to the internet when it should stay internal.

Without proper VPC isolation, you also expose credentials and data to unnecessary attack surface. A compromised EC2 instance in a public subnet can become a pivot point if it can freely reach your data warehouse.

## Practice

**Problem:** Your analytics team is running hourly aggregations on `job_postings_fact` stored in S3, querying via Redshift. The query completes in 2 seconds on a test dataset, but runs in 15 seconds in production and costs 3× more in data transfer charges than expected.

**Solution:** Configure a VPC endpoint for S3 and update your Redshift cluster to use it.

```sql
-- Check if Redshift cluster is in a VPC with private subnets
-- Step 1: Create S3 VPC endpoint (via AWS console or IaC, not SQL)
-- aws ec2 create-vpc-endpoint --vpc-id vpc-xxx --service-name com.amazonaws.region.s3 --route-table-ids rtb-xxx

-- Step 2: Verify Redshift can reach S3 via endpoint by checking cluster network config
-- Redshift should have Enhanced VPC Routing enabled

-- Step 3: This query now routes through the VPC endpoint, not public internet
SELECT 
  job_title_short,
  AVG(salary_year_avg) as avg_salary,
  COUNT(*) as job_count
FROM job_postings_fact
WHERE job_posted_date >= CURRENT_DATE - INTERVAL '7 days'
GROUP BY job_title_short
ORDER BY avg_salary DESC;

-- Data transfer now costs $0.00 instead of $0.05/GB; latency drops to 2s
```

## Notes

- **NAT gateway gotcha**: if your Redshift cluster is in a private subnet and routes through a NAT gateway to reach S3, you pay $0.045/GB egress *plus* $0.05/GB S3 transfer—use VPC endpoints instead (free, faster).
- **Enhanced VPC Routing**: Redshift's setting that forces all traffic through VPC endpoints; enable it immediately if you care about cost and security.
- **Endpoint vs. Bastion**: VPC endpoints replace the need for bastion hosts to access cloud services; know when you need each (endpoints for service access, bastions for EC2-to-EC2 admin).
- **Cross-region implications**: VPC endpoints are region-specific; accessing S3 in a different region still incurs data transfer costs even with an endpoint—co-locate compute and storage.
- **Revisit**: IAM policy attachment to VPC endpoints (restrictive), gateway vs. interface endpoints (S3/DynamoDB use gateway; other services use interface), and cost monitoring via VPC Flow Logs.
