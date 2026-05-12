# PR Self-Review (Local Only)

Perform a thorough, structured code review of a GitHub pull request — but **do NOT post anything to GitHub**. Print all findings to the console for the developer to review locally before deciding what to act on.

Arguments: `$ARGUMENTS`

The first token is the PR number (or full URL), and is OPTIONAL. Everything after is treated as **additional review focus instructions** that should be given extra weight during the review. Examples:
- `/self-review` — review the PR for the current branch in the current repo (default)
- `/self-review focus on failure tolerance in the backfill` — current branch's PR + focus instructions
- `/self-review 958` — standard review
- `/self-review 958 focus on failure tolerance in the backfill` — standard review with extra emphasis
- `/self-review https://github.com/org/repo/pull/958 check for race conditions` — URL form with focus

## Phase 1: Setup

1. Parse `$ARGUMENTS`: try to extract the PR number from the first token (a number or a URL containing one). If the first token is not a PR number or URL, treat ALL of `$ARGUMENTS` as focus instructions and resolve the PR from the current branch (see step 2 below). Otherwise, everything after the first token is the **focus instructions**.

2. **Determine which PR to review:**

   **2a. Full GitHub URL provided** (e.g., `https://github.com/org/repo/pull/123`):
   - Extract the `owner/repo` and PR number from the URL.
   - Run `git remote -v` to check if the current directory matches that repo.
   - If it does NOT match (or you're not in a git repo at all), find and `cd` into the correct local clone:
     ```bash
     find ~/mycase ~/code ~/src ~/repos ~/projects -maxdepth 2 -name "<repo>" -type d 2>/dev/null | head -5
     ```
   - If the repo cannot be found locally, **STOP and tell the user**.

   **2b. PR number only**:
   - Verify the current directory is a git repository: `git rev-parse --is-inside-work-tree`
   - If NOT in a git repo, **STOP and tell the user** you need either a full PR URL or to be run from inside the target repository.
   - Verify the PR exists: `gh pr view <number> --json url --jq .url`

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

3. Enter a worktree named `pr-review-<number>`.
4. Check out the PR branch: `gh pr checkout <number>`

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

### Our Own Previous Reviews (for context only)
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
- **Our previous findings** — extract each finding's severity, file, line, and core issue description
- **Replies to our comments** — check `in_reply_to_id` on all PR comments to find author responses to our findings
- **Commits after our review** — compare `submitted_at` of our latest review against the commit list to see what changed since we last reviewed

This data feeds into **Phase 2.5** below.

### JIRA Ticket
Extract the JIRA ticket ID from the PR branch name or PR body. Look for patterns like `[A-Z]+-\d+` (e.g., `LOR-2160`, `HAL-1234`).
If found, fetch the ticket using the Atlassian MCP tool:
- Use `mcp__plugin_FDK_atlassian__getJiraIssue` with the ticket ID
- Extract: summary, description, acceptance criteria, story points, status
- If the tool is unavailable or fails, note this and continue without JIRA context.

### Read Changed Files in Full
For every file in the diff, read the FULL file (not just the diff hunks) to understand the surrounding context. This is critical for catching issues that depend on how the changed code interacts with existing code.

For each changed file, also check:
- Are there related files that weren't changed but should have been? (e.g., tests for new code, serializers for new model fields, migration for new columns)

## Phase 2.5: Previous Review Triage

**Skip this phase if no previous reviews from our login were found.**

For each finding from our previous reviews, classify it into one of these buckets:

| Bucket | Criteria | Action in Phase 5 |
|--------|----------|--------------------|
| **Addressed** | The code was changed to fix the issue, OR the author replied explaining why it's not needed and the explanation is sound | Note as resolved |
| **Partially addressed** | The fix exists but is incomplete, or the author's reply doesn't fully resolve the concern | Note what's still open |
| **Not addressed** | No code change and no author reply, OR the author replied but the concern stands | Re-raise with additional context |
| **Superseded** | The surrounding code changed enough that the original finding no longer applies | Note as moot |
| **New context** | Our original finding still applies, but new code changes add additional nuance worth mentioning | Note with additional context |

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

## Phase 5: Print the Review (DO NOT POST)

**CRITICAL: Do NOT post anything to GitHub. Do NOT use `gh api` to submit reviews, comments, or replies. Print everything to the console only.**

### Determine Severity
Categorize each finding:
- **blocker**: Must fix before merge (correctness bugs, security issues, data loss risk)
- **warning**: Should fix, but not a merge blocker (performance concerns, missing validation)
- **suggestion**: Nice-to-have improvements (style, maintainability, test coverage)
- **question**: Needs clarification from the author
- **nitpick**: Trivial style/formatting issues

### Print the Review Summary
Print the full review to the console using markdown formatting. Organize the summary by semantic chunk, with findings grouped by severity. If this is a **continuation review** (we found our own previous reviews in Phase 2.5), lead with the follow-up section. Structure:

```markdown
## Review Summary

<1-2 sentence overall assessment>
<If continuation: "This is a follow-up review. Previous review posted on <date>.">

### Previous Review Follow-up
<Include ONLY if we had previous reviews. Show the triage table from Phase 2.5.>

| # | Previous Finding | Status | Notes |
|---|-----------------|--------|-------|
| 1 | Task leak on exception | ✅ Addressed | Fixed in 78b46c5d with try/finally |
| 2 | Dirty flag race | ⚠️ Not addressed | No reply or code change — re-raised below |

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

### Print Inline Comments
After the summary, print each inline comment with its file location so the developer can navigate to it:

```
---
### Inline Comments

**[severity] `path/to/file.py:42`**
Comment body...

**[severity] `path/to/other_file.py:108`**
Comment body...
```

### Print Previous Review Thread Actions (if applicable)
If we had previous reviews, print what replies we WOULD post to each thread so the developer can see the triage:

```
---
### Previous Thread Replies (not posted)

**Reply to comment #12345 on `agent.py:374`:**
✅ Fixed in 78b46c5d — the try/finally cleanup looks correct.

**Reply to comment #12346 on `agent.py:212`:**
Still outstanding — re-raised in latest review with additional detail.
```

## Phase 6: Cleanup

Exit and remove the worktree. Use `ExitWorktree` with `action: "remove"` and `discard_changes: true` (since the worktree only has the checked-out PR branch, no original work).

## Important Rules

1. **NEVER post to GitHub.** This is a local-only review. No `gh api` calls to submit reviews, comments, or replies. All output is printed to the console.
2. **Never duplicate existing feedback from other reviewers.** If another reviewer already flagged an issue, don't re-raise it unless you have a materially different take.
3. **Always track your own previous reviews.** If you posted a review before on this PR, you MUST triage every previous finding (Phase 2.5) in your printed output.
4. **Always include positives.** Call out what was done well. On continuation reviews, explicitly acknowledge improvements made since last review.
5. **Be specific.** Reference exact file paths, line numbers, and code snippets. Don't make vague "consider improving" comments.
6. **Assume competence.** The author likely had reasons for their choices. Frame suggestions as questions or alternatives, not commands.
7. **Prioritize signal over noise.** 3 high-signal comments are worth more than 15 nitpicks. Don't comment just to comment.
8. **Check existing indexes before claiming one is missing.** Read the full model file to see all `__table_args__` indexes before suggesting new ones.
9. **For unique constraints on nullable columns**, remember PostgreSQL treats NULLs as distinct — multiple NULLs are allowed. Only flag this if the non-NULL case is genuinely problematic.
10. **For performance claims**, verify the actual query path. A composite index with the filtered column as the Nth position CAN still be used via bitmap index scan, just less efficiently than a leading-column match.
11. **Continuation reviews are first-class.** Re-reviewing a PR after changes is not a lesser activity. The follow-up triage table is just as important as new findings.
12. **Respond to author replies.** If the author replied to one of your previous comments, include your response in the printed output.
13. **Adapt to PR changes.** If the PR title, description, files, or base branch changed since your last review, note what changed and adjust your review scope accordingly.
