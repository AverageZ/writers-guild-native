---
name: to-spec
description: "Turn the current conversation into a spec and publish it to the project issue tracker: no interview, just synthesis of what you've already discussed."
disable-model-invocation: true
---

<!-- Adapted from https://github.com/mattpocock/skills/blob/5beb35b040e3de97e54fa9e386d7e42d15c295c2/skills/engineering/to-spec/SKILL.md; MIT, see ../LICENSE-matt-pocock. -->

This skill takes the current conversation context and codebase understanding and produces a spec. Do NOT interview the user; just synthesize what you already know.

## Repository integration

Read [the configured GitHub tracker](../wayfinder/issue-tracker.md#publishing-specs). Specs are separate GitHub issues in `AverageZ/writers-guild-native`, labelled `ready-for-agent`; they are not Wayfinder maps or decision children. Setup is complete: do not run a setup wizard, create a local tracker, or add Factory authorization labels.

Use the harness's Skill tool when available. Otherwise read `skill://<name>` if supported, or `.agents/skills/<name>/SKILL.md`.

When synthesizing a Wayfinder map, read its Destination, Notes, Decisions so far, and remaining fog, then follow the named decision links needed for the spec. Preserve settled decisions and their provenance; do not invent answers to open questions. If an essential decision is still unresolved, identify that gap rather than publishing it as ready for implementation. Link the published spec back from the map, but do not relabel the map or turn the spec into a decision ticket. Publishing a spec does not authorize implementation.

## Process

1. Explore the repo to understand the current state of the codebase, if you haven't already. Use the domain vocabulary in `docs/DOMAIN.md`, respect the boundaries in `docs/ARCHITECTURE.md`, and read relevant ADRs in `docs/DECISIONS/`, including `001-native-boundaries.md` for native/editor or persistence changes. This repository has no root glossary; do not introduce a second domain-doc convention or create empty files.

2. Load `test-quality` before sketching test seams. Prefer existing production boundaries and the **narrowest sufficient layer**, as repository policy requires, rather than defaulting to the highest seam. Name observable post-action behavior and the plausible regression or no-op each test must catch. Add a broader layer only for a distinct coordination or browser contract.

For this SwiftUI/AppKit application, separate Swift domain and persistence behavior, native `EditorHost`/WKWebView bridge and lifecycle coordination, and the embedded Wordgard editor's browser contracts. Use focused Swift tests for domain/persistence behavior; native integration coverage for typed bridge messages, document loading/export, scene switching or termination/save coordination; and editor Playwright coverage in Chromium and WebKit for browser behavior such as editing, selection, annotations and HTML round trips. A browser test alone cannot establish AppKit/WKWebView lifecycle correctness, and a native smoke test is not a substitute for a focused editor contract. Choose only the layers relevant to the agreed change. Follow the README's graphical-session and nonparallel requirements for Swift tests and its native app smoke guidance; consult `test-quality` and existing tests for the exact seams, not a game E2E DSL or browser-routing convention. This planning skill does not authorize running checks contrary to repository instructions.

Check with the user that these seams match their expectations unless already agreed in the conversation or resolved map decisions. This is a focused confirmation, not a new design interview; never fabricate user approval.

3. Write the spec using the template below, then publish it using the configured tracker's "Publishing specs" operations. Apply `ready-for-agent` to the spec issue only; no additional triage is needed. Return the issue's named link. Keep the spec on GitHub rather than creating a repository reference that restates inferable implementation behavior.

<spec-template>

## Problem Statement

The problem that the user is facing, from the user's perspective.

## Solution

The solution to the problem, from the user's perspective.

## User Stories

A LONG, numbered list of user stories. Each user story should be in the format of:

1. As an <actor>, I want a <feature>, so that <benefit>

<user-story-example>
1. As a writer, I want observations anchored to the manuscript passage they describe, so that I can review the critique in context.
</user-story-example>

Cover every agreed aspect of the feature without inventing requirements or padding the list with duplicate stories.

## Implementation Decisions

A list of implementation decisions that were made. This can include:

- The modules that will be built/modified
- The interfaces of those modules that will be modified
- Technical clarifications from the developer
- Architectural decisions
- Schema changes
- API contracts
- Specific interactions

Do NOT include specific file paths or code snippets. They may end up being outdated very quickly.

Exception: if a prototype produced a snippet that encodes a decision more precisely than prose can (state machine, schema, type shape), inline it within the relevant decision and note briefly that it came from a prototype. Trim to the decision-rich parts, not a working demo, just the important bits.

## Testing Decisions

A list of testing decisions that were made. Include:

- A description of what makes a good test (only test external behavior, not implementation details)
- Which modules will be tested, at which native or editor seam, and why that is the narrowest sufficient layer
- Observable post-action outcomes and the plausible regression or no-op each test must catch
- Prior art for the tests (i.e. similar types of tests in the codebase)
- Any distinct native WKWebView coordination or editor browser contract that requires a broader layer

## Out of Scope

A description of the things that are out of scope for this spec.

## Further Notes

Any further notes about the feature.

</spec-template>
