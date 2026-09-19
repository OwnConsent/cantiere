#!/usr/bin/env bash
# Perche' i commit risultano tutti firmati "orchestrator".
#
# Il marcatore di ruolo lo scrive hooks/agent-stamp.sh quando parte un subagente.
# Se resta su "orchestrator" per tutto un giro, le possibilita' sono tre e si
# distinguono solo guardando cosa arriva davvero all'hook:
#   a. l'evento SubagentStart non scatta;
#   b. scatta ma il payload non porta il tipo del subagente;
#   c. scatta, il nome c'e', ma a committare e' il filo principale per conto
#      dell'agente — e allora la firma e' corretta e sbagliata era l'attesa.
#
#   ./diagnostica-firma.sh --attiva    aggiunge il log (modifica NON committata)
#   ./diagnostica-firma.sh --leggi     mostra cosa e' stato registrato
#   ./diagnostica-firma.sh --spegni    ripristina il file dal repository
#
# Fra --attiva e --leggi: apri una sessione e chiedi una cosa banale che faccia
# partire un subagente, per esempio
#   «Chiedi a @docs-writer di leggere docs/DEFINITION-OF-DONE.md e dirmi in una
#    riga cosa contiene.»
set -uo pipefail
H="$(cd "$(dirname "$0")" && pwd)"
F="$H/agent-stamp.sh"
LOG="${TMPDIR:-/tmp}/agent-stamp.log"
RIGA='printf '"'"'%s\n'"'"' "$INPUT" >> "'"$LOG"'"'

case "${1:-}" in
  --attiva)
    grep -q 'agent-stamp.log' "$F" && { echo "Log gia' attivo."; exit 0; }
    python3 - "$F" "$RIGA" <<'PY'
import sys
f, riga = sys.argv[1], sys.argv[2]
t = open(f, encoding="utf-8").read()
anchor = "INPUT=$(cat 2>/dev/null || echo '{}')\n"
if anchor not in t:
    sys.exit("ancora non trovata in agent-stamp.sh: non modifico niente")
open(f, "w", encoding="utf-8").write(t.replace(anchor, anchor + riga + "\n", 1))
PY
    rm -f "$LOG"
    echo "Log attivo: $LOG"
    echo "Apri una sessione, fai partire un subagente, poi: $0 --leggi" ;;
  --leggi)
    [ -f "$LOG" ] || { echo "Nessun log: o l'evento non e' scattato, o non hai ancora fatto partire un subagente."; exit 0; }
    echo "--- payload ricevuti ---"; cat "$LOG"
    echo "--- eventi e nomi ---"
    python3 - "$LOG" <<'PY'
import sys, json
for n, riga in enumerate(open(sys.argv[1], encoding="utf-8"), 1):
    riga = riga.strip()
    if not riga: continue
    try: d = json.loads(riga)
    except Exception: print(n, "non e' JSON:", riga[:80]); continue
    nomi = {k: v for k, v in d.items() if "agent" in k.lower() or k in ("name", "subagent")}
    print(n, d.get("hook_event_name", "<senza evento>"), nomi or "<nessun campo di nome>")
PY
    ;;
  --spegni)
    git -C "$H" checkout -- "$F" 2>/dev/null \
      && echo "agent-stamp.sh ripristinato dal repository." \
      || echo "Ripristinalo a mano: git checkout -- plugins/cantiere/hooks/agent-stamp.sh" ;;
  *)
    sed -n '2,20p' "$0"; exit 1 ;;
esac
