---
date: 2026-11-04
phase: reliability
topic: Change management: documentation and stakeholder communication
---

# Change management: documentation and stakeholder communication

*Quality, reliability and the professional layer*

## Concept

Change management documentation captures *why* a modification was made, not just what changed. This includes the business context, affected stakeholders, rollback procedures, and testing evidence. Without it, future maintainers inherit a codebase of mysterious decisions: Why does this filter exist? Was it intentional or a bug? Did we test this with production data?

Stakeholder communication happens *before* deployment: alerting data consumers that schema changes are coming, metric definitions are shifting, or SLA expectations are changing. A silent schema migration that breaks downstream dashboards destroys trust faster than any technical failure. The owner who communicates proactively—"we're adding a NOT NULL constraint to job_location on Tuesday, here's what that means for your queries"—becomes someone teams rely on.

This layer separates pipeline builders from pipeline *owners*. Builders ship features; owners ensure the feature doesn't silently corrupt reporting, break contracts with downstream systems, or create undocumented tribal knowledge.

## Practice

**Problem:** You're adding a new `job_salary_currency` column to `job_postings_fact` to support international job listings. The column defaults to 'USD' for existing rows, but some legacy jobs have NULL salaries that can't be converted. You need to deploy this change without breaking the analytics team's weekly compensation report.

```sql
-- CHANGE LOG ENTRY (in version control, not just comments)
-- Date: 2024-01-15
-- Owner: data_eng_team
-- Ticket: DATA-4521
-- Impact: Analytics team, Finance reporting
-- Rollback: DROP COLUMN job_salary_currency; UPDATE job_postings_fact SET salary_year_avg = NULL WHERE job_id IN (select_legacy_nulls)

-- 1. Documentation: add new column with safe default
ALTER TABLE job_postings_fact 
ADD COLUMN job_salary_currency VARCHAR(3) DEFAULT 'USD';

-- 2. Backfill: identify and document the edge case
UPDATE job_postings_fact 
SET job_salary_currency = 'UNKNOWN' 
WHERE salary_year_avg IS NULL 
  AND job_posted_date < '2023-01-01';

-- 3. Validation query: prove data integrity before announcing
SELECT 
  job_salary_currency,
  COUNT(*) as record_count,
  COUNT(CASE WHEN salary_year_avg IS NOT NULL THEN 1 END) as salary_present
FROM job_postings_fact
GROUP BY job_salary_currency;

-- 4. Stakeholder communication (sent 48 hours before deploy):
-- "New column added: job_salary_currency. All USD salaries default to 'USD'.
--  International jobs will show 'GBP', 'EUR', etc. Legacy rows with NULL salary 
--  marked as 'UNKNOWN'. Your existing queries unaffected. New queries must handle 
--  currency explicitly. Contact us with questions."
```

## Notes

- **Common mistake:** Documenting *what* changed in tickets but not *why* it matters or *who's affected*. A schema change without stakeholder notice turns you into a liability, not an asset.
- **Rollback procedures must be tested**, not theoretical. "We'll just DROP the column" is not a plan if you haven't verified it restores the exact prior state in a staging environment.
- **Connects to:** data contract enforcement (making breaking changes explicit), observability (alerting when downstream queries fail after your change), and SLA documentation (what guarantees do you make about availability during migrations?).
- **Adjacent skill:** writing effective incident postmortems—same discipline of explaining decisions and impact to non-technical stakeholders.
- **Revisit:** the line between "communicating a minor fix" and "notifying everyone." Document everything; *communicate* changes that shift definitions, nullability, or cardinality. Err on the side of over-communication early in your career.
