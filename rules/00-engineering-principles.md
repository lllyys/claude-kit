# 00 - Engineering Principles (Local)

Follow the shared rules in `AGENTS.md`.
This file exists to mirror local-only references from dev docs.

Key points:
- Read a file fully before editing it; never edit blind.
- Keep diffs focused — change only what the task requires, no drive-by edits.
- Research before building: understand existing patterns and abstractions before adding new ones.
- Keep modules cohesive; avoid cross-module coupling unless the dependency is genuinely shared.
- Keep code files small and single-purpose (a soft ceiling of ~300 lines is a good signal to split).
- Handle edge cases deliberately: empty input, null/absent values, boundary conditions, and concurrent access.
