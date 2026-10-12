---
date: 2026-10-12
phase: pipelines
topic: Dagster resources: database connections and configuration
---

# Dagster resources: database connections and configuration

*Pipelines and orchestration*

## Concept

Dagster resources are configured, injectable dependencies that your ops and assets use at runtime—most commonly database connections, API credentials, or file system paths. Rather than hardcoding connection strings inside op logic, you define resources once and pass them in, making your DAG testable, portable across environments (dev/staging/prod), and safe to refactor.

Without resources, you either duplicate connection logic across every op, scatter credentials in code, or can't easily swap a PostgreSQL connection for a test SQLite one. This breaks the orchestration principle of "fail loudly, rerun safely"—if a connection fails mid-op, you have no isolation; if you need to retry, you can't inject a fresh connection object cleanly.

Resources also integrate with Dagster's config system: you define them in your deployment's `resource_defs` dict or in a `resources.yaml` file, then reference them by name in op signatures. On failure or retry, Dagster manages the lifecycle—acquiring, using, and releasing the resource—so connections don't leak and retries don't inherit stale state.

## Practice

**Problem:** Your job postings pipeline reads from a staging table, validates salary_year_avg is non-null, and writes clean records to job_postings_fact. You have separate dev and prod databases. Without resources, you'd hardcode one connection; with a mistake, you corrupt production. How do you safely pass the right database to each op?

```sql
-- In Dagster, define a resource that yields a database connection:
-- resources.py (pseudocode):
@resource
def postgres_db(init_context):
    db_url = init_context.resource_config["url"]
    conn = psycopg2.connect(db_url)
    yield conn
    conn.close()

-- Then in your job:
@op
def validate_salaries(context, staging_data) -> pd.DataFrame:
    db = context.resources.postgres_db
    # Use db connection; on exit, Dagster closes it automatically
    result = db.execute(
        "SELECT job_id, salary_year_avg FROM job_postings_staging WHERE salary_year_avg IS NOT NULL"
    )
    return pd.DataFrame(result)

@op
def write_fact_table(context, validated_df):
    db = context.resources.postgres_db
    validated_df.to_sql('job_postings_fact', db, if_exists='append', index=False)

@job(resource_defs={"postgres_db": postgres_db})
def job_postings_etl():
    write_fact_table(validate_salaries())

-- Then in your Dagster config (resources.yaml):
resources:
  postgres_db:
    config:
      url: "postgresql://user:pass@localhost/prod_db"  # Swap for dev_db in dev config
```

## Notes

- **Config management:** Use separate `resources.yaml` files or environment variables per deployment; never hardcode credentials in code. Dagster's `run_launcher` and `executor` can inject these at runtime.
- **Connection pooling:** For high-throughput pipelines, wrap your resource in a connection pool (psycopg2.pool, SQLAlchemy engine) so you don't exhaust database connections across parallel ops.
- **Testing:** Mock resources in unit tests using `build_op_context(resources={"postgres_db": my_test_db})` so your op logic is decoupled from real I/O.
- **Lifecycle and retries:** Resources are acquired once per run, not per op invocation—if an op retries, it reuses the same connection object. Design idempotent writes (upsert, merge) so retries don't duplicate rows.
- **Adjacent topic:** Resource IO managers are a related pattern for storing op outputs (DataFrames, models) to external storage; combine resources + IO managers for full control over data flow and versioning.
