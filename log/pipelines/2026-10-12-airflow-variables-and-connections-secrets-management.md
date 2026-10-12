---
date: 2026-10-12
phase: pipelines
topic: Airflow variables and connections: secrets management
---

# Airflow variables and connections: secrets management

*Pipelines and orchestration*

## Concept

Airflow variables and connections are the primary mechanisms for managing configuration, credentials, and secrets in DAGs. Variables are key-value pairs (strings, JSON, environment variables) stored in the metadata database, while connections define how Airflow authenticates with external systems (databases, APIs, cloud services). Secrets management matters because hardcoding credentials in DAGs is a critical security vulnerability—they'd be visible in source control, logs, and the web UI. Without proper secrets management, your pipelines either leak credentials or fail when they can't connect to protected resources.

The typical failure mode is a DAG that runs locally (where you set env vars manually) but crashes in production because the operator can't find the secret. Another common break: storing plaintext passwords in variables and committing them to git, then discovering the breach months later. Airflow mitigates this by integrating with external secret backends (Vault, AWS Secrets Manager, GCP Secret Manager) and encrypting variable values at rest using `fernet_key`.

Best practice: use connections for system credentials (database passwords, API keys, SSH keys) and variables for non-secret config (batch sizes, retry counts, feature flags). Never hardcode; always retrieve at runtime.

## Practice

**Problem:** You're building a data pipeline that loads job postings from a PostgreSQL database and must authenticate using a username and password. The same pipeline runs in dev, staging, and production with different database hostnames. You need a reusable DAG that fails loudly if credentials are missing and works across all environments without code changes.

```sql
-- DAG snippet using Airflow Connection and Variable retrieval
from airflow.models import Connection, Variable
from airflow.providers.postgres.operators.postgres import PostgresOperator

# Retrieve connection (stores host, user, password, port, db)
pg_conn = Connection.get_connection_from_secrets('postgres_job_postings')

# Retrieve environment-specific schema
target_schema = Variable.get('job_postings_schema', default_var='public')

# SQL task that inserts from source to fact table
insert_job_postings = PostgresOperator(
    task_id='load_job_postings_fact',
    postgres_conn_id='postgres_job_postings',  # Airflow resolves this at runtime
    sql=f"""
    INSERT INTO {target_schema}.job_postings_fact 
    (job_id, job_title_short, salary_year_avg, job_work_from_home, job_posted_date, job_location)
    SELECT 
        id, 
        title, 
        salary, 
        remote, 
        posted_at, 
        location
    FROM staging.raw_postings
    WHERE posted_at >= CURRENT_DATE - INTERVAL '1 day'
    ON CONFLICT (job_id) DO UPDATE SET salary_year_avg = EXCLUDED.salary_year_avg;
    """,
    dag=dag
)
```

Connection `postgres_job_postings` is created via Airflow UI or `airflow connections add`, storing sensitive fields encrypted. Variable `job_postings_schema` is set per environment. If the connection doesn't exist, the DAG fails loudly during parsing.

## Notes

- **Never use `Variable.get()` with hardcoded secrets as fallback defaults**—defaults are logged and visible in UI. Omit the default or default to an empty string and let the task fail.
- **Fernet encryption requires a stable `fernet_key` across all Airflow instances**; losing it means losing access to encrypted variables. Back it up separately.
- **Secret backend backends (Vault, AWS Secrets Manager) are superior to Airflow's native encryption** for enterprise use—they support rotation, audit logging, and fine-grained access control without touching the Airflow database.
- **Connections have a "test" button in the UI**—use it during setup to catch typos and permission issues early; a failing test = a failing DAG.
- **Adjacent topic: environment variables in Airflow pools and queue routing**—use them for non-credential config to avoid polluting the variables table and to keep infra concerns separate from DAG logic.
