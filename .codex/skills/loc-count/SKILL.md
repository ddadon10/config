---
name: loc-count
description: >-
  Report branch changes as line-count tables, separating non-test files from test files and sorting by additions. Use
  only when explicitly requested.
---

Return two tables of files changed on this branch: non-test files and test files.
Determine the base branch from context and state the comparison used.

Use the format below. Sort each table by added lines descending, then by file
path alphabetically for ties. Net = added − deleted. Include a Total row.
Show positive Net values with +, negative values with −, and zero as 0.
Color positive Net values green and negative Net values red; leave zero uncolored.
If the interface cannot render colored table cells, use plain signed values.
If a category has no changed files, write “No changed files.”
Do not modify files.

Example output:

Comparison: merge base of origin/main → HEAD

Non-test files

| File | Added | Deleted | Net |
|---|---:|---:|---:|
| internal/api/resolver.go | 80 | 20 | +60 |
| internal/api/validator.go | 10 | 35 | −25 |
| Total | 90 | 55 | +35 |

Test files

| File | Added | Deleted | Net |
|---|---:|---:|---:|
| internal/api/resolver_test.go | 45 | 5 | +40 |
| Total | 45 | 5 | +40 |
