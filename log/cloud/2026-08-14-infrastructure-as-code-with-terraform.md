---
date: 2026-08-14
phase: cloud
topic: Infrastructure as code with Terraform
---

# Infrastructure as code with Terraform

*Cloud platforms and storage*

## Concept

Infrastructure as Code (IaC) with Terraform lets you define cloud resources—compute, storage, databases, networks—in declarative configuration files rather than clicking through a console. This matters because data engineering workloads are expensive; without IaC, it's easy to provision oversized instances, forget to tear down dev environments, or accidentally duplicate resources across regions. A single forgotten RDS instance or idle Redshift cluster can cost hundreds per month. Terraform also makes cost attribution transparent: you write `instance_type = "t3.large"` explicitly, forcing you to justify each resource size.

Without IaC, you lose auditability, reproducibility, and the ability to version-control your infrastructure decisions. When a query runs slow, you can't easily check if someone manually resized a database or changed a security group. Terraform's state file and change plans let you see *exactly* what will change before you apply it, and you can review infrastructure changes in Git like code reviews.

## Practice

**Problem:** You have a data lake with 500 GB of job_postings_fact data. A colleague manually provisioned an S3 bucket for raw data and an RDS instance for the star schema, but didn't document the configuration. A query filtering by job_location runs in 15 seconds instead of 2. You need to:
1. Define the infrastructure in Terraform so it's reproducible  
2. Add a database index on job_location to speed up queries  
3. Know whether you're overspending on instance size

**Solution:**

```hcl
# S3 bucket for raw job postings data
resource "aws_s3_bucket" "raw_job_data" {
  bucket = "raw-job-postings-data"
}

resource "aws_s3_bucket_versioning" "raw_job_data" {
  bucket = aws_s3_bucket.raw_job_data.id
  versioning_configuration {
    status = "Enabled"
  }
}

# RDS PostgreSQL for star schema (intentionally small to control costs)
resource "aws_db_instance" "job_postings_warehouse" {
  identifier     = "job-postings-warehouse"
  engine         = "postgres"
  engine_version = "14.7"
  instance_class = "db.t3.medium"  # Explicit sizing decision
  allocated_storage = 100
  
  db_name  = "analytics"
  username = "postgres"
  
  skip_final_snapshot = false  # Protect production data
  
  tags = {
    Environment = "production"
    Cost_Center = "data_team"
  }
}

# Create index on job_location to fix slow queries
resource "null_resource" "job_location_index" {
  provisioner "local-exec" {
    command = "psql -h ${aws_db_instance.job_postings_warehouse.endpoint} -U postgres -d analytics -c 'CREATE INDEX idx_job_location ON job_postings_fact(job_location);'"
  }
  depends_on = [aws_db_instance.job_postings_warehouse]
}

# Output connection details for teams
output "rds_endpoint" {
  value = aws_db_instance.job_postings_warehouse.endpoint
}

output "s3_bucket_name" {
  value = aws_s3_bucket.raw_job_data.bucket
}
```

Run `terraform plan` to preview changes, then `terraform apply` to provision. Now the infrastructure is versioned, auditable, and resizing the instance is one line and one PR away.

## Notes

- **State file security**: Terraform state contains passwords and sensitive data; store it in S3 with encryption and versioning, never in Git or local disk.
- **Cost estimation**: Use `terraform plan` with cost estimation tools (Infracost) to catch expensive changes before they happen; a single `db.r5.4xlarge` mistake costs $10k/month.
- **Index placement**: Indexes live in the database schema, not infrastructure, but IaC is where you *decide* on instance size and storage—don't over-provision to hide missing indexes.
- **Drift detection**: Run `terraform plan` regularly to catch manual changes (someone SSH'd in and created a table); drift erodes reproducibility.
- **Adjacent topics**: Terraform modules (reusable configurations for data lake setups), CI/CD pipelines that auto-apply infrastructure, cost allocation tags for chargeback, monitoring (CloudWatch alarms on slow queries).
