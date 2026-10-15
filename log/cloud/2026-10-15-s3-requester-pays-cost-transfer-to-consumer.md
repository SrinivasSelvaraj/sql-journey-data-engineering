---
date: 2026-10-15
phase: cloud
topic: S3 Requester Pays: cost transfer to consumer
---

# S3 Requester Pays: cost transfer to consumer

*Cloud platforms and storage*

## Concept

S3 Requester Pays is a bucket configuration where the *consumer* (not the bucket owner) pays for data transfer and API request costs. The bucket owner pays only for storage. This is critical when sharing large datasets publicly or across AWS accounts—without it, a popular dataset could generate unexpected bills for the owner as thousands of users query it.

The cost transfer happens automatically at the AWS billing level; no code changes required. When enabled, requests must include the `x-amz-request-payer: requester` header, or they fail with 403 Forbidden. This matters most for data lakes and open datasets where usage is unpredictable or distributed across many teams.

Without Requester Pays awareness, you'll either (1) get surprise bills when publishing data, or (2) discover your queries fail silently in cross-account scenarios because headers aren't set. It's a hidden cost and permission boundary that breaks workflows quietly.

## Practice

**Problem:** Your analytics team maintains a `job_postings_fact` table in S3 (parquet format, ~500 GB, queried via Athena by 20 external clients). You need to shift data egress costs to clients without breaking their queries.

**Solution:**

```sql
-- 1. Enable Requester Pays on the S3 bucket (AWS CLI or Terraform)
-- aws s3api put-bucket-request-payment --bucket my-job-data --request-payment-configuration payer=Requester

-- 2. Athena query—clients must add this parameter to their connection string or query
-- In Athena console: Settings → Query Result Location → ensure they set requester-pays
-- Or via SDK:
-- client.start_query_execution(
--   QueryString='SELECT job_title_short, AVG(salary_year_avg) FROM job_postings_fact WHERE job_posted_date >= CAST(current_date AS DATE) - INTERVAL 30 DAY GROUP BY job_title_short',
--   QueryExecutionContext={'Database': 'analytics_db'},
--   ResultConfiguration={'OutputLocation': 's3://my-results-bucket/'},
--   ExecutionParameters=[],
--   WorkGroup='primary'  -- Ensure WorkGroup has requester-pays enabled
-- )

-- 3. Clients query normally; their AWS account is billed for:
-- - S3 GET/SELECT requests
-- - Data transfer out (egress)
SELECT 
  job_title_short,
  COUNT(*) AS job_count,
  AVG(salary_year_avg) AS avg_salary
FROM job_postings_fact
WHERE job_posted_date >= CAST(current_date AS DATE) - INTERVAL 30 DAY
GROUP BY job_title_short
ORDER BY avg_salary DESC;
```

## Notes

- **Header requirement is silent:** Requests without `x-amz-request-payer: requester` fail with 403, not a helpful error. Always document this in your data-sharing SLA.
- **Cross-account complexity:** IAM policies must allow the consumer's role to call S3 actions *and* assume the cost burden; test with a sandbox account first.
- **Athena/Glue integration:** Workgroups have separate Requester Pays toggles; enabling it on the bucket alone won't force Athena clients to pay unless the workgroup is configured too.
- **Cost visibility:** Requester's billing console will show `AmazonS3` line items for `GetObject` and `DataTransfer`; this is your audit trail for shared data usage.
- **Related:** VPC endpoints, S3 Transfer Acceleration, and S3 Select all interact with egress costs; Requester Pays amplifies the importance of query pushdown (SELECT in S3, not in application).
