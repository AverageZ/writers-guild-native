# Level writing-workspace contract

Status: accepted by the writer for [issue #14](https://github.com/AverageZ/writers-guild-native/issues/14). Design contract only; Level storage, UI and gameplay are not implemented by this decision.

## Context and decision

The [confirmed hierarchy](https://github.com/AverageZ/writers-guild-native/issues/5#issuecomment-6370783133) is World → Story → Chapter → ordered Scene/Level blocks. Scenes supply prose/exposition between playable action sequences. A Level is a first-class block, not a Scene subtype, a prose document, or proof that gameplay exists. Chapter roles, numbering and ownership remain as settled there.

The writer chose a minimal planning record with an optional opaque reference to separately authored gameplay. This lets the writer arrange action sequences before gameplay exists without coupling manuscript identity, chronology or evidence to a game engine. [Domain language](../DOMAIN.md#agreed-level-workspace-language) defines the terms; this record defines the workspace obligations.

## Writer-owned information

A Level has a stable block identity, exactly one parent chapter in its story, and a position in that chapter's mixed sequence. The writer can inspect and edit:

| Information | Contract |
| --- | --- |
| Title | A writer-editable name identifying the action sequence, not its external gameplay identity. |
| Intent note | Optional planning text describing its narrative purpose. It is neither manuscript prose nor established story state. No structured objectives, participants, outcomes or gameplay schema are required. |
| Story time | An explicit chronological position, editable independently of presentation placement and gameplay reference. |
| Gameplay reference | At most one optional writer-supplied identifier or locator for separately authored gameplay, preserved as entered. |

The block's identity is independent of its title, position and gameplay reference. Renaming, moving, replacing or clearing a reference must not recreate the block or lose its other information.

## Creation and reference states

The workspace must offer explicit Level creation in a chosen chapter, including an empty chapter, and placement among either kind of block. Creation exposes title and story time; the intent note and gameplay reference may be absent. Gameplay availability is never a creation prerequisite, and the operation does not create an empty Scene or prose document.

There are two reference states, separate from playability:

| Reference state | Writer-visible meaning |
| --- | --- |
| No gameplay reference | An unbound Level: a valid planning block whose gameplay has not been referenced. Creation, editing, navigation and reorder remain available. |
| Reference supplied—not verified | A reference has been recorded, not checked. It does not establish that the target exists, is accessible, is compatible or can be played. |

Both states must identify the representation as **nonplayable in this workspace**. A supplied reference must not become a misleading “ready”, “connected” or “playable” status.

The writer can inspect and copy the complete reference, replace it, or clear it to return to the unbound state. Clearing it leaves the Level's identity, title, note, placement and time intact. No resolver, file/URL opening, external launch, import, synchronization or automatic target validation is promised. A value such as `bridge-crossing-01` is an example reference, not a required identifier format.

## Cards, inspection and manuscript navigation

- Cards and manuscript navigation explicitly identify the block as **Level**, expose its title and reference state, and make story time distinguishable from presentation placement. The distinction must not rely only on color or an unexplained icon.
- Selecting a Level from either surface reaches the same block and opens its writer-owned details. It does not load its note into the prose editor, leave another Scene's prose presented as Level content, or offer a fake gameplay preview.
- Navigation through the manuscript follows the mixed Scene/Level sequence. It can enter a Level and continue to the adjacent block without silently skipping Levels or requiring a reference first.
- Entering or leaving a Level is a content-type transition, not a section break between prose Scenes or a new Section container. Exact card layout, typography, transition appearance and editing gestures remain prototype decisions.

## Ordering, chronology and authority

Reordering a Level within its story, including moving it between chapters, changes only presentation placement and chapter ownership as appropriate. Identity, title, note, reference, story time and established facts/events remain unchanged. Moving a chapter carries its mixed blocks in their existing relative order. The confirmed Prologue/Epilogue constraints still apply; this does not introduce cross-story moves or silent block-type conversion.

Editing a Level's story time is an explicit action separate from reordering. It changes that Level's chronological position, not its presentation order, reference or established events. No Level event-authoring, gameplay outcome or automatic story-state transition is introduced. This does not redefine the existing Scene time-edit behavior, which moves that Scene's explicitly attached events with it.

A planning note, reference, navigation action or reorder cannot establish that an action occurred or that a player succeeded. Even a future playable integration must separately decide outcome authority; it is not inherited from this structural contract.

## Considered options and consequences

- **Minimal metadata rather than required structured planning fields:** keeps Level planning possible before objectives, participants or mechanics are known. The intent note is deliberately not an executable specification or evidence of an outcome.
- **Opaque reference rather than an openable file/URL or embedded payload:** avoids choosing an engine, payload format, locator policy or integration lifecycle. The cost is that the writer must find and author gameplay separately; the workspace cannot certify or launch it.
- **Unbound Levels rather than reference-required creation:** supports planning before gameplay exists. Clear reference-state and nonplayability labels are required to avoid confusing a structural entry with a working game.

These ownership boundaries matter before storage and UI implementation: treating Level identity as an external target, or treating its note as prose/evidence, would later require migrating manuscript links and authority assumptions. This decision intentionally leaves gameplay outside the writing workspace rather than building a partial runtime into it.

## Concrete contract walkthroughs

These are hypothetical expected outcomes for downstream design and implementation, not claims of executed app scenarios:

1. Create “Crossing the bridge” between two Scenes, with an intent note and story time 2 but no reference. It appears as an unbound, nonplayable Level; selecting it exposes its details and navigation can continue to the following Scene.
2. Add `bridge-crossing-01`. The reference state becomes supplied—not verified; it does not become playable. Copying returns the recorded reference. Replacing it and then clearing it preserve the same Level and its other information.
3. Move that Level to the Prologue. It remains at story time 2 with the same identity, note and reference state; surrounding prose and established events are unchanged. Move its chapter and the relative block sequence travels together.
4. Explicitly change the Level's story time from 2 to 7. Its manuscript position stays fixed; no character survives, dies, learns a secret or otherwise changes established state because of this edit.

## Handoff and verification boundary

- [#8 — Writing surface](https://github.com/AverageZ/writers-guild-native/issues/8) and [#9 — Cards and notes](https://github.com/AverageZ/writers-guild-native/issues/9) decide visual treatment and interaction through human-reviewed prototypes; they must retain the Level/prose and reference/playability distinctions above.
- [#15 — Legacy hierarchy migration](https://github.com/AverageZ/writers-guild-native/issues/15) decides conversion of existing chapter labels. This decision neither migrates libraries nor manufactures Levels from legacy prose.
- [#12 — Shared safety](https://github.com/AverageZ/writers-guild-native/issues/12) decides cross-feature undo, durable saves/reopen and evidence handling; these identity, content, ordering and authority invariants are inputs, not a transaction design.
- [#13 — Acceptance and test seams](https://github.com/AverageZ/writers-guild-native/issues/13) finalizes observable checks after those decisions. The walkthroughs above supply boundary cases, not a new test suite or completed verification.
- [#4 — Planning map](https://github.com/AverageZ/writers-guild-native/issues/4) publishes the combined accepted implementation spec. [#16 — Mixed-block delivery](https://github.com/AverageZ/writers-guild-native/issues/16) implements it and proves actual native navigation, reorder and save/reopen behavior.

Current implementation remains Scene-based: `Scene.chapter` is a string, `Manuscript` belongs to a Scene, and the workspace navigates Scenes. This resolution changes documentation only. It does not claim a Level schema, native UI, tested gameplay, a visual prototype or production delivery. Document discovery and link checks verify this PR's surface; they cannot establish runtime behavior.
