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
INPUT=$(cat)
rotto() { # i messaggi sono costanti senza virgolette: entrano in un JSON cosi' come sono
  case "$INPUT" in
    *'"stop_hook_active":true'*|*'"stop_hook_active": true'*)
      printf '{"systemMessage":"gate in errore: journal-check: %s. Il journal di questa sessione NON e stato controllato. Gia detto una volta: lascio chiudere."}\n' "$1"
      exit 0 ;;
  esac
  echo "gate in errore: journal-check: $1: il journal di questa sessione NON e' stato controllato. Verifica tu che le voci di journal/ ci siano, scrivi nella risposta finale che questo gate e' in errore e perche', poi chiudi: al secondo tentativo ti lascio andare." >&2
  exit 2
}
corpo() {
  command -v git >/dev/null 2>&1 || rotto "git non e nel PATH"
  git rev-parse --git-dir >/dev/null 2>&1 || exit 0
  command -v python3 >/dev/null 2>&1 || rotto "python3 non e nel PATH"
  SID=$(printf '%s' "$INPUT" | python3 -c 'import sys,json
v = json.load(sys.stdin)["session_id"]
if not isinstance(v, str) or not v.strip(): sys.exit(1)
print(v)' 2>/dev/null) || rotto "il payload non e JSON valido o manca session_id"
  NUDGE=".work/sessioni/${SID//[^A-Za-z0-9_-]/}.sollecitata"
  [ -f "$NUDGE" ] && exit 0

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
