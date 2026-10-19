---
paths:
  - ".agentic-os/project/**"
---

# .agentic-os/project

The project's own planning data: the concepts, the plans and the project context.

## Purpose and conventions
- `concepts/<name>/CONCEPT-<name>.json` is a concept, written only through `bash bin/app runtime concept write <name>` after the developer approved it; the markdown view beside it is rendered and never edited by hand.
- `plans/<session>/PLAN-<session>.json` is a plan, changed only through `/aos:plan`.
- `product.md`, `identity.md` and `architecture.md` are the project context the developer confirmed.

## Environment
- `bash bin/app runtime concept check <name>` validates a concept and `bash bin/app lint concepts` all of them; `bash bin/app runtime plan check` validates the active plan.

## Constraints
- A decision of a decided concept is superseded, never deleted.
