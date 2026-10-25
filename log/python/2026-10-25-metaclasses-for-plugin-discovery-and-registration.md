---
date: 2026-10-25
phase: python
topic: Metaclasses for plugin discovery and registration
---

# Metaclasses for plugin discovery and registration

*Python for data engineering*

## Concept

Metaclasses enable automatic plugin discovery and registration by intercepting class creation. When you define a subclass, the metaclass's `__init_subclass__()` hook fires, letting you register that plugin without explicit boilerplate. This matters in data pipelines where you have many extractors, transformers, or validators—each plugin registers itself into a central registry, and your pipeline engine discovers them at runtime without hardcoding imports.

Without metaclasses, you'd manually maintain a registry dict and risk forgetting to register new plugins. Bad input—a typo in a plugin name, a missing import—silently fails or crashes downstream. A metaclass-driven registry makes plugin presence verifiable at class definition time, not at pipeline execution time. This catches configuration errors early and keeps your pipeline code DRY and discoverable.

## Practice

**Problem:** You have a `job_postings_fact` table. You need a plugin system where different extraction sources (LinkedIn, Indeed, custom CSV) each define a `SourceExtractor` subclass. At runtime, your pipeline should discover all available extractors and validate that a requested source exists before querying.

```python
class SourceRegistry(type):
    """Metaclass that auto-registers all SourceExtractor subclasses."""
    _registry = {}
    
    def __init_subclass__(cls, **kwargs):
        super().__init_subclass__(**kwargs)
        if cls.__name__ != 'SourceExtractor':  # skip abstract base
            SourceRegistry._registry[cls.source_name] = cls

class SourceExtractor(metaclass=SourceRegistry):
    source_name = None
    
    def extract(self) -> list[dict]:
        raise NotImplementedError

class LinkedInExtractor(SourceExtractor):
    source_name = 'linkedin'
    
    def extract(self) -> list[dict]:
        return [{'job_id': 1, 'job_title_short': 'Data Engineer', ...}]

class IndeedExtractor(SourceExtractor):
    source_name = 'indeed'
    
    def extract(self) -> list[dict]:
        return [{'job_id': 2, 'job_title_short': 'Analytics Engineer', ...}]

# Usage: validate source before pipeline runs
def load_job_postings(source: str):
    if source not in SourceRegistry._registry:
        raise ValueError(f"Unknown source '{source}'. Available: {list(SourceRegistry._registry.keys())}")
    extractor = SourceRegistry._registry[source]()
    return extractor.extract()
```

## Notes

- **Common mistake:** Forgetting `__init_subclass__()` and instead overriding `__init__()`, which requires explicit plugin instantiation and defeats auto-discovery.
- **Type safety:** Use `__init_subclass__()` to enforce required attributes (e.g., `source_name`) via `assert hasattr(cls, 'source_name')`, catching misconfigured plugins at definition time.
- **Testing:** Mock the registry in unit tests by accessing `SourceRegistry._registry` directly; avoid relying on import side-effects for test plugin discovery.
- **Adjacent topics:** Decorators (`@register_plugin`) and entry points (`setup.py`) offer lighter alternatives for small registries; metaclasses scale better for large codebases with strict validation requirements.
- **Revisit:** Abstract base classes (`abc.ABC`, `@abstractmethod`) often pair with metaclasses to enforce interface contracts—combine them for bulletproof plugin systems.
