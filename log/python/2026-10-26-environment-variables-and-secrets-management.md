---
date: 2026-10-26
phase: python
topic: Environment variables and secrets management
---

# Environment variables and secrets management

*Python for data engineering*

## Concept

Environment variables store configuration outside code—database credentials, API keys, file paths, feature flags—without hardcoding secrets into repositories. In data pipelines, this separation is critical: you need different database hosts for dev/staging/prod, and you cannot commit AWS keys to Git. Python's `os.environ` or libraries like `python-dotenv` (for development) and `pydantic.BaseSettings` (for validation) let you read these safely. Without this layer, credentials leak into logs, get exposed in code review, and become impossible to rotate without redeploying code.

When a pipeline runs in production (Airflow, Lambda, Kubernetes), secrets come from the orchestrator's vault, not a `.env` file. Your local development setup should mirror this: read from environment, never hardcode. Type hints (`str`, `int`, optional flags) catch configuration errors early. A missing `DATABASE_URL` should fail loudly at import time, not silently at runtime when you're halfway through loading 10GB of data.

## Practice

**Problem:** Your data pipeline connects to a PostgreSQL database and reads S3 paths. The job_postings_fact table has salary, location, and posting date. You need to connect to different databases in dev/prod and fetch only recent postings, but credentials and bucket names must never appear in your code.

```python
from pydantic import BaseSettings, Field
import os
from typing import Optional

class PipelineConfig(BaseSettings):
    database_url: str = Field(..., description="PostgreSQL connection string")
    s3_bucket: str = Field(..., description="S3 bucket for job data")
    aws_region: str = Field(default="us-east-1")
    job_postings_table: str = "job_postings_fact"
    days_lookback: int = Field(default=30)
    
    class Config:
        env_file = ".env"  # local dev only
        case_sensitive = False

config = PipelineConfig()

# Usage in your pipeline
import psycopg2
conn = psycopg2.connect(config.database_url)
query = f"""
SELECT job_id, job_title_short, salary_year_avg, job_work_from_home, 
       job_posted_date, job_location
FROM {config.job_postings_table}
WHERE job_posted_date >= CURRENT_DATE - INTERVAL '{config.days_lookback} days'
ORDER BY job_posted_date DESC
"""
cursor = conn.cursor()
cursor.execute(query)
```

## Notes

- **Validation matters:** `pydantic.BaseSettings` raises an error immediately if `DATABASE_URL` is missing, not when the pipeline hits that connection line after 2 hours of processing.
- **Never use `.env` in production:** Use secrets managers (AWS Secrets Manager, HashiCorp Vault, Kubernetes Secrets). The `.env` file is for local development only and should be in `.gitignore`.
- **Typed config objects are testable:** Pass a mock config object to your functions instead of reading `os.environ` directly. This makes unit tests deterministic and fast.
- **Adjacent topic—logging:** Strip secrets from logs and tracebacks. Log `DATABASE_URL=postgres://***:***@host/db`, never the actual password.
- **Rotation strategy:** If you're using credentials, design your pipeline to read them at startup (or per task), not cache them for the lifetime of a long-running process.
