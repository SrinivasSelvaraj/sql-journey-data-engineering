---
date: 2026-10-16
phase: cloud
topic: VPC endpoints: private connectivity without NAT gateway
---

# VPC endpoints: private connectivity without NAT gateway

*Cloud platforms and storage*

## Concept

A VPC endpoint allows AWS resources (EC2, Lambda, RDS) to communicate with AWS services (S3, DynamoDB, Redshift) *without* routing traffic through the public internet or requiring a NAT gateway. Instead, traffic stays within the AWS backbone network via a private connection. This matters because NAT gateways charge per GB of data transferred (~$0.045/GB in most regions), while VPC endpoints are either free (Gateway endpoints for S3/DynamoDB) or charge a modest hourly fee (~$7/month) plus data processing costs. For data engineering pipelines that move terabytes daily—especially Lambda functions querying S3 or RDS reading from Redshift—NAT gateway costs can easily exceed $1000/month. Without VPC endpoints, you either pay heavily for NAT or expose your data to the public internet, which is a security and compliance risk.

## Practice

**Problem:** Your Redshift cluster in a private subnet processes 2TB daily from S3, routing through a NAT gateway. Daily NAT costs: ~$90. You need to eliminate this without moving resources to public subnets.

**Solution:** Create a Gateway VPC endpoint for S3 and attach it to your subnet's route table.

```sql
-- In AWS CLI (infrastructure setup, not SQL)
aws ec2 create-vpc-endpoint \
  --vpc-id vpc-12345678 \
  --service-name com.amazonaws.us-east-1.s3 \
  --route-table-ids rtb-abcdef12

-- Then query Redshift normally; traffic now routes privately
SELECT 
  job_title_short,
  SUM(salary_year_avg) as total_salary,
  COUNT(*) as posting_count
FROM job_postings_fact
WHERE job_posted_date >= CURRENT_DATE - INTERVAL '30 days'
GROUP BY job_title_short
ORDER BY total_salary DESC;

-- No code change needed. Redshift automatically uses the endpoint.
```

## Notes

- **Gateway vs. Interface endpoints:** Gateway endpoints (S3, DynamoDB) use route table entries and are free; Interface endpoints (SNS, SQS, Redshift) use ENIs and cost ~$7/month plus data. Choose the right type to avoid overpaying.
- **Route table trap:** The endpoint is invisible unless you explicitly attach it to the route table. Forgetting this means traffic still exits via NAT despite the endpoint existing.
- **Data transfer costs still apply:** VPC endpoints eliminate NAT charges but Redshift→S3 or cross-region transfers may still incur AWS data transfer fees; check your service pair.
- **Security groups matter:** Interface endpoints require a security group that allows inbound on port 443 from your subnet. A misconfigured SG blocks access silently.
- **Connects to:** S3 access patterns (Gateway Select, transfer acceleration), PrivateLink for third-party services, cost allocation tags for tracking savings across endpoints.
