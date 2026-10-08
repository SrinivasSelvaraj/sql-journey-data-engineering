---
date: 2026-10-08
phase: modelling
topic: Role-playing dimensions and view aliases
---

# Role-playing dimensions and view aliases

*Data modelling and warehousing*

## Concept

Role-playing dimensions and view aliases solve a critical problem: the same dimension table often needs to appear multiple times in a fact table with different semantic meanings, but a single join produces ambiguity and naming collisions. For example, a recruitment fact might need both a "posting location" and a "candidate location"—both reference the same location dimension, but represent different business concepts. View aliases let you create virtual renamed copies of dimension tables, so queries can join the same table twice with clear, distinct column prefixes.

Without aliases, you either flatten everything into the fact table (destroying reusability and creating massive redundancy), or you force every analyst to remember which role each join plays and manually alias columns in every query. This breaks self-service: your team will either get wrong answers or keep asking you what `location_id` really means in the context of their join.

The pattern is essential whenever a single dimension logically appears in multiple roles. It keeps your schema clean, makes column names self-documenting, and ensures consistent logic across all downstream queries.

## Practice

**Problem:** Your analytics team needs to compare job salary by posting location versus job market location. The same location dimension applies to both, but they need distinct, unambiguous columns in their results.

```sql
-- Create view aliases for the same location dimension in different roles
CREATE VIEW location_posting AS
  SELECT location_id, location_name, country
  FROM dim_location;

CREATE VIEW location_market AS
  SELECT location_id, location_name, country
  FROM dim_location;

-- Now query the fact table using both roles
SELECT
  jp.job_id,
  jp.job_title_short,
  posting_loc.location_name AS posting_location,
  market_loc.location_name AS market_location,
  jp.salary_year_avg
FROM job_postings_fact jp
LEFT JOIN location_posting AS posting_loc
  ON jp.job_location = posting_loc.location_id
LEFT JOIN location_market AS market_loc
  ON jp.job_market_location = market_loc.location_id;
```

## Notes

- **Don't hardcode role names into the dimension itself.** Create lightweight views instead—they're cheap, composable, and let you keep the true dimension pure and singular.
- **Column naming is the payoff.** Prefix all columns from a role-played dimension with the role name (`posting_location_name`, not just `location_name`). Self-documenting beats clever.
- **Adjacent pattern: conformed dimensions.** Role-playing assumes the same dimension in multiple contexts; conformed dimensions ensure that shared dimension has one consistent definition across the warehouse.
- **Revisit when:** You notice the same dimension appearing in multiple fact tables with different meanings, or when analysts start writing custom aliases in every query—that's a signal to formalize the role as a view.
- **Watch out for slowly-changing dimensions (SCD).** If your dimension has historical versions, ensure your view alias pulls the right SCD branch and that your fact table's foreign keys are aligned correctly.
