# ADR-0003: A Helm library chart of workload archetypes

**Status:** accepted

## Context
Every service needs the same production scaffolding: restricted Pod Security,
non-root, fail-closed readiness, zone spread, PodDisruptionBudgets, and (for some)
an ordered schema-migration Job. Copying this YAML per service guarantees drift.

## Decision
Author one **library chart** (`platform-lib`) that defines the shared archetypes —
`web`, `scalable-worker`, `fenced-singleton`, `migration-job` — and bakes in the
security defaults so no service can forget them. Each per-service chart is a few
lines: it depends on the library and `include`s the archetype it needs. The umbrella
chart composes the services and is delivered via Argo CD ApplicationSets.

## Consequences
- **+** Security and HA defaults are enforced centrally, not by convention.
- **+** A new service is a Chart.yaml + values.yaml, nothing more.
- **–** A library-chart bug hits every service; changes need care and lint/template
  checks in CI.
