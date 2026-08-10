---
date: 2026-08-10
phase: modelling
topic: Surrogate keys vs natural keys
---

# Surrogate keys vs natural keys

*Data modelling and warehousing*

## Concept

A **natural key** is a column or set of columns that uniquely identifies a row by business meaning alone—like an email address, product SKU, or job posting URL. A **surrogate key** is an artificial identifier (usually an auto-incremented integer or UUID) added purely for technical purposes. In data warehousing, surrogate keys matter because they decouple your schema from business logic: natural keys can change (a company rebrand, a postal code split), break referential integrity, or span multiple columns. A surrogate key is stable, compact, and lets you join tables without exposing the complexity of multi-column natural keys to end users. Without it, downstream queries become brittle and your schema becomes a documentation burden.

## Practice

**Problem:** The `job_postings_fact` table uses `job_id` as its only identifier, but job postings from different sources sometimes share the same `job_id` value. Reports are double-counting records. You need a stable primary key that survives data reloads and source system changes, while keeping `job_id` queryable.

```sql
-- Add surrogate key; keep natural key for traceability
CREATE TABLE job_postings_fact (
  job_posting_pk BIGINT PRIMARY KEY,  -- Surrogate key (auto-increment or UUID)
  job_id VARCHAR(100),                -- Natural key from source
  job_source VARCHAR(50),             -- Source system identifier
  job_title_short VARCHAR(100),
  salary_year_avg DECIMAL(10,2),
  job_work_from_home BOOLEAN,
  job_posted_date DATE,
  job_location VARCHAR(100),
  UNIQUE (job_id, job_source)         -- Enforce uniqueness of natural key
);
```

This design guarantees no duplicates, allows historical tracking, and queries remain unambiguous even if `job_id` semantics shift.

## Notes

- **Don't discard the natural key:** Keep it in the table and index it. It's your audit trail and essential for loading logic.
- **Surrogate vs. slowly changing dimensions:** If a natural key *occasionally* changes (job title rebranding), you need SCD Type 2 logic—track surrogate key, add effective dates, keep historical rows.
- **Foreign key joins become simpler:** Fact tables reference dimensions via surrogate keys (job_posting_pk → job_dimension.job_pk), reducing JOIN overhead and schema readability.
- **UUID vs. sequential IDs:** UUIDs avoid merge conflicts and scale across distributed systems; sequential integers are lighter and easier to debug. Choose based on your architecture (single warehouse vs. federated pipeline).
- **Related: Junk dimensions, conformed dimensions, grain.** Once you have clean keys, you can confidently design shared dimension tables that entire teams query without asking "what does this mean?"
