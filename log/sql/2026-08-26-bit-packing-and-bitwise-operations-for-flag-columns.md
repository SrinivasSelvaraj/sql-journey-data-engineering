---
date: 2026-08-26
phase: sql
topic: Bit packing and bitwise operations for flag columns
---

# Bit packing and bitwise operations for flag columns

*SQL for analytics and engineering*

## Concept

Bit packing stores multiple Boolean or small integer flags in a single column using bitwise operations, reducing storage overhead and enabling fast flag filtering without joins. Instead of five separate BOOLEAN columns consuming five bytes per row, you can pack them into a single INTEGER (typically 32 or 64 bits), cutting storage by 80% while improving cache locality and query performance on analytics workloads.

This matters most in fact tables with hundreds of millions of rows where flag columns are common: remote work, visa sponsorship, healthcare coverage, etc. Without bit packing, you join to dimension tables or maintain denormalized Boolean columns that bloat your table size and slow full-table scans. With it, you use bitwise AND (`&`), OR (`|`), and XOR (`^`) operators to test and set flags in microseconds.

However, bit packing is only worth the complexity if: (1) you have many flags (5+) on a hot table, (2) you filter those flags frequently in analytics queries, and (3) your SQL dialect supports efficient bitwise operations. Premature bit packing obscures intent and makes maintenance harder—profile first, then pack.

## Practice

**Problem:** You have a jobs table with separate BOOLEAN columns for `job_work_from_home`, `job_visa_sponsored` (implicit in job title patterns), and `job_has_salary`. You need to efficiently query: "How many remote, visa-sponsored jobs with posted salaries exist in each location?" The current query scans and filters across three columns. Show how to pack these three flags into a single integer and write the optimized filter.

```sql
-- Packing flags into bit positions (at load time or in a materialized view)
-- Bit 0: work_from_home, Bit 1: visa_sponsored, Bit 2: has_salary
CREATE TABLE job_postings_packed AS
SELECT
  job_id,
  job_title_short,
  salary_year_avg,
  job_posted_date,
  job_location,
  (CAST(job_work_from_home AS INTEGER) << 0)
  | (CAST(job_visa_sponsored AS INTEGER) << 1)
  | (CAST(CASE WHEN salary_year_avg IS NOT NULL THEN 1 ELSE 0 END AS INTEGER) << 2)
  AS job_flags
FROM job_postings_fact;

-- Efficient filter using bitwise AND
-- Test if bits 0, 1, and 2 are all set (0b111 = 7)
SELECT
  job_location,
  COUNT(*) AS remote_sponsored_salaried_count
FROM job_postings_packed
WHERE (job_flags & 7) = 7  -- All three flags set
GROUP BY job_location
ORDER BY remote_sponsored_salaried_count DESC;

-- Individual flag checks
SELECT job_title_short
FROM job_postings_packed
WHERE (job_flags & (1 << 0)) > 0  -- Remote only
  AND (job_flags & (1 << 2)) = 0; -- No salary posted
```

## Notes

- **Bit ordering discipline:** Document your bit layout explicitly (e.g., in a comment or enum). Swapping bits mid-project causes silent logic bugs. Use named constants (`REMOTE_FLAG = 1 << 0`) in production.
- **Readability vs. performance trade-off:** Bitwise filters are cryptic to junior engineers. If your query is run once per quarter, clear Boolean columns are better. Use bit packing only for queries in the critical path (dashboards, real-time API calls).
- **Database support variance:** PostgreSQL, MySQL, and SQLite all support bitwise ops, but performance and syntax differ. Test on your target system; some databases optimize `(flags & X) > 0` better than `(flags & X) = X`.
- **Adjacent topic—denormalization and materialized views:** Bit packing is often paired with materialized views to hide complexity. Users query the packed table; ETL handles packing logic. This keeps analytics code clean while gaining performance.
- **Revisit when:** Adding a fourth or fifth flag, or if your query plan shows full-table scans on 1B+ row tables where Boolean column cardinality filtering is weak.
