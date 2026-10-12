---
date: 2026-10-12
phase: pipelines
topic: Prefect blocks: deployment-time configuration injection
---

# Prefect blocks: deployment-time configuration injection

*Pipelines and orchestration*

## Concept

Prefect blocks are reusable, environment-agnostic configuration objects that decouple deployment parameters from flow code. Instead of hardcoding database credentials, API endpoints, or cloud storage paths into your Python scripts, you define them once as blocks and inject them at deployment time. This lets the same flow code run in dev, staging, and production by simply swapping which block instance gets referenced.

Without blocks, you either scatter credentials throughout your codebase (security risk, hard to rotate), or rely on environment variables that must be manually set on every worker (fragile, easy to miss). Blocks solve this by centralizing configuration in Prefect's encrypted storage, versioning it, and making it available to any deployed flow that requests it by name. This matters most when you have multiple environments, multiple teams, or frequent credential rotations.

The pattern is simple: create a block (e.g., `PostgresCredentials` or `S3Bucket`), register it in your Prefect workspace, reference it by name in your flow using `@flow` or task parameters, and Prefect automatically loads the right instance at runtime based on your deployment configuration.

## Practice

**Problem:** You have a flow that loads job postings into `job_postings_fact` from three different S3 environments (dev, staging, prod) and writes to three different Postgres databases. Right now credentials are scattered in `.env` files and your flow breaks when someone forgets to set `PROD_DB_PASSWORD`. You need one flow definition that works in all three environments without modification.

```sql
-- Your flow loads from S3, transforms, and inserts:
INSERT INTO job_postings_fact 
  (job_id, job_title_short, salary_year_avg, job_work_from_home, job_posted_date, job_location)
SELECT 
  job_id,
  title AS job_title_short,
  salary AS salary_year_avg,
  remote AS job_work_from_home,
  posted_at::DATE AS job_posted_date,
  location AS job_location
FROM staging_job_postings
WHERE posted_at >= CURRENT_DATE - INTERVAL '1 day';
```

Instead of hardcoding connection strings, define blocks in Prefect:
```python
from prefect import flow, task
from prefect_aws import S3Bucket
from prefect_sqlalchemy import SqlAlchemyConnector

@task
def load_from_s3(s3_block_name: str) -> pd.DataFrame:
    s3 = S3Bucket.load(s3_block_name)  # Loads by name at runtime
    return pd.read_csv(s3.read_path("job_postings.csv"))

@task
def insert_to_postgres(df: pd.DataFrame, db_block_name: str) -> None:
    with SqlAlchemyConnector.load(db_block_name).get_connection() as conn:
        df.to_sql("job_postings_fact", conn, if_exists="append", index=False)

@flow
def load_job_postings(s3_block: str = "dev-jobs-bucket", db_block: str = "dev-postgres"):
    df = load_from_s3(s3_block)
    insert_to_postgres(df, db_block)

# Deploy with: prefect deploy --name prod-load --param s3_block=prod-jobs-bucket --param db_block=prod-postgres
```

Create blocks once via CLI or UI, deploy the flow multiple times with different block names, and the same code handles all environments.

## Notes

- **Block names are references, not values.** The flow never sees the actual credential; it just asks Prefect "give me the block named `prod-postgres`" and Prefect decrypts and injects it. This keeps secrets out of logs and code history.

- **Confusing blocks with environment variables:** Env vars are still useful for non-sensitive config (log levels, retry counts), but blocks are designed for credentials and external system references. Use both in concert.

- **Block registration is environment-specific.** You must create your `prod-postgres` block in your production Prefect workspace; it won't exist in dev unless you create it there too. Plan block creation as part of environment setup.

- **Blocks pair with parameters.** You can set default block names in `@flow` parameter defaults, but the real power comes from overriding them at deployment time or via the Prefect UI, making a single flow definition deployable across multiple environments without code change.

- **Adjacent patterns:** Look into `Automation` rules to trigger deployments with different parameters on schedule, and `Concurrency limits` on blocks to rate-limit access to a shared resource like a database connection pool.
