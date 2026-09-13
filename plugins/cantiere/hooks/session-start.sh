#!/usr/bin/env bash
# SessionStart. Posa il marcatore che journal-check usa per capire cosa è cambiato
# in questa sessione, e ricorda le regole del cantiere.
set -uo pipefail
mkdir -p .work
: > .work/.session-start
rm -f .work/.journal-nudged
cat <<'MSG'
Cantiere attivo.
Gate umani: nessun push su main, nessun merge di PR, nessun comando su produzione.
Leggi contracts/ prima di scrivere codice.
Scrivi in journal/ MENTRE lavori: ogni decisione, ogni gate, ogni fallimento, ogni misura.
Un giro senza almeno una voce di tipo "fallimento" o "gate" è un journal incompleto,
non un lavoro perfetto.
MSG
exit 0
