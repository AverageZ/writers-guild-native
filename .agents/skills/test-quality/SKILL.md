---
name: test-quality
description: Choose and review behavior-focused Swift, native WKWebView, and editor browser tests at the narrowest sufficient boundary
---

# Test Quality Workflow

Adapted from `strategy-game/.agents/skills/test-quality` for Writers Guild.

Use before writing, changing, auditing, or reviewing tests, including test seams proposed by `to-spec`. Follow repository policy and [documented commands](../../../README.md#tests); do not import strategy-game's React, saga, game DSL, or coverage infrastructure.

## Validity gate

A permanent test must detect a plausible consumer-visible regression in behavior, boundaries, invariants, transitions, precedence, or errors. A passing run, assertion count, or coverage percentage cannot establish that validity.

1. Read the implementation that owns the behavior and the nearest valid existing test. Legacy tests are not automatically valid precedents.
2. State **setup → production action → post-action observation**. Identify a plausible no-op, wrong boundary, or transition that the assertion must catch. The setup must not already satisfy the outcome.
3. Choose the narrowest sufficient layer below. Add a slower layer only for a distinct coordination, native host, or browser contract.
4. Act through the real production boundary. Mocks may supply external inputs; configured mock outputs and call logs do not prove domain outcomes. For persistence, read the saved data through the real storage boundary; for cancellation, observe that obsolete work cannot change the current result.
5. Run the focused test/scenario directly and observe the output. For bugs, reproduce before and confirm after when practical. Report only exercised checks.
6. Re-review the assertions against the contract and named regression after a green run. Remove invalid, duplicate, obsolete, implementation-wording, or incidental-behavior tests in the touched scope rather than re-pinning them. Never weaken checks to meet a metric.

Do not add permanent tests for wiring, forwarding, copied fixtures, source text, bare not-throw, non-empty results, incidental defaults, or preserved layout structure. Use a throwaway smoke for workflow/discovery changes or presentation refactors unless a distinct consumer-visible regression needs lasting coverage.

## Layer selection

- **Swift domain:** `Tests/GuildCoreTests` and `Tests/GuildAITests` for temporal isolation, evidence grounding, review transitions, claims, and cancellation. Use real production types and small deterministic fixtures.
- **Persistence:** `Tests/GuildPersistenceTests` with isolated disposable storage for round-trip state, revision integrity, restart behavior, and failure safety. Never touch a user's real library.
- **Native editor host:** `Tests/EditorHostTests` for WKWebView bridge, anchors, and native/editor coordination. Run in a graphical session without `swift test --parallel`.
- **Embedded editor browser:** `Editor/tests` using the existing Playwright setup for actual Wordgard interactions in Chromium/WebKit. Keep pure domain matrices at Swift layers; do not substitute browser tests for WKWebView host behavior.
- **Whole app:** the opt-in disposable-library native integration scenario in README when a change spans app coordination or process restart. Technical smoke does not replace human design feedback.

Cover distinct behavior and material boundaries, not every function or implementation branch. Do not repeat the same variant matrix at every layer. Permanent tests must be deterministic, isolated, and safe in the full suite.

## Commands and evidence

- Swift focus: `swift test --filter <test-name>`; full native suite: `swift test` in a graphical session, without `--parallel`.
- Editor types: `npm --prefix Editor run typecheck`.
- Editor focus: `npm --prefix Editor test -- <test-file>`; full browser suite: `npm --prefix Editor test`. Install pinned dependencies and browsers as described in README when needed.
- Native integration: build with `make app`, then run the documented `--library <new-disposable-path> --smoke-test` scenario and reopen against the same disposable path when restart behavior matters. Observe its actual result file and editor snapshot. Never reuse a real library.

Record **contract → layer → regression/no-op → post-action observation → command/result** in task/review notes, not boilerplate in every test file. For feature/API changes, update broken contract tests; use throwaway smoke for straightforward new behavior unless an uncertain edge or user request warrants a permanent test.

Compilation and type checking establish static contracts; runtime tests establish values, effects, transitions, errors, and visible behavior. Neither replaces the other. Tests alone do not prove a significant changed surface: exercise the relevant real app, CLI, or browser path before claiming completion.
