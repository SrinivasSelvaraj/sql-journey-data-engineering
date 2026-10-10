---
date: 2026-10-10
phase: modelling
topic: Dimension conformation: matching dimension definitions
---

# Dimension conformation: matching dimension definitions

*Data modelling and warehousing*

## Concept

Dimension conformation means ensuring that the same business concept (e.g., "location," "job title," "date") is defined and named identically across all fact tables and dimension tables in your warehouse. When a `job_location` appears in multiple fact tables, it must reference the same dimension table with the same grain, attributes, and surrogate keys—not stored as a string in one table and a foreign key in another.

Without dimension conformation, queries become fragile and inconsistent. A user might join `job_postings_fact` to `location_dimension` on one table but find they need to parse strings or use a different join logic on `salary_survey_fact`. Analytics break silently: counts diverge, filters apply unevenly, and you end up explaining data differences instead of insights.

Conformation is enforced at design time through shared dimension tables and documented standards, not through hope. It's the agreement that says "when you see `location_key` anywhere, it means the exact same thing."

## Practice

**Problem:** You have `job_postings_fact` with `job_location` stored as free text (e.g., "New York, NY"). A new analyst writes a query filtering for remote jobs:

```sql
SELECT job_title_short, salary_year_avg
FROM job_postings_fact
WHERE job_work_from_home = TRUE;
```

Later, the team builds `salary_survey_fact` with `survey_location_id` pointing to a `location_dimension`. Your analyst now tries to filter both tables together and fails—`job_postings_fact` has no `location_key`, only text. Queries diverge by source.

**Solution:** Conform `job_postings_fact` to use a `location_key` foreign key:

```sql
-- Create the conformed dimension
CREATE TABLE location_dimension (
  location_key INT PRIMARY KEY,
  location_name VARCHAR,
  city VARCHAR,
  state VARCHAR,
  country VARCHAR,
  is_remote BOOLEAN
);

-- Alter fact table to conform
ALTER TABLE job_postings_fact
ADD COLUMN location_key INT REFERENCES location_dimension(location_key);

-- Now both facts use the same dimension
SELECT jp.job_title_short, jp.salary_year_avg, ld.city
FROM job_postings_fact jp
INNER JOIN location_dimension ld ON jp.location_key = ld.location_key
INNER JOIN salary_survey_fact ss ON ss.location_key = ld.location_key
WHERE ld.is_remote = TRUE;
```

## Notes

- **Conformation is a design contract, not a runtime fix.** You cannot conform dimensions after the fact tables diverge; you'll spend weeks reconciling historical data and query logic.
- **Watch for "dimension variants."** Teams often create `job_title_short` in one fact and `job_title` in another because "it's convenient." This is slow dimension poisoning—use a single `job_title_key` in all facts.
- **Bus matrix is your tool.** Map which dimensions apply to which facts (job_postings, salary_survey, applicant_pipeline). Dimensions at intersections must be identical.
- **String columns are conformation killers.** Free-text location, title, or category fields create implicit, hidden dimensions. Always extract and conform to explicit dimension tables.
- **Adjacent: slowly changing dimensions (SCD) and grain conformance.** Conformation also means agreeing on the granularity (e.g., is location a city or a postal code?). Mix those, and your joins silently produce Cartesian products.
