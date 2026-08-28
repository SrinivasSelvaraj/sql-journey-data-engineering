---
date: 2026-08-28
phase: python
topic: Configuration management: environment variables and config files
---

# Configuration management: environment variables and config files

*Python for data engineering*

## Concept

Configuration management separates runtime parameters (database credentials, API keys, output paths, feature flags) from code, making pipelines portable across dev/staging/production without code changes. In data engineering, this is critical because pipelines often run in different environments with different data sources, credentials, and thresholds—hardcoding these values breaks reproducibility and creates security leaks.

Without configuration management, you end up with code like `conn = psycopg2.connect("user=admin password=secret123 host=prod-db")` scattered throughout your codebase, which is unsafe, inflexible, and fails when you move to a new cluster. Environment variables (via `os.getenv()`) and config files (YAML, TOML, JSON) let you inject these values at runtime. Typed configuration classes (using `dataclasses` or Pydantic) add validation—catching a missing required credential or an invalid log level before your pipeline crashes on line 50,000.

The pattern: define a `Config` class that reads from environment variables with fallbacks, validate on instantiation, and pass it throughout your pipeline. This makes testing trivial (mock the config), enables local development without touching production secrets, and makes deployment scripts readable.

## Practice

**Problem:** Your job postings ETL pipeline needs to read from different Postgres databases depending on environment (local SQLite for testing, staging db for QA, prod cluster for production). The output bucket also changes. You want to load configurations from environment variables with sensible defaults, validate that required values exist, and fail fast if the config is invalid.

```python
from dataclasses import dataclass
from typing import Optional
import os

@dataclass
class PipelineConfig:
    db_host: str
    db_port: int
    db_name: str
    db_user: str
    db_password: str
    output_bucket: str
    environment: str
    log_level: str = "INFO"
    
    def __post_init__(self):
        valid_envs = {"dev", "staging", "prod"}
        if self.environment not in valid_envs:
            raise ValueError(f"environment must be one of {valid_envs}")
        valid_levels = {"DEBUG", "INFO", "WARNING", "ERROR"}
        if self.log_level not in valid_levels:
            raise ValueError(f"log_level must be one of {valid_levels}")

def load_config() -> PipelineConfig:
    return PipelineConfig(
        db_host=os.getenv("DB_HOST", "localhost"),
        db_port=int(os.getenv("DB_PORT", "5432")),
        db_name=os.getenv("DB_NAME", "job_postings"),
        db_user=os.getenv("DB_USER"),  # required, no default
        db_password=os.getenv("DB_PASSWORD"),  # required, no default
        output_bucket=os.getenv("OUTPUT_BUCKET"),
        environment=os.getenv("ENVIRONMENT", "dev"),
        log_level=os.getenv("LOG_LEVEL", "INFO"),
    )

# In your pipeline
if __name__ == "__main__":
    config = load_config()  # Raises ValueError if DB_USER or DB_PASSWORD missing
    engine = create_engine(
        f"postgresql://{config.db_user}:{config.db_password}@{config.db_host}:{config.db_port}/{config.db_name}"
    )
    job_postings = pd.read_sql("SELECT * FROM job_postings_fact", engine)
    job_postings.to_parquet(f"s3://{config.output_bucket}/job_postings.parquet")
```

## Notes

- **Secrets in version control:** Never commit `.env` files or hardcoded credentials. Use `python-dotenv` locally, but let deployment tools (GitHub Actions, Airflow, K8s secrets) inject production credentials.
- **Validation timing:** Validate config in `__post_init__` or a dedicated method, not deep in pipeline logic. Fail at startup, not after processing 10 million rows.
- **Pydantic alternative:** For complex configs with nested objects and coercion, `pydantic.BaseSettings` is more powerful than dataclasses—it handles type casting and has built-in secret masking for logs.
- **Config files for complex setups:** YAML or TOML files work well when you have many environments or feature flags; use `pyyaml` or `tomllib` to load, then pass through your Config class for validation.
- **Testing:** Mock the config in unit tests; use a separate test fixture that overrides environment variables to avoid side effects (use `monkeypatch` in pytest).
