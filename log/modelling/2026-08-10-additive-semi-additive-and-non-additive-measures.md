---
date: 2026-08-10
phase: modelling
topic: Additive, semi-additive and non-additive measures
---

# Additive, semi-additive and non-additive measures

*Data modelling and warehousing*

## Concept

Measures in a fact table fall into three categories based on how they aggregate across dimensions. **Additive measures** (like revenue, quantity sold, or count) combine meaningfully across all dimensions—sum them by any attribute and the result is valid. **Semi-additive measures** (like account balance, inventory level, or headcount) aggregate meaningfully across some dimensions but not time; summing a balance across months is nonsense, but summing across locations is valid. **Non-additive measures** (like price, discount rate, or average salary) never sum meaningfully—you must first aggregate the underlying counts or amounts, then calculate the ratio.

Without this classification, queries break silently. A dashboard that sums `salary_year_avg` across job postings looks plausible but is meaningless—you've added incompatible values. A BI tool that auto-sums a semi-additive measure like account balance across a time dimension will produce garbage. Clarity at schema design time prevents downstream consumers (analysts, BI tools, self-service dashboards) from making this mistake themselves.

## Practice

**Problem:** Your team built a fact table of job postings but the analytics team is summing `salary_year_avg` across job titles and locations, and management is now confused about total compensation spend. How do you fix the schema to make the correct aggregation path obvious?

**Solution:** Separate the non-additive measure into its additive components, and document the intended aggregation:

```sql
-- Original (problematic)
CREATE TABLE job_postings_fact (
    job_id INT,
    job_title_short VARCHAR,
    salary_year_avg DECIMAL,  -- NON-ADDITIVE: never sum this
    job_work_from_home BOOLEAN,
    job_posted_date DATE,
    job_location VARCHAR
);

-- Corrected
CREATE TABLE job_postings_fact (
    job_id INT,
    job_title_short VARCHAR,
    salary_year_avg DECIMAL,  -- DOCUMENTED: non-additive; use for filtering/grouping only
    job_count INT,            -- ADDITIVE: safely sum across any dimension
    job_posted_date DATE,     -- ADDITIVE: count of postings
    job_work_from_home BOOLEAN,
    job_location VARCHAR
);

-- Correct query: derive avg salary only after summing counts
SELECT 
    job_location,
    SUM(job_count) AS total_postings,
    ROUND(SUM(salary_year_avg * job_count) / SUM(job_count), 2) AS avg_salary
FROM job_postings_fact
GROUP BY job_location;
```

## Notes

- **Mistake:** Treating a ratio (average, percentage, rate) as additive. Always decompose into numerator and denominator before aggregation.
- **Mistake:** Forgetting that "semi-additive" depends on context—inventory level is semi-additive across location but *requires point-in-time selection* across time (snapshot, not sum).
- **Connection:** This is why slowly-changing dimensions exist; a dimension attribute's value at query time may differ from its value when the fact was recorded, affecting which aggregations are valid.
- **Connection:** Grain and cardinality matter here—if your fact table grain is "one row per job posting," then `job_count` should be 1 and salary is still non-additive. Consider whether you need a pre-aggregated table.
- **Revisit:** When building cubes or aggregate tables, explicitly tag measures in metadata (Looker, dbt docs, a data dictionary) so self-service users never guess.
