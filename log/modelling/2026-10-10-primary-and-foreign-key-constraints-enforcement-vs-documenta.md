---
date: 2026-10-10
phase: modelling
topic: Primary and foreign key constraints: enforcement vs documentation
---

# Primary and foreign key constraints: enforcement vs documentation

*Data modelling and warehousing*

## Concept

Primary keys (PK) and foreign keys (FK) serve two distinct purposes that often get conflated. **Enforcement** means the database actively prevents invalid data—null PKs, duplicate rows, or orphaned references. **Documentation** means the schema itself tells you how tables relate, so analysts understand what they're querying without needing you to explain it. In a data warehouse, enforcement is often relaxed (especially in fact tables where you append-only and late-arrive dimensions are normal), but documentation becomes *more* critical because your team queries without your help.

Without explicit FK constraints, a job_postings_fact table with a company_id column looks like any other integer column—nobody knows if it points to a companies dimension or is just a label. Without documentation (even if constraints are missing), analysts either guess, ask you repeatedly, or build incorrect joins. The practical trade-off: warehouses often drop FK constraints for performance and loading flexibility, but always declare them as comments or in a data dictionary so the relationship is discoverable.

## Practice

**Problem:** You inherit a job_postings_fact table with a company_id column but no constraint or comment. A junior analyst joins company_id to job_postings twice (thinking there are multiple company roles) and gets incorrect salary aggregates. How do you document the relationship to prevent this?

```sql
CREATE TABLE job_postings_fact (
    job_id INT PRIMARY KEY,
    job_title_short VARCHAR(100),
    salary_year_avg DECIMAL(10,2),
    job_work_from_home BOOLEAN,
    job_posted_date DATE,
    job_location VARCHAR(100),
    company_id INT NOT NULL,
    -- FOREIGN KEY (company_id) REFERENCES companies_dim(company_id)  [constraint commented out for performance]
    CONSTRAINT fk_company FOREIGN KEY (company_id) REFERENCES companies_dim(company_id)  [if enforced]
);

COMMENT ON COLUMN job_postings_fact.company_id = 'FK to companies_dim(company_id). One job posting = one company. Do NOT join on company_id twice.';
```

## Notes

- **Enforcement vs. documentation trade-off:** Many warehouses drop FKs to avoid slow inserts and to allow late-arriving dimensions; always compensate with explicit comments or a data lineage tool.
- **Primary key cardinality is documentation:** If job_id is PK, analysts immediately know each row is unique by job. If it's not, they cannot assume uniqueness without asking.
- **NULL in FK columns:** Even without constraints, document whether company_id can be null and what it means (missing metadata vs. intentional unknown).
- **Related to:** dimensional modeling (fact vs. dimension table roles), slowly changing dimensions (SCD types), and data quality tests (check for orphaned FKs in dbt or Great Expectations even without constraints).
- **Revisit after:** setting up dbt or a data catalog tool that auto-documents relationships; you can then enforce fewer database constraints and rely on tooling.
