---
name: domain-modeling
description: Build and sharpen the project's domain language and record consequential trade-offs in its existing domain documentation and ADRs.
---

<!-- Adapted from https://github.com/mattpocock/skills/blob/5beb35b040e3de97e54fa9e386d7e42d15c295c2/skills/engineering/domain-modeling/SKILL.md; license: ../LICENSE-matt-pocock -->

# Domain Modeling

Actively sharpen the domain model while designing: challenge terms, explore concrete edge cases, and record definitions and decisions when they crystallize. Merely reading vocabulary is not this skill; use it when changing the model, not just consuming it.

This skill can accompany Wayfinder or grilling without a setup command. Load it through the harness Skill tool when available, otherwise `skill://domain-modeling`, then `.agents/skills/domain-modeling/SKILL.md`.

## Existing documentation is the home

This repository already uses:

```text
docs/
  DOMAIN.md                         Domain concepts and their boundaries
  ARCHITECTURE.md                   Architecture documentation
  DECISIONS/
    001-native-boundaries.md        Existing architectural decision record
```

Read `docs/DOMAIN.md` before adding language and inspect the relevant existing ADRs. Update domain definitions in `docs/DOMAIN.md`; do not create a competing root `GLOSSARY.md`. New ADRs belong in `docs/DECISIONS/`, preserving the existing three-digit numbering convention. Do not create `documentation/adr/` or empty documentation files.

If a root `GLOSSARY-MAP.md` is introduced explicitly in the future, read it first and follow its declared context locations. Do not create a map merely to use this skill, or split contexts without a real domain need. Preserve existing links and resolve conflicting documentation deliberately rather than maintaining duplicate authorities.

Code, configuration, and types are authoritative for implementation. Domain documentation records shared language and conceptual boundaries; ADRs record non-inferable decisions and their reasons. Neither should duplicate implementation details already evident from those sources.

## During the session

### Challenge existing language

When a term conflicts with `docs/DOMAIN.md` (or a mapped context), surface it immediately: “The domain document distinguishes a narrative claim from a story event, but this proposal uses them interchangeably. Is that a deliberate change?”

### Sharpen fuzzy terms

Propose a precise canonical term for vague or overloaded language. Ask whether “accept” means accepting a critique as useful or explicitly establishing a story event; these are different decisions. Recommendations are not the user's answers. Do not invent agreement or establish world facts on the writer's behalf.

### Discuss concrete scenarios

Invent clearly labelled hypothetical scenarios to probe boundaries. For example: a flashback appears late but occurs early; a critique identifies a rank discrepancy without authorizing a change; two stories share canon but not events. These are questions to resolve, not facts to insert into the user's world.

### Cross-reference with code

Check factual claims against the current implementation and surface contradictions. Do not silently rewrite the model to match code or assume that proposed behavior is already implemented. Investigate inline by default and honor repository delegation rules.

### Record resolved terms immediately

Update the relevant portion of `docs/DOMAIN.md` when a term is resolved rather than batching definitions for later. Follow [GLOSSARY-FORMAT.md](./GLOSSARY-FORMAT.md) while retaining the document's existing useful structure and conceptual distinctions. Keep implementation specifications, scratch notes, and unresolved proposals out of canonical definitions.

### Offer ADRs sparingly

Only offer an ADR when all three are true:

1. **Hard to reverse:** changing course later has meaningful cost.
2. **Surprising without context:** a future reader would wonder why this choice was made.
3. **A real trade-off:** genuine alternatives were considered and one was selected for specific reasons.

If any criterion is missing, skip the ADR. Otherwise use [ADR-FORMAT.md](./ADR-FORMAT.md), and record actual decisions and reasons—not invented user approval.
