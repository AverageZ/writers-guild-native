You are rebuilding **Writers Guild** (/Users/alexzajac/projects/writers-guild
) as a new greenfield repository.

Do not port the old application architecture.

The existing POC was a React + Lexical + Vite SPA created quickly by coding agents. It is difficult to understand and barely works. Treat it only as a source of product ideas if it is available to you. Do not preserve React, Lexical, Vite, component structure, state management, or other implementation choices merely because they already exist.

Build a clean, understandable macOS application around the actual product goal described below.

# 1. Product vision

Writers Guild is a **writing environment for fiction writers working inside persistent fictional worlds**.

A writer may create **many stories inside the same world**.

The application helps the writer maintain:

- continuity,
- world accuracy,
- character consistency,
- location consistency,
- chronology,
- names and terminology,
- titles/ranks/status,
- prose mechanics,
- tense,
- stylistic habits,
- and other forms of consistency.

It does this through a “Guild” of background agents with distinct specialties and personalities.

The Guild should feel like a group of attentive readers who have spent a long time learning the writer's world.

They do **not** write the story for the user.

The core fantasy is:

> I sit down and write normally. Somewhere around me, a small guild of opinionated readers understands my world, remembers what has happened, notices mistakes and patterns, and occasionally taps me on the shoulder when something deserves my attention.

The AI is the critic, continuity editor, researcher, copy editor, and eccentric writing companion.

**The human remains the author.**

# 2. Example of the experience

Suppose the world contains a place called Old Town.

Earlier in the story:

- the party enters a dungeon,
- traverses it,
- exits through a southern exit,
- and that exit establishes their current location as being south of Old Town.

Several chapters later I write:

> They headed south toward Old Town.

A continuity agent should notice that this is geographically inconsistent.

It should be able to explain, concisely:

- where the manuscript currently establishes the party to be,
- what source established that,
- what the lore says about Old Town if relevant,
- and why the new sentence appears inconsistent.

It should **not** silently rewrite the sentence.

Other examples:

- A character named Maren is accidentally written as “Marenne.”
- The manuscript is written in past tense but slips into present tense for a paragraph.
- A character established as a Private was promoted to Corporal in the previous chapter, but a later scene calls them Private again.
- The manuscript accidentally depicts the same promotion as happening twice.
- A character is described as carrying an object they gave away three scenes earlier.
- A person who is canonically missing an eye is later described as having “blue eyes” without explanation.
- A journey takes an impossible amount of time according to the established geography.
- A character knows information they have not yet learned.
- A dead character appears without the story establishing why.
- A style-oriented agent notices clusters of hedge words such as “perhaps,” “somewhat,” “seemed,” “almost,” or “maybe.”
- Another agent notices repeated sentence openings.
- Another notices dialogue attribution habits.
- Another notices an unusual density of adverbs.
- Another asks whether a scene contradicts a character motivation established earlier.

Some of these checks should be deterministic.

Some should use language models.

Do **not** use an LLM merely because one is available.

# 3. Critical conceptual separation

There are four different kinds of knowledge in Writers Guild. Do not collapse them into one RAG database.

## A. Canon

Facts deliberately established by the writer about the world.

Examples:

- lore documents,
- maps,
- character profiles,
- known aliases,
- organizations,
- geography,
- rules of magic,
- established historical facts.

Canon is authoritative.

## B. Story history / world state

Things established by events in a particular story.

Examples:

- Rowan was promoted from Private to Corporal.
- The party exited the dungeon south of Old Town.
- Mara gave the key to Elise.
- Jonas learned who killed his brother.
- The bridge collapsed.
- The king died.
- The characters are currently on day 14.

This needs temporal semantics.

A question like:

> What rank does Rowan have?

is incomplete.

The meaningful question is:

> What rank had Rowan reached as of scene 37 of Story A?

Story state must therefore be queryable **as of a specific point in story chronology**.

## C. Agent memory

An agent's accumulated experience.

Examples:

- “The writer tends to intentionally use sentence fragments during combat.”
- “I previously complained about sparse dialogue and the writer dismissed it.”
- “I have repeatedly noticed water imagery around Elise.”
- “Ada and I usually disagree about whether Jonas is sincere.”

