# Fixup Commit

Stage the current changes and fixup them into the most appropriate existing commit on this branch.

## Workflow

1. Run `git diff --cached --stat` and `git diff --stat` to see what has changed (staged and unstaged).
2. If there are unstaged changes, stage them with `git add` for the relevant files.
3. Identify the correct target commit by examining `git log --oneline main..HEAD` (or the appropriate base branch). Choose the commit whose scope best matches the staged changes. If the argument `$ARGUMENTS` is provided, use it as the target commit hash directly.
4. Confirm with the user which commit to fixup into before proceeding.
5. Create the fixup commit: `git commit --fixup <target-hash>`
6. Autosquash it: `GIT_SEQUENCE_EDITOR=true git rebase -i --autosquash --autostash <target-hash>^`
7. Verify the result with `git log --oneline -5 HEAD`.

## Important

- Always confirm the target commit with the user before running the fixup.
- If the rebase fails, show the error and ask the user how to proceed.
- Never force-push without explicit user approval.
