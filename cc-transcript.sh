#!/usr/bin/env bash
# cc-transcript.sh — render the live Claude Code JSONL session transcript to a compact,
# human-readable markdown mirror under ~/.config/CLAUDE/transcript/.
#
# Fired by a CC `Stop` hook (runs after EVERY assistant turn → crash-safe: the mirror is
# current the instant a turn ends, even if the session is killed before SessionEnd).
# Reads the hook payload (JSON) on stdin → .transcript_path / .session_id.
#
# Thorough: full user + assistant text, and one line per tool CALL (the action trace).
# Low-token: tool arguments and tool results are each clipped to a single short line —
# the bulk (file bodies, command output) is summarized, not mirrored. For true full
# fidelity on resume, use `claude --continue` (the native JSONL is the source of truth).
set -u

OUTDIR="$HOME/.config/CLAUDE/transcript"
TRUNC_ARG=200      # max chars of a tool-call argument line
TRUNC_OUT=200      # max chars of a tool-result body

payload="$(cat)"
tpath="$(printf '%s' "$payload" | jq -r '.transcript_path // empty' 2>/dev/null)"
sid="$(printf '%s'   "$payload" | jq -r '.session_id // empty'     2>/dev/null)"
[ -n "${tpath:-}" ] && [ -r "$tpath" ] || exit 0
[ -n "${sid:-}" ] || sid="$(basename "$tpath" .jsonl)"

mkdir -p "$OUTDIR"
out="$OUTDIR/$sid.md"; tmp="$out.tmp.$$"

jq -rs --argjson ta "$TRUNC_ARG" --argjson to "$TRUNC_OUT" '
  def clip($n): (. // "") | tostring | gsub("\n";" ⏎ ")
                | if (length>$n) then (.[:$n] + "…") else . end;
  def argsum:  (.command // .file_path // .pattern // .path // .url
                // .description // (keys|join(","))) | clip($ta);
  def resof:   (if (.content|type)=="array"
                then ([.content[]?|select(.type=="text")|.text]|join("\n"))
                else (.content|tostring) end);
  .[]
  | (.message // {}) as $m
  | if .type=="user" then
      ( $m.content
        | if type=="string" then "\n### 👤 User\n\(.)"
          elif (type=="array" and any(.[]?; .type=="tool_result")) then
            ([.[]?|select(.type=="tool_result")|"    ⤷ "+(resof|clip($to))]|join("\n"))
          elif type=="array" then
            "\n### 👤 User\n"+([.[]?|select(.type=="text")|.text]|join("\n"))
          else empty end )
    elif .type=="assistant" then
      ( [ $m.content[]?
          | if   .type=="text"     then "\n### 🤖 Claude\n\(.text)"
            elif .type=="tool_use" then "  → **\(.name)** `\(.input|argsum)`"
            else empty end ] | join("\n") )
    elif .type=="summary" then "\n---\n**↻ summary:** \(.summary // "")"
    else empty end
' "$tpath" > "$tmp" 2>/dev/null || { rm -f "$tmp"; exit 0; }

{ printf '# CC transcript — %s\n_session `%s` · live mirror (Stop hook) · `claude --continue` for full fidelity_\n' \
    "$(date '+%Y-%m-%d %H:%M')" "$sid"
  cat "$tmp"
} > "$out"
rm -f "$tmp"
ln -sfn "$out" "$OUTDIR/latest.md"
exit 0