Agent memory creates characterization.

It is **not canon**.

It may decay, be reinforced, become inaccurate, conflict with another agent's memory, or be forgotten.

An agent's memory must never override canonical world facts or established story state.

## D. Current textual evidence

The actual chapter, scene, paragraph, selection, or sentence currently being reviewed.

Never confuse these four layers.

This separation is one of the most important architectural requirements in the entire application.

# 4. Platform direction

Build Writers Guild as a **native macOS application**.

Use:

- Swift
- SwiftUI where appropriate
- AppKit where it materially improves the editor/window/platform experience
- WKWebView for the rich-text writing surface
- Wordgard as the browser-based editor engine inside that WKWebView
- a very small TypeScript/JavaScript layer around Wordgard
- native Swift domain logic outside of the editor
- local persistence

Do not use React.

Do not use Lexical.

Do not build a web SPA wrapped in a native window.

The macOS application is the application.

Wordgard is merely one replaceable implementation of the manuscript editing surface.

The architecture must permit Wordgard to be replaced someday without rewriting the Guild.

# 5. Wordgard boundary

Research the current Wordgard APIs before implementation. It is an evolving dependency; do not invent APIs from memory.

Bundle all Wordgard assets locally with the application.

No CDN.

No remote runtime dependencies.

Keep the JavaScript/TypeScript surface intentionally small.

Create an editor abstraction roughly equivalent to:

```
loadDocument(...)
exportDocument(...)
getSelection(...)
getText(...)
getTextForAnchor(...)
applyFormatting(...)
addAnnotation(...)
removeAnnotation(...)
clearAnnotations(...)
scrollToAnnotation(...)
onDocumentChanged(...)
onSelectionChanged(...)
```

The exact interface should follow Wordgard's real capabilities rather than this pseudocode.

Wordgard must know as little as possible about the Guild.

It should not:

- call language models,
- implement agents,
- own agent memory,
- query canon,
- decide continuity,
- own the application database,
- know agent personalities,
- schedule reviews.

Its job is editing text and displaying annotations.

Build a clean Swift ↔ WKWebView bridge around it.

Keep the bridge typed and inspectable. Avoid a large collection of ad-hoc string messages.

# 6. Durable manuscripts

Wordgard's internal representation must not become the only durable representation of the user's writing.

Design an explicit storage format for manuscripts.

Prefer boring, inspectable formats.

Markdown is strongly preferred for prose/lore where it can represent the supported manuscript semantics without destructive round trips.

If Wordgard requires an internal structure that cannot be losslessly represented as Markdown, design an explicit serialization boundary and document the tradeoff rather than silently allowing editor internals to become the permanent file format.

A writer must never risk losing access to a novel because an editor framework disappears.

# 7. World → stories → manuscript hierarchy

The domain should represent at least:

```
World
  ├── Lore
  ├── Entities
  ├── Canonical facts
  └── Stories
        ├── Story A
        │     ├── chapters/scenes
        │     ├── chronology
        │     └── story events
        ├── Story B
        └── Story C
```

Multiple stories share a world.

However, do not assume every story occurs at the same point on one simple timeline.

A story should be able to represent its own chronology relative to the world.

Design for:

- stories set before other stories,
- stories occurring concurrently,
- flashbacks,
- scene ordering that differs from world chronology,
- facts that become true only after some event.

Do not overbuild a full temporal database in the first iteration, but do not choose a schema that makes temporal reasoning impossible.

# 8. Structured world state

Continuity cannot depend solely on embeddings or LLM context.

Create an explicit queryable model for entities, facts, events, and state transitions.

Candidate concepts include:

```
Entity
EntityAlias
CanonicalFact
StoryEvent
NarrativeClaim
StateTransition
EvidenceReference
ScenePosition
StoryTimestamp
LocationRelationship
```

You may improve these names.

Examples of stateful properties:

```
character.rank
character.location
character.alive
character.possessions
character.knowledge
character.relationships
group.location
object.owner
faction.leader
```

Do not hard-code the system only around those examples.

We need a reasonably general model.

A useful conceptual operation is:

