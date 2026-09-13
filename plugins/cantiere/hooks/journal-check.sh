#!/usr/bin/env bash
# Stop. Se in questa sessione è cambiato del codice ma non è stata scritta nessuna
# voce di journal, rimanda l'agente a scriverla. Blocca una volta sola per sessione:
# il tracciamento è una regola, non un cappio.
set -uo pipefail
[ -d .git ] || exit 0
MARK=.work/.session-start
[ -f "$MARK" ] || exit 0
[ -f .work/.journal-nudged ] && exit 0

changed=$(find . -type f -newer "$MARK" \
  -not -path './.git/*' -not -path './journal/*' -not -path './corso/*' \
  -not -path './.work/*' -not -path './node_modules/*' -not -path './vendor/*' \
  -not -name '*.log' 2>/dev/null | head -1)
[ -z "$changed" ] && exit 0

entries=$(find journal -type f -name '*.json' -newer "$MARK" 2>/dev/null | head -1)
if [ -z "$entries" ]; then
  : > .work/.journal-nudged
  cat <<'JSON'
{"decision":"block","reason":"In questa sessione è cambiato del codice ma journal/ non ha nuove voci. Prima di chiudere scrivi le voci mancanti seguendo docs/JOURNAL.md: ogni decisione presa, ogni gate incontrato, ogni tentativo fallito, ogni misura fatta. Scrivile come sono andate davvero, non come sarebbero dovute andare: il valore didattico sta soprattutto nei fallimenti. Poi chiudi."}
JSON
  exit 0
fi
exit 0
