---
date: 2026-08-22
phase: pipelines
topic: Two-phase commit vs saga for distributed transactions
---

# Two-phase commit vs saga for distributed transactions

*Pipelines and orchestration*

## Concept

**Two-phase commit (2PC)** coordinates writes across multiple databases by requiring all participants to lock resources, vote "yes/no," then commit atomically. It guarantees consistency but blocks resources during coordination, making it fragile in distributed systems—if a coordinator crashes mid-commit, participants hang indefinitely.

**Sagas** break a distributed transaction into a sequence of local transactions, each with a compensating action (rollback logic). If step N fails, the saga executes compensations for steps 1 through N-1. Sagas don't lock resources globally and tolerate coordinator failures, but they require explicit compensation code and may leave partial writes visible during execution.

In data pipelines, 2PC suits tightly-coupled systems with fast networks and high availability (rare). Sagas suit the realistic case: inserting a job posting fact into a data warehouse while updating search indices and triggering downstream jobs. If the index write fails, you compensate by marking the fact record as "unindexed" rather than rolling back everything. Sagas fail loud (you see the compensation) and rerun safely (compensation is idempotent).

## Practice

**Problem:** Load job postings into `job_postings_fact`, sync to Elasticsearch, and notify the recommendations service. If the Elasticsearch write fails halfway through a batch, the fact table already has partial writes. You need atomic visibility or safe recovery.

```sql
-- Saga approach: add compensation columns to track state
ALTER TABLE job_postings_fact ADD COLUMN sync_status VARCHAR(20) DEFAULT 'pending';
ALTER TABLE job_postings_fact ADD COLUMN es_doc_id VARCHAR(256);

-- Step 1: Insert facts with sync_status='pending'
INSERT INTO job_postings_fact 
  (job_id, job_title_short, salary_year_avg, job_work_from_home, job_posted_date, job_location, sync_status)
VALUES 
  (101, 'Data Engineer', 125000, true, '2024-01-15', 'Remote', 'pending'),
  (102, 'Analytics Lead', 135000, false, '2024-01-16', 'NYC', 'pending');

-- Step 2: Update to 'synced' only after ES write succeeds
UPDATE job_postings_fact 
SET sync_status = 'synced', es_doc_id = ? 
WHERE job_id IN (101, 102);

-- Compensation (rollback): if ES or notifications fail, mark for retry
UPDATE job_postings_fact 
SET sync_status = 'es_failed' 
WHERE job_id IN (101, 102);

-- Rerun safely: retry only jobs in 'es_failed' or 'pending' state
SELECT * FROM job_postings_fact 
WHERE sync_status IN ('pending', 'es_failed') 
ORDER BY job_posted_date DESC;
```

## Notes

- **2PC hidden cost:** Even with "fast" networks, a single slow participant blocks all others. In data pipelines this serializes parallel loads.
- **Saga complexity:** Compensation logic must be idempotent (safe to run twice) and ordered correctly. Document which writes are reversible and which leave residue.
- **Visibility during saga:** Downstream consumers may see incomplete writes before compensation runs. Use status columns (`sync_status`, `_processed_at`) to signal readiness.
- **Adjacent topics:** Idempotent keys, event sourcing (audit trail of saga steps), dead-letter queues (where failed sagas sit for replay).
- **Revisit:** When designing sagas, list what each step writes and what failure means; sagas that span >5 steps often signal a need to split pipelines.
