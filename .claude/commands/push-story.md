# Push Story

Take work-in-progress (or a clean repo + an intent) and produce: a JIRA story in the LOR active sprint, a branch named after the ticket, a commit + push, a PR, and a non-technical **Acceptance Criteria** checklist mirrored in both the PR description and the JIRA ticket.

**This skill is an orchestrator.** The two riskiest pieces are delegated to dedicated skills:
- **Ticket creation** → `/create-story` (handles required-field plumbing, Investment Category / Capitalizable Project / Points / Priority heuristics, parent-epic search, retry loop)
- **Acceptance Criteria generation + dual sync** → `/update-qa-steps` (replaces the `## Acceptance Criteria` section in both the PR body and the JIRA description after the PR diff is real)

See `_jira-helpers.md` for the shared discovery routines (R1–R10).

---

## Arguments — `$ARGUMENTS`

```
/push-story [LOR-NNNN] [<summary words>] [--flag ...]
```

The first token MAY be an existing ticket key (`LOR-NNNN`). Everything else is split into:
- **Summary words** — positional tokens that aren't flags. These form the proposed summary when creating a new ticket, or are treated as extra context when an existing key is given.
- **Pass-through flags** — any `--flag [value]` is forwarded to `/create-story` verbatim. See `/create-story` for the full flag list. The flags `/push-story` recognizes for pass-through:

| Flag | Forwarded to | Effect |
|---|---|---|
| `--type <story\|bug\|spike>` | `/create-story` | Issue type override |
| `--epic <LOR-NNNN>` | `/create-story` | Explicit parent (skips auto-search) |
| `--cap-project <name>` | `/create-story` | Capitalizable Project override |
| `--category <name>` | `/create-story` | Investment Category override |
| `--points <N>` | `/create-story` | Story Points override (Fibonacci only) |
| `--priority <name>` | `/create-story` | Priority override (Highest/High/Medium/Low/Lowest) |
| `--backlog` | `/create-story` | Create in backlog instead of active sprint |
| `--description-file <path>` | `/create-story` | Use file contents as description |
| `--no-prompt` | `/create-story` | Suppress all prompts; use heuristic defaults |
| `--dry-run` | `/create-story` | Don't actually create the ticket (`/push-story` will also stop after Phase 2d) |
| `--no-transition` | (consumed here) | Skip Phase 8 — don't transition the ticket to Code Review. Useful for draft PRs or exploratory pushes. |

Flags only matter when creating a new ticket. If `LOR-NNNN` was passed, the flags are ignored (warn the user once).

### Examples

- `/push-story` — infer summary from diff; search active-sprint tickets, else delegate to `/create-story`.
- `/push-story Add retry to webhook handler` — search then create with all heuristic defaults.
- `/push-story Add retry to webhook handler --points 2 --priority High` — same, but override points and priority.
- `/push-story LOR-2345` — use existing ticket; commit diff and open PR.
- `/push-story LOR-2345 also handle the timeout case` — existing ticket + extra context (the extra context goes into commit message + PR body, not the ticket).
- `/push-story New checkout flow --type bug --cap-project "Checkout Optimization"` — bug variant on a specific cap project.
- `/push-story Refactor session manager --dry-run` — see what `/create-story` would do without actually creating anything (skill stops at the end of Phase 2d).

---

## Phase 0: Repository & state check

1. Verify current directory is a git repository: `git rev-parse --is-inside-work-tree`. If not, **STOP**.
2. Verify a github remote exists: `git remote -v | grep -i github`. If not, **STOP**.
3. Log the repo and current branch.
4. Capture current branch as `$STARTING_BRANCH`.
5. Determine the repo's default branch: `gh repo view --json defaultBranchRef --jq .defaultBranchRef.name` → `$DEFAULT_BRANCH`.
6. If `$STARTING_BRANCH` is not the default branch, ask: **branch off current branch** (stack) vs. **branch off `$DEFAULT_BRANCH`** (fresh). Default: current branch.

---

## Phase 1: Inspect working tree

```bash
git status --porcelain
git diff --stat
git diff --cached --stat
git diff
git diff --cached
```

Classify:
- `$HAS_CHANGES=true` if anything is staged or unstaged.
- `$ONLY_UNTRACKED=true` if all changes are new files.

If `$HAS_CHANGES=false`:
- Tell the user: "No working-tree changes detected. I can still create the ticket and branch, but I won't push or open a PR."
- Continue through Phase 2–3 (ticket + branch), then **STOP** before Phase 4. Print a "come back when you have code to push" message.

