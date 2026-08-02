# When Estimating

Estimate feasibility before implementing: count the operations, multiply by known costs, compare against the budget. Estimation reveals which cost dominates before you write code, and tells you afterward whether a measurement is believable.

## Method

1. State the budget (e.g. 200 ms per request, 5 minutes per batch job)
2. List the operations on the hot path
3. Multiply each by its unit cost from the table below
4. Sum, compare to budget, and identify the dominant term
5. Only the dominant term is worth optimizing

## Latency numbers

```
L1 cache reference                             0.5 ns
L2 cache reference                               3 ns
Branch mispredict                                5 ns
Mutex lock/unlock                               15 ns
Main memory reference                           50 ns
Compress 1K bytes (Snappy)                   1,000 ns
Read 4KB from SSD                           20,000 ns   (20 us)
Datacenter round trip                       50,000 ns   (50 us)
Read 1MB sequentially from memory           64,000 ns   (64 us)
Read 1MB over 100 Gbps network             100,000 ns  (100 us)
Read 1MB from SSD                        1,000,000 ns    (1 ms)
Disk seek                                5,000,000 ns    (5 ms)
Read 1MB from disk                      10,000,000 ns   (10 ms)
Cross-country network round trip       150,000,000 ns  (150 ms)
```

Rules of thumb for interpreted stacks: a Python bytecode operation costs tens of nanoseconds; a simple Python function call ~100 ns; a dict lookup ~50 ns; constructing a small object hundreds of ns. I/O costs are language-independent, which is why round trips dominate most web workloads.

## Worked example: Django request budget

Budget: 200 ms for a list endpoint returning 50 orders with customer names.

Naive implementation: one query for orders, then `order.customer.name` in the serializer - an N+1.

```
1 query (orders)         : 1 round trip + execution   ~ 1 ms
50 queries (customers)   : 50 x (0.05 ms RT + ~0.5 ms execution) ~ 27 ms
Serialization of 50 rows : 50 x ~10 us                ~ 0.5 ms
```

28 ms fits the budget - until the page size grows to 500, when queries alone cost ~275 ms and blow it. The fix (select_related) makes cost grow with rows fetched, not queries issued:

```
1 query with join        : 1 round trip + ~3 ms execution ~ 3 ms
Serialization of 500 rows: ~5 ms
```

The estimate shows the naive version fails at scale before you ship it, and tells you the fixed version has ~25x headroom.

## Worked example: data-processing job

Task: nightly job reads 10 million rows (2 GB) from Postgres, computes an aggregate per row, writes 10 million rows back.

```
Read 2 GB over network    : 2,000 x 100 us/MB          ~ 0.2 s (wire time)
Row hydration in Python   : 10^7 x ~2 us/row           ~ 20 s
Per-row computation       : 10^7 x ~1 us               ~ 10 s
Write, one UPDATE per row : 10^7 x ~0.55 ms (RT + exec) ~ 90 min
Write, batched 1000/stmt  : 10^4 x ~10 ms              ~ 100 s
```

The dominant term is the write pattern, by two orders of magnitude. No amount of tuning the computation matters until writes are batched (bulk_update, COPY, or executemany). This is the shape of most batch-job problems: per-item round trips dwarf everything else.

## The classic CPU example

Sorting 10^9 4-byte integers: memory bandwidth predicts ~7.5 s, but comparison-based sorting mispredicts branches; ~30 levels of quicksort with a mispredict every other comparison costs ~75 s. Estimate ~82.5 s, dominated by mispredicts, not memory. The lesson: enumerate the cost sources, not just the obvious one.

## Sources

- How to estimate: https://abseil.io/fast/90
- Performance Hints (estimation section): https://abseil.io/fast/hints.html
