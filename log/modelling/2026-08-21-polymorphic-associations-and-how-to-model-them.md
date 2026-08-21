---
date: 2026-08-21
phase: modelling
topic: Polymorphic associations and how to model them
---

# Polymorphic associations and how to model them

*Data modelling and warehousing*

## Concept

A polymorphic association occurs when a single foreign key can reference multiple different entity types. For example, a `comments` table might have a `commentable_id` that points to either a `posts` row or a `users` row depending on a type discriminator column. This pattern is common in application code but creates ambiguity in analytics—you can't join `commentable_id` to a single table, and downstream users won't know what entity they're actually querying without consulting code or documentation.

In data warehouses, polymorphic associations break the principle of self-documenting schemas. A analyst seeing `entity_id = 42` in a fact table has no way to know if it's a job, a candidate, or a company without additional context. This forces dependency on tribal knowledge and creates maintenance burden when the application adds a new entity type.

The solution is to denormalize at the warehouse layer: create explicit foreign keys for each entity type, keep only the relevant one populated per row, and add a discriminator column (`entity_type`) that names which relationship is active. This adds columns but eliminates ambiguity and makes queries self-serve.

## Practice

**Problem:** Your application stores notifications with a `notifiable_id` that can reference either a `job_posting` or a `candidate_profile`. In the warehouse, analysts query `notifications_fact` but can't reliably join to the correct entity without writing custom logic. New team members don't know the join rules exist.

**Solution:**

```sql
-- Before (polymorphic, ambiguous)
CREATE TABLE notifications_fact (
  notification_id INT PRIMARY KEY,
  notifiable_id INT,
  notifiable_type VARCHAR(50),  -- 'job_posting' or 'candidate_profile'
  message TEXT,
  created_at DATE
);

-- After (denormalized, self-documenting)
CREATE TABLE notifications_fact (
  notification_id INT PRIMARY KEY,
  entity_type VARCHAR(50) NOT NULL,  -- discriminator: 'job_posting' or 'candidate_profile'
  job_posting_id INT,
  candidate_profile_id INT,
  message TEXT,
  created_at DATE,
  FOREIGN KEY (job_posting_id) REFERENCES job_postings_fact(job_id),
  FOREIGN KEY (candidate_profile_id) REFERENCES candidate_profiles_dim(candidate_id),
  CONSTRAINT exactly_one_entity CHECK (
    (job_posting_id IS NOT NULL AND candidate_profile_id IS NULL) 
    OR (job_posting_id IS NULL AND candidate_profile_id IS NOT NULL)
  )
);

-- Query is now unambiguous
SELECT n.notification_id, jp.job_title_short, n.message
FROM notifications_fact n
LEFT JOIN job_postings_fact jp ON n.job_posting_id = jp.job_id
WHERE n.entity_type = 'job_posting';
```

## Notes

- **Null foreign keys are acceptable here**—the CHECK constraint ensures exactly one relationship is non-null. This is one rare case where NULLs clarify intent rather than obscure it.
- **Discriminator column is mandatory**, not optional. Without it, downstream users must query the application layer or reverse-engineer join logic from documentation that falls out of sync.
- **Related pattern: surrogate keys.** Polymorphic associations often emerge when application code uses natural keys from different domains (user IDs and post IDs in the same column). Assign surrogate keys early to avoid this mess.
- **Watch for slowly changing dimensions.** If an entity type can change (rare but possible in complex domains), you need SCD Type 2 logic applied to the discriminator, or you risk historical queries returning wrong joins.
- **Revisit: star schema normalization, conformed dimensions, and type bridges.** These patterns work together to eliminate the need for polymorphic thinking in analytics.
