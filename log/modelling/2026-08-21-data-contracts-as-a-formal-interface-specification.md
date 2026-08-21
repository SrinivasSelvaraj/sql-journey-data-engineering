---
date: 2026-08-21
phase: modelling
topic: Data contracts as a formal interface specification
---

# Data contracts as a formal interface specification

*Data modelling and warehousing*

## Concept

A data contract is a formal specification that documents what data consumers can expect from a dataset: column names, data types, valid value ranges, null policies, and semantic meaning. It acts as a service-level agreement between data producers and consumers, eliminating the need for repeated "what does this column mean?" conversations.

Without explicit contracts, schema drift goes undetected (a column silently changes from string to int), semantic confusion spreads (is `salary_year_avg` median or mean? gross or net?), and consumers build fragile queries on undocumented assumptions. Contracts are especially critical in mature warehouses where dozens of teams query the same tables; one person's rename or type change breaks downstream dashboards silently.

A contract lives as documentation paired with schema validation rules. At minimum, it should specify: each column's name, type, and nullable status; expected value ranges or enums; the semantic definition; and the data refresh cadence. Tools like dbt can enforce contracts on every load, rejecting data that violates the agreement before it reaches consumers.

## Practice

**Problem:** The `job_postings_fact` table is shared across hiring analytics, recruiter dashboards, and a public API. Without a contract, you discover that different teams interpret `salary_year_avg` differently—some assume null means "not disclosed" (exclude from analysis), others assume it's "unknown" (should impute). The API team adds a new column `salary_currency` without notifying downstream consumers. A recruiter's dashboard breaks.

**Solution:**

```sql
-- Define the contract explicitly (dbt example syntax)
-- File: models/job_postings_fact.yml
version: 2
models:
  - name: job_postings_fact
    description: "Fact table of job postings. Single row per posting."
    columns:
      - name: job_id
        description: "Unique job posting identifier"
        data_type: int
        constraints:
          - type: not_null
          - type: unique
      
      - name: job_title_short
        description: "Standardized job title category (e.g., 'Data Analyst', 'Senior Engineer')"
        data_type: varchar
        constraints:
          - type: not_null
        accepted_values: ['Data Analyst', 'Data Engineer', 'Senior Engineer', ...]
      
      - name: salary_year_avg
        description: "Average annual salary in USD. Null indicates salary not disclosed by employer."
        data_type: numeric(10,2)
        constraints:
          - type: accepted_values
            values: [null] # or range: [20000, 500000]
      
      - name: job_work_from_home
        description: "Boolean: true if role is remote-eligible, false if on-site only"
        data_type: boolean
        constraints:
          - type: not_null
      
      - name: job_posted_date
        description: "Date job was posted (UTC). Historical posts retained for 2 years."
        data_type: date
        constraints:
          - type: not_null
    
    freshness:
      warn_after: {count: 6, period: hour}
      error_after: {count: 24, period: hour}
    
    tests:
      - dbt_expectations.expect_column_values_to_be_of_type:
          column_name: salary_year_avg
          type: "NUMERIC"

-- Enforce on load: contract violations block data ingestion
-- Teams can now trust the schema without asking for clarification
```

## Notes

- **Mistake:** Documenting the contract in a Slack message or wiki that drifts out of sync with schema changes. Keep contracts as code (dbt, JSON Schema, Protobuf) in version control so they enforce automatically.

- **Mistake:** Making contracts too rigid early. Start with critical columns (PK, revenue, timestamp) and loosen constraints as your understanding grows; over-constraining causes unnecessary pipeline failures.

- **Adjacent topic:** Schema versioning and backward compatibility—how to evolve contracts without breaking consumers. Add nullable columns, deprecate old ones gracefully, avoid type changes in place.

- **Adjacent topic:** Data lineage and observability. Contracts define the interface; lineage tools (like dbt DAGs) show who depends on it, surfacing the blast radius of changes.

- **Revisit:** Testing strategy. A contract is half the story; you also need tests that verify *data quality* (distinct job_ids, salary_year_avg > 0 when not null) separate from structural validation.
