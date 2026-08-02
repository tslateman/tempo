# When Measuring

Profiles show where time goes, not what to fix. Measure before optimizing to find the real problem, and after to prove the fix. An optimization without a before-and-after number is a hypothesis.

## Tool selection

| Context                 | Tool                                   | Use for                                             |
| ----------------------- | -------------------------------------- | --------------------------------------------------- |
| Python, production-ish  | py-spy (`py-spy top`, `py-spy record`) | Sampling profile of a live process, no code changes |
| Python, deterministic   | cProfile + snakeviz                    | Call counts and cumulative time per function        |
| Python, line-level      | line_profiler                          | Hot lines inside a known-hot function               |
| Python, microbenchmark  | pytest-benchmark, timeit               | Comparing two implementations, regression gates     |
| Django, development     | Debug Toolbar (SQL panel)              | Query count, duplicate queries, per-query time      |
| Django, request tracing | django-silk                            | Profiles and SQL across many real requests          |
| Django, tests           | assertNumQueries, connection.queries   | Locking in query counts so N+1 cannot return        |
| Node/TS                 | `node --prof`, `--cpu-prof`, clinic.js | V8 CPU profiles of server code                      |
| Browser/Vue             | Chrome DevTools Performance panel      | Long tasks, layout thrash, component render cost    |
| CLI comparison          | hyperfine                              | Whole-command before-and-after with statistics      |

Build/run with optimizations on and debug info available so profiles map to source (for compiled extensions and minified frontend code, keep symbols/sourcemaps).

## Methodology

- Profile the workload you care about, at realistic data sizes. A 10-row fixture hides every O(N^2).
- Profile CPU and off-CPU separately: py-spy's `--idle` and Django's SQL panels catch time spent waiting that a CPU profile never shows.
- Change one thing, measure, repeat. Two fixes measured together cannot be attributed.
- Keep a benchmark or query-count assertion for every fix, so regressions surface in CI rather than production.

## Microbenchmark pitfalls

Microbenchmarks lie by default. The main failure modes:

1. **Dead-code elimination.** Optimizers (V8 especially, PyPy, C extensions) delete computations whose results are unused. A loop that computes and discards can benchmark as free. Consume the result: accumulate it, return it, or assert on it.
2. **Unrealistic cache warmth.** A tight loop over one small input keeps everything in L1 and branch predictors trained - production traffic will not. Benchmark with data sized and shuffled like production.
3. **Statistical noise.** Single runs mislead: CPU frequency scaling, thermal throttling, other processes, GC pauses. Use tools that report distributions (pytest-benchmark, hyperfine), run enough iterations, and compare medians, not single runs. Treat differences within the noise band as no difference.
4. **Missing warmup.** JIT runtimes (V8, PyPy) need warmup iterations before steady state; measuring cold includes compilation time you may or may not care about. Decide which one you are measuring, then measure that.
5. **Benchmarking the harness.** Setup inside the timed region (building the test data, opening connections) swamps small effects. Time only the operation under test.

## Django measurement recipe

For a slow endpoint, in order:

1. Query count and duplicates via Debug Toolbar or `assertNumQueries` - most slow views are N+1s
2. Per-query time via `connection.queries` or silk; `EXPLAIN ANALYZE` anything over a few ms
3. Only then a Python profile (py-spy) for serialization and template time

## Sources

- Performance Hints (measurement section): https://abseil.io/fast/hints.html
- Microbenchmark pitfalls: https://abseil.io/fast/39 and https://abseil.io/fast/75
