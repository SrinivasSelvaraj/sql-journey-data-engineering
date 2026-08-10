---
date: 2026-08-10
phase: python
topic: Secrets handling and configuration layering
---

# Secrets handling and configuration layering

*Python for data engineering*

## Concept

Secrets handling and configuration layering separates sensitive credentials (database passwords, API keys, cloud tokens) from code and environment-specific settings (database host, log levels, batch sizes). Without this separation, secrets leak into version control, logs, and Docker images. Configuration layering means using environment variables or config files to override defaults per environment—dev, staging, production—without code changes.

In Python data pipelines, this matters because you often need to connect to multiple data sources (Postgres, S3, APIs) with different credentials per environment. If you hardcode `conn_string = "postgresql://user:password@localhost"` in your script, you cannot safely share code, containerize it, or run tests. Bad input—missing env vars, malformed connection strings, expired tokens—crashes pipelines silently or hangs them.

The pattern: store secrets in environment variables or a secrets manager (AWS Secrets Manager, HashiCorp Vault); use a config layer (dataclass, Pydantic model, or dict) to load and validate them at startup; fail fast if required values are missing. This makes pipelines portable, testable, and auditable.

## Practice

**Problem:** You are building an ETL that reads job postings from a private API, transforms them, and inserts into a Postgres table. The pipeline must run locally, in CI/CD, and in production without code changes. You need to handle missing or invalid credentials gracefully and validate the database connection before processing.

```sql
-- After credentials and config are validated in Python, insert:
INSERT INTO job_postings_fact (
  job_id, job_title_short, salary_year_avg, 
  job_work_from_home, job_posted_date, job_location
)
VALUES 
  (1, 'Data Engineer', 120000, true, '2024-01-15', 'Remote'),
  (2, 'Analytics Engineer', 115000, false, '2024-01-16', 'New York, NY')
ON CONFLICT (job_id) DO UPDATE SET
  salary_year_avg = EXCLUDED.salary_year_avg,
  job_posted_date = EXCLUDED.job_posted_date;
```

**Python pattern:**
```python
from dataclasses import dataclass
from typing import Optional
import os

@dataclass
class Config:
    db_host: str
    db_user: str
    db_password: str
    db_name: str
    api_key: str
    batch_size: int = 100
    
    @classmethod
    def from_env(cls) -> "Config":
        db_pass = os.getenv("DB_PASSWORD")
        api_key = os.getenv("API_KEY")
        if not db_pass or not api_key:
            raise ValueError("Missing required env vars: DB_PASSWORD, API_KEY")
        return cls(
            db_host=os.getenv("DB_HOST", "localhost"),
            db_user=os.getenv("DB_USER", "postgres"),
            db_password=db_pass,
            db_name=os.getenv("DB_NAME", "jobs_db"),
            api_key=api_key,
            batch_size=int(os.getenv("BATCH_SIZE", "100"))
        )

config = Config.from_env()  # Fails fast if secrets missing
```

## Notes

- **Never log or print secrets:** Use `***masked***` in logging; set up log redaction if handling many credentials.
- **Fail fast at startup:** Validate config before any I/O; don't discover missing secrets mid-pipeline.
- **Test with fixtures:** Mock `Config.from_env()` in tests; never use real credentials in test code.
- **Version control:** `.env` files and `secrets.yaml` belong in `.gitignore`; document required vars in `README` or `example.env`.
- **Adjacent topics:** Pydantic validation (stronger typing for config), dependency injection (pass config as argument, not global), and observability (audit which service fetched which secret).
