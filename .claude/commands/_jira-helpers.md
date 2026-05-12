# JIRA Helpers (shared reference)

> **Not a slash command** — this file is referenced from `/update-released-tickets`, `/code-review`, `/address-pr`, and `/push-story`. It documents the discovery routines and shared posture every JIRA-aware skill follows so behavior is consistent.

Atlassian instance: `affinipay.atlassian.net`
JIRA project we touch: `LOR` (Left on Read)
MCP tool prefix: `mcp__plugin_FDK_atlassian__<toolName>`

---

## Posture (applies to every JIRA-aware skill)

1. **Project guard** — only touch tickets whose key starts with `LOR-`. Any other key is *skipped with a warning*, never auto-transitioned.
2. **Sprint guard** — for in-flight workflow skills (`/code-review`, `/address-pr`, `/push-story`), the ticket SHOULD be in the active sprint. If it isn't, surface the discrepancy and ask before transitioning. `/update-released-tickets` skips this guard (released work may have rolled over).
3. **Idempotent transitions** — always read current status first. If already at the target, skip silently. Don't double-transition.
4. **Fail-soft on JIRA when work is already complete** — `/code-review` and `/address-pr` complete the GitHub-side work BEFORE touching JIRA. If the JIRA transition fails, log it and tell the user, but don't crash — the review/replies/push are already done.
5. **Confirm before bulk writes** — `/update-released-tickets` prints a table and asks once before transitioning N tickets at once.
6. **Never overwrite Tester** — only set Tester (a) if the Done transition fails because Tester is required and missing.

---

## Routines

### R1. `get_cloud_id` (one-shot per session)

```
mcp__plugin_FDK_atlassian__getAccessibleAtlassianResources
```

Find the resource whose `url` is `https://affinipay.atlassian.net` (or `name` is `AffiniPay`). Save its `id` as `$CLOUD_ID`. Reuse for all subsequent calls.

If no AffiniPay resource is returned, **STOP and tell the user** their Atlassian MCP session may have expired.

### R2. `get_my_account_id`

The MCP doesn't expose `myself` directly, but JQL returns the calling user's accountId in any issue assigned to them. Use a probe:

```
mcp__plugin_FDK_atlassian__searchJiraIssuesUsingJql({
  cloudId: $CLOUD_ID,
  jql: "assignee = currentUser()",
  fields: ["assignee"],
  limit: 1
})
```

Extract `issues[0].fields.assignee.accountId` → `$MY_ACCOUNT_ID`.

**Fallback:** if no issue is currently assigned, run:

```
mcp__plugin_FDK_atlassian__searchJiraIssuesUsingJql({
  cloudId: $CLOUD_ID,
  jql: "reporter = currentUser()",
  fields: ["reporter"],
  limit: 1
})
```

If both probes return zero results, prompt the user once for their accountId (rare).

### R3. `get_active_lor_sprint`

```
mcp__plugin_FDK_atlassian__searchJiraIssuesUsingJql({
  cloudId: $CLOUD_ID,
  jql: "project = LOR AND sprint in openSprints()",
  fields: ["customfield_10007"],
  limit: 1
})
```

From `issues[0].fields.customfield_10007[0]` extract `{id, name, state}`. Save as `$ACTIVE_SPRINT`.

If no open sprint exists, warn the user — `/push-story` cannot proceed without one; the others can continue but skip the sprint guard.

### R4. `extract_ticket_keys(text)` — local string parsing

Regex: `\b[A-Z]{2,}-\d+\b`. Dedupe (preserving order). Then split into:
- `lor_keys` — keys whose prefix is exactly `LOR`.
- `other_keys` — everything else (these get a warning, not silent drop, so the user knows we ignored them).

### R5. `validate_in_active_sprint(key)`

```
mcp__plugin_FDK_atlassian__getJiraIssue({ cloudId: $CLOUD_ID, issueIdOrKey: key, fields: ["customfield_10007", "status"] })
```

