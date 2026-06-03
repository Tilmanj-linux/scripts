#!/usr/bin/env bash
# sync-dump.sh — deterministic catch-up artifact for the 30.01 CC<->Proper sync-loop (A16).
#
# Emits ONE structured, append-ready Markdown block to stdout: the system + doc deltas since
# the last marked sync. Re-provide the block to Proper (the claude.ai planner) at boot/shutdown
# so it catches up WITHOUT Claude burning tokens regenerating state. Token-light by design;
# append order encodes supersession.
#
#   ~/scripts/sync-dump.sh                  # print the catch-up block (safe, non-mutating, repeatable)
#   ~/scripts/sync-dump.sh --mark           # ...and advance the sync marker to current HEAD
#   ~/scripts/sync-dump.sh --since <ref>    # override the delta baseline (git ref/sha)
#   ~/scripts/sync-dump.sh --out FILE       # also append the block to FILE
#
# Complements: session-state.sh (quick terminal paste) | system-snapshot.sh (full JSON to Drive).

set -uo pipefail

CFG="$HOME/.config"
SCRIPTS="$HOME/scripts"
DOCS="$CFG/CLAUDE"
STATE="$DOCS/.sync-state"          # git-ignored (only *.md is tracked under CLAUDE/)
TS="$(date +%Y-%m-%d_%H%M%S)"

# shellcheck source=/dev/null
[ -r "$SCRIPTS/lib/colors.sh" ] && . "$SCRIPTS/lib/colors.sh" || { warn(){ printf '! %s\n' "$*" >&2; }; ok(){ printf '%s\n' "$*" >&2; }; }

MARK=0; SINCE=""; OUT=""
while [ $# -gt 0 ]; do
  case "$1" in
    --mark)  MARK=1 ;;
    --since) SINCE="${2:-}"; shift ;;
    --out)   OUT="${2:-}"; shift ;;
    -h|--help) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) printf 'unknown arg: %s\n' "$1" >&2; exit 2 ;;
  esac
  shift
done

# --- delta baseline: --since override, else last-marked SHA, else 24h ago ---
last_cfg=""; last_scr=""
if [ -f "$STATE" ]; then
  last_cfg="$(awk -F= '/^config=/{print $2}'  "$STATE" 2>/dev/null)"
  last_scr="$(awk -F= '/^scripts=/{print $2}' "$STATE" 2>/dev/null)"
fi
base_cfg="${SINCE:-${last_cfg:-$(git -C "$CFG"     rev-list -1 --before='24 hours ago' HEAD 2>/dev/null)}}"
base_scr="${SINCE:-${last_scr:-$(git -C "$SCRIPTS" rev-list -1 --before='24 hours ago' HEAD 2>/dev/null)}}"

short() { git -C "$1" rev-parse --short "${2:-HEAD}" 2>/dev/null || echo "?"; }
ahead() { git -C "$1" rev-list --count '@{upstream}..HEAD' 2>/dev/null || echo "?"; }
logrange() { # repo base -> oneline log since base (or last 10 if base empty)
  local repo="$1" base="$2"
  if [ -n "$base" ] && git -C "$repo" cat-file -e "$base^{commit}" 2>/dev/null; then
    git -C "$repo" log --oneline "$base..HEAD" 2>/dev/null
  else
    git -C "$repo" log --oneline -n 10 2>/dev/null
  fi
}
probe() { command -v "$1" >/dev/null 2>&1; }

