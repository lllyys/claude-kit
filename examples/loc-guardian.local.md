---
max_pure_loc: 300
---

# loc-guardian Extraction Rules

When a file exceeds `max_pure_loc`, split it by **responsibility**, not by
mechanical line count. Move each cohesive group of code into its own file in
the same module/directory, keeping the original file as the entry point that
wires the parts together. Use whatever file/extension conventions your language
already follows.

## Split by responsibility

- **Type / interface / schema definitions** → a dedicated types/schema file
- **Constants & static config** → a dedicated constants/config file
- **Pure helper / utility functions** → a dedicated utils/helpers file
- **Cohesive sub-units** (a sub-component, sub-class, sub-module, or distinct
  feature slice) → its own file, named for the unit it contains
- **Stateful or orchestration logic** (handlers, controllers, stores, services)
  → keep with its owner; if still too large, split by feature/domain boundary

Stop splitting once each file has a single clear responsibility and is under the
threshold. Do not create empty or near-empty files just to satisfy the count.
