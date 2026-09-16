---
date: 2026-09-16
phase: modelling
topic: Outrigger tables and performance trade-offs
---

# Outrigger tables and performance trade-offs

*Data modelling and warehousing*

## Concept

An outrigger table is a small, highly denormalized dimension attached to a fact table to avoid expensive joins while keeping the schema readable. Instead of normalizing a low-cardinality attribute into a separate dimension, you store it directly on the fact table (or on a small companion table keyed only by that attribute). The trade-off is storage and update complexity versus query speed and cognitive load.

Outriggers matter when you have attributes that are queried frequently, change rarely, and live in a dimension that would otherwise force users to join through multiple tables to get context. Without outriggers, you either force expensive joins, or you denormalize everything into the fact table and lose semantic clarity. The middle ground is useful: keep the fact table lean, but push low-cardinality attributes onto a focused companion that never needs updating.

A common scenario: job postings linked to a company dimension that holds industry, company size, and founding year. Most queries ask "show me postings by industry and company size," but the proper dimension is huge and slow to join. An outrigger with just {company_id, industry, company_size_category} lets you join once and stop, without polluting the fact table.

## Practice

**Problem:** Your job_postings_fact table is frequently filtered by job_category and job_seniority_level, but these attributes belong logically to jobs, not salaries or locations. Users keep asking "what does job_category mean?" because it's buried in documentation. You want queries like "average salary by category and seniority" to run without joining through job_title_dim (which is large and changes often).

```sql
-- Create outrigger: small, focused, rarely updated
CREATE TABLE job_context_outrigger (
    job_id INT PRIMARY KEY,
    job_category VARCHAR(50),
    job_seniority_level VARCHAR(50),
    FOREIGN KEY (job_id) REFERENCES job_postings_fact(job_id)
);

-- Query becomes simple and semantic
SELECT 
    jco.job_category,
    jco.job_seniority_level,
    ROUND(AVG(jpf.salary_year_avg), 0) AS avg_salary,
    COUNT(*) AS posting_count
FROM job_postings_fact jpf
INNER JOIN job_context_outrigger jco USING (job_id)
WHERE jpf.job_posted_date >= DATE '2024-01-01'
GROUP BY 1, 2
ORDER BY 3 DESC;
```

## Notes

- **Outrigger vs. denormalization:** An outrigger is not the same as dropping a column onto the fact table. It lives elsewhere and is joined only when needed; denormalization bakes it in permanently and wastes space on every scan.
- **Watch for slow-moving dimensions:** If an attribute changes frequently (e.g., employee title), an outrigger becomes a maintenance nightmare. Reserve outriggers for truly stable metadata.
- **Cardinality is key:** Outriggers shine for attributes with ~10–1000 distinct values. Beyond that, you risk bloating the join; below that, just denormalize directly.
- **Bridges and snowflaking:** Outriggers are a lightweight alternative to snowflaking (normalizing dimensions further). Use when you want clarity without the join count spiraling.
- **Test query plans:** Always verify that the optimizer treats your outrigger join as a simple lookup, not a full scan. A small outrigger should never drive the query plan.
