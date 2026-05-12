# Address PR Feedback

Read all reviews, comments, and feedback on a PR, triage everything, resolve stale threads, fix what's still actionable, commit, push, and reply to every comment. The goal: **zero unresponded-to comments** when this is done.

Arguments: `$ARGUMENTS`

The first token is the PR number (or full URL), and is OPTIONAL. Everything after is treated as **additional context or focus instructions**. Examples:
- `/address-pr` — address feedback on the PR for the current branch in the current repo (default)
- `/address-pr skip the nitpicks, focus on blockers` — current branch's PR + focus instructions
- `/address-pr 958` — address all feedback on PR 958
- `/address-pr 958 skip the nitpicks, focus on blockers` — prioritize specific feedback
- `/address-pr https://github.com/org/repo/pull/958` — URL form

**IMPORTANT**: This skill does NOT use a worktree. It operates directly in the working tree because it needs to run tests, linting, and coverage locally. A stash/pop mechanism protects any uncommitted work.

---

## Phase 0: Repository Verification

You MUST be inside the correct git repository before doing anything.

1. Parse `$ARGUMENTS`: try to extract the PR number from the first token (a number or a URL containing one). If the first token is not a PR number or URL, treat ALL of `$ARGUMENTS` as focus instructions and resolve the PR from the current branch (see step 2c below). Otherwise, everything after the first token is the **focus instructions**.

