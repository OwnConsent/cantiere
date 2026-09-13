#!/usr/bin/env bash
# SubagentStart / SubagentStop / Stop.
# Tiene aggiornato .work/.current-agent con chi sta lavorando ora, così il git hook
# prepare-commit-msg può firmare il commit a suo nome.
#
# Tre stati, non due:
#   nome di un ruolo  -> sta lavorando quel subagente
#   "orchestrator"    -> sta lavorando il filo principale della sessione
#   file assente      -> non c'è nessuna sessione: il commit è di una persona
#
# L'ultimo caso è il motivo per cui il file va rimosso alla chiusura: un commit
# umano non deve risultare firmato da un agente.
set -uo pipefail
INPUT=$(cat 2>/dev/null || echo '{}')
mkdir -p .work

EVENT=$(printf '%s' "$INPUT" | python3 -c '
import sys,json
try: d=json.load(sys.stdin)
except Exception: d={}
print(d.get("hook_event_name",""))' 2>/dev/null || echo "")

case "$EVENT" in
  Stop)
    rm -f .work/.current-agent
    exit 0 ;;
  SubagentStop)
    printf 'orchestrator' > .work/.current-agent
    exit 0 ;;
esac

# SubagentStart (o evento non riconosciuto con un nome dentro).
# Il campo che porta il tipo di subagent non è garantito stabile fra le versioni:
# proviamo le chiavi plausibili e, se non troviamo nulla, restiamo su orchestrator
# invece di inventare un ruolo. La fonte autorevole di chi ha fatto cosa è journal/.
NAME=$(printf '%s' "$INPUT" | python3 -c '
import sys,json
try: d=json.load(sys.stdin)
except Exception: d={}
for k in ("agent_type","subagent_type","agent","agentType","name","subagent"):
    v=d.get(k)
    if isinstance(v,str) and v.strip():
        print(v.strip()); break
else:
    print("orchestrator")' 2>/dev/null || echo "orchestrator")

printf '%s' "$NAME" > .work/.current-agent
exit 0
