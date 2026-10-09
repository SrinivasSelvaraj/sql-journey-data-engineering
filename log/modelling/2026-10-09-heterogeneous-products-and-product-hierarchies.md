---
date: 2026-10-09
phase: modelling
topic: Heterogeneous products and product hierarchies
---

# Heterogeneous products and product hierarchies

*Data modelling and warehousing*

## Concept

Heterogeneous products are items that differ fundamentally in structure, attributes, or behavior—not just in price or volume. A data warehouse storing both job postings for software engineers and marketing coordinators, or both physical products and SaaS subscriptions, must handle the fact that these entities don't share the same meaningful dimensions. Without careful hierarchy design, you force all products into a single flat schema, creating hundreds of NULL columns, inconsistent naming, and queries that become brittle ("is this column even populated for this product type?").

Product hierarchies solve this by organizing related but structurally different items into logical groups—job categories, product lines, subscription tiers—so that shared attributes (price, date, location) live in a fact table, while type-specific attributes (remote policy, tech stack, contract length) live in type-specific dimension tables or are flagged clearly. This prevents the data warehouse from becoming a source of ambiguity; downstream teams can confidently filter, group, and aggregate without guessing what NULL means or whether a field applies to their use case.

The cost of ignoring this shows up as slow queries with excessive JOINs and CASE statements, high cardinality dimension tables that don't compress, and most painfully, silent analysis bugs—sums that include items that shouldn't be included because the schema allows it, even if the business logic forbids it.

## Practice

**Problem:** The job_postings_fact table conflates remote work (only meaningful for full-time roles) with a boolean column available to all rows. Finance teams querying average salary by remote status accidentally include contract roles and internships, inflating numbers. Filtering by job_work_from_home requires knowing in advance which job_title_short values actually support that attribute.

**Solution:**

```sql
-- Separate fact and dimension; only job postings of types that
-- support remote work include that attribute.

CREATE TABLE job_postings_fact (
    job_id INT PRIMARY KEY,
    job_type_id INT NOT NULL,  -- FK to job_type_dim
    job_title_short VARCHAR,
    salary_year_avg DECIMAL(10,2),
    job_posted_date DATE,
    job_location VARCHAR,
    FOREIGN KEY (job_type_id) REFERENCES job_type_dim(job_type_id)
);

CREATE TABLE job_type_dim (
    job_type_id INT PRIMARY KEY,
    job_type_name VARCHAR,  -- 'Full-time', 'Contract', 'Internship'
    supports_remote BOOLEAN  -- metadata about the type itself
);

CREATE TABLE job_posting_remote_detail (
    job_id INT PRIMARY KEY,
    job_work_from_home BOOLEAN NOT NULL,
    FOREIGN KEY (job_id) REFERENCES job_postings_fact(job_id)
);

-- Now a clean query:
SELECT 
    jt.job_type_name,
    AVG(jpf.salary_year_avg) AS avg_salary
FROM job_postings_fact jpf
INNER JOIN job_type_dim jt ON jpf.job_type_id = jt.job_type_id
INNER JOIN job_posting_remote_detail jprd ON jpf.job_id = jprd.job_id
WHERE jprd.job_work_from_home = TRUE
  AND jt.supports_remote = TRUE
GROUP BY jt.job_type_name;
```

## Notes

- **Null ≠ unknown:** Use dimension tables or separate fact tables to encode "this attribute does not apply" rather than relying on NULL, which is ambiguous and makes aggregation fragile.
- **Bridge tables for many-to-many:** If a job posting can belong to multiple product categories or a product can have multiple hierarchies, use a bridge table (job_id, category_id) to avoid denormalization and redundancy.
- **Metadata in dimensions, not facts:** Store `supports_remote` in job_type_dim, not as a separate fact measure; this clarifies intent and prevents accidental filtering errors downstream.
- **Related concepts:** Slowly Changing Dimensions (SCD) for tracking changes to hierarchy membership over time; Conformed Dimensions when the same product hierarchy is queried across multiple fact tables (finance, ops, product).
- **Revisit:** Test queries from actual downstream users early; schema elegance matters less than whether people can write correct queries without domain expertise or asking you what a column means.
