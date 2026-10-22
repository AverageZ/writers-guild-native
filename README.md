# Writers Guild

A native macOS writing environment for fiction set in persistent worlds. Multiple stories share world lore; each keeps its own chronology. The Guild critiques with evidence and never rewrites the manuscript.

SwiftUI/AppKit is the application. A locally bundled Wordgard editor runs inside WKWebView. There is no React, web SPA, account, hosted backend, telemetry, or runtime CDN.

## Requirements

- macOS 14 or later and a graphical login session.
- Xcode 16.4 / Swift 6.1 or newer; select Xcode with `xcode-select`.
- Node.js 22+ and npm; Python 3 for app bundling.
- Network access only to install the pinned development/editor dependencies and test browsers.
- Optional Apple semantic review: a macOS 26+ SDK to compile the Foundation Models branch, macOS 26+, supported Apple Intelligence hardware, and an available on-device model.

**Verified on Xcode 26.6, the macOS 26.5 SDK, and macOS 26.6.2 with the on-device model available.** Older SDKs without Foundation Models still build the editor and deterministic Guild, with an explicit semantic-review availability message. Xcode's predictive code-completion model is separate from the Foundation Models runtime used by this app.

## Build and run

```sh
make app
open build/WritersGuild.app
```

`make app` installs the exact npm lockfile, bundles the editor locally, builds the Swift package, creates an ad-hoc-signed `.app`, and copies its SwiftPM resource bundle. No Xcode project generator or non-Apple Swift dependency is required. You can also open `Package.swift` in Xcode after building the editor assets.

For development without packaging:

```sh
cd Editor
npm ci
npm run build
cd ..
swift run WritersGuild
```

By default the library is under `~/Library/Application Support/Writers Guild/`. **Add / Open → Open Library Folder** selects another library. An empty folder starts with the Greyhaven fixture. Use **New World** for your own setting.

```sh
build/WritersGuild.app/Contents/MacOS/WritersGuild --library /absolute/path/to/library
```

## Try the grounded vertical slice

1. Open **Greyhaven → The Homecoming → The road to Old Town** (Chapter 5).
2. Choose **Let the Guild Read** (`⌘⇧R`). Deterministic checks also run after two seconds of settled text.
3. Click a highlighted passage or an observation. Open its evidence links to see the prior scene, lore, or canonical entity.
4. Inspect **The new insignia** (Chapter 4), **A key entrusted** (Chapter 2), and **The south stair** (Chapter 1). They establish rank, ownership, and location.
5. Open **World State** in Chapter 5: Jonas's `knowledge.brothersKiller` is false. In Chapter 8 it is true. The flashback appears later in presentation but uses story time 2. **The Quiet Watch** does not inherit The Homecoming's events.
6. **Useful**, **Dismiss**, and **Intentional** record feedback, not prose edits. Give repeated style feedback, then **End Session**. Inspect the resulting episodes, tentative beliefs and effective pattern threshold in **Guild Hall**.
7. **Quiet Time** hides Guild annotations/inspector and defers automatic reviews; writing and saving continue.

### Write your own world

- **Add / Open** creates worlds, stories and lore. Each story's sidebar has **New scene**.
- **Lore** edits writer-owned Markdown. Agents cannot modify it.
- **World State** adds entities/aliases, canonical facts cited to exact lore quotes, and explicit story events cited to exact current-scene quotes.
- Relationship values are stable entity IDs shown in World State. Examples: `rank = Corporal`, `owner = elise`, `location = south-exit`, `southOf = old-town`, `knowledge.brothersKiller = true`.
- Review-produced claims remain unestablished until you choose **Establish as event**. Accepting a critique does not accept a claim.
- Scene presentation order, chronological time, and story world-time offset are separate controls. Moving a scene's time also moves its writer-established events.

You do **not** need to import all your lore before writing or reviewing. For continuity in a new world, add the relevant entities/aliases and establish the facts or earlier events you want checked. Lore Markdown is not automatically converted into structured canon. Known entities can produce pending claims without existing lore; without registered entities, semantic continuity has no subjects to ground and returns no findings. Deterministic text checks remain available.

Semantic review retrieves required context in Swift before generation. The model cannot invent entity references, citation IDs, or UTF-16 offsets: entity/passage choices are constrained, and Swift attaches actual stored evidence and text anchors. This guarantees reference provenance, **not semantic correctness**. The small local model can still misinterpret prose, raise false concerns, or extract incorrect claims. Inspect the evidence before choosing **Establish as event**.

## Tests

```sh
cd Editor
npm ci
npx playwright install chromium webkit
npm run typecheck
npm test
cd ..
swift test
```

Run native tests in a graphical session, without `swift test --parallel`. The native editor tests use an actual WKWebView. Browser tests use actual Wordgard in Chromium and WebKit. Swift domain tests cover temporal isolation, provenance, claims, acceptance fixtures, anchors, cancellation, persistence failure safety, and memory adaptation.

The opt-in native integration scenario uses a disposable library and the actual app window. Run it twice: the first process edits, reviews, records feedback, consolidates a semantic style belief and verifies its changed threshold, creates a world/two stories/scenes/lore, establishes a new character's promotion, and catches a later rank mistake with that event as evidence. The second verifies process-restart persistence.

```sh
build/WritersGuild.app/Contents/MacOS/WritersGuild --library /tmp/writers-guild-smoke --smoke-test
build/WritersGuild.app/Contents/MacOS/WritersGuild --library /tmp/writers-guild-smoke --smoke-test
```

It writes `smoke-result.json` and an actual WKWebView `editor-native.png` snapshot into that disposable folder. Use a new empty path to repeat the first phase.

