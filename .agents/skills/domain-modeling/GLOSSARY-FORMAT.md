# Domain Language Format

Companion to [SKILL.md](./SKILL.md). Upstream attribution and license: [SKILL.md](./SKILL.md), `../LICENSE-matt-pocock`.

## Location and structure

The canonical domain document here is `docs/DOMAIN.md`, not a new root glossary. Preserve its existing tables, concise definitions, and explanations of boundaries. Add a language section only if it improves readability; do not reformat the document just to match a template.

For new or clarified entries, this compact shape is useful:

```md
**{Canonical term}**: {One or two sentences defining the concept.}
_Avoid_: {Ambiguous alternatives, only when useful.}
```

For example, a clarification might distinguish “narrative claim” from “story event” using their existing definitions. Do not redefine terms from this reference without first reading the current domain document and resolving any disagreement with the user.

## Rules

- **Be opinionated.** Choose one canonical name for a concept; list misleading alternatives under `_Avoid_` when useful. Do not forbid a word that names a genuinely different concept.
- **Keep definitions tight.** One or two sentences per definition. Define what it is, not the sequence of functions that implements it. Preserve additional conceptual boundary explanations where they matter.
- **Include domain language, not programming vocabulary.** General concepts such as timeouts, utility patterns, or error types do not belong merely because the app uses them.
- **Group naturally.** Use subheadings when concepts form real clusters; a flat list is fine for a cohesive area. Keep existing helpful organization.
- **Do not restate implementation.** Code, configuration, and types remain authoritative for behavior and storage details. Domain language explains meaning, authority, and conceptual distinctions.
- **Record resolved meaning, not guesses.** Clearly distinguish proposals during discussion; do not place an unanswered recommendation into the canonical vocabulary as an accepted definition.

## Future context maps

Default to the existing `docs/DOMAIN.md`. If an explicitly established root `GLOSSARY-MAP.md` exists, read it first and defer to its declared locations rather than creating duplicate glossaries. A map may link existing domain documents; the filename of a context document need not be `GLOSSARY.md`.

A future map can list each context, its document, and the meaning of relationships between contexts. Do not introduce a map or split the domain merely because there are separate Swift modules or an embedded editor: technical boundaries do not automatically establish separate domain languages.

When multiple mapped contexts actually exist, determine which applies from the topic and repository evidence. Ask the user only if the domain choice remains ambiguous after investigation.
