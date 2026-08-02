# When Debugging Performance

Find the real problem before fixing. A fix that does not address the actual cause adds complexity and leaves the slowness in place. The sequence is always: reproduce, measure, locate, then fix.

## First moves

1. **Reproduce with realistic data.** Slowness that vanishes with a 10-row fixture is a data-size problem - which is itself the clue (look for O(N^2), N+1, unindexed scans).
2. **Establish the boundary.** Is the time in CPU, database, network, or disk? A py-spy profile with `--idle`, or comparing wall time to CPU time, answers this in one measurement. Optimizing CPU when 95% of wall time is awaiting the database wastes effort.
3. **Get one number.** Total wall time for the operation, before touching anything. Every hypothesis gets tested against it.

## Web request checklist (in order of likelihood)

1. Query count - N+1s dominate slow Django views; Debug Toolbar or `assertNumQueries`
2. Individual slow queries - `EXPLAIN ANALYZE`; missing or wrong-order composite indexes
3. Serialization and template rendering - full model hydration where `.values()` suffices, nested serializers fanning out
4. External calls - sequential awaits, per-request clients, missing timeouts
5. Payload size - returning megabytes to render a table

## Flat-profile playbook

When the profile shows no hotspot - time smeared a few percent everywhere - do not micro-optimize the leaves. Instead:

- **Look up the stack.** A cheap function called 10 million times is a caller problem. Find the loop higher in the call stack and ask why it iterates so often, or whether work can hoist above it.
- **Check allocation patterns.** Dispersed allocation cost shows up as "everything is slightly slow" because every cache miss pays. Profile allocations (tracemalloc, memray) separately from CPU.
- **Find overly general code.** Regex where a prefix match suffices, generic serializers building intermediate dicts, datetime parsing where ISO-8601 strings compare correctly as strings, deep-copy where a reference is safe. General code on a hot path is a specialization opportunity - the source material cites 4x from replacing sprintf-style formatting with custom code.
- **Add up the small taxes.** Logging (which costs a load and compare per call site even when disabled - hoist the enabled-check out of loops), stats counters, locks taken per item instead of per batch. The source material cites 8-10% from hoisting log-level checks and 62% from sampling stats. Treat those as priors, not predictions.

## Avoiding unnecessary work (the usual fixes)

- **Fast path** for the common case: check the cheap, frequent case first and return early
- **Precompute** what does not change per call: move it to import time, a class attribute, or a migration
- **Defer** what is rarely used: compute lazily on first access (the source cites a 43 s to 2 s win from deferral)
- **Cache** repeated pure computation: functools.lru_cache, computed keys on model save, memoized computed properties in Vue

## Verify the fix

Re-run the same measurement from step 3 of First moves. If the number did not move, the hypothesis was wrong - revert and re-locate rather than stacking speculative fixes.

## Sources

- Performance Hints (profiling, avoiding work sections): https://abseil.io/fast/hints.html