```
worldState(
    story: storyID,
    asOf: scenePosition
)
```

which can answer questions such as:

```
currentLocation(of: party)
currentRank(of: Rowan)
currentOwner(of: key)
doesKnow(character: Mara, fact: X)
```

The output must include provenance.

If the engine believes Rowan is a Corporal, it should be possible to ask **why** and receive the prior event or canon evidence establishing that state.

# 9. Claims are not automatically truth

This is important.

If the writer accidentally types:

> Private Rowan stepped forward.

when Rowan is already a Corporal, the system must not immediately update Rowan's rank back to Private.

New prose produces **claims**.

Claims can:

- agree with established state,
- introduce a plausible new fact,
- describe an explicit state transition,
- conflict with established state,
- be ambiguous.

Design a pipeline that distinguishes textual claims from accepted/established story state.

A contradiction should be surfaced before an accidental line silently rewrites the application's understanding of the world.

Likewise:

> Rowan was promoted to Corporal.

may legitimately establish a state transition.

The architecture needs to model that distinction.

For the first implementation, it is acceptable for state extraction to be imperfect. It is not acceptable for the conceptual distinction to be absent.

# 10. Evidence and citations

Every continuity observation should have provenance.

An agent saying:

> This seems wrong.

is significantly less useful than:

> Rowan is called “Private” here, but Chapter 4 establishes their promotion to Corporal.

The observation should internally carry structured references to:

- manuscript range,
- prior scene/chapter,
- lore document,
- canonical fact,
- story event,
- or other relevant evidence.

Do not rely on prose citations generated from model memory.

Evidence references should come from application data.

Clicking an observation should eventually be able to navigate to its evidence.

# 11. Agents

Agents are persistent characters with specialties.

Examples:

- continuity specialist,
- geography/cartography specialist,
- names/terminology specialist,
- chronology specialist,
- character-state specialist,
- prose style specialist,
- tense specialist,
- hedge-word specialist,
- dialogue specialist.

Do not implement these as eight copies of an enormous system prompt.

Create a first-class `AgentDefinition`.

An agent can have things such as:

```
id
name
role
specialty/lenses
temperament traits
style preferences
thresholds
review frequency
confidence threshold
memory parameters
model preferences
enabled capabilities
```

Personality should be data-driven enough to inspect and tune.

The application should eventually allow a Guild Hall to expose much of this state.

# 12. Agent output contract

Agents should produce structured observations.

Define a native type along the lines of:

```
AgentObservation
  id
  agentID
  category
  severity
  confidence
  documentID
  anchor
  concise message
  optional question
  evidence[]
  createdAt
  status
```

Possible statuses:

```
unread
read
accepted
dismissed
markedIntentional
obsolete
```

Do not include a general `replacementText` or `rewrittenParagraph` field.

Agents are not prose generators.

An agent may:

- point,
- question,
- explain,
- compare,
- identify,
- cite,
- categorize,
- challenge.

It should not author the writer's final prose.

# 13. No chat-first UX

Do not turn Writers Guild into ChatGPT next to a text editor.

The primary interactions should be things like:

- manuscript highlights,
- gutter indicators,
- review cards,
- evidence popovers,
- agent presence,
- Guild Hall,
- lore browser,
- structured controls,
- accept/dismiss/intentional actions.

No generic prompt box is necessary for the first version.

The writer writes the manuscript rather than prompting the Guild.

# 14. Deterministic analysis before LLM analysis

Use ordinary code when ordinary code is better.

Examples likely suitable for deterministic or mostly deterministic analysis:

- hedge-word lists,
- repeated words,
- repeated sentence openings,
- possible character-name misspellings,
- aliases,
- simple title/rank mismatches after entity resolution,
- punctuation patterns,
- some tense heuristics,
- known geography relationships,
- explicit current-state comparisons.

Use language models where language understanding is actually valuable:

- extracting structured claims from narrative prose,
- entity resolution under ambiguity,
- interpreting implied state transitions,
- semantic continuity,
- character knowledge,
- motivation,
- subtle contradiction,
- evaluating prose patterns that aren't reducible to simple rules.

Build analyzers behind protocols so deterministic and model-powered analyzers can coexist.

