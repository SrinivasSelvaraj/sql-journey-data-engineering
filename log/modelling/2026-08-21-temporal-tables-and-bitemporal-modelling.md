---
date: 2026-08-21
phase: modelling
topic: Temporal tables and bitemporal modelling
---

# Temporal tables and bitemporal modelling

*Data modelling and warehousing*

## Concept

Temporal tables track **when** data was true, not just what the data is. Bitemporal modelling tracks two timestamps: *valid time* (when the fact was true in reality) and *transaction time* (when it was recorded in the system). This matters because real-world facts change—a salary band is adjusted, a job location shifts to hybrid—but you often need to report "what did we know on date X?" and "what was actually true on date Y?" without these dimensions, you either lose history or can't distinguish between a correction and a real change.

Without temporal modelling, you either overwrite old records (losing audit trail), duplicate rows with no clear version (confusion on which is current), or build expensive point-in-time snapshots as an afterthought. Bitemporal design bakes this in from schema creation: you record both when a fact became true and when you learned about it, enabling correct historical analysis and regulatory compliance without costly refactoring.

## Practice

**Problem:** Job postings are updated frequently—salary ranges are corrected, remote status changes, locations are clarified. Your analytics team needs to answer: "What salary range did we *know* was accurate on 2024-03-15?" and separately, "What salary range was *actually true* on 2024-03-15?" Without temporal columns, you cannot distinguish between these.

```sql
-- Bitemporal job_postings_fact
CREATE TABLE job_postings_fact (
    job_id INT,
    job_title_short VARCHAR(50),
    salary_year_avg INT,
    job_work_from_home BOOLEAN,
    job_location VARCHAR(100),
    
    -- Valid time: when this fact was true in reality
    valid_from DATE,
    valid_to DATE,
    
    -- Transaction time: when this record entered the warehouse
    transaction_from TIMESTAMP,
    transaction_to TIMESTAMP,
    
    PRIMARY KEY (job_id, valid_from, transaction_from)
);

-- Example: Job 1001 salary corrected on 2024-03-20
INSERT INTO job_postings_fact 
VALUES (1001, 'Data Engineer', 95000, TRUE, 'Remote', 
        '2024-01-01', '2024-03-19', '2024-01-05 10:00:00', '2024-03-20 08:00:00');
INSERT INTO job_postings_fact 
VALUES (1001, 'Data Engineer', 105000, TRUE, 'Remote', 
        '2024-01-01', '9999-12-31', '2024-03-20 08:00:00', NULL);

-- Query: What did we know on 2024-03-15?
SELECT * FROM job_postings_fact 
WHERE valid_from <= '2024-03-15' 
  AND valid_to > '2024-03-15'
  AND transaction_from <= '2024-03-15'
  AND (transaction_to IS NULL OR transaction_to > '2024-03-15');

-- Query: What was actually true on 2024-03-15?
SELECT * FROM job_postings_fact 
WHERE valid_from <= '2024-03-15' 
  AND valid_to > '2024-03-15'
  AND transaction_to IS NULL; -- Current version
```

## Notes

- **SCD Type 2 vs. bitemporal:** SCD Type 2 tracks *valid time* only (surrogate keys, valid_from/to); bitemporal adds *transaction time* for full audit. Choose bitemporal only if you need to replay what was known at past dates.
- **NULL vs. 9999-12-31:** Use NULL for `transaction_to` (current record) or '9999-12-31' for `valid_to` (open-ended). Be consistent; NULL is clearer for "still active."
- **Query complexity:** Bitemporal queries are verbose; encapsulate them in views or stored procedures so analysts query intent ("as-of" or "current") not temporal logic.
- **Slowly changing dimensions connection:** Temporal tables are often the backbone of SCD implementations; revisit when you need to version dimensions in a data warehouse.
- **Watch for:** Not closing out old records (`valid_to` left NULL) or conflating corrections (new transaction) with actual changes (new valid period). Clarify with stakeholders whether corrections rewrite history or create new versions.
