---
name: performance-hints
description: This skill should be used when the user asks to "optimize code", "make this faster", "reduce allocations", "improve performance", "speed up", "reduce latency", "why is this slow", "profile this", "benchmark this", "fix this N+1", or mentions performance, latency, throughput, memory usage, profiling, or benchmarking. Do not use for general code review, testing, or API design requests that lack a performance angle.
---

# Performance Hints

Distilled performance engineering from Jeff Dean and Sanjay Ghemawat's Performance Hints (abseil.io), translated to Python/Django and TypeScript/Vue.

## Philosophy

Knuth's "premature optimization is the root of all evil" continues: "Yet we should not pass up our opportunities in that critical 3%." Choose faster alternatives during development when they do not hurt readability, especially in library code, where your performance problem becomes every caller's problem.

Why "optimize later" fails:

1. **Flat profile problem** - inefficiency spreads everywhere; no single hotspot remains to fix later
2. **Library users suffer** - downstream callers cannot fix your slow code
3. **Heavy use constrains change** - production systems resist significant change
4. **Expensive workarounds** - teams overprovision hardware instead of fixing solvable problems

And small wins compound: "In established engineering disciplines a 12% improvement, easily obtained, is never considered marginal" (Knuth).

## Method

Estimate first, then measure, then fix the real problem, then measure again. Find the actual cause before changing code. The most concise solution is often the fastest because it avoids overhead - compare ISO-8601 dates as strings instead of parsing them into objects.

## Reference routing

| Task                                          | Reference file                         |
| --------------------------------------------- | -------------------------------------- |
| Back-of-envelope, estimation, latency budgets | `references/when-estimating.md`        |
| Profiling, benchmarking, measurement          | `references/when-measuring.md`         |
| Memory, allocations, data representation      | `references/when-optimizing-memory.md` |
| "Why is this slow?", flat profiles            | `references/when-debugging-perf.md`    |
| API and interface design for performance      | `references/when-designing-apis.md`    |
| Reviewing an optimization                     | `references/when-reviewing-perf.md`    |

## Latency quick reference

L1 cache 0.5 ns / main memory 50 ns / datacenter round trip 50 us / read 1MB from memory 64 us / read 1MB from SSD 1 ms / disk seek 5 ms / cross-country round trip 150 ms

## Common bottlenecks in this stack

| Issue                 | Pattern                                     | Fix                                          |
| --------------------- | ------------------------------------------- | -------------------------------------------- |
| Django N+1            | Related-object access in loops              | select_related / prefetch_related            |
| Sequential I/O        | `for` + `await`, chained awaits             | asyncio.gather / Promise.all                 |
| Item-at-a-time writes | `.save()` or `.create()` in loops           | bulk_create / bulk_update                    |
| Client per request    | HTTP client built per call                  | Shared client with connection pool           |
| Hot-loop allocations  | Objects, dicts, `+=` strings in loops       | Hoist, pre-size, `"".join`                   |
| Missing index         | filter/order_by on unindexed fields         | Add index matching the query shape           |
| Vue over-reactivity   | Deep watchers, keyless v-for on large lists | Shallow refs, keyed lists, memoized computed |

For the full workflow with analysis and validation agents, use the `/perf` command.

## Sources

Performance Hints by Jeff Dean and Sanjay Ghemawat: https://abseil.io/fast/hints.html and the Fast Tips series: https://abseil.io/fast/
