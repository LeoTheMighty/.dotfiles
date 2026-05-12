# Update QA Steps

Regenerate the non-technical **Acceptance Criteria** checklist for a PR — concrete, user-visible items derived from the diff — and sync them into BOTH the PR description and the linked LOR JIRA ticket. Idempotent — re-running replaces the existing `## Acceptance Criteria` section in place instead of stacking.

The section heading (`## Acceptance Criteria`) is the contract. `/create-story` writes a placeholder version of this section at ticket-creation time; this skill replaces its contents once the PR diff makes the real testable items obvious. Same heading, same `- [ ]` checkbox format — kept in lockstep between PR and JIRA.

Called by `/push-story` after PR creation, and runnable standalone any time the diff has meaningfully changed.

See `_jira-helpers.md` for:
- Discovery routines R1 / R2
- R8 `sync_qa_steps` (JIRA side)
- R10 `sync_qa_steps_pr` (PR side)
- **QA Steps style guide** — non-technical, smoke-test framed. Read it before generating.

Arguments: `$ARGUMENTS`

The first token is OPTIONAL — a PR number or full URL. If omitted, defaults to the current branch's PR. Examples:
- `/update-qa-steps` — current branch's PR
- `/update-qa-steps 1046` — PR 1046 in current repo
- `/update-qa-steps https://github.com/org/repo/pull/1046` — full URL
- `/update-qa-steps preview` — generate and print to console, don't write to PR or JIRA
- `/update-qa-steps 1046 preview` — same, for a specific PR

The keyword `preview` (case-insensitive) anywhere in `$ARGUMENTS` switches to read-only output.

---

## Phase 0: Resolve PR

Use the same resolution logic as `/code-review` Phase 0 (URL → number → current branch). If the current directory isn't the right repo, navigate to it; if it can't be found locally, **STOP**.

Capture: `$PR_NUMBER`, `$PR_URL`, `$OWNER/$REPO`.

---

## Phase 1: Extract LOR ticket — flag loudly if missing

This is the **"always flag if a PR is not attached to a ticket"** behavior.

```bash
TITLE=$(gh pr view $PR_NUMBER --json title --jq .title)
BODY=$(gh pr view $PR_NUMBER --json body --jq .body)
BRANCH=$(gh pr view $PR_NUMBER --json headRefName --jq .headRefName)

TITLE_KEYS=$(echo "$TITLE" | grep -oE '\bLOR-[0-9]+\b' | sort -u)
BODY_KEYS=$(echo "$BODY"   | grep -oE '\bLOR-[0-9]+\b' | sort -u)
BRANCH_KEYS=$(echo "$BRANCH" | grep -oE '\bLOR-[0-9]+\b' | sort -u | tr 'a-z' 'A-Z')
```

Decision tree:

| Title | Body | Branch | Action |
|---|---|---|---|
| has key | has key | — | OK — use the intersection of title+body as `$TICKET_KEY` |
| has key | empty | — | **⚠️ FLAG:** ticket in title but not body. Print the warning banner below. Continue with the title key but tell the user to update the body. |
| empty | has key | — | **⚠️ FLAG:** ticket in body but not title. Print warning. Continue with body key, tell user to update title. |
| empty | empty | has key | **⚠️ FLAG:** ticket in branch only. Continue with branch key. Tell the user to add it to both title and body. |
| empty | empty | empty | **🚨 LOUD FLAG (see banner).** No ticket anywhere. Ask: "Continue with PR-only update?" Default: yes (the PR-side update is still useful). |
| title and body keys disagree | — | — | **⚠️ FLAG:** title=[...] body=[...]. Ask user which to use. |

### Warning banner — printed prominently

```
═════════════════════════════════════════════════════════════════════════
⚠️  PR #<num> is not properly attached to a LOR ticket.

  Title:       <title status>
  Description: <body status>
  Branch:      <branch status>

  Fix with:    gh pr edit <num> --title "LOR-NNNN: <title>" \
                                --body-file - <<< "<body with LOR-NNNN>"

  Continuing in: <PR-only mode | with key from <where>>
═════════════════════════════════════════════════════════════════════════
```

