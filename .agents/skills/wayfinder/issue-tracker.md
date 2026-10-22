# Issue tracker: GitHub

<!-- Adapted from https://github.com/mattpocock/skills/blob/5beb35b040e3de97e54fa9e386d7e42d15c295c2/skills/engineering/setup-matt-pocock-skills/issue-tracker-github.md; MIT, see ../LICENSE-matt-pocock. -->

Wayfinder maps, decision tickets, and synthesized specs live in **AverageZ/writers-guild-native** GitHub Issues. Use the authenticated `gh` CLI, explicitly targeting this repository. Setup is complete; no `/setup-matt-pocock-skills` or local Markdown tracker is needed.

**PRs as a request surface: no.** Implementation PRs are separate from Wayfinder decision tickets. Do not add Factory authorization/status labels or triage labels to maps or tickets.

## Publishing specs

`to-spec` publishes a separate implementation-spec issue using the **`ready-for-agent`** label. This label means the spec is ready for implementation planning; it is not Factory execution authorization. No broader triage-label setup is required.

```sh
gh issue create --repo AverageZ/writers-guild-native --label ready-for-agent --title "<spec name>" --body-file <spec-file>
```

Use the `to-spec` template for the body and confirm test seams before publication unless already agreed. Never attach `wayfinder:*` labels, `agent:run`, or workflow/status labels to the spec automatically. A spec is not a child decision ticket: keep it outside the map's frontier. For a Wayfinder handoff, put a named map link in the spec's Further Notes, then re-read the map and add the named spec link to Destination without overwriting concurrent edits.

Verify the returned issue with `gh issue view <spec-number> --repo AverageZ/writers-guild-native --json title,body,labels,url` and return its named link. Publishing does not authorize implementation.

## Wayfinding operations

### Maps and tickets

- Create a map: `gh issue create --repo AverageZ/writers-guild-native --label wayfinder:map --title "<map name>" --body-file <body-file>`. Use the Destination / Notes / Decisions so far / Not yet specified / Out of scope body from Wayfinder.
- Create a ticket: `gh issue create --repo AverageZ/writers-guild-native --parent <map-number> --label wayfinder:<type> --title "<question name>" --body-file <body-file>`. The body holds its Question; the type comes from its label, not prose. Each ticket has exactly one type label.
- Attach an existing ticket: `gh issue edit <map-number> --repo AverageZ/writers-guild-native --add-sub-issue <ticket-number>`.
- Read an issue and its resolution comments: `gh issue view <number> --repo AverageZ/writers-guild-native --json number,title,body,labels,assignees,state,comments,url`.
- Find maps: `gh issue list --repo AverageZ/writers-guild-native --state open --label wayfinder:map --limit 100 --json number,title,url`. Paginate with the API if more than 100 maps exist; never treat a truncated result as complete.

GitHub native sub-issues define membership. Do not maintain a second list of open tickets in the map body. Link maps and tickets by title in human-facing text, not bare numbers. Use the actual created issue numbers when wiring cross-references; never publish placeholder numbers.

### Blocking

Create all tickets first, then wire dependencies in a second pass:

```sh
gh issue edit <blocked-ticket-number> --repo AverageZ/writers-guild-native --add-blocked-by <blocker-ticket-number>
```

This is GitHub's native, UI-visible dependency relationship, not a Markdown checklist or a `Blocked by` body line. For API access, `POST repos/AverageZ/writers-guild-native/issues/<blocked-ticket-number>/dependencies/blocked_by` takes `issue_id`: the blocker's numeric **database ID**, obtained with `gh api repos/AverageZ/writers-guild-native/issues/<blocker-ticket-number> --jq .id`. It is neither the issue number nor the GraphQL node ID.

Read blockers with `gh api --paginate repos/AverageZ/writers-guild-native/issues/<ticket-number>/dependencies/blocked_by`. A ticket is unblocked only when every blocker is closed. `issue_dependencies_summary.blocked_by` counts open blockers; `total_blocked_by` includes closed blockers and is not the frontier gate.

### Frontier and claims

Query **all native children of this map**, preserving their returned order. Do not use a repository-wide label query to choose a ticket: another map can have identically labelled tickets.

```sh
gh api --paginate repos/AverageZ/writers-guild-native/issues/<map-number>/sub_issues \
  --jq '.[] | select(.state == "open" and (.assignees | length) == 0 and .issue_dependencies_summary.blocked_by == 0) | {number, title, html_url}'
```

The first result is the next frontier ticket. Before claiming, re-read the issue's state, assignees, and dependency summary with `gh api repos/AverageZ/writers-guild-native/issues/<ticket-number>`. Skip closed, assigned, or blocked tickets; do not steal another session's claim. If the dependency summary is absent, explicitly read blockers and check their states rather than treating missing data as zero.

Claim as the session's **first write**, before investigation or conversation:

```sh
gh issue edit <ticket-number> --repo AverageZ/writers-guild-native --add-assignee @me
```

Verify the assignee after the write. Assignment is a shared convention, not an atomic lock: if a concurrent claimant appears, stop work on that ticket and coordinate with them. An empty frontier with open children means blocked or claimed, not a completed map. Revisit Not yet specified before declaring the destination clear.

### Resolution and concurrent map edits

1. Post the answer: `gh issue comment <ticket-number> --repo AverageZ/writers-guild-native --body-file <resolution-file>`.
2. Close the ticket: `gh issue close <ticket-number> --repo AverageZ/writers-guild-native --reason completed`.
3. Re-read the map immediately before editing its body, preserve other sessions' updates, and append a named link plus one-line gist to Decisions so far. The ticket's resolution comment owns the detail.
4. Create newly specifiable tickets and wire their dependencies, then remove only their graduated fog from Not yet specified.

For a ticket ruled beyond the destination, explain why, close it with `--reason "not planned"`, and put its named link and scope rationale in Out of scope, not Decisions so far. A HITL ticket requires the real human exchange; never invent the human's answers.

If a native sub-issue or dependency operation is unavailable or unauthorized, report the exact GitHub failure. This repository uses native relationships: do not silently replace them with body conventions or a local tracker.

## Labels

These `wayfinder:*` labels are reserved for Wayfinder and are the **only** labels its maps and tickets carry. Do not apply them to ordinary implementation issues, specs, or PRs.

| Label | Purpose |
| --- | --- |
| `wayfinder:map` | Planning map and decision index |
| `wayfinder:research` | AFK primary-source investigation |
| `wayfinder:prototype` | HITL throwaway artifact for a design decision |
| `wayfinder:grilling` | HITL decision conversation with domain modeling |
| `wayfinder:task` | Manual prerequisite that unblocks a decision |

Skills named in an individual map's Notes are effort-specific; load the installed skill or report the missing prerequisite before proceeding.
