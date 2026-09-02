---
date: 2026-09-02
phase: pipelines
topic: Graceful degradation when external dependencies fail
---

# Graceful degradation when external dependencies fail

*Pipelines and orchestration*

## Concept

Graceful degradation means your pipeline continues operating with reduced functionality when an external dependency (API, third-party database, service) becomes unavailable, rather than crashing entirely. Instead of blocking downstream consumers, you serve stale data, cached results, or partial datasets while logging the failure clearly so your monitoring alerts and you investigate.

This matters most when your enrichment or validation depends on services you don't control—job boards returning location geocoding, salary survey APIs, or HR systems providing job category mappings. Without it, a single API timeout or rate limit blocks your entire pipeline, and downstream dashboards go dark. With it, analysts still see yesterday's job postings even if geolocation failed today.

The key is being explicit about degradation: mark degraded rows, track which dependency failed, set a rerun schedule, and alert ops. Your data quality layer must distinguish between "this is stale but valid" and "this is broken and needs investigation."

## Practice

**Problem:** Your `job_postings_fact` table depends on an external API to enrich `job_location` with geocoordinates. The API is down 2–3 times per month. When it fails, your entire ingest fails and analysts lose access to new postings.

```sql
-- Graceful degradation pattern
INSERT INTO job_postings_fact 
  (job_id, job_title_short, salary_year_avg, job_work_from_home, job_posted_date, job_location, location_geocoded, data_quality_flag)
SELECT 
  jp.job_id,
  jp.job_title_short,
  jp.salary_year_avg,
  jp.job_work_from_home,
  jp.job_posted_date,
  jp.job_location,
  COALESCE(geo.coordinates, stale.coordinates) AS location_geocoded,
  CASE 
    WHEN geo.coordinates IS NOT NULL THEN 'complete'
    WHEN stale.coordinates IS NOT NULL THEN 'degraded_using_stale_geocode'
    ELSE 'degraded_missing_geocode'
  END AS data_quality_flag
FROM raw_job_postings jp
LEFT JOIN geocoding_api_response geo 
  ON jp.job_location = geo.location 
  AND jp.ingest_date = CURRENT_DATE
LEFT JOIN job_postings_fact stale 
  ON jp.job_location = stale.job_location 
  AND stale.data_quality_flag = 'complete'
  AND stale.job_posted_date = (SELECT MAX(job_posted_date) FROM job_postings_fact)
WHERE jp.ingest_date = CURRENT_DATE;

-- Monitoring query
SELECT data_quality_flag, COUNT(*) as row_count 
FROM job_postings_fact 
WHERE job_posted_date = CURRENT_DATE 
GROUP BY data_quality_flag;
```

## Notes

- **Mistake:** Silently falling back without marking degradation. Your data quality metrics won't reveal you're serving partial results, and alerts won't trigger until a human notices.
- **Mistake:** Keeping degraded data indefinitely. Set a TTL or rerun window—after 7 days, fail the pipeline loudly if dependencies still aren't available.
- **Related:** Circuit breakers (fail fast once an API is known-bad) and exponential backoff (don't hammer a struggling service). Both complement graceful degradation.
- **Revisit:** How to test degradation without taking down real APIs—mock API responses in dev and staging, use feature flags to simulate failures in production safely.
- **Adjacent:** Data freshness SLAs and observability—your `data_quality_flag` feeds alerting rules, and downstream consumers must know when they're using degraded data.
