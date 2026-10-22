---
name: research
description: Investigate a question against high-trust primary sources and capture cited findings. Use when the user wants a topic researched, docs or API facts gathered, or reading legwork delegated to a background agent.
---

<!-- Adapted from https://github.com/mattpocock/skills/blob/5beb35b040e3de97e54fa9e386d7e42d15c295c2/skills/engineering/research/SKILL.md ; license: ../LICENSE-matt-pocock -->

# Research

Investigate the question against **primary sources**: official documentation, source code, specifications, and first-party APIs, rather than secondary write-ups. Follow every factual claim back to the source that owns it. Distinguish sourced facts from inference and unresolved questions; cite URLs or repository file locations for each claim.

## Research ownership and delegation

Scope the question inline first. Follow the local delegation policy: delegate only when its gates are met, not merely because this skill was invoked. Use a read-only `scout` for exploratory repository research when appropriate. Give it a bounded question and request cited findings, not file edits. The owning agent writes the final findings.

**If already running as a delegated agent, do not recursively spawn subagents.** Perform the assigned research directly and return cited findings to the owning agent.

When background delegation is permitted and useful, keep working on independent parts of the task while it reads. Do not wait or poll while actionable independent work remains. Reconcile the returned evidence before drawing conclusions.

## Capture the findings

Keep the findings together, with the question, answer, evidence, and remaining uncertainty. Match an existing research-note convention only when repository policy permits a Markdown artifact; do not invent a research directory or create documentation that violates the repository's documentation constraints. Otherwise return the findings directly or record them on the relevant ticket.

When invoked by Wayfinder, record the source-backed findings and any artifact location on its ticket. Research informs a planning decision; it does not authorize implementation, git mutations, or new processes.
