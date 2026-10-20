---
date: 2026-10-20
phase: reliability
topic: Database failover and connection retry logic
---

# Database failover and connection retry logic

*Quality, reliability and the professional layer*

## Concept

Database failover is the automatic or semi-automatic process of redirecting application traffic from a failed primary database instance to a healthy replica or standby. Connection retry logic is the client-side mechanism that detects transient failures (network hiccups, temporary unavailability, connection pool exhaustion) and reattempts the operation with exponential backoff and jitter, rather than immediately surfacing the error to users.

Without these patterns, a single database restart or brief network disruption crashes your entire pipeline. A data engineer without failover strategy owns brittle infrastructure that fails visibly and requires manual intervention. With them, you get resilience: the difference between "the job failed at 2 AM and nobody noticed until 9 AM" and "the job transparently recovered and completed on schedule."

The professional layer recognizes that production reliability isn't about code perfection—it's about graceful degradation. Failover and retry logic are force multipliers: they let small teams own large, critical pipelines because failures become recoverable events, not catastrophes.

## Practice

**Problem**: Your nightly job ingests `job_postings_fact` from a primary PostgreSQL database. The primary undergoes maintenance at 2 AM with a planned 30-second failover to a hot standby. Without retry logic, your job fails immediately. Design a solution that survives this.

```sql
-- Use a connection string with failover parameters (PostgreSQL example)
-- Connection string for application config:
postgresql://user:password@primary-db:5432,standby-db:5432/jobs_db?
  target_session_attrs=read-write&
  connect_timeout=10&
  statement_timeout=30000

-- Application-level retry wrapper (pseudocode pattern)
-- Implement in your ETL framework (dbt, Airflow, custom Python):

WITH retry_config AS (
  SELECT 
    max_attempts := 3,
    base_delay_ms := 500,
    max_delay_ms := 5000
)
SELECT 
  job_id,
  job_title_short,
  salary_year_avg,
  job_work_from_home,
  job_posted_date,
  job_location
FROM job_postings_fact
WHERE job_posted_date >= CURRENT_DATE - INTERVAL '1 day'
  AND job_location IS NOT NULL
LIMIT 1000000;

-- Implementation pattern (Python + psycopg2):
import time
import psycopg2
from psycopg2 import OperationalError

def fetch_with_retry(query, max_attempts=3, base_delay=0.5):
    for attempt in range(1, max_attempts + 1):
        try:
            conn = psycopg2.connect(
                "postgresql://user:password@primary-db:5432,standby-db:5432/jobs_db"
            )
            cursor = conn.cursor()
            cursor.execute(query)
            return cursor.fetchall()
        except (OperationalError, psycopg2.DatabaseError) as e:
            if attempt == max_attempts:
                raise
            delay = min(base_delay * (2 ** (attempt - 1)), 5.0)
            print(f"Attempt {attempt} failed, retrying in {delay}s: {e}")
            time.sleep(delay)
```

## Notes

- **Exponential backoff + jitter**: Always use backoff (delay grows with retries) and add randomness to jitter. Without jitter, all clients retry simultaneously and hammer the recovering database, causing cascading failure.

- **Distinguish transient from permanent**: Network timeouts and "database unavailable" are retriable. Schema errors and permission denied are not. Retrying the wrong errors wastes time and masks real problems.

- **Connection pooling is prerequisite**: Retry logic is useless if your pool is misconfigured. Too small and you exhaust connections under load; too large and you bloat memory and overwhelm the database. Set realistic pool sizes and test them under failure.

- **Observe and alert on retry rates**: High retry counts signal a degraded database or network. Instrument your retry logic: log attempts, emit metrics, alert ops. A silent recovery that happens 100 times per run is a reliability debt you don't know you're paying.

- **Test failover manually**: Don't discover failover bugs in production. Periodically restart your database, kill network connections, or simulate latency and verify your pipeline recovers. Chaos engineering at small scale prevents surprises at large scale.
