#!/usr/bin/env bash
# Stop. Se in questa sessione e' cambiato del lavoro ma journal/ non ha voci nuove,
# rimanda l'agente a scriverle. Una volta sola per sessione: il tracciamento e' una
# regola, non un cappio. Cosa conta come «cambiato» lo decide journal-stato.py,
# confrontando il contenuto con la foto presa all'avvio — non le date dei file.
set -uo pipefail
INPUT=$(cat 2>/dev/null || echo '{}')
git rev-parse --git-dir >/dev/null 2>&1 || exit 0
SID=$(printf '%s' "$INPUT" | python3 -c 'import sys,json
try: print(json.load(sys.stdin).get("session_id",""))
except Exception: print("")' 2>/dev/null)
[ -n "$SID" ] || exit 0
NUDGE=".work/sessioni/${SID//[^A-Za-z0-9_-]/}.sollecitata"
[ -f "$NUDGE" ] && exit 0

read -r LAVORO VOCI <<< "$(python3 "$(dirname "$0")/journal-stato.py" esame "$SID")"
[ "${LAVORO:-0}" -gt 0 ] || exit 0
[ "${VOCI:-0}" -gt 0 ] && exit 0

mkdir -p .work/sessioni; : > "$NUDGE"
cat <<'JSON'
{"decision":"block","reason":"In questa sessione e' cambiato del lavoro ma journal/ non ha voci nuove. Prima di chiudere scrivi le voci mancanti seguendo docs/JOURNAL.md: ogni decisione, ogni gate, ogni tentativo fallito, ogni misura. Il campo ts si prende da `date -Is` eseguito in quel momento, mai a memoria. Scrivile come sono andate davvero. Se ritieni che il lavoro contato non sia tuo, non scrivere una voce per farmi tacere: dillo, con la misura."}
JSON
exit 0
