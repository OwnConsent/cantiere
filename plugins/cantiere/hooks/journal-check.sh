#!/usr/bin/env bash
# Stop. Se in questa sessione e' cambiato del lavoro ma journal/ non ha voci nuove,
# rimanda l'agente a scriverle. Una volta sola per sessione: il tracciamento e' una
# regola, non un cappio. Cosa conta come «cambiato» lo decide journal-stato.py,
# confrontando il contenuto con la foto presa all'avvio — non le date dei file.
#
# FAIL-CLOSED (03/10), ma una volta sola. Misurato: senza python3, senza git, con un
# payload che non si legge e con la foto di avvio assente, illeggibile o corrotta
# l'hook usciva con 0 e la sessione chiudeva senza che nessuno avesse guardato il
# journal. Ora nega e dice perche'. Pero' un gate di Stop rotto nega a OGNI tentativo
# di chiudere, e non ha un file su cui segnarsi «gia' detto» (magari e' proprio
# .work a non essere scrivibile). Misurato con Claude Code 2.1.288 e un hook di Stop
# che esce sempre con 2: 14 dinieghi di fila prima che Claude Code lasci chiudere.
# Per questo si guarda stop_hook_active, che Claude Code mette a true quando la
# sessione sta continuando per un diniego di Stop (misurato: false al primo, true ai
# tredici successivi): al secondo giro si lascia chiudere, dicendolo a chi guarda.
set -uo pipefail
INPUT=$(cat 2>/dev/null)
# UNA VOLTA PER SESSIONE (seconda review della PR 19). Fino a qui il «nega una volta»
# guardava solo stop_hook_active, e valeva una volta per TURNO: misurato con Claude
# Code 2.1.288 e una sessione a due turni (claude -p, poi --resume), al primo Stop del
# secondo turno stop_hook_active e' di nuovo false. In una sessione interattiva senza
# foto di avvio ogni turno veniva negato, anche quelli di sola lettura. Ora il guasto
# si segna nello stesso file .sollecitata del percorso sano, con dentro il motivo:
# detto una volta, per il resto della sessione si lascia chiudere. Il nome viene da session_id se il payload
# si e' letto, altrimenti da CLAUDE_CODE_SESSION_ID, che Claude Code mette
# nell'ambiente degli hook e che coincide con il session_id del payload (misurato su
# SessionStart, PreToolUse e Stop). Se il file non si puo' scrivere si ricade su
# stop_hook_active, cioe' una volta per turno, e il diniego lo dice.
BASE="${CLAUDE_PROJECT_DIR:-$PWD}"
rotto() { # i messaggi sono costanti senza virgolette: entrano in un JSON cosi' come sono
  local id segno=""
  id="${SID:-${CLAUDE_CODE_SESSION_ID:-}}"; id="${id//[^A-Za-z0-9_-]/}"
  [ -n "$id" ] && [ -d "$BASE" ] && segno="$BASE/.work/sessioni/$id.sollecitata"
  case "$INPUT" in
    *'"stop_hook_active":true'*|*'"stop_hook_active": true'*)
      [ -n "$segno" ] && { mkdir -p "${segno%/*}" && printf '%s' "$1" > "$segno"; } 2>/dev/null
      printf '{"systemMessage":"gate in errore: journal-check: %s. Il journal di questa sessione NON e stato controllato. Gia detto una volta: lascio chiudere."}\n' "$1"
      exit 0 ;;
  esac
  [ -n "$segno" ] && [ -f "$segno" ] && exit 0      # gia' detto in questa sessione
  if [ -n "$segno" ] && { mkdir -p "${segno%/*}" && printf '%s' "$1" > "$segno"; } 2>/dev/null; then
    echo "gate in errore: journal-check: $1: il journal di questa sessione NON e' stato controllato. Verifica tu che le voci di journal/ ci siano, scrivi nella risposta finale che questo gate e' in errore e perche', poi chiudi: al secondo tentativo ti lascio andare, e in questa sessione non te lo ripeto." >&2
  else
    echo "gate in errore: journal-check: $1: il journal di questa sessione NON e' stato controllato. Verifica tu che le voci di journal/ ci siano, scrivi nella risposta finale che questo gate e' in errore e perche', poi chiudi: al secondo tentativo ti lascio andare. Non ho potuto segnarmi di avertelo detto (.work/sessioni non scrivibile, o sessione senza identificativo): lo ripetero' a ogni turno." >&2
  fi
  exit 2
}
# Comandi esterni (review della PR 19): se uno manca dal PATH il valore che doveva
# produrre resta vuoto, e un valore vuoto qui vale «lascia chiudere». Si controllano
# tutti prima di cominciare, come l'interprete.
for c in git python3 cat dirname sleep mkdir; do
  command -v "$c" >/dev/null 2>&1 || rotto "comando esterno mancante: $c"