# 15. Model architecture

Use Apple's Foundation Models framework as the first model implementation when available.

Before coding against it, inspect the currently installed SDK and current Apple documentation. Do not rely on stale API examples.

Use its capabilities where appropriate:

- structured/guided generation,
- native Swift output types,
- tool calling,
- querying application state,
- local on-device inference.

The Guild should expose tools conceptually like:

```
searchCanon(...)
resolveEntity(...)
getStoryState(...)
getEvents(...)
retrieveEvidence(...)
recallAgentMemory(...)
```

Require grounding tools for continuity tasks where appropriate.

Do not shovel the entire novel into a model context.

Retrieve narrowly scoped evidence.

Create a model-provider abstraction in the domain.

The rest of Writers Guild must not depend directly on `SystemLanguageModel`.

Design for future providers such as:

- another Foundation Models `LanguageModel`,
- MLX,
- LM Studio,
- other local models.

Do not implement all of those now.

Implement one clean provider and prove the boundary.

Check model capabilities at runtime and degrade gracefully when the Apple model is unavailable.

The editor must remain usable without AI.

# 16. Agent memory: experimental biological model

Implement the beginnings of a simulated biological memory system.

Keep this deliberately separate from canon and story state.

Memory layers:

## Working memory

Tiny, temporary, review/session scoped.

Examples:

- what the agent is currently investigating,
- recently retrieved evidence.

## Episodic memory

Specific experiences.

Examples:

- “I flagged this character's speech as too formal.”
- “The writer dismissed my concern.”
- “I observed recurring water imagery in three scenes.”

Each episode can have properties such as:

```
salience
strength
confidence
createdAt
lastRecalledAt
recallCount
decayRate
```

## Semantic agent memory

Generalizations produced by consolidation.

Examples:

- “This writer intentionally uses fragments in action scenes.”
- “Mori tends to overestimate the importance of sparse dialogue.”
- “Elise frequently avoids direct answers.”

These are agent beliefs, not world facts.

## Consolidation / sleep

Do not continuously ask an LLM to update memory while the writer types.

Create a review/consolidation ritual that can run:

- after a writing session,
- after inactivity,
- manually through an End Session / Let the Guild Read action.

Consolidation may:

- strengthen frequently recalled memories,
- weaken stale memories,
- merge related episodes,
- produce tentative semantic memories,
- detect contradictions between memories,
- retire low-value memories.

Start simple.

The goal is a clean memory lifecycle that we can experiment with, not a biologically accurate neural simulation.

Memory should materially affect what an agent notices or prioritizes.

It must never change canon by itself.

# 17. Writer feedback affects agents

Treat user interaction with an observation as meaningful agent experience.

Examples:

```
dismissed
accepted
marked intentional
useful
not useful
```

A repeated pattern of dismissals should be able to change an agent's future thresholds or memory.

However, avoid opaque self-modifying prompts.

Persist the relevant events and derive behavior through understandable rules wherever possible.

I want to be able to inspect **why an agent behaves differently now than ten sessions ago**.

# 18. Review scheduling

Do not run language models on every keystroke.

The writing experience must remain calm.

Separate:

## Cheap local analysis

Can run relatively frequently.

## Expensive semantic review

Run deliberately:

- after a paragraph/scene settles,
- after an idle interval,
- on explicit review,
- at end of writing session.

The Guild should feel attentive, not twitchy.

Design a `ReviewCoordinator` or equivalent rather than allowing individual views to launch arbitrary model jobs.

Handle cancellation and stale results.

If text has changed enough that a result is no longer valid, mark it obsolete rather than displaying nonsense.

# 19. Anchoring observations in changing text

Annotations must survive normal edits as gracefully as practical.

Do not rely solely on a raw integer character offset saved forever.

Investigate Wordgard's actual mechanisms for positions, decorations, document changes, or mapping positions across edits.

At the persistence boundary, consider storing enough context to relocate an annotation, such as:

- document identity,
- structural location if available,
- text range,
- nearby text/context fingerprint,
- content hash.

The initial implementation does not need perfect CRDT-grade anchoring.

It must, however, have an explicit strategy for stale and shifted annotations.