For the "no ticket anywhere" case, this banner is mandatory and must be the most visible part of the output. Don't bury it.

---

## Phase 2: Gather diff + PR context

```bash
gh pr view $PR_NUMBER --json title,body,headRefName,baseRefName,files,additions,deletions
gh pr diff $PR_NUMBER
```

If the diff is large (>500 lines), save to a temp file and read in chunks. You don't need every line — you need to understand what the PR DOES from the user's perspective.

Also fetch the JIRA ticket (if one exists) so you can use the ticket's `summary` and any existing AC for context:

```
mcp__plugin_FDK_atlassian__getJiraIssue({ cloudId: $CLOUD_ID, issueIdOrKey: $TICKET_KEY, fields: ["summary", "description", "status"] })
```

(Run R1 `get_cloud_id` first to obtain `$CLOUD_ID`.)

---

## Phase 3: Generate non-technical Acceptance Criteria

**Read `_jira-helpers.md` § "QA Steps style guide" first.** (The guide is named "QA Steps" historically but its rules — non-technical, user-observable, smoke-test framed — apply identically to the AC checklist this skill produces.) Before writing a single item, internalize:

- An AC item is something a non-engineer can DO and VERIFY in the product.
- The action is something they can take, the outcome something they can SEE on the screen.
- No endpoint paths, no controller names, no logs, no dev tools.

### Procedure

1. Identify the **user-visible surface** of the change. Categorize each changed file:
   - UI / frontend (`.jsx`, `.tsx`, `.vue`, `.erb`, `.html`, view templates) → there's a user-facing screen to test.
   - Controller / route / endpoint touched by UI → there's an action a user takes that hits this.
   - Background job / consumer / service → the user sees the *result* somewhere (an email, a notification, a status change).
   - Pure infra / refactor / lib upgrade → smoke test the touched feature.
   - Tests / docs / lockfiles only → one item: "Smoke-test the feature touched. Confirm no regressions."
2. For each surface, write a checklist item:
   - **Action**: where to go + what to do (`"Sign in as a paying user. Open the Invoices page and click 'New Invoice'..."`)
   - **Expected**: what they should see (`"...the new invoice form opens with the client field pre-filled."`)
3. Cover the happy path first. Then add 1–2 items for the most likely edge case (invalid input, empty state, permission denied, etc.) — but only if you can describe them in user terms.
4. If you can't write ≥3 concrete user-level items, fall back to a smoke test:
   `- [ ] Smoke-test [feature]: sign in, open [page], perform [main action]. Confirm nothing looks broken (no error banners, page loads, links work).`

### Output format

```
- [ ] <Action sentence>. <Expected outcome sentence.>
- [ ] <Action sentence>. <Expected outcome sentence.>
- [ ] ...
```

GitHub-flavored markdown checkbox list. No nested bullets. No code blocks unless the user has to type something specific (rare).

### Quality bar before showing to user

Before posting/printing, audit each item against:

- [ ] Contains no internal name (function, controller, endpoint, env var, model class, file path)
- [ ] Could be done by someone who has never read the code
- [ ] Outcome is observable on screen (no "check the logs", no "inspect the DB")
- [ ] Uses concrete UI words ("button", "page", "form", "list", "banner") not abstract verbs ("trigger", "validate", "exercise")
- [ ] If a step requires a special account / role / data setup, it says so in plain English ("as an admin user", "with at least one open case")

If any item fails the audit, rewrite it before continuing.

---

## Phase 4: Build the Acceptance Criteria block

Format the items into the shared block:

```
## Acceptance Criteria

- [ ] ...
- [ ] ...
- [ ] ...
```

No HTML comment markers — the `## Acceptance Criteria` heading itself is the idempotency anchor. Hold this as `$AC_BLOCK`.

---

## Phase 5: Preview-only short-circuit

If `$ARGUMENTS` contained `preview` (case-insensitive substring):

1. Print `$AC_BLOCK` to the console.
2. Print where it WOULD be synced: `"Would update PR #<num> and JIRA <key>"` (or `"PR #<num> only — no LOR ticket attached"`).
3. **STOP.** Do not write to GitHub or JIRA.

Otherwise continue to Phase 6.

