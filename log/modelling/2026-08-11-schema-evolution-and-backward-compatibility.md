---
date: 2026-08-11
phase: modelling
topic: Schema evolution and backward compatibility
---

# Schema evolution and backward compatibility

*Data modelling and warehousing*

## Concept

Schema evolution is the ability to modify a table or dataset structure over time while maintaining the ability for existing queries, dashboards, and downstream consumers to continue working. Backward compatibility means new schema changes don't break old code—typically achieved by *adding* columns rather than removing or renaming them, and by providing sensible defaults for historical data.

This matters because data warehouses are read by many teams simultaneously. A analyst's dashboard written months ago should still run tomorrow even if the underlying table gains new columns. Without backward compatibility, every schema change becomes a coordination nightmare: you must update all dependent queries, retrain users on new column names, and risk breaking production reports.

Without it, you're forced to choose between: breaking existing queries (expensive and error-prone), or creating new tables and managing both (technical debt). The cost compounds quickly across a mature data organization.

## Practice

**Problem:** Your `job_postings_fact` table is in production with 2M rows. A new requirement surfaces: you must track whether each job allows remote work *partially* (not just yes/no). The current boolean `job_work_from_home` is too restrictive. Changing its type to a string will break existing queries that use `WHERE job_work_from_home = TRUE`.

**Solution:**

```sql
-- Step 1: Add new column with richer domain
ALTER TABLE job_postings_fact
ADD COLUMN job_work_location VARCHAR(50) DEFAULT 'on_site';

-- Step 2: Backfill existing data based on old boolean
UPDATE job_postings_fact
SET job_work_location = CASE
  WHEN job_work_from_home = TRUE THEN 'remote'
  WHEN job_work_from_home = FALSE THEN 'on_site'
END;

-- Step 3: Keep old column for 2+ release cycles (deprecation window)
-- Document in schema: "DEPRECATED—use job_work_location instead"

-- Step 4: Old queries continue to work unchanged
SELECT job_title_short, salary_year_avg
FROM job_postings_fact
WHERE job_work_from_home = TRUE;  -- Still valid

-- Step 5: New code uses the richer column
SELECT job_title_short, COUNT(*)
FROM job_postings_fact
WHERE job_work_location IN ('remote', 'hybrid')
GROUP BY job_title_short;
```

## Notes

- **Additive-only rule:** Add columns, never delete or rename without a long deprecation window. Deletion should be invisible to users.
- **Default values are critical:** Any new column must have a sensible default for all historical rows, or backfill logic must be bulletproof.
- **Version your schemas:** Use metadata (schema version, last_modified_date) to help downstream consumers understand what they're reading.
- **Connects to:** data governance (who approves changes), testing practices (validate new columns don't break BI tools), and API design (if exposing data via services, schema changes are even more costly).
- **Revisit:** Avro/Protobuf enforce schema contracts and make evolution explicit; consider them for high-velocity pipelines.
