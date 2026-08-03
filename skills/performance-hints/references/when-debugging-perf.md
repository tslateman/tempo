# When Debugging Performance

The question is not "how do I make this faster?" It is "what is actually taking
the time?" Those have different answers more often than not, and a fix aimed at
the wrong one is churn.

## Find the real problem first

A fix that does not address the actual cause is a permanent maintenance cost
with no payoff. Before changing anything, confirm all four:

1. **The symptom is real and reproducible.** One slow request may be a cold
   cache, a noisy neighbour, or a garbage collection pause.
2. **The measurement matches the complaint.** Users report page load; you
   measured the API handler. The gap may be the whole problem.
3. **The suspected cause is on the path.** Confirm by reading the code, not by
   pattern-matching a profile line.
4. **The magnitude fits.** If the suspect accounts for 12 ms of a 900 ms
   request, it is not the cause however wrong it looks.

The most expensive failure mode in performance work is fixing something real,
shipping it, and finding the number unchanged.

## Establish the boundary first

Before anything else, find out whether the time is CPU, database, network, or
disk. A `py-spy` profile with `--idle`, or wall-clock time compared against CPU
time, answers this in one measurement. Optimizing CPU when 95% of wall time
waits on the database wastes the whole effort.

Then get one number: total wall time for the operation, before touching
anything. Every hypothesis gets tested against it.

## Web request checklist, in order of likelihood

1. **Query count.** N+1s dominate slow Django views. `assertNumQueries` or the
   Debug Toolbar.
2. **Individual slow queries.** `EXPLAIN (ANALYZE, BUFFERS)`; missing indexes or
   a composite index in the wrong column order.
3. **Serialization and template rendering.** Full model hydration where
   `.values()` suffices; nested serializers fanning out.
4. **External calls.** Sequential awaits, per-request clients, missing timeouts.
5. **Payload size.** Returning megabytes to render a table.

## Narrow before you profile

Bisect the request rather than reading the whole profile at once:

- Time the layers: total, minus the view, minus the queries, minus
  serialization. The layer where the number collapses is your target.
- Compare against a variant. A fast endpoint next to the slow one; the same
  endpoint with a smaller page size; the same job on a tenth of the data.
- Scale the input. If time grows linearly with rows, it is per-row work. If it
  grows quadratically, look for a nested loop or a membership test against a
  list. If it is flat, it is fixed overhead and the row count is a red herring.
- Check the trivial explanations first: a missing index, a cache turned off in
  this environment, DEBUG left on, a proxy adding a round trip, a retry loop
  succeeding on the second attempt.

## The flat profile

No function exceeds a few percent. Nothing to fix, apparently. Cost is
distributed, and the answer is above the leaves rather than inside them.

Work through these in order:

**Look up the call stack for the loop.** The leaf is cheap and runs 40 000
times. Sort by cumulative time, not self time, and find the outermost frame
whose count is unexpectedly large. The fix is usually to call it less, not to
make it faster.

**Count calls, not time.** A deterministic profile gives call counts. A function
called once per row of a 50 000-row result is a design problem regardless of how
fast it is.

**Look at allocation instead of CPU.** Object churn shows nothing in a CPU
profile except a slight tax spread across everything, plus garbage collection
pauses that appear unrelated to the work.

**Suspect generality.** A serializer handling every case for a three-field
response, a regex where `startswith` suffices, a generic dispatch layer on a
path that only ever takes one branch. General code on a specific hot path is
Abseil's canonical flat-profile cause.

**Count the layers.** Each abstraction costs a small constant. Ten of them cost
a large one, and none of them will appear as a hotspot.

**Suspect instrumentation.** Logging, metrics, and tracing emitted per item.
Logging costs even when disabled, because the level check runs at every call
site and the arguments may be built first. Hoist the enabled check out of the
loop and sample high-frequency metrics rather than emitting them all.

**Add up the small wins.** Twenty 1% improvements compound to about 18%.
Evaluate them as a group with a combined estimate; individually each looks not
worth doing.

## When the profile says I/O

A CPU profile shows a request that waits on Postgres for 400 ms as idle. If
wall-clock time greatly exceeds CPU time, stop reading the CPU profile.

- Count the queries. The number scaling with result size is an N+1.
- Time the individual queries. One slow query is a plan problem: run
  `EXPLAIN (ANALYZE, BUFFERS)` and look for a sequential scan on a large table
  or a bad row estimate.
- Count external calls and check whether they are sequential. Independent awaits
  in a loop add latency that should have overlapped.
- Check connection setup. A client constructed per request pays a TLS handshake
  every time.

## When it is only slow in production

The difference is the finding. Enumerate what differs:

- **Data volume.** A query that is instant on 1 000 development rows scans 10
  million in production. Load representative data before concluding anything.
- **Concurrency.** Lock contention, connection pool exhaustion, and event-loop
  blocking are invisible with one user.
- **Network topology.** A database on another host turns a 0.05 ms call into 0.5
  ms, and an N+1 from a nuisance into an outage.
- **Cold caches.** Development runs warm. Production has evictions and deploys.
- **Configuration.** `CONN_MAX_AGE`, worker counts, gzip, CDN, debug flags.

When you cannot reproduce it locally, measure it where it happens: a sampling
profiler attached to a live process, tracing spans, or query logging over a
sample of requests.

## Avoiding unnecessary work: the usual fixes

Once you know the dominant term, these are the four moves that remove work
rather than speeding it up. Removing work beats optimizing it.

- **Fast path.** Handle the common case first with minimal code and return
  early. Keep the slow path in a separate function so it does not weigh down the
  common one.
- **Precompute.** Move what does not change per call to import time, a class
  attribute, a denormalized column, or a migration.
- **Defer.** Compute lazily on first access when the value is rarely needed. The
  source material cites one case going from 43 s to 2 s of CPU on deferral
  alone.
- **Cache.** Memoize repeated pure computation: `functools.lru_cache`, a
  computed key written on model save, a memoized computed property in Vue.
  Caching brings an invalidation obligation; take it on deliberately.

The source material also cites 8-10% from hoisting log-level checks out of loops
and 62% from sampling stats rather than emitting them all. Treat every figure in
this section as a prior for ranking candidates, not as a prediction for your
case.

## Prefer the concise form

When the data format already carries the comparison semantics, use it directly.
ISO-8601 dates sort lexicographically, so string comparison gives the same
answer as parsing to `datetime` and comparing:

```python
recent = [row for row in rows if row["created_at"] >= cutoff_iso]
```

That is shorter than the parsing version and avoids constructing an object per
row purely to throw it away. This generalizes: parse-compare-format round trips,
serializing to compare, and converting a type only to convert it back are all
work performed to reach a conclusion the original representation already
supported.

The concise solution being the fast one is common enough to be a useful signal.
When an optimization makes the code longer, ask whether you are working around a
representation choice made earlier.

## Rules

- Reproduce before diagnosing. Diagnose before fixing. Measure after fixing.
- One change at a time. Two changes measured together tell you nothing about
  either.
- Re-estimate after every fix. The dominant term moves, and the next one is
  frequently somewhere you had ruled out.
- When the number does not improve, revert. A change that did not help is not
  neutral; it is complexity you now maintain.

---

Source: Jeff Dean and Sanjay Ghemawat, "Performance Hints", flat profile and
measurement sections, https://abseil.io/fast/hints.html.