2. **Determine which PR to operate on:**

   **2a. Full GitHub URL** (e.g., `https://github.com/org/repo/pull/123`):
   - Extract the `owner/repo` and PR number from the URL.
   - Run `git remote -v` to check if the current directory already matches that repo.
   - If it does NOT match (or you're not in a git repo at all), find and navigate to the correct local clone:
     ```bash
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

3. **Confirm repo state**: Run `git remote -v` and log which repository you're operating in.

---

## Phase 1: Safe Branch Checkout

Protect the user's current work before switching branches.

1. Record the current branch: `git branch --show-current` — save this as `$ORIGINAL_BRANCH`.
2. Check for uncommitted changes: `git status --porcelain`
3. **If there are uncommitted changes**, stash them with a descriptive message:
   ```bash
   git stash push -m "address-pr: auto-stash before checking out PR #<number>"
   ```
   Record that a stash was created (`$STASH_CREATED=true`).
4. Fetch latest and check out the PR branch:
   ```bash
   git fetch origin
   gh pr checkout <number>
   ```
5. Verify the checkout: `git branch --show-current` — confirm you're on the expected branch.
6. Pull latest changes on the PR branch:
   ```bash
   git pull --ff-only origin $(git branch --show-current) 2>/dev/null || true
   ```

**If checkout fails**, restore the stash (if created) and STOP.

---

## Phase 2: Deep Research & Context Gathering

Run as much of this in parallel as possible.

### 2a. PR Metadata
```bash
gh pr view <number> --json title,body,headRefName,baseRefName,additions,deletions,files,commits,reviews,comments,labels,author,reviewRequests,mergeStateStatus,statusCheckRollup
```

### 2b. PR Diff (against base)
```bash
gh pr diff <number>
```
If the diff is large, save to a temp file and read in chunks.

### 2c. JIRA Ticket
Extract the JIRA ticket ID from the PR branch name or PR body. Look for patterns like `[A-Z]+-\d+` (e.g., `LOR-2160`, `HAL-1234`).
If found, fetch the ticket using the Atlassian MCP tool:
- Use `mcp__plugin_FDK_atlassian__getJiraIssue` with the ticket ID
- Extract: summary, description, acceptance criteria, story points, status
- If the tool is unavailable or fails, note this and continue without JIRA context.

### 2d. ALL Reviews & Comments (exhaustive — REST + GraphQL cross-check)

Determine our own GitHub login:
```bash
gh api user --jq .login
```

Fetch **all** review-level data:
```bash
# All reviews (REST)
gh api repos/{owner}/{repo}/pulls/<number>/reviews --paginate

# All inline review comments (REST) — these are the line-level comments
gh api repos/{owner}/{repo}/pulls/<number>/comments --paginate

# All issue-level comments (REST) — these are the top-level PR conversation comments
gh api repos/{owner}/{repo}/issues/<number>/comments --paginate
```

**Cross-check with GraphQL** for review threads (critical for resolving threads later — we need the `threadId`):
```
gh api graphql -f query='{
  repository(owner: "<owner>", name: "<repo>") {
    pullRequest(number: <number>) {
      reviewThreads(first: 100) {
        nodes {
          id
          isResolved
          isOutdated
          line
          path
          comments(first: 50) {
            nodes {
              id
              databaseId
              author { login }
              body
              createdAt
              path
              line
              replyTo { id }
            }
          }
        }
      }
      reviews(first: 50) {
        nodes {
          id
          databaseId
          author { login }
          body
          state
          submittedAt
          comments(first: 50) {
            nodes {
              id
              databaseId
              author { login }
              body
              path
              line
              replyTo { id }
            }
          }
        }
      }
    }
  }
}'
```

If pagination is needed (>100 threads), use `after` cursors to get all threads. **Do not miss any.**

### 2e. Read Changed Files in Full
For every file in the diff, read the FULL current file (not just diff hunks) to understand context.

### 2f. Read Project Config
Read the project's `CLAUDE.md` (and any `.claude/` config) to understand:
- How to run tests
- How to run linting
- How to check coverage
- Any project-specific conventions or CI requirements

Also check for `Makefile`, `package.json` scripts, `pyproject.toml`, `Cargo.toml`, etc. as fallbacks.

---

## Phase 3: Comment Triage

For EVERY comment thread on the PR (reviews, inline comments, issue comments, bot comments — everything), classify it into exactly one bucket. **Nothing gets skipped.**

### Triage Buckets

| Bucket | Criteria | Action |
|--------|----------|--------|
| **Stale — already addressed** | Code was already changed to fix this, but nobody replied | Reply acknowledging the fix + resolve thread (if bot) or reply only (if human reviewer) |
| **Stale — no longer applicable** | The code path was removed, refactored away, or the comment targets outdated lines | Reply noting it's moot + resolve thread (if bot) or reply only (if human) |
| **Stale — bot/CI noise** | Automated comment (linter, CI, coverage bot, etc.) that is outdated or no longer relevant | Resolve thread directly — be generous resolving bot noise |
| **Actionable — needs code fix** | Valid feedback that requires a code change | Add to execution plan (Phase 4) |
| **Actionable — needs reply only** | Question, clarification request, or suggestion that doesn't need a code change but needs a response | Queue a reply |
| **Already resolved** | Thread is already marked resolved in GitHub | Skip entirely |
| **Already responded to** | Our login already replied and no further response is needed | Skip unless there's a new reply from the reviewer we haven't addressed |

### Triage Rules

- **Bot vs. human**: Check `author.login` — common bots include `github-actions[bot]`, `codecov[bot]`, `codeclimate[bot]`, `dependabot[bot]`, `sonarcloud[bot]`, and anything ending in `[bot]`. For bots, be **generous with resolving** stale threads. For human reviewers, **always reply** to explain what you did and let THEM resolve.
- **isOutdated flag**: GitHub marks threads as "outdated" when the underlying code changed. This is a strong signal of staleness, but still verify by reading the current code.
- **Thread vs. standalone**: Some comments are part of review threads (have a `threadId`), others are standalone issue comments. Track both.
- **Our own comments**: If we left a comment previously, check if the reviewer replied to it — if so, we need to respond.
- **Prioritize resolving bot/CI noise first** — these are the noisiest and cleaning them up makes the PR much easier to read.

### Build the Triage Table

Present the full triage table to the user before proceeding. Format:

```
## Comment Triage — PR #<number>

### Stale — Will Resolve (<count>)
| # | Author | Type | File:Line | Summary | Action |
|---|--------|------|-----------|---------|--------|
| 1 | codecov[bot] | bot | — | Coverage report outdated | Resolve thread |
| 2 | reviewer123 | human | api.py:45 | Missing null check | Reply "fixed in current code" |

### Actionable — Needs Code Fix (<count>)
| # | Author | Type | File:Line | Summary | Severity |
|---|--------|------|-----------|---------|----------|
| 3 | reviewer123 | human | models.py:89 | Race condition in save | blocker |
| 4 | reviewer123 | human | tests.py:12 | Missing edge case test | suggestion |

### Actionable — Needs Reply Only (<count>)
| # | Author | Type | File:Line | Summary | Response |
|---|--------|------|-----------|---------|----------|
| 5 | reviewer123 | human | utils.py:30 | "Why not use X?" | Explain design choice |

### Already Handled (<count>)
(threads already resolved or fully responded to)
```

---

## Phase 4: Resolve Stale Comments

Handle all stale threads BEFORE making any code changes.

### 4a. Resolve bot/CI threads
For stale bot comments, resolve the thread directly using GraphQL:
```bash
gh api graphql -f query='
  mutation {
    resolveReviewThread(input: { threadId: "<thread_node_id>" }) {
      thread { isResolved }
    }
  }
