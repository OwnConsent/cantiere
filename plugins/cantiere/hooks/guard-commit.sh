#!/usr/bin/env bash
# PreToolUse su Edit|Write. Oltre una soglia di file modificati e non committati,
# rifiuta la scrittura successiva finche' non c'e' un commit.
#
# Perche' un meccanismo e non una regola: la regola «committa a incrementi» e' nella
# scheda di tutti gli agenti dal 19/09, e il 19-20/09 nove agenti su nove sono
# arrivati al tetto dei turni; chi non aveva committato ha perso tutto, circa 280.000
# token nel solo L05. Un'istruzione che chiede a un agente di fermarsi mentre e'
# assorbito dal lavoro e' esattamente quella che non viene seguita.
#
# Soglia: CANTIERE_SOGLIA_COMMIT, predefinita 20 file.
set -uo pipefail
INPUT=$(cat 2>/dev/null || echo '{}')
FILE=$(printf '%s' "$INPUT" | python3 -c 'import sys,json
try: print(json.load(sys.stdin).get("tool_input",{}).get("file_path",""))
except Exception: print("")' 2>/dev/null)
[ -n "$FILE" ] || exit 0
D=$(dirname "$FILE")
while [ ! -d "$D" ] && [ "$D" != "/" ]; do D=$(dirname "$D"); done
git -C "$D" rev-parse --git-dir >/dev/null 2>&1 || exit 0
SOGLIA="${CANTIERE_SOGLIA_COMMIT:-20}"
N=$(git -C "$D" status --porcelain --untracked-files=normal 2>/dev/null | wc -l | tr -d ' ')
if [ "${N:-0}" -ge "$SOGLIA" ]; then
  echo "COMMIT PRIMA DI CONTINUARE: in questo albero ci sono $N file modificati o nuovi non committati (soglia $SOGLIA). Committa e pusha il lavoro fatto finora sul ramo del lotto, poi riprendi. Se il tetto dei turni arriva adesso, quello che non e' committato si perde: e' successo a nove agenti su nove il 19-20/09." >&2
  exit 2
fi
exit 0