Verified with the installed toolchain: 63 native tests (30 XCTest + 33 Swift Testing), 14 browser cases across Chromium/WebKit, actual Foundation Models reviews of Greyhaven, and the native app smoke/reopen scenario with semantic review enabled. The WKWebView snapshot visually verifies the actual writing surface. Full desktop screenshot/accessibility automation requires macOS permissions not granted in this environment.

## Storage and recovery

`library.sqlite3` holds indexed, versioned structured records plus FTS5. `sources/manuscripts/<sceneID>/` holds immutable HTML and plain-text revisions. `sources/lore/<loreID>/` holds immutable Markdown. The database points to the committed revisions; old revisions remain recoverable. Saves stage and synchronize source files before committing database references. Corruption, unsupported schema versions, and conflicting independent writers fail explicitly instead of resetting the library.

Manuscripts are **portable semantic HTML, not Wordgard JSON**. Supported semantics: paragraphs, headings, bold/italic, lists, blockquotes and line breaks. Markdown is used for lore; rich manuscripts deliberately use HTML to avoid destructive Markdown conversions. Back up the entire library folder, including SQLite sidecars while the app is running. For the simplest consistent filesystem backup, quit the app first. Do not edit internal source revision files in place: checksums detect corruption.

## Current limits

- English deterministic heuristics are intentionally conservative, not general narrative understanding. Rank syntax, directional travel, and possession patterns are bounded; ambiguous phrasing requires semantic review or explicit writer-established events.
- Apple semantic review is operational on compatible systems, but remains fallible. Real-model verification caught false positives and incorrect extracted claims as well as correctly cited rank discrepancies; grounded references are not a truth guarantee.
- Local reviews cover a scene, not a novel-wide semantic audit. Extraction is bounded to 1,200 UTF-16 units, eight relevant/related entities, and three state properties per entity. Comparison sessions run only for extracted static conflicts or repeated transitions and use state immediately before the mentioning paragraph. No whole novel or lore document is sent to a session.
- Changing text makes active observations obsolete; unchanged quotes can relocate by context, but ambiguous/deleted passages are not guessed. Recorded event evidence remains historical when its source changes.
- Canonical facts and events are explicit structured entries, not automatically synchronized interpretations of edited lore. Updating lore alone does not silently change a previously established structured fact; review its structured entry too.
- One app workspace/window; no collaboration or synchronization. The repository is not an App Store/notarized release.
- Source revisions and historical review records are retained; automatic compaction is not implemented.
- No arbitrary HTML import, links, images, tables, DOCX fidelity, publishing, or cloud storage.

See [Architecture](docs/ARCHITECTURE.md), [Domain](docs/DOMAIN.md), and [Decisions](docs/DECISIONS/001-native-boundaries.md).

## Agent workflows

Portable planning and contribution skills are adapted from sibling `strategy-game`. Edit the canonical sources in `.agents/skills/` and `.agents/commands/`; `.claude/skills` and `.claude/commands` are relative symlinks to those directories, so no generation or sync command is needed.

| Skill | Use |
| --- | --- |
| `wayfinder` | Large, uncertain efforts: a GitHub planning map with native child decision issues and blocking relationships |
| `grilling` | Stress-test a plan in question rounds; decisions remain with the human |
| `domain-modeling` | Sharpen language in `docs/DOMAIN.md` and record consequential decisions in `docs/DECISIONS/` |
| `research` | Bounded, cited investigations |
| `prototype` | Throwaway native UI or logic experiments; technical smoke is separate from human design approval |
| `to-spec` | Publish agreed decisions as an implementation-spec issue, without starting implementation |
| `git-workflow` | Issue-linked branch, commit, and PR naming; mutation safety and surface-appropriate verification |
| `pr` | PR bodies with Summary, Evidence, and Merge Danger |
| `test-quality` | Behavior-focused Swift, native WKWebView, and embedded-editor test seams |

The command entrypoints are `grill-me`, `ticket-task`, `ticket-task-lite`, `triage-issue`, and `reflect`. Each also has a `source-command-<name>` skill for harnesses that discover skills rather than commands. Load a skill through the harness when available; otherwise read `.agents/skills/<name>/SKILL.md` and follow it. For example, `grill-me` loads `grilling`; authorized branch/commit/PR work loads `git-workflow` and `pr`.

Wayfinder and specs explicitly target **`AverageZ/writers-guild-native`**, using authenticated GitHub CLI operations. The installed tracker labels are `wayfinder:map`, `wayfinder:research`, `wayfinder:prototype`, `wayfinder:grilling`, `wayfinder:task`, and `ready-for-agent`. `ready-for-agent` marks a spec ready for implementation planning, not permission to execute. A simple implementation task does not need a Wayfinder map. See [tracker operations](.agents/skills/wayfinder/issue-tracker.md) for claims, dependencies, and concurrent edits.

Check a workflow-only change by exercising canonical and Claude discovery paths, resolving local skill/reference links, and querying the live tracker; do not substitute an unrelated app test run. The initial port smoke verified 14 skills, 5 commands, 30 local Markdown links, all 6 labels, and read access to GitHub's native sub-issue and blocking endpoints. Git branch/commit/PR naming was exercised by the port's own contribution workflow. Native/editor code changes still require the relevant checks and runtime scenarios above.

Upstream planning-skill attribution is retained in the skill files, with the [Matt Pocock MIT license](.agents/skills/LICENSE-matt-pocock). Gameplay skills and the source project's game-specific E2E/configuration tooling are intentionally not imported.
