#!/usr/bin/env bash
# PostToolUse su Edit|Write. Se un segreto finisce in un file, blocca e lo dice.
#
# E' un gate anche se arriva dopo: il file e' gia' scritto e PostToolUse non lo
# disfa, ma l'uscita 2 porta il messaggio all'agente, che e' cio' che lo ferma prima
# del commit.
# FAIL-CLOSED (03/10). Misurato con un'esca: senza python3, senza grep, con un payload
# che non si legge e con un file illeggibile l'hook usciva con 0, cioe' «nessun
# segreto». Ora dice che il file NON e' stato controllato.
set -uo pipefail
rotto() { echo "gate in errore: guard-secrets: $1: il file NON e' stato controllato per i segreti. Controllalo a mano prima di committare e riportalo ad Andrea." >&2; exit 2; }
command -v python3 >/dev/null 2>&1 || rotto "python3 non e' nel PATH"
INPUT=$(cat)
FILE=$(printf '%s' "$INPUT" | python3 -c 'import sys,json
v = json.load(sys.stdin)["tool_input"]["file_path"]
if not isinstance(v, str) or not v.strip(): sys.exit(1)
print(v)' 2>/dev/null) \
  || rotto "il payload non e' JSON valido o manca tool_input.file_path"
[ -f "$FILE" ] || exit 0
[ -r "$FILE" ] || rotto "non posso leggere $FILE"
case "$FILE" in *.example|*.sample|*.md) exit 0 ;; esac

PAT='(AKIA[0-9A-Z]{16}|sk-[A-Za-z0-9]{32,}|ghp_[A-Za-z0-9]{36}|xox[baprs]-[A-Za-z0-9-]{10,}|-----BEGIN [A-Z ]*PRIVATE KEY-----|(password|passwd|secret|api_?key|token)[[:space:]]*[=:][[:space:]]*["'"'"'][^"'"'"'${}]{12,}["'"'"'])'
# grep: 0 = trovato, 1 = non trovato, altro = non ha cercato (assente dal PATH,
# espressione rifiutata, errore di lettura)
grep -nEi "$PAT" "$FILE" >/dev/null 2>&1; RC=$?
case "$RC" in
  0) echo "SEGRETO in $FILE. Rimuovilo e leggilo da variabile d'ambiente o dal secret manager. Non committare." >&2
     exit 2 ;;
  1) exit 0 ;;
  *) rotto "grep e' uscito con $RC su $FILE" ;;
esac
