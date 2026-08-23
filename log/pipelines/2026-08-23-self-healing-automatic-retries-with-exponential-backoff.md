---
date: 2026-08-23
phase: pipelines
topic: Self-healing: automatic retries with exponential backoff
---

# Self-healing: automatic retries with exponential backoff

*Pipelines and orchestration*

## Concept

Automatic retries with exponential backoff is a resilience pattern that re-attempts failed operations with increasing delays between attempts. Instead of failing immediately when a database query times out or an API call fails, your pipeline catches the error, waits (2s, then 4s, then 8s), and tries again. This is critical in data engineering because external dependencies—cloud APIs, databases under load, network blips—fail transiently but often succeed within seconds.

Without this pattern, a single 30-second network hiccup kills your entire job run and blocks downstream reporting. You're forced to manually re-trigger pipelines, accumulating data quality debt. With it, 95% of transient failures resolve silently, and you only alert when genuine problems persist across all retry attempts.

The exponential component matters: hammering a failing service immediately makes it worse (thundering herd), while a naive fixed delay wastes time on recoverable failures. Exponential backoff balances responsiveness with respect for overloaded systems, typically capping at a maximum interval (e.g., 30s) to avoid runaway waits.

## Practice

**Problem:** Your daily `job_postings_fact` load pulls data from an unstable vendor API that returns 503 errors ~5% of the time. Without retries, your 8 AM pipeline fails before analysts see refreshed salary benchmarks, requiring manual re-run.

**Solution:**

```sql
-- Pseudo-code for Airbnb Airflow / Python orchestration context
from airflow.decorators import task
from tenacity import retry, stop_after_attempt, wait_exponential

@task
@retry(
  stop=stop_after_attempt(5),
  wait=wait_exponential(multiplier=1, min=2, max=30)
)
def load_job_postings_fact():
  """
  Attempt up to 5 times with backoff: 2s, 4s, 8s, 16s, 30s.
  If vendor API fails, wait before retry.
  """
  response = requests.get("https://api.vendor.com/jobs")
  response.raise_for_status()  # Raise exception on 503
  
  data = response.json()
  
  sql_insert = """
    INSERT INTO job_postings_fact 
    (job_id, job_title_short, salary_year_avg, job_work_from_home, job_posted_date, job_location)
    VALUES (%s, %s, %s, %s, %s, %s)
    ON CONFLICT (job_id) DO UPDATE SET job_posted_date = EXCLUDED.job_posted_date
  """
  
  with psycopg2.connect(...) as conn:
    cur = conn.cursor()
    for job in data['jobs']:
      cur.execute(sql_insert, (
        job['id'], job['title_short'], job['salary_avg'], 
        job['remote'], job['posted_date'], job['location']
      ))
    conn.commit()
```

Pipeline retries 5 times over ~60s; 99% of transient API failures succeed by attempt 2–3. Only genuine outages surface as alerts.

## Notes

- **Retry only transient errors:** Distinguish 503 (retry) from 400 (don't retry). Bad SQL or invalid credentials won't fix themselves; respect that boundary or waste credits.
- **Idempotency is non-negotiable:** Retries only work safely if re-running the same operation twice produces the same result. Use `ON CONFLICT DO UPDATE` or upsert logic; never assume inserts are fresh.
- **Set a max retry budget:** Unbounded retries can delay pipeline completion past SLA. Cap attempts (usually 3–5) and max elapsed time (e.g., 5 minutes) to fail fast when real problems exist.
- **Log each attempt:** Record attempt count, wait duration, and error reason. Downstream troubleshooting depends on knowing if a load succeeded on attempt 1 or attempt 4.
- **Connects to:** circuit breakers (stop retrying a permanently broken service), dead-letter queues (quarantine unsalvageable records), and observability dashboards (track retry frequency as an early warning signal).
