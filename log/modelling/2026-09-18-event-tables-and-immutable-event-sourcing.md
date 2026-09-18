---
date: 2026-09-18
phase: modelling
topic: Event tables and immutable event sourcing
---

# Event tables and immutable event sourcing

*Data modelling and warehousing*

## Concept

Event tables record immutable, append-only facts about what happened at a specific point in time. Unlike dimensional tables that update in place, event tables preserve the complete history—every state change becomes a new row with a timestamp. This matters because it lets you replay exactly what occurred, audit who changed what and when, and answer retroactive questions ("what was the price on day X?") without losing data to overwrites.

Without immutable events, you lose the audit trail. A job posting that changed salary three times leaves you with only the final number. Event sourcing also solves the "slowly changing dimension" problem elegantly: instead of SCD Type 2 logic (versioning rows with effective dates), you simply append. Queries become harder to accidentally break because the raw facts never vanish—only derived views change.

## Practice

**Problem:** The `job_postings_fact` table currently updates salary in place. You need to track when salaries change, know what the salary was on any given date, and audit salary edits for compliance.

```sql
-- Event table: immutable log of salary events
CREATE TABLE job_postings_events (
  event_id BIGINT PRIMARY KEY,
  job_id INT NOT NULL,
  event_type VARCHAR(50) NOT NULL,  -- 'posted', 'salary_updated', 'closed'
  job_title_short VARCHAR(255),
  salary_year_avg INT,
  job_work_from_home BOOLEAN,
  job_location VARCHAR(255),
  event_timestamp TIMESTAMP NOT NULL,
  recorded_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- Insert: initial job posting
INSERT INTO job_postings_events 
  (job_id, event_type, job_title_short, salary_year_avg, job_work_from_home, job_location, event_timestamp)
VALUES (42, 'posted', 'Data Engineer', 120000, TRUE, 'Remote', '2024-01-15 09:00:00');

-- Salary update two weeks later—new row, old row untouched
INSERT INTO job_postings_events 
  (job_id, event_type, job_title_short, salary_year_avg, job_work_from_home, job_location, event_timestamp)
VALUES (42, 'salary_updated', 'Data Engineer', 135000, TRUE, 'Remote', '2024-01-29 14:30:00');

-- Query: what was the salary on 2024-01-20?
SELECT salary_year_avg
FROM job_postings_events
WHERE job_id = 42
  AND event_timestamp <= '2024-01-20'::TIMESTAMP
ORDER BY event_timestamp DESC
LIMIT 1;
-- Returns 120000

-- Audit trail: all changes to job 42
SELECT event_type, salary_year_avg, event_timestamp, recorded_at
FROM job_postings_events
WHERE job_id = 42
ORDER BY event_timestamp ASC;
```

## Notes

- **Append-only requires discipline:** Never update or delete rows in an event table. If you must correct data, insert a corrective event and mark the bad one as retracted, not erased.
- **Timestamps are critical:** Record both `event_timestamp` (when the business fact occurred) and `recorded_at` (when you learned about it). These can differ by days in delayed pipelines.
- **Connects to CDC (Change Data Capture):** Event tables are the natural output of CDC tools like Debezium. Treat your event log as the source of truth and derive reporting views from it.
- **Materialized views and snapshots:** Don't query raw events for every dashboard; create periodic snapshots (`job_postings_snapshot` as of end-of-day) or materialized views for performance. The event table stays small and fast.
- **Revisit:** Schema registry and versioning become essential when event schemas evolve—track which version of the schema each event uses, or plan migrations carefully.
