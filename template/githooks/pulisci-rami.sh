#!/usr/bin/env bash
# Toglie i rami lasciati indietro dalle worktree degli agenti e dalle PR mergiate.
#
#   ./githooks/pulisci-rami.sh          dice cosa farebbe
#   ./githooks/pulisci-rami.sh --go     esegue
#
# Cancella SOLO rami gia' interamente contenuti in main: usa git branch -d, che
# rifiuta tutto il resto. Le worktree le elenca e basta: quelle le chiudi tu,
# perche' possono contenere lavoro non committato.
set -uo pipefail
GO=0; [ "${1:-}" = "--go" ] && GO=1
git rev-parse --git-dir >/dev/null 2>&1 || { echo "Non sei in un repository."; exit 1; }

echo "Aggiorno la mappa dei rami remoti"
[ "$GO" = 1 ] && git fetch --prune || echo "  [prova] git fetch --prune"

echo
echo "Rami locali gia' dentro main"
RAMI=$(git branch --merged main --format='%(refname:short)' | grep -vE '^(main|master)$' || true)
if [ -z "$RAMI" ]; then
  echo "  nessuno."
else
  echo "$RAMI" | sed 's/^/  /'
  if [ "$GO" = 1 ]; then
    echo "$RAMI" | xargs -r git branch -d
  else
    echo "  [prova] git branch -d su questi"
  fi
fi

echo
echo "Worktree aperte — non le tocco, guardale tu"
git worktree list | sed 's/^/  /'
echo
echo "  Una worktree che non serve piu' si chiude con:  git worktree remove <percorso>"
echo "  Se si rifiuta, dentro c'e' lavoro non committato: guardalo prima di forzare."
