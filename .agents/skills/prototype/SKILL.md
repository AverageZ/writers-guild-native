---
name: prototype
description: Build a throwaway artifact to answer a design question about native UI, embedded editing, domain logic, or state transitions, then collect actual human feedback.
---

<!-- Adapted from https://github.com/mattpocock/skills/blob/5beb35b040e3de97e54fa9e386d7e42d15c295c2/skills/engineering/prototype/SKILL.md ; license: ../LICENSE-matt-pocock -->

# Prototype

A prototype is **throwaway code that answers a question**, not production implementation. The question determines its shape.

## Pick the question

- **“Does this logic or state model feel right?”** → [LOGIC.md](./LOGIC.md). Prefer a small native scratch artifact for Swift semantics or app-specific behavior. A self-contained HTML demo is appropriate only when browser-independent domain exploration or embedded-editor behavior is genuinely the question.
- **“What should this look like?”** → [UI.md](./UI.md). Explore structurally different native variants with a preview or prototype-only native selector. Exercise Wordgard in the actual WKWebView when the question crosses that boundary.

Infer the shape from the user's question and surrounding code; state the assumption visibly in the artifact. Ask if genuine ambiguity would materially change the experiment. Never invent user answers or a preferred design verdict.

## Shared rules

1. **Clearly throwaway.** Place an unmistakably named scratch artifact near the module or native surface it explores. Follow the actual directory and build conventions; do not introduce a new framework, routing system, or permanent prototype infrastructure.
2. **Easy human inspection.** Use existing README instructions: `make app`, then `open build/WritersGuild.app`, or open `Package.swift` in Xcode after preparing the editor assets as documented. Provide the exact artifact, preview, or in-app entry point. Do not invent npm scripts, browser routes, or unsupported launch flags.
3. **Safe data.** Prefer memory. If running the real app, use a fresh disposable library via the documented `--library /absolute/path/to/library` option or **Add / Open → Open Library Folder**. Never experiment on the default personal library or production data. A persistence question may use explicit scratch files/database inside that disposable library.
4. **Minimal engineering, not waived safety.** Avoid production polish, speculative abstractions, and a separate prototype test suite. Keep only the safeguards that make the experiment usable. Honor required repository checks, technical smoke, and normal safety rules; throwaway status does not waive them.
5. **Visible state.** Show the relevant state after every logic action or variant switch. Label fixtures and simulated results honestly. Do not present fake persistence, model inference, or editor integration as working behavior.
6. **Technical smoke is not a design verdict.** Follow repository-required verification and runtime smoke policy, using a graphical macOS session and disposable data for the app. Exercise the relevant artifact/path when required and record what actually ran. A successful launch, screenshot, or automated walkthrough proves only that exercised behavior; only actual human feedback can settle whether a design feels right. If human inspection is pending, say so. Report environmental blockers precisely rather than claiming success. Delegated workers still obey their assignment's prohibition on mid-flight verification; the integration owner performs the required smoke.
7. **Capture evidence without automatic cutover.** Record the question, artifact path, exercised checks, actual human feedback, verdict, and unresolved issues. When invoked by Wayfinder, put the artifact and decision on the ticket and return to planning. Prepared code is not a validated answer. A selected direction does not authorize production implementation; obtain separate explicit authorization before changing production behavior or promoting prototype code.

## Git and artifact capture

Before any branch creation, commit, or push, load and follow `git-workflow`: harness Skill tool when available, otherwise `skill://git-workflow`, then `.agents/skills/git-workflow/SKILL.md`. Skill invocation is not Git authorization. Follow the applicable local workflow and explicit user permissions.

If an authorized throwaway branch is needed, use the branch convention in that workflow and a real ticket number where required. Never invent a ticket or silently mutate Git to preserve the artifact. Without authorization, leave the artifact uncommitted and report its path. Do not create a PR solely for throwaway artifacts unless the user explicitly requests one under the applicable workflow.

When authorized, preserve primary-source variants and walkthroughs on the throwaway branch and link the branch plus artifact path from the ticket. Capture the answer even if Git is unavailable. Later, separately authorized implementation must apply normal production standards and remove obsolete prototype integration; it must not blindly ship exploratory code.
