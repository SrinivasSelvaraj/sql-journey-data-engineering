---
date: 2026-08-14
phase: cloud
topic: Containerising a pipeline with Docker
---

# Containerising a pipeline with Docker

*Cloud platforms and storage*

## Concept

Containerising a pipeline with Docker ensures reproducibility and cost predictability in cloud environments. When you package your data pipeline (extraction, transformation, loading scripts) in a Docker image, you capture exact versions of dependencies, Python libraries, and system configurations. This matters because environment drift—where dev, staging, and production have different setups—causes queries to behave unexpectedly, makes debugging slow, and often leads to unexpected cloud costs when retries multiply due to failures.

Without containerisation, you risk: inefficient resource allocation (oversized VMs to handle dependency conflicts), repeated debugging cycles (works on my machine), and opaque cost attribution (hard to know if a slow query is your code or the wrong environment). In cloud platforms like AWS ECS, GCP Cloud Run, or Azure Container Instances, you pay for compute per invocation or runtime; if your container is bloated or dependencies are missing, you're paying for wasted execution time.

## Practice

**Problem:** A data engineer runs a daily job that extracts job posting data, calculates average salary by location, and loads results to a data warehouse. The query runs in 2 minutes locally but takes 15 minutes in production, inflating cloud costs. Turns out the production environment is missing a PostgreSQL client library that forces a fallback to slower in-memory processing.

**Solution:** Containerise the pipeline to guarantee consistent environments.

```dockerfile
FROM python:3.11-slim

WORKDIR /app

COPY requirements.txt .
RUN apt-get update && apt-get install -y postgresql-client && \
    pip install --no-cache-dir -r requirements.txt

COPY pipeline.py .

CMD ["python", "pipeline.py"]
```

```python
# pipeline.py
import psycopg2
import pandas as pd

conn = psycopg2.connect("postgresql://user:pass@warehouse:5432/analytics")

query = """
SELECT 
    job_location,
    ROUND(AVG(salary_year_avg), 2) as avg_salary,
    COUNT(*) as job_count
FROM job_postings_fact
WHERE job_posted_date >= CURRENT_DATE - INTERVAL '30 days'
GROUP BY job_location
ORDER BY avg_salary DESC;
"""

df = pd.read_sql(query, conn)
df.to_csv("salary_by_location.csv", index=False)
conn.close()
```

Build once: `docker build -t job-pipeline:1.0 .` Deploy to ECS/Cloud Run with fixed resource requests—you now pay only for what you actually use.

## Notes

- **Image bloat costs money**: every MB of Docker image takes time to pull and start; use `slim` or `alpine` base images and multi-stage builds to strip unnecessary layers.
- **Dependency pinning matters**: Docker makes you specify versions explicitly (requirements.txt or poetry.lock); vague versions (e.g., `pandas>=1.0`) cause silent performance regressions between runs.
- **Cold start and warm start**: serverless platforms like Cloud Run charge per invocation; containerised jobs that take 30s to start consume budget even during idle periods—know your pricing model.
- **Connects to**: orchestration (Airflow/Prefect schedule containers), observability (log aggregation from ephemeral containers), and CI/CD (build images on commit to avoid manual versioning).
- **Revisit**: layer caching (why a one-line change rebuilt the whole image) and secrets management (never hardcode credentials in Dockerfile).
