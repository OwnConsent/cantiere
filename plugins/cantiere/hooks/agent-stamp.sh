#!/usr/bin/env bash
# SubagentStart / SubagentStop.
# Tiene aggiornato .work/.current-agent con il ruolo che sta lavorando ora,
# così il git hook prepare-commit-msg può firmare il commit a suo nome.
#
# Il nome del campo che porta il tipo di subagent nel payload non è garantito
# stabile fra le versioni: proviamo le chiavi plausibili e, se non troviamo
# nulla, scriviamo "sconosciuto" invece di indovinare. La fonte autorevole di
# chi ha fatto cosa resta journal/, non questo file.
set -uo pipefail
INPUT=$(cat 2>/dev/null || echo '{}')
mkdir -p .work

EVENT=$(printf '%s' "$INPUT" | python3 -c '
import sys,json
try: d=json.load(sys.stdin)
except Exception: d={}
print(d.get("hook_event_name",""))' 2>/dev/null || echo "")

if [ "$EVENT" = "SubagentStop" ]; then
  rm -f .work/.current-agent
  exit 0
fi

NAME=$(printf '%s' "$INPUT" | python3 -c '
import sys,json
try: d=json.load(sys.stdin)
except Exception: d={}
for k in ("agent_type","subagent_type","agent","agentType","name","subagent"):
    v=d.get(k)
    if isinstance(v,str) and v.strip():
        print(v.strip()); break
else:
    print("sconosciuto")' 2>/dev/null || echo "sconosciuto")

printf '%s' "$NAME" > .work/.current-agent
exit 0
