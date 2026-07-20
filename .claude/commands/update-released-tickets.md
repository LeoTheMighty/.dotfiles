# Update Released Tickets

After a production release has been validated, move every AIP JIRA ticket attached to the release's PRs into **Done**. Set yourself as Tester only if the transition fails because Tester is required.

See `_jira-helpers.md` for the shared discovery routines (R1–R9) referenced below.

Arguments: `$ARGUMENTS`

The first token is OPTIONAL — a release tag to operate on. If omitted, uses the latest release in the current repo. Examples:
- `/update-released-tickets` — latest release in current repo
- `/update-released-tickets v2.34.0` — specific release tag
- `/update-released-tickets https://github.com/mycase/mc_aws_identity_center/releases/tag/v2.34.0` — full URL

---

## Phase 0: Repository & release verification

1. Verify current directory is a git repository: `git rev-parse --is-inside-work-tree`. If not, **STOP** and tell the user to run from inside a mycase repo (or pass a full release URL).
2. Run `git remote -v` and log the repo you're operating in.
3. Resolve the target release:
   - **No argument:** `gh release view --json tagName,name,body,url,publishedAt`
   - **Tag given:** `gh release view <tag> --json tagName,name,body,url,publishedAt`
   - **URL given:** parse `owner/repo` and tag; verify the current repo matches, otherwise `cd` to the correct local clone (search `~/mycase ~/code ~/src ~/repos ~/projects -maxdepth 2 -name "<repo>" -type d`). If not found, **STOP**.