---

## Phase 6: Update PR description (R10)

```bash
gh pr view $PR_NUMBER --json body --jq .body > /tmp/pr-body-$PR_NUMBER.md
```

Apply the replace-or-insert rule, in this priority order:

1. **`## Acceptance Criteria` heading exists** → replace the section (from heading until the next `## ` heading or end of file) with `$AC_BLOCK`. This is the normal case.
2. **Legacy `## QA Steps` heading exists** (with or without `<!-- qa-steps:start/end -->` markers) → replace that section with `$AC_BLOCK`. The section is renamed to `## Acceptance Criteria` as part of the swap. Markers, if present, are dropped.
3. **Neither heading exists** → append `$AC_BLOCK` to the end of the body.

The heading is the idempotency anchor — same heading text on re-runs means in-place replacement, never stacking.

Write back:

```bash
gh pr edit $PR_NUMBER --body-file /tmp/pr-body-$PR_NUMBER.md
```

Clean up the temp file. If the edit fails, surface the error and STOP — don't proceed to JIRA if we couldn't update the PR.

---

## Phase 7: Update JIRA ticket description (R8)

**Skip this phase entirely if no LOR ticket was found** (PR-only mode from Phase 1).

For `$TICKET_KEY`:

1. Run R8 `sync_qa_steps($TICKET_KEY, $AC_BLOCK)` from `_jira-helpers.md`. Apply the same heading-based replace-or-insert rule as Phase 6 to the JIRA description: prefer existing `## Acceptance Criteria`, fall back to legacy `## QA Steps` (rename it), else append.
2. On success → log `"✓ JIRA $TICKET_KEY description updated"`.
3. On failure:
   - Print the JIRA error verbatim.
   - Print `$AC_BLOCK` to the console so the user can paste it manually.
   - Print the manual link: `https://affinipay.atlassian.net/browse/$TICKET_KEY`
   - Do NOT roll back the PR update — leave it in place.

---

## Phase 8: Summary

```
## /update-qa-steps complete

### PR
#<num>: <title>
<pr_url>

### JIRA Ticket
<key> — <summary>  (status: <status>)
https://affinipay.atlassian.net/browse/<key>

### Acceptance Criteria (synced to PR + JIRA)
<full AC block>
```

If the PR has no LOR ticket, the **JIRA Ticket** section is replaced with the warning banner from Phase 1 so the user is reminded.

---

## Important Rules

1. **Always run the no-ticket flag.** Even when the PR has a ticket on the branch but not in the description, surface a warning. The whole point of this skill is to keep PR-ticket-AC in sync.
2. **Non-technical language is non-negotiable.** Apply the Phase 3 quality bar to every item before writing. If an item uses internal jargon, rewrite it.
3. **Idempotent — heading-based.** The `## Acceptance Criteria` heading is the contract with `/create-story` and with prior runs of this skill. Re-runs locate that heading and replace from it to the next `## ` heading (or EOF). No HTML comment markers — the heading is the anchor.
4. **PR-first, JIRA-second.** PR update is the primary contract — if JIRA update fails, the PR is still updated and the user gets the AC block to paste manually.
5. **Preview mode is read-only.** No `gh pr edit`, no `editJiraIssue` — pure console output. Useful when testing the generator.
6. **Don't touch other parts of the PR or JIRA body.** Only the `## Acceptance Criteria` section. Preserve everything else exactly, including any `🤖 Generated with...` footers from earlier tools, the `## Summary` section, and any non-AC content.
7. **Don't infer permissions.** If an item needs a specific user role or data setup, say it explicitly (`"as an admin user with at least one active case..."`). Don't quietly assume the QA reviewer has those.
8. **One AC section per document.** Don't write AC into multiple sections. The single `## Acceptance Criteria` heading is the single source of truth.
9. **Migrate legacy `## QA Steps` sections.** If a ticket or PR still has the old `## QA Steps` heading (with or without `<!-- qa-steps:start/end -->` markers), rename it to `## Acceptance Criteria` and reformat its numbered items into `- [ ]` checkboxes as part of the replacement. The HTML markers, if any, are dropped — they're no longer needed.
