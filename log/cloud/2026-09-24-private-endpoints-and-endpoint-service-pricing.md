---
date: 2026-09-24
phase: cloud
topic: Private endpoints and endpoint service pricing
---

# Private endpoints and endpoint service pricing

*Cloud platforms and storage*

## Concept

Private endpoints allow your applications and data warehouses to connect to cloud services (S3, Snowflake, Redshift, etc.) without traversing the public internet. Instead of routing traffic through AWS's public IP space, a private endpoint creates a direct, private connection within your VPC. This matters because data exfiltration over the public internet incurs **data transfer charges**—typically $0.02 per GB egress on AWS—which can dwarf your compute costs on large analytical queries.

When you skip private endpoints and query S3 from Redshift over the public internet, you pay twice: once for compute and again for egress. A 100 GB analytical query can cost $2 in transfer alone. Additionally, without private endpoints, your data traverses untrusted networks, creating compliance violations in regulated industries (HIPAA, PCI-DSS). Without them, you also lose fine-grained network access controls and may face unpredictable latency.

The hidden cost emerges during high-volume ETL or when running ad-hoc queries on large S3 datasets. A slow query might be slow not because of poor indexes, but because bandwidth is being throttled by egress costs or network congestion on the public path.

## Practice

**Problem:** Your analytics team runs a daily job that joins job_postings_fact with a 50 GB lookup table stored in S3. The query completes but costs spike to $150/day. The team suspects the join is inefficient, but profiling shows execution time is normal—the delay is in data transfer.

**Solution:** Deploy a VPC endpoint for S3 and configure Redshift to use it, eliminating egress charges for S3→Redshift traffic:

```sql
-- No SQL change needed; configure at infrastructure level
-- AWS CLI: Create S3 VPC endpoint
aws ec2 create-vpc-endpoint \
  --vpc-id vpc-12345678 \
  --service-name com.amazonaws.us-east-1.s3 \
  --route-table-ids rtb-12345678

-- In Redshift, query remains the same but now routes privately
SELECT jp.job_id, jp.job_title_short, jp.salary_year_avg, s3_lookup.category
FROM job_postings_fact jp
JOIN s3_lookup ON jp.job_id = s3_lookup.job_id
WHERE jp.job_posted_date >= '2024-01-01';

-- Cost drops from $150/day (with egress) to ~$0.01/day (no egress charge)
```

## Notes

- **Gateway vs. Interface endpoints:** S3 and DynamoDB use cheaper gateway endpoints (free); Redshift, Snowflake APIs use interface endpoints (small hourly charge, ~$7–14/month). Choose the right type or you overpay.
- **Endpoint policies are silent failures:** A restrictive S3 endpoint policy that blocks your query will not error clearly; the query hangs or times out. Always test connectivity before rolling out.
- **Cross-region endpoints don't exist:** If your Redshift cluster is in us-east-1 and S3 bucket in us-west-2, the private endpoint only helps within the same region. Cross-region traffic still incurs egress charges.
- **Adjacent: VPC peering, Transit Gateway, and PrivateLink** all solve similar network isolation problems at different scales. Private endpoints are the simplest for single-service access.
- **Revisit:** Check your AWS Cost Explorer monthly for "EC2 - Data Transfer" line items. If it's >5% of total compute cost, private endpoints are likely ROI-positive within weeks.