If `$HAS_CHANGES=true`:
- Print a diff summary (file count, lines added/removed) so the user can confirm scope before we create the JIRA ticket.

---

## Phase 2: Resolve OR create the ticket

Parse `$ARGUMENTS`:
- First positional token matches `^LOR-\d+$` → `$TICKET_KEY` = first token; remaining positional words = extra context (used in commit/PR body, NOT the ticket).
- Else → `$TICKET_KEY = null`; positional words = proposed summary.
- Either way, collect `--*` flags as `$PASSTHROUGH_FLAGS`.

If `$TICKET_KEY` is set AND `$PASSTHROUGH_FLAGS` is non-empty: warn `"Flags [<list>] are ignored when an existing LOR key is given."` and drop them.

### Phase 2a: Discovery (parallel)

- R1 `get_cloud_id` → `$CLOUD_ID`
- R2 `get_my_account_id` → `$MY_ACCOUNT_ID`
- R3 `get_active_lor_sprint` → `$ACTIVE_SPRINT` (id + name)

If `$ACTIVE_SPRINT` is empty (no open sprint), warn and ask: "Continue anyway (ticket will land in backlog)?"

### Phase 2b: Existing-ticket validation (if `$TICKET_KEY` given)

1. `getJiraIssue` for `$TICKET_KEY`. Verify project = `LOR`. If not, **STOP** with "Ticket is not in LOR."
2. R5 `validate_in_active_sprint($TICKET_KEY)`. If not in active sprint, warn (`"LOR-XXXX is in [<sprint_names>], not the active sprint. Continue anyway?"`) — ask y/N.
3. Read the ticket's `summary`, `status`, and `description` for later use.

Jump to Phase 3.

### Phase 2c: Search active-sprint tickets (if no `$TICKET_KEY`)

Per the "search first" preference, look at the user's open in-sprint tickets before offering to create:

```
mcp__plugin_FDK_atlassian__searchJiraIssuesUsingJql({
  cloudId: $CLOUD_ID,
  jql: "project = LOR AND sprint = " + $ACTIVE_SPRINT.id + " AND assignee = currentUser() AND statusCategory != Done ORDER BY updated DESC",
  fields: ["summary", "status", "updated"],
  limit: 20
})
```

Present:

```
Your open LOR tickets in this sprint:
  1. LOR-2345  In Progress     Cherry-pick fix for callback   (updated 2h ago)
  2. LOR-2350  To Do           Refactor session manager       (updated 1d ago)
  3. LOR-2351  In Code Review  Cleanup deprecated endpoint    (updated 3d ago)

Pick a number to attach this work to, or 'new' to create. Default: new.
```

- User picks a number → `$TICKET_KEY` = that key. Skip to Phase 3.
- User picks `new` (or default) → continue to 2d.

### Phase 2d: Delegate to `/create-story`

Build the invocation. The positional summary comes first; pass-through flags follow:

```
/create-story <summary words> <$PASSTHROUGH_FLAGS>
```

If `/push-story` was called with no positional summary words (i.e., the user ran `/push-story` bare with the intent of inferring from the diff), derive a one-line summary from the diff first and use that:

- Most-changed file's path component + a verb inferred from the largest hunk (add/fix/refactor/remove).
- Example: a diff dominated by `app/webhooks/retry.rb` with `+ def with_backoff` becomes `"Add backoff to webhook retry"`.
- Show the derived summary to the user before invoking `/create-story` (one-line confirm).

**Capture the returned ticket key.** `/create-story`'s Phase 7 output leads with `Key: LOR-NNNN` on its own line. Parse it from the output. Also note the `Notes:` section if present (sprint dropped, parent skipped, etc.) so the final `/push-story` summary can surface those.

**Handling `/create-story` outcomes:**

| Outcome | `/push-story` action |
|---|---|
| Success — ticket created | Continue to Phase 3 with the new `$TICKET_KEY`. |
| `/create-story --dry-run` was forwarded | `/create-story` prints the payload but doesn't create. **STOP** here — there's no ticket to branch from. Echo `/create-story`'s output as the final summary. |
| 3-attempt retry exhausted | `/create-story` printed the full failure block with a manual JIRA URL. **STOP**. Tell the user: "Ticket creation failed — create manually using the link above, then re-run `/push-story LOR-NNNN`." |
| User aborted inside `/create-story` (e.g., declined a prompt) | **STOP**. Don't branch / commit. |

