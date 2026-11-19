# Domain

Four knowledge layers must never collapse into one retrieval bag.

| Layer | Meaning | Example |
|---|---|---|
| Canon | Writer-authored world authority | Old Town is north of the dungeon exit. |
| Established story state | Writer-approved changes in one chronology | Rowan became Corporal in scene 4. |
| Agent memory | Fallible, decaying experience | The writer often marks hedge clusters intentional. |
| Current evidence | Text under review at a revision | “Private Rowan stepped forward.” |

A **narrative claim** is extracted from current prose. It may agree, conflict, be ambiguous, or propose a transition. It is not a story event. The accidental word “Private” must not demote Rowan.

A **story event** is an explicit writer-established transition with entity, property, value, story time, sequence and evidence. Computed state replays applicable events over applicable canon, returning provenance. Properties are open strings (`rank`, `location`, `owner`, `knowledge.secret`, etc.), not a fixed character schema. Entity values use stable IDs where relationships require them.

A **scene** has a presentation order and an independent chronological time. Flashbacks can appear late while being queried early. A **story** has its own world-time offset and does not inherit events from sibling stories. A knowledge event in Chapter 8 cannot leak into Chapter 5, regardless of array or retrieval order.

An **observation** is an agent's question or critique anchored to a manuscript revision and backed by application evidence. Accepting a critique is feedback, not permission to rewrite prose or promote a claim to fact. The writer explicitly establishes state using structured controls.

An **agent memory** is an inspectable belief with confidence, strength, recall, decay and feedback provenance. Working memory is review-scoped; episodes record experience; semantic beliefs consolidate repeated episodes. None participates in authoritative world-state computation.

Sources are referenced by stable IDs. Text anchors include UTF-16 range, quote, prefix, suffix and revision. Missing or ambiguous anchors become obsolete rather than landing on a coincidentally similar sentence.

## Agreed Level workspace language

These terms resolve [the Level workspace contract (#14)](https://github.com/AverageZ/writers-guild-native/issues/14), using the [confirmed mixed Scene/Level hierarchy](https://github.com/AverageZ/writers-guild-native/issues/5#issuecomment-6370783133). They describe agreed design, not implemented storage, UI or gameplay; the [Level workspace decision](DECISIONS/002-level-workspace-contract.md) records behavior and trade-offs.

**Level block**: A first-class manuscript block for a separately authored playable action sequence, not a prose Scene; its writing-workspace representation is nonplayable. It belongs to exactly one chapter in its story and retains stable identity and explicit story time independently of presentation order.

**Level intent note**: Optional writer-owned planning text describing a Level's narrative purpose, not manuscript prose, executable gameplay or established story state.

**Gameplay reference**: An optional opaque, writer-supplied identifier or locator for a Level's separately authored gameplay, distinct from the block's own identity. Recording it does not verify the target's existence or playability, authorize a story event, or promise external opening.

**Unbound Level**: A Level with no gameplay reference, valid for creation, planning, inspection, navigation and reorder. Supplying a reference changes its reference state, not the workspace's nonplayability or its authority over story facts.
