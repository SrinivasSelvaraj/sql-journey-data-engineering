---
date: 2026-10-01
phase: reliability
topic: Retry budgets: limiting retry storms for cascading failures
---

# Retry budgets: limiting retry storms for cascading failures

*Quality, reliability and the professional layer*

## Concept

A retry budget is a fixed allocation of retry attempts across a time window that prevents a single failing task from triggering exponential cascades of retries across dependent systems. Without it, one upstream failure can balloon into thousands of retry requests hitting already-stressed services, amplifying the original problem rather than solving it. This is the difference between a graceful degradation and a complete meltdown: a job_postings_fact load fails, retries with exponential backoff, but those retries fail too—now your job_location enrichment service, your salary aggregation, and your downstream dashboards all pile on retry requests to the same failing source, creating a retry storm.

Retry budgets matter most at the professional layer because they force you to make explicit trade-offs: you can retry 3 times in 5 minutes, or you can circuit-break and alert ops. You stop treating retries as "free" and start treating them as a resource you're spending. This is especially critical in data pipelines where a single failed API call or database connection can trigger cascading retries across dozens of dependent jobs running on shared infrastructure. Without a budget, you become the person whose pipeline accidentally DDOS'd the company's data warehouse at 3am.

## Practice

**Problem:** Your job_postings_fact pipeline fetches fresh listings from an external job board API every 15 minutes. The API goes down. Your pipeline retries aggressively (exponential backoff: 1s, 2s, 4s, 8s...). Within 2 minutes, you've made 40 retry attempts, each one hitting a service that's already struggling. Three other pipelines that depend on job_postings_fact also start retrying their transformations. The warehouse connection pool exhausts. Everything fails.

**Solution:** Implement a retry budget at the ingest layer:

```sql
-- Create retry tracking table
CREATE TABLE IF NOT EXISTS pipeline_retry_budget (
    pipeline_name VARCHAR,
    window_start TIMESTAMP,
    retry_count INT DEFAULT 0,
    max_retries INT DEFAULT 3,
    circuit_open BOOLEAN DEFAULT FALSE,
    last_retry_at TIMESTAMP,
    PRIMARY KEY (pipeline_name, window_start)
);

-- Before retrying job_postings fetch, check budget
SELECT 
    CASE 
        WHEN circuit_open THEN 'CIRCUIT_OPEN'
        WHEN retry_count >= max_retries THEN 'BUDGET_EXHAUSTED'
        ELSE 'RETRY_ALLOWED'
    END as retry_status,
    retry_count,
    max_retries - retry_count as remaining_budget
FROM pipeline_retry_budget
WHERE pipeline_name = 'job_postings_ingest'
    AND window_start = DATE_TRUNC('minute', CURRENT_TIMESTAMP);

-- Log retry attempt and update budget
INSERT INTO pipeline_retry_budget (pipeline_name, window_start, retry_count, last_retry_at)
VALUES ('job_postings_ingest', DATE_TRUNC('minute', CURRENT_TIMESTAMP), 1, CURRENT_TIMESTAMP)
ON CONFLICT (pipeline_name, window_start) 
DO UPDATE SET 
    retry_count = retry_count + 1,
    circuit_open = CASE WHEN retry_count + 1 >= max_retries THEN TRUE ELSE FALSE END,
    last_retry_at = CURRENT_TIMESTAMP;

-- When circuit opens, alert instead of retrying
INSERT INTO alerts (severity, message, pipeline_name)
SELECT 'CRITICAL', 
       'job_postings_ingest retry budget exhausted; circuit open for 5 minutes',
       'job_postings_ingest'
WHERE EXISTS (SELECT 1 FROM pipeline_retry_budget 
              WHERE circuit_open = TRUE 
              AND pipeline_name = 'job_postings_ingest');
```

## Notes

- **Common mistake:** Treating retry budgets as uniform across all pipelines. A real-time alerting pipeline might have a 10-retry budget; a batch warehouse load might have 2. Align budget to criticality and expected failure modes, not convenience.

- **Adjacent topic:** Circuit breakers are the enforcement mechanism; retry budgets are the policy. Together they prevent cascading failures. Also study exponential backoff + jitter to avoid thundering herd (all retries happening simultaneously).

- **Alerting as a first-class output:** When a retry budget exhausts, that's not a silent failure—it's the signal that humans need to intervene. Treat budget exhaustion as an alert trigger, not a swallowed error.

- **Cross-pipeline visibility:** Document retry budgets per pipeline in your DAG metadata or monitoring system. This is how the person on-call at 2am understands why job_postings_fact stopped and everything downstream is stale.

- **Revisit after incidents:** Every production retry storm should trigger a postmortem question: "What was the retry budget, and was it set correctly?" Budget tuning is data-driven, not guesswork.