---

## Phase 3: Create the branch

Compute branch name: `lor-<NNNN>-<kebab-summary>` (max 60 chars). Lowercase, replace non-alphanumerics with `-`, collapse repeats, strip trailing `-`. Matches the existing convention (`lor-2348-cherry-pick`).

The `<kebab-summary>` uses the **ticket's** summary (from `/create-story`'s output, or the existing ticket's summary fetched in 2b) — NOT the raw `$ARGUMENTS` string. This way the branch name stays in sync with whatever summary actually landed in JIRA.

1. If `$STARTING_BRANCH` is not `$DEFAULT_BRANCH` AND the user chose "branch off main" in Phase 0:
   ```bash
   git stash push -m "push-story: stash before branching to <new-branch>"
   git checkout $DEFAULT_BRANCH
   git pull --ff-only
   ```
2. Check for branch name collision (local and remote):
   ```bash
   git rev-parse --verify "refs/heads/<branch>" 2>/dev/null
   git ls-remote --heads origin "<branch>"
   ```
3. If it exists, suffix `-2`, `-3`, etc. Confirm with the user before adopting a suffix.
4. Create and check out:
   ```bash
   git checkout -b <branch>
   ```
5. If we stashed: `git stash pop`. On conflict, warn and **STOP** — let the user resolve.

If `$HAS_CHANGES=false`, this is the exit point per Phase 1.

---

## Phase 4: Commit

1. If nothing is staged, stage everything that isn't ignored:
   ```bash
   git add -A
   ```
   Then run `git status --porcelain` and **scan for sensitive paths** before committing: `.env`, `*.pem`, `id_rsa*`, `secrets/`, `*credentials*`, `*.key`. If anything matches, **STOP** and ask the user.
2. Commit:
   ```bash
   git commit -m "$TICKET_KEY: <ticket summary>" -m "$(cat <<'EOF'
   <2-3 line body derived from the diff and any extra context from $ARGUMENTS>

   Jira: https://affinipay.atlassian.net/browse/$TICKET_KEY
   EOF
   )"
   ```
3. Push:
   ```bash
   git push -u origin HEAD
   ```

---

## Phase 5: Create the PR

The PR body MUST include a `## Acceptance Criteria` section with at least one placeholder checkbox so `/update-qa-steps` (Phase 6) has a heading to anchor on when it replaces the section's contents.

**No HTML comment markers.** The `## Acceptance Criteria` heading itself is the idempotency anchor, matching the same convention `/create-story` writes into the JIRA description.

```bash
gh pr create --title "$TICKET_KEY: <ticket summary>" --body "$(cat <<'EOF'
## Summary
<1-3 sentences derived from diff + any extra context from $ARGUMENTS>

## Changes
- <bullet per significant file/area>

## Acceptance Criteria
- [ ] (placeholder — will be filled by /update-qa-steps after this PR is open)

## Jira
- $TICKET_KEY: https://affinipay.atlassian.net/browse/$TICKET_KEY
EOF
)"
```

Capture the returned PR URL and PR number.

---

## Phase 6: Delegate Acceptance Criteria to `/update-qa-steps`

Invoke:

```
/update-qa-steps <PR_NUMBER>
```

That skill will:
- Read the PR diff + JIRA ticket.
- Generate non-technical, user-observable AC items (per the QA Style Guide in `_jira-helpers.md`).
- Replace the contents of the `## Acceptance Criteria` section in the PR body with the new `- [ ]` checklist (matching the heading we wrote in Phase 5).
- Sync the same section into the JIRA ticket description by replacing the contents of its `## Acceptance Criteria` section (the one `/create-story` seeded with a placeholder in its Phase 2).

If `/update-qa-steps` fails partway through (e.g., the JIRA edit errored), it surfaces the manual recovery info and prints the AC block to the console. **Don't roll back** — the PR is open, the ticket exists, the work is real. Include the error and the printed AC block in the final summary so the user can paste manually.

---

## Phase 7: Attach PR link as a JIRA comment

Run R9 `attach_pr_comment($TICKET_KEY, prUrl, prNumber)`.

If `addCommentToJiraIssue` fails, log the error but don't abort.

---

## Phase 8: Transition the ticket to Code Review

The PR is open, the AC is synced, the comment is attached — the ticket is now ready for review. Move it forward.

Run R6 `transition_to($TICKET_KEY, "code review")` from `_jira-helpers.md`.

