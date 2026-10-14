---
date: 2026-10-14
phase: cloud
topic: Snowflake data sharing and Secure Data Exchange
---

# Snowflake data sharing and Secure Data Exchange

*Cloud platforms and storage*

## Concept

Snowflake Data Sharing and Secure Data Exchange enable zero-copy data sharing between accounts and organizations without moving or duplicating data. A *share* is a named object that grants read-only access to selected databases, schemas, or tables; the consumer sees live data without ETL overhead. This matters because sharing data cross-organization—especially with partners, vendors, or internal teams in separate accounts—eliminates replication costs and staleness while maintaining security boundaries.

Without these mechanisms, you either duplicate data (expensive storage, sync delays, compliance risks) or resort to insecure export/import workflows. Snowflake's approach keeps data in place, charges only the *reader* for compute (not the data holder), and allows fine-grained object-level access control. Secure Data Exchange adds a business layer: requests, listings, and managed agreements that formalize who can access what.

Understanding sharing is critical for cost optimization—a shared table costs nothing to the provider but does incur compute costs for the consumer's queries. Slow sharing queries often reveal inefficient filtering or missing clustering keys, not storage problems.

## Practice

**Problem:** Your HR team maintains `job_postings_fact` in account A. The Analytics team in account B needs to query posting volume by job title and work-from-home status without copying the data. Create a secure share granting access to this table, and write a query in account B that counts postings by `job_title_short` and `job_work_from_home` to identify trends.

```sql
-- Account A: Create and populate the share
CREATE SHARE job_postings_share;
GRANT USAGE ON DATABASE hr_db TO SHARE job_postings_share;
GRANT USAGE ON SCHEMA hr_db.public TO SHARE job_postings_share;
GRANT SELECT ON TABLE job_postings_fact TO SHARE job_postings_share;
ALTER SHARE job_postings_share ADD ACCOUNTS = 'account_b_name';

-- Account B: Create a database from the inbound share
CREATE DATABASE job_postings_shared FROM SHARE account_a_name.job_postings_share;

-- Account B: Query the shared data
SELECT 
  job_title_short,
  job_work_from_home,
  COUNT(*) AS posting_count
FROM job_postings_shared.public.job_postings_fact
WHERE job_posted_date >= CURRENT_DATE - INTERVAL '30 days'
GROUP BY job_title_short, job_work_from_home
ORDER BY posting_count DESC;
```

## Notes

- **Cost asymmetry:** The data provider pays nothing for sharing; the consumer's account is billed for all compute. Monitor consumer query patterns to catch runaway scans on unclusteredColumns.
- **Read-only enforcement:** Shares grant SELECT only. If the consumer needs to join with their own tables, they must create a view or materialized view in their own database—that compute cost lands on them.
- **Clustering and pruning matter more here:** Without proper clustering on frequently filtered columns (e.g., `job_posted_date`), the consumer's queries scan the entire table remotely, inflating their bill. Always ask: "Will the consumer filter on this column?"
- **Secure Data Exchange vs. direct shares:** Exchange adds governance layers (request workflows, listings) and is better for external or semi-trusted partners. Direct shares are faster for internal cross-account access or established integrations.
- **Adjacent topics:** Virtual warehouses (sizing for consumer workloads), network policies (restricting IP access to shares), and Time Travel (consumers can query historical snapshots, which may surprise them on their bill).
