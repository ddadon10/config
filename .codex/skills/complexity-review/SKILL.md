---
name: complexity-review
description: >-
  Review branch changes for complexity that can be removed or simplified, with estimated non-test and test LOC
  savings. Use only when explicitly requested.
---

Review the changes on this branch. Distinguish essential complexity required
by the task from implementation complexity introduced by implementation choices.

Use the conversation, code, and relevant ExecPlan if one exists to establish
requirements and constraints. Look for superseded assumptions still reflected
in code or tests. Challenge the plan’s implementation choices too.

Challenge:
- Outdated assumptions, unnecessary restrictions, and hypothetical future needs.
- Redundant checks, validation, transformations, state, and configuration.
- Abstractions or custom logic that could be removed or replaced by existing facilities.
- Backward compatibility that adds complexity: show the simpler implementation
  possible with a breaking change, what would break, and who would be affected.

For each finding, propose how to remove or simplify it, citing concrete evidence.
Check callers, dependencies, and tests for code that could also be removed
or simplified, and explain what behavior would change.
State any compatibility breaks or constraints being relaxed.

Return a table:
Location | Complexity | Essential / Implementation / Uncertain | Evidence |
Simpler alternative | Estimated non-test LOC saved | Estimated test LOC saved

Estimate net savings as removed lines minus replacement lines. Flag overlapping
or mutually exclusive proposals. Sort by non-test LOC saved descending, then
location alphabetically; put unsupported estimates as “Unknown” last.

Show positive net LOC saved values with +, negative values with −, and zero as 0.
Color positive LOC saved values green and negative LOC saved values red;
leave zero uncolored. If the interface cannot render colored table cells,
use plain signed values.

Elaborate below the table where needed. Do not equate fewer lines with simplicity.
Do not modify files.
