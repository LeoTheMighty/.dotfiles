# Create Story

Create a JIRA story (or bug / spike) in the LOR project with sane defaults and a careful, error-driven retry loop for required-field plumbing. Designed for the in-flight engineering workflow — not for grooming. Used standalone OR by `/push-story` when no key is given.

> **This skill is the riskiest in the JIRA workflow** because JIRA's required-field surface is opaque and varies by project / workflow. Read the **"Trial-and-error posture"** section below before iterating on this skill.

See `_jira-helpers.md` for shared routines:
- R1 `get_cloud_id`
- R2 `get_my_account_id`
- R3 `get_active_lor_sprint`

Arguments: `$ARGUMENTS`

Everything up to the first `--flag` is the **summary**. Flags can appear in any order:

```
/create-story <summary> [--type story|bug|spike] [--epic LOR-NNNN] [--cap-project <name>] [--category <name>] [--points N] [--priority <name>] [--backlog] [--description-file <path>] [--dry-run] [--no-prompt]
```

Examples:
- `/create-story Add retry to webhook handler` — heuristic-derived category / cap-project / points / priority / parent; assigned to active sprint
- `/create-story Webhook 500s on duplicate event --type bug --priority High` — bug variant with explicit priority
- `/create-story Investigate API latency on cold start --type spike --backlog --points 3` — spike, backlog, explicit points
- `/create-story Refactor session manager --epic LOR-1000` — explicit epic skips parent auto-search
- `/create-story Add AI legal research tab --cap-project "AI Legal Research"` — explicit cap-project; parent search runs against it
- `/create-story Test the create flow --dry-run` — assemble + print the payload but DON'T call the API

---

## Trial-and-error posture (READ FIRST)

Building a reliable JIRA `createJiraIssue` is hard because:

1. **Required fields vary by project, by issue type, and by workflow.** What's required for a LOR Story today may not be what's required tomorrow if the project admin adds a field.
2. **The JIRA error response is the source of truth.** Don't trust your assumptions about what fields are needed — trust JIRA's `400` response.
3. **Some required fields have safe defaults**, others don't. Drive the difference from the error, not from a hard-coded list in this file.

The skill is built around a **try → parse → fill → retry** loop:

1. Assemble the payload with everything we know is required (Phase 4).
2. Attempt `createJiraIssue`.
3. On `400`, parse the per-field `errors` map.
4. For each error: either fill from a known default, prompt the user once, OR (if unrecoverable) print everything and stop.
5. Retry up to **3 times total**.
6. After the 3rd failure, dump the full payload + error + a one-click "Create in JIRA web UI" link.

This loop is the iterative-improvement surface — over time, fields that show up in the prompt step a lot can be promoted to Phase 4 defaults.

> **Field source-of-truth:** The lists in Phase 3 (Investment Category, Capitalizable Project, etc.) are cached from `getJiraIssueTypeMetaWithFields` and drift over time. If a user requests a value not in the cached list, call `getJiraIssueTypeMetaWithFields(cloudId, "LOR", "10001")` to refresh — JIRA's response wins.

---

## Phase 0: Parse arguments + defaults

Set defaults:
- `$PROJECT_KEY = "LOR"` (hard-coded — `/create-story` is LOR-only)
- `$ISSUE_TYPE = "Story"` (override via `--type`)
- `$SPRINT_MODE = "active"` (override via `--backlog`)
- `$DRY_RUN = false` (`true` via `--dry-run`)
- `$NO_PROMPT = false` (`true` via `--no-prompt` — fail instead of prompting)
- `$CATEGORY = null` (override via `--category`)
- `$CAP_PROJECT = null` (override via `--cap-project`)
- `$POINTS = null` (override via `--points`; must be Fibonacci: 1, 2, 3, 5, 8, 13, 21)
- `$PRIORITY = null` (override via `--priority`; one of Highest, High, Medium, Low, Lowest)
- `$EPIC_KEY = null` (override via `--epic`; setting this skips Phase 3e auto-search)

Parse positional summary (everything before the first `--`). If empty, **STOP** and prompt the user for one.