# 20. UI

Build a restrained native Mac interface.

Prioritize the manuscript.

A reasonable initial shape is:

```
Navigation/sidebar
  World
  Stories
  Chapters / scenes
  Lore
  Guild Hall

Main content
  Wordgard manuscript editor

Secondary contextual surface
  Guild observations / inspector
```

Avoid dashboarditis.

Avoid filling the application with cards merely because SwiftUI makes cards easy.

The application should feel like a serious writing application with a strange living system underneath it.

Support a Quiet Time state that hides or defers Guild interruptions without stopping the writer.

# 21. Guild Hall

Build a basic inspectable Guild Hall.

For each agent show enough state to make it feel concrete:

- identity,
- role,
- specialty,
- current enabled state,
- important traits,
- recent observations,
- selected memories,
- confidence/review parameters.

This does not need elaborate visual design yet.

The point is to make agent characterization tangible and debuggable.

# 22. Persistence

Everything important must persist locally.

Choose a boring, robust local persistence mechanism.

SQLite is appropriate for structured Guild state.

Use SwiftData only if, after examining current capabilities, it provides a genuinely simpler and testable solution for the queries and migrations required here.

Do not choose it merely because it is Apple's newest framework.

Persist structured data such as:

- worlds,
- stories,
- scenes/chapters metadata,
- entities,
- aliases,
- canonical facts,
- story events,
- narrative claims,
- evidence,
- agent definitions,
- observations,
- feedback events,
- agent memories,
- review runs.

Keep manuscript/lore source files separate where appropriate.

All data should be local for this first build.

Architect persistence so optional personal iCloud synchronization can be explored later, but **do not make sync a dependency of the first vertical slice**.

Do not add:

- accounts,
- a hosted backend,
- telemetry,
- a cloud database,
- remote manuscript storage.

# 23. Search / retrieval

Start with practical retrieval.

Before introducing a vector database, determine what can be handled well with:

- entity IDs,
- aliases,
- structured facts,
- temporal state,
- SQLite FTS,
- lexical search,
- document metadata.

If semantic embeddings become necessary, hide them behind a retrieval protocol and keep the index regenerable from authoritative source material.

Embeddings are an index.

They are not canon.

# 24. Lore

Lore belongs to the world, not to a single agent.

Lore should be readable and editable by the writer.

Prefer Markdown files.

Agents using lore must cite the relevant lore source.

Never silently edit lore because an agent thinks the manuscript implies something different.

If manuscript and lore conflict:

**flag the conflict.**

Let the writer decide which is correct.

# 25. Testing philosophy

Testing is mandatory because continuity logic will become subtle.

Use native Swift tests for domain behavior.

Use appropriate macOS UI tests for native integration.

Create a minimal browser test harness for the Wordgard editor layer. Playwright is acceptable for testing the Wordgard/TypeScript surface independently from the full native app.

Prioritize tests around domain invariants over screenshot-heavy UI testing.

The world-state engine and temporal logic must be heavily unit tested.

# 26. Required acceptance fixtures

Create a small fixture world named something like **Greyhaven** specifically for automated and manual testing.

It must cover at least these cases.

## Geography continuity

Lore/state establishes:

- Old Town.
- The dungeon's southern exit lies south of Old Town.
- The party exits through that exit.

Later text says:

> They headed south toward Old Town.

Expected:

A geography/continuity observation identifies the likely directional contradiction and includes evidence for the current location / established relationship.

## Rank continuity

Earlier text establishes:

- Rowan begins as Private.
- Rowan is promoted to Corporal.

Later text says:

> Private Rowan stepped into the room.

Expected:

A character-state observation notes the mismatch and cites the promotion.

Also test a repeated “promoted to Corporal” event when Rowan is already Corporal.

## Character name

Canon contains:

```
Maren Vale
```

Later prose contains a plausible typo:

```
Marenn Vale
```

Expected:

A name/terminology observation.

Do not globally autocorrect it.

## Tense

A past-tense scene contains an accidental sustained switch into present tense.

Expected:

A tense observation anchored to the affected passage.

## Hedge language

A paragraph contains an intentionally excessive cluster of:

