# When Optimizing Memory

Allocation costs three ways: allocator time, construction/destruction, and cache dispersal - freshly allocated objects scatter across memory, so later traversal misses cache. Reducing allocations and choosing dense representations often beats micro-optimizing the computation.

## Prefer contiguous, dense representations

- Contiguous beats node-based: lists and arrays beat linked structures; in Python, a list of tuples beats a linked structure of objects, and numpy arrays beat lists of objects by an order of magnitude in both memory and traversal.
- Columnar beats row-of-objects for bulk numeric work: numpy/pandas keep values contiguous and typed; a million Python floats in a list cost ~28 bytes each plus pointer, a float64 numpy array costs 8.
- Downsize dtypes when ranges allow: int64 to int32/int16, float64 to float32, object strings to `category` for low-cardinality columns. Halving width halves memory traffic.
- Indices over references: store an index into a shared list instead of a reference to the object, when building transient graphs or cross-references. Smaller, and serializes trivially.

## Reduce per-object overhead

- `__slots__` or `@dataclass(slots=True)` removes the per-instance `__dict__`: substantial savings and faster attribute access for classes instantiated in the millions.
- Tuples over dicts for fixed-shape records in hot paths; NamedTuple keeps names without dict overhead.
- Separate hot from cold data: Django's `.only()` / `.defer()` and `.values_list()` avoid hydrating full model instances when the loop touches two fields. Hydrating a model instance costs far more than a tuple.

## Reduce allocation count

- Pre-size and build once: list comprehensions and `dict(...)` constructors allocate once; repeated `.append()` in a loop reallocates as the list grows. In TypeScript, `Array.from({length: n})` or a single `map` beats repeated `push` on large arrays.
- Hoist allocations out of loops: buffers, compiled regexes (`re.compile` once, module level), date formatters, reused dicts.
- Build strings with `"".join(parts)` or an f-string, never `+=` in a loop (quadratic copying). Same in TS: collect into an array and `join`.
- Stream instead of materializing: generators, `QuerySet.iterator()`, and `StreamingHttpResponse` process rows one at a time. Use them for single-pass pipelines over large data; use a list when the data is reused, needs `len`, or is small.
- Move, do not copy: pass references, slice with memoryview for bytes, avoid `list(x)` "just in case" copies.

## Layout for the cache (compiled/hot-path work)

For numpy, native extensions, or very hot TS code, the original C++ guidance applies directly:

- Order fields to minimize padding; use smaller numeric types
- Separate hot-read-only from hot-mutable fields (cache line behavior)
- Small-size optimizations and arenas: batch many small objects into one allocation

## Priors, not measurements

Pre-sizing containers eliminated 21% of one benchmark's cost in the source material; treat that and any figure like it as a rough prior. Estimate the saving for your case with the latency table, then measure.

## Sources

- Performance Hints (memory representation, allocation sections): https://abseil.io/fast/hints.html
