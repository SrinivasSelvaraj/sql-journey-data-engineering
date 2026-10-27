---
date: 2026-10-27
phase: modelling
topic: Generic dimensions and flexible attribute storage
---

# Generic dimensions and flexible attribute storage

*Data modelling and warehousing*

## Concept

Generic dimensions solve the problem of rigid, unmaintainable schemas when attributes vary across entities or change frequently. Instead of adding a new column every time a job posting gains a new attribute (remote_eligible, visa_sponsorship, salary_currency, experience_level), you store flexible key–value pairs in a bridge table or JSON column. This keeps your fact table lean and your dimension tables queryable without schema migration.

The tension: standard star schemas assume stable, known attributes. Real data doesn't work that way. Job postings gain new fields; product catalogs expand; user profiles accumulate tags. Without a generic dimension approach, you either bloat your schema with null-heavy columns, or you become a bottleneck approving every schema change. With it, analysts can self-serve: they join to a simple attributes table, filter on attribute_name and attribute_value, and explore without asking you what `job_sponsorship_visa_eligible` means or whether it's populated.

This matters most when (1) attributes are sparse—not every entity has every field—or (2) attributes are exploratory and evolving. It breaks down when you try to query across many attributes at once, or when you need strong typing and validation; then you're fighting the schema instead of using it.

## Practice

**Problem:** Your job_postings_fact table has columns for five job attributes, but data sources vary wildly. Some provide benefits (401k, health_insurance, remote_work); some provide certifications required; some provide nothing. You're constantly adding nullable columns. You need analysts to query "which jobs offer 401k?" without you adding schema columns.

```sql
-- Generic dimension approach: job_attributes bridge table
CREATE TABLE job_attributes (
    job_id INT,
    attribute_name VARCHAR(100),
    attribute_value VARCHAR(500),
    PRIMARY KEY (job_id, attribute_name)
);

-- Insert flexible attributes from any source
INSERT INTO job_attributes VALUES
    (1001, 'benefits_401k', 'yes'),
    (1001, 'remote_work', 'fully_remote'),
    (1002, 'benefits_401k', 'no'),
    (1002, 'certifications_required', 'AWS_Solutions_Architect'),
    (1003, 'remote_work', 'hybrid');

-- Analyst query: no schema changes needed
SELECT DISTINCT jpf.job_id, jpf.job_title_short, jpf.salary_year_avg
FROM job_postings_fact jpf
INNER JOIN job_attributes ja ON jpf.job_id = ja.job_id
WHERE ja.attribute_name = 'benefits_401k' 
  AND ja.attribute_value = 'yes'
  AND jpf.salary_year_avg > 100000;
```

## Notes

- **Null inflation trap:** Don't add columns like `benefits_401k BOOLEAN` alongside the generic table. You'll end up maintaining both, defeating the purpose. Pick one pattern and commit.

- **Query complexity cost:** Analysts filtering on 3+ different attributes need multiple self-joins (or a pivot), which is slower and less intuitive than columnar queries. Consider a materialized view or denormalizing hot attributes back into the fact table if they're queried together constantly.

- **Type safety loss:** Generic dimensions store everything as strings. Validation and casting happen downstream, not in the schema. Use data tests (dbt, Datafold) to catch bad values early.

- **Related patterns:** Slowly Changing Dimensions (SCD) track attribute history over time; EAV (Entity–Attribute–Value) is the classic relational form; JSON/JSONB columns are the semi-structured cousin. Pick based on query patterns and team skill.

- **Revisit when:** schema churn stops (all attributes stabilize → denormalize back), or query volume spikes (consider column store or caching). Generic dimensions are a bridge, not a destination.
