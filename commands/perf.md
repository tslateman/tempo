---
description: Performance optimization workflow - back-of-envelope analysis, bottleneck detection, approved fixes, measured validation
argument-hint: Optional file, directory, endpoint, or job to analyze
---

# /perf - Performance Optimization Workflow

Optimize the target for performance using a structured 7-phase workflow.

## Core principles

- Estimate before optimizing. Back-of-envelope analysis comes before code changes.
- Quantify everything. Estimates carry units; claims carry evidence.
- Profiles show where time goes, not what to fix. Find the real problem before fixing.
- Validated means measured. Re-reading code is not validation.
- Counts beat timings. Query counts, allocation counts, and payload sizes are deterministic; wall-clock time on a laptop is noise with a trend in it.
- Track progress with a todo list across all phases.

Consult the `performance-hints` skill throughout, routing to its reference files by task.

## Phase 1: Scoping

Target: `$ARGUMENTS` (default: current project).

Create a todo list covering all seven phases. If scope is unclear, ask:

1. What is slow? (endpoint, job, page, build, query, test suite)
2. How slow is it now? (p50 and p95 if known, a single wall-clock number otherwise, or "unknown")
3. What is the target? (latency budget, throughput, memory ceiling, or "as fast as reasonably possible")
4. What constraints apply? (API stability, memory limits, deploy freeze, dependency policy, migration risk)
5. Does it reproduce locally, or only under production load?

Confirm scope before proceeding.

## Phase 2: Analysis

Launch 2-3 `perf-analyzer` agents in parallel. Split by codebase area (views/API layer, data layer, external calls, frontend) or by angle (I/O patterns, memory and allocation, algorithmic complexity). Give each agent one specific question and a distinct file scope; overlapping scopes waste tokens.

When agents return, read every file they flagged. Agent findings are leads, not verdicts.

Then present consolidated findings:

- Back-of-envelope latency table for the hot path
- Bottlenecks ranked by estimated impact, each with file:line
- Estimated total possible improvement, labeled as an estimate

Say plainly which findings are confirmed by reading code and which remain hypotheses awaiting measurement.

## Phase 3: Clarifying questions

CRITICAL - do not skip this phase.

Surface every decision the user must make before work begins:

- Tradeoffs: memory vs speed, latency vs throughput, freshness vs cache hits, simplicity vs peak performance
- Scope: fix everything found, or highest ROI only
- Constraints: can APIs change, can dependencies be added, can schema migrate
- Correctness risk: any fix that changes ordering, error handling, or transaction boundaries

Ask, then wait for answers.

## Phase 4: Fix prioritization

Rank candidate fixes by ROI: expected savings, effort, risk, dependencies between fixes.

| Fix | Estimated saving | Effort | Risk | Depends on |
| --- | ---------------- | ------ | ---- | ---------- |

Recommended order: highest impact first, low-risk before risky, independent before dependent. Group fixes that must land together.

Present the ranked list and ask which fixes to implement.

## Phase 5: Implementation

DO NOT START WITHOUT USER APPROVAL.

Implement approved fixes one at a time. For each fix:

1. State what changes and the mechanism by which it saves time
2. State the expected improvement as an estimate
3. Make the change, keeping it minimal - a refactor folded into an optimization makes the measurement uninterpretable
4. Confirm existing tests still pass

Stop and report if a fix turns out to be infeasible or riskier than estimated.

## Phase 6: Validation

Measure first, review second.

### 6a: Measurement (attempt this first)

Run a real measurement of the changed path:

- If benchmarks exist (pytest-benchmark, a bench script, vitest bench), run them before-and-after
- Else if the change affects Django queries, count queries before-and-after (`assertNumQueries`, `connection.queries`, silk) - exact, cheap, and far less noisy than timing
- Else if the change is testable in isolation, write a minimal timing harness (timeit, hyperfine, `console.time`) with realistic data sizes and run it
- Else run the code path once each way with timing added

Report the numbers alongside the estimate. When measurement contradicts the estimate, the measurement wins and the estimate was missing a term; say so and find the term.

If execution is impossible (no runtime available, no reproducible data, the change only manifests under production load), say so explicitly, name the blocker, and rely on 6b. Never describe an unmeasured change as validated.

### 6b: Review

Launch 2-3 `perf-reviewer` agents in parallel:

- One focused on correctness (behavior preserved, errors intact, edge cases)
- One focused on performance (is the claimed win real, hidden costs, behavior under load)
- One focused on quality (readability, maintainability, idiom)

Consolidate results. Present issues with severity. Ask: fix now, fix later, or accept.

## Phase 7: Summary

Present:

- Before/after numbers where measured, with the method used; estimates clearly labeled where not
- Each change with file references
- Tradeoffs accepted and why
- The regression guard added for each fix (query-count assertion, benchmark threshold, payload-size check), or a note that none exists
- Remaining opportunities, ranked, as next steps
- What to watch in production to confirm the win holds under real load

Correct any estimate that measurement proved wrong. A corrected estimate is calibration; an estimate defended against data is superstition.
