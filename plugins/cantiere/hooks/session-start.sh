#!/usr/bin/env bash
# SessionStart. Fotografa lo stato del repository per journal-check e ricorda le
# regole del cantiere. La firma dei commit non passa piu' da qui: vedi agent-env.py.
#
# 01/10 — avviso di main indietro. Una sessione su ownconsent-www e' partita da un
# checkout principale 56 commit indietro, con un CLAUDE.md vecchio. E non e' solo il
# CLAUDE.md: li' core.hooksPath e' un percorso assoluto verso githooks/ del checkout
# principale (misurato in .git/config), quindi tutte le worktree eseguono il git
# hook nella versione che c'e' li' in quel momento. Qui si fa `git fetch origin main`
# e, se main e' indietro, lo si dice nel contesto. Niente pull: l'hook non tocca ne'
# il ramo ne' i file; il fetch aggiorna solo origin/main. Il fetch ha un limite di
# tempo che sta dentro i 10 s concessi all'hook in hooks.json, e se fallisce o scade
# l'avviso lo dice, invece di tacere.
#
# 03/10 — e' un hook INFORMATIVO: se si rompe non blocca niente, ma lo dice. Misurato
# con Claude Code 2.1.288: di un SessionStart che esce con 1, 2 o 127, o che scade,
# nel contesto non arriva niente, nemmeno quello che aveva gia' scritto su stdout.
# Quindi qui si esce sempre con 0 e il guasto si scrive su stdout, come avviso. Prima
# la foto falliva in silenzio (`|| true`): senza python3, con un payload che non si
# legge o con .work non scrivibile la sessione partiva senza foto, e a valle
# journal-check non aveva niente da confrontare e guard-tempo perdeva l'inizio.
set -uo pipefail
INPUT=$(cat 2>/dev/null || echo '{}')
guasto() {
  echo "ATTENZIONE: hook informativo in errore: session-start: $1."
  echo "Conseguenza: $2"
  echo "Dillo ad Andrea prima di cominciare."
  echo
}
SID=$(printf '%s' "$INPUT" | python3 -c 'import sys,json
v = json.load(sys.stdin)["session_id"]
if not isinstance(v, str) or not v.strip(): sys.exit(1)
print(v)' 2>/dev/null) || SID=""
if ! command -v git >/dev/null 2>&1; then
  guasto "git non e' nel PATH" "nessuna foto di avvio e nessun controllo di main; guard-commit, guard-tempo e journal-check negheranno."
elif git rev-parse --git-dir >/dev/null 2>&1; then
  if [ -z "$SID" ]; then
    guasto "non ho letto session_id dal payload (python3 assente dal PATH, o payload non valido)" \
           "nessuna foto di avvio: alla chiusura journal-check neghera' una volta dicendo che non ha potuto controllare."
  elif ! ERR=$(python3 "$(dirname "$0")/journal-stato.py" foto "$SID" 2>&1 >/dev/null); then
    guasto "la foto di avvio non e' stata presa (${ERR:-journal-stato.py in errore})" \
           "alla chiusura journal-check neghera' una volta dicendo che non ha potuto controllare, e guard-tempo conta solo dall'ultimo commit."
  fi
fi
# residui del marcatore di ruolo su file, abbandonato il 21/09
rm -f .work/.current-agent 2>/dev/null
C=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null) && rm -f "$C/cantiere-current-agent"

main_indietro() {
  local gd ramo limite esito n fonte tempo
  # solo nel checkout principale (in una worktree collegata git-dir e common-dir
  # sono diversi), solo su main, solo se c'e' un origin da interrogare
  gd=$(git rev-parse --path-format=absolute --git-dir 2>/dev/null) || return 0
  [ "$gd" = "${C:-}" ] || return 0
  ramo=$(git symbolic-ref --quiet --short HEAD 2>/dev/null) || return 0
  [ "$ramo" = "main" ] || return 0
  git remote get-url origin >/dev/null 2>&1 || return 0

  limite="${CANTIERE_FETCH_LIMITE:-6}"
  # ssh resta quello configurato dall'utente (core.sshCommand, GIT_SSH): forzare
  # GIT_SSH_COMMAND lo scavalcava e dava un «fetch fallito» falso a ogni avvio.
  # Senza un comando per il limite di tempo (macOS non ha timeout) il fetch non
  # si fa, e lo si dice per quello che e'.
  tempo=$(command -v "${CANTIERE_TIMEOUT_CMD:-timeout}" || command -v gtimeout || true)
  fonte=""
  if [ -n "$tempo" ]; then
    GIT_TERMINAL_PROMPT=0 "$tempo" "$limite" git fetch --quiet origin main >/dev/null 2>&1 </dev/null
    esito=$?
  else
    esito=0; fonte="non ho fatto il fetch di origin/main: manca il comando timeout"
  fi
  if [ "$esito" -eq 124 ]; then
    fonte="il fetch di origin/main e' scaduto dopo ${limite} s"
  elif [ "$esito" -ne 0 ]; then
    fonte="il fetch di origin/main e' fallito (rete o credenziali)"
  fi
  n=$(git rev-list --count main..origin/main 2>/dev/null || echo "")

  if [ -n "$fonte" ]; then
    echo "ATTENZIONE: $fonte: non so se main e' allineato a origin/main."
    [ -n "$n" ] && [ "$n" -gt 0 ] && \
      echo "Rispetto all'ultimo origin/main noto, main e' gia' indietro di $n commit."
    echo "Dillo ad Andrea prima di cominciare; il comando per allineare e': git pull --ff-only"
    echo
  elif [ -n "$n" ] && [ "$n" -gt 0 ]; then
    echo "ATTENZIONE: main e' indietro di $n commit rispetto a origin/main."
    echo "Il CLAUDE.md letto e il githooks/ eseguito da tutte le worktree (core.hooksPath"
    echo "punta al checkout principale) possono essere vecchi."
    echo "Non allineare tu: chiedi ad Andrea di dare  git pull --ff-only  e riparti da li'."
    echo
  fi
}
main_indietro

cat <<'MSG'
Cantiere attivo.
Gate umani: nessun push su main, nessun merge di PR, nessun comando su produzione.
Una sessione per worktree: la checkout principale e' di Andrea.
Committa ogni volta che una cosa sta in piedi, e comunque entro 20 minuti: oltre,
il gate a tempo ti ferma. Non per non perdere lavoro — perche' se ti fermi al tetto
dei turni il tuo lavoro lo committa un altro e il trailer porta il suo nome.
Leggi contracts/ prima di scrivere codice.
Scrivi in journal/ MENTRE lavori, con ts preso da `date -Is`: ogni decisione, ogni gate,
ogni fallimento, ogni misura. Un giro senza fallimenti registrati e' un journal
incompleto, non un lavoro perfetto.
MSG
exit 0