done
# ANCORA (review della PR 19). La foto di avvio sta in .work/sessioni/ della cartella
# in cui la sessione e' partita. Misurato con Claude Code 2.1.288: un hook gira nella
# cartella corrente dell'agente, quindi dopo un `cd sub/` lo Stop gira in sub/ e la
# foto, cercata con un percorso relativo, non si trovava. CLAUDE_PROJECT_DIR resta la
# cartella di avvio in tutti i casi misurati (checkout principale, worktree, cd in una
# sottocartella, cd in un'altra worktree); `git rev-parse --show-toplevel` no: dopo un
# cd in un'altra worktree diventa quella. Senza la variabile (hook lanciato a mano)
# vale la cartella corrente, come prima.
if [ -n "${CLAUDE_PROJECT_DIR:-}" ]; then
  cd "$CLAUDE_PROJECT_DIR" 2>/dev/null || rotto "la cartella di progetto non esiste (CLAUDE_PROJECT_DIR)"
fi
corpo() {
  git rev-parse --git-dir >/dev/null 2>&1 || exit 0
  SID=$(printf '%s' "$INPUT" | python3 -c 'import sys,json
v = json.load(sys.stdin)["session_id"]
if not isinstance(v, str) or not v.strip(): sys.exit(1)
print(v)' 2>/dev/null) || rotto "il payload non e JSON valido o manca session_id"
  NUDGE=".work/sessioni/${SID//[^A-Za-z0-9_-]/}.sollecitata"
  if [ -f "$NUDGE" ]; then
    # Vuoto: la sollecitazione del percorso sano. Non vuoto: l'ha scritto rotto(), con
    # il motivo; al secondo giro dello stesso turno lo si ripete a chi guarda.
    if [ -s "$NUDGE" ]; then
      case "$INPUT" in *'"stop_hook_active":true'*|*'"stop_hook_active": true'*) rotto "$(cat "$NUDGE")" ;; esac
    fi
    exit 0
  fi

  STATO=$(python3 "$(dirname "$0")/journal-stato.py" esame "$SID" 2>/dev/null); RC=$?
  # 3 = la foto non c'e' (journal-stato.py); il resto e' un errore mentre la si confronta
  [ "$RC" -eq 3 ] && rotto "manca la foto di avvio di questa sessione: di solito significa che SessionStart non e girato o si e rotto"
  [ "$RC" -eq 0 ] || rotto "non ho potuto confrontare lo stato con la foto di avvio (illeggibile o corrotta, oppure git in errore)"
  read -r LAVORO VOCI <<< "$STATO"
  [[ "${LAVORO:-}" =~ ^[0-9]+$ && "${VOCI:-}" =~ ^[0-9]+$ ]] || rotto "journal-stato.py non ha restituito due numeri"
  [ "$LAVORO" -gt 0 ] || exit 0
  [ "${VOCI:-0}" -gt 0 ] && exit 0

  { mkdir -p .work/sessioni && : > "$NUDGE"; } 2>/dev/null \
    || rotto "non posso scrivere in .work/sessioni e non posso segnarmi di averti gia sollecitato"
  cat <<'JSON'
{"decision":"block","reason":"In questa sessione e' cambiato del lavoro ma journal/ non ha voci nuove. Prima di chiudere scrivi le voci mancanti seguendo docs/JOURNAL.md: ogni decisione, ogni gate, ogni tentativo fallito, ogni misura. Il campo ts si prende da `date -Is` eseguito in quel momento, mai a memoria. Scrivile come sono andate davvero. Se ritieni che il lavoro contato non sia tuo, non scrivere una voce per farmi tacere: dillo, con la misura."}
JSON
  exit 0
}
# SVEGLIA (03/10): il gate gira sotto un limite ricavato dal timeout di hooks.json.
# Se lo supera nega, invece di farsi terminare da Claude Code e lasciar passare.
. "$(dirname "$0")/sveglia.sh" 2>/dev/null || rotto "non trovo sveglia.sh accanto allo script"
con_sveglia journal-check.sh corpo
