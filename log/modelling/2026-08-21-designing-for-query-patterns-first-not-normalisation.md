---
date: 2026-08-21
phase: modelling
topic: Designing for query patterns first, not normalisation
---

# Designing for query patterns first, not normalisation

*Data modelling and warehousing*

## Concept

Query-first design means structuring your schema around *how people will actually ask questions*, not around minimising redundancy. A heavily normalised schema might split job titles into a separate dimension table, require five joins to answer "what's the average salary by role", and force teammates to hunt through documentation to find the right keys. Instead, denormalise strategically: keep `job_title_short` in the fact table if analysts query by role constantly.

This matters most in analytics and data warehousing, where the cost of a slow or confusing query compounds across a team. In operational systems, normalisation prevents update anomalies; in warehouses, denormalisation prevents *cognitive* and *performance* anomalies. Without this mindset, you end up building schemas that are "correct" on paper but hostile to exploration—people either stop asking questions or keep asking you.

The breaking point arrives when a self-service analyst can't write a query without your help, or when simple questions need three joins and a subquery. Your schema should whisper the answers; it shouldn't force people to memorise entity relationships.

## Practice

**Problem:** Your analytics team frequently answers questions like "How many remote jobs posted each month had salary data, grouped by job title?" With a heavily normalised schema, `job_title` lives in a `job_titles_dim` table (requiring a join), and determining "has salary data" requires checking for nulls across multiple tables.

**Solution:**

```sql
SELECT 
  DATE_TRUNC('month', job_posted_date) AS month,
  job_title_short,
  COUNT(*) AS job_count
FROM job_postings_fact
WHERE job_work_from_home = TRUE
  AND salary_year_avg IS NOT NULL
GROUP BY DATE_TRUNC('month', job_posted_date), job_title_short
ORDER BY month DESC, job_count DESC;
```

Because `job_title_short`, `job_work_from_home`, and `salary_year_avg` live in the fact table, this query is one-table, readable, and needs no joins. A new team member can write it alone.

## Notes

- **Denormalisation ≠ redundancy everywhere.** Denormalise the dimensions your queries touch most; leave slowly-changing dimensions (like location metadata) linked by key if they truly change.
- **Revisit query logs quarterly.** If 80% of queries filter or group by a column, ensure it's in your main table. If a column is never touched, consider removing it.
- **Adjacent topic:** Slowly Changing Dimensions (SCD) trade off between history tracking and query simplicity. Denormalising a SCD Type 2 (full history) into the fact table can explode row counts; Type 1 (overwrite) keeps tables lean but loses history.
- **Common mistake:** Normalising "too early" because it *feels* correct, then adding columns back later anyway. Instead, start denormalised and refactor only if storage or update complexity becomes real.
- **Connect to:** Conformed dimensions and the Kimball method treat query patterns as a first-class constraint. This philosophy is the bridge between academic normalisation and practical warehouse design.
