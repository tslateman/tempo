# When Estimating

Estimation answers "is this feasible?" and "which cost dominates?" before you
write code. It costs minutes and routinely saves days of optimizing the wrong
thing.

## Method

1. **Name the unit of work.** One request, one row, one file, one frame.
2. **Count the operations** in that unit: queries, round trips, allocations,
   bytes moved, comparisons.
3. **Multiply by the cost** of each operation.
4. **Find the dominant term.** Everything smaller is noise until the dominant
   term is fixed.
5. **Compare against the budget.** If the estimate exceeds the target, the
   design is wrong and no amount of tuning will save it.

Round aggressively. You are looking for the order of magnitude, not a number to
put in a report.

## Hardware costs

| Operation                          |     Cost |
| ---------------------------------- | -------: |
| L1 cache reference                 |   0.5 ns |
| L2 cache reference                 |     3 ns |
| Branch mispredict                  |     5 ns |
| Mutex lock/unlock                  |    15 ns |
| Main memory reference              |    50 ns |
| Compress 1 KB (Snappy)             | 1 000 ns |
| Read 4 KB from SSD                 |    20 us |
| Datacenter round trip              |    50 us |
| Read 1 MB sequentially from memory |    64 us |
| Read 1 MB over 100 Gbps network    |   100 us |
| Read 1 MB from SSD                 |     1 ms |
| Disk seek                          |     5 ms |
| Read 1 MB from disk                |    10 ms |
| Cross-country network round trip   |   150 ms |

Two useful ratios: memory is 100x slower than L1, and a cross-country round trip
is 3 000x a datacenter one.

## Application-level anchors

Order-of-magnitude priors for triage. Replace each with a measurement as soon as
you can take one.

| Operation                        | Order of magnitude |
| -------------------------------- | ------------------ |
| Python function call             | 50-100 ns          |
| Python attribute lookup          | 20-50 ns           |
| Dict or set lookup               | ~50 ns             |
| Simple Postgres query, same host | 0.3-1 ms           |
| ORM row to model instance        | 5-20 us per row    |
| DRF serialization, simple row    | 20-100 us per row  |
| JSON encode 100 KB               | ~1 ms              |
| Redis GET, same datacenter       | 0.2-1 ms           |
| HTTPS call to an external API    | 50-500 ms          |
| Template render, moderate page   | 1-10 ms            |
| Vue re-render, small component   | 0.1-1 ms           |

## Worked example 1 - a Django list endpoint

An endpoint returns 200 orders. Each order shows its customer name and its line
item count. The team reports 1.4 seconds and wants under 200 ms.

Count the operations in the current implementation:

```
1 query for the order page                          1 x 0.5 ms =   0.5 ms
1 query per order for customer (FK in template)   200 x 0.5 ms = 100.0 ms
1 query per order for line items (.count())       200 x 0.5 ms = 100.0 ms
model instantiation                          200 x ~15 us       =   3.0 ms
serialization                                200 x ~60 us       =  12.0 ms
```

The estimate is about 215 ms of database round trips against roughly 15 ms of
CPU. The measured 1.4 s exceeds this, which is itself a finding: either the
queries are slower than 0.5 ms, or something outside this count dominates. That
gap is the first thing to measure, not to guess at.

The estimate already tells you the shape of the fix. Query count, not
serialization, is the term to attack:

```
1 query, joined + annotated                         1 x 2 ms   =   2.0 ms
model instantiation                          200 x ~15 us      =   3.0 ms
serialization                                200 x ~60 us      =  12.0 ms
```

About 17 ms. Comfortably inside the 200 ms budget, so there is no reason to
touch serialization. Stop.

The lesson is not "fix N+1"; it is that the estimate identified the dominant
term and told you when to stop.

## Worked example 2 - a nightly reconciliation job

Reconcile 5 million transaction records against a remote ledger API. The job
must finish inside a 4 hour window.

The naive design calls the API once per record:

```
5 000 000 x 100 ms = 500 000 s = 139 hours
```

Infeasible by two orders of magnitude. No tuning fixes this; the design is
wrong. Estimation caught it before anyone wrote the retry logic.

With a batch endpoint taking 500 records per call, run 20 in parallel:

```
5 000 000 / 500 = 10 000 calls
10 000 x 200 ms / 20 concurrent = 100 s
```

Now the API is no longer the dominant term, so re-estimate what is:

```
read 5M rows from Postgres, .iterator(), ~5 KB each = 25 GB
25 GB over a 1 Gbps link                            ~200 s
parse and compare, ~10 us per row                   5M x 10 us = 50 s
```

Data transfer now dominates. The next move is `.values()` to fetch only the four
fields the comparison needs, cutting 5 KB per row to roughly 200 bytes and the
transfer to about 8 s.

The dominant term moved twice. Re-estimate after every fix.

Had the job also written a row back per record, that write would have dwarfed
everything else before any of this mattered:

```
10 000 000 UPDATEs, one per row      10M x ~0.55 ms  = ~90 min
10 000 batched statements, 1000 each 10k x ~10 ms    = ~100 s
```

Per-item round trips dwarfing all other terms is the standard shape of a batch
job problem. Check the write pattern first.

## Worked example 3 - the classic CPU case

Sorting 10^9 four-byte integers. The obvious cost source is memory bandwidth:
4 GB moved several times over predicts roughly 7.5 s.

That is not the dominant term. Comparison sorting mispredicts branches, and
about 30 levels of quicksort with a mispredict every other comparison costs
around 75 s. Total estimate: roughly 82.5 s, dominated by mispredicts rather
than by the bandwidth everyone thinks of first.

The lesson generalizes past CPU work: enumerate every cost source, not just the
obvious one. In web work the overlooked term is usually round-trip count; in
batch jobs it is usually the write pattern.

## When the estimate and the measurement disagree

The measurement is right. The estimate is a model, and a model that contradicts
reality is missing a term. Find the missing term before proceeding:

- An operation you did not count. Middleware, a signal handler, an authorization
  check per object, a lazy field forcing a query.
- A cost different from your prior. The query is 20 ms, not 0.5 ms, because it
  scans.
- Contention. The number is fine in isolation and terrible under concurrency.
- Cold cache, cold connection pool, cold JIT.

A corrected estimate is worth more than the original was. Update the prior.

## Estimation as a design gate

Run the estimate before writing the code, not after. The questions it answers
early are the ones that are expensive to answer late:

- Can this endpoint meet its latency budget at 10x the current data volume?
- Does this job fit its window?
- Is a cache worth it? Estimate hit rate times saved cost against added
  complexity and staleness risk.
- Does this need a queue, or is it fast enough inline?

---

Source: Jeff Dean and Sanjay Ghemawat, "Performance Hints",
https://abseil.io/fast/hints.html. Estimation technique: https://abseil.io/fast/90.
