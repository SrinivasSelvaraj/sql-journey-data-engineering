---
date: 2026-10-12
phase: pipelines
topic: Prefect flows and tasks: modern Python-native orchestration
---

# Prefect flows and tasks: modern Python-native orchestration

*Pipelines and orchestration*

## Concept

Prefect is a modern workflow orchestration framework that treats data pipelines as Python-native objects rather than configuration files or DAGs drawn in UI. A **flow** is a Python function decorated with `@flow` that coordinates work; a **task** is a decorated `@task` function that does atomic work—fetch data, transform it, validate it—and Prefect automatically tracks state, retries, dependencies, and observability.

What makes Prefect valuable: when a pipeline fails at step 7 of 10, you don't restart from step 1. Tasks are granular and idempotent by design, so Prefect's state machine knows exactly which task failed, why, and can resume downstream tasks once you fix the upstream issue. Without orchestration, failures cascade silently, retries are manual, and debugging a 50-step pipeline means reading logs like tea leaves.

The "fail loudly, rerun safely" philosophy means every task has explicit state (completed, failed, skipped), timeouts prevent zombie processes, and Prefect's logging ties each log line to a task run and flow run. You get lineage: what data went where, who ran it, when, and why it failed—essential when stakeholders ask "why did my report break yesterday at 3 PM?"

## Practice

**Problem**: Your `job_postings_fact` table arrives daily from a partner API. You need to:
1. Fetch new postings since the last successful run
2. Enrich salary data (handle nulls, convert to annual USD)
3. Validate no duplicate job_ids in today's batch
4. Upsert into the fact table
5. Send a summary email (only on success or after manual approval on failure)

Without task isolation, a validation failure partway through the upsert corrupts your table. With Prefect, the upsert task doesn't run until validation passes, and you can see exactly which records failed validation.

```python
from prefect import flow, task
from prefect.tasks.sql import execute_query
import requests
from datetime import datetime, timedelta

@task(retries=2, timeout_seconds=300)
def fetch_job_postings(days_back: int = 1) -> list[dict]:
    """Fetch new postings from API since last run."""
    cutoff = (datetime.now() - timedelta(days=days_back)).isoformat()
    response = requests.get(
        "https://api.jobapi.com/postings",
        params={"posted_after": cutoff}
    )
    response.raise_for_status()
    return response.json()["data"]

@task
def enrich_salaries(postings: list[dict]) -> list[dict]:
    """Standardize salary fields; null becomes 0."""
    for p in postings:
        p["salary_year_avg"] = p.get("salary_usd_annual") or 0
        p["job_posted_date"] = datetime.fromisoformat(p["posted_at"]).date()
    return postings

@task
def validate_batch(postings: list[dict]) -> None:
    """Fail loudly if duplicates or malformed records."""
    job_ids = [p["job_id"] for p in postings]
    if len(job_ids) != len(set(job_ids)):
        raise ValueError(f"Duplicate job_ids in batch: {postings}")
    for p in postings:
        if not p.get("job_title_short") or not p.get("job_location"):
            raise ValueError(f"Missing required fields: {p}")

@task
def upsert_postings(postings: list[dict]) -> int:
    """Insert or update job_postings_fact."""
    # Pseudo-code; use your DB connector
    for p in postings:
        query = """
        INSERT INTO job_postings_fact 
        (job_id, job_title_short, salary_year_avg, job_work_from_home, job_posted_date, job_location)
        VALUES (%s, %s, %s, %s, %s, %s)
        ON CONFLICT (job_id) DO UPDATE SET
            salary_year_avg = EXCLUDED.salary_year_avg,
            job_posted_date = EXCLUDED.job_posted_date
        """
        execute_query(query, (
            p["job_id"], p["job_title_short"], p["salary_year_avg"],
            p.get("remote", False), p["job_posted_date"], p["job_location"]
        ))
    return len(postings)

@task
def send_summary(count: int, status: str) -> None:
    """Email stakeholders."""
    print(f"Loaded {count} postings. Status: {status}")

@flow(name="daily-job-postings", log_prints=True)
def load_job_postings():
    postings = fetch_job_postings(days_back=1)
    enriched = enrich_salaries(postings)
    validate_batch(enriched)
