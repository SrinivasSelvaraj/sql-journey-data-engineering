---
date: 2026-09-16
phase: modelling
topic: Mini-dimensions for high-cardinality attributes
---

# Mini-dimensions for high-cardinality attributes

*Data modelling and warehousing*

## Concept

Mini-dimensions solve the problem of high-cardinality attributes—fields with thousands or millions of distinct values—that would bloat a fact table if stored as separate dimension keys. Instead of creating a full dimension table for every attribute combination (location + job title + seniority level), you create a lightweight "mini" dimension that groups related low-cardinality attributes together, then join it to your fact table.

Without mini-dimensions, you either store high-cardinality text directly in the fact table (denormalization, slow queries, storage waste) or create exploding dimension tables with millions of rows (joins become expensive, maintenance nightmare). Mini-dimensions let you normalize without creating a Cartesian product of permutations.

The pattern works best when a subset of attributes are frequently filtered or aggregated together but have independent cardinalities. For example: job title, seniority level, and industry domain might each have 500–5,000 values, but combined they create meaningful business contexts worth pre-grouping.

## Practice

**Problem:** Your `job_postings_fact` table has `job_title_short` (3,000 unique values) and `job_location` (5,000 unique values) stored as strings, making filters slow and aggregations memory-intensive. You also want to add `seniority_level` and `industry` attributes for analysis, but don't want to create a 75M-row dimension.

**Solution:** Create a mini-dimension for job context:

```sql
CREATE TABLE job_context_mini_dim (
  job_context_key INT PRIMARY KEY,
  job_title_short VARCHAR(100),
  seniority_level VARCHAR(50),
  industry VARCHAR(100),
  dbt_updated_at TIMESTAMP
);

ALTER TABLE job_postings_fact 
ADD COLUMN job_context_key INT,
ADD FOREIGN KEY (job_context_key) REFERENCES job_context_mini_dim(job_context_key);

-- Populate mini-dimension with distinct combinations from source
INSERT INTO job_context_mini_dim (job_title_short, seniority_level, industry)
SELECT DISTINCT job_title_short, seniority_level, industry
FROM staging_job_postings
ON CONFLICT DO NOTHING;

-- Update fact table with surrogate keys
UPDATE job_postings_fact jpf
SET job_context_key = jcmd.job_context_key
FROM job_context_mini_dim jcmd
WHERE jpf.job_title_short = jcmd.job_title_short
  AND jpf.seniority_level = jcmd.seniority_level
  AND jpf.industry = jcmd.industry;
```

## Notes

- **Cardinality trap:** Don't create a mini-dimension for truly low-cardinality fields (region, date) or purely high-cardinality unique identifiers (user_id). The sweet spot is 100–50,000 distinct values per field.
- **Conformed attributes:** Mini-dimensions work best alongside conformed dimensions. Keep job_posted_date and salary_year_avg in the fact table; move descriptive business context to mini-dimensions.
- **SCD handling:** Mini-dimensions are often Type 1 (overwrite) rather than Type 2 (history tracking) because job titles change frequently and historical versions rarely matter for analysis.
- **Grain confusion:** Clarify whether your fact table is at job-posting grain or application grain *before* deciding which attributes belong in a mini-dimension; misalignment creates duplicates.
- **Related patterns:** Bridge tables handle many-to-many relationships; role-playing dimensions reuse the same physical table as different logical entities; this is orthogonal to mini-dims but often combined.
