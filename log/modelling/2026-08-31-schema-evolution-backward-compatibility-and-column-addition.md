---
date: 2026-08-31
phase: modelling
topic: Schema evolution: backward compatibility and column addition
---

# Schema evolution: backward compatibility and column addition

*Data modelling and warehousing*

## Concept

Schema evolution is the controlled process of modifying a table structure—adding columns, changing types, deprecating fields—without breaking existing queries and pipelines. Backward compatibility means new schema versions work with code written for old versions; when you add a column, old queries should still run without modification.

This matters because data warehouses serve multiple consumers: dashboards, reports, ML pipelines, and ad-hoc analysts all depend on stable table structures. Without backward-compatible evolution, adding a single column forces you to update every downstream dependency simultaneously, creating a coordination nightmare and blocking schema improvements.

Breaking evolution looks like: renaming a column (old queries fail), changing a NOT NULL constraint without defaults (inserts fail), or dropping a column still referenced elsewhere. Instead, backward-compatible evolution adds columns with sensible defaults, marks deprecated fields for future removal, and uses naming conventions that signal intent to consumers.

## Practice

**Problem:** Your `job_postings_fact` table is live and queried by 12 different dashboards. The business now wants to track `job_salary_currency` (defaulting to 'USD') and `job_posting_status` (either 'active' or 'archived', defaulting to 'active'). How do you add these without breaking existing queries?

```sql
-- Add new columns with NOT NULL + DEFAULT so existing rows are populated
-- and new inserts don't require explicit values from callers
ALTER TABLE job_postings_fact
ADD COLUMN job_salary_currency VARCHAR(3) NOT NULL DEFAULT 'USD',
ADD COLUMN job_posting_status VARCHAR(20) NOT NULL DEFAULT 'active';

-- Old query still works unchanged:
SELECT job_id, job_title_short, salary_year_avg 
FROM job_postings_fact 
WHERE job_posted_date > '2024-01-01';

-- New code can use the new columns:
SELECT job_id, salary_year_avg, job_salary_currency, job_posting_status
FROM job_postings_fact
WHERE job_posting_status = 'active';
```

## Notes

- **Nullable vs. defaults:** `NOT NULL DEFAULT 'active'` is safer than nullable; it guarantees existing rows won't have NULLs and makes consumers' logic simpler (no null checks needed retroactively).
- **Naming conventions signal stability:** prefix deprecated columns with `_deprecated_` or `_legacy_` so analysts know not to build new work on them; version your column names only if a field genuinely changes meaning (e.g., `salary_year_avg_v2`).
- **Document additions in metadata:** DDL comments or a schema registry (dbt, Collibra, Confluent Schema Registry) let consumers discover why a column exists and when it was added; don't rely on word-of-mouth.
- **Connects to:** data contracts (formal agreements between producer and consumer), CI/CD for schema changes (test impact before merging), and lineage tracking (knowing which dashboards depend on which columns).
- **Revisit:** how this scales with hundreds of columns (consider wide tables vs. normalized design) and how to handle breaking changes *when* they're unavoidable (versioned views, deprecation windows, feature flags in consuming code).
