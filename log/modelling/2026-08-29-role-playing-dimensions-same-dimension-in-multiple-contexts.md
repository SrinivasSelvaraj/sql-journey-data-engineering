---
date: 2026-08-29
phase: modelling
topic: Role-playing dimensions: same dimension in multiple contexts
---

# Role-playing dimensions: same dimension in multiple contexts

*Data modelling and warehousing*

## Concept

A role-playing dimension occurs when the same dimension table is referenced multiple times in a fact table, each time representing a different business context or "role." For example, a sales fact table might join to a `location` dimension three times: once for where the customer is, once for where the warehouse is, and once for where the sale was fulfilled. Without explicit role names, queries become ambiguous—you won't know which location column answers which question, and your team will ask you "does this mean customer location or warehouse location?"

The problem intensifies when a dimension has many attributes (like `location` with country, city, zip, timezone). If you don't separate these roles into distinct foreign keys with clear names, your schema forces business logic into the application layer or requires constant documentation. Users will write incorrect queries, and you'll spend time clarifying intent rather than building new features.

This matters most in operational and HR schemas where entities play multiple roles. A job posting can reference a company location (where the company is headquartered), a job location (where the work happens), and a remote location (if applicable). Without role clarity, these collapse into ambiguity.

## Practice

**Problem:** The job_postings_fact table references locations in two ways—where the job is posted and where the company operates—but a single `job_location` column doesn't distinguish them. A user wants to analyze: "How many jobs posted by NYC-based companies are remote?" The query is impossible without knowing whether `job_location` means company location or work location.

**Solution:**

```sql
-- Restructured fact table with role-playing dimensions
CREATE TABLE job_postings_fact (
  job_id INT PRIMARY KEY,
  job_title_short VARCHAR(50),
  salary_year_avg DECIMAL(10, 2),
  job_work_from_home BOOLEAN,
  job_posted_date DATE,
  company_location_id INT,  -- role: where company is based
  work_location_id INT      -- role: where work happens
);

-- Now queries are unambiguous
SELECT 
  cl.city AS company_city,
  wl.city AS work_city,
  COUNT(*) AS job_count
FROM job_postings_fact jpf
JOIN location_dim cl ON jpf.company_location_id = cl.location_id
JOIN location_dim wl ON jpf.work_location_id = wl.location_id
WHERE cl.city = 'New York' AND jpf.job_work_from_home = FALSE
GROUP BY cl.city, wl.city;
```

## Notes

- **Naming matters:** Use suffixes like `_company`, `_work`, or `_fulfillment` in foreign key names, not generic `location_id`. This forces clarity at schema design time, not query time.
- **Documentation in cardinality:** Add a data dictionary entry for each role explicitly (e.g., "`company_location_id`: references location dimension in the role of organizational headquarters, updated quarterly"). Don't assume the name alone is self-documenting.
- **Junk dimensions as alternative:** For simple role-playing (especially when roles are mutually exclusive or sparse), consider a junk dimension or flags instead of multiple foreign keys—measure the trade-off between normalization and query simplicity.
- **Connects to:** slowly-changing dimensions (SCD Type 2), bridge tables for many-to-many relationships, and conformed dimensions across multiple fact tables.
- **Revisit:** If you find yourself adding a third or fourth role for the same dimension, the fact table granularity may be wrong; consider splitting into separate fact tables or normalizing the dimension differently.
