#!/usr/bin/env bash
# La sveglia dei gate in shell. Si include, non si esegue:
#
#   . "$(dirname "$0")/sveglia.sh" 2>/dev/null || rotto "non trovo sveglia.sh"
#   con_sveglia <nome-in-hooks.json> <funzione>
#
# Esegue la funzione in secondo piano e la aspetta per i secondi che sveglia.py ricava
# dal timeout di hooks.json (vedi li' il perche'). Allo scadere la termina con tutti i
# suoi figli e chiama rotto "tempo esaurito ...", che chi include deve avere definito.
#
# Niente `timeout` di coreutils: su macOS non c'e' (gia' visto in session-start.sh).
# E niente trap attorno al lavoro in primo piano: bash serve una trap solo quando il
# comando in corso finisce, quindi con un `git status` piantato non scatterebbe mai.
# `wait` invece si interrompe all'arrivo del segnale: per questo il lavoro va in
# secondo piano. `set -m` da' a lavoro e sentinella un gruppo di processi ciascuno,
# cosi' si terminano insieme ai figli: un figlio rimasto vivo terrebbe aperto lo
# stderr dell'hook e Claude Code lo aspetterebbe fino al suo timeout.
con_sveglia() {
  local hook="$1" corpo="$2" limite lavoro sentinella scaduto=0 rc
  limite=$(python3 "$(dirname "${BASH_SOURCE[0]}")/sveglia.py" "$hook" 2>/dev/null) \
    || rotto "non ricavo il mio timeout da hooks.json (illeggibile, o $hook non registrato)"
  trap 'scaduto=1' ALRM
  set -m
  "$corpo" <&0 & lavoro=$!
  ( trap - ALRM; sleep "$limite"; kill -ALRM $$ ) </dev/null >/dev/null 2>&1 & sentinella=$!
  set +m
  wait "$lavoro"; rc=$?
  if [ "$scaduto" = 1 ]; then
    kill -KILL -- "-$lavoro" 2>/dev/null
    rotto "tempo esaurito dopo ${limite} s"
  fi
  kill -KILL -- "-$sentinella" 2>/dev/null
  exit "$rc"
}
