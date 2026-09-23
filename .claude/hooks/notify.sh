#!/bin/bash
# Desktop notification for Claude Code hook events.
# Usage: notify.sh <permission|elicitation>
#
# Notifies only when Claude needs you: a permission request or an interview
# question. Deliberately silent when a turn merely finishes -- `notify.sh stop`
# is accepted and does nothing.
#
# xirp tabs are tmux panes, not Terminal.app tabs. When this hook runs inside a
# tmux session named `xirp-<uuid>` it targets that tab directly:
#   - "View" focuses it with the xirp://open-session deep link, which raises the
#     Xirp window (main process app.focus({steal:true})) and selects the tab.
#   - "Allow"/"Always" are delivered with `tmux send-keys` to the asking PANE,
#     so they can never land in whichever tab happens to be visible.
# Outside xirp it falls back to the old Terminal/iTerm2/Warp/VS Code behaviour.
#
# Env:
#   CLAUDE_NOTIFY_DEBUG=0                      stop logging to hooks/notify.log
#   CLAUDE_NOTIFY_TIMEOUT=45                   seconds before the alert gives up

EVENT="$1"
INPUT=$(cat)

PY=/usr/bin/python3
LOG="$HOME/.claude/hooks/notify.log"
TIMEOUT="${CLAUDE_NOTIFY_TIMEOUT:-45}"

log() {
  [ "${CLAUDE_NOTIFY_DEBUG:-1}" = "1" ] || return 0
  printf '%s %s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$EVENT" "$*" >> "$LOG"
  # keep the log small
  if [ "$(wc -l < "$LOG" 2>/dev/null || echo 0)" -gt 400 ]; then
    tail -n 200 "$LOG" > "$LOG.tmp" && mv "$LOG.tmp" "$LOG"
  fi
}

# ---------------------------------------------------------------- tab identity

XIRP_SID=""
TMUX_SESSION=""
PANE=""

if [ -n "${TMUX_PANE:-}" ] && command -v tmux >/dev/null 2>&1; then
  INFO=$(tmux display-message -p -t "$TMUX_PANE" '#S|#D' 2>/dev/null)
  if [ -n "$INFO" ]; then
    TMUX_SESSION="${INFO%%|*}"
    PANE="${INFO##*|}"
    case "$TMUX_SESSION" in
      xirp-*) XIRP_SID="${TMUX_SESSION#xirp-}" ;;
    esac
  fi
fi

# Legacy terminal detection, used only when we are not in a xirp tab.
case "${TERM_PROGRAM:-}" in
  WarpTerminal)   APP_NAME="Warp" ;;
  iTerm.app|iTerm2) APP_NAME="iTerm2" ;;
  vscode)         APP_NAME="Code" ;;
  *)              APP_NAME="Terminal" ;;
esac
CLAUDE_TTY="/dev/$(ps -o tty= -p $PPID 2>/dev/null | tr -d ' ')"

# xirp project names, cached for 10 minutes (id -> name).
PROJ_CACHE="${TMPDIR:-/tmp}/claude-notify-xirp-projects.json"
project_cache() {
  if [ ! -f "$PROJ_CACHE" ] || [ -n "$(find "$PROJ_CACHE" -mmin +10 2>/dev/null)" ]; then
    xirp project list --json 2>/dev/null > "$PROJ_CACHE.tmp" \
      && mv "$PROJ_CACHE.tmp" "$PROJ_CACHE" \
      || rm -f "$PROJ_CACHE.tmp"
  fi
  printf '%s' "$PROJ_CACHE"
}

