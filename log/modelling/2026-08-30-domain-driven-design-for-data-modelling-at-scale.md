---
date: 2026-08-30
phase: modelling
topic: Domain-driven design for data modelling at scale
---

# Domain-driven design for data modelling at scale

*Data modelling and warehousing*

## Concept

Domain-driven design (DDD) for data models means structuring your schema around business concepts and language, not technical convenience. Instead of generic column names like `col_5` or `is_active`, you name things exactly as your business talks about them: `job_work_from_home`, `salary_year_avg`. When a stakeholder asks "show me remote jobs," engineers shouldn't need to ask which column that is—the schema itself answers the question.

This matters at scale because ambiguity compounds. Ten columns might seem clear to their creator, but across a team of 20, three different people will interpret `location` differently: is it postal code, city, region, or timezone? Without shared vocabulary embedded in the schema, you get duplicate logic, conflicting analyses, and questions routed to you instead of self-service analytics.

Without DDD, you build a schema that technically works but fails as a communication tool. Teams create their own interpretations, queries diverge, trust in metrics erodes, and you become a permanent bottleneck answering "what does this column actually mean?"

## Practice

**Problem:** Your `job_postings_fact` table uses `job_work_from_home` as a BOOLEAN, but the business distinguishes between fully remote, hybrid, and on-site roles. Teams are writing conflicting queries—some treat `TRUE` as "hybrid allowed," others as "fully remote only." You need to align the schema with actual business logic.

```sql
-- OLD: Ambiguous boolean
SELECT COUNT(*) FROM job_postings_fact WHERE job_work_from_home = TRUE;

-- NEW: Domain language explicit
ALTER TABLE job_postings_fact 
RENAME COLUMN job_work_from_home TO work_arrangement;

ALTER TABLE job_postings_fact 
MODIFY COLUMN work_arrangement VARCHAR(50) 
CHECK (work_arrangement IN ('fully_remote', 'hybrid', 'on_site'));

-- Now queries are self-documenting
SELECT COUNT(*) FROM job_postings_fact 
WHERE work_arrangement = 'fully_remote';
```

## Notes

- **Mistake:** Treating domain design as optional polish. Name ambiguity costs time exponentially—save it upfront through conversation with stakeholders.
- **Mistake:** Over-normalizing for storage while losing readability. A denormalized, well-named fact table beats a normalized schema nobody understands.
- **Adjacent topic:** Data dictionaries and metadata management—DDD is the foundation; a living dictionary is how you scale it across teams.
- **Adjacent topic:** Conformed dimensions—multiple fact tables need shared dimension definitions so business logic stays consistent (e.g., work_arrangement means the same thing everywhere).
- **Revisit:** Ask your stakeholders directly: "How do you talk about this concept in meetings?" That's your column name.
