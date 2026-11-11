---
date: 2026-11-11
phase: modelling
topic: Degenerate dimensions: dimension attributes in fact tables
---

# Degenerate dimensions: dimension attributes in fact tables

*Data modelling and warehousing*

## Concept

A degenerate dimension is a dimension attribute stored directly in a fact table rather than in a separate dimension table. It represents low-cardinality, slowly-changing, or descriptive data that lacks a natural key or hierarchy. Common examples include order numbers, invoice IDs, or in this case, job titles and location strings.

Degenerate dimensions matter when the cost of normalization (joins, additional tables, maintenance) exceeds the benefit. Without them, you'd create tiny dimension tables for every descriptive attribute, bloating your schema and making queries harder to read. They're practical when the attribute is genuinely atomic, rarely updated, and adds value directly to analysis.

The risk: degenerate dimensions become problematic when they *do* change frequently or contain messy, inconsistent values. If job titles are spelled differently across records, or locations lack standardization, analysts will write inconsistent WHERE clauses and produce conflicting reports. This defeats the purpose of a well-designed warehouse.

## Practice

**Problem:** Analysts keep asking which job posting has the best salary, but `job_title_short` values are inconsistent ("Senior Data Engineer" vs "Sr. Data Engineer" vs "Data Engineer, Senior"), making filtering unreliable and reports non-comparable.

**Solution:** Normalize the degenerate dimension into a proper dimension table:

```sql
-- Create job_title dimension
CREATE TABLE job_title_dim (
  job_title_id INT PRIMARY KEY,
  job_title_short VARCHAR(100) UNIQUE NOT NULL,
  job_title_category VARCHAR(50) NOT NULL -- e.g., "Data", "Analytics", "Engineering"
);

-- Refactor fact table
ALTER TABLE job_postings_fact
  DROP COLUMN job_title_short,
  ADD COLUMN job_title_id INT REFERENCES job_title_dim(job_title_id);

-- Now queries are unambiguous
SELECT jd.job_title_short, AVG(jpf.salary_year_avg)
FROM job_postings_fact jpf
JOIN job_title_dim jd ON jpf.job_title_id = jd.job_title_id
GROUP BY jd.job_title_short
ORDER BY AVG(jpf.salary_year_avg) DESC;
```

## Notes

- **Consistency trap:** Degenerate dimensions are tempting shortcuts. Don't use them for attributes that will be filtered, grouped, or joined across multiple fact tables—normalize those immediately.
- **Slowly changing dimensions:** If a degenerate attribute *does* change over time (job titles evolve, locations consolidate), it must become a proper dimension with SCD logic (Type 1, 2, or 3).
- **Granularity mismatch:** Degenerate dimensions work best when they have the same granularity as the fact table (one value per fact row). If multiple postings share "New York," consider extracting it.
- **Discovery friction:** Degenerate dimensions can hide structural debt. Document which attributes are intentionally degenerate and why; flag candidates for refactoring during schema reviews.
- **Adjacent: conform dimensions, bus matrix:** Degenerate dimensions complicate data integration across fact tables. Use a bus matrix to identify shared dimensions early and avoid fragmenting data across competing denormalizations.