# Human label for the tab: xirp session name + project name.
tab_label() {
  local label=""
  if [ -n "$XIRP_SID" ] && command -v xirp >/dev/null 2>&1; then
    label=$(xirp session get "$XIRP_SID" --json 2>/dev/null | "$PY" -c '
import sys, json, os
try:
    d = json.load(sys.stdin)
except Exception:
    raise SystemExit(1)
name = (d.get("name") or "").strip()
if len(name) > 48:
    name = name[:47].rstrip() + "…"

# Prefer the xirp project name; a worktree directory basename is unreadable.
where = ""
try:
    with open(sys.argv[1]) as fh:
        for proj in json.load(fh):
            if proj.get("id") == d.get("projectId"):
                where = proj.get("name") or ""
                break
except Exception:
    pass
if not where:
    wt = (d.get("worktreePath") or "").rstrip("/")
    where = os.path.basename(wt) if wt else ""
    if len(where) > 24:
        where = where[:23].rstrip() + "…"

branch = (d.get("branch") or "").strip()
if branch in ("HEAD", "main", "master"):
    branch = ""
parts = [p for p in (name, where, branch) if p]
print(" · ".join(parts))
' "$(project_cache)" 2>/dev/null)
  fi
  if [ -z "$label" ]; then
    label=$(printf '%s' "$INPUT" | "$PY" -c '
import sys, json, os
try:
    d = json.load(sys.stdin)
except Exception:
    d = {}
cwd = d.get("cwd") or ""
print(os.path.basename(cwd.rstrip("/")) or "Claude Code")
' 2>/dev/null)
  fi
  [ -z "$label" ] && label="Claude Code"
  printf '%s' "$label"
}

# --------------------------------------------------------------------- actions

focus_tab() {
  if [ -n "$XIRP_SID" ]; then
    # Raises the Xirp window AND selects this session's tab.
    open "xirp://local/?action=open-session&sessionId=$XIRP_SID"
    log "focus xirp $XIRP_SID"
    return
  fi
  if [ "$APP_NAME" = "Terminal" ]; then
    osascript <<EOF
tell application "Terminal"
  repeat with w in windows
    repeat with t in tabs of w
      if tty of t is "$CLAUDE_TTY" then
        set selected of t to true
        set index of w to 1
      end if
    end repeat
  end repeat
  activate
end tell
EOF
  else
    osascript -e "tell application \"$APP_NAME\" to activate"
  fi
  log "focus $APP_NAME"
}

# True when the asking pane is still showing a Claude Code choice prompt.
pane_awaiting_choice() {
  [ -n "$PANE" ] || return 1
  local tail_text
  tail_text=$(tmux capture-pane -p -t "$PANE" -S -25 2>/dev/null) || return 1
  # Every Claude Code permission dialog asks "Do you want to ...?" and renders a
  # numbered option list. Requiring both keeps ordinary output from matching.
  printf '%s' "$tail_text" | grep -qE 'Do you want to ' || return 1
  printf '%s' "$tail_text" | grep -qE '^[[:space:]]*.?[[:space:]]*2\.[[:space:]]' || return 1
  return 0
}

answer() {
  # $1 = the digit to send
  if [ -n "$PANE" ]; then
    if pane_awaiting_choice; then
      tmux send-keys -t "$PANE" -l "$1" 2>/dev/null
      log "send-keys -t $PANE '$1'"
    else
      log "send-keys skipped: pane $PANE no longer prompting; focusing instead"
      focus_tab
    fi
    return
  fi
  # Legacy: activate the terminal and type into it.
  if [ "$APP_NAME" = "Terminal" ]; then
    osascript <<EOF
set prevApp to path to frontmost application as text
tell application "Terminal"
  repeat with w in windows
    repeat with t in tabs of w
      if tty of t is "$CLAUDE_TTY" then
        set selected of t to true
        set index of w to 1
      end if
    end repeat
  end repeat
  activate
end tell
tell application "System Events"
  tell process "Terminal"
    keystroke "$1"
  end tell
end tell
activate application prevApp
EOF
  else
    osascript <<EOF
set prevApp to path to frontmost application as text
tell application "$APP_NAME" to activate
tell application "System Events"
  tell process "$APP_NAME"
    keystroke "$1"
  end tell
end tell
activate application prevApp
EOF
  fi
  log "keystroke $1 -> $APP_NAME"
}

# show_alert <title> <message> <button1> [button2] [button3]
# Last button is the default. Echoes the button label, or GAVEUP.
show_alert() {
  osascript - "$TIMEOUT" "$@" <<'EOF' 2>/dev/null
on run argv
  set givingUp to (item 1 of argv) as integer
  set theTitle to item 2 of argv
  set theMsg to item 3 of argv
  set btns to {}
  repeat with i from 4 to (count of argv)
    set end of btns to (item i of argv)
  end repeat
  set dflt to item (count of argv) of argv
  set res to display alert theTitle message theMsg buttons btns default button dflt giving up after givingUp
  if gave up of res then return "GAVEUP"
  return button returned of res
end run
EOF
}

# ---------------------------------------------------------------------- events

LABEL=$(tab_label)
log "label='$LABEL' xirp_sid='$XIRP_SID' pane='$PANE' term='${TERM_PROGRAM:-}'"

case "$EVENT" in
  permission)
    PARSED=$(printf '%s' "$INPUT" | "$PY" -c '
import sys, json
try:
    data = json.load(sys.stdin)
except Exception:
    data = {}
tool = data.get("tool_name", "unknown tool")
tool_input = data.get("tool_input", {}) or {}
if tool == "Bash":
    cmd = tool_input.get("command", "")
    description = tool_input.get("description", "")
    desc = f"{description}\n\n{cmd}" if description else cmd
elif tool in ("Edit", "Write", "Read"):
    desc = tool_input.get("file_path", "")
else:
    desc = json.dumps(tool_input)
if len(desc) > 600:
    desc = desc[:599] + "…"

always = ""
for s in data.get("permission_suggestions", []) or []:
    if s.get("type") == "addRules" and s.get("behavior") == "allow":
        rules = s.get("rules", [])
        if rules:
            r = rules[0]
            tn = r.get("toolName", "")
            rule = (r.get("ruleContent", "") or "").replace("//", "/")
            if tn and rule:
                always = f"Always allow {tn} {rule}"
            elif tn:
                always = f"Always allow {tn}"
if not always and data.get("permission_suggestions"):
    always = "Always"
if len(always) > 60:
    always = always[:59] + "…"
print(json.dumps({"msg": f"{tool}: {desc}", "always": always}))
' 2>/dev/null)

    MSG=$(printf '%s' "$PARSED" | "$PY" -c 'import sys,json; print(json.load(sys.stdin)["msg"])' 2>/dev/null)
    ALWAYS_LABEL=$(printf '%s' "$PARSED" | "$PY" -c 'import sys,json; print(json.load(sys.stdin)["always"])' 2>/dev/null)
    [ -z "$MSG" ] && MSG="Needs permission"

    if [ -n "$ALWAYS_LABEL" ]; then
      RESPONSE=$(show_alert "$LABEL" "$MSG" "View" "$ALWAYS_LABEL" "Allow")
    else
      RESPONSE=$(show_alert "$LABEL" "$MSG" "View" "Allow")
    fi
    log "response='$RESPONSE'"

    if [ "$RESPONSE" = "Allow" ]; then
      answer "1"
    elif [ "$RESPONSE" = "View" ]; then
      focus_tab
    elif [ -n "$ALWAYS_LABEL" ] && [ "$RESPONSE" = "$ALWAYS_LABEL" ]; then
      answer "2"
    fi
    ;;

  elicitation)
    log "payload keys: $(printf '%s' "$INPUT" | "$PY" -c 'import sys,json
try: print(",".join(sorted(json.load(sys.stdin).keys())))
except Exception: print("unparsed")' 2>/dev/null)"
    MSG=$(printf '%s' "$INPUT" | "$PY" -c '
import sys, json
try:
    d = json.load(sys.stdin)
except Exception:
    d = {}
msg = d.get("message") or d.get("prompt") or d.get("question") or "Claude is waiting for your input."
if not isinstance(msg, str):
    msg = json.dumps(msg)
print(msg[:600])
' 2>/dev/null)
    [ -z "$MSG" ] && MSG="Claude is waiting for your input."
    RESPONSE=$(show_alert "$LABEL" "$MSG" "Dismiss" "View")
    log "response='$RESPONSE'"
    [ "$RESPONSE" = "View" ] && focus_tab
    ;;

  *)
    log "unhandled event"
    ;;
esac
