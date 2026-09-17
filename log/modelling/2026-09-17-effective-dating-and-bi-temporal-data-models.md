---
date: 2026-09-17
phase: modelling
topic: Effective dating and bi-temporal data models
---

# Effective dating and bi-temporal data models

*Data modelling and warehousing*

## Concept

Effective dating separates *when data was recorded* (load time) from *when it became true in the business* (business event time). Bi-temporal models track both: the valid time period (when a fact was actually true) and the transaction time (when we learned about it). Without this distinction, you cannot answer "what salary range was posted on this job on March 15?" versus "what did we know about this job's salary on March 15?" — and those are different questions when data arrives late, gets corrected, or reflects retroactive changes.

This matters most in hiring, HR, and contract work where job attributes change (salary adjustments, remote status flips, location closures) and historical accuracy is auditable. Without bi-temporal columns, you overwrite history; with them, you preserve it and allow point-in-time queries that don't require asking a human "what does the data actually mean?"

Breaking without it: you lose auditability (why did the salary change?), cannot rebuild past reports accurately, and cannot detect data quality issues (late-arriving corrections look like spontaneous changes). Stakeholders end up querying you instead of the schema.

## Practice

**Problem:** A job posting's salary was recorded as $60k on 2025-01-10, but on 2025-02-01 we receive a correction indicating it was actually $75k at time of posting (2025-01-05). You need to support both "what salary did we know on 2025-01-15?" and "what was the true salary on 2025-01-05?"

```sql
CREATE TABLE job_postings_fact (
    job_id INT,
    job_title_short VARCHAR,
    salary_year_avg DECIMAL,
    job_work_from_home BOOLEAN,
    job_location VARCHAR,
    valid_from DATE,           -- when this fact became true in the business
    valid_to DATE,             -- when this fact stopped being true (null = current)
    load_ts TIMESTAMP,         -- when this row was inserted into the warehouse
    source_system VARCHAR,
    PRIMARY KEY (job_id, valid_from, load_ts)
);

-- Query 1: "What salary did we know on Jan 15?"
SELECT job_id, salary_year_avg
FROM job_postings_fact
WHERE job_id = 123
  AND load_ts <= '2025-01-15 23:59:59'
  AND valid_from <= '2025-01-15'
  AND (valid_to IS NULL OR valid_to > '2025-01-15')
ORDER BY load_ts DESC
LIMIT 1;

-- Query 2: "What was the true salary on Jan 5?" (latest correction)
SELECT job_id, salary_year_avg
FROM job_postings_fact
WHERE job_id = 123
  AND valid_from <= '2025-01-05'
  AND (valid_to IS NULL OR valid_to > '2025-01-05')
ORDER BY load_ts DESC
LIMIT 1;
```

## Notes

- **Type 2 SCD temptation:** Don't confuse valid_from/valid_to with Slowly Changing Dimension type 2; SCD2 tracks dimension changes in a star schema, while bi-temporal tracks fact corrections and business events. Both can coexist.
- **Null handling:** `valid_to IS NULL` means "still current" — make this explicit in comments and consider a sentinel date (9999-12-31) if your query engine struggles with NULLs in range predicates.
- **Late-arriving data trap:** Load_ts must be *insertion* time, not the time you *processed* the file. If you backload Jan data in March, load_ts = March date, not January.
- **Audit trail vs. performance:** Bi-temporal schemas grow fast (every correction adds rows). Archive old transaction times after regulatory retention expires; partition on load_ts to keep queries fast.
- **Adjacent: data lineage, slowly changing dimensions, audit logging.** Revisit when adding schema evolution (new columns) — you'll need to decide: does a new column apply to all historical rows, or only forward?
