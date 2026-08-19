---
date: 2026-08-19
phase: sql
topic: Bitwise operations for flag columns
---

# Bitwise operations for flag columns

*SQL for analytics and engineering*

## Concept

Bitwise operations allow you to pack multiple boolean flags into a single integer column, saving storage and enabling efficient filtering. Each bit position represents one flag—bit 0 might represent "remote eligible," bit 1 "has signing bonus," bit 2 "sponsorship available," and so on. Instead of storing five separate BOOLEAN columns that each consume 1 byte per row, you use one INTEGER that consumes 4–8 bytes total.

This matters most when you have many flags that rarely change and need fast filtering at scale. A table with 10M rows saves ~40MB of storage per flag column you consolidate. More importantly, bitwise predicates execute faster because you're checking a single integer comparison rather than evaluating multiple boolean columns in a WHERE clause. Systems like Snowflake and PostgreSQL optimize bitwise AND/OR operations into single CPU instructions.

Without understanding bitwise operations, you either bloat schemas with dozens of boolean columns, or you lose query performance when filtering on multiple flags. You also miss opportunities to use bitmasks for role-based access control, feature flags in analytics tables, or status tracking in event streams where compactness and speed matter.

## Practice

**Problem:** You're adding job attributes to `job_postings_fact`. Instead of five new BOOLEAN columns (remote_eligible, has_signing_bonus, sponsorship, travel_required, visa_sponsorship), encode them as bit flags in a single `job_flags` INTEGER column. Write a query that creates this column, then write a query that filters for jobs that are remote-eligible AND offer sponsorship.

```sql
-- Create and populate the flags column (bit 0=remote, bit 1=signing_bonus, bit 2=sponsorship, bit 3=travel, bit 4=visa)
ALTER TABLE job_postings_fact ADD COLUMN job_flags INTEGER DEFAULT 0;

UPDATE job_postings_fact
SET job_flags = 
  (CASE WHEN job_work_from_home THEN 1 ELSE 0 END) << 0 |
  (CASE WHEN salary_year_avg > 150000 THEN 1 ELSE 0 END) << 1 |
  (CASE WHEN job_title_short ILIKE '%senior%' THEN 1 ELSE 0 END) << 2;

-- Filter: remote-eligible (bit 0) AND senior-level (bit 2)
SELECT job_id, job_title_short, salary_year_avg
FROM job_postings_fact
WHERE (job_flags & ((1 << 0) | (1 << 2))) = ((1 << 0) | (1 << 2))
ORDER BY job_posted_date DESC;
```

## Notes

- **Bit indexing confusion:** `1 << 0` is bit 0 (value 1), `1 << 1` is bit 1 (value 2), `1 << n` is 2^n. Use a comment block to document which bit represents what so teammates don't flip flags by accident.

- **XOR vs AND for checking:** Use `(flags & mask) = mask` to check if all bits in a mask are set. XOR is for toggle/flip operations; AND is for testing presence.

- **Interoperates with role-based access control:** Flags often encode permissions—read (bit 0), write (bit 1), delete (bit 2)—allowing you to check user access with one integer comparison instead of a join to a permissions table.

- **Database-specific: know your bitwise functions.** PostgreSQL uses `&`, `|`, `<<`, `>>` directly; MySQL and T-SQL are the same; Snowflake requires `BITAND()`, `BITOR()`, `BITSHIFTLEFT()`. Check docs before writing production code.

- **Revisit when:** working with feature flags in analytics, building permission matrices, or optimizing tables with >100M rows where every byte counts. Also relevant for event stream deduplication (marking which transformations have run on a record).
