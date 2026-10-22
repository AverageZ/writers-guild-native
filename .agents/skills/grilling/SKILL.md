---
name: grilling
description: Stress-test a plan, decision, or idea through a decision-tree interview. Use when the user asks to be grilled or wants to challenge their thinking.
---

# Grilling

Ported from `strategy-game/.agents/skills/grilling/SKILL.md`.

Interview the user until you reach a shared understanding. Map the discussion as a **design tree**: each decision branches into the decisions that depend on it.

Work the tree in **rounds**. The **frontier** contains every decision whose prerequisites are settled: questions you can ask now without guessing answers you have not heard. Ask the whole frontier in one round, number each question, and give your recommended answer. Then wait for the user's answers before the next round.

Format each question like this:

```text
**Q1 — <question title>**: <question, context, and choices>

Recommended: <your recommended answer and its reason>

---

**Q2 — <question title>**: <question, context, and choices>

Recommended: <your recommended answer and its reason>
```

Word each question so “yes” accepts the recommendation, while making alternatives and trade-offs clear. A recommendation is not the user's answer. Never invent answers or treat silence as agreement.

Each answered round reshapes the tree. Settled decisions move the frontier outward and unblock dependent questions. Recompute the frontier and ask the next round. A question that depends on another still-open question belongs in a later round.

## Facts versus decisions

Finding **facts** is your job; **decisions** belong to the user. Read the relevant code, documentation, and available tool output instead of asking the user for information you can look up. Use inline investigation by default. Delegate only when the governing repository/tool rules permit genuinely independent, substantial investigation; use a read-only scout for warranted exploratory code research. Do not spawn an agent for every fact or a single small lookup.

An investigation still in flight is an unsettled prerequisite. Ask the independent frontier questions now and hold only the questions that require its result. Surface contradictions between the proposal and the actual app rather than silently choosing a version of reality.

For this project, ground questions in the native SwiftUI/AppKit application and embedded Wordgard WKWebView. Read `docs/DOMAIN.md`, `docs/ARCHITECTURE.md`, and relevant decisions in `docs/DECISIONS/` when they affect the question. Distinguish writer-authored authority, established story state, fallible agent memory, and current evidence. Do not turn critique acceptance into authorization to rewrite prose or establish story facts.

## Shared understanding

The interview is complete when the frontier is empty: every relevant branch is visited and unresolved assumptions are explicit. Summarize the agreed decisions and remaining uncertainty, and wait for the user to confirm shared understanding before acting on the plan. Interview participation is not authorization for implementation or Git mutations.

If terminology or a durable trade-off crystallizes, the `domain-modeling` skill can help record it in existing documentation. Load it through the harness Skill tool when available, otherwise `skill://domain-modeling`, then `.agents/skills/domain-modeling/SKILL.md`. Do not start a separate interview merely because this skill is being installed or ported.
