#!/usr/bin/env bash
# PostToolUse su Edit|Write. Formatta e verifica solo il file toccato.
# Exit 2 rimanda l'errore all'agente, che corregge senza che tu intervenga.
set -uo pipefail
INPUT=$(cat)
FILE=$(printf '%s' "$INPUT" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("tool_input",{}).get("file_path",""))' 2>/dev/null || echo "")
[ -f "$FILE" ] || exit 0
OUT=""; RC=0
case "$FILE" in
  *.go)        command -v gofmt   >/dev/null && gofmt -w "$FILE"
               command -v go      >/dev/null && { OUT=$(go vet "$(dirname "$FILE")" 2>&1) || RC=1; } ;;
  *.ts|*.tsx|*.js|*.jsx)
               command -v npx     >/dev/null && npx --no-install prettier --write "$FILE" >/dev/null 2>&1
               command -v npx     >/dev/null && { OUT=$(npx --no-install eslint "$FILE" 2>&1) || RC=1; } ;;
  *.py)        command -v ruff    >/dev/null && { ruff format "$FILE" >/dev/null 2>&1; OUT=$(ruff check "$FILE" 2>&1) || RC=1; } ;;
  *.tf)        command -v terraform >/dev/null && terraform fmt "$FILE" >/dev/null 2>&1 ;;
  *.sql)       command -v sqlfluff >/dev/null && { OUT=$(sqlfluff lint "$FILE" 2>&1) || RC=1; } ;;
  *.json)      OUT=$(python3 -c "import json,sys;json.load(open('$FILE'))" 2>&1) || RC=1 ;;
  *.yml|*.yaml) OUT=$(python3 -c "import yaml,sys;list(yaml.safe_load_all(open('$FILE')))" 2>&1) || RC=1 ;;
esac
if [ "$RC" -ne 0 ]; then
  echo "Verifica fallita su $FILE:" >&2
  echo "$OUT" | head -40 >&2
  exit 2
fi
exit 0
