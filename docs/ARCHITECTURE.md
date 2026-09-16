# Architecture

Writers Guild is a native macOS application. The manuscript is the primary surface; the Guild critiques, never authors.

```text
SwiftUI / AppKit shell ── EditorHost ── typed WKWebView bridge ── Wordgard
          │                    │                              local assets
          │             portable HTML + plain text snapshot
          ▼
     GuildCore ← ReviewCoordinator → GuildAI / ModelProvider
          │        │                  Apple on-device model
          │        ├─ deterministic analyzers
          │        └─ observations + unaccepted narrative claims
          ▼
     GuildPersistence → SQLite metadata / HTML manuscripts / Markdown lore
```

## Boundaries

- `GuildCore`: value domain, temporal state, evidence, deterministic analysis, anchors, feedback and memory. No UI or model-framework imports.
- `GuildPersistence`: SQLite transactions and portable source files. SQLite is supplied by macOS, not a third-party wrapper.
- `GuildAI`: replaceable provider; the Apple implementation alone imports Foundation Models when the SDK supports it.
- `EditorHost`: AppKit/WebKit integration. Wordgard knows documents, selection, formatting and annotations, not canon or agents.
- `WritersGuild`: navigation, writer decisions and orchestration. Review scheduling is centralized, not launched by arbitrary views.

## Chronology and authority

A scene has both presentation order and story time. A story has a world-time offset. State queries are isolated by world and story, bounded by time and event sequence; future events never become prior evidence because search happened to return them first. Canon initializes authoritative facts; writer-established events change story-local state. Text extraction produces pending claims, never automatic state changes. Every state value retains its evidence.

Within a scene, deterministic checks use safely relocated accepted-event anchors to provide a sequence cutoff at the passage being checked. The establishing promotion does not flag itself, but a later second depiction does. Missing source context does not manufacture a textual ordering: the explicit timeline remains authoritative. Semantic comparisons use the scene's accepted state snapshot, not a sentence-by-sentence simulation.

## Storage boundary

Manuscripts are portable semantic HTML, not Wordgard JSON. HTML preserves the supported rich-text semantics without an invented Markdown conversion. Lore is Markdown. The editor adapter performs HTML parsing/serialization using Wordgard's public API. Unsupported imports are not a promised feature. This deliberate departure from Markdown for manuscripts avoids destructive round trips and keeps novels readable in any browser without Wordgard.

Structured records are individually keyed JSON rows with indexed world/story/scene columns, SQLite FTS5, a schema version and a store generation. Database IDs are opaque bound text; only filesystem source IDs have a path-component whitelist. Sources are content-addressed and immutable. A successful source write precedes the transaction updating its database pointer, so failed commits leave the last committed manuscript accessible. Independent stale store handles cannot overwrite each other.

## Reviews and memory

Cheap local analysis may run after text settles; model work runs only on deliberate review. Results carry document revision and contextual UTF-16 anchors. Edits invalidate semantic results; safe contextual relocation preserves navigation without pretending obsolete reasoning remains current. Feedback is persisted separately. Session-end consolidation creates inspectable agent beliefs with decay and source feedback IDs. Beliefs can adjust stylistic thresholds but cannot mutate canon or temporal state.

Two independent intentional/dismissed style experiences can consolidate into a tentative semantic belief. Age-weighted source feedback and decayed belief strength derive a bounded pattern-threshold adjustment. Repeated consolidation without new feedback is idempotent. Continuity confidence and world state are never adjusted by this rule. Deliberate reviews recall relevant memories; working evidence remains review-scoped.

`ReviewGrounding.prepare()` resolves mentioned entities and bounded established relationships in the current world, then retrieves current text, scoped fallible memories, and effective state immediately before each paragraph. Claim extraction receives entity/property vocabulary and current prose, **not accepted values**. Only extracted static conflicts and repeated transitions reach a comparison session; ordinary state transitions are filtered before generation. Runtime generation schemas constrain entity and passage selections, and each state selection is bound to the paragraph whose prior state it represents. Swift chooses the specialist and supplies the source identity. Canonical baselines and accepted events remain separate in storage and in the complete citation trail.

The model does not calculate text offsets or construct citations. Swift materializes exact current-revision UTF-16 anchors and stored evidence from prepared references, then validates the resulting proposals. Every semantic observation requires current prose plus authoritative state provenance. Claims remain pending/conflicting, never accepted automatically. Reference validation cannot prove that a model's explanation is logically correct; real on-device runs still produced false positives and erroneous claims.

## Editor and application lifecycle

Versioned JSON command/reply envelopes travel through `callAsyncJavaScript` with an argument object, not interpolated script text. Events carry document changes, selection changes, annotation clicks or explicit errors. The adapter projects Wordgard structural-token positions onto block-separated UTF-16 prose. RangeSet requires disjoint ranges: a boundary sweep renders overlapping observations as non-overlapping visual spans while retaining independent logical anchors.

Selection ranges are read explicitly from Wordgard getters; spreading its selection object loses those getter values. The npm release enables its default keymap automatically, unlike the current website's example import.

Native scene switching waits for the selected document to load and exports the old document before replacement. App quit temporarily defers termination while export runs on the normal event loop, then terminates only after a successful save. AppKit's deferred-termination loop otherwise starved the WebKit export in native integration testing.

Packaged apps resolve the resource bundle under `Contents/Resources`, explicitly avoiding SwiftPM's absolute developer-build fallback. Swift package tests and `swift run` use `Bundle.module`. All runtime JavaScript assets and dependency licenses are copied into the application. CSP, a WebKit content blocker and navigation policy keep the editor offline.

## Platform research

Initial development used Xcode 16.4 and the macOS 15.5 SDK, which could not compile the Foundation Models branch. Active-path verification now uses Xcode 26.6, the macOS 26.5 SDK, and macOS 26.6.2 with an available on-device model. A real Greyhaven probe exposed the original failure: the model skipped all grounding tools, confused reader IDs with entity IDs, and invented citation IDs and text lengths. Required retrieval now happens in Swift rather than depending on optional model tool calls. This follows Apple's recommendation to retrieve obligatory information directly and keep on-device tasks small: https://developer.apple.com/documentation/foundationmodels/managing-the-context-window

Wordgard: npm 0.5.2, MIT; public docs at https://wordgard.net/docs/guide/ and https://wordgard.net/docs/ref/. Its document indices include structural tokens; they are not plain-text offsets. The adapter must map these explicitly. `ChangeSet.mapPos` and range decorations support editor-local annotation tracking. Persisted anchors store quotes and neighboring context.
