#!/usr/bin/env bash
# ~/scripts/lib/colors.sh — shared ANSI palette for script output. Source it.
# Degrades to plain when stdout isn't a TTY (piped/redirected) or NO_COLOR is set.
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  C_RESET=$'\e[0m'; C_BOLD=$'\e[1m'; C_DIM=$'\e[2m'
  C_OK=$'\e[32m'; C_ERR=$'\e[31m'; C_WARN=$'\e[33m'
  C_CLAY=$'\e[38;2;204;120;92m'      # Anthropic clay — accent / section headers
else
  C_RESET=''; C_BOLD=''; C_DIM=''; C_OK=''; C_ERR=''; C_WARN=''; C_CLAY=''
fi
ok()   { printf '%s✓%s %s\n'     "$C_OK"   "$C_RESET" "$*"; }
err()  { printf '%s✗%s %s\n'     "$C_ERR"  "$C_RESET" "$*"; }
warn() { printf '%s⚠%s %s\n'     "$C_WARN" "$C_RESET" "$*"; }
hdr()  { printf '%s▌ %s%s\n'     "$C_CLAY" "$*"        "$C_RESET"; }
rule() { printf '%s── %s ──%s\n' "$C_DIM"  "$*"        "$C_RESET"; }
