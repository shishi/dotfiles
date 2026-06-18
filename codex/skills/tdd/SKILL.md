---
name: tdd
description: Guide Test-Driven Development using Kent Beck's Red-Green-Refactor cycle. Use when writing tests, implementing features via TDD, or following plan.md test instructions.
---

# INSTRUCTIONS

Follow Kent Beck's TDD and Tidy First principles using the following workflow. None of the phases can be skipped.

1. **RED** - Write ONE small failing test
2. **GREEN** - Make the smallest behavioral change needed to pass the test, then commit when appropriate
3. **REFACTOR** - Improve structure without changing behavior, committing each cohesive tidy step when appropriate

## Workflow Pattern

```
RED → GREEN → commit → REFACTOR (commit each) → satisfied? ──yes──→ done
 ↑                                                  │
 └───── no (more behavior needed OR triangulate) ───┘
```
