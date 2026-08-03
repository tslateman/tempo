---
name: performance-hints
description: Estimate-first performance engineering from Jeff Dean and Sanjay Ghemawat's Abseil performance hints, applied to Python/Django, TypeScript/Node, and Vue. Use when the user asks to make something faster, optimize a slow endpoint or job, reduce latency or memory, fix an N+1, cut allocations, profile or benchmark code, size a performance budget, or asks why something is slow. Do not use for general code review, testing, or API design requests that lack a performance angle.
---

# Performance Hints

Estimate the cost before you write the code. Measure the result before you call
it done.

## Philosophy

> "In established engineering disciplines a 12% improvement, easily obtained, is
> never considered marginal." - Donald Knuth

Knuth's line about premature optimization is usually quoted with its ending cut
off. The full passage continues: "Yet we should not pass up our opportunities in
that critical 3%." Choose the faster alternative during development when it does
not cost readability. This matters most in library code, where your performance
problem becomes every caller's performance problem.

### Why "optimize later" fails

1. **Flat profile.** Cost distributed everywhere leaves no hotspot to find
   later.
2. **Callers suffer.** Downstream users cannot fix your slow code.
3. **Wide use freezes design.** Once a system is in production, the changes that
   would fix it are the ones nobody will risk.
4. **Expensive workarounds.** Teams buy hardware instead of fixing a solvable
   problem.

### The order that works

1. Estimate. Count operations, multiply by known costs, find the dominant term.
2. Measure. Confirm the estimate against reality before changing anything.
3. Diagnose. A profile shows where time goes, not what to fix. Find the real
   cause.
4. Fix the dominant term. Everything else is noise until it is the largest term.
5. Measure again. Compare against the baseline you captured.

## Routing

| Task                                           | Reference                              |
| ---------------------------------------------- | -------------------------------------- |
| Back-of-envelope, latency budget, feasibility  | `references/when-estimating.md`        |
| Profilers, benchmarks, avoiding fake results   | `references/when-measuring.md`         |
| Allocations, memory layout, GC, large datasets | `references/when-optimizing-memory.md` |
| "Why is this slow?", flat profile, no hotspot  | `references/when-debugging-perf.md`    |
| Bulk endpoints, pagination, sync/async surface | `references/when-designing-apis.md`    |
| Validating an optimization, review checklist   | `references/when-reviewing-perf.md`    |

## Latency numbers

| Operation                          |   Cost |
| ---------------------------------- | -----: |
| L1 cache reference                 | 0.5 ns |
| Branch mispredict                  |   5 ns |
| Mutex lock/unlock                  |  15 ns |
| Main memory reference              |  50 ns |
| Datacenter round trip              |  50 us |
| Read 1 MB sequentially from memory |  64 us |
| Read 1 MB from SSD                 |   1 ms |
| Disk seek                          |   5 ms |
| Read 1 MB from disk                |  10 ms |
| Cross-country round trip           | 150 ms |

Full table with worked examples: `references/when-estimating.md`.

## Common bottlenecks

| Symptom                        | Pattern                                      | Fix                                           |
| ------------------------------ | -------------------------------------------- | --------------------------------------------- |
| Query count scales with rows   | FK or related manager accessed in a loop     | `select_related` / `prefetch_related`         |
| Slow bulk write                | `.save()` inside a loop                      | `bulk_create` / `bulk_update`                 |
| Slow lookup loop               | `.get(pk=...)` inside a loop                 | `in_bulk` / `filter(id__in=...)`              |
| Latency adds up                | `await` inside a loop, independent calls     | `asyncio.gather` / `Promise.all`              |
| Steady per-call overhead       | HTTP client constructed per request          | one shared client with a lifecycle            |
| Event loop stalls              | blocking call inside `async def`             | async client, or `sync_to_async`              |
| Memory grows with table size   | full queryset materialized                   | `.iterator()`, pagination, `.values()`        |
| Everything slightly slow       | allocation churn in a loop                   | hoist, reuse, pre-size, generators            |
| Quadratic time                 | `+=` on strings, `in` against a list         | `"".join`, set membership                     |
| Frontend jank on data change   | deep watcher or work inside `computed`       | `shallowRef`, precompute, virtualize          |
| Repeated identical computation | pure function called with the same arguments | memoize with a bounded cache and invalidation |

## Rules of thumb

- The most concise solution is often the fastest, because it avoids the
  overhead. When the data format already matches the comparison semantics -
  ISO-8601 dates sort lexicographically - compare in the native format rather
  than parsing to objects and back.
- A saving on cold code is not a saving.
- Fix the cause, not the symptom.
- Query counts and allocation counts are measurements. Wall-clock time on a
  laptop is a rumor.
- Twenty 1% improvements compound. Report them together.

## Full workflow

For the complete seven-phase workflow with parallel analysis agents, hard
approval gates, and measured validation, run `/perf [target]`.

## Sources

Jeff Dean and Sanjay Ghemawat, "Performance Hints"
(https://abseil.io/fast/hints.html) and the Abseil Fast Tips series
(https://abseil.io/fast/).
