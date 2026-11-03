---
date: 2026-11-03
phase: reliability
topic: Test coverage: unit, integration, end-to-end tests
---

# Test coverage: unit, integration, end-to-end tests

*Quality, reliability and the professional layer*

## Concept

Test coverage across three layers ensures that data pipelines fail predictably and are debugged methodically. **Unit tests** validate individual components in isolation—a transformation function, a schema validator, or a data quality rule. **Integration tests** verify that components work together correctly—that your extraction feeds cleanly into your transformation layer. **End-to-end tests** simulate the real production flow from source through to consumer, catching issues that unit and integration tests miss: latency problems, permission errors, or contract violations between systems.

Without layered testing, you discover failures in production: a pipeline runs green locally but crashes on the cluster, or data quality degrades silently because no one validated assumptions about upstream schema changes. The professional difference is stark: a pipeline builder ships code and hopes; a trusted owner ships code and has proof it works before it touches real data.

Coverage means *intentional gaps are documented*. You don't need 100% coverage, but you must know which code paths are untested and why that's acceptable. For data work, this often means: test the business logic ruthlessly, accept some coverage gaps in boilerplate, and always test at the edges—null handling, boundary conditions, late-arriving data.

## Practice

**Problem:** The `job_postings_fact` table's `salary_year_avg` column occasionally contains negative values and nulls. A downstream BI dashboard that ranks jobs by salary breaks when it encounters these. You own this table and need to prevent bad data from reaching consumers.

```sql
-- Unit test: salary validation rule
SELECT 
  CASE 
    WHEN salary_year_avg < 0 THEN 'FAIL: negative salary'
    WHEN salary_year_avg IS NULL AND job_title_short NOT IN ('Unpaid Intern', 'Volunteer') THEN 'FAIL: missing salary for paid role'
    WHEN salary_year_avg > 5000000 THEN 'FAIL: salary implausibly high'
    ELSE 'PASS'
  END AS validation_result,
  COUNT(*) AS row_count
FROM job_postings_fact
WHERE job_posted_date = CURRENT_DATE
GROUP BY validation_result
HAVING validation_result LIKE 'FAIL%';

-- Integration test: transformation preserves lineage and counts
SELECT 
  COUNT(DISTINCT job_id) AS fact_count,
  COUNT(DISTINCT job_location) AS unique_locations,
  MIN(job_posted_date) AS earliest_post,
  CASE 
    WHEN COUNT(*) = 0 THEN 'FAIL: empty load'
    WHEN COUNT(*) < (SELECT COUNT(*) FROM job_postings_staging) * 0.95 THEN 'FAIL: >5% row loss'
    ELSE 'PASS'
  END AS load_health
FROM job_postings_fact
WHERE job_posted_date = CURRENT_DATE;

-- End-to-end test: downstream consumer contract
SELECT 
  CASE 
    WHEN COUNT(*) = 0 THEN 'FAIL: no data for BI'
    WHEN SUM(CASE WHEN salary_year_avg IS NULL THEN 1 ELSE 0 END) > 0 THEN 'FAIL: nulls present'
    WHEN SUM(CASE WHEN job_work_from_home IS NULL THEN 1 ELSE 0 END) > 0 THEN 'FAIL: wfh column incomplete'
    ELSE 'PASS'
  END AS bi_readiness
FROM job_postings_fact
WHERE job_posted_date = CURRENT_DATE;
```

## Notes

- **Common mistake:** Testing only the happy path. Negative tests (wrong schema, late data, duplicates, permission denied) catch real failures.
- **Mock vs. real data:** Unit tests should use fixtures; integration and E2E tests run against real staging or production replicas to catch environment-specific bugs.
- **Connects to:** Data quality frameworks (Great Expectations, dbt tests), observability/monitoring (alerting on test failures is more valuable than passing tests), and SLA contracts with downstream teams.
- **Revisit:** Test flakiness—if a test passes 95% of the time, it's worse than no test. Flakiness usually signals tight coupling to external systems or race conditions.
- **Coverage gaps are features:** Document why certain transformations aren't tested (e.g., "we trust the vendor's CSV export schema, verified quarterly"). This drives conversations with stakeholders about risk tolerance.
