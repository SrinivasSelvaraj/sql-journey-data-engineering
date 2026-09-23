---
date: 2026-09-23
phase: cloud
topic: NAT gateway throughput and cost surprises
---

# NAT gateway throughput and cost surprises

*Cloud platforms and storage*

## Concept

A NAT gateway enables private subnets to initiate outbound connections to the internet while remaining unreachable from outside. Every byte leaving through a NAT gateway incurs a charge (typically $0.045/GB in AWS), and throughput is capped at ~5 Gbps per NAT gateway. When a data pipeline extracts data from external APIs, backs up to S3 cross-region, or streams logs to a third-party service, all that traffic funnels through NAT gateways if your resources lack public IPs.

The cost surprise hits when you deploy a batch job that seemed cheap in development but hammers external APIs or downloads large datasets in production. A single large export can cost $20–$50 in NAT charges alone. The throughput bottleneck emerges when multiple jobs contend for one NAT gateway—queries slow mysteriously not because of database compute, but because outbound traffic is queuing at 5 Gbps.

Without a NAT gateway (or VPC endpoint), private resources cannot reach external services at all. With one, you gain privacy but trade fixed costs (NAT runs 24/7) and per-GB egress charges. Recognizing when data leaves your VPC is the first step to controlling both latency and cost.

## Practice

**Problem:** Your daily job_postings ETL queries remote job boards via API to enrich salary_year_avg. The job runs fine in a t3.micro test environment but takes 3× longer and costs $15/day in NAT charges when scaled to production (pulling 5 GB/day). You suspect the external API is slow, but infrastructure is the culprit.

```sql
-- Problematic: pulls raw API response and filters after
WITH raw_postings AS (
  SELECT * FROM external_api_call('https://api.example.com/jobs')
  WHERE job_posted_date >= CURRENT_DATE - INTERVAL '1 day'
)
SELECT 
  job_id,
  job_title_short,
  salary_year_avg,
  job_work_from_home,
  job_location
FROM raw_postings
WHERE salary_year_avg > 50000 AND job_location LIKE '%United States%';

-- Solution: filter at source API (if supported), or cache locally
-- Option A: Push filter to API query string (reduces egress)
WITH raw_postings AS (
  SELECT * FROM external_api_call(
    'https://api.example.com/jobs?min_salary=50000&country=US&date_from=' || 
    (CURRENT_DATE - INTERVAL '1 day')::TEXT
  )
)
SELECT job_id, job_title_short, salary_year_avg, job_work_from_home, job_location
FROM raw_postings;

-- Option B: Cache full response in RDS, join locally (one-time cost)
-- Create materialized local copy refreshed once daily
CREATE TABLE job_postings_cache AS
SELECT * FROM external_api_call('https://api.example.com/jobs')
WHERE job_posted_date >= CURRENT_DATE - INTERVAL '1 day';

SELECT 
  job_id, job_title_short, salary_year_avg, job_work_from_home, job_location
FROM job_postings_cache
WHERE salary_year_avg > 50000 AND job_location LIKE '%United States%';
```

## Notes

- **Egress ≠ ingress**: S3 downloads from private EC2 → NAT cost; S3 uploads from private EC2 → NAT cost. Inbound is free. Check CloudWatch NAT gateway metrics (BytesOutToDestination) to quantify daily leakage.
- **VPC endpoints bypass NAT**: If you only need AWS services (S3, DynamoDB, Secrets Manager, SNS), use gateway or interface endpoints instead—no per-GB charge, lower latency, no throughput cap.
- **Batch windows hide the cost**: A job running 10 am–2 pm looks fast because it's I/O bound. Running the same job 12 times daily at scale reveals NAT contention. Stagger jobs or add a second NAT.
- **Cross-region replication**: Copying data between regions incurs inter-region data transfer charges *plus* NAT gateway charges if initiated from a private subnet. Use S3 cross-region replication rules to avoid NAT altogether.
- **Monitor and alert**: Set up CloudWatch alarms on NAT BytesOutToDestination and EstablishedConnectionCount; spike signals either runaway queries or forgotten scheduled scripts. Review quarterly to catch "mystery" cost growth.
