---
date: 2026-08-31
phase: modelling
topic: Boolean fields vs flags vs status enumerations
---

# Boolean fields vs flags vs status enumerations

*Data modelling and warehousing*

## Concept

Boolean fields are binary (TRUE/FALSE), flags are typically integers (0/1) with implicit meaning, and status enumerations are explicit categorical values (e.g., 'active', 'inactive', 'paused'). The distinction matters because a single boolean column obscures business logic and creates ambiguity—is TRUE "yes they work remote" or "yes they don't work remote"? Without clarity, every analyst queries you instead of the schema. Status enumerations scale when you need more than two states (common in real workflows) and make queries self-documenting. A job posting isn't just "remote or not"; it might be 'fully_remote', 'hybrid', 'on_site', or 'flexible'. Once you add a fourth state, a boolean breaks and forces schema changes; an enumeration handles it naturally.

The cost of using boolean when you should use enumeration appears later: renaming columns, adding comments no one reads, or worse, discovering the business logic was never captured. A schema that forces you to *ask* what a column means has failed its primary job—enabling independent querying.

## Practice

**Problem:** The `job_work_from_home` boolean column is ambiguous. Does TRUE mean "fully remote," "hybrid allowed," or "not on-site"? Analysts need clarification and future work-type requirements (fully remote, hybrid, on-site, flexible) will require schema changes.

**Solution:**

```sql
-- Replace boolean with enumeration in staging/modelling layer
CREATE TABLE job_postings_fact (
    job_id INT,
    job_title_short VARCHAR(100),
    salary_year_avg DECIMAL(10,2),
    job_work_type VARCHAR(20) CHECK (job_work_type IN ('fully_remote', 'hybrid', 'on_site', 'flexible')),
    job_posted_date DATE,
    job_location VARCHAR(100)
);

-- Self-documenting query; no clarification needed
SELECT job_title_short, COUNT(*) as count
FROM job_postings_fact
WHERE job_work_type = 'fully_remote'
GROUP BY job_title_short;
```

## Notes

- **Boolean creep:** Once you add a second TRUE/FALSE nuance, booleans fail silently—schema looks clean but queries require tribal knowledge.
- **Enumeration with comments:** Always add a comment or separate reference table documenting what each value means; 'hybrid' to one team might mean something different to another.
- **NULL handling:** Distinguish between "unknown work type" (NULL), "not specified" (value in enum), and "not applicable" (another value). Booleans hide this distinction.
- **Bridge to data governance:** This is where data dictionaries and lineage tracking become essential—someone must own the definition of each enumeration value.
- **Revisit:** Dimension tables in star schemas typically use enumerations (status dims), while fact tables reference them—organize this relationship early to avoid repeated definitions.
