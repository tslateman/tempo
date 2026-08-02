---
description: Performance optimization workflow - back-of-envelope analysis, bottleneck detection, approved fixes, measured validation
argument-hint: Optional file or directory to analyze
---

# /perf - Performance Optimization Workflow

Optimize the target for performance using a structured 7-phase workflow.

## Core principles

- Estimate before optimizing. Back-of-envelope analysis comes before code changes.
- Quantify everything. Estimates carry units; claims carry evidence.
- Profiles show where time goes, not what to fix. Find the real problem before fixing.
- Validated means measured. Re-reading code is not validation.
- Track progress with a todo list across all phases.

## Phase 1: Scoping

Target: `$ARGUMENTS` (default: current project).

Create a todo list covering all seven phases. If scope is unclear, ask:

1. What is slow? (endpoint, job, page, build, query)
2. How slow is it now? (numbers, or "unknown")
3. What is the target? (latency budget, throughput, memory ceiling)
4. What constraints apply? (API stability, memory limits, deploy freeze, dependency policy)

Confirm scope before proceeding.

## Phase 2: Analysis

Launch 2-3 `perf-analyzer` agents in parallel. Split by codebase area (views/API layer, data layer, external calls, frontend) or by angle (I/O patterns, memory and allocation, algorithmic complexity). Give each agent one specific question.

When agents return, read every file they flagged. Then present consolidated findings:

- Back-of-envelope latency table for the hot path
- Bottlenecks ranked by estimated impact, each with file:line
- Estimated total possible improvement, labeled as an estimate

## Phase 3: Clarifying questions

CRITICAL - do not skip this phase.

Surface every decision the user must make before work begins:

- Tradeoffs: memory vs speed, latency vs throughput, simplicity vs peak performance
- Scope: fix everything found, or highest ROI only
- Constraints: can APIs change, can dependencies be added, can schema migrate

Ask, then wait for answers.

## Phase 4: Fix prioritization

Rank candidate fixes by ROI: expected savings, effort, risk, dependencies between fixes.

Recommended order: highest impact first, low-risk before risky, independent before dependent.

Present the ranked list and ask which fixes to implement.

## Phase 5: Implementation

DO NOT START WITHOUT USER APPROVAL.

Implement approved fixes one at a time. For each fix:

1. State what changes and why it should be faster
2. State the expected improvement as an estimate
3. Make the change
4. Confirm existing tests still pass

## Phase 6: Validation

Measure first, review second.

### 6a: Measurement (attempt this first)

Run a real measurement of the changed path:

- If benchmarks exist (pytest-benchmark, a bench script, vitest bench), run them before-and-after
- Else if the change is testable in isolation, write a minimal timing harness (timeit, hyperfine, `console.time`) with realistic data sizes and run it
- Else if the change affects Django queries, count queries before-and-after (`assertNumQueries`, `connection.queries`, silk)

Report the numbers. If execution is impossible (no runtime available, change only manifests under production load), say so explicitly and explain why, then rely on 6b.

### 6b: Review

Launch 2-3 `perf-reviewer` agents in parallel:

- One focused on correctness (behavior preserved, errors intact, edge cases)
- One focused on performance (is the claimed win real, hidden costs, behavior under load)
- One focused on quality (readability, maintainability, idiom)

Consolidate results. Present issues with severity. Ask: fix now, fix later, or accept.

## Phase 7: Summary

Present:

- Before/after numbers where measured; estimates clearly labeled where not
- Each change with file references
- Tradeoffs accepted and why
- Remaining opportunities, ranked, as next steps
