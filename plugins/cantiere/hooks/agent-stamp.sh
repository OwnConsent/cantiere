#!/usr/bin/env bash
# SubagentStart / SubagentStop / Stop.
# Tiene aggiornato il marcatore di ruolo con chi sta lavorando ora, così il git hook
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

# --- risoluzione del marcatore di ruolo -----------------------------------
# Il marcatore NON puo' stare in .work/: una worktree collegata ha la sua
# radice e li' .work/ non esiste, quindi i commit fatti da un subagente con
# isolation: worktree uscivano senza firma (osservato il 13/09 sui commit
# cb481f5 e b3dcc26).
# git rev-parse --git-common-dir restituisce la stessa cartella .git per la
# checkout principale e per ogni worktree collegata: e' l'unico posto che
# tutte vedono. Sta dentro .git/, quindi non e' tracciato e non puo' finire
# in un commit per sbaglio.
marcatore_ruolo() {
  local comune=""
  comune=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || comune=""
  if [ -z "$comune" ]; then   # git < 2.31: nessun --path-format
    comune=$(git rev-parse --git-common-dir 2>/dev/null) || comune=""
    [ -n "$comune" ] && comune=$(cd "$comune" 2>/dev/null && pwd) || comune=""
  fi
  if [ -n "$comune" ] && [ -d "$comune" ]; then
    printf '%s/cantiere-current-agent\n' "$comune"
  else
    printf '.work/.current-agent\n'   # fuori da un repo: comportamento di prima
  fi
}

MARCATORE=$(marcatore_ruolo)
case "$MARCATORE" in .work/*) mkdir -p .work ;; esac

EVENT=$(printf '%s' "$INPUT" | python3 -c '
import sys,json
try: d=json.load(sys.stdin)
except Exception: d={}
print(d.get("hook_event_name",""))' 2>/dev/null || echo "")

case "$EVENT" in
  Stop)
    # si rimuove anche il vecchio percorso: una sessione aperta prima di questo
    # fix puo' averlo lasciato li', e un file rimasto firmerebbe come agente il
    # prossimo commit di una persona.
    rm -f "$MARCATORE" .work/.current-agent
    exit 0 ;;
  SubagentStop)
    printf 'orchestrator' > "$MARCATORE"
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

printf '%s' "$NAME" > "$MARCATORE"
exit 0