# ------------------------------------------------------------------ render
render() {
  printf '## ⟐ Littlebear sync — %s\n\n' "$TS"
  printf '**Baseline:** config@`%s` · scripts@`%s`  →  **now:** config@`%s` (ahead %s unpushed) · scripts@`%s` (ahead %s)\n' \
    "$(short "$CFG" "$base_cfg")" "$(short "$SCRIPTS" "$base_scr")" \
    "$(short "$CFG")" "$(ahead "$CFG")" "$(short "$SCRIPTS")" "$(ahead "$SCRIPTS")"

  printf '\n### Commits since baseline\n'
  local c s
  c="$(logrange "$CFG" "$base_cfg")";    printf '~/.config:\n%s\n'  "${c:-  (none)}"
  s="$(logrange "$SCRIPTS" "$base_scr")"; printf '~/scripts:\n%s\n' "${s:-  (none)}"

  printf '\n### Uncommitted now\n'
  local uc us
  uc="$(git -C "$CFG"     status -s 2>/dev/null)"
  us="$(git -C "$SCRIPTS" status -s 2>/dev/null)"
  printf '~/.config: %s\n' "$([ -n "$uc" ] && echo "$(printf '%s\n' "$uc" | wc -l) file(s)" || echo clean)"
  [ -n "$uc" ] && printf '%s\n' "$uc"
  printf '~/scripts: %s\n' "$([ -n "$us" ] && echo "$(printf '%s\n' "$us" | wc -l) file(s)" || echo clean)"
  [ -n "$us" ] && printf '%s\n' "$us"

  printf '\n### Earmarks touched in work docs\n'
  local marks
  if [ -n "$base_cfg" ] && git -C "$CFG" cat-file -e "$base_cfg^{commit}" 2>/dev/null; then
    marks="$(git -C "$CFG" log "$base_cfg..HEAD" -p -- CLAUDE/ 2>/dev/null | grep -oE '\b[AFSCR][0-9]+\b' | sort -uV | paste -sd' ' -)"
  fi
  local nmarks; nmarks="$(printf '%s' "$marks" | wc -w)"
  if [ "$nmarks" -gt 20 ]; then
    printf '  (%s ids — whole work-doc added in this range; tightens to real deltas after --mark)\n' "$nmarks"
  else
    printf '%s\n' "${marks:-  (no work-doc changes in range)}"
  fi

  printf '\n### Package drift\n'
  if [ -x "$SCRIPTS/package-diff.sh" ]; then
    bash "$SCRIPTS/package-diff.sh" 2>/dev/null | grep -iE 'drift|added|removed|^[[:space:]]*[+-]' | head -8 \
      || echo "  (package-diff produced no summary)"
  fi
  printf 'explicit: %s · AUR: %s\n' "$(pacman -Qe 2>/dev/null | wc -l)" "$(pacman -Qm 2>/dev/null | wc -l)"

  printf '\n### System facts\n'
  printf -- '- kernel: %s\n' "$(uname -r)"
  probe hyprctl && printf -- '- hyprland: %s | configerrors: %s\n' \
    "$(hyprctl version 2>/dev/null | awk '/^Hyprland/{print $2; exit}')" \
    "$(hyprctl configerrors 2>/dev/null | head -1)"
  if probe hyprctl; then
    hyprctl monitors -j 2>/dev/null | python3 -c '
import sys, json
try:
    ms = json.load(sys.stdin)
    parts = ["%s %dx%d@%.0f t%d" % (m["name"], m["width"], m["height"], m.get("refreshRate", 0), m.get("transform", 0)) for m in ms]
    print("- monitors: " + ", ".join(parts))
except Exception:
    pass' 2>/dev/null
  fi
  printf -- '- ~/Drive: %s | rclone-drive: %s\n' \
    "$(mountpoint -q "$HOME/Drive" && echo mounted || echo UNMOUNTED)" \
    "$(systemctl --user is-active rclone-drive 2>/dev/null || echo '?')"

  printf '\n_Re-provide this block to Proper. Run `sync-dump.sh --mark` once synced to advance the baseline._\n'
}

BLOCK="$(render)"
printf '%s\n' "$BLOCK"

if [ -n "$OUT" ]; then
  printf '\n%s\n' "$BLOCK" >> "$OUT" && ok "appended to $OUT"
fi

if [ "$MARK" -eq 1 ]; then
  { echo "# sync-dump baseline — advanced $TS"
    echo "config=$(short "$CFG")"
    echo "scripts=$(short "$SCRIPTS")"; } > "$STATE"
  ok "marker advanced → config@$(short "$CFG") scripts@$(short "$SCRIPTS")"
fi
