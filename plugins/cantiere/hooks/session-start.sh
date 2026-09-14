#!/usr/bin/env bash
# SessionStart. Posa il marcatore che journal-check usa per capire cosa è cambiato
# in questa sessione, e ricorda le regole del cantiere.
set -uo pipefail
mkdir -p .work
: > .work/.session-start
rm -f .work/.journal-nudged

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

# da ora e finche' la sessione e' aperta, i commit sono del filo principale,
# non di una persona: vedi hooks/agent-stamp.sh
MARCATORE=$(marcatore_ruolo)
case "$MARCATORE" in .work/*) mkdir -p .work ;; esac
printf 'orchestrator' > "$MARCATORE"
rm -f .work/.current-agent   # residuo delle sessioni precedenti al fix del 14/09

cat <<'MSG'
Cantiere attivo.
Gate umani: nessun push su main, nessun merge di PR, nessun comando su produzione.
Leggi contracts/ prima di scrivere codice.
Scrivi in journal/ MENTRE lavori: ogni decisione, ogni gate, ogni fallimento, ogni misura.
Un giro senza almeno una voce di tipo "fallimento" o "gate" è un journal incompleto,
non un lavoro perfetto.
MSG
exit 0