Handle outcomes:
- `{result: "noop"}` — already in Code Review. Log `"LOR-XXXX already in Code Review"`. Common when re-running `/push-story` on a ticket that came back from Pushback.
- `{result: "ok"}` — log `"✓ LOR-XXXX → Code Review"`.
- `{result: "error", reason: "no transition to code review", available: [...]}` — the workflow doesn't allow Code Review from the ticket's current status. Print the available transitions and surface the issue. Do not auto-pick. Common cause: ticket sits in a non-standard state (Blocked, On Hold) that doesn't directly transition to Code Review.
- `{result: "ambiguous", options: [...]}` — multiple transitions land in Code Review. Ask the user which to use.
- Any other error — print verbatim and surface.

**Fail-soft posture.** Everything else is already done: branch pushed, PR open, AC synced, comment attached. A transition failure here is a warning, not a crash. Always include the JIRA link in the error so manual recovery is one click away.

**Skip when:** the user passed `--no-transition` (consume this flag in Phase 2 if present). This is for the rare case of opening a draft PR or pushing exploratory work that shouldn't move the ticket yet.

---

## Phase 9: Summary

```
## /push-story complete

### Branch
<branch-name>  (pushed to origin)

### Commit
<sha>  $TICKET_KEY: <ticket summary>

### Pull Request
<pr-url>

### JIRA Ticket
$TICKET_KEY  <summary>  (status: <status>)
https://affinipay.atlassian.net/browse/$TICKET_KEY

Type:        <type>
Priority:    <priority>
Points:      <points>
Sprint:      <sprint name or "Backlog">
Category:    <Investment Category>
Cap Project: <Capitalizable Project>
Parent:      <epic key + summary, or "(none)">

### Acceptance Criteria
<AC checklist as synced to PR + JIRA by /update-qa-steps>

### Notes
<any items from /create-story's Notes block — sprint dropped, parent skipped, label drift, etc.>
<any errors from /update-qa-steps or Phase 7 — with manual recovery instructions>
```

Restore the user to a sensible state:
- Default: stay on the new branch (most likely they want to keep coding).
- If they want to switch back to `$STARTING_BRANCH`, ask.

---

## Important Rules

1. **This skill is an orchestrator.** Don't reinvent ticket creation or AC generation here — delegate to `/create-story` and `/update-qa-steps`. When those skills evolve, this one inherits the improvements.
2. **Stop the chain on critical failures.** If `/create-story` fails (3-retry exhausted, user aborts, or `--dry-run`), don't branch / commit / push — the work has no JIRA home.
3. **Project guard.** Only LOR tickets. If passed a non-LOR key, refuse before touching the working tree.
4. **Active-sprint scope.** New tickets land in the active sprint (delegated to `/create-story` — overridable via `--backlog`). Existing tickets get a warn-and-confirm if they're in a different sprint.
5. **Search before create.** When no key is passed, run the JQL probe first. This avoids the user accidentally creating a duplicate of in-flight work.
6. **`## Acceptance Criteria` is the contract on both surfaces.** The heading IS the idempotency anchor — no HTML comment markers. `/create-story` seeds it in the JIRA description; `/push-story` Phase 5 seeds it in the PR body; `/update-qa-steps` replaces both sets of contents in lockstep once the diff is real.
7. **Flags are pass-through.** Don't try to interpret `--points`, `--priority`, etc. here — forward them to `/create-story` and let that skill handle validation. The flags `/push-story` consumes itself are `--dry-run` (stops the chain after Phase 2d) and `--no-transition` (skips Phase 8).
8. **Never auto-stage sensitive files.** The Phase 4 scan is non-negotiable.
9. **Branch name uses the ticket's summary, not `$ARGUMENTS`.** This keeps the branch in sync with whatever summary actually landed in JIRA (especially relevant when `/create-story` modified the user's input or when an existing ticket has a different summary than the extra context passed).
10. **Fail-soft after PR creation.** Once the GitHub PR is open, every JIRA error (AC sync, PR comment, transitions) is non-fatal — print manual recovery info, don't roll back.
11. **Surface `/create-story` Notes.** If `/create-story` had to drop the sprint, skip the parent, fall back on priority, etc., echo those notes in Phase 9 so the user isn't surprised by the ticket's final state.
12. **The skill is iterable.** As `/create-story`'s heuristics and `/update-qa-steps`'s AC style improve, this skill stays lean. Resist the urge to inline logic from either delegate.
