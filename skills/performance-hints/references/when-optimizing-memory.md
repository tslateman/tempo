# When Optimizing Memory

Allocation costs three ways: the allocator's time, the constructor and
destructor, and the cache dispersal of the resulting objects. The third is the
one people forget and often the largest.

The goal is rarely "use less RAM." It is usually "touch less memory," because
memory is 100x slower than L1 cache and a scattered heap turns every access into
a cache miss.

## Principles from the hardware up

**Contiguity beats indirection.** An array of values is one stream the prefetcher
can follow. A list of pointers to objects is a random walk. In Python this means
`array`, `bytes`, and numpy arrays over lists of objects; in TypeScript, typed
arrays over arrays of records when the data is numeric and large.

The scale of this is easy to underestimate: a Python float in a list costs
roughly 28 bytes plus a pointer, while the same value in a `float64` numpy array
costs 8 bytes and sits next to its neighbours. Columnar beats row-of-objects by
close to an order of magnitude for bulk numeric work, in both memory and
traversal speed.

**Smaller is faster.** More elements per cache line means fewer misses. A numpy
column downcast from `float64` to `float32`, or `int64` to `int32`, halves the
bytes moved. Do this only where the range genuinely fits; a silent overflow is
not a performance win.

**Indices beat references.** A 4-byte index into a dense array beats an 8-byte
pointer, and the target is likely already in cache because it sits next to its
neighbours.

**Separate hot from cold.** Fields read on every iteration and fields read once
should not share a cache line. Splitting a wide record into a hot narrow one plus
a cold detail lookup is the data-layout version of Django's `.only()`.

**Pre-size when you know the size.** Growing a container reallocates and copies.
Abseil reports pre-sizing removing 21% of the cost in one benchmark. In Python
this matters most for numpy (`np.empty(n)` then fill) and for avoiding repeated
concatenation.

## Python

**`__slots__` removes the per-instance dict.** For a class instantiated in the
millions this cuts memory substantially and speeds attribute access:

```python
class Point:
    __slots__ = ("x", "y")

    def __init__(self, x, y):
        self.x = x
        self.y = y
```

For dataclasses, `@dataclass(slots=True)`. The trade is that you cannot add
attributes dynamically, which is usually a feature.

**Generators instead of lists** when the sequence is consumed once. Memory goes
from O(n) to O(1) and the first result arrives immediately:

```python
def parse_lines(path):
    with open(path) as fh:
        for line in fh:
            yield parse(line)
```

`list(parse_lines(path))` undoes this. So does any code that iterates twice.

**Hoist allocations out of loops.** Building the same object every iteration
pays construction and gives the allocator work:

```python
matcher = re.compile(PATTERN)
for row in rows:
    if matcher.match(row.name):
        ...
```

Reuse a mutable buffer where the API supports it rather than allocating a fresh
one per item.

**Join, do not concatenate.** `s += x` in a loop is O(n^2) because each
concatenation copies the whole accumulated string:

```python
parts = []
for row in rows:
    parts.append(format_row(row))
body = "".join(parts)
```

**Sets and dicts for membership.** `x in some_list` is O(n). Build the set once
outside the loop.

**Tuples and `namedtuple` for fixed records** are smaller than dicts and hash
cheaply. `dict` per row is the standard hidden memory cost in data pipelines.

**`array` and `memoryview`** for homogeneous numeric data and for slicing bytes
without copying. `memoryview(buf)[100:200]` is a view; `buf[100:200]` is a copy.

## Django and large datasets

**`.iterator()`** streams rows instead of materializing the result cache. Use it
for any queryset large enough that the list would be uncomfortable. Note that it
disables `prefetch_related` unless you pass `chunk_size` on a supported backend,
and that iterating the queryset twice re-runs the query.

**`.values()` and `.values_list()`** skip model instantiation entirely. For a job
that reads four fields from five million rows, this is the difference between a
model object graph and a stream of tuples:

```python
for order_id, status in Order.objects.values_list("id", "status").iterator():
    ...
```

**`.only()` and `.defer()`** keep model instances but fetch fewer columns. The
trap: touching a deferred field triggers a query per instance, converting a
memory win into an N+1.

**Bulk operations** move work from N round trips to one, and from N model
lifecycles to one queryset:

```python
Order.objects.bulk_update(orders, ["status"], batch_size=1000)
```

`batch_size` matters. An unbounded bulk statement builds one enormous query and
can exhaust memory on both sides.

**`select_related` versus `prefetch_related`.** `select_related` joins and
returns wider rows, so it trades bytes for round trips; good for a
one-to-one or forward FK. `prefetch_related` runs a second query and joins in
Python, so it trades memory for round trips; necessary for reverse and M2M
relations. Neither is free, and applying both to a wide model can move more
bytes than the N+1 they replaced.

## numpy and pandas

- Downcast dtypes where the range allows. `int64` to `int32` halves the column.
- `category` dtype for low-cardinality string columns replaces per-row Python
  strings with integer codes plus a small dictionary. On a column with a handful
  of distinct values this is usually the single largest available win.
- Prefer vectorized operations to `.apply()` with a Python function. `.apply()`
  reintroduces the per-row interpreter cost the array layout exists to avoid.
- `df.copy()` and chained indexing produce copies. Know which operations return
  views.
- Read only the columns you need: `usecols` on `read_csv`, column projection on
  parquet.

## TypeScript and the browser

- Typed arrays (`Float32Array`, `Int32Array`) for large numeric datasets:
  contiguous, no per-element object header, transferable to a worker without a
  copy.
- Object shape stability matters. Adding properties to an object after
  construction, or constructing the same logical record with different key
  orders, forces the engine to abandon its optimized hidden class.
- `structuredClone` and JSON round trips are full copies. On a large object
  either one can dominate the operation containing it.
- Closures captured in long-lived handlers retain everything in scope. This is
  the usual cause of a leak in a component that mounts and unmounts repeatedly.
- Build large arrays in one pass. `Array.from({length: n}, fn)` or a single
  `map` allocates once; repeated `push` reallocates as the array grows.
- In Vue, `ref()` over a large array creates a deep reactive proxy over every
  element. Use `shallowRef` when the value is replaced wholesale rather than
  mutated in place, and `markRaw` for objects that should never be reactive.

## What not to do

- Do not add object pooling before you have evidence that allocation is the
  dominant term. It usually is not, and a pool is a lifetime bug waiting to
  happen.
- Do not micro-tune a data structure that holds a hundred elements. Cache
  effects are a large-n phenomenon.
- Do not trade clarity for bytes without a measurement showing the bytes
  mattered.

---

Source: Jeff Dean and Sanjay Ghemawat, "Performance Hints", memory
representation and allocation reduction sections,
https://abseil.io/fast/hints.html.
