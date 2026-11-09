---
name: symbol-inventory
description: >-
  Perform an inventory of all symbols added or modified on the current branch relative to the repository's default
  branch, with types, meanings, and dependency ordering. Use only when explicitly requested.
---

Perform an inventory of symbols added or modified on the current branch relative to the repository's default branch.
Include all symbols, such as functions, methods, constructors, classes, interfaces, records, enums, type aliases,
constants, fields, parameters, and variables.

State the comparison refs and present tables with:
Location | Symbol category | Name | Data type or signature | Meaning

Use clickable file-and-line references for Location. Symbol category identifies what the symbol is. Data type or
signature shows data types for values, parameter and return types for callables, or declarations for types. Meaning
describes each symbol's role based on its definition and callers.

Sort the inventory topologically across files and repositories, placing dependencies before dependents. Group cyclic
dependencies together. Use file path and declaration order to break ties between independent symbols.
