---
date: 2026-10-26
phase: modelling
topic: Minidimensions for rapidly changing attributes
---

# Minidimensions for rapidly changing attributes

*Data modelling and warehousing*

## Concept

A minidimension is a narrow dimension table that captures frequently changing attributes separately from a main dimension. Instead of updating dimension records or creating new rows for every small change, you store the volatile attributes (like job title variations, salary adjustments, or remote work policy changes) in their own table, linked by a surrogate key.

Without minidimensions, you face three problems: (1) slow dimension updates that require touching millions of fact rows, (2) loss of historical context when you overwrite attributes, or (3) dimension table explosion if you create a new row every time a single field changes. For example, if a job posting's title gets refined from "Senior Engineer" to "Senior Software Engineer," you either lose the original or duplicate the entire job dimension just to track that one text change.

Minidimensions let you track rapid changes independently. A job posting might be reposted with a salary bump, a location change, and a remote work policy shift—three separate minidimension records—without rewriting the job dimension or fact table.

## Practice

**Problem:** The same job_id has multiple job_postings_fact rows because the job_title_short, salary_year_avg, and job_work_from_home changed across postings. This inflates your fact table, makes aggregation ambiguous ("which salary do I use?"), and couples dimension logic to the fact table.

**Solution:** Separate volatile attributes into a job_posting_minidimension:

```sql
CREATE TABLE job_posting_minidimension (
  job_posting_minidim_key SERIAL PRIMARY KEY,
  job_id INT NOT NULL,
  job_title_short VARCHAR(255),
  salary_year_avg INT,
  job_work_from_home BOOLEAN,
  effective_date DATE NOT NULL,
  end_date DATE,
  is_current BOOLEAN DEFAULT TRUE
);

CREATE TABLE job_postings_fact (
  job_posting_fact_key SERIAL PRIMARY KEY,
  job_posting_minidim_key INT NOT NULL REFERENCES job_posting_minidimension,
  job_location VARCHAR(255),
  job_posted_date DATE,
  applications_received INT,
  FOREIGN KEY (job_posting_minidim_key) REFERENCES job_posting_minidimension(job_posting_minidim_key)
);

-- Single job_id can have multiple minidim records for different snapshots
INSERT INTO job_posting_minidimension (job_id, job_title_short, salary_year_avg, job_work_from_home, effective_date, is_current)
VALUES (1001, 'Senior Engineer', 125000, TRUE, '2024-01-15', FALSE),
       (1001, 'Senior Software Engineer', 135000, TRUE, '2024-02-01', TRUE);
```

Now a single job reposting is one fact row that points to the correct minidimension version without duplicating or overwriting history.

## Notes

- **SCD Type 0 vs minidim:** Don't use minidimensions for attributes you never need to query historically. Keep truly static data (e.g., job_id creation date) in the main dimension; use minidims only for attributes analysts will filter or aggregate by period.

- **Effective dating discipline:** Always include effective_date and end_date (or is_current flag) on minidimensions. Without it, you cannot know which version of salary applied on a given reporting date.

- **Connects to:** Slowly Changing Dimensions (SCD Type 2 is the parent concept), fact table grain definition, and conformed dimensions in multi-fact schemas.

- **Common mistake:** Creating a minidimension for every attribute change. This trades one problem (fat dimensions) for another (dimension proliferation). Minidimensions should be reserved for attributes that genuinely change faster than your fact grain—usually 5–10 attributes, not 50.

- **Revisit grain definition:** If you decide job_title, salary, and remote status are "minidimension-worthy," your fact table grain must be clear: is each row one posting snapshot or one application? Grain ambiguity kills minidimension design.
