#!/usr/bin/env bash
# SessionStart. Fotografa lo stato del repository per journal-check e ricorda le
# regole del cantiere. La firma dei commit non passa piu' da qui: vedi agent-env.py.
set -uo pipefail
INPUT=$(cat 2>/dev/null || echo '{}')
SID=$(printf '%s' "$INPUT" | python3 -c 'import sys,json
try: print(json.load(sys.stdin).get("session_id",""))
except Exception: print("")' 2>/dev/null)
if [ -n "$SID" ] && git rev-parse --git-dir >/dev/null 2>&1; then
  python3 "$(dirname "$0")/journal-stato.py" foto "$SID" 2>/dev/null || true
fi
# residui del marcatore di ruolo su file, abbandonato il 21/09
rm -f .work/.current-agent 2>/dev/null
C=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null) && rm -f "$C/cantiere-current-agent"
cat <<'MSG'
Cantiere attivo.
Gate umani: nessun push su main, nessun merge di PR, nessun comando su produzione.
Una sessione per worktree: la checkout principale e' di Andrea.
Committa ogni volta che una cosa sta in piedi, e comunque entro 20 minuti: oltre,
il gate a tempo ti ferma. Non per non perdere lavoro — perche' se ti fermi al tetto
dei turni il tuo lavoro lo committa un altro e il trailer porta il suo nome.
Leggi contracts/ prima di scrivere codice.
Scrivi in journal/ MENTRE lavori, con ts preso da `date -Is`: ogni decisione, ogni gate,
ogni fallimento, ogni misura. Un giro senza fallimenti registrati e' un journal
incompleto, non un lavoro perfetto.
MSG
exit 0
