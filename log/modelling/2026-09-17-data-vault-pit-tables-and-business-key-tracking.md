---
date: 2026-09-17
phase: modelling
topic: Data vault pit tables and business key tracking
---

# Data vault pit tables and business key tracking

*Data modelling and warehousing*

## Concept

A PIT (Point-In-Time) table captures the state of a business entity at specific moments, paired with business key tracking to maintain the historical lineage of what changed. In data vault methodology, this solves a critical problem: slowly changing dimensions and fact tables often obscure *when* a record actually became valid. Without PIT tables, you end up joining multiple dimension versions with facts, creating ambiguity about which version was "active" at query time.

PIT tables store a surrogate key for each business key (e.g., job_id) alongside effective dates and references to the current dimension satellite keys at that point in time. This lets you query "what was the state of this job posting on 2024-03-15?" without guessing which version to use. Business key tracking ensures you never lose the natural identifier (job_id) and can trace every change back to its source.

Without PIT tables, dimensional queries become fragile: you either materialize many versions of facts (bloating storage), or you lose historical context entirely. The PIT table is your audit trail and your performance safety net combined.

## Practice

**Problem:** You have job postings that update frequently (salary corrections, location changes, remote status updates). You need to report "how many jobs offering remote work were posted each day?" but salary_year_avg changed three times for some postings. Which version do you use in your daily count?

```sql
-- PIT table structure (built during load)
CREATE TABLE job_postings_pit (
    job_postings_pit_key SERIAL PRIMARY KEY,
    job_id INT NOT NULL,  -- business key
    effective_date DATE NOT NULL,
    end_date DATE,
    current_salary_satellite_key INT,
    current_location_satellite_key INT,
    current_work_from_home_satellite_key INT
);

-- Query: remote jobs posted on 2024-06-01, using PIT
SELECT 
    pit.job_id,
    sat_wfh.job_work_from_home,
    sat_loc.job_location,
    sat_sal.salary_year_avg
FROM job_postings_pit pit
JOIN job_postings_sat_work_from_home sat_wfh 
    ON pit.current_work_from_home_satellite_key = sat_wfh.satellite_key
JOIN job_postings_sat_location sat_loc 
    ON pit.current_location_satellite_key = sat_loc.satellite_key
JOIN job_postings_sat_salary sat_sal 
    ON pit.current_salary_satellite_key = sat_sal.satellite_key
WHERE pit.effective_date = '2024-06-01' 
  AND sat_wfh.job_work_from_home = TRUE
  AND pit.end_date IS NULL;
```

## Notes

- **Business key must always be present:** job_id stays in the PIT table even after you join satellites; it's your connection back to raw data and audit logs when questions arise.
- **End-dating discipline is critical:** if end_date is NULL or inconsistent, you'll silently query stale satellite versions. Establish a clear policy (e.g., end_date = next effective_date - 1 day).
- **PIT bridges to SCD Type 2 dimensions:** both track history, but SCD Type 2 lives in the dimension table itself, while PIT is a separate navigation layer—choose based on query cardinality and update frequency.
- **Adjacent: bridge tables and conformed dimensions.** PIT tables are most powerful when satellite designs are normalized; otherwise you're re-joining the same data you already denormalized.
- **Revisit: slowly changing dimensions (SCD), effective-date logic, and dimensional conformance**—PIT success depends on clean upstream satellite loads.
