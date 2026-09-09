---
date: 2026-09-09
phase: reliability
topic: Load testing a pipeline before it hits production
---

# Load testing a pipeline before it hits production

*Quality, reliability and the professional layer*

## Concept

Load testing a data pipeline means running it against realistic volumes and concurrency patterns *before* it serves production traffic. It answers: Does this break at 10x the expected data volume? What happens when three schedulers trigger simultaneously? Load testing is where you discover that your transformation logic runs fine on 100K rows but crashes on 10M, or that your database connection pool exhausts under peak load.

Without load testing, you ship brittle pipelines that appear to work during development but fail catastrophically when they meet real-world scale. This is the difference between a pipeline that works and a pipeline you can trust. It surfaces resource constraints (memory, CPU, I/O), reveals algorithmic bottlenecks, and validates that your error handling actually works under pressure—not just in happy-path unit tests.

The cost of discovery during production is high: data quality issues propagate downstream, stakeholders lose confidence, you're debugging under pressure. Load testing moves that discovery to a controlled environment where you can iterate, fail safely, and document capacity limits.

## Practice

**Problem:** Your daily job postings ETL ingests job posting data into `job_postings_fact`. In dev, you tested with 10K rows. Production receives 500K rows daily, with 50K arriving in the first hour (peak load). Your current transformation includes a self-join to deduplicate by title + location + salary. The job fails sporadically during peak hours with memory errors.

**Solution:** Simulate production volume and identify the bottleneck:

```sql
-- Load test: Simulate 500K rows, measure performance
WITH simulated_load AS (
  SELECT 
    ROW_NUMBER() OVER (ORDER BY job_id) as job_id,
    job_title_short,
    salary_year_avg,
    job_work_from_home,
    job_posted_date,
    job_location
  FROM job_postings_fact
  CROSS JOIN (SELECT 1 as multiplier FROM UNNEST([1,2,3,4,5]) as multiplier)
  LIMIT 500000
),
-- Original approach: self-join for dedup (memory-heavy)
dedup_join AS (
  SELECT DISTINCT ON (job_title_short, job_location, salary_year_avg)
    job_id, job_title_short, salary_year_avg, 
    job_work_from_home, job_posted_date, job_location
  FROM simulated_load
  ORDER BY job_title_short, job_location, salary_year_avg, job_posted_date DESC
),
-- Better approach: window function (streaming-friendly)
dedup_window AS (
  SELECT 
    job_id, job_title_short, salary_year_avg, 
    job_work_from_home, job_posted_date, job_location
  FROM (
    SELECT *,
      ROW_NUMBER() OVER (PARTITION BY job_title_short, job_location, salary_year_avg 
                        ORDER BY job_posted_date DESC) as rn
    FROM simulated_load
  )
  WHERE rn = 1
)
SELECT COUNT(*) as final_row_count FROM dedup_window;
```

Run this and measure execution time, memory usage, and whether it completes. Replace the self-join with the window function approach if it fails. Then test again at 2x and 5x volume to find your breaking point.

## Notes

- **Confuse load testing with unit testing**: Unit tests verify correctness on tiny samples; load tests verify *sustainability* at scale. Both needed, different purposes.
- **Test concurrency, not just volume**: A pipeline that handles 500K rows sequentially may fail when two runs overlap. Use job scheduling simulators to stress parallel execution.
- **Document capacity limits**: Once you find the breaking point (e.g., "this pipeline handles up to 1M rows before memory spikes"), write it down. It's institutional knowledge and informs future scaling decisions.
- **Connect to monitoring**: Load testing teaches you what metrics to track in production (query duration, memory consumption, connection pool saturation). Wire these up during load tests so you recognize problems early.
- **Revisit after schema changes**: Adding a column, changing a join, or switching to a new transformation library can alter performance profile. Retest before deploying schema changes to production.
