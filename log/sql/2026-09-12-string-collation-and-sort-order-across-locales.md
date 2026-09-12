---
date: 2026-09-12
phase: sql
topic: String collation and sort order across locales
---

# String collation and sort order across locales

*SQL for analytics and engineering*

## Concept

Collation defines how strings are compared and sorted in a database—it determines character ordering, case sensitivity, accent handling, and locale-specific rules. Without explicit collation, sort results depend on the database default (often UTF-8 binary or server locale), leading to inconsistent behavior across environments. This matters most when sorting job titles, location names, or user-generated text where natural language order is expected rather than byte-order.

Collation affects ORDER BY, WHERE (string comparisons), GROUP BY (aggregation boundaries), and JOIN conditions. For example, sorting German city names requires knowing whether "ö" sorts near "o" (linguistic) or after "z" (binary). Mismatched collations between columns cause implicit conversions, index bypasses, and performance cliffs. In analytics, silent collation mismatches produce wrong grouping and ranking.

When collation is unspecified, databases default to a system-wide setting that may not match your data's actual language. Multi-locale datasets need explicit COLLATE clauses to ensure deterministic, intentional ordering—especially critical in reports where users expect alphabetical lists in their language.

## Practice

**Problem:** You're building a report ranking job locations by frequency. The stakeholder is French and expects locations like "Île-de-France" and "Auvergne" to sort correctly (accents respected). Your query groups by location and counts postings, but the ORDER BY is placing accented names unpredictably.

```sql
SELECT 
  job_location COLLATE 'fr_FR.UTF-8' AS location,
  COUNT(*) AS posting_count
FROM job_postings_fact
WHERE job_location IS NOT NULL
GROUP BY job_location COLLATE 'fr_FR.UTF-8'
ORDER BY location COLLATE 'fr_FR.UTF-8' DESC;
```

**Alternative (if database is PostgreSQL):**
```sql
SELECT 
  job_location,
  COUNT(*) AS posting_count
FROM job_postings_fact
WHERE job_location IS NOT NULL
GROUP BY job_location
ORDER BY job_location COLLATE "fr_FR" DESC;
```

## Notes

- **GROUP BY and COLLATE must match:** If you collate in ORDER BY but not GROUP BY, the database treats identical strings with different collations as separate groups, producing duplicate rows and wrong counts.
- **Index use depends on collation:** A column indexed with UTF-8 binary collation won't use the index efficiently if your query applies a different collation; rewrite to collate at storage time or accept a scan.
- **Case sensitivity is collation-dependent:** Binary collations treat 'A' ≠ 'a'; linguistic collations (like `utf8_general_ci`) ignore case. Choose deliberately based on business logic.
- **Collation is dialect-specific:** 'en_US' sorts differently from 'en_GB' (e.g., "color" vs. "colour" placement); know your audience and document the choice.
- **Related topics:** Character sets (UTF-8 vs. Latin1), locale-aware formatting (DATE, CURRENCY), and database-specific collation syntax (MySQL COLLATE vs. PostgreSQL COLLATE vs. SQL Server COLLATE).
