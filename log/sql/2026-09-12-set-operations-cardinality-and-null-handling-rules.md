---
date: 2026-09-12
phase: sql
topic: Set operations cardinality and NULL handling rules
---

# Set operations cardinality and NULL handling rules

*SQL for analytics and engineering*

## Concept

Set operations (UNION, INTERSECT, EXCEPT) combine result sets from multiple queries, but their behavior around NULL and cardinality differs fundamentally from joins. UNION removes duplicates by default and treats NULL as a distinct value—two NULLs are considered equal for deduplication purposes. INTERSECT and EXCEPT also deduplicate and require column count and type compatibility across all SELECT lists, but NULL handling follows the same rule: NULL = NULL evaluates to TRUE in the set operation context (unlike the three-valued logic of WHERE clauses). Cardinality matters because UNION without ALL can become a hidden performance bottleneck—the database must sort or hash-aggregate to eliminate duplicates, while UNION ALL simply concatenates result sets. Understanding when duplicates are semantically correct prevents both wrong answers and unnecessary computational waste.

Set operations fail silently in two ways: (1) you get incorrect row counts because duplicates were unexpectedly removed, and (2) you apply the wrong operation and lose or keep rows that should have been filtered. Misunderstanding NULL behavior causes subtle bugs—a UNION query filtering on a column with NULLs will deduplicate NULLs across branches, potentially losing rows. This matters in analytics when combining data from multiple sources (e.g., active vs. archived job postings) or in engineering when building incremental pipelines.

## Practice

**Problem:** You need to find all unique job locations from two separate tables: current active job postings and historical archived postings. A location should appear only once in the result, even if it appears in both tables. However, you want to preserve NULLs (representing unknown locations) and count them as a single NULL value.

```sql
SELECT job_location
FROM job_postings_fact
WHERE job_posted_date >= CURRENT_DATE - INTERVAL '90 days'

UNION

SELECT job_location
FROM job_postings_archive
WHERE job_posted_date >= CURRENT_DATE - INTERVAL '90 days'
ORDER BY job_location NULLS LAST;
```

**Why this works:** UNION (not UNION ALL) automatically deduplicates rows and treats NULL as equal to NULL, so a location appearing in both tables appears once. If you needed cardinality (e.g., "how many locations appear in active but not archived?"), you would use EXCEPT instead, which removes rows from the first set that exist in the second. UNION ALL would be wrong here because it would repeat every location that exists in both tables.

## Notes

- **Cardinality mistake:** using UNION when you need UNION ALL (or vice versa). UNION incurs sort/hash cost; only use it when deduplication is semantically required. Conversely, UNION ALL when you need uniqueness produces wrong counts.
- **NULL gotcha:** set operations treat NULL = NULL as true for deduplication, opposite to WHERE and JOIN predicates. This is correct but counterintuitive; document it clearly in comments when NULLs are involved.
- **Column alignment:** set operations require identical column count and compatible types (but not names). Mismatched types can cause implicit casting and silent errors; always explicitly cast if combining different schemas.
- **Performance lever:** query planner may push filters into subqueries before the set operation. Write clear CTEs or derived tables to control execution order, especially when one branch is much larger than the other.
- **Related topics:** INTERSECT (rows in both sets), EXCEPT/MINUS (rows in first but not second), and set operations vs. full/left outer joins (joins preserve all columns; set ops collapse to union of columns).
