---
date: 2026-09-17
phase: modelling
topic: Fact table incremental loads and merge logic
---

# Fact table incremental loads and merge logic

*Data modelling and warehousing*

## Concept

A fact table incremental load captures only new or changed records since the last ETL run, rather than reloading the entire table. This is essential in data warehouses because fact tables grow continuously—reloading millions of historical rows every night wastes compute, storage, and time. Merge logic (typically SQL MERGE or INSERT/UPDATE patterns) applies these incremental changes: it inserts new fact records, updates existing ones if metrics changed, and avoids duplicates.

This matters most when fact tables are large, updated frequently, or feed real-time dashboards. Without it, you either waste resources or lose data freshness. Common failure modes include duplicate fact records (same transaction loaded twice), stale metrics (old values never updated), or missing late-arriving facts (events that arrive after their natural date).

The key design decision is choosing a merge key: what combination of columns uniquely identifies a fact? For job postings, that's typically `job_id` + `job_posted_date`, since the same job can be reposted. Your merge logic must also handle slowly changing dimensions—if a job title gets corrected, should the historical fact record update or stay as originally recorded?

## Practice

**Problem:** Your `job_postings_fact` loads daily from a source system that sometimes corrects salary data retroactively or rejects postings. You need an incremental merge that:
- Inserts new job postings (identified by `job_id` + `job_posted_date`)
- Updates salary or remote-work status if the source corrects it
- Avoids inserting duplicates if the ETL reruns
- Keeps historical accuracy (don't lose the original `job_posted_date`)

```sql
MERGE INTO job_postings_fact AS target
USING staging_job_postings AS source
  ON target.job_id = source.job_id 
  AND target.job_posted_date = source.job_posted_date
WHEN MATCHED THEN
  UPDATE SET
    job_title_short = source.job_title_short,
    salary_year_avg = source.salary_year_avg,
    job_work_from_home = source.job_work_from_home
WHEN NOT MATCHED THEN
  INSERT (job_id, job_title_short, salary_year_avg, job_work_from_home, job_posted_date, job_location)
  VALUES (source.job_id, source.job_title_short, source.salary_year_avg, 
          source.job_work_from_home, source.job_posted_date, source.job_location);
```

## Notes

- **Merge key design is critical:** Choose columns that truly identify a unique business event. If you pick only `job_id`, you'll overwrite the same job posted on different dates as one record—wrong.
- **Staging table hygiene:** Always deduplicate and validate the staging layer before merge. If the source sends duplicates, your merge will too.
- **Late-arriving facts:** Plan how to handle events that arrive days late (a job posting recorded with yesterday's date). MERGE handles this naturally, but track how many late updates occur—signals data quality issues.
- **Slowly changing dimensions vs. facts:** Decide upfront: do dimension attributes (job title, location) update the fact, or stay immutable? Most warehouses freeze facts and update linked dimension tables instead, preserving audit trails.
- **Monitor merge performance:** MERGE operations on large fact tables can be expensive. Index your merge keys, partition fact tables by date, and test incremental window sizes (daily vs. hourly loads).
