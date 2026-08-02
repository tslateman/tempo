# When Reviewing a Performance Change

Correctness first: an optimization that breaks behavior is worse than slow code. Then interrogate the performance claim itself - many optimizations optimize a path that was never hot.

## Correctness checklist

- Same outputs for same inputs, including empty, single-element, maximum-size, unicode, and timezone cases
- Error handling intact: exceptions still surface; partial failures in batches are accounted for
- Concurrency: caching, pooling, and parallelism introduce shared state - who synchronizes it?
- Resource cleanup on all paths: clients closed, tasks awaited, files released

## Common optimization bugs

| Optimization          | Common bug          | What to check                           |
| --------------------- | ------------------- | --------------------------------------- |
| Parallel I/O          | Lost error handling | try/except around the gathered tasks    |
| Shared clients        | Connection leaks    | Shutdown cleanup, timeouts configured   |
| Pre-sized collections | Off-by-one          | The size calculation                    |
| Caching               | Stale data          | An invalidation strategy exists         |
| Deferred computation  | Never computed      | The lazy value is actually awaited/read |
| Bulk operations       | Partial failures    | Rollback or per-item error reporting    |

## Stack-specific bugs

| Optimization              | Common bug                                                            | What to check                                                                       |
| ------------------------- | --------------------------------------------------------------------- | ----------------------------------------------------------------------------------- |
| asyncio.gather            | First exception cancels siblings, or errors vanish                    | return_exceptions choice matches intended semantics                                 |
| Django cache              | Write path skips invalidation                                         | Every mutation of the cached data invalidates                                       |
| prefetch_related          | Later .filter() on the related manager silently discards the prefetch | No .filter()/.exclude() on prefetched relations; use Prefetch(queryset=...) instead |
| Promise.all               | Fail-fast aborts in-flight siblings                                   | Whether allSettled was the intended semantics                                       |
| Module-level shared state | Mutation races under ASGI workers/threads                             | Module dicts or lists mutated per request                                           |
| bulk_create/bulk_update   | Bypasses save() overrides and signals                                 | Whether signals or save() carried business logic                                    |

## Interrogating the claim

1. **Is it a hot path?** Init code and admin-only paths rarely justify complexity
2. **Is the size plausible?** Check the claimed saving against the latency table; a fix "saving" more time than the operation ever took is misattributed
3. **Hidden costs?** Extra memory, cache pressure, lock contention, added dependency, complexity tax on every future reader
4. **Under load?** Caches can thrash, pools can exhaust, batch sizes can exceed limits - the benchmark ran once, production runs concurrently
5. **Was it measured?** Before-and-after numbers, on realistic data, with noise accounted for (see when-measuring.md). Unmeasured wins are unverified claims - say so in the review

## Maintainability

- The optimized code should state its constraint where the code cannot show it ("hot path: called per row, avoid allocation")
- If the measured win is small and the complexity large, recommend reverting - a 2% win rarely pays for opaque code outside a proven-hot library

## Verdict form

Change summary, correctness PASS/FAIL, claim vs evidence, issues by severity with file:line, then APPROVE / APPROVE WITH CHANGES / REJECT.

## Sources

- Performance Hints: https://abseil.io/fast/hints.html
