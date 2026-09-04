---
date: 2026-09-04
phase: cloud
topic: Identity and access management: IAM roles and service accounts
---

# Identity and access management: IAM roles and service accounts

*Cloud platforms and storage*

## Concept

IAM roles and service accounts control *who* (or *what*) can access cloud resources and *what actions* they can perform. In data engineering, this typically means granting a data pipeline service account permissions to read from a database, write to cloud storage, or query a data warehouse—without embedding credentials in code. A service account is a non-human identity (e.g., `data-pipeline@project.iam.gserviceaccount.com`); an IAM role bundles permissions (e.g., `roles/bigquery.dataEditor` allows querying and modifying datasets).

This matters because overly permissive roles hide costs and security risks. A pipeline with `Owner` access can accidentally delete tables or spin up expensive clusters. Conversely, insufficient permissions cause silent failures: a job reads nothing, the query returns zero rows, and debugging takes hours. In multi-tenant cloud environments, weak IAM is how one team's runaway job burns another team's budget.

Without proper IAM setup, you either hardcode credentials in scripts (which leak in version control), run everything as root (audit nightmare), or grant everyone full access (cost and security disaster). The answer is role-based access control: grant the minimum permissions needed, audit who did what, and catch overages before they compound.

## Practice

**Problem:** A data pipeline runs nightly to load job postings into BigQuery. You want the service account to read from a Cloud Storage staging bucket and append to a `job_postings_fact` table, but not drop tables or modify other datasets. The pipeline keeps failing silently, and you suspect IAM is the culprit.

```sql
-- Assume the service account is: data-loader@my-project.iam.gserviceaccount.com
-- Grant the service account read access to the staging bucket (via gcloud):
-- gcloud storage buckets add-iam-policy-binding gs://staging-bucket \
--   --member=serviceAccount:data-loader@my-project.iam.gserviceaccount.com \
--   --role=roles/storage.objectViewer

-- Grant the service account permission to write to the specific dataset:
-- gcloud bigquery datasets add-iam-policy-binding my_project:job_data \
--   --member=serviceAccount:data-loader@my-project.iam.gserviceaccount.com \
--   --role=roles/bigquery.dataEditor

-- Now the pipeline can run this query:
INSERT INTO my_project.job_data.job_postings_fact
(job_id, job_title_short, salary_year_avg, job_work_from_home, job_posted_date, job_location)
SELECT 
  job_id, 
  job_title_short, 
  salary_year_avg, 
  job_work_from_home, 
  CURRENT_DATE() as job_posted_date,
  job_location
FROM (
  SELECT * FROM `my_project.staging.raw_postings`
)
WHERE job_posted_date = CURRENT_DATE();
```

The service account can now read staging data and insert into the target table, but cannot drop tables or access other datasets.

## Notes

- **Overpermission creep:** Start with minimal roles (e.g., `dataViewer` only) and add permissions only when a specific operation fails. Never grant `Editor` or `Owner` to automate operations.
- **Audit trails are your invoice:** Enable Cloud Audit Logs to see which service account ran which queries; correlate with billing to catch runaway jobs before they cost thousands.
- **Cross-project access:** If your pipeline reads from one project and writes to another, you need IAM grants in *both* projects; missing the reader grant is a common silent failure.
- **Heredity and inheritance:** Child resources inherit parent IAM policies; a dataset inherits permissions from its project. Grant narrowly at the resource level, not the organization level.
- **Adjacent topics:** Cost attribution (tagging queries by service account), secret management (storing service account keys safely), and network access (VPC/firewall rules complement IAM by controlling *where* the service account can connect from).
