---
date: 2026-08-10
phase: modelling
topic: Bridge tables for many-to-many relationships
---

# Bridge tables for many-to-many relationships

*Data modelling and warehousing*

## Concept

A bridge table (also called a junction or association table) maps two entities that have a many-to-many relationship by storing only their primary keys. Without it, you'd either duplicate rows (violating normalization) or lose data entirely. For example, a job posting can require multiple skills, and a skill can appear across many job postings—neither a one-to-many structure nor denormalization handles this cleanly.

Bridge tables are essential the moment you encounter "many sides" in your data model. They keep your fact and dimension tables lean, prevent update anomalies, and make queries explicit about relationships. Without them, filtering on a single skill drags in irrelevant job postings or forces you to store "skill1, skill2, skill3" as a single string column—a maintenance nightmare that breaks analytics.

The bridge table itself is usually sparse (few columns: two or more foreign keys, sometimes a join date or rank). It sits between your fact/dimension layers and forces you to think clearly about what "belongs together."

## Practice

**Problem:** Your `job_postings_fact` table has job postings with salary and location, but each posting requires multiple skills. Storing skills as a comma-separated string in a `required_skills` column breaks filtering and aggregation. How do you model this?

**Solution:** Create a bridge table:

```sql
-- Bridge table mapping jobs to skills
CREATE TABLE job_skills_bridge (
    job_id INT NOT NULL,
    skill_id INT NOT NULL,
    PRIMARY KEY (job_id, skill_id),
    FOREIGN KEY (job_id) REFERENCES job_postings_fact(job_id),
    FOREIGN KEY (skill_id) REFERENCES skills_dim(skill_id)
);

-- Now you can query cleanly:
SELECT j.job_id, j.job_title_short, j.salary_year_avg, s.skill_name
FROM job_postings_fact j
INNER JOIN job_skills_bridge jsb ON j.job_id = jsb.job_id
INNER JOIN skills_dim s ON jsb.skill_id = s.skill_id
WHERE s.skill_name = 'Python'
  AND j.salary_year_avg > 100000;
```

## Notes

- **Composite primary keys matter:** The bridge table's PK should be `(job_id, skill_id)` to prevent duplicate relationships and ensure each pair appears once.
- **Bridge tables are not facts:** They have no measures, only foreign keys and possibly metadata like `proficiency_level` or `years_required`. Treat them as structural, not analytical.
- **Connects to slowly-changing dimensions:** If a skill's attributes change (e.g., category reclassification), you may need timestamps on the bridge table or a Type 2 SCD in the dimension.
- **Query pattern: always join through the bridge.** Never denormalize back into the fact table; the bridge *is* the contract between your dimensions.
- **Watch for cartesian products:** If you join multiple bridge tables (`job_skills_bridge` *and* `job_locations_bridge`) without care, you can multiply rows unexpectedly. Use `DISTINCT` or aggregate carefully.
