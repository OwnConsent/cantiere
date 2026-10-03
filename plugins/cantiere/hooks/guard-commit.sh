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
#
# FAIL-CLOSED (03/10). Misurato con 26 file sporchi: senza python3 o senza git nel
# PATH, con un payload che non si legge e con una soglia non numerica l'hook usciva
# con 0 e la scrittura passava. Ora ogni guasto nega e dice quale.
set -uo pipefail
rotto() { echo "gate in errore: guard-commit: $1: non so quanto lavoro non committato c'e', quindi nego la scrittura. Riportalo ad Andrea invece di aggirarlo." >&2; exit 2; }
command -v python3 >/dev/null 2>&1 || rotto "python3 non e' nel PATH"
command -v git >/dev/null 2>&1 || rotto "git non e' nel PATH"
corpo() {
  INPUT=$(cat)
  FILE=$(printf '%s' "$INPUT" | python3 -c 'import sys,json
v = json.load(sys.stdin)["tool_input"]["file_path"]
if not isinstance(v, str) or not v.strip(): sys.exit(1)
print(v)' 2>/dev/null) \
    || rotto "il payload non e' JSON valido o manca tool_input.file_path"
  D=$(dirname "$FILE")
  while [ ! -d "$D" ] && [ "$D" != "/" ]; do D=$(dirname "$D"); done
  git -C "$D" rev-parse --git-dir >/dev/null 2>&1 || exit 0
  SOGLIA="${CANTIERE_SOGLIA_COMMIT:-20}"
  # una soglia che non e' un numero faceva fallire il confronto, e il gate taceva
  case "$SOGLIA" in ''|*[!0-9]*) SOGLIA=20 ;; esac
  STATO=$(git -C "$D" status --porcelain --untracked-files=normal 2>/dev/null) \
    || rotto "git status e' uscito con $? in $D"
  N=$(printf '%s' "$STATO" | grep -c '')
  if [ "${N:-0}" -ge "$SOGLIA" ]; then
    echo "COMMIT PRIMA DI CONTINUARE: in questo albero ci sono $N file modificati o nuovi non committati (soglia $SOGLIA). Committa e pusha il lavoro fatto finora sul ramo del lotto, poi riprendi. Se il tetto dei turni arriva adesso, quello che non e' committato si perde: e' successo a nove agenti su nove il 19-20/09." >&2
    exit 2
  fi
  exit 0
}
# SVEGLIA (03/10): il gate gira sotto un limite ricavato dal timeout di hooks.json.
# Se lo supera nega, invece di farsi terminare da Claude Code e lasciar passare.
. "$(dirname "$0")/sveglia.sh" 2>/dev/null || rotto "non trovo sveglia.sh accanto allo script"
con_sveglia guard-commit.sh corpo
