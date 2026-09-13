#!/usr/bin/env bash
# Chi ha fatto cosa, da git. Per la slide, e per accorgersi quando un ruolo
# sta lavorando molto più o molto meno del previsto.
#
#   ./githooks/chi-ha-fatto-cosa.sh                tutta la storia
#   ./githooks/chi-ha-fatto-cosa.sh v0.1.0..HEAD   un intervallo
set -uo pipefail
RANGE="${1:-}"

echo "Commit per ruolo${RANGE:+ ($RANGE)}"
echo "----------------------------------------"
git log $RANGE --format='%(trailers:key=Cantiere-Agent,valueonly)' \
  | sed '/^$/d' \
  | sort | uniq -c | sort -rn \
  | awk '{printf "  %4d  %s\n", $1, $2}'

TOT=$(git log $RANGE --oneline | wc -l)
FIRME=$(git log $RANGE --format='%(trailers:key=Cantiere-Agent,valueonly)' | sed '/^$/d')
AG=$(printf '%s\n' "$FIRME" | sed '/^$/d;/^sconosciuto$/d' | wc -l)
IGN=$(printf '%s\n' "$FIRME" | grep -cx 'sconosciuto' || true)
echo "----------------------------------------"
printf '  %4d  commit totali\n' "$TOT"
printf '  %4d  attribuiti a un ruolo\n' "$AG"
printf '  %4d  firmati "sconosciuto" (il ruolo non era rilevabile: controlla journal/)\n' "$IGN"
printf '  %4d  senza firma (tuoi, o fatti fuori sessione)\n' "$((TOT-AG-IGN))"

echo
echo "Merge su main (i tuoi gate)"
git log $RANGE --merges --format='  %h  %ad  %s' --date=short | head -20
