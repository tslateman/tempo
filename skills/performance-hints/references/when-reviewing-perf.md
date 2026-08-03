# When Reviewing Performance Changes

An optimization that breaks correctness is worse than the slow code it replaced,
because it is fast, wrong, and now trusted. Review in three gates, in order.
Nothing downstream matters until correctness passes.

## Gate 1 - Correctness

- **Behavior preserved.** Same output for the same input, including ordering
  where anything depends on it.
- **Errors still propagate.** No new blanket `except`, no swallowed failure, no
  default value substituted for an error. An exception at the point of failure
  is worth more than a fallback that hides it.
- **Edge cases.** Empty, one element, exactly at a batch boundary, null fields,
  duplicates, unicode.
- **Concurrency.** New shared state, changed transaction boundaries, ordering
  assumptions that parallelism breaks.
- **Cleanup.** Every long-lived client, connection, or file has a shutdown path.
- **Side effects.** A per-row loop replaced by a bulk call may have been firing
  signals, hooks, audit writes, or cache invalidations. Confirm those still
  happen.

### Common optimization bugs

| Optimization                    | Bug                                                    | Detection                                                                                    |
| ------------------------------- | ------------------------------------------------------ | -------------------------------------------------------------------------------------------- |
| `asyncio.gather`                | exceptions lost or misattributed                       | `return_exceptions=True` with results never inspected, or `False` with siblings left running |
| `Promise.all`                   | fail-fast cancels nothing, siblings run unobserved     | partial success required but `allSettled` not used                                           |
| Shared client                   | leak, no shutdown, wrong event loop                    | module-level client with no close; created before fork or before the loop                    |
| `bulk_create`                   | `post_save` never fires, PKs unset, validation skipped | signal handlers that the loop used to trigger; `obj.pk` read after create                    |
| `bulk_update`                   | `auto_now` fields stale                                | `updated_at` expected to move and does not                                                   |
| `select_related` on nullable FK | inner join drops rows                                  | result count differs from before                                                             |
| `select_related` chained        | wide joined rows cost more than the two queries did    | join width times row count against what the caller actually reads                            |
| `prefetch_related`              | prefetch discarded, N+1 returns silently               | `.filter()`, `.exclude()`, or `.order_by()` on the related manager afterwards                |
| `.only()` / `.defer()`          | deferred field touched, one query per instance         | attribute access outside the fetched set                                                     |
| `.iterator()`                   | queryset consumed twice, prefetch disabled             | second iteration; prefetch expected but not honoured                                         |
| `.values()`                     | model methods and properties no longer available       | downstream code calling a method on what is now a dict                                       |
| Caching                         | stale reads                                            | no invalidation on the write path, no TTL                                                    |
| Cache key                       | cross-tenant or cross-user leakage                     | key omits tenant, user, locale, or permission scope                                          |
| `lru_cache`                     | unbounded growth, instance retained, mutable result    | cache on a method holding `self`; cached mutable returned by reference                       |
| Deferred computation            | never forced, or computed twice                        | lazy value not awaited; no memo on the lazy path                                             |
| Pre-sized container             | off-by-one                                             | size expression differs from the loop bound                                                  |
| Fast path                       | diverges from the slow path                            | the two returning different results for the same input                                       |
| Bulk endpoint                   | partial failure with no rollback or report             | atomicity assumed, not enforced                                                              |
| Module-level mutable state      | cross-request contamination                            | dict or list at module scope mutated per request                                             |
| `shallowRef`                    | nested mutation no longer triggers render              | a nested field mutated in place                                                              |
| Debounce or throttle            | last event dropped                                     | no trailing invocation                                                                       |
| Index added                     | write amplification, migration lock                    | high-write table, large row count, no `CONCURRENTLY`                                         |
| Compression added               | CPU now dominates on a local path                      | compressing over localhost or an already-compressed payload                                  |

## Gate 2 - Does it actually help?

Challenge the claim, not just the code.

- **Is it hot?** A 90% saving on code that runs once at startup saves nothing.
- **Is it measured?** Find the numbers. If the change was validated by reading
  the code, label the claim UNVERIFIED and say so. A saving nobody measured is a
  hypothesis.
- **Is the benchmark honest?** Warm cache for cold, unrealistic input size,
  single run, setup inside the timed region, dead code eliminated, arms not
  interleaved. See `when-measuring.md`.
- **Did the cost move rather than vanish?** More memory, more connections,
  larger payloads, more GC pressure, work pushed to another service, latency
  traded away in a latency-sensitive path.
- **Does it hold under load?** A pool of one is a serialization point. A cache
  with a poor hit rate is pure overhead. A batch size tuned on ten rows may be
  wrong at a million.
- **Was the dominant term addressed?** Reducing a term that was 8% of the total
  is churn, however satisfying the percentage on that term looks.

## Gate 3 - Maintainability

- Can someone unfamiliar with this change modify it safely in six months?
- Is the constraint that forced the non-obvious form recorded durably, in a test
  name, a commit message, or a docstring stating the requirement?
- Did the optimization leak into a public interface that is now hard to change?
- Is there a regression test? An unprotected performance fix regresses. The
  cheapest guard that would catch it: `assertNumQueries`, a benchmark
  threshold, a payload-size assertion, a bundle budget.
- Was the complexity worth it? Say plainly when it was not.

**Prefer the concise form.** When a simpler expression is also the faster one -
comparing ISO-8601 strings directly instead of parsing to `datetime`, a set
literal instead of a constructed set, a projection instead of fetching and
discarding - the optimization should have made the code shorter. An optimization
that made the code longer needs to justify the trade explicitly.

## Reporting

Every finding needs a concrete failure scenario: the inputs and state that
produce the wrong result. "This could be risky" is not a finding.

Rank by severity and lead with the worst. Separate what must change from what
you would prefer.

Do not manufacture findings to appear thorough. "Correct, measured, and
maintainable" is a valid review outcome and the most useful one to receive.

---

Source: Jeff Dean and Sanjay Ghemawat, "Performance Hints",
https://abseil.io/fast/hints.html.
