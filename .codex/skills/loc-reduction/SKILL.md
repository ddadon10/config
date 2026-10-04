---
name: loc-reduction
description: >-
  Review branch changes for LOC reduction while preserving behavior, compatibility, and the accepted design. Use only
  when explicitly requested.
---

Review the changes on this branch for LOC reduction without changing behavior,
compatibility, or the accepted design.

Start with the largest non-test additions. Look for redundant code, repeated
logic, unnecessary intermediate variables, single-use helpers that can be inlined,
and verbose implementations that existing facilities can replace.

Include savings in related tests. Avoid code golf, compressed formatting,
and moving code elsewhere merely to shrink a file.

Return a table:
Location | Simplification | Estimated non-test LOC saved | Estimated test LOC saved

Estimate net savings as removed lines minus replacement lines. Flag overlapping
proposals. Sort by non-test LOC saved descending, then location alphabetically.
Use “Unknown” for unsupported estimates and place them last.

Show positive net LOC saved values with +, negative values with −, and zero as 0.
Color positive LOC saved values green and negative values red; leave zero uncolored.
If the interface cannot render colored table cells, use plain signed values.

For the proposals with the largest estimated non-test LOC savings,
show short examples of the current code and its proposed replacement.
Do not modify files.