Validate `--type`:
- `story` → Issue Type Name = "Story"
- `bug` → Issue Type Name = "Bug" (note: bugs need extra fields per FDK conventions — `Environment Source`, `Severity`. We'll discover them via the retry loop, not pre-fill.)
- `spike` → Issue Type Name = "Spike"
- Anything else → STOP.

---

## Phase 1: Discovery (parallel)

- R1 `get_cloud_id` → `$CLOUD_ID`
- R2 `get_my_account_id` → `$MY_ACCOUNT_ID`
- R3 `get_active_lor_sprint` → `$ACTIVE_SPRINT` (only if `$SPRINT_MODE = active`)

If `$SPRINT_MODE = active` and `$ACTIVE_SPRINT` is missing, ask the user: "No open sprint on LOR right now. Create in backlog instead? [Y/n]". Default yes.

---

## Phase 2: Description

Three sources, in priority order:

1. `--description-file <path>` → read the file's contents.
2. Caller-provided description (e.g., `/push-story` passes one in via the args string convention) — if present.
3. **Generate a draft** from the summary alone. Template:

```
## Summary
<one paragraph elaborating the summary>

## Acceptance Criteria
- [ ] <derived from summary — best guess>
- [ ] <one or two more concrete items if the summary supports them>
```

The `## Acceptance Criteria` heading is the **idempotency anchor** for `/update-qa-steps`. That skill regenerates this section's checklist from the actual PR diff once the PR is open — replacing whatever placeholder items live here. Same heading, same checkbox format, replace in place. No HTML comment markers needed.

If `$NO_PROMPT = false` and the description is auto-generated, show it to the user and ask: "Use this description or paste your own?" — accept either. Skip in `$NO_PROMPT = true` mode.

---

## Phase 3: Custom fields — heuristic-first, confirm

Five fields are populated here, each with a smart-guess so the user only confirms once instead of answering five separate prompts. The known-required ones for LOR Stories are **Investment Category** (`customfield_11045`) and **Summary/Issue Type/Project/Reporter** (system). The rest (Capitalizable Project, Story Points, Priority, Parent) are *optional in schema* but we always set them because the team's reporting and grooming workflow depends on them.

### 3a. Investment Category (`customfield_11045`) — REQUIRED

Field is named **"Investment Category"** in JIRA (older docs call it "AffiniPay Category" — same field). Used for capitalization labor reporting.

| Value | ID | When to choose |
|---|---|---|
| **Roadmap** | `10248` | Planned strategic initiatives, new features, products, major net-new work tied to OKRs. |
| **Product Improvement** | `10249` | Enhancements to existing features: UX polish, bug fixes, performance, workflow refinements. This is the most common choice. |
| **Technology Improvement** | `10250` | Internal engineering investments with no direct user-visible change: refactors, infra, CI/CD, dependency upgrades, security hardening. |
| **KTLO** | `14005` | "Keep The Lights On" — operational toil, on-call follow-ups, alert tuning, minor compliance/maintenance that isn't a product improvement. |

**Heuristic from summary text** (case-insensitive):

| Summary keywords | Default guess |
|---|---|
| `refactor`, `upgrade`, `perf`, `infra`, `migrate`, `ci`, `pipeline`, `tech debt`, `dependency`, `security` | Technology Improvement |
| `oncall`, `alert`, `runbook`, `noise`, `rotate`, `cleanup`, `housekeeping`, `compliance` | KTLO |
| `add`, `new`, `feature`, `enable`, `launch`, `introduce` | Roadmap |
| `fix`, `bug`, `error`, `crash`, `regression`, `broken`, `improve`, `tweak` | Product Improvement |
| (no match) | Product Improvement |

If `$CATEGORY` was set via `--category`, skip the prompt. Otherwise show one prompt with the guess as default; accept number or name. Skip the prompt in `$NO_PROMPT = true` mode (use the guess).

### 3b. Capitalizable Project (`customfield_11018`) — SET WHEN POSSIBLE

Optional in schema (defaults to "Other"), but we always pick the best match because Phase 3e's parent-epic search keys off it. Cache `$LAST_CAP_PROJECT` in-session so back-to-back calls don't re-ask.

**Strategy:**

1. If `--cap-project <name>` was passed → fuzzy-match against the table below. Exact match wins; otherwise normalize (lowercase, strip punctuation) and pick the closest.
2. If `$LAST_CAP_PROJECT` exists from a prior call this session → use it as the default in the prompt.
3. Otherwise free-text prompt; fuzzy-match against the table. If no good match (>1 candidate with similar score), show the top 5 and let the user pick.
4. If the user types `other`, `none`, `unknown`, or leaves blank → use `Other` (10215).
5. `$NO_PROMPT = true` → if no flag and no session cache, default to `Other`.

**When to pick a specific project:** match it to the *initiative the work funds*, not the system being changed. A bug fix in payments that's part of the New CPACharge rollout → `New CPACharge`, not `Other`.

**Full options (alphabetical, current as of cache refresh):**

| Name | ID |
|---|---|
| Accept Payment w/o Receivable | 13311 |
| Accounting Connector | 10491 |
| Adding UPF to MyCase | 13312 |
| AI Actions | 10941 |
| AI Legal Research | 13526 |
| AI Platform Q226 | 15359 |
| AllDrafts Integration | 13659 |
| AMEX Direct | 11400 |
| Apple Pay | 10388 |
| Audit Trail | 10256 |
| BillBlast Integration | 13803 |
| Branch-Specific LawPay Accounts | 10361 |
| Capital Lending | 10489 |
| Case Assistant V2 | 12591 |
| Chat with Finances | 10939 |
| Checkout Optimization | 13310 |
| Common Identity Phase 1 | 12225 |
| Dashboard Customization | 12555 |
| Delayed eCheck | 12489 |
| Dispute Report | 10707 |
| Docketwise File Sync | 10633 |
| Document Enhancements | 11829 |
| DW - NLP (New LawPay) Integration Enablement | 12736 |
| Elite 3E Integration | 13057 |
| Embeddable Bank Activity Report V1 | 11072 |
| EOIR Case Tracking | 10487 |
| ETA-9089 e-Filing | 10348 |
| Evergreen Payment Form | 10360 |
| FinTech Embeddable Merchant Application | 13125 |
| Form I-956H (Add) | 10362 |
| I-90 e-Filing | 10349 |
| I2C Cash Application | 11632 |
| Interchange+ Net New Support | 11730 |
| Multi-vertical Foundation | 15360 |
| MyCase Immigration Settings | 11301 |
| MyCase Invoice Revamp | 10439 |
| MyCase Search Modernization | 11763 |
| New CPACharge | 11631 |
| New LawPay Experience | 10335 |
| NYC1 Mobile Device | 10638 |
| OCR | 13527 |
| Other | 10215 |
| Partner-Credited Payment Pages | 10291 |
| Payment Method Customization | 13195 |
| PCI Embeddable | 11796 |
| Promotional Credits | 10358 |
| QBO Integration v2 | 10306 |
| Royalty Improvements | 10839 |
| Self-Service Beneficial Ownership Collection | 10387 |
| Sigma | 15321 |
| Single Source of Truth Automation | 10872 |
| Smart Form: Track & Record Input History | 10486 |
| Spend Management | 10304 |
| Task Management Enhancements for Docketwise | 10639 |
| UPF - Partial Payments | 10655 |
| UPF - Saved Payment Methods | 10656 |
| Voltage Reporting | 10773 |

**Selectable options vs. legacy values on existing tickets.** This table is the createmeta — the options selectable when creating a *new* ticket. It is **not** the same as the set of values that appear on *existing* tickets. When an admin archives an option, the value persists on already-tagged issues but disappears from createmeta. So users browsing legacy Epics may see a Cap Project value (e.g. "AI Platform Q126" on LOR-1695) that you cannot apply to a new ticket — the live equivalent is the renamed/replaced option ("AI Platform Q226"). When this happens:

1. Try to map the legacy value to a current option by name similarity (e.g. `Q126 → Q226`). If a clean mapping exists, use the live ID and warn: `Note: requested "AI Platform Q126" is archived; using "AI Platform Q226" (15359).`
2. If no mapping is obvious, fall back to `Other` (10215) with a warning.
3. **Do not** trigger a createmeta refresh on these — refreshing won't bring archived options back. Only refresh when JIRA rejects an option that *should* be selectable (true drift).

**Known legacy aliases** (extend as encountered):

| Legacy value (on old tickets) | Current option | Current ID |
|---|---|---|
| AI Platform Q126 | AI Platform Q226 | 15359 |

If a user requests a value that is neither in the table above nor a known legacy alias, refresh by calling `getJiraIssueTypeMetaWithFields(cloudId, "LOR", "10001")` and re-match — admins do add new options occasionally (true drift).

### 3c. Story Points (`customfield_10005`) — Fibonacci complexity

Always set to a **Fibonacci number**: `1, 2, 3, 5, 8, 13, 21`. Anything else is rejected at parse time.

**Scale guide:**

| Points | Complexity | Examples |
|---|---|---|
| **1** | Trivial. <30 min. | Typo, copy change, comment, single-line config, one-line null check. |
| **2** | Tiny. Half a day or less. | Add a known-pattern endpoint, simple validation, well-scoped bug fix with reproduction. |
| **3** | Small. A day. **Default for ambiguous work.** | Standard feature work with clear acceptance criteria and no architectural surprises. |
| **5** | Medium. 2–3 days. | Multi-file feature, a small refactor, a bug that needs investigation before the fix. |
| **8** | Large. ~1 sprint. | New cross-cutting feature, a migration, a refactor that touches several modules. Should usually be split. |
| **13** | Very large. Spans a sprint. | Probably needs to be broken down. Use sparingly; flag for grooming. |
| **21** | Epic-sized. | Almost never appropriate for a Story. If you're tempted to pick this, it's an Epic. |

**Heuristic from summary text** (case-insensitive, last match wins):

| Summary keywords | Default points |
|---|---|
| `typo`, `comment`, `rename`, `copy`, `wording`, `link`, `readme` | 1 |
| `bump`, `flag`, `toggle`, `add log`, `add metric`, `null check` | 2 |
| (no match, default) | 3 |
| `refactor`, `extract`, `cleanup`, `migrate small`, `consolidate` | 5 |
| `rewrite`, `multi-step`, `cross-service`, `breaking`, `major refactor`, `redesign` | 8 |
| (caller indicates spike via `--type spike`) | 3 |

If `$POINTS` was set via `--points`, validate it's in the Fibonacci set; reject otherwise. If unset, in interactive mode show the prompt with the guess; in `$NO_PROMPT = true` mode use the guess.

### 3d. Priority (`priority`) — keyword-driven

Always set. LOR has both legacy ("Blocker/Critical/Major/Minor/Trivial") and modern priorities; we use the **modern set**: Highest, High, Medium, Low, Lowest. JIRA's default is Medium.

**Scale guide:**

| Priority | When to choose |
|---|---|
| **Highest** | Outage, data loss, security breach, P0 incident follow-up, on-call active page. |
| **High** | User-blocking regression, churn-risk bug, time-sensitive launch dependency. |
| **Medium** | Default. Normal feature work and non-blocking bugs. |
| **Low** | Polish, cleanup, nice-to-have improvements, low-impact bugs. |
| **Lowest** | Documentation tweaks, comment fixes, no-impact housekeeping. |

**Heuristic from summary text** (case-insensitive, first match wins):

| Summary keywords | Priority |
|---|---|
| `outage`, `data loss`, `security`, `breach`, `p0`, `paging`, `incident`, `blocker` | Highest |
| `regression`, `crash`, `5xx`, `urgent`, `critical`, `broken in prod`, `customer-blocking` | High |
| `typo`, `comment`, `copy`, `wording`, `doc`, `readme` | Lowest |
| `polish`, `cleanup`, `nit`, `nice-to-have`, `tweak`, `minor` | Low |
| (no match, default) | Medium |
| (issue type = Bug) | High (overrides default Medium — bugs default higher) |

If `$PRIORITY` was set via `--priority`, validate it's one of the modern five; reject otherwise. Skip prompt in `$NO_PROMPT = true` mode.

### 3e. Parent Epic (`parent.key`) — search the board, score, pick best

If `$EPIC_KEY` was set via `--epic`, use it directly and skip the search.

Otherwise, fetch **all open Epics on the LOR board** and score them for relevance to the new story. The best one wins; ties or low confidence go to the user.

**Step 1 — Fetch.** Get every open Epic in LOR (the board scope):

```
mcp__atlassian__searchJiraIssuesUsingJql({
  cloudId: $CLOUD_ID,
  jql: 'project = LOR AND issuetype = Epic AND statusCategory != Done ORDER BY updated DESC',
  fields: ["summary", "status", "updated", "customfield_11018", "labels"],
  maxResults: 100
})
```

**Step 2 — Score each Epic.** Compute a relevance score against the new story's summary, category, and (if set) Cap Project. Higher is better; cap each component to keep scoring legible.

| Signal | Points | Notes |
|---|---|---|
| Epic's Cap Project ID matches `$CAP_PROJECT_ID` (and Cap Project is not "Other") | **+50** | Strongest signal when Cap Project is specific. If `$CAP_PROJECT_ID = 10215` (Other), award 0 here — the field is too generic to be informative. |
| Each meaningful token in the new summary that appears in the Epic's summary (case-insensitive, ignore stopwords like `the`, `a`, `and`, `for`, `add`, `fix`, `update`) | **+10 per token, cap at +40** | Use word-boundary matches; partial substrings only if length ≥ 5 chars. |
| Epic was updated in the last 14 days | **+5** | Active epics outrank stale ones at ties. |
| Epic label intersects derived labels from Phase 4 (e.g. both have `frontend`) | **+5 per overlap, cap at +10** | Weak signal but useful as a tiebreaker. |

**Step 3 — Pick.** Sort by score descending.

- **Top score ≥ 50 AND beats #2 by ≥ 20** → auto-link. Output note: `Parent: LOR-NNNN (auto, score N, beat #2 by M)`.
- **Top score ≥ 50 but lead < 20** (close call) AND `$NO_PROMPT = false` → show the top 5 (key, summary, score, why-it-scored) and prompt: "Pick a number or `0` for none." Default to the top one.
- **Top score < 50** AND `$NO_PROMPT = false` → show the top 5 anyway with a warning: "No strong match; best guess is LOR-NNNN. Pick a number or `0` for none." Default to `0` (no parent).
- **`$NO_PROMPT = true`** → only auto-link if Top score ≥ 70 AND beats #2 by ≥ 30 (a stricter bar for automation). Otherwise skip with note: `Parent: (skipped — top score N too weak for auto-pick; pass --epic to set)`.

**Why score-then-pick instead of strict-filter:** earlier versions of this skill filtered Epics strictly by Cap Project ID, but that breaks down when (a) the Story's Cap Project is "Other" (~30% of cases), (b) the Epic is tagged with a different but related Cap Project, or (c) the Epic was created before Cap Projects were rolled out. Scoring across all open Epics handles those cases gracefully — Cap Project remains the dominant signal when present, summary-overlap fills in otherwise.

**Tokenization for summary overlap:** split on whitespace and punctuation, lowercase, drop tokens shorter than 3 chars, drop stopwords (`the`, `a`, `an`, `and`, `or`, `for`, `to`, `in`, `on`, `of`, `add`, `fix`, `update`, `new`, `support`, `enable`). Reasonable hit-rate matters more than perfect linguistics — this is a heuristic.

---

## Phase 4: Assemble initial payload

```json
{
  "cloudId": "$CLOUD_ID",
  "projectKey": "LOR",
  "issueTypeName": "$ISSUE_TYPE",
  "summary": "$SUMMARY",
  "description": "$DESCRIPTION",
  "additionalFields": {
    "assignee": { "accountId": "$MY_ACCOUNT_ID" },
    "priority": { "name": "$PRIORITY" },
    "customfield_11045": { "id": "<category_id>" },
    "customfield_11018": { "id": "<cap_project_id>" },
    "customfield_10005": $POINTS,
    "customfield_10600": { "accountId": "712020:04910a22-e552-4ffe-b610-36103d3315b9" },
    "labels": [<category_label>, ...derived_labels]
  }
}
```

Append conditionally:
- If `$SPRINT_MODE = active` AND `$ACTIVE_SPRINT` exists → `"customfield_10007": $ACTIVE_SPRINT.id`
- If `$EPIC_KEY` resolved (explicit or auto-search) → `"parent": { "key": "$EPIC_KEY" }` (some workflows use `customfield_10008` instead; if the first create fails, retry with the alternate shape — see Phase 5 retry rules)

Category label mapping (for the labels array — these are kept lowercase-hyphenated to match historical labels):
- Roadmap → `Roadmap`
- Product Improvement → `Product-improvements`
- Technology Improvement → `Technology-improvement`
- KTLO → `KTLO`

Derived labels (heuristic from summary text):
- `frontend`, `ui`, `component` → `frontend`
- `api`, `backend`, `server`, `worker` → `backend`
- `test`, `spec`, `coverage` → `tests`
- `docker`, `ci`, `infra`, `pipeline` → `infrastructure`
- At most 3 derived labels, plus the category label.

---

## Phase 5: Try → parse → fill → retry loop (max 3 attempts)

If `$DRY_RUN = true`, print the payload and stop here.

### Attempt 1

```
createJiraIssue(<payload>)
```

**On success** → save `$TICKET_KEY` from response. Skip to Phase 6.

**On 400 (validation error)** → parse:
- `errorMessages` (array of human strings)
- `errors` (per-field map: `{ "<field>": "<message>" }`)

For each field in `errors`, apply rules:

| Field key (or message hints) | Rule |
|---|---|
| `summary` | Should never happen; we always pass it. Surface and stop. |
| `description` | Same. |
| `assignee` | Likely a permission/format issue. Surface and stop. |
| `customfield_10007` (Sprint) | Drop sprint and retry in backlog. Warn the user. |
| `parent` / `customfield_10008` (Epic Link) — if epic was set | Swap shape: try `customfield_10008: "$EPIC_KEY"` instead of `parent: {key: "$EPIC_KEY"}`, or vice versa. If both shapes fail, drop the parent entirely and warn. |
| `customfield_10005` (Story Points) | If value isn't accepted (e.g., field expects integer not float), retry with `int($POINTS)`. If still failing, drop the field and warn. |
| `customfield_11045` (Investment Category) — invalid option | Means our cached options list is stale. Refresh via `getJiraIssueTypeMetaWithFields` and re-match. |
| `customfield_11018` (Capitalizable Project) — invalid option | If the value is a known legacy alias (Phase 3b table), swap to the current option and retry. Otherwise refresh via `getJiraIssueTypeMetaWithFields` and re-match; if still invalid, fall back to `Other` (10215) and warn. |
| `customfield_*` (any other custom field) | **Prompt the user** for the value. Show the JIRA error message verbatim. Common cases: Environment Source (for bugs), Severity (for bugs). |
| `priority` | If our chosen value is rejected, retry with `{name: "Medium"}` and warn. |
| `reporter` | Default to `{accountId: $MY_ACCOUNT_ID}` and retry. |
| `labels` | Likely we passed a label that doesn't exist. Drop derived labels (keep only the category label) and retry. |
| Anything else | Prompt the user with the JIRA message verbatim. |

After collecting fixes, **rebuild the payload** with the new fields and retry.

### Attempt 2 / 3

Same logic. If we hit a field we've already prompted for once and it's still failing, **STOP** — don't loop forever asking the same question. Tell the user the loop is stuck and dump everything.

### Final failure (after 3 attempts)

Print:

```
═════════════════════════════════════════════════════════════════════════
🚨 /create-story could not create the ticket after 3 attempts.

Last error:
  <full errorMessages and errors map>

Payload attempted:
  <pretty-printed JSON>

Create manually:
  https://affinipay.atlassian.net/jira/software/c/projects/LOR/issues/?jql=
  (Use the "+ Create" button. Copy fields from the payload above.)
═════════════════════════════════════════════════════════════════════════
```

Exit with non-zero status (caller `/push-story` should detect and stop its own flow).

---

## Phase 6: Verify the ticket landed

After a successful create, verify with a read-back:

```
getJiraIssue({
  cloudId: $CLOUD_ID,
  issueIdOrKey: "$TICKET_KEY",
  fields: ["summary", "status", "assignee", "priority", "parent", "customfield_10007", "customfield_10005", "customfield_10600", "customfield_11018", "customfield_11045"]
})
```

Confirm:
- Project key starts with `LOR-`
- Summary matches what we sent
- Assignee accountId = `$MY_ACCOUNT_ID`
- Priority name = `$PRIORITY`
- Story Points = `$POINTS`
- Investment Category id = `<category_id>`
- Capitalizable Project id = `<cap_project_id>`
- Tester accountId = `712020:04910a22-e552-4ffe-b610-36103d3315b9` (Patrick Duff)
- Sprint matches `$ACTIVE_SPRINT.id` (if active sprint mode)
- Parent key = `$EPIC_KEY` (if set)

If anything is off, warn but don't roll back (the ticket exists; the user can fix). List any silently-dropped fields explicitly in the Phase 7 output's "Notes:" section.

---

## Phase 7: Summary output

The output format MUST be parseable by `/push-story` (which extracts the key). Lead with the key on its own line.

```
═════════════════════════════════════════════════════════════════════════
✓ Created LOR-NNNN

Key:         LOR-NNNN
URL:         https://affinipay.atlassian.net/browse/LOR-NNNN
Summary:     <summary>
Type:        <type>
Status:      <status>
Assignee:    <you>
Tester:      Patrick Duff
Sprint:      <sprint name or "Backlog">
Priority:    <priority>
Points:      <points>
Category:    <Investment Category>
Cap Project: <Capitalizable Project>
Parent:      <epic key + summary, or "(none)" with reason>
Labels:      <comma-separated>
═════════════════════════════════════════════════════════════════════════
```

If we had to drop the sprint, drop the parent, swap an epic-link shape, fall back on priority, or any other unusual outcome, add a `Notes:` section listing what was changed from the original intent.

---

## Important Rules

1. **LOR project only.** Hard-coded. Refuse anything else.
2. **The error response is the source of truth.** Never silently fill required fields based on guesses — always prompt the user OR use a known-safe default and warn.
3. **Cap the retry loop at 3.** Don't loop forever. Better to dump everything and let the user finish manually than spam JIRA with bad payloads.
4. **Cache `$LAST_CAP_PROJECT` in-session.** Don't re-ask Capitalizable Project for back-to-back calls — it's almost always the same per work area.
5. **Always set Investment Category, Capitalizable Project, Story Points, Priority.** These are the team's grooming/reporting backbone — heuristic-guess + one-prompt-to-confirm is cheaper than letting them be empty. Parent is best-effort: auto-link if there's exactly one open Epic for the Cap Project (excluding "Other"), otherwise prompt or skip.
6. **`$NO_PROMPT = true` mode is for automation.** It uses heuristic defaults across the board and fails fast on missing-field errors — no prompts. Use this when calling from another skill that needs deterministic behavior.
7. **`--dry-run` never calls the API.** Useful for iterating on this skill's payload shape without spamming JIRA.
8. **`## Acceptance Criteria` is the idempotency anchor for `/update-qa-steps`.** Always include this heading in the description, followed by `- [ ]` checklist items (one or more — even a placeholder is fine). `/update-qa-steps` replaces this section in place by matching the heading. Do not invent a different heading name and do not nest the section under another heading.
9. **Don't link epics by `parent.key` AND `customfield_10008` simultaneously.** Pick one; let Phase 5 swap if the first fails. Both at once usually fails.
10. **Read-back in Phase 6 is non-optional.** A 200 response from `createJiraIssue` doesn't always mean every field landed. The read-back catches silently-dropped fields (e.g., a sprint assignment that wasn't allowed, or a stale custom-field option ID).
11. **The skill is meant to be iterated on.** Expect to update this file as JIRA's required-field surface changes. The retry loop is the safety net; the inline option lists in Phase 3 are the optimization. Refresh them via `getJiraIssueTypeMetaWithFields` whenever JIRA rejects a value as invalid.
12. **Fibonacci points only.** Reject any `--points N` where N is not in `{1, 2, 3, 5, 8, 13, 21}`.
13. **Parent search scores all open Epics, doesn't strict-filter.** Cap Project is the strongest signal but not the only one — summary-keyword overlap, recency, and label overlap also contribute. When Cap Project = Other (10215), Cap Project contributes 0 and the other signals carry the decision. Auto-link only on confident wins; otherwise prompt or skip.
14. **Tester is always Patrick Duff.** `customfield_10600` is hard-coded to accountId `712020:04910a22-e552-4ffe-b610-36103d3315b9`. No prompt, no override flag. If this needs to change, edit the skill — don't work around it per-call. If JIRA rejects the value (account deactivated, permission change), surface the error and stop rather than silently dropping the field.
