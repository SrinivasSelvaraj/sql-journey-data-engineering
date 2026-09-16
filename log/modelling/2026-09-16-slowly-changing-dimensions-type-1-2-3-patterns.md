---
date: 2026-09-16
phase: modelling
topic: Slowly changing dimensions: Type 1, 2, 3 patterns
---

# Slowly changing dimensions: Type 1, 2, 3 patterns

*Data modelling and warehousing*

## Concept

A slowly changing dimension (SCD) is a strategy for handling updates to reference data in a data warehouse—deciding whether to overwrite old values, keep history, or do both. Without a deliberate SCD approach, you either lose audit trails (Type 1), bloat your fact table with redundant dimension keys (Type 2 done wrong), or create unmaintainable lookup tables (Type 3 done wrong).

The pattern matters most when dimensions change infrequently but meaningfully: job titles get rebranded, locations consolidate, salary bands shift. If you don't choose an SCD type upfront, you'll face either (a) queries that can't answer "what was the salary band when this job was posted?" or (b) a mess of multiple rows per job with overlapping dates that nobody trusts.

In practice, the choice depends on your use case: preserve historical accuracy (Type 2), keep the table small and only care about current state (Type 1), or track both current *and* one previous value (Type 3). Most data warehouses use a mix across different dimensions.

## Practice

**Problem:** Job titles are rebranded quarterly. A analyst needs to report "how many active postings per job title *as of the date they were posted*" without the title changing retroactively when you refresh the dimension table.

```sql
-- Type 2: Create a job_titles_dim with slowly changing history
CREATE TABLE job_titles_dim (
  job_title_key SERIAL PRIMARY KEY,
  job_id INT,
  job_title_short VARCHAR(100),
  effective_date DATE,
  end_date DATE,
  is_current BOOLEAN,
  UNIQUE(job_id, effective_date)
);

-- Insert initial load
INSERT INTO job_titles_dim (job_id, job_title_short, effective_date, end_date, is_current)
SELECT DISTINCT job_id, job_title_short, job_posted_date, '9999-12-31'::DATE, TRUE
FROM job_postings_fact;

-- When a title changes, close the old row and insert a new one
BEGIN;
UPDATE job_titles_dim 
SET end_date = CURRENT_DATE - 1, is_current = FALSE
WHERE job_id = 123 AND is_current = TRUE;

INSERT INTO job_titles_dim (job_id, job_title_short, effective_date, end_date, is_current)
VALUES (123, 'Senior Engineer (New Brand)', CURRENT_DATE, '9999-12-31'::DATE, TRUE);
COMMIT;

-- Query: accurate title per posting date
SELECT 
  jpf.job_id,
  jpf.job_posted_date,
  jtd.job_title_short,
  COUNT(*) as posting_count
FROM job_postings_fact jpf
INNER JOIN job_titles_dim jtd 
  ON jpf.job_id = jtd.job_id
  AND jpf.job_posted_date BETWEEN jtd.effective_date AND jtd.end_date
GROUP BY jpf.job_id, jpf.job_posted_date, jtd.job_title_short;
```

## Notes

- **Type 1 (overwrite)** is fastest and cheapest—use it only when history doesn't matter (e.g., correcting a typo in a location name).
- **Type 2 (add row with dates)** doubles or triples dimension table size but enables precise historical reporting; always include `is_current` flag for fast current-state queries.
- **Type 3 (add column)** stores only current *and* previous value in one row—useful for tracking one-level changes but breaks down with rapid churn; rarely worth the complexity.
- **Adjacent concept:** Bridge tables and factless fact tables often pair with Type 2 dimensions to handle many-to-many relationships (e.g., one job posting with multiple skills).
- **Common mistake:** Forgetting to join on effective/end dates in queries—you'll get duplicate rows and wrong counts. Make the join condition explicit in your team's query templates.
