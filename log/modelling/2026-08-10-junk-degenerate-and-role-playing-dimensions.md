---
date: 2026-08-10
phase: modelling
topic: Junk, degenerate and role-playing dimensions
---

# Junk, degenerate and role-playing dimensions

*Data modelling and warehousing*

## Concept

A **junk dimension** consolidates low-cardinality, unrelated boolean or flag columns into a single dimension table to reduce fact table width and improve query performance. A **degenerate dimension** is an attribute on the fact table itself (like an order number or transaction ID) that has no separate dimension table because it serves only as a grouping key. A **role-playing dimension** is a single dimension table referenced multiple times by a fact table through different foreign keys—for example, a `date_dim` table used for both `order_date_key` and `ship_date_key`.

These patterns emerge because raw transactional data often includes many small attributes that don't justify their own dimension tables. Without them, you either bloat your fact table with dozens of flags, lose semantic clarity by treating different relationships to the same table as identical, or create redundant dimension tables that are expensive to maintain. The payoff is cleaner queries, faster joins, and schemas that self-document: a column name like `job_work_arrangement_key` immediately signals "look this up in the dimension table" rather than leaving readers guessing whether a boolean means yes/no or 0/1.

## Practice

**Problem:** The `job_postings_fact` table has `job_work_from_home BOOLEAN` mixed with salary and location data. Three years of history means millions of rows. Analysts are confused: does `TRUE` mean remote-eligible or fully remote? And filtering on multiple boolean conditions in queries is error-prone.

**Solution:** Create a junk dimension to standardize work arrangements:

```sql
CREATE TABLE job_work_arrangement_dim (
  work_arrangement_key INT PRIMARY KEY,
  work_arrangement_name VARCHAR(50),
  is_remote BOOLEAN,
  is_hybrid BOOLEAN,
  is_onsite BOOLEAN
);

INSERT INTO job_work_arrangement_dim VALUES
  (1, 'Fully Remote', TRUE, FALSE, FALSE),
  (2, 'Hybrid', FALSE, TRUE, FALSE),
  (3, 'On-site', FALSE, FALSE, TRUE);

-- Refactored fact table
ALTER TABLE job_postings_fact
  DROP COLUMN job_work_from_home,
  ADD COLUMN work_arrangement_key INT REFERENCES job_work_arrangement_dim;

-- Now queries are self-documenting
SELECT 
  jd.job_title_short,
  wad.work_arrangement_name,
  AVG(jp.salary_year_avg) AS avg_salary
FROM job_postings_fact jp
JOIN job_work_arrangement_dim wad ON jp.work_arrangement_key = wad.work_arrangement_key
WHERE wad.is_remote = TRUE
GROUP BY jd.job_title_short, wad.work_arrangement_name;
```

## Notes

- **Junk dimensions** work best when you have 3–5 related flags of low cardinality (under 50 distinct combinations); beyond that, a full dimension or entity table is clearer.
- **Degenerate dimensions** (like `order_number_degenerate_key`) are fine to leave on the fact table—they're not dimensions in the relational sense, they're identifiers that enable drill-down without a separate lookup.
- **Role-playing dimensions** require clear naming: instead of ambiguous `date_key`, use `order_date_key` and `ship_date_key`, both pointing to the same `date_dim`. Add a comment in the schema documenting the relationship.
- Common mistake: creating a junk dimension for a high-cardinality attribute (like user comments or product descriptions)—those belong in a proper dimension or are better left denormalized.
- This connects directly to slowly changing dimensions (SCD) and conformed dimensions in multi-fact warehouses; reusing a dimension requires careful SCD strategy.
