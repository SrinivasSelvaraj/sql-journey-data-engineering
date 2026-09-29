---
date: 2026-09-29
phase: streaming
topic: Processor topology vs DSL in Kafka Streams
---

# Processor topology vs DSL in Kafka Streams

*Streaming and distributed processing*

## Concept

In Kafka Streams, you can build stream processing logic two ways: the **Processor Topology API** (low-level) gives you direct control over state stores and node connections, while the **DSL** (Domain Specific Language) provides high-level operators like `map`, `filter`, `join`, and `aggregate` that abstract away topology details. The DSL compiles down to a topology internally, so you're choosing abstraction level, not fundamentally different engines.

The distinction matters when your pipeline needs custom state management, precise control over punctuation schedules, or interaction patterns the DSL doesn't expose. For example, if you need to maintain multiple state stores per processor, emit side-channel outputs conditionally, or implement a stateful operation that doesn't fit the `Transformer` model, the Processor API becomes necessary. Without understanding this trade-off, teams often either over-engineer with the Processor API when DSL is sufficient, or hit hard limits trying to force DSL semantics onto complex state logic.

## Practice

**Problem:** You receive a stream of job postings and need to flag postings where the salary has increased by >20% compared to the same job title in the last 30 days, then output only flagged postings with the previous average salary attached.

```sql
-- Conceptual solution (Processor Topology approach in pseudocode/Java-style)
KStream<String, JobPosting> postings = topology.addSource("source", "job-postings");

KStream<String, JobPosting> flagged = topology.addProcessor(
  "salary-anomaly",
  () -> new Processor<String, JobPosting>() {
    private KeyValueStore<String, SalaryStats> store;
    
    @Override
    public void init(ProcessorContext ctx) {
      store = ctx.getStateStore("job-title-salary-store");
    }
    
    @Override
    public void process(String jobId, JobPosting posting) {
      String key = posting.job_title_short;
      SalaryStats prev = store.get(key);
      
      if (prev != null && posting.salary_year_avg > prev.avgSalary * 1.2) {
        context.forward(jobId, 
          new FlaggedPosting(posting, prev.avgSalary));
      }
      
      // Update store with new salary
      SalaryStats updated = prev == null 
        ? new SalaryStats(posting.salary_year_avg, 1)
        : prev.addSalary(posting.salary_year_avg);
      store.put(key, updated);
    }
  },
  "job-title-salary-store"
);

topology.addSink("output", "flagged-postings", flagged);
```

**Note:** The DSL approach (`KStream.aggregate()`) would struggle here because you need to emit *selectively* based on comparison logic while maintaining rolling stats—the Processor API's explicit state and punctuation control is clearer.

## Notes

- **DSL-first reflex:** Start with DSL operators. Reach for Processor API only when you can't express your logic as a chain of `map`→`filter`→`aggregate` or when state access patterns require custom windows.
- **State store lifecycle:** Processor API requires you to manually fetch state stores in `init()` and manage changelog topics; DSL handles this implicitly. Forgetting to add the store to topology dependencies is a common silent failure.
- **Punctuation vs. grace period:** Processor API uses `context.schedule()` for timer callbacks; DSL uses grace periods and suppression. They solve the same problem (late data cutoffs) but the Processor API is more explicit—useful when you need to emit alerts at exact intervals regardless of data arrival.
- **Testing and debugging:** DSL is easier to unit test (topologies are more declarative); Processor API requires `TopologyTestDriver` with manual state setup. Complex logic often warrants extracting the stateful operation into a testable helper class.
- **Adjacent skill:** Understanding `Transformer` (stateful DSL operator) bridges the gap—it's a middle ground when you need state but want to stay in DSL syntax. Always consider `Transformer` before dropping to Processor API.
