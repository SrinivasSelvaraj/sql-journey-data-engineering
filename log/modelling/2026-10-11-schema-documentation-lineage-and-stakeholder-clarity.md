---
date: 2026-10-11
phase: modelling
topic: Schema documentation: lineage and stakeholder clarity
---

# Schema documentation: lineage and stakeholder clarity

*Data modelling and warehousing*

## Concept

Schema documentation creates a shared understanding of what data exists, where it comes from, and who owns it—so your team doesn't need to reverse-engineer your design choices. Without it, analysts waste time guessing whether `salary_year_avg` is median or mean, if `job_work_from_home` includes hybrid roles, or whether `job_location` is the office address or employee region. This friction multiplies as your warehouse scales.

Lineage documentation answers the upstream question: where did this column originate? A `salary_year_avg` might come from web scraping, manual data entry, or a partner API—each has different freshness, accuracy, and completeness guarantees. Stakeholder clarity answers the downstream question: who should be notified if this schema changes, and who owns fixing bad data?

Without this, schema changes break silently (a dashboard quietly returns wrong numbers), redundant columns get created (three different interpretations of "remote-eligible"), and onboarding new analysts becomes a blocker conversation instead of a self-serve activity.

## Practice

**Problem:** A new analyst joins and queries `job_postings_fact`, filtering `WHERE job_work_from_home = TRUE`. They're confused: their results exclude roles listed as "hybrid" on the source website, and they don't know if that's intentional or a bug. They have to ask you.

**Solution:** Document the schema inline and in a metadata table:

```sql
-- In your schema definition or README
CREATE TABLE job_postings_fact (
  job_id INT PRIMARY KEY,
  job_title_short VARCHAR(100),           -- Standardized title (e.g., 'Data Analyst', 'Senior Engineer'). Source: cleaned from job_postings_raw.job_title via title_mapping lookup.
  salary_year_avg INT,                    -- Mean annual salary in USD. Null if not disclosed. Source: job_postings_raw.salary_min/max (averaged). Updated daily via dbt model 'fact_job_postings'.
  job_work_from_home BOOLEAN,             -- TRUE = fully remote only. FALSE = on-site or hybrid. Does not distinguish hybrid. Owner: data platform team. Contact: @data-eng-squad.
  job_posted_date DATE,                   -- Date job was published to source site. Source: job_postings_raw.posted_timestamp. Lineage: web_scrape → raw → staging → fact.
  job_location VARCHAR(150)               -- Primary office location (city, state). Null if remote-only. Source: job_postings_raw.location (cleaned by geocoding service). Accuracy: ~95% (manual QA spot-checks).
);

-- Supplementary metadata table for tooling and dashboards
CREATE TABLE schema_lineage (
  table_name VARCHAR(100),
  column_name VARCHAR(100),
  description TEXT,
  source_system VARCHAR(100),
  owner_team VARCHAR(100),
  refresh_frequency VARCHAR(50),
  known_limitations TEXT
);

INSERT INTO schema_lineage VALUES
  ('job_postings_fact', 'job_work_from_home', 'TRUE = fully remote only. FALSE = on-site or hybrid.', 'job_postings_raw', 'data-eng-squad', 'daily', 'Hybrid roles collapsed into FALSE; does not distinguish flexibility levels.');
```

## Notes

- **Document the boolean trap:** Boolean columns are deceptively ambiguous. Always state what TRUE and FALSE mean, and whether NULL is possible. A single sentence prevents 10 confused questions.
- **Lineage connects to data quality & observability:** If an upstream source changes its format, lineage documentation helps you quickly find all downstream tables affected. Pair this with dbt, data catalogs (Collibra, Atlan), or even a simple markdown DAG.
- **Stakeholder ownership prevents silent breakage:** Assign an owner (person or team) to each table and critical column. When you must change the schema, you know exactly who to notify and what downstream work will break.
- **Common mistake: writing docs no one reads.** Embed descriptions in the schema definition itself (`COMMENT ON COLUMN …`), or generate auto-populated wiki pages from metadata tables. One source of truth, not a forgotten spreadsheet.
- **Revisit after each schema change:** Documentation debt accrues quickly. Make it part of your merge request checklist: "Did you update the column descriptions, lineage, and ownership?"
