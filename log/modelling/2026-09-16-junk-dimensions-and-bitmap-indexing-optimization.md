---
date: 2026-09-16
phase: modelling
topic: Junk dimensions and bitmap indexing optimization
---

# Junk dimensions and bitmap indexing optimization

*Data modelling and warehousing*

## Concept

A junk dimension is a grouping of low-cardinality boolean or small-domain attributes into a single dimension table, rather than storing them as separate columns in a fact table. Instead of cluttering `job_postings_fact` with individual boolean columns (`is_remote`, `is_entry_level`, `is_urgent`), you create a `junk_dimension` table that pre-combines all sensible permutations of these flags, assign each combination a surrogate key, and reference that key in the fact table. This reduces fact table width and foreign key count.

Bitmap indexing complements this by storing boolean combinations as compressed bitmaps—particularly efficient when these flags are queried together (e.g., "remote AND entry-level jobs"). Modern databases like Vertica and Exasol apply bitmap indexing automatically; traditional row stores like PostgreSQL benefit when you denormalize these flags into a single junk dimension key that the query planner can index compactly.

Without junk dimensions, fact tables become wide and difficult to scan; without bitmap indexing, OR/AND queries across many small boolean columns perform full table scans. Together, they eliminate the false choice between normalization and query speed: you normalize semantically (grouping related flags) while optimizing physically (one indexed key instead of many).

## Practice

**Problem:** Your `job_postings_fact` has 50 million rows. Analysts frequently query combinations like "remote jobs with average salary > $100k" and "non-remote entry-level roles." Currently, `job_work_from_home` is a single boolean column; over time, columns for `is_entry_level`, `is_contract`, and `is_urgent` will be added. Each new boolean adds table width and slows full scans.

**Solution:**

```sql
-- Create junk dimension for job characteristics
CREATE TABLE job_characteristics_dim (
    job_char_id SMALLINT PRIMARY KEY,
    is_remote BOOLEAN NOT NULL,
    is_entry_level BOOLEAN NOT NULL,
    is_contract BOOLEAN NOT NULL,
    is_urgent BOOLEAN NOT NULL
);

INSERT INTO job_characteristics_dim VALUES
(1, false, false, false, false),
(2, true, false, false, false),
(3, false, true, false, false),
(4, true, true, false, false),
-- ... all 16 combinations for 4 booleans
(16, true, true, true, true);

-- Refactor fact table
ALTER TABLE job_postings_fact
  DROP COLUMN job_work_from_home,
  ADD COLUMN job_char_id SMALLINT REFERENCES job_characteristics_dim(job_char_id);

CREATE INDEX idx_fact_char_salary 
  ON job_postings_fact(job_char_id, salary_year_avg);

-- Query is now compact and indexable
SELECT COUNT(*) 
FROM job_postings_fact f
JOIN job_characteristics_dim c USING (job_char_id)
WHERE c.is_remote = true 
  AND c.is_entry_level = true
  AND f.salary_year_avg > 100000;
```

## Notes

- **Cardinality is key:** junk dimensions work best for attributes with ≤ 20 combinations; beyond that, cost of the dimension table outweighs the fact-table width savings.
- **Bitmap indexing requires density:** if you have 2⁴ = 16 possible combinations but only 3 exist in your data, bitmap compression still wins; if all 16 exist but one row per combination, the index overhead may exceed the scan cost—profile your workload.
- **Maintenance burden:** adding a new boolean flag means regenerating the junk dimension and reloading the fact table; design for anticipated growth, but don't over-engineer for hypothetical columns.
- **Bridges to adjacent topics:** constellations (multiple fact tables sharing a junk dimension), snowflake vs. star trade-offs, and slowly changing dimensions (SCD Type 2) when job characteristics themselves vary over time.
- **Revisit indexing strategy:** bitmap indexes assume OLAP workloads with multi-condition WHERE clauses; OLTP inserts into junk dimensions are cheap (only 2ⁿ rows), but frequent updates to the fact table's junk key should be rare if the dimension is truly static.
