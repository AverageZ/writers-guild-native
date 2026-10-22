# Logic Prototype

Companion to [SKILL.md](./SKILL.md). Upstream attribution and license: [SKILL.md](./SKILL.md), `../LICENSE-matt-pocock`.

Build a small, inspectable demo that lets the human drive domain logic or state transitions through awkward cases. The question is whether the model makes sense, not whether production code is ready. For visual design questions, use [UI.md](./UI.md).

## Choose the cheapest faithful artifact

- **Pure Swift semantics:** prefer a self-contained scratch `.swift` file with concrete scenarios and labelled state output. Use an interactive action loop when human free play is needed. Reuse the installed toolchain; do not add a package dependency or pretend JavaScript validates Swift behavior.
- **Native interaction or application state:** use a small scratch SwiftUI/AppKit host, or a debug-only host following existing package conventions. A native button-driven demo is appropriate when selection, scene transitions, or application integration is part of the question. Reuse the real app host when editor bridging is involved.
- **Portable, language-independent model discussion:** one self-contained HTML file can be useful for a non-developer to open directly, provided no native or embedded-editor behavior is being claimed. Clearly label it a model simulation.
- **Wordgard-specific behavior:** exercise the actual local editor and, for native integration questions, its real WKWebView bridge. A generic HTML demo cannot establish that boundary's behavior.

Do not build a fake web UI to answer a native focus, window, persistence, or Swift semantics question. Do not introduce a new package, bundler, server, or prototype framework when a scratch artifact answers it.

## Process

### 1. State a checkable question

Show a short introduction in the artifact, not merely a source comment. Describe the model and the uncertainty being explored. Use domain language from `docs/DOMAIN.md`, not reducer jargon.

Examples of questions include whether a flashback can query earlier state without later knowledge leaking in, or whether accepting a critique is visibly distinct from establishing a story event. Scenarios are hypothetical fixtures, not permission to alter a writer's world.

### 2. Isolate the logic

Keep the model independent of its display and input mechanism. Choose the simplest faithful shape:

- A pure transition function over state and actions.
- Explicit states and legal transitions.
- A few pure functions over plain data.
- A small state-owning type when ongoing internal state is the question.

The driver invokes the model and renders the result; model logic should not reach into SwiftUI views, AppKit controls, DOM handlers, or WKWebView. In an HTML demo, isolate it in an inline script module. Portability is not authorization to ship the code.

For Swift model questions, preserve the relevant types and semantics rather than translating away the uncertainty. If isolation would require extensive app rewiring, use the existing host with disposable data rather than constructing misleading substitutes.

### 3. Build the driver

Expose:

1. **The question and assumptions.** Clearly mark fixtures and simulated outcomes.
2. **Current relevant state.** Use readable labels, including chronology, authority, provenance, or revision when relevant, rather than only raw object dumps.
3. **Free-play actions.** Buttons or a simple native/terminal action menu let the human try operations in any order. Invalid actions should visibly demonstrate the model's response rather than silently vanish. Update state output after each action.
4. **Guided walkthroughs.** Include a happy path, an awkward edge case, and an illegal action. Each walkthrough starts from a known reset state and exposes real actions step by step. Use tabs, a native picker, or named terminal scenarios as appropriate; do not introduce UI plumbing merely to satisfy a visual template.

Keep the driver simple. For an appropriate HTML artifact, use one file with inline HTML/CSS/JavaScript, no external dependencies, and no server requirement; it should open directly. For a Swift script, use the installed `swift` interpreter and provide the exact file invocation, not an invented package command. For an app-hosted artifact, use the README's actual build/run instructions and identify its prototype entry point.

Keep state in memory unless persistence is the question. When using the app, select a fresh disposable library using its documented `--library` option. Never connect experiments to the default personal library or real manuscript revisions. Simulated persistence or model inference must be labelled as such, not shown as successful integration.

### 4. Exercise and collect actual feedback

Follow repository-required technical smoke and [SKILL.md](./SKILL.md). A native app smoke needs a graphical macOS session and disposable library; a native scratch script needs exercise of its actual actions. Do not forbid runtime launch when the governing policy requires it. Respect delegated assignments that reserve verification for the integration owner.

Give the human the artifact path, exact run/open instructions, and walkthroughs. Let them free-play. “That should not be possible” or “I thought this action meant something else” is evidence about the model. Add requested scenarios within the question's scope. Do not invent feedback or infer agreement from a lack of response.

Report technical results separately from human validation. Successful execution is not evidence that the model feels right. If the human has not inspected it, explicitly leave the design verdict pending.

### 5. Capture the answer

Record the question, artifact, actual exercised behavior, real feedback, verdict, and unresolved points. When invoked by Wayfinder, record them on the ticket and return to planning. Preserve evidence only through the authorized Git workflow in [SKILL.md](./SKILL.md); otherwise report the uncommitted artifact path.

Do not automatically move logic into production. Separate implementation authorization and normal production engineering standards are required. Remove obsolete scratch integration after an authorized implementation; preserve primary-source evidence separately when appropriate.

## Anti-patterns

- A separate test suite or abstractions that turn one throwaway experiment into an implementation project. Required repository verification still applies.
- Real library writes or a real database when memory would answer the question.
- Hypothetical future features unrelated to the uncertainty.
- Mixing model logic with the driver.
- Browser simulations offered as proof of native semantics or the actual Wordgard bridge.
- Servers and frameworks for an otherwise self-contained experiment.
- Treating technical execution as human approval, or shipping the scratch shell automatically.
