-- Practice: Full-Text Search in PostgreSQL
-- Task 1: to_tsvector / to_tsquery — convert text to searchable vectors

SELECT
    job_title_short,
    to_tsvector('english', job_title_short) AS search_vector
FROM job_postings_fact
LIMIT 5;

-- Task 2: Match a search query against a text column

SELECT job_id, job_title_short
FROM job_postings_fact
WHERE to_tsvector('english', job_title_short) @@ to_tsquery('english', 'engineer');

-- Task 3: Multi-word phrase search with & (AND) and | (OR)

SELECT job_id, job_title_short
FROM job_postings_fact
WHERE to_tsvector('english', job_title_short) @@ to_tsquery('english', 'data & engineer');

SELECT job_id, job_title_short
FROM job_postings_fact
WHERE to_tsvector('english', job_title_short) @@ to_tsquery('english', 'analyst | scientist');

-- Task 4: plainto_tsquery — no need to manually add & between words

SELECT job_id, job_title_short
FROM job_postings_fact
WHERE to_tsvector('english', job_title_short) @@ plainto_tsquery('english', 'data engineer');

-- Task 5: websearch_to_tsquery — use Google-style syntax (quoted phrases, minus)

SELECT job_id, job_title_short
FROM job_postings_fact
WHERE to_tsvector('english', job_title_short) @@ websearch_to_tsquery('english', '"machine learning" -junior');

-- Task 6: ts_rank — rank results by relevance

SELECT
    job_id,
    job_title_short,
    ts_rank(
        to_tsvector('english', job_title_short),
        to_tsquery('english', 'data')
    ) AS relevance
FROM job_postings_fact
WHERE to_tsvector('english', job_title_short) @@ to_tsquery('english', 'data')
ORDER BY relevance DESC
LIMIT 10;

-- Task 7: Create a GIN index for faster full-text search

CREATE INDEX IF NOT EXISTS idx_fts_title
ON job_postings_fact
USING GIN (to_tsvector('english', job_title_short));
