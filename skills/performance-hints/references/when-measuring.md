# When Measuring

A profile shows where time goes. It does not tell you what to fix. Measurement
narrows the search; diagnosis still requires reading the code.

Measure before you change anything, and again after. Without a baseline captured
the same way, the second number means nothing.

## Choose the right instrument

| Question                           | Instrument                                               |
| ---------------------------------- | -------------------------------------------------------- |
| Where does wall-clock time go?     | sampling profiler (`py-spy`, Chrome DevTools)            |
| Which functions dominate CPU?      | `cProfile`, `--cpu-prof`                                 |
| How many queries, and which?       | `assertNumQueries`, django-silk, `CaptureQueriesContext` |
| Why is this query slow?            | `EXPLAIN (ANALYZE, BUFFERS)`                             |
| Where does memory go?              | `tracemalloc`, `memray`, heap snapshot                   |
| Is this function faster than that? | `pytest-benchmark`, `timeit`, `tinybench`                |
| Where does the request wait?       | distributed tracing, OpenTelemetry spans                 |
| Why does the page feel slow?       | DevTools Performance panel, Lighthouse                   |
| Which lines inside a hot function? | `line_profiler`                                          |
| Is this whole command faster?      | `hyperfine`, which reports a distribution                |
| How do I read this profile?        | `snakeviz` over a `cProfile` dump                        |
| Is time spent waiting, not on CPU? | `py-spy --idle`, or wall-clock time minus CPU time       |

Prefer counts to timings whenever a count is available. Query count, allocation
count, and payload size are deterministic. Wall-clock time on a developer laptop
is noise with a trend in it.

## Python and Django

**Sampling profile of a live process.** Attaches without restarting, low
overhead, safe against production if you are careful:

```
py-spy top --pid 12345
py-spy record --pid 12345 --duration 30 --output profile.svg
```

**Deterministic profile of a specific path.** High overhead, distorts short
calls, but exact about call counts:

```python
import cProfile, pstats

profiler = cProfile.Profile()
profiler.enable()
run_the_thing()
profiler.disable()
pstats.Stats(profiler).sort_stats("cumulative").print_stats(30)
```

Sort by `cumulative` to find the expensive subtree, by `tottime` to find the
expensive function itself.

**Query count as a regression test.** The most valuable performance test Django
offers, because it is exact and fails loudly:

```python
def test_order_list_query_count(self):
    with self.assertNumQueries(3):
        self.client.get("/api/orders/")
```

An N+1 that returns will fail this test. A wall-clock assertion would not.

**Inspecting the queries themselves:**

```python
from django.test.utils import CaptureQueriesContext
from django.db import connection

with CaptureQueriesContext(connection) as ctx:
    run_the_view()
for query in ctx.captured_queries:
    print(query["time"], query["sql"][:120])
```

`django-silk` gives the same view per request in a running server, with a
profile per request. `django-debug-toolbar` is fine for interactive work and
misleading for measurement, since it adds its own overhead.

**Query plans.** A slow query is a different problem from too many queries.
`str(queryset.query)` gives the SQL; run it under `EXPLAIN (ANALYZE, BUFFERS)`.
Look for `Seq Scan` on a large table, a row estimate far from the actual count,
and sorts spilling to disk.

**Microbenchmarks:**

```python
def test_parse_speed(benchmark):
    result = benchmark(parse_payload, SAMPLE)
    assert result.count == 100
```

`pytest-benchmark` reports min, mean, and standard deviation, and compares
against saved runs with `--benchmark-compare`.

## TypeScript, Node, and the browser

**Node CPU profile:**

```
node --cpu-prof --cpu-prof-dir=./profiles dist/job.js
```

Load the `.cpuprofile` in Chrome DevTools. `clinic doctor` and `clinic flame`
wrap this with better defaults and detect event-loop blocking.

**Event loop lag** is the measurement that matters most for a Node server. A
handler that blocks for 200 ms adds 200 ms to every concurrent request, and no
CPU profile of a single request will show that.

**Browser.** The DevTools Performance panel records a real interaction. Read it
in this order: long tasks first, then scripting versus rendering versus
painting, then the flame chart. Vue DevTools adds a component render timeline
that attributes a re-render to the state change that caused it.

For a targeted measurement in application code:

```ts
performance.mark("render-start");
renderTable(rows);
performance.mark("render-end");
performance.measure("render", "render-start", "render-end");
```

## How microbenchmarks lie

Every one of these produces a confident, wrong number.

- **Dead code elimination.** The compiler or interpreter removes work whose
  result is unused. Consume the result: assert on it, accumulate it, return it.
- **Constant folding.** A benchmark with a literal input may be computed once.
  Vary the input, or read it from outside the timed region.
- **Unrealistic cache warmth.** The same small input on every iteration lives in
  L1. Production data does not. Use an input set larger than cache, and iterate
  over it in an order production would produce.
- **Setup inside the timed region.** Measuring the fixture, not the function.
- **Cold start counted once.** Import time, JIT warmup, and connection setup
  land in the first iteration and distort a short run.
- **One run reported as a result.** Report a distribution. If the difference is
  smaller than the run-to-run spread, there is no difference.
- **Noise from the machine.** Thermal throttling, other processes, and CPU
  frequency scaling move numbers by tens of percent. Compare arms interleaved
  rather than sequentially.
- **The wrong scale.** A function that wins at n=10 can lose at n=100 000.
  Benchmark at production scale, and at 10x it if the data grows.
- **Missing warmup on a JIT runtime.** V8 and PyPy need warmup iterations before
  steady state. Measuring cold includes compilation time. Decide which one you
  care about, then measure that one deliberately.
- **Isolated measurement of a contended resource.** A lock, a connection pool,
  or a shared client behaves differently with one caller than with fifty.
- **Missing symbols.** Compiled extensions without debug info and minified
  frontend code without sourcemaps produce profiles that do not map to source.
  Build with optimizations on and symbols available.

## Django measurement recipe

For a slow endpoint, in this order. Most slow views never get past step 1.

1. **Query count and duplicates** via `assertNumQueries` or the Debug Toolbar
   SQL panel. N+1s dominate.
2. **Per-query time** via `connection.queries` or silk. Run
   `EXPLAIN (ANALYZE, BUFFERS)` on anything over a few milliseconds.
3. **Python profile** with py-spy, for serialization and template time. Only
   reach for this once steps 1 and 2 are clean.

## Interpreting a profile

- **Cumulative time** finds the expensive subtree. **Self time** finds the
  expensive function. You need both; they answer different questions.
- **A flat profile means the cost is distributed.** See
  `when-debugging-perf.md`.
- **I/O wait does not appear in a CPU profile.** A request that spends 400 ms
  waiting on Postgres looks idle. Use tracing or wall-clock sampling.
- **Lock contention needs its own measurement.** Contended time is neither CPU
  nor I/O.
- **Inlined and native frames hide.** Time attributed to a C extension or a
  framework internal usually belongs to your call pattern, not to that code.

## Make the measurement permanent

A performance fix without a test regresses. Choose the cheapest instrument that
would catch the regression:

- `assertNumQueries` around the endpoint that had the N+1.
- A `pytest-benchmark` case with a threshold for a hot pure function.
- A payload-size assertion for a response that grew.
- A bundle-size budget in CI for a frontend import.

Record the baseline number and the machine or CI runner it came from. A
threshold without a recorded baseline gets raised the first time it fails.

---

Sources: https://abseil.io/fast/39 (benchmark pitfalls),
https://abseil.io/fast/75 (microbenchmark design),
https://abseil.io/fast/hints.html.
