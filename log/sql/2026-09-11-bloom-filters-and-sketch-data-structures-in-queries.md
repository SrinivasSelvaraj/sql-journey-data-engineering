---
date: 2026-09-11
phase: sql
topic: Bloom filters and sketch data structures in queries
---

# Bloom filters and sketch data structures in queries

*SQL for analytics and engineering*

## Concept

Bloom filters and sketch data structures are probabilistic data structures that trade perfect accuracy for speed and memory efficiency. A Bloom filter answers the question "is element X definitely not in set S?" with certainty (no false negatives) but may incorrectly report "yes, X is in S" with a tunable false positive rate. In SQL analytics, these structures matter when you're filtering massive datasets against a membership list—checking if a user_id appears in a blacklist of millions, or if a domain belongs to known fraud domains—without loading the entire reference set into memory or performing expensive joins.

Without Bloom filters or sketches, you're forced into a choice between slow accuracy (join against a large table) or risky approximation (sampling). Bloom filters let you reject non-members cheaply before attempting expensive downstream operations. Most modern data warehouses (Snowflake, BigQuery, DuckDB) don't expose Bloom filters directly in SQL, but understanding their behavior informs how to structure filtering logic: pre-compute a compressed membership set, broadcast it, and filter early.

In interview contexts, Bloom filters signal knowledge of query optimization trade-offs. You won't implement one in SQL itself, but you'll reason about when to use approximate inclusion checks (HyperLogLog for cardinality, MinHash for similarity) versus exact filters, and how to structure a query plan to fail fast rather than compute useless rows.

## Practice

**Problem:** You have 50M historical job postings and need to identify postings from the last 7 days whose job_location matches any of 10,000 known high-growth tech hubs. A naive join is slow. Use a Bloom filter principle: pre-aggregate the hub locations into a compact reference, then filter.

```sql
-- Step 1: Build a compact reference of known tech hub locations
WITH tech_hubs AS (
  SELECT DISTINCT job_location
  FROM job_postings_fact
  WHERE job_posted_date >= CURRENT_DATE - INTERVAL 180 DAY
    AND job_title_short IN ('Data Engineer', 'Data Scientist', 'Senior Data Engineer')
  GROUP BY job_location
  HAVING COUNT(*) > 500  -- Only locations with high volume = "true" hubs
)
-- Step 2: Filter recent postings using the compact set
SELECT 
  job_id,
  job_title_short,
  job_location,
  salary_year_avg
FROM job_postings_fact
WHERE job_posted_date >= CURRENT_DATE - INTERVAL 7 DAY
  AND job_location IN (SELECT job_location FROM tech_hubs)
ORDER BY job_posted_date DESC;
```

The `tech_hubs` CTE acts like a Bloom filter: it's a compressed membership set built once, then used to reject non-matching rows early. The query planner can push this filter down before scanning the full table.

## Notes

- **False positives vs. false negatives:** A Bloom filter never misses an element (no false negatives) but may incorrectly include non-members (false positives). In SQL, INNER JOIN behaves like a perfect filter; approximate counts (APPROX_COUNT_DISTINCT) may under-report. Know which error direction matters for your use case.

- **Pre-computation is key:** Bloom filters shine when the reference set is expensive to compute or reused many times. In SQL, materialize the filtered set as a temp table or CTE, then broadcast it to workers—this is what Spark's broadcast join does under the hood.

- **HyperLogLog and cardinality:** When you only need *approximate* cardinality ("roughly how many unique users?"), HyperLogLog sketches save memory. Many warehouses support `APPROX_COUNT_DISTINCT()` or `HLL_INIT()` functions; they're sketches, not Bloom filters.

- **Common mistake:** Joining against a huge reference table on every query. Instead, pre-filter the reference to essential members (high volume, recent activity) and materialize it. This mimics how a Bloom filter works in theory.

- **Adjacent topic—MinHash and similarity:** For "find postings similar to a seed posting," MinHash sketches approximate Jaccard similarity. Not SQL-native but relevant when reasoning about approximate joins for recommendation systems.