4. Print the release name, tag, URL, and `publishedAt`. Ask the user to confirm this is the right release before going further. (This is a guardrail — bulk-transitioning the wrong release's tickets is the worst-case error.)

---

## Phase 1: Parse release body for PR refs

The release body usually has a "What's Changed" section listing PRs. Extract every PR reference. Handle all three forms:

```bash
BODY=$(gh release view <tag> --json body --jq .body)
```

Patterns to grep:
- Same-repo: `#NNN` — resolve via `gh pr view NNN`
- Full URL: `https://github.com/<owner>/<repo>/pull/NNN`
- Cross-repo shorthand: `<owner>/<repo>#NNN`

Build a deduplicated list of `(owner, repo, number)` tuples.

If zero PRs found, **STOP** and tell the user — the release body is probably non-standard and they should pass tickets manually (offer `/update-released-tickets` as a future enhancement that accepts a ticket list directly).

---

## Phase 2: Resolve PRs → AIP ticket keys

For each PR ref, in parallel:

```bash
gh pr view <ref-or-url> --json title,body,headRefName,url --jq .
```

For each PR:
1. Combine `title + " " + body + " " + headRefName`.
2. Apply R4 (`extract_ticket_keys`): split into `aip_keys` and `other_keys`.
3. If `aip_keys` is empty → log `"PR <url> has no AIP ticket (other keys: [other_keys] — skipped)"`.
4. If `other_keys` is non-empty → warn `"PR <url> referenced [other_keys] which are not AIP tickets — ignored"`.

Dedupe AIP keys across all PRs (one ticket may appear in multiple PRs).

If the deduped list is empty, **STOP** with a summary: which PRs had no AIP keys, and ask if the user wants to add tickets manually.

---

## Phase 3: JIRA discovery

Run once, in parallel:
- R1 `get_cloud_id` → `$CLOUD_ID`
- R2 `get_my_account_id` → `$MY_ACCOUNT_ID`

(Skip R3 `get_active_aip_sprint` — released work may be from prior sprints.)

---

## Phase 4: Per-ticket status read + confirm table

For each AIP key, fetch:

```
mcp__plugin_FDK_atlassian__getJiraIssue({
  cloudId: $CLOUD_ID,
  issueIdOrKey: "<key>",
  fields: ["status", "summary", "assignee"],
  expand: ["names"]
})
```

(Use `expand: ["names"]` on at least one issue so the Tester custom field ID can be discovered if needed in Phase 5.)

Build the confirm table:

```
Release: <release name> (<tag>)
PRs: <count>
AIP tickets found: <count>

| Key       | Summary                          | Status         | Action                |
|-----------|----------------------------------|----------------|-----------------------|
| AIP-2345  | Cherry-pick fix for callback     | In Code Review | → Done                |
| AIP-2348  | Add retry to webhook handler     | In QA          | → Done                |
| AIP-2350  | Refactor session manager         | Done           | skip (already Done)   |
| AIP-2351  | Cleanup deprecated endpoint      | In Progress    | → Done (unusual ⚠️)   |
```

Mark anything that's **two or more steps away from Done** (e.g., still "In Progress" or "To Do") with the ⚠️ — that ticket may not actually be released and is a likely human-error catch.

Ask once:

```
Proceed with transitioning the <N> non-skipped tickets to Done? [y/N]
```

If the user says no, exit cleanly. If they say yes with edits ("yes, but skip AIP-2351"), honor the exclusions.

---

## Phase 5: Execute transitions

For each ticket in the confirmed list:

1. Run R6 `transition_to(key, "done")`.
2. Handle outcomes:
   - `{result: "noop"}` → log `"AIP-XXXX already Done — skipped"`.
   - `{result: "ok"}` → log `"✓ AIP-XXXX → Done"`.
   - `{result: "error", reason: "JIRA rejected transition", errors: {Tester: ...}}` AND current Tester is empty AND target is Done:
     - Call R7 `set_tester(key, $MY_ACCOUNT_ID)`.
     - Retry R6 `transition_to(key, "done")` ONCE.
     - On retry success: log `"✓ AIP-XXXX → Done (set Tester to you)"`.
     - On retry failure: log error and add to the "ask user" list.
   - `{result: "error", reason: "no transition to done", available: [...]}` → add to "ask user" list with the available transitions printed.
   - `{result: "ambiguous", options: [...]}` → ask the user inline which to pick before moving on, OR collect and batch-ask at the end (your choice — batch is less interruption).
   - Any other error → add to "ask user" list.

Process tickets sequentially (not in parallel) — JIRA workflow changes can have side effects and serial gives cleaner error output.

---

## Phase 6: Summary

```
## Released Tickets — <release tag>

### Transitioned to Done (<count>)
- AIP-2345  Cherry-pick fix for callback
- AIP-2348  Add retry to webhook handler (set Tester to you)

### Already Done — skipped (<count>)
- AIP-2350  Refactor session manager

### Needs manual attention (<count>)
- AIP-2351  Cleanup deprecated endpoint
  Reason: JIRA rejected transition — required field 'Story Points' is empty
  Available transitions: To Do, Blocked
  Link: https://affinipay.atlassian.net/browse/AIP-2351

### PRs with no AIP ticket (<count>) — informational only
- https://github.com/mycase/mc_aws_identity_center/pull/789 (branch: chore/bump-deps)
```

If anything is in "Needs manual attention," explicitly tell the user to handle those in JIRA directly and offer to retry just those keys later.

---

## Important rules

1. **Always confirm before bulk-transitioning.** The Phase 4 confirm table is non-negotiable. A single yes/no covers all tickets at once but you must show every key + status first.
2. **Don't auto-fill any field except Tester.** If the Done transition fails for any other required field (Story Points, Resolution, etc.), surface and ask. Don't guess.
3. **Don't overwrite an existing Tester.** Only set Tester when the field is currently empty AND the transition failed because of it.
4. **Project guard.** Only touch tickets starting with `AIP-`. Other project tickets get a one-line warning and are dropped.
5. **Sprint guard relaxed.** Released work may be from prior sprints — don't filter on sprint here.
6. **Fail-soft, but verbose.** Errors on individual tickets don't stop the loop. Collect them and report at the end.
7. **Always print the JIRA URL on errors.** Manual recovery is one click away — don't make the user search.
8. **Re-runnable.** If a ticket is already Done (Phase 4 already-Done or Phase 5 noop), this skill should always skip cleanly without touching it.
