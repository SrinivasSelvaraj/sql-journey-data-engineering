---
date: 2026-09-15
phase: python
topic: Environment variables and secrets management patterns
---

# Environment variables and secrets management patterns

*Python for data engineering*

## Concept

Environment variables store configuration outside code—database credentials, API keys, file paths, feature flags—so the same codebase runs across dev, staging, and production without modification. In data pipelines, this is critical: hardcoding a production database URI into your script means every developer sees it, it leaks into version control, and rotation becomes a nightmare. Secrets management goes further, adding encryption, access control, and audit trails for sensitive values. Without this pattern, your pipeline either becomes inflexible (recompile for each environment) or insecure (credentials in git history forever).

Load environment variables early and validate them on startup, not mid-pipeline. Use `.env` files locally (with `python-dotenv`), but rely on your orchestrator (Airflow, dbt Cloud, GitHub Actions) or cloud provider (AWS Secrets Manager, Azure Key Vault) in production. Type and validate immediately: if `DATABASE_PORT` must be an integer or `S3_BUCKET` must match a regex, fail loudly at import time, not when your pipeline crashes at hour 3 of a 12-hour run.

## Practice

**Problem:** Your data pipeline reads job postings from a database and writes aggregated salary insights to a data warehouse. The source database hostname, port, credentials, and target warehouse URI should differ between your local development environment and the production cloud deployment. You need to read these from environment variables and fail fast if they're missing or malformed.

```python
import os
from typing import NamedTuple
from urllib.parse import urlparse
import psycopg2

class DatabaseConfig(NamedTuple):
    host: str
    port: int
    user: str
    password: str
    database: str

def load_db_config(env_prefix: str = "SOURCE") -> DatabaseConfig:
    """Load and validate database config from environment."""
    try:
        return DatabaseConfig(
            host=os.getenv(f"{env_prefix}_DB_HOST") or ValueError(f"{env_prefix}_DB_HOST required"),
            port=int(os.getenv(f"{env_prefix}_DB_PORT", "5432")),
            user=os.getenv(f"{env_prefix}_DB_USER") or ValueError(f"{env_prefix}_DB_USER required"),
            password=os.getenv(f"{env_prefix}_DB_PASSWORD") or ValueError(f"{env_prefix}_DB_PASSWORD required"),
            database=os.getenv(f"{env_prefix}_DB_NAME") or ValueError(f"{env_prefix}_DB_NAME required"),
        )
    except (ValueError, TypeError) as e:
        raise RuntimeError(f"Invalid database config: {e}") from e

# Load at module level—fail immediately on import if config is bad
source_config = load_db_config("SOURCE")
target_config = load_db_config("TARGET")

def extract_job_postings():
    conn = psycopg2.connect(
        host=source_config.host,
        port=source_config.port,
        user=source_config.user,
        password=source_config.password,
        database=source_config.database,
    )
    cursor = conn.cursor()
    cursor.execute("""
        SELECT job_id, job_title_short, salary_year_avg, job_work_from_home, job_posted_date, job_location
        FROM job_postings_fact
        WHERE job_posted_date >= CURRENT_DATE - INTERVAL '7 days'
    """)
    return cursor.fetchall()
```

## Notes

- **Mistake:** Defaulting secrets to dummy values (`os.getenv("API_KEY", "test-key")`) hides misconfiguration. Use `or raise` to fail loudly instead.
- **Mistake:** Loading environment variables inside functions repeatedly; load once at module init so failures happen at import time, before orchestrators invest compute.
- **Adjacent topics:** Connects to configuration management (Pydantic `BaseSettings`, Hydra), secrets rotation (short-lived tokens, automatic renewal), and infrastructure-as-code (Terraform, CloudFormation storing secrets in vaults).
- **Revisit:** How to test code that depends on environment variables without polluting the real environment; use fixtures and monkeypatch in pytest.
- **Revisit:** Audit logging—log *that* a secret was accessed, never log the secret itself; most cloud providers track this automatically via Key Vault or Secrets Manager APIs.
