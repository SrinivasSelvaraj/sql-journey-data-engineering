---
date: 2026-09-03
phase: pipelines
topic: Secrets management: credential rotation and access control
---

# Secrets management: credential rotation and access control

*Pipelines and orchestration*

## Concept

Secrets management—storing, rotating, and controlling access to credentials (API keys, database passwords, tokens)—is the backbone of safe pipeline orchestration. Without it, credentials leak into logs, get committed to repos, or expire silently mid-pipeline, causing cascading failures that are hard to debug. Credential rotation means regularly replacing old secrets with new ones, forcing attackers to work faster and limiting exposure windows. Access control ensures only the right service or person can retrieve a specific secret at a specific time.

In a data pipeline context, this matters acutely: your orchestrator (Airflow, dbt Cloud, Prefect) needs to pull data from Postgres, call a Snowflake warehouse, or hit an external API—all without baking passwords into DAG code or config files. A rotated credential that's not updated everywhere the pipeline runs causes jobs to fail silently or at 2am. Pipelines that "fail loudly" must detect auth failures immediately and alarm; pipelines that "rerun safely" must retrieve fresh secrets on each retry, not cache stale ones.

## Practice

**Problem:** Your data pipeline reads from an external job board API (authenticated with an API key) and loads into `job_postings_fact`. The key rotates monthly, but your pipeline doesn't know about it, so after rotation day, all scheduled runs fail silently for hours. How do you make the pipeline fetch the secret at runtime and fail loudly if it's missing or invalid?

```sql
-- Solution: Use a secrets manager (e.g., AWS Secrets Manager, HashiCorp Vault)
-- In your orchestrator (pseudocode for Airflow):

from airflow.models import Variable
from airflow.exceptions import AirflowException
import requests

def fetch_job_postings(**context):
    # Retrieve secret at runtime, not at DAG parse time
    api_key = Variable.get("job_board_api_key", deserialize_json=False)
    
    if not api_key:
        raise AirflowException("job_board_api_key not found in secrets store")
    
    headers = {"Authorization": f"Bearer {api_key}"}
    response = requests.get("https://api.jobboard.com/postings", headers=headers)
    
    # Fail loudly on auth errors
    if response.status_code == 401:
        raise AirflowException(f"API authentication failed: {response.text}")
    
    response.raise_for_status()
    
    # Load into job_postings_fact
    postings = response.json()
    for posting in postings:
        insert_sql = f"""
        INSERT INTO job_postings_fact 
        (job_id, job_title_short, salary_year_avg, job_work_from_home, job_posted_date, job_location)
        VALUES (
            {posting['id']}, 
            '{posting['title']}', 
            {posting.get('salary', 'NULL')}, 
            {posting.get('remote', False)}, 
            '{posting['date']}'::DATE, 
            '{posting['location']}'
        )
        """
        # Execute insert; fail if constraint violated
```

## Notes

- **Don't cache secrets in memory across retries**: fetch at task runtime so rotated keys are picked up without redeploying the DAG.
- **Never log secrets**: redact them from task logs and Airflow UI; if a credential appears in logs, treat it as compromised immediately.
- **Pair with audit logging**: log *who accessed what secret when*, so you can trace leaks and revoke permissions surgically.
- **Connects to: idempotency and retry logic**—a pipeline that reruns safely must assume the credential may have changed; design tasks to fetch fresh secrets on every attempt.
- **Revisit**: integrate secrets rotation alerts into your monitoring; a silently rotated key with no notification is a time bomb.
