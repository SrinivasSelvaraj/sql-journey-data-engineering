---
date: 2026-11-03
phase: reliability
topic: Master data management: entity governance and curation
---

# Master data management: entity governance and curation

*Quality, reliability and the professional layer*

## Concept

Master data management (MDM) is the discipline of defining, maintaining, and governing the authoritative version of entities that appear across your data ecosystem. In data engineering, this means declaring which system owns each critical dimension—job titles, locations, company names, skill codes—and ensuring all pipelines reference that single source of truth rather than allowing inconsistent representations to propagate downstream.

Entity governance breaks down into two layers: *definition* (what constitutes a valid job_title_short? does "Sr Engineer" equal "Senior Engineer"?) and *curation* (who validates new values before they enter the master record, and how do you handle historical corrections without breaking past analyses?). Without explicit governance, you inherit silent data quality degradation: analysts write conflicting business logic, reporting becomes unreliable, and ownership becomes diffuse—no one knows who to contact when job titles suddenly fragment.

The cost of skipping this is steep. When job_location is ingested raw from multiple job boards without curation, you end up with "New York, NY", "NYC", "New York", and "new york" all representing the same place. Aggregations fail silently, dashboards show inflated regional counts, and the trust in your platform erodes. Ownership means taking responsibility for the master record—treating it as a product.

## Practice

**Problem:** Your job_postings_fact table ingests raw locations from three different job board APIs. Reporting teams are filtering on job_location to analyze regional salary trends, but location values are inconsistent: some use "San Francisco, CA", others "San Francisco", and some "SF". Joins to a geography dimension are failing silently, and salary aggregations by region are unreliable.

```sql
-- Create a master location entity with governance metadata
CREATE TABLE dim_job_location (
    location_id INT PRIMARY KEY,
    location_name VARCHAR(255) NOT NULL UNIQUE,  -- canonical form: "San Francisco, CA"
    city VARCHAR(100),
    state_province VARCHAR(100),
    country VARCHAR(100),
    canonical_normalized VARCHAR(255),  -- for fuzzy matching logic
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    last_curated_by VARCHAR(100),  -- governance: who approved this?
    last_curated_at TIMESTAMP
);

-- Populate master data with intentional curation
INSERT INTO dim_job_location 
    (location_name, city, state_province, country, canonical_normalized, last_curated_by)
VALUES
    ('San Francisco, CA', 'San Francisco', 'CA', 'USA', 'sanfranciscoCA', 'data_steward@company.com'),
    ('New York, NY', 'New York', 'NY', 'USA', 'newyorkNY', 'data_steward@company.com'),
    ('Remote', NULL, NULL, NULL, 'remote', 'data_steward@company.com');

-- Inbound staging table tracks raw values and their mapping
CREATE TABLE stg_location_mapping (
    raw_location_value VARCHAR(255) PRIMARY KEY,
    location_id INT REFERENCES dim_job_location(location_id),
    mapping_confidence DECIMAL(3,2),  -- 0.95 = 95% confident this is correct
    last_seen_date DATE,
    mapped_by VARCHAR(100),  -- governance: who made this mapping decision?
    CONSTRAINT fk_location FOREIGN KEY (location_id) REFERENCES dim_job_location(location_id)
);

-- Insert known mappings; unmapped values raise a flag
INSERT INTO stg_location_mapping (raw_location_value, location_id, mapping_confidence, mapped_by)
VALUES
    ('San Francisco, CA', 1, 1.0, 'data_steward@company.com'),
    ('SF', 1, 0.95, 'data_steward@company.com'),
    ('san francisco', 1, 0.90, 'data_steward@company.com'),
    ('New York, NY', 2, 1.0, 'data_steward@company.com'),
    ('Remote', 3, 1.0, 'data_steward@company.com');

-- In your ingest pipeline, join through the mapping layer
INSERT INTO job_postings_fact (job_id, job_title_short, salary_year_avg, job_work_from_home, job_posted_date, location_id)
SELECT 
    raw.job_id,
    raw.job_title_short,
    raw.salary_year_avg,
    raw.job_work_from_home,
    raw.job_posted_date,
    COALESCE(
        m.location_id,
        -1  -- default to unknown; triggers alert for curation team
    ) AS location_id
FROM raw_job_postings raw
LEFT JOIN stg_location_mapping m ON LOWER(TRIM(raw.job_location)) = LOWER(TRIM(m.raw_location_value));

-- Governance query: what unmapped locations are we seeing?
SELECT DISTINCT