```
perhaps
seemed
almost
somewhat
maybe
```

Expected:

The relevant style agent highlights the pattern.

## Possession

An earlier scene establishes:

```
Mara gives the brass key to Elise.
```

Later prose says:

```
Mara unlocked the door with the brass key.
```

Expected:

A continuity observation unless an intervening event returns the key.

## Character knowledge

Jonas learns a secret in Chapter 8.

A Chapter 5 scene must not be allowed to treat that later knowledge as something Jonas already knows simply because Chapter 8 appears earlier in editor retrieval results.

Expected:

Temporal story state prevents future information from leaking backward.

That test is especially important.

# 27. Repository structure

Choose a clean modular structure.

A reasonable starting direction is conceptually:

```
WritersGuild/
  App/
  Domain/
  Persistence/
  AI/
  Review/
  EditorHost/
  Features/
    Writing/
    Lore/
    GuildHall/
  Resources/
  Tests/

  Editor/
    src/
    tests/
    package.json
    ...
```

Do not follow this mechanically if Swift Package boundaries suggest something better.

The important thing is separation of concerns.

Keep the pure domain independently testable where possible.

# 28. Documentation for humans

I want to be able to understand this repository.

Write concise documentation as you build.

At minimum create:

## README.md

Explain:

- what Writers Guild is,
- how to build it,
- how to run it,
- dependency requirements,
- current capabilities,
- known limitations.

## docs/ARCHITECTURE.md

Explain:

- module boundaries,
- data flow,
- Wordgard bridge,
- persistence,
- Guild review pipeline,
- model-provider abstraction,
- world-state model,
- agent-memory model.

Include simple diagrams.

## docs/DOMAIN.md

Explain the difference between:

- canon,
- narrative claims,
- story events,
- computed story state,
- agent observations,
- agent memories.

Give concrete examples.

## docs/DECISIONS/

Use short ADR-style documents for major decisions such as:

- why native macOS,
- why Wordgard behind WKWebView,
- manuscript storage representation,
- database choice,
- model abstraction.

Keep documentation current.

# 29. Code quality constraints

Optimize for comprehensibility.

Prefer:

- small types,
- explicit names,
- obvious data flow,
- protocols at real boundaries,
- dependency injection where it improves testing,
- value types for domain data when sensible,
- actors / structured concurrency where actual concurrency exists,
- explicit error handling.

Avoid:

- giant managers,
- `FooService` for every concept,
- global state,
- singleton soup,
- magic notification buses,
- hundreds of tiny abstractions,
- reflection-heavy frameworks,
- speculative generic infrastructure,
- massive system prompts,
- business logic in SwiftUI views,
- business logic in JavaScript,
- model calls directly from UI code.

Do not create abstractions merely to make the architecture look enterprise-grade.

This is a personal creative tool.

I want a small system whose important behavior can be understood.

# 30. Dependency discipline

Research dependencies before adding them.

For each non-Apple dependency, be able to explain:

- what problem it solves,
- why standard APIs are insufficient,
- whether it is maintained,
- how deeply it infects the codebase,
- how difficult replacement would be.

Wordgard is explicitly isolated because it is an implementation detail.

Apply similar thinking to other dependencies.

Pin versions appropriately.

# 31. Build strategy

Do not attempt to implement the entire dream at once.

But do not stop after writing an architecture document either.

Build a working vertical slice.

Recommended order:

## Phase 1 — Native shell + editor

Produce a real macOS application that:

- launches,
- creates/opens a world,
- creates a story,
- creates a chapter/scene,
- edits text using Wordgard,
- persists and reloads the manuscript.

Prove the Swift ↔ Wordgard boundary.

## Phase 2 — Domain and world state

Implement:

- entities,
- aliases,
- lore,
- story events,
- narrative claims,
- scene ordering,
- temporal state queries,
- provenance.

Make the required continuity fixtures pass without worrying yet about agent personality.

## Phase 3 — Review system

Implement:

- AgentDefinition,
- AgentObservation,
- ReviewCoordinator,
- annotation rendering,
- evidence navigation,
- dismiss / intentional feedback.

Use deterministic analyzers first.

## Phase 4 — Foundation Models

