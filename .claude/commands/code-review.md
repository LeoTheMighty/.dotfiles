# PR Code Review

Perform a thorough, structured code review of a GitHub pull request.

Arguments: `$ARGUMENTS`

The first token is the PR number (or full URL), and is OPTIONAL. Everything after is treated as **additional review focus instructions** that should be given extra weight during the review. Examples:
- `/code-review` — review the PR for the current branch in the current repo (default)
- `/code-review focus on failure tolerance in the backfill` — current branch's PR + focus instructions
- `/code-review 958` — standard review
- `/code-review 958 focus on failure tolerance in the backfill` — standard review with extra emphasis
- `/code-review https://github.com/org/repo/pull/958 check for race conditions` — URL form with focus

## Phase 0: Repository Verification (MANDATORY — before any worktree)

You MUST be inside the correct git repository before creating a worktree. Worktree creation will silently fail or error if run from the wrong directory.

1. Parse `$ARGUMENTS`: try to extract the PR number from the first token (a number or a URL containing one). If the first token is not a PR number or URL, treat ALL of `$ARGUMENTS` as focus instructions and resolve the PR from the current branch (see step 2c below). Otherwise, everything after the first token is the **focus instructions**.

2. **Determine which PR to review:**

   **2a. Full GitHub URL provided** (e.g., `https://github.com/org/repo/pull/123`):
   - Extract the `owner/repo` and PR number from the URL.
   - Run `git remote -v` to check if the current directory already matches that repo.
   - If it does NOT match (or you're not in a git repo at all), you must find and navigate to the correct local clone:
     ```bash
     # Search common locations for the repo
     find ~/mycase ~/code ~/src ~/repos ~/projects -maxdepth 2 -name "<repo>" -type d 2>/dev/null | head -5
     ```
   - `cd` into the correct repo directory and verify: `git remote -v | grep "<owner>/<repo>"`
   - If the repo cannot be found locally, **STOP and tell the user** — do not proceed.

   **2b. PR number only** (no URL):
   - Verify the current directory is a git repository: `git rev-parse --is-inside-work-tree`
   - If NOT in a git repo, **STOP and tell the user** you need either a full PR URL or to be run from inside the target repository.
   - Verify the PR exists in this repo: `gh pr view <number> --json url --jq .url`
   - If the PR is not found, **STOP and tell the user** the PR was not found in the current repo.

   **2c. No PR number/URL** (default — use current branch's PR):
   - Verify the current directory is a git repository: `git rev-parse --is-inside-work-tree`
   - If NOT in a git repo, **STOP and tell the user** you need either a PR number/URL or to be run from inside a git repo with a PR.
   - Resolve the PR for the current branch:
     ```bash
     gh pr view --json number,url --jq '"\(.number) \(.url)"'
     ```
   - `gh pr view` (no arg) automatically uses the current branch. If no PR is open for the current branch, **STOP and tell the user** they need to either open a PR first or pass a PR number/URL explicitly.
   - Use the resolved number as `<number>` for the rest of the skill.
   - **Tell the user** which PR was auto-resolved before proceeding (e.g., "Defaulting to PR #1046 for current branch `lor-2348-cherry-pick`").

3. **Confirm repo state**: Run `git remote -v` and log which repository you're operating in, so it's visible in the output.

## Phase 1: Worktree Setup (MUST succeed before any review work)

1. Enter a worktree named `pr-review-<number>` using the `EnterWorktree` tool.
2. **Verify you are inside the worktree** — this is NON-NEGOTIABLE:
   ```bash
   git rev-parse --show-toplevel
   ```
   The path MUST contain `pr-review-<number>` (e.g., `.claude/worktrees/pr-review-<number>`). If it does NOT, the worktree entry failed silently — **STOP immediately and tell the user**. Do NOT continue the review in the main repo.
3. Check out the PR branch inside the worktree: `gh pr checkout <number>`
4. Verify the checkout succeeded: `git branch --show-current`

**CRITICAL**: If ANY step in Phase 1 fails, you MUST abort the entire review. Never fall back to running the review in the main working tree — this will interfere with the user's other work.

## Phase 2: Gather All Context

Run these in parallel where possible:

### PR Metadata
```
gh pr view <number> --json title,body,headRefName,baseRefName,additions,deletions,files,commits,reviews,comments,labels,author
```

### PR Diff
```
gh pr diff <number>
```
If the diff is large, save it to a temp file and read in chunks.

### Existing Reviews & Comments
Fetch all existing review comments so you don't duplicate feedback:
```
gh api repos/{owner}/{repo}/pulls/<number>/reviews
gh api repos/{owner}/{repo}/pulls/<number>/comments
```
Note what has already been said by **other** reviewers. Do NOT re-raise issues that other reviewers have already flagged unless you have a materially different take.

### Our Own Previous Reviews (critical for continuations)
Determine your own GitHub login:
```
gh api user --jq .login
```

**IMPORTANT — use both REST and GraphQL to find our reviews.** The REST endpoint (`gh api repos/.../pulls/<number>/reviews`) can silently omit reviews that the GraphQL-backed `gh pr view` returns. Always cross-check:

1. **Primary source** — use `gh pr view` filtered to our login:
   ```
   gh pr view <number> --json reviews --jq '[.reviews[] | select(.author.login == "<our_login>") | {id, state, body, submittedAt}]'
   ```
2. **Secondary source** — also check the REST API (already fetched above):
   ```
   gh api repos/{owner}/{repo}/pulls/<number>/reviews --jq '[.[] | select(.user.login == "<our_login>")]'
   ```
3. **If either source finds reviews**, use GraphQL to get the full details including inline comments:
   ```
   gh api graphql -f query='{
     repository(owner: "<owner>", name: "<repo>") {
       pullRequest(number: <number>) {
         reviews(last: 10, author: "<our_login>") {
           nodes {
             id body submittedAt
             comments(first: 50) {
               nodes { id databaseId body path line replyTo { id } }
             }
           }
         }
       }
     }
   }'
   ```

From the combined results, collect:
- **Our review comment IDs** (for replying later)
- **Our previous findings** — extract each finding's severity, file, line, and core issue description
- **Replies to our comments** — check `in_reply_to_id` on all PR comments to find author responses to our findings
- **Commits after our review** — compare `submitted_at` of our latest review against the commit list to see what changed since we last reviewed

This data feeds into **Phase 2.5** below.

### JIRA Ticket
Extract the JIRA ticket ID from the PR title, PR body, and branch name. Look for patterns like `[A-Z]+-\d+` (e.g., `LOR-2160`, `HAL-1234`).
If found, fetch the ticket using the Atlassian MCP tool:
- Use `mcp__plugin_FDK_atlassian__getJiraIssue` with the ticket ID (and `cloudId` from `getAccessibleAtlassianResources` — see `_jira-helpers.md` routine R1).
- Extract: summary, description, acceptance criteria, story points, status
- If the tool is unavailable or fails, note this and continue without JIRA context.

### Phase 2.5b: LOR ticket check (title + description)

**This phase records ticket-hygiene findings to surface in the review — it does NOT block.** Always continue to Phase 3 afterward, regardless of outcome. See `_jira-helpers.md` for the parsing pattern.

```bash
TITLE=$(gh pr view <number> --json title --jq .title)
BODY=$(gh pr view <number> --json body --jq .body)
TITLE_KEYS=$(echo "$TITLE" | grep -oE '\bLOR-[0-9]+\b' | sort -u)
BODY_KEYS=$(echo "$BODY"  | grep -oE '\bLOR-[0-9]+\b' | sort -u)
```

Classify the outcome and set `$PR_LOR_KEYS` accordingly. In every case below, **record a finding** that will be added to the review summary under a dedicated **"Ticket Hygiene"** section (see Phase 5), then continue.

- **Both empty** → Record a **[warning]** finding: `"No LOR ticket attached to this PR — neither the title nor the description references a JIRA ticket. Please tag the PR with its LOR-NNNN key so the change is traceable to a tracked unit of work."` Include the copy-paste fix commands (`gh pr edit <number> --title "LOR-NNNN: <existing title>"` and the `--body-file -` equivalent). Set `$PR_LOR_KEYS=""` (Phase 7 will skip).
- **Title empty, body has keys** → Record a **[nitpick]** finding: `"LOR ticket [<keys>] found in description but not title. Add the key to the title for visibility."` Set `$PR_LOR_KEYS=<body_keys>` so Phase 7 can still transition the ticket.
- **Body empty, title has keys** → Record a **[nitpick]** finding: `"LOR ticket [<keys>] found in title but not description. Add the key to the description."` Set `$PR_LOR_KEYS=<title_keys>`.
- **Both have keys, no intersection** → Record a **[warning]** finding: `"LOR keys mismatch: title=[<title_keys>], description=[<body_keys>]. Confirm which ticket this PR is implementing."` Set `$PR_LOR_KEYS=""` so Phase 7 does not transition the wrong ticket. Ask the user to confirm in chat.
- **Both have keys, intersection non-empty** → No finding. Use the intersection as `$PR_LOR_KEYS`.

If the user passes a focus instruction like `skip-ticket-guard` (case-insensitive substring), skip this phase entirely (no finding, `$PR_LOR_KEYS=""`).

### Read Changed Files in Full
For every file in the diff, read the FULL file (not just the diff hunks) to understand the surrounding context. This is critical for catching issues that depend on how the changed code interacts with existing code.

For each changed file, also check:
- Are there related files that weren't changed but should have been? (e.g., tests for new code, serializers for new model fields, migration for new columns)

## Phase 2.5: Previous Review Triage

**Skip this phase if no previous reviews from our login were found.**

For each finding from our previous reviews, classify it into one of these buckets:

| Bucket | Criteria | Action in Phase 5 |
|--------|----------|--------------------|
| **Addressed** | The code was changed to fix the issue, OR the author replied explaining why it's not needed and the explanation is sound | Post a reply acknowledging the fix/explanation |
| **Partially addressed** | The fix exists but is incomplete, or the author's reply doesn't fully resolve the concern | Post a reply noting what's still open |
| **Not addressed** | No code change and no author reply, OR the author replied but the concern stands | Bump the original comment with additional context or re-raise in the new review |
| **Superseded** | The surrounding code changed enough that the original finding no longer applies | Post a brief reply noting it's moot |
| **New context** | Our original finding still applies, but new code changes add additional nuance worth mentioning | Post a reply with the additional context |

To check whether a finding was addressed:
1. Read the current state of the file+line our comment targeted
2. Check if commits after our review touched that file (use `gh pr diff <number>` against the current HEAD)
3. Read any replies to our comment

Build a **triage table** for use in Phase 5. Example:
```
| # | Finding | File | Bucket | Notes |
|---|---------|------|--------|-------|
| 1 | Task leak on exception | agent.py:374 | Addressed | Fixed in 78b46c5d with try/finally |
| 2 | Dirty flag race | agent.py:212 | Not addressed | No reply or code change |
```

## Phase 3: Semantic Chunking

Group the changes into semantically meaningful review chunks. Common groupings:
- **Database/Migration**: Schema changes, indexes, constraints
- **Models**: ORM model changes, relationships, validations
- **API/Endpoints**: Route handlers, request/response types, auth
- **Business Logic**: Core logic changes, algorithms, data flow
- **Plumbing/Wiring**: Config, dependency injection, serialization pass-through
- **Tests**: Test coverage, test quality, missing test cases
- **Infrastructure**: Docker, CI, deployment config
- **Unrelated Changes**: Changes that don't belong in this PR

Don't force changes into these exact categories; use whatever grouping makes the most semantic sense for the specific PR.

## Phase 4: Review Each Chunk

For each semantic chunk, review across four dimensions. If the user provided **focus instructions**, treat those as a fifth high-priority lens — dedicate extra scrutiny to whatever they asked for, and ensure your review explicitly addresses it even if you find no issues (state that you checked and it looks good).

### 4a. Correctness
- Logic errors, off-by-one, null/None handling
- Race conditions (especially with multiple API/worker instances)
- Transaction boundaries and atomicity
- Edge cases: empty inputs, large datasets, concurrent access
- Unique constraints with nullable columns
- Missing error handling at system boundaries

### 4b. Performance
- Missing or misaligned database indexes (especially for WHERE clauses that don't match composite index leading columns)
- N+1 query patterns
- Unnecessary data loading (loading full objects when only updating)
- Transaction scope (too broad or too narrow)
- Batch vs. single-record operations

### 4c. Acceptance Criteria Matching
- Does each JIRA AC have corresponding code changes?
- Are there code changes that go beyond the AC (scope creep)?
- Are there ACs that aren't addressed?
- If no JIRA ticket was found, evaluate against the PR description instead.

### 4d. Style & Maintainability
- Consistency with existing codebase patterns
- Naming conventions
- Appropriate abstraction level (not too much, not too little)
- Temporary/migration code clearly marked for future cleanup
- Test quality: meaningful assertions, edge case coverage, not just happy path

## Phase 5: Post the Review

### Determine Severity
Categorize each finding:
- **blocker**: Must fix before merge (correctness bugs, security issues, data loss risk)
- **warning**: Should fix, but not a merge blocker (performance concerns, missing validation)
- **suggestion**: Nice-to-have improvements (style, maintainability, test coverage)
- **question**: Needs clarification from the author
- **nitpick**: Trivial style/formatting issues

### Build Inline Comments
Map each finding to a specific file and line number in the diff. For inline comments, you need:
- `path`: relative file path
- `line`: the actual line number in the file (on the new/right side for additions)
- `side`: "RIGHT" for additions, "LEFT" for deletions
- `body`: the comment text with severity prefix

### Build Summary Body
Organize the summary by semantic chunk, with findings grouped by severity. If this is a **continuation review** (we found our own previous reviews in Phase 2.5), lead with the follow-up section. If Phase 2.5b recorded a ticket-hygiene finding, surface it in its own **Ticket Hygiene** section near the top of the summary (above the per-chunk sections) so it's visible at a glance. Structure:

```markdown
## Review Summary

<1-2 sentence overall assessment>
<If continuation: "This is a follow-up review. Previous review posted on <date>.">

### Ticket Hygiene
<Include ONLY if Phase 2.5b recorded a finding. Examples:>
- **[warning]** No LOR ticket attached to this PR — neither the title nor the description references a JIRA ticket. Please tag the PR with its LOR-NNNN key. Fix:
  ```bash
  gh pr edit <number> --title "LOR-NNNN: <existing title>"
  ```

### Previous Review Follow-up
<Include ONLY if we had previous reviews. Show the triage table from Phase 2.5.>

| # | Previous Finding | Status | Notes |
|---|-----------------|--------|-------|
| 1 | Task leak on exception | ✅ Addressed | Fixed in 78b46c5d with try/finally |
| 2 | Dirty flag race | ⚠️ Not addressed | No reply or code change — re-raised below |
| 3 | Instance attr leak | ✅ Addressed | Switched to local dict per our suggestion |
| 4 | Performance concern | ➡️ Superseded | Code path was removed entirely |

### <Chunk Name> (e.g., "Database & Migration")
- **[blocker]** Description...
- **[warning]** Description...

### <Chunk Name> (e.g., "API Endpoint")
- **[suggestion]** Description...

### Acceptance Criteria
- [x] AC 1 — addressed in <file>
- [x] AC 2 — addressed in <file>
- [ ] AC 3 — not addressed (explain)

### What looks good
- Bullet points of things done well (always include positives)
- <If continuation: explicitly call out improvements made since last review>
```

### Reply to Previous Comment Threads
**Before** posting the new review, reply to our own previous comments based on the Phase 2.5 triage:

- **Addressed**: Reply acknowledging the fix. Be specific about what commit or change resolved it. Example: `"✅ Fixed in 78b46c5d — the try/finally cleanup looks correct."`
- **Partially addressed**: Reply noting what was fixed and what remains open. Example: `"The inner try/except is good, but the dirty flag race (see new review) is still a concern."`
- **Not addressed (re-raising)**: Reply bumping the comment with any additional context. Example: `"Still outstanding — re-raised in latest review with additional detail."`
- **Superseded**: Reply noting it's moot. Example: `"Moot — this code path was removed in the latest push."`
- **New context from author reply**: If the author replied to our comment, respond to their reply directly.

To reply to an existing PR comment, use:
```bash
cat <<'PAYLOAD' | gh api repos/{owner}/{repo}/pulls/<number>/comments --method POST --input -
{
  "body": "<reply text>",
  "in_reply_to": <original_comment_id>
}
PAYLOAD
```

Post all replies before posting the new review submission.

### Post New Review via GitHub API
CRITICAL: Use `gh api` with piped JSON, NOT `--raw-field` for the comments array. The `--raw-field` flag does not handle JSON arrays correctly.

```bash
cat <<'PAYLOAD' | gh api repos/{owner}/{repo}/pulls/<number>/reviews --method POST --input -
{
  "event": "COMMENT",
  "body": "<summary body>",
  "comments": [
    {
      "path": "<file>",
      "line": <line_number>,
      "side": "RIGHT",
      "body": "<comment>"
    }
  ]
}
PAYLOAD
```

If you have more than ~15 inline comments, split into multiple review submissions to avoid API limits. Post the summary body with the first batch.

Only include **new** findings as inline comments. Do NOT re-post inline comments for issues already tracked in the "Previous Review Follow-up" table — those are handled via replies to the original comment threads.

## Phase 6: Cleanup

Exit and remove the worktree. Use `ExitWorktree` with `action: "remove"` and `discard_changes: true` (since the worktree only has the checked-out PR branch, no original work).

## Phase 7: Transition LOR ticket to Pushback

**This phase ONLY runs if Phase 5 successfully posted the new review (or successfully posted previous-thread replies, if there were no new findings). If Phase 5 failed, skip this phase — don't transition the ticket if the review didn't actually land.**

**If `$PR_LOR_KEYS` is empty** (no ticket attached, or title/description mismatch from Phase 2.5b), skip this phase. Log a one-line note: `"Skipping JIRA transition — no LOR ticket attached to PR (surfaced in Ticket Hygiene section of review)."` Do not prompt the user for a ticket key; the Ticket Hygiene finding in the review already asks the author to add one.

For each key in `$PR_LOR_KEYS` (from Phase 2.5b):

1. Run R6 `transition_to(key, "pushback")` from `_jira-helpers.md`.
2. Handle outcomes:
   - `{result: "noop"}` — already at Pushback. Log `"LOR-XXXX already in Pushback"`.
   - `{result: "ok"}` — log `"✓ LOR-XXXX → Pushback"`.
   - `{result: "error", reason: "no transition to pushback", available: [...]}` — the ticket's current status doesn't allow moving to Pushback directly (e.g., the workflow disallows Done → Pushback). Print the available transitions and ask the user. **Do not retry automatically.**
   - Any other error — print and ask.

**Fail-soft posture:** the review is already posted in GitHub. If the JIRA transition fails or the MCP tool is unavailable, log a clear warning and continue to the summary. Never roll back the review.

**Skip the JIRA transition if the user passed `skip-jira` as a focus instruction.**

## Important Rules

1. **Never duplicate existing feedback from other reviewers.** If another reviewer already flagged an issue, don't re-raise it unless you have a materially different take.
2. **Always track your own previous reviews.** If you posted a review before on this PR, you MUST triage every previous finding (Phase 2.5) and reply to your own comment threads before posting a new review. Don't leave previous threads dangling.
3. **Always include positives.** Call out what was done well. On continuation reviews, explicitly acknowledge improvements made since last review.
4. **Be specific.** Reference exact file paths, line numbers, and code snippets. Don't make vague "consider improving" comments.
5. **Assume competence.** The author likely had reasons for their choices. Frame suggestions as questions or alternatives, not commands.
6. **Prioritize signal over noise.** 3 high-signal comments are worth more than 15 nitpicks. Don't comment just to comment.
7. **Check existing indexes before claiming one is missing.** Read the full model file to see all `__table_args__` indexes before suggesting new ones.
8. **For unique constraints on nullable columns**, remember PostgreSQL treats NULLs as distinct — multiple NULLs are allowed. Only flag this if the non-NULL case is genuinely problematic.
9. **For performance claims**, verify the actual query path. A composite index with the filtered column as the Nth position CAN still be used via bitmap index scan, just less efficiently than a leading-column match.
10. **Continuation reviews are first-class.** Re-reviewing a PR after changes is not a lesser activity. The follow-up triage table and reply threads are just as important as new findings — they tell the author exactly what landed and what's still open.
11. **Respond to author replies.** If the author replied to one of your previous comments (agreeing, disagreeing, or asking for clarification), always respond. Don't leave conversations one-sided.
12. **Adapt to PR changes.** If the PR title, description, files, or base branch changed since your last review, note what changed and adjust your review scope accordingly. Don't review stale context.
