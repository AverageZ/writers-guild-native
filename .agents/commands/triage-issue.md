---
description: Triage a stale GitHub issue as close, update, or replace
allowed-tools: Bash(gh issue view:*), Bash(gh issue list:*), Bash(gh label list:*)
---

Fetch the supplied issue from `AverageZ/writers-guild-native`, search related issues, and inspect the smallest code slice needed to determine whether it is resolved, relevant, superseded, or misframed. Recommend exactly one outcome: close, update, or replace.

Report evidence, related issues, and ready-to-run GitHub CLI commands explicitly targeting this repository. Search duplicates before drafting replacements and obtain actual repository labels. Do not execute mutations without human approval.
