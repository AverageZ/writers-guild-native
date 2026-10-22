---
description: Audit project instructions without duplicate repository facts
---

Audit the loaded repository instructions, canonical `.agents/` sources, and relevant harness settings against the conversation and repository. Find contradictions, stale or duplicate prose, and missing mechanical enforcement. Prefer deletion; retain only non-inferable invariants, safety constraints, and behavior-changing task knowledge. Do not search for unrelated instruction files.

Move enforceable rules to existing tooling where appropriate. Present evidence, the smallest change, and tradeoffs; wait for approval before editing instructions. Then edit canonical sources, verify local skill/command references and `.claude` discovery links, and report instruction-size change plus any necessary prose-only policy. This repository uses symlinked entrypoints, not a generated agent-config sync script. Do not mutate Git or GitHub without authorization.
