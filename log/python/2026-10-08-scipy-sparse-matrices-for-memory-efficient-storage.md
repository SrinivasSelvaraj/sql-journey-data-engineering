---
date: 2026-10-08
phase: python
topic: Scipy sparse matrices for memory-efficient storage
---

# Scipy sparse matrices for memory-efficient storage

*Python for data engineering*

## Concept

Scipy sparse matrices store only non-zero values plus their coordinates, reducing memory footprint dramatically when data is >90% zeros. In data pipelines, this matters for feature matrices, TF-IDF vectorization, and adjacency representations where dense storage wastes gigabytes on padding. Without sparsity, a 1M × 50K term-document matrix consumes ~200GB dense; sparse CSR format uses ~2GB.

Scipy provides three main formats: COO (coordinate, easy to build), CSR (compressed sparse row, fast row slicing), and CSC (compressed sparse column, fast column ops). The tradeoff is access speed—sparse matrices are slower than dense for random element lookup, and they break silently if your "sparse" data isn't actually sparse (no zero compression occurs, just overhead).

In production pipelines, sparse matrices pair with scikit-learn, sparse linear algebra, and downstream ML models that accept scipy sparse input natively. However, they don't serialize easily to Parquet or CSV, and type checkers struggle to validate them, so you need explicit guards in your typed pipeline code.

## Practice

**Problem:** You need to build a job-posting feature matrix for salary prediction. Feature 1: one-hot encoded job titles (thousands of unique values, most jobs have one title). Feature 2: salary itself. Feature 3: work-from-home (boolean). Most rows have 2–3 non-zero features. Store this efficiently and ensure the pipeline rejects malformed input.

```python
from scipy.sparse import csr_matrix, hstack
from typing import Union
import numpy as np
import pandas as pd

def build_job_feature_matrix(df: pd.DataFrame) -> Union[csr_matrix, None]:
    """
    Build sparse feature matrix from job postings.
    Returns CSR matrix or None if validation fails.
    """
    # Validate input
    required_cols = {'job_title_short', 'salary_year_avg', 'job_work_from_home'}
    if not required_cols.issubset(df.columns):
        raise ValueError(f"Missing columns: {required_cols - set(df.columns)}")
    
    if df.empty or any(df[required_cols].isna().any()):
        return None
    
    # Feature 1: one-hot job titles (sparse)
    title_dummies = pd.get_dummies(
        df['job_title_short'], 
        dtype='uint8',
        sparse=True
    ).astype('uint8')
    title_sparse = csr_matrix(title_dummies)
    
    # Feature 2: salary (dense, convert to sparse column)
    salary_col = np.log1p(df['salary_year_avg'].fillna(0)).values.reshape(-1, 1)
    salary_sparse = csr_matrix(salary_col)
    
    # Feature 3: work-from-home (sparse)
    wfh_col = df['job_work_from_home'].astype('uint8').values.reshape(-1, 1)
    wfh_sparse = csr_matrix(wfh_col)
    
    # Horizontally stack all features
    feature_matrix = hstack([title_sparse, salary_sparse, wfh_sparse])
    
    return feature_matrix.tocsr()  # Ensure CSR format for row access
```

## Notes

- **Type annotation gap:** `scipy.sparse` matrices don't satisfy `pd.DataFrame` or numpy array type hints; use `Union[csr_matrix, None]` and document format expectations explicitly in docstrings.
- **Silent performance cliffs:** if your "sparse" data is actually dense (e.g., all job titles are unique, filling the matrix), sparse storage becomes slower and fatter than dense—profile with `sparsity = 1 - nnz / (m * n)` first.
- **Serialization friction:** sparse matrices don't pickle well across Python versions; prefer converting to COO format, exporting to triplet CSV, or using `scipy.sparse.save_npz()` for intermediate checkpoints.
- **Scikit-learn coupling:** most estimators (LogisticRegression, SVM, linear regressors) accept sparse input natively and run *faster* on sparse data—but some (tree-based) don't, so validate compatibility before committing to sparse pipelines.
- **Adjacent topics:** understand CSR vs. CSC format choice (row ops → CSR, column ops → CSC), learn `sparse.random()` for benchmarking, and revisit when handling billion-row feature stores where dense is infeasible.