'
```

### 4b. Reply to stale human reviewer threads
For stale human reviewer comments where the issue was already addressed:
- Reply with a specific explanation of how/when it was fixed
- Reference the commit if identifiable: `"This was addressed in <commit> — <brief description of the fix>."`
- Do NOT resolve the thread — let the reviewer do that

### 4c. Reply to stale human reviewer threads where code is no longer applicable
- Reply explaining the code was removed/refactored: `"This code path was removed in <commit> / refactored in <commit> — no longer applicable."`
- Do NOT resolve — let the reviewer do that

---

## Phase 5: Plan & Execute Fixes

### 5a. Build the Execution Plan

Group all "Actionable — needs code fix" comments into semantic commits. Guidelines:
- **As few commits as possible** without compromising git hygiene
- Quick fixes (typos, naming, small style issues) can be batched into one commit
- Significant fixes (logic bugs, race conditions, missing error handling) get their own commit
- Test additions/fixes can be their own commit or grouped with the code they test
- Each commit message should reference which comment(s) it addresses

Present the plan:
```
## Execution Plan

### Commit 1: "Fix race condition in model save (PR feedback)"
- Address comment #3: race condition in models.py:89
- Files: models.py, test_models.py

### Commit 2: "Address review feedback: null checks, edge case tests"
- Address comment #4: missing edge case test
- Address comment #7: add null check in serializer
- Files: tests.py, serializer.py
```

### 5b. Execute the Fixes

For each planned commit:
1. Make the code changes
2. Stage the relevant files
3. Commit with a clear message that references the feedback being addressed

**Commit message format:**
```
<concise description of changes>

Addresses PR review feedback:
- <summary of comment 1> (<author>)
- <summary of comment 2> (<author>)
```

### 5c. Run Tests, Linting & Coverage

**CRITICAL — this is a hard gate. Do NOT push until the full CI command passes.**

After ALL code changes are committed (but before pushing):

1. **Read the project's CLAUDE.md** to find the CI command. For `mycase_hal`, this is:
   ```bash
   npx nx run-many -t test coverage lint
   ```
2. **Run the full CI command** — not just tests. Coverage and linting are equally required.
3. **Verify coverage meets requirements** — if coverage drops below the threshold, add tests to cover the new/changed code before proceeding.

If tests, coverage, or linting fail:
- Fix the issues
- Create an additional commit: `"Fix lint/test/coverage issues from PR feedback changes"`
- Re-run the **full CI command** again to verify green

**You MUST run the complete CI command (tests + coverage + lint) and see it pass before pushing. Running only `test` without `coverage` and `lint` is NOT acceptable — the PR will fail CI.**

### 5d. Push

```bash
git push origin HEAD
```

Record the commit SHAs for use in Phase 6.

If there are NO code changes needed (all comments just need replies), skip 5a–5d entirely and proceed to Phase 6.

---

## Phase 6: Respond to All Comments

The goal: **every single comment thread has a response from us**. No thread left behind.

### 6a. Reply to addressed comments (code was fixed)

For each comment that we fixed with code:
- Reply on the specific thread citing the commit:
  ```
  Fixed in <short_sha> — <brief description of what changed>.
  ```
- Be specific: don't say "fixed" without explaining what you did
- Do NOT resolve the thread — let the reviewer decide

To reply to an inline review comment thread:
```bash
cat <<'PAYLOAD' | gh api repos/{owner}/{repo}/pulls/<number>/comments --method POST --input -
{
  "body": "<reply text>",
  "in_reply_to": <original_comment_database_id>
}
PAYLOAD
```

To reply to a top-level issue comment (not an inline review comment):
```bash
cat <<'PAYLOAD' | gh api repos/{owner}/{repo}/issues/<number>/comments --method POST --input -
{
  "body": "<reply text>"
}
PAYLOAD
```

### 6b. Reply to comments that need explanation only

For questions, design clarifications, or suggestions you intentionally didn't take:
- Provide a clear, respectful explanation
- If declining a suggestion, explain WHY (not just "no")
- If answering a question, be thorough

### 6c. Reply to any remaining unanswered threads

Sweep through ALL threads one more time. If any thread from a human reviewer has no reply from our login, reply now. Even if it's just an acknowledgment: `"Good catch, thanks — addressed in <sha>."` or `"Agreed, though this is out of scope for this PR — I'll track it separately."`

### 6d. Resolve remaining bot threads

Any bot/CI thread that is now passing or no longer relevant — resolve it:
```bash
gh api graphql -f query='
  mutation {
    resolveReviewThread(input: { threadId: "<thread_node_id>" }) {
      thread { isResolved }
    }
  }
