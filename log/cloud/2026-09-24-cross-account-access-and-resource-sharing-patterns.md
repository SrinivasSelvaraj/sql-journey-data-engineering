---
date: 2026-09-24
phase: cloud
topic: Cross-account access and resource sharing patterns
---

# Cross-account access and resource sharing patterns

*Cloud platforms and storage*

## Concept

Cross-account access enables secure resource sharing between AWS accounts (or equivalent in GCP/Azure) without copying data or sharing credentials. This is critical in data engineering when multiple teams, environments, or business units need controlled access to centralized data lakes. The pattern typically involves role assumption via STS (Security Token Service), resource-based policies, and IAM roles that trust external principals.

Without proper cross-account design, teams either duplicate data (increasing storage costs and sync complexity), share long-lived credentials (security risk), or bottleneck through a single account admin. When a query runs slow across accounts, the culprit is often overly permissive policies causing audit logging overhead, or S3 bucket policies that weren't optimized for the access pattern—each LIST or GET operation hits IAM evaluation before reaching the actual resource.

The key trade-off: tighter policies improve security and observability but require precise role chaining and resource tagging. Loose policies speed up queries but hide cost attribution and create blast-radius risk if credentials leak.

## Practice

**Problem:** Your analytics team needs read access to a shared `job_postings_fact` table in a centralized data account's S3 bucket (s3://data-lake-prod/job_postings/) and Athena. Currently, you're sharing AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY across email, and cost allocation is impossible. Redesign using cross-account role assumption.

```sql
-- In the *data* account (centralized):
-- 1. Create an IAM role that grants S3 and Athena permissions
CREATE ROLE DataLakeReadRole (
  trust relationship: allow analytics-account-id to assume this role
);
ATTACH policy: s3:GetObject, s3:ListBucket on s3://data-lake-prod/job_postings/
ATTACH policy: athena:GetQueryExecution, athena:GetQueryResults

-- 2. Tag resources for cost allocation
-- S3 object tags: Environment=prod, Owner=DataLake, AccessTeam=Analytics

-- In the *analytics* account (consumer):
-- 3. Create IAM role for analytics users
CREATE ROLE AnalyticsQueryRole (
  trust relationship: allow analytics IAM users to assume this role
);
ATTACH policy: sts:AssumeRole on arn:aws:iam::DATA_ACCOUNT_ID:role/DataLakeReadRole

-- In Athena (analytics account), query using assumed role:
SELECT job_title_short, AVG(salary_year_avg) as avg_salary
FROM awsdatacatalog.default.job_postings_fact
WHERE job_posted_date >= DATE '2024-01-01'
GROUP BY job_title_short
ORDER BY avg_salary DESC;
-- Athena transparently assumes the cross-account role; no credentials in code.
```

## Notes

- **S3 bucket policy + IAM role both apply:** even with correct IAM, a restrictive bucket policy blocks access. Test with `aws s3api get-object-acl` to verify both layers.
- **Cost attribution gaps:** cross-account access obscures who consumed what. Use S3 bucket tags + AWS Cost Explorer filters by tag; enable CloudTrail in the data account to log access source.
- **Assume-role session duration:** default is 1 hour; long-running Spark jobs may timeout mid-query. Adjust `DurationSeconds` in role trust policy, but balance against security.
- **Connects to:** least-privilege IAM, AWS Organizations SCPs (service control policies) for account-wide guardrails, resource-based policies vs. identity-based policies trade-offs.
- **Revisit:** Glue Data Catalog resource links (Glue-native cross-account sharing), S3 Bucket Keys (reduce KMS API calls in cross-account encryption), and VPC endpoints (avoid NAT gateway costs for cross-account S3 transfers).
