#!/usr/bin/env bash
# PostToolUse su Edit|Write. Se un segreto finisce in un file, blocca e lo dice.
set -uo pipefail
INPUT=$(cat)
FILE=$(printf '%s' "$INPUT" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("tool_input",{}).get("file_path",""))' 2>/dev/null || echo "")
[ -f "$FILE" ] || exit 0
case "$FILE" in *.example|*.sample|*.md) exit 0 ;; esac

PAT='(AKIA[0-9A-Z]{16}|sk-[A-Za-z0-9]{32,}|ghp_[A-Za-z0-9]{36}|xox[baprs]-[A-Za-z0-9-]{10,}|-----BEGIN [A-Z ]*PRIVATE KEY-----|(password|passwd|secret|api_?key|token)[[:space:]]*[=:][[:space:]]*["'"'"'][^"'"'"'${}]{12,}["'"'"'])'
if grep -nEi "$PAT" "$FILE" >/dev/null 2>&1; then
  echo "SEGRETO in $FILE. Rimuovilo e leggilo da variabile d'ambiente o dal secret manager. Non committare." >&2
  exit 2
fi
exit 0
