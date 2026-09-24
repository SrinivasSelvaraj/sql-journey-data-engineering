---
date: 2026-09-24
phase: cloud
topic: CloudTrail and audit logging storage fees
---

# CloudTrail and audit logging storage fees

*Cloud platforms and storage*

## Concept

CloudTrail logs every API call made in your AWS account—who, what, when, where—and stores these logs in S3. Each log entry is JSON and accumulates quickly; a moderately active account can generate gigabytes daily. You pay for S3 storage, data transfer out, and S3 API calls (PutObject) to write the logs. Without audit logging, you lose compliance evidence, cannot troubleshoot deleted resources, and have no trail to investigate security incidents.

When cost matters most: high-volume accounts, strict compliance requirements (SOC 2, HIPAA), or when you enable CloudTrail on multiple regions or organizations. A query runs slow or fails silently not because of CloudTrail itself, but because you didn't realize CloudTrail was writing to the same S3 bucket where your data engineering pipelines read from—causing unexpected PUT/GET costs and list operation throttling.

The key insight: CloudTrail is cheap *until* you query it at scale or store years of logs without lifecycle policies. Always use S3 Intelligent-Tiering or set a 90-day retention, and store logs in a dedicated audit bucket separate from your analytics buckets.

## Practice

**Problem:** You notice your monthly AWS bill spiked $400. Your data pipeline queries job_postings_fact in S3 daily, but performance degraded and S3 list operations started throttling. Your ops team enabled CloudTrail logging to your analytics bucket without telling you.

**Solution:** Move CloudTrail to a separate bucket with lifecycle rules, and use S3 Batch Operations or a partition filter to isolate your pipeline data.

```sql
-- Query job_postings_fact WITHOUT CloudTrail noise
SELECT 
  job_title_short,
  COUNT(*) as posting_count,
  AVG(salary_year_avg) as avg_salary
FROM job_postings_fact
WHERE job_posted_date >= CAST(CURRENT_DATE - INTERVAL '30' DAY AS DATE)
  AND job_location NOT LIKE '%cloudtrail%'  -- avoid partition pollution
GROUP BY job_title_short
ORDER BY posting_count DESC;

-- Separate CloudTrail bucket setup (pseudo-code for Terraform/CloudFormation)
-- s3://my-company-analytics-logs/ → job_postings_fact/ (data only)
-- s3://my-company-audit-logs/ → AWSLogs/cloudtrail/ (CloudTrail only)
-- Set lifecycle: transition to Glacier after 90 days, delete after 2 years
```

## Notes

- **Storage creep:** CloudTrail generates ~1–5 GB/month per region per active account; multiply by regions and orgs and you'll hit expensive Standard tier fast. Always enable S3 Intelligent-Tiering or Lifecycle policies immediately.

- **List operation bottleneck:** S3 list calls are throttled at 3,500 RPS per prefix; CloudTrail writing thousands of small JSONs to the same prefix as your Parquet data will cause your Athena/Spark jobs to fail on `ListObjects`.

- **Separate concerns:** Audit logs and analytics data belong in different buckets. This isolates blast radius, simplifies retention policies, and makes cost allocation clear.

- **Connected topics:** S3 bucket policies (who can write CloudTrail), Athena querying CloudTrail directly (useful for forensics), and organization-level CloudTrail (multi-account scenarios multiply costs).

- **Revisit:** Check your CloudTrail configuration quarterly; disable it for non-production accounts, set bucket versioning to OFF (CloudTrail doesn't need it), and use S3 Object Lock only if compliance requires immutability.
