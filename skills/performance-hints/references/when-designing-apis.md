# When Designing APIs

API shape sets the performance ceiling for every caller. A slow implementation can be fixed later; a per-item interface forces every caller into per-item costs forever. Design from the use case's domain logic, then give it a shape that amortizes.

## Bulk operations

Batch to amortize per-call costs: locking, dispatch, serialization, and above all network round trips.

- Offer `lookup_many(ids)` alongside `lookup(id)`; implement the singular as a one-element batch
- Django: `bulk_create`, `bulk_update`, `in_bulk`, `filter(id__in=...)` instead of loops of saves and gets
- REST: accept arrays in POST bodies; add batch endpoints for the operations clients call in loops
- Frontend/backend: one endpoint returning what the page needs beats five calls the page must sequence; where GraphQL-style fanout exists, batch resolvers (DataLoader pattern) collapse N lookups into one query per tick

The estimate discipline applies: 100 items at one 50 us round trip each is 5 ms of pure network before any work; one batched call pays it once.

## Pagination

- Always paginate list endpoints; unbounded lists are a latency and memory cliff waiting for growth
- Cursor (keyset) pagination over offset for large or hot tables: `WHERE id > :last ORDER BY id LIMIT n` stays constant-cost while `OFFSET 100000` scans and discards
- Return total counts only when the UI needs them; `COUNT(*)` on large tables can cost more than the page

## Accept views, return streams

The C++ advice (string_view, Span) translates directly: do not force callers to copy or convert.

- Accept any iterable, not just list; accept bytes-like objects and memoryview, not just bytes
- Do not `list(x)` defensively at the boundary; document single-pass semantics instead
- Return generators or streaming responses for large results so callers can stop early and never hold the whole result in memory
- TypeScript: accept `Iterable<T>` / `ArrayLike<T>` where you only iterate; avoid forcing arrays

## Sync/async surface

- Pick one color per layer. A sync ORM call inside an async view blocks the event loop; asgiref's `sync_to_async` bridges cost a threadpool hop per call - acceptable at request granularity, deadly per row
- If the service layer is called from async views, make it async end-to-end or keep the whole view sync; mixed layers pay bridging costs both ways
- Never hide an await inside a property or getter; callers cannot batch what they cannot see

## Thread-safety and state placement

Placing synchronization (or caching) inside a type versus leaving it to callers is a tradeoff:

- Thread-compatible (caller synchronizes): callers that need no synchronization pay nothing
- Internally synchronized: enables internal optimization (sharding, batching) when concurrent use is the norm
- Same logic for caching: a cache inside the client helps every caller but imposes invalidation semantics on all of them; a cache outside stays optional

Default to the simple, unsynchronized, uncached core with an explicit wrapper for the expensive concerns - the wrapper can be measured and replaced independently.

## Sources

- Performance Hints (API design section): https://abseil.io/fast/hints.html
