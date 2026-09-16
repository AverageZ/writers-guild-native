# Native boundaries and persistence

Status: accepted for the first vertical slice.

## Native macOS

SwiftUI provides navigation and inspectors; AppKit owns window lifecycle and file panels. This is not the former React/Lexical/Vite SPA. The domain is independently testable Swift. Tradeoff: macOS-only, deliberate for a personal writing environment.

## Wordgard behind WKWebView

Wordgard 0.5.2 is MIT-licensed, actively published, and provides semantic editing, history, public HTML serialization and mapped decorations. These are not provided by a simple native text view. Only `Editor` and `EditorHost` depend on its behavior; replacement requires implementing the typed manuscript/annotation boundary, not rewriting the Guild. esbuild bundles assets locally; TypeScript and Playwright are development-only dependencies. Exact direct versions and the lockfile pin the toolchain. No runtime network access is required.

Sources: https://wordgard.net/docs/guide/ ; https://wordgard.net/docs/ref/ ; https://github.com/obsidianmd/wordgard

## Manuscript representation

Portable semantic HTML is the durable manuscript format. Markdown is preferred for lore, but is not chosen for rich manuscripts because converting all supported formatting through Markdown would require a lossy mapping or another parser. HTML is standardized, inspectable and readable without the editor dependency. Wordgard's internal JSON is never the sole copy. This is an explicit tradeoff, not a claim of arbitrary HTML/DOCX import fidelity.

## Database

Use macOS SQLite through its C API. It supplies transactions, explicit migrations, indexes and FTS without a persistence-framework dependency. Structured records stay separate from human-readable source files. Immutable source revisions are staged before database references change, preserving the previous committed state if a save fails. Synchronization is not implemented.

## Model abstraction

Only GuildAI depends on Foundation Models. The provider consumes a bounded review snapshot and returns validated observations and pending claims. Evidence comes from app-owned data and temporal queries; model prose is not a citation database. No remote fallback. Missing model capability leaves deterministic review and writing intact.

The provider is verified with Xcode 26.6 / macOS 26.5 SDK and the available on-device model on macOS 26.6.2. Older SDKs remain conditionally supported without semantic inference.

Required grounding is application-owned retrieval, not optional model tool calling. A real fixture run demonstrated that prompting the model to call tools did not ensure it did so; it generated agent IDs as entity IDs and fabricated citations and offsets instead. Swift now prepares scoped evidence, guided extraction restricts reference choices, and focused comparisons receive app-selected facts and passages. Swift retains citation and anchor construction. Extraction is separate from comparison to avoid copying historical facts into current claims. This trades additional small sessions for less context and fewer model responsibilities. Semantic judgments are still fallible and require writer review.

Sources: https://developer.apple.com/documentation/foundationmodels/generating-swift-data-structures-with-guided-generation ; https://developer.apple.com/documentation/foundationmodels/managing-the-context-window
