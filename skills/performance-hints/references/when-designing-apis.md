# When Designing APIs

An API's performance characteristics outlive the implementation behind it. A
signature that forces callers into a loop cannot be fixed by optimizing the
body, and once callers depend on it, the design is frozen.

This is the highest-leverage moment in performance work, and it happens before
any code is slow.

## Bulk over singular

A single-item API forces every caller to loop, and every loop pays per-call
overhead N times: dispatch, locking, connection setup, transaction boundaries,
round trips.

```python
def get_prices(self, symbols: Iterable[str]) -> dict[str, Decimal]:
    ...
```

Design guidance:

- Offer the bulk form first. A singular convenience wrapper over the bulk call
  is trivial; the reverse is not.
- Return a mapping keyed by input, not a positional list. Callers should not
  have to zip results back to inputs, and a mapping makes partial results
  expressible.
- Define partial-failure semantics explicitly. All-or-nothing, or per-item
  status? Silence here becomes a correctness bug in every caller.
- Bound the batch. Document the maximum and enforce it. An unbounded bulk
  endpoint is a memory exhaustion vector.
- Batch size is a parameter, not a constant. The right value differs between a
  local database and a remote API, and it changes with row width.

The same reasoning applies internally. A repository method taking one ID gets
called in a loop by someone eventually.

The estimate discipline applies here too: 100 items at one 50 us round trip each
is 5 ms of pure network before any work happens. One batched call pays it once.

Where a resolver-style fanout exists (GraphQL, or any nested serializer that
fetches per node), a DataLoader-pattern batch resolver collapses N lookups into
one query per tick. This is the same bulk API argument applied one layer down.

## Accept views, not copies

Abseil's `string_view` and `Span` exist so callers do not pay for a copy to
satisfy a signature. The Python and TypeScript equivalent is accepting the
broadest type you can actually work with.

- Accept `Iterable[T]` rather than `list[T]` when you iterate once. The caller
  keeps the option of passing a generator, and you stop forcing materialization.
- Accept `Sequence[T]` when you index or need the length. Do not demand `list`.
- Accept `bytes | memoryview` for binary data and slice with `memoryview` to
  avoid copying.
- Return an iterator when the result is large and consumed once. Return a
  concrete list when callers will iterate twice, and say which in the docstring.
- Do not accept a `QuerySet` in a function that only needs the rows. That
  couples the caller to the ORM and hides where the query executes.

The corresponding trap: accepting `Iterable` and then iterating twice. Take the
narrower type or materialize once, deliberately.

## Where the query executes

The most common Django API performance defect is a signature that hides when
evaluation happens.

- A function taking a model instance and touching a related object performs a
  query the caller cannot see or batch. Take the data, or document the
  prefetch requirement as part of the contract.
- A property that runs a query is invisible at the call site, and invisible in
  a template loop. Name it `fetch_*` or make it a method.
- Return querysets from repository functions when callers need to compose
  further filters; return concrete data when they do not. Mixing the two
  conventions across a codebase guarantees an N+1 somewhere.

State prefetch requirements in the signature's docstring when a function depends
on them:

```python
def summarize(orders: Sequence[Order]) -> Summary:
    """Requires orders fetched with prefetch_related("items")."""
```

## HTTP endpoints

**Pagination is mandatory, not optional.** A list endpoint without a bound will
eventually be called against a table nobody anticipated. Prefer cursor
pagination for large or frequently-written collections: offset pagination makes
the database scan and skip, so page 5 000 is far more expensive than page 1, and
concurrent inserts shift rows between pages.

**Return total counts only when the UI needs them.** `COUNT(*)` on a large table
can cost more than fetching the page it accompanies.

**Let the caller choose the shape.** A fixed response forces either
over-fetching or a second round trip. Sparse fieldsets, expansion parameters, or
separate summary and detail endpoints all work. Whatever you choose, make the
expensive fields opt-in rather than default.

**Expose a batch endpoint before callers build a loop.** Once ten clients loop
over your singular endpoint, adding the batch form does not remove the loops.

**Compress, and know what it costs.** Compression trades CPU for bandwidth. On a
cross-datacenter or public-internet path it nearly always wins; on localhost it
usually loses.

**Make cacheability explicit.** ETags and `Cache-Control` on responses that can
be cached. A response that cannot be cached should say why, because someone will
try.

## Sync and async surface

Choosing this is choosing your callers' concurrency model. Changing it later is
a breaking change dressed as a refactor.

- I/O-bound and called concurrently: async, with a sync wrapper if needed.
- CPU-bound: sync. An `async def` that never awaits is misleading.
- Do not offer both implementations of the same logic. Two code paths diverge.
  Write one and wrap it.
- A blocking call inside `async def` stalls the event loop for every concurrent
  request, not just the caller. In Django, wrap ORM access with `sync_to_async`
  or use the async ORM methods.
- `async_to_sync` in a hot path builds an event loop per call. It is a bridge,
  not a design.
- Pick one color per layer. `sync_to_async` costs a threadpool hop per call:
  acceptable at request granularity, fatal per row. Mixed layers pay bridging
  costs in both directions.
- Never hide an `await` inside a property or a getter. Callers cannot batch what
  they cannot see.

## Client lifecycle

A client is a resource with a lifecycle, not a value to construct on demand.

- One shared `httpx.AsyncClient` or `requests.Session` per process, created at
  startup, closed at shutdown. Constructing one per call pays a TCP and TLS
  handshake every time.
- Bind async clients to the event loop that will use them. A client created at
  import time and used from a different loop fails in ways that look like
  network flakiness.
- Size connection pools deliberately. A pool of one serializes every caller.
- Expose the client as a parameter with a module-level default so tests can
  inject their own.

## Thread safety is a design choice

Placing synchronization inside a type charges every caller for it, including
single-threaded ones. Leaving the type thread-compatible and requiring callers to
synchronize keeps the cost where it is needed but is easy to get wrong.

Choose by expected use: if concurrent access is the normal case, synchronize
internally and optimize inside. If it is the exception, document the type as not
thread-safe and let concurrent callers wrap it. Say which one you chose. An
unstated answer means callers assume the safe one and pay for it, or assume the
fast one and have a race.

The same logic governs caching. A cache inside the client helps every caller and
imposes invalidation semantics on all of them; a cache outside stays optional.

Default to a simple, unsynchronized, uncached core with an explicit wrapper for
the expensive concerns. The wrapper can then be measured and replaced
independently of the thing it wraps.

## Design questions worth asking early

- What is the largest N a caller will realistically pass? Estimate the cost at
  that N before finalizing the signature. See `when-estimating.md`.
- What happens when a caller loops over this? If the answer is bad, the API
  needs a bulk form.
- What does the caller have to fetch or compute before calling this? Hidden
  prerequisites are hidden costs.
- Which fields are expensive? Make them opt-in.
- What is the cheapest correct response? Anything beyond it should be requested.

---

Source: Jeff Dean and Sanjay Ghemawat, "Performance Hints", API design section,
https://abseil.io/fast/hints.html.