Check if `$ACTIVE_SPRINT.id` appears in `fields.customfield_10007` (it's an array — a ticket can sit in multiple sprints).

Return: `{in_sprint: bool, status_name: str, sprint_names: [str]}`.

Caller decides whether to warn-and-confirm or proceed.

### R6. `transition_to(key, target_name)` — **the core routine**

Target names this codebase uses: `done`, `pushback`, `code review`.

1. **Read current status**:
   ```
   mcp__plugin_FDK_atlassian__getJiraIssue({ cloudId: $CLOUD_ID, issueIdOrKey: key, fields: ["status"] })
   ```
   If `status.name` matches `target_name` (case-insensitive), return `{result: "noop", reason: "already at target"}`.

2. **List transitions**:
   ```
   mcp__plugin_FDK_atlassian__getTransitionsForJiraIssue({ cloudId: $CLOUD_ID, issueIdOrKey: key })
   ```
   Find transitions where `transition.to.name` matches `target_name` case-insensitively. (Match on `to.name`, not the transition `name`, because workflow transitions are often named after the action — "Submit for review" — while the destination is what we care about.)

3. **Resolve matches:**
   - 0 matches → return `{result: "error", reason: "no transition to <target_name>", available: [(t.name, t.to.name) for t in transitions]}`. Caller prints the available list and asks the user.
   - 1 match → use it.
   - 2+ matches → return `{result: "ambiguous", options: [(t.id, t.name, t.to.name)]}`. Caller asks the user to pick.

4. **Execute the transition:**
   ```
   mcp__plugin_FDK_atlassian__transitionJiraIssue({
     cloudId: $CLOUD_ID,
     issueIdOrKey: key,
     transition: { id: "<chosen_id>" }
   })
   ```

5. **Handle errors:**
   - **Success** → return `{result: "ok", from: <old_status>, to: <target_name>}`.
   - **400 with `errors` map** → parse the per-field errors.
     - If the only error key is `Tester` (or its custom field ID) AND target is `done` AND the ticket's current Tester is empty → call `set_tester(key, $MY_ACCOUNT_ID)`, then retry the transition ONCE.
     - Otherwise → return `{result: "error", reason: "JIRA rejected transition", errors: <error map>}`. Caller surfaces and asks.
   - Other error codes → return `{result: "error", reason: <message>}`. Don't retry.

### R7. `set_tester(key, accountId)`

The Tester field's custom field ID is **not hard-coded** — it varies by project. Discover at runtime:

```
mcp__plugin_FDK_atlassian__getJiraIssue({ cloudId: $CLOUD_ID, issueIdOrKey: key, fields: ["*all"] })
```

Look at `names` map (returned when `expand: "names"` is set on the issue payload — pass `expand=["names"]`). Find the entry whose value is `"Tester"`; its key is the custom field ID (e.g., `customfield_12345`).

Cache the discovered ID in-conversation so we don't re-discover for every ticket in a bulk operation.

Then:

```
mcp__plugin_FDK_atlassian__editJiraIssue({
  cloudId: $CLOUD_ID,
  issueIdOrKey: key,
  fields: { "<tester_custom_field_id>": { "accountId": accountId } }
})
```

If `editJiraIssue` errors, surface it — don't retry blindly.

### R8. `sync_ac(key, ac_block)` — idempotent

Used by `/update-qa-steps` to replace the Acceptance Criteria checklist in the JIRA description. `/create-story` seeds the `## Acceptance Criteria` section with a placeholder at ticket-creation time; this routine replaces its contents once the PR diff makes the real testable items obvious.

**The `## Acceptance Criteria` heading is the idempotency anchor.** No HTML comment markers — the heading itself is the contract. This matches the PR-side convention in R10.

1. Read current description:
   ```
   mcp__plugin_FDK_atlassian__getJiraIssue({ cloudId: $CLOUD_ID, issueIdOrKey: key, fields: ["description"] })
   ```
2. Replace-or-insert the AC block:
   - **If a `## Acceptance Criteria` heading exists** → replace the section (from the heading up to but not including the next `## ` heading or end of doc) with the new block (heading + checkbox list).
   - **If no AC heading exists** → append the new block at the end of the description.
   - Do not modify or reflow any other section. Preserve everything else exactly.
3. Write back:
   ```
   mcp__plugin_FDK_atlassian__editJiraIssue({
     cloudId: $CLOUD_ID,
     issueIdOrKey: key,
     fields: { description: "<new_description>" }
   })
   ```

Block format (mirrors the PR body — same heading, same checkbox shape):

```
## Acceptance Criteria

- [ ] <action sentence>. <expected outcome sentence>.
- [ ] <action sentence>. <expected outcome sentence>.
- [ ] ...
```

Note: JIRA Cloud REST API v3 uses ADF (Atlassian Document Format) for description, not raw markdown. The MCP wrapper accepts plain text and converts. If it doesn't, the call will return an error — surface it and let the user paste the AC block manually as fallback.

### R10. `sync_ac_pr(pr_number, ac_block)` — PR-side counterpart of R8

Used by `/update-qa-steps`. Same heading-as-anchor convention as R8 so the PR body and the JIRA description stay in lockstep.

1. Read current body:
   ```bash
   gh pr view <pr_number> --json body --jq .body > /tmp/pr-body.md
   ```
2. Apply the same replace-or-insert rule as R8 — find the `## Acceptance Criteria` heading and replace its section, or append if missing. Don't touch other sections.
3. Write back:
   ```bash
   gh pr edit <pr_number> --body-file /tmp/pr-body.md
   ```

**Both `/create-story` (placeholder seed at ticket creation) and `/push-story` Phase 5 (placeholder seed in PR body) write the heading + a `- [ ]` placeholder so this routine always has an anchor to find.**

---

## QA Steps style guide (READ BEFORE GENERATING QA)

QA steps are for **someone who is not the engineer**. Could be QA, could be product, could be support. Write them so any one of those people can run them end-to-end without asking "what does that mean."

### What QA steps should look like

- **Action a person performs**, in plain English, in the product. Not in code.
- **An observable outcome** they can verify by looking at the screen, not by checking logs or inspecting the database.
- One step = one verb (open / click / submit / search / refresh).
- Order: happy path first, then edge cases / error paths.
- 3–7 steps typical. Fewer is fine for tiny PRs.

### Examples — yes / no

| ❌ Don't write | ✅ Write |
|---|---|
| Trigger the `POST /webhooks/retry` endpoint with a 5xx response | Send a test webhook that fails. Confirm the retry happens automatically and you see the success state. |
| Verify the `payment_attempts` table has the new column populated | Make a payment. Open the payment's detail page and confirm the attempt history is shown. |
| Confirm the `useSessionStorage` hook returns the expected shape | Sign in, refresh the page, and confirm you're still signed in. |
| Test the migration against existing records | Open an existing case and confirm it still loads and looks normal. |
| Validate error handling for empty form submission | Try to submit the form with no fields filled in. Confirm a helpful error message appears. |
| Backend refactor — no UI change | Smoke-test the affected feature: load the page, perform the main action, confirm nothing looks broken. |

### When the change is purely internal (refactor, infra, lib upgrade)

It's fine to fall back to a smoke test framed at the user level. Examples:

- "Sign in, navigate to [feature], and run through the main flow. Confirm there are no error banners and pages load normally."
- "Open the dashboard. Confirm the data still appears the same as before."

### Avoid these terms in QA steps

- Endpoint paths, controller names, model names, function names
- Env vars, feature flags by their internal key
- "Verify the response payload"
- "Check the logs"
- "Inspect the network tab"
- "Run the test suite"
- Anything that requires opening dev tools

If the only way to verify the change is to look at logs or hit an API directly, **say that explicitly** and label the step as "engineer-only" so the QA reviewer knows to skip or get help.

### R9. `attach_pr_comment(key, prUrl, prNumber)`

```
mcp__plugin_FDK_atlassian__addCommentToJiraIssue({
  cloudId: $CLOUD_ID,
  issueIdOrKey: key,
  commentBody: `Pull Request created: [View PR #${prNumber}](${prUrl})`
})
```

Same pattern as the FDK `attach-pr-to-jira` skill.

---

## Common parsing patterns

### Extract LOR keys from a PR

```bash
gh pr view <number> --json title,body,headRefName --jq '.title + " " + .body + " " + .headRefName'
```

Then run R4 over the combined text.

### Extract PR references from a release body

```bash
gh release view <tag> --json body --jq .body
```

Then parse:
- `#NNN` (same-repo) → resolve with `gh pr view NNN`
- `https://github.com/<owner>/<repo>/pull/NNN` (full URLs) → `gh pr view <url>`
- `<owner>/<repo>#NNN` (cross-repo shorthand) → `gh pr view --repo <owner>/<repo> NNN`

Dedupe.

### Detect "Left on Read" ticket in PR title + description

```bash
TITLE=$(gh pr view <num> --json title --jq .title)
BODY=$(gh pr view <num> --json body --jq .body)
TITLE_KEYS=$(echo "$TITLE" | grep -oE '\bLOR-[0-9]+\b' | sort -u)
BODY_KEYS=$(echo "$BODY" | grep -oE '\bLOR-[0-9]+\b' | sort -u)
```

- Both empty → STOP and ask user to add a key.
- Title empty, body has keys → ask user to add to title.
- Body empty, title has keys → ask user to add to body.
- Both have keys, but they don't intersect → surface mismatch and ask which is correct.

---

## Error messaging convention

When surfacing a JIRA error to the user, always include:

1. The ticket key.
2. The action that failed (transition / edit / create / comment).
3. The full error response (JIRA error messages are usually actionable).
4. A suggested next step ("you can do this manually at https://affinipay.atlassian.net/browse/<key>").

Example:

```
✗ Could not transition LOR-2345 to Done.
  JIRA error: Field 'Story Points' is required.
  Available transitions from current status: [list]
  Manual link: https://affinipay.atlassian.net/browse/LOR-2345
```
