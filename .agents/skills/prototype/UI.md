# UI Prototype

Companion to [SKILL.md](./SKILL.md). Upstream attribution and license: [SKILL.md](./SKILL.md), `../LICENSE-matt-pocock`.

Generate several **structurally different** variants of a native surface. Let the human compare them and choose a direction or combination; the alternatives remain throwaway evidence. For state-model questions, use [LOGIC.md](./LOGIC.md).

Read the existing UI code, `docs/ARCHITECTURE.md`, and relevant native-boundary ADRs before designing. SwiftUI/AppKit owns the application; Wordgard is embedded in WKWebView, not a standalone web application. Follow existing views, controls, accessibility, window, focus, and editor-host conventions. No additional design skill is a prerequisite.

## Choose the host

Judge designs against realistic navigation, inspector space, manuscript length, and data density. Default to variants inside the existing native host when plausible.

### A. Existing surface (preferred)

Keep the existing view model/data preparation and swap only the presentation subtree in a clearly marked prototype-only path. Use an existing development mechanism, an isolated SwiftUI preview host, or a debug-only native selector following local conventions. Do not assume a prototype mechanism already exists: inspect first. `#if DEBUG` can isolate new Swift prototype integration without creating a runtime configuration subsystem.

### B. New native surface

When no sensible host exists, use an unmistakably named scratch SwiftUI view or AppKit window/controller near the relevant code, with a disposable preview or debug-only entry point. Explain why embedding in an existing surface would hide the question. Do not add a permanent navigation destination just to compare designs.

SwiftUI previews are useful for layout and fixture states, but do not claim they prove window lifecycle, keyboard focus, persistence, or the real editor bridge. An editor-related question needs the actual Wordgard host in WKWebView, not a fake text area or screenshot substituted for integration.

## Process

### 1. State the question

Default to three variants, no more than five. Record a one-line plan in a top-of-file comment and show the question in the prototype host, for example: “Compare three observation-inspector layouts beside a long manuscript.” Describe assumptions and fixture data clearly.

### 2. Generate different directions

Use clear names such as `PrototypeVariantA` and descriptive labels. Differences must concern layout, hierarchy, density, or primary affordance—not merely color or copy. Three slightly different card stacks are not three directions. If drafts converge, impose a structural constraint on one.

Use realistic read-only data or explicitly named in-memory fixtures. For actual app interaction, launch against a fresh disposable library; never modify the writer's working library. An empty library starts with the documented Greyhaven fixture. Preserve the distinction between displaying a critique and authorizing edits or established story state.

### 3. Make comparison simple

For layout-only exploration, named SwiftUI preview variants may suffice. For live interaction, use one small prototype-only native control, such as a labelled `Picker`, to switch variants within the same host. Keep relevant scene/selection data stable between variants and display the current variant and meaningful state. State resets should be explicit.

Keep the control visually separate from the design under evaluation and out of production using the repository's actual development convention or compile-time debug gate. Avoid permanent shared infrastructure. Do not use URL query parameters or introduce a browser router.

Do not intercept manuscript arrow keys, typing, undo, or standard AppKit shortcuts for switching. Native buttons or a picker avoid stealing Wordgard's focus and selection. If comparing editor integration, inspect selection, input focus, annotations, and keyboard interaction in the actual app rather than assuming preview parity.

### 4. Exercise and hand over

Follow the technical smoke policy in [SKILL.md](./SKILL.md); do not prohibit runtime exercise required by the repository. Read the current README for commands. The documented packaged path is `make app`, followed by launching the built app. For isolated data, use:

```sh
build/WritersGuild.app/Contents/MacOS/WritersGuild --library /absolute/path/to/fresh-disposable-library
```

Use a genuinely fresh scratch path, not the default personal library. Give the human the artifact path, preview or exact in-app entry point, variant labels, and applicable documented command. Do not invent preview tooling or launch flags. Record actual technical smoke separately from pending human feedback.

The human decides whether the design works. “The hierarchy from B with the compact inspector from C” is useful evidence. Do not equate a built app, screenshot, or automated click with a human design verdict.

### 5. Capture the answer without automatic implementation

Record the question, variants, observed feedback, selected direction or combination, reasons, and outstanding uncertainty. When invoked by Wayfinder, record these on the ticket and return to planning. Preserve artifacts according to [SKILL.md](./SKILL.md) and the authorized Git workflow.

Selecting a winner does not authorize production changes. After separate implementation authorization, implement the chosen direction properly under normal engineering requirements and remove obsolete variants, selectors, preview-only scaffolding, and debug navigation integration. Do not simply promote throwaway code.

## Anti-patterns

- Color/copy-only variation or excessive shared layout that defeats comparison.
- Web mockups for native navigation, focus, or window questions.
- Substituting a fake editor when WKWebView behavior is the question.
- Writes to real libraries, lore, manuscripts, or structured world state.
- Claiming technical smoke settles the design, or inventing human feedback.
- Automatic production promotion or abandoned prototype paths in production.
