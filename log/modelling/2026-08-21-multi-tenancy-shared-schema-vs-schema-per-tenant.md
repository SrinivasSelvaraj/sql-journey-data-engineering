---
date: 2026-08-21
phase: modelling
topic: Multi-tenancy: shared schema vs schema-per-tenant
---

# Multi-tenancy: shared schema vs schema-per-tenant

*Data modelling and warehousing*

## Concept

Multi-tenancy is the architectural choice of how to isolate data for different customers/organizations in a shared application. **Shared schema** means all tenants' rows live in the same tables with a `tenant_id` column; **schema-per-tenant** means each tenant gets separate tables or even separate databases. This choice cascades through every query, security policy, and scaling decision you make.

The decision matters most when tenants have different compliance requirements (GDPR, data residency), unpredictable growth rates, or when query performance across millions of rows for one tenant degrades the experience for others. Without a deliberate choice, you'll either face data leakage (tenant A queries tenant B's salary data) or operational chaos (can't isolate one tenant's schema without affecting others).

In a data warehouse context, shared schema is simpler to query and report across tenants, but schema-per-tenant gives you physical isolation, easier scaling per customer, and clearer cost attribution. Most SaaS platforms use shared schema at the OLTP layer (application database) and decide per-tenant or shared at the warehouse layer depending on self-service analytics needs.

## Practice

**Problem:** Your `job_postings_fact` table stores postings from multiple recruiting agencies (tenants). Agency A (US-based) must never see Agency B's salary data due to contract terms. A analyst accidentally wrote `SELECT * FROM job_postings_fact WHERE job_location LIKE '%New York%'` in a shared workspace—they got Agency B's confidential data.

**Solution with shared schema + row-level security:**

```sql
-- Add tenant identifier
ALTER TABLE job_postings_fact ADD COLUMN tenant_id INT NOT NULL;
CREATE INDEX idx_job_postings_tenant ON job_postings_fact(tenant_id);

-- Create role per tenant (or use application context)
CREATE POLICY job_postings_tenant_isolation ON job_postings_fact
  USING (tenant_id = current_setting('app.current_tenant_id')::INT);
ALTER TABLE job_postings_fact ENABLE ROW LEVEL SECURITY;

-- Analyst query—automatically filtered by their tenant_id
SELECT job_title_short, salary_year_avg, job_location 
FROM job_postings_fact 
WHERE job_location LIKE '%New York%';
-- Returns only rows where tenant_id matches current_setting('app.current_tenant_id')
```

## Notes

- **Shared schema trap:** Row-level security only works if the application *always* sets the context variable correctly. One missing `current_setting('app.current_tenant_id')` in a batch job and you're back to data leakage.
- **Schema-per-tenant complexity:** Easier to isolate, but versioning schema changes across 500 customer schemas becomes DevOps hell; consider using templated migration frameworks (Flyway, Liquibase) if you go this route.
- **Hybrid approach:** Use shared schema at OLTP layer for operational simplicity, then snapshot each tenant's data into separate marts/schemas in the warehouse for analytics isolation and cost tracking.
- **Adjacent skills:** Row-level security (PostgreSQL, Snowflake SECURE views), `current_user` / application context patterns, and tenant-aware indexing (put `tenant_id` first in all composite indexes).
- **Revisit when:** Your warehouse grows beyond a few billion rows per tenant, or when you onboard a customer with strict data residency rules (EU-only storage)—that's usually when you regret shared schema.
