#!/usr/bin/env bash
# PostToolUse su Edit|Write. Formatta e verifica solo il file toccato.
# Exit 2 rimanda l'errore all'agente, che corregge senza che tu intervenga.
#
# 03/10 — e' un hook INFORMATIVO: aiuta l'agente a correggersi, non protegge niente.
# Se si rompe non blocca, ma lo dice nel contesto: additionalContext di PostToolUse
# con uscita 0 arriva all'agente (misurato con Claude Code 2.1.288), mentre un'uscita
# 1 o 127 non arriva a nessuno. Prima, senza python3 o con un payload che non si
# legge, usciva con 0 senza avere verificato niente. Gli strumenti di un linguaggio
# assenti (gofmt, ruff, npx, ...) restano un salto silenzioso voluto: un progetto
# non li ha tutti.
set -uo pipefail
guasto() { # messaggi costanti senza virgolette: entrano in un JSON cosi' come sono
  printf '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"hook informativo in errore: verify-after-edit: %s. Il file appena scritto NON e stato formattato ne verificato: dillo ad Andrea."}}\n' "$1"
  exit 0
}
command -v python3 >/dev/null 2>&1 || guasto "python3 non e nel PATH"
INPUT=$(cat)
FILE=$(printf '%s' "$INPUT" | python3 -c 'import sys,json
v = json.load(sys.stdin)["tool_input"]["file_path"]
if not isinstance(v, str) or not v.strip(): sys.exit(1)
print(v)' 2>/dev/null) \
  || guasto "il payload non e JSON valido o manca tool_input.file_path"
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