Add the first local model provider.

Use structured output.

Use application tools for grounded continuity tasks.

Add claim extraction and semantic continuity.

Make failures graceful.

## Phase 5 — Agent memory

Implement:

- episodic memory,
- basic decay/reinforcement,
- feedback events,
- manual End Writing Session,
- consolidation,
- inspectable Guild Hall memory.

Prove that user feedback can measurably affect an agent's later behavior.

## Phase 6 — Delight

Only after the foundations work, add:

- subtle animations,
- agent presence,
- native notifications,
- sounds where appropriate,
- more visual personality,
- richer Guild Hall behavior.

Do not compensate for weak continuity logic with visual polish.

# 32. First vertical-slice definition of done

The first meaningful milestone is complete when I can:

1. Launch Writers Guild as a native Mac app.
2. Open a world.
3. See multiple stories belonging to that world.
4. Open a chapter.
5. Write comfortably in Wordgard.
6. Close and reopen the app without losing work.
7. Maintain some lore about Old Town and Rowan.
8. Establish earlier events in a story.
9. Write a continuity mistake in a later scene.
10. Ask the Guild to review or wait for the appropriate review trigger.
11. Receive a concise in-editor observation.
12. Click it and see the evidence behind the observation.
13. Dismiss or mark it intentional.
14. Inspect the agent that raised it in the Guild Hall.
15. End the writing session and see some persistent agent-memory effect.
16. Run the automated tests successfully.

Do not declare success merely because a model produced comments beside text.

The key requirement is that the comment was grounded in the correct **world + story + point-in-time state**.

# 33. Things that are explicitly not goals yet

Do not spend major time on:

- collaboration,
- multi-user accounts,
- web deployment,
- mobile,
- cloud backend,
- publishing workflows,
- DOCX fidelity,
- Scrivener import,
- extensive export systems,
- plugin marketplaces,
- fully autonomous agents,
- complex vector infrastructure,
- agent-to-agent social simulation,
- beautiful onboarding,
- App Store release work,
- iCloud sync.

Leave sensible seams where appropriate, but do not build speculative systems.

# 34. Product rules vs implementation decisions

Treat these as strong product hypotheses:

- The writer remains the author.
- Agents critique and guide rather than write manuscript prose.
- World/story continuity is central.
- Evidence is more important than confident model prose.
- Many stories can inhabit the same world.
- Lore/canon and story state are distinct.
- Agent memory is distinct from both.
- The Guild should be inspectable.
- Reviews should feel deliberate rather than frantic.
- The editor should feel excellent enough to disappear while writing.

Treat these as implementation decisions that may be revisited:

- SwiftUI vs AppKit for a particular screen.
- Wordgard.
- exact persistence library.
- Markdown representation details.
- Foundation Models as the first provider.
- exact schema shape.
- exact agent set.

Do not confuse implementation choices with product identity.

# 35. Working style

Work autonomously and make reasonable decisions.

Do not repeatedly ask me to approve obvious implementation details.

When an uncertainty matters, prefer:

1. inspecting the actual framework/API,
2. choosing the smallest reversible design,
3. documenting the assumption,
4. continuing.

Do not hide broken behavior behind mocks once a vertical slice is expected to work.

Run builds and tests frequently.

Resolve compiler warnings you introduce.

Do not leave the repository in a broken state between major phases.

If the installed macOS SDK differs from assumptions in this prompt, adapt to the real SDK rather than forcing outdated sample code.

If Wordgard's real API differs from assumptions in this prompt, adapt the editor bridge while preserving the architectural boundary.

# 36. Start now

Begin by:

1. inspecting the environment and available macOS/Xcode SDKs,
2. researching the current Wordgard API,
3. researching the Foundation Models API available in the installed SDK,
4. creating the new repository architecture,
5. writing the minimal architectural/domain docs,
6. implementing the Phase 1 vertical slice,
7. continuing into the domain and continuity engine.

Do not stop after giving me a plan.

Build the project.

Throughout the implementation, keep asking yourself:

> Is this making Writers Guild better at understanding a writer's world and history, or am I just building generic AI-editor infrastructure?

If it is the latter, simplify or remove it.
