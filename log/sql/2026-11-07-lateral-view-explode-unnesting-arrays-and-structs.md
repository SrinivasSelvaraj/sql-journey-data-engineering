---
date: 2026-11-07
phase: sql
topic: Lateral view explode: unnesting arrays and structs
---

# Lateral view explode: unnesting arrays and structs

*SQL for analytics and engineering*

## Concept

`LATERAL VIEW EXPLODE` (Hive/Spark SQL) and `UNNEST` (standard SQL) transform a single row containing an array or map into multiple rows—one per element. This is essential when upstream data models nest collections (common in event logs, user profiles, or denormalized schemas) but your analytics requires grain-level detail. Without unnesting, you either lose data by selecting only the first element, or your aggregations become logically incorrect because you're grouping over the container rather than the contents.

The operation is a join variant: the lateral view acts as a correlated subquery that iterates the array in parallel with the outer row, emitting each element as a new row. This preserves the outer row's context (job_id, date, etc.) while expanding the nested collection. Performance depends on array cardinality; exploding a 1000-element array per row can multiply your result set dramatically, so filtering before the unnest is critical.

Understanding when to unnest versus when to leave nested structures alone separates engineers from analysts. Use unnest for detailed analytics (impression-level metrics), but keep arrays compressed for aggregated snapshots or when you need set operations. Query planners often struggle with lateral views, so explicitly filter or limit before unnesting to avoid memory spills.

## Practice

**Problem:** You have job postings where `job_location` is a comma-separated string (e.g. `"New York, San Francisco, Austin"`). You want to create a row per location so you can count how many unique postings target each city, then rank locations by posting volume.

```sql
-- Solution using LATERAL VIEW EXPLODE (Hive/Spark)
WITH exploded_locations AS (
  SELECT
    job_id,
    job_title_short,
    salary_year_avg,
    TRIM(location) AS city
  FROM job_postings_fact
  LATERAL VIEW EXPLODE(SPLIT(job_location, ',')) locs AS location
  WHERE job_posted_date >= '2024-01-01'
)
SELECT
  city,
  COUNT(DISTINCT job_id) AS posting_count,
  ROUND(AVG(salary_year_avg), 0) AS avg_salary,
  ROW_NUMBER() OVER (ORDER BY COUNT(DISTINCT job_id) DESC) AS location_rank
FROM exploded_locations
GROUP BY city
ORDER BY posting_count DESC;
```

**Alternative using standard UNNEST (PostgreSQL, BigQuery, Snowflake):**
```sql
WITH exploded_locations AS (
  SELECT
    job_id,
    job_title_short,
    salary_year_avg,
    TRIM(city) AS city
  FROM job_postings_fact,
  LATERAL UNNEST(SPLIT(job_location, ',')) AS city
  WHERE job_posted_date >= '2024-01-01'
)
SELECT
  city,
  COUNT(DISTINCT job_id) AS posting_count,
  ROUND(AVG(salary_year_avg), 0) AS avg_salary,
  ROW_NUMBER() OVER (ORDER BY COUNT(DISTINCT job_id) DESC) AS location_rank
FROM exploded_locations
GROUP BY city
ORDER BY posting_count DESC;
```

## Notes

- **Cardinality explosion risk:** Exploding a 100-element array across 10M rows yields 1B rows before aggregation. Always estimate downstream size and filter/limit early. Use `HAVING ARRAY_LENGTH(...) < threshold` before the lateral view if possible.

- **TRIM() after split:** String splits leave leading/trailing whitespace. `TRIM(location)` prevents "New York" and " New York" from being treated as different cities—a subtle bug in production.

- **Lateral joins in query plans:** Most optimizers don't push predicates through lateral views as effectively as regular joins. Explicitly filter the outer table before the unnest; avoid filtering inside the exploded result set if you can.

- **Set operations and deduplication:** If the same location appears multiple times in the comma-separated string, explode will preserve duplicates. Use `DISTINCT` in GROUP BY or wrap with a deduplication CTE if single-counting is required.

- **Related topics:** Window functions (ROW_NUMBER for ranking), ARRAY_AGG for the reverse (collecting rows back into arrays), and semi-structured data handling (JSON unnesting follows the same pattern). Practice reasoning about whether to normalize at query time vs. ETL time.