'
```

---

## Phase 7: Verification & Cleanup

### 7a. Verify all comments are handled

Run the GraphQL query from Phase 2d again to get all review threads. Check:
- Every thread from a human reviewer has at least one reply from our login (or was already resolved)
- Every stale bot thread is resolved
- No threads were missed

If any were missed, go back and handle them now.

### 7b. Restore original branch state

1. Check out the original branch:
   ```bash
   git checkout $ORIGINAL_BRANCH
   ```
2. If a stash was created (`$STASH_CREATED=true`):
   ```bash
   git stash pop
   ```
3. Verify the working tree is clean (or has the same uncommitted changes as before): `git status`

**If the stash pop fails** (conflict), warn the user and leave the stash in place — do NOT force it.

### 7c. Transition LOR ticket to Code Review

**Only runs when BOTH conditions hold:**
- Phase 5 actually pushed at least one commit (i.e., 5a–5d ran — not just the reply-only path).
- A `LOR-NNNN` key was extracted from the PR (Phase 2c).

If you only replied to comments without pushing code, **skip this phase** — moving the ticket back to Code Review when nothing changed would be misleading. The reviewer can re-review the existing commits without a state change.

For each LOR key:

1. Run R6 `transition_to(key, "code review")` from `_jira-helpers.md`.
2. Handle outcomes:
   - `{result: "noop"}` — already in Code Review. Log `"LOR-XXXX already in Code Review"`.
   - `{result: "ok"}` — log `"✓ LOR-XXXX → Code Review"`.
   - `{result: "error", reason: "no transition to code review", available: [...]}` — print the available transitions and tell the user; don't auto-pick. Common reason: the ticket is in a state (like "Blocked") where Code Review isn't a direct transition.
   - Any other error — print and ask.

**Fail-soft:** all PR feedback work is already complete (push + replies). A JIRA transition failure here should warn the user but not crash. Always include the JIRA link for manual recovery.

Skip the JIRA transition entirely if the user passed `skip-jira` as a focus instruction.

### 7d. Summary

Present a final summary:

```
## PR #<number> Feedback — Fully Addressed

### Stats
- Total comment threads: <N>
- Resolved (stale/bot): <N>
- Fixed with code: <N> (across <M> commits)
- Replied to (no code change): <N>
- Already handled (skipped): <N>

### Commits Pushed
- `<sha1>` — <message>
- `<sha2>` — <message>

### Threads Resolved
- <list of resolved thread summaries>

### Replies Posted
- <list of reply summaries>

### Still Open (if any)
- <anything that couldn't be resolved — e.g., needs reviewer input>
```

---

## Important Rules

1. **Zero unresponded-to comments.** This is the primary goal. Every human reviewer comment gets a reply. Every bot thread gets resolved or replied to.
2. **Never resolve a human reviewer's thread.** Reply to it and let them resolve. The only exception is if it's clearly stale AND the reviewer is no longer active on the PR.
3. **Be generous resolving bot/CI threads.** If a bot comment is outdated, resolve it. Don't let CI noise clutter the PR.
4. **Commit hygiene matters.** As few commits as semantically necessary. Batch quick fixes, separate significant changes. Every commit message should be meaningful.
5. **Always run tests before pushing.** Never push code that doesn't pass the project's test suite and linter.
6. **Be specific in replies.** Always reference the commit SHA and describe what changed. "Fixed" alone is not enough.
7. **Don't over-engineer.** If a comment suggests a refactor that would bloat the PR, reply explaining you'll handle it separately. Stay focused on the PR's scope.
8. **Respect the reviewer.** Frame responses as collaborative, not defensive. Thank reviewers for catches. If you disagree with feedback, explain your reasoning respectfully.
9. **Read the CLAUDE.md.** The project config is authoritative for how to run tests, lint, and check coverage. Don't guess.
10. **Stash safety is non-negotiable.** Always stash before checkout, always pop after. If the pop fails, warn the user — never force it or drop the stash.
11. **If there are no code changes needed**, that's fine. The skill is equally valuable as a "respond to all comments" tool. Don't make changes just to have something to commit.
12. **Adapt to the PR's state.** If the PR has been through multiple review rounds, the thread history may be complex. Take the time to understand the full conversation before responding — don't reply based on a single comment in isolation.
