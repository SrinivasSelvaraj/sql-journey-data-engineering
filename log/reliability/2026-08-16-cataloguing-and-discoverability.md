---
date: 2026-08-16
phase: reliability
topic: Cataloguing and discoverability
---

# Cataloguing and discoverability

*Quality, reliability and the professional layer*

## Concept

A data catalog is a centralized, searchable inventory of data assets—tables, pipelines, dashboards, schemas—with metadata about ownership, lineage, freshness, and purpose. Without it, data engineers become gatekeepers: colleagues email asking "where is X?" or build duplicate pipelines because they didn't know Y already existed. This compounds technical debt and makes it impossible to trace where a bug originated.

Discoverability is the operational consequence of cataloging. When someone can find that `job_postings_fact` exists, who maintains it, when it was last updated, and which dashboards depend on it, they make better decisions: reuse instead of rebuild, report bugs to the right owner, understand acceptable latency. This shifts responsibility from "I know everything" to "everything is knowable."

Without cataloging, you inherit organizational risk. A critical table goes unmaintained because no one realizes it's being used. A transformation logic exists in three places. Downstream consumers build brittle workarounds instead of fixing the source. The professional layer isn't just about clean code—it's about making your work visible, auditable, and trustworthy.

## Practice

**Problem:** Your `job_postings_fact` table is used by three different teams for salary analysis, hiring dashboards, and ML features. Two of them independently filter `job_work_from_home` differently. A third team doesn't know the table exists and rebuilt it. You need to establish what this table is, who owns it, and how it should be used.

```sql
-- Create a metadata table to catalog the asset
CREATE TABLE IF NOT EXISTS data_catalog (
    asset_id STRING,
    asset_name STRING,
    asset_type STRING,
    owner_email STRING,
    description STRING,
    last_modified TIMESTAMP,
    sla_freshness_hours INT,
    pii_columns ARRAY<STRING>,
    downstream_consumers ARRAY<STRING>,
    valid_values_job_work_from_home STRING,
    PRIMARY KEY (asset_id)
);

INSERT INTO data_catalog VALUES (
    'job_postings_fact_prod',
    'job_postings_fact',
    'table',
    'data-platform@company.com',
    'Fact table of job postings sourced from LinkedIn API. job_work_from_home: TRUE = remote-eligible, FALSE = on-site only, NULL = not specified. Updated daily at 02:00 UTC.',
    CURRENT_TIMESTAMP,
    24,
    ARRAY['job_location'],
    ARRAY['hiring_dashboard', 'salary_analytics_team', 'ml_feature_store'],
    'TRUE (remote-eligible) | FALSE (on-site only) | NULL (not specified)',
);

-- Query to help others discover and understand the asset
SELECT asset_name, owner_email, description, sla_freshness_hours, valid_values_job_work_from_home
FROM data_catalog
WHERE asset_name = 'job_postings_fact';
```

## Notes

- **Metadata decay**: A catalog is only useful if it's maintained. Build a process—code comments linked to catalog entries, automated freshness checks, quarterly audits—or it becomes fiction.

- **Lineage matters as much as inventory**: Knowing `job_postings_fact` exists means little if you don't know it depends on `raw_linkedin_jobs`. Invest in tracking source → transformation → consumption chains early.

- **This connects to data governance and quality**: A catalog without SLAs, PII tagging, or ownership is incomplete. Discoverability and accountability are inseparable.

- **Common mistake**: treating the catalog as a one-time documentation task. It's a living system; changes to table schema, ownership, or latency requirements must flow into it immediately.

- **Adjacent topic**: data lineage tools (dbt docs, Collibra, DataHub) automate much of this, but the discipline of *thinking* about discoverability comes first. Technology follows process.
