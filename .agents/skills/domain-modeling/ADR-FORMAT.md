# ADR Format

Companion to [SKILL.md](./SKILL.md). Upstream attribution and license: [SKILL.md](./SKILL.md), `../LICENSE-matt-pocock`.

ADRs live in `docs/DECISIONS/`. Read relevant existing records, including `001-native-boundaries.md`, before proposing another. Follow the existing sequential three-digit convention: `002-short-slug.md`, and so on. Scan the actual directory for the highest existing number and increment it; the example is not an instruction to assume the next available number.

If a future, explicitly established root `GLOSSARY-MAP.md` declares context-specific decision locations, follow those locations. Do not create `documentation/adr/`, empty records, or a competing decision tree.

Code, configuration, and types are authoritative for implementation. Record non-inferable choices and reasons, not an inventory of current behavior.

## Minimal template

```md
# {Short title of the decision}

{One to three sentences: context, actual decision, and why it was chosen.}
```

An ADR may be one paragraph. Its value is recording that a decision was made and why, not filling out sections. Do not mark a proposal accepted until the decision is actually made.

## Optional sections

Use only when helpful, following the local style (the existing native-boundaries record uses a prose `Status:` line):

- **Status:** proposed, accepted, deprecated, or superseded by a linked ADR.
- **Considered options:** rejected alternatives whose rejection is worth remembering.
- **Consequences:** non-obvious downstream effects.
- **Sources:** evidence or external constraints that materially informed the choice.

Preserve historical reasoning when a decision is superseded. Link the replacement instead of silently rewriting history.

## When to offer an ADR

All three must hold:

1. **Hard to reverse:** changing course has meaningful cost.
2. **Surprising without context:** a future reader would otherwise wonder why.
3. **A real trade-off:** genuine alternatives were considered and one selected for specific reasons.

If a choice is easily reversed, obvious, or has no real alternative, skip the ADR.

Candidates include architectural shape, integration patterns, technology lock-in, ownership boundaries, deliberate deviations from the obvious path, externally imposed constraints, and non-obvious rejection of alternatives. For this project, first check whether the SwiftUI/AppKit boundary, Wordgard embedding, manuscript representation, persistence, or on-device model decision is already covered in `001-native-boundaries.md`. Do not create a duplicate record to restate that existing decision. A genuinely new trade-off can warrant a new record; a factual correction can belong in the existing documentation.
