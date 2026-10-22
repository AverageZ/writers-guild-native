---
name: pr
description: Write concise, human-readable pull request bodies with Summary, Evidence, and Merge Danger
---

# Write a Pull Request Body

Ported from `strategy-game/.agents/skills/pr`.

Use this skill whenever writing or rewriting a pull request body. It defines the body only: invocation does not authorize creating a branch, committing, pushing, opening a pull request, or triaging review comments.

For a pull request title, use [git-workflow](../git-workflow/SKILL.md); this skill defines only the body.

Write for a reviewer who needs to understand the change before opening the diff. The body MUST begin with `## Summary`; do not add a preamble.

## Required shape

```md
## Summary

<smallest visual that explains the change>

<one or two plain-language sentences that give the visual context>

## Evidence

- Before: <the observed failure, absence, or prior behavior>
- After: <the exact command, scenario, or screenshot that demonstrates the change>

## Merge Danger

**Door:** <one-way | two-way> — <why it is or is not easy to reverse>.
**Blast radius:** <the concrete users, systems, layouts, or data that could break>.
```

### Summary

- Put the reviewer-relevant change above the fold. Use plain language; introduce technical terms only when they identify a boundary the reviewer must inspect.
- Pick the smallest useful visual. Usually use exactly one of: a shaped diff, file tree, call tree, component tree, short pseudocode, or Mermaid diagram. Omit it when a concise sentence is clearer.
- Include only the files, calls, props, states, and boundaries needed to understand the change. Do not restate the diff, list incidental files, or stack multiple diagrams for a small change.
- For user-facing work, state the observable user outcome before implementation detail.

### Evidence

- Show a meaningful before and after. “Tests pass” is not evidence by itself.
- For visual changes, attach or link a before/after screenshot when available; otherwise name the exercised user scenario and observed result.
- For non-visual changes, give the exact targeted test or command and the behavior it proves. State the relevant observed output or postcondition, not merely an exit code.
- Do not claim checks, screenshots, or outcomes that were not observed. Name missing prerequisites when verification could not run.

### Merge Danger

- A **one-way door** is a destructive migration, public contract removal, external side effect, irreversible data write, or hard-to-reverse product decision. Name the rollback constraint.
- A **two-way door** is cheap to revert with a normal code rollback. State why that rollback restores the prior behavior.
- The blast radius MUST be concrete: e.g. library compatibility, callers of a public API, native editor behavior, Guild review, or manuscript persistence. Do not write “low risk” without scope.
- Treat the door call as a review claim, not a guarantee. When uncertain, prefer the cautious classification and name the uncertainty.

## Project constraints

- This repository has no pull request template. Use the required shape directly.
- Preserve repository rules: never claim unrun verification, never create commits or pull requests unless the user explicitly requests that workflow, and keep implementation-only detail below reviewer decision context.
- If a repository template is added later, fill it first, then place Summary, Evidence, and Merge Danger beneath it unless repository instructions say otherwise.
