#!/usr/bin/env bash
# resume-digest.sh — Claude Code `SessionStart` hook (matcher: all; self-gates on source).
# Emits a COMPACT digest of the PREVIOUS session (last user msg + last assistant msg + uncommitted
# git state) to STDOUT, which CC injects into the new session's context BEFORE the first turn.
# Result: a fresh/post-crash session is oriented instantly — no "let me investigate" archaeology,
# no `claude --continue`. Pure shell → costs ZERO model tokens to produce; the digest itself is a
# few hundred tokens. Full readable mirror lives at ~/.config/CLAUDE/transcript/<id>.md.
set -u

payload="$(cat)"
sid="$(printf '%s' "$payload" | jq -r '.session_id // empty' 2>/dev/null)"
cwd="$(printf '%s' "$payload" | jq -r '.cwd // empty'        2>/dev/null)"
src="$(printf '%s' "$payload" | jq -r '.source // empty'     2>/dev/null)"

# Only orient on a real (re)start. `clear` = deliberate fresh start; `compact` already has a summary.
case "$src" in startup|resume|"") ;; *) exit 0 ;; esac

# Project transcript dir = CC's per-cwd encoding (non-alnum → '-'); fall back to newest across all.
enc="$(printf '%s' "$cwd" | sed 's#[^a-zA-Z0-9]#-#g')"
projdir="$HOME/.claude/projects/$enc"
[ -d "$projdir" ] || projdir="$HOME/.claude/projects"

# Newest *.jsonl that is NOT the current session.
prev=""
while IFS= read -r f; do
  case "$f" in *"$sid"*) continue ;; esac
  prev="$f"; break
done < <(find "$projdir" -maxdepth 2 -name '*.jsonl' -printf '%T@\t%p\n' 2>/dev/null | sort -rn | cut -f2-)
[ -n "$prev" ] && [ -r "$prev" ] || exit 0

LU="$(jq -rs '
  def t: if type=="array" then ([.[]?|select(.type=="text")|.text]|join("\n")) else (.//"") end;
  [ .[] | select(.type=="user") | .message.content
        | select((type=="string") or (type=="array" and (all(.[]?; .type!="tool_result"))))
        | t ] | map(select(length>0)) | (last // "")
  | if length>700 then (.[:700]+"…") else . end' "$prev" 2>/dev/null)"

LA="$(jq -rs '
  [ .[] | select(.type=="assistant")
        | [.message.content[]?|select(.type=="text")|.text] | join("\n") ]
  | map(select(length>0)) | (last // "")
  | if length>2200 then (.[:2200]+"…") else . end' "$prev" 2>/dev/null)"

[ -n "$LU$LA" ] || exit 0

short="$(basename "$prev" .jsonl)"
ts="$(date -d "@$(stat -c %Y "$prev" 2>/dev/null)" '+%Y-%m-%d %H:%M' 2>/dev/null)"
cfg="$(git -C "$HOME/.config" status --short 2>/dev/null | head -6)"
scr="$(git -C "$HOME/scripts" status --short 2>/dev/null | head -6)"

cat <<EOF
## ⟐ PREVIOUS SESSION — resume orientation (auto-injected; ignore if starting a different task)
session \`$short\` · last active ${ts:-?} · full readable mirror: ~/.config/CLAUDE/transcript/$short.md

### Last user message
$LU

### Last assistant message (usually the wrap-up + stated next steps)
$LA

### Uncommitted now
~/.config:
${cfg:-clean}
~/scripts:
${scr:-clean}

➤ RESUME FROM THE ABOVE. Do NOT re-run discovery/investigation to reconstruct state — this digest replaces that step. Open the full mirror only if this is insufficient.
EOF
exit 0
