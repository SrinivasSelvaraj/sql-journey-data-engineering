---
date: 2026-08-29
phase: modelling
topic: Bridge tables for many-to-many relationships in star schema
---

# Bridge tables for many-to-many relationships in star schema

*Data modelling and warehousing*

## Concept

A bridge table (also called a junction or linking table) resolves many-to-many relationships in a star schema by sitting between two dimension tables. Instead of storing multiple values in a single row or denormalizing data, the bridge table holds foreign keys to both dimensions, with one row per valid combination. This keeps your fact table clean and queryable without redundancy.

Many-to-many relationships are common in real data: a job posting may require multiple skills, a skill may appear in multiple job postings. Without a bridge table, you'd either flatten the data (duplicating job posting rows) or store comma-separated values (impossible to filter or join). Both approaches break dimensional consistency and make queries fragile.

The bridge table sits logically between your fact table and one of the dimension tables. It doesn't replace the fact table; it normalizes the relationship so your fact queries remain performant and your dimension filters remain unambiguous.

## Practice

**Problem:** Your `job_postings_fact` table needs to capture skills required for each job, but jobs require multiple skills and skills span multiple jobs. You can't add a `skill_id` column to `job_postings_fact` without duplicating rows.

**Solution:** Create a `job_skills_bridge` table:

```sql
CREATE TABLE job_skills_bridge (
    job_id INT NOT NULL,
    skill_id INT NOT NULL,
    PRIMARY KEY (job_id, skill_id),
    FOREIGN KEY (job_id) REFERENCES job_postings_fact(job_id),
    FOREIGN KEY (skill_id) REFERENCES skills_dim(skill_id)
);

-- Query jobs requiring Python AND SQL without row duplication:
SELECT jpf.job_id, jpf.job_title_short, jpf.salary_year_avg
FROM job_postings_fact jpf
WHERE jpf.job_id IN (
    SELECT job_id FROM job_skills_bridge 
    WHERE skill_id IN (SELECT skill_id FROM skills_dim WHERE skill_name IN ('Python', 'SQL'))
    GROUP BY job_id
    HAVING COUNT(DISTINCT skill_id) = 2
);
```

## Notes

- **Composite primary key trap:** Always use `(foreign_key_1, foreign_key_2)` as primary key, never add a surrogate key—it obscures the many-to-many intent and wastes space.
- **Bridge vs. fact confusion:** A bridge table is *not* a fact table. It has no measures, only foreign keys and relationships. Don't add metrics to it.
- **Conformed dimensions matter:** Both dimension tables the bridge references must be conformed (shared, consistent definitions) across the warehouse, or your joins become unreliable.
- **Performance consideration:** Index both foreign key columns separately if you filter by one dimension heavily; composite indexes work for joins but not for single-column WHERE clauses.
- **Related patterns:** Snowflaking (normalizing dimensions further) and slowly-changing dimensions (SCD) often coexist with bridge tables; understand how SCD versioning interacts with bridge lookups to avoid stale joins.
