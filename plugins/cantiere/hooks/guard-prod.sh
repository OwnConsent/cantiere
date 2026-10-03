#!/usr/bin/env bash
# PreToolUse su Bash. Blocca i comandi che possono CAMBIARE la produzione o
# scavalcare i due gate umani.
#
# Diagnosi in sola lettura su produzione: AMMESSA. @incident-responder deve poter
# guardare log, pod ed eventi per capire cosa è rotto; un gate che glielo impedisce
# non rende il sistema più sicuro, rende l'incidente più lungo.
# Eccezione dentro l'eccezione: i segreti non si leggono comunque.
#
# FAIL-CLOSED (03/10). Misurato: senza python3 nel PATH, o con un payload che non si
# legge, CMD restava vuoto e l'hook usciva con 0: `gh pr merge` passava. Un gate che
# non riesce a leggere il comando non lo ha esaminato, quindi nega.
set -uo pipefail
rotto() { echo "gate in errore: guard-prod: $1: comando non esaminato, quindi negato. Riportalo ad Andrea invece di aggirarlo." >&2; exit 2; }
# Comandi esterni (review della PR 19). Se uno manca dal PATH il valore che doveva
# produrre resta vuoto, e in questi script un valore vuoto vale «passa»: senza sed
# l'elenco dei segmenti era vuoto e `git push origin main` passava.
# Si controllano tutti prima di cominciare, come l'interprete.
for c in python3 cat sed dirname sleep; do
  command -v "$c" >/dev/null 2>&1 || rotto "comando esterno mancante: $c"
done
corpo() {
  INPUT=$(cat)
  CMD=$(printf '%s' "$INPUT" | python3 -c 'import sys,json
v = json.load(sys.stdin)["tool_input"]["command"]
if not isinstance(v, str) or not v.strip(): sys.exit(1)
print(v)' 2>/dev/null) \
    || rotto "il payload non e' JSON valido o manca tool_input.command"

  deny() { echo "GATE: $1 — questa azione richiede una persona. Prepara il cambiamento e fermati." >&2; exit 2; }

  shopt -s nocasematch
  case "$CMD" in
    *"gh pr merge"*)       deny "merge di PR" ;;
    *"gh release create"*) deny "creazione di release" ;;
    # --force-with-lease rifiuta di sovrascrivere quello che non hai visto: e' il modo
    # corretto di riscrivere un ramo di lotto dopo un rebase, e negarlo costringeva a
    # cancellare e ricreare il ramo, perdendo la PR. Su main resta negato dal controllo
    # per segmento qui sotto, che guarda il ramo di destinazione.
    *"--force-with-lease"*) : ;;
    *"git push --force"*|*"git push -f "*) deny "push forzato senza --force-with-lease" ;;
  esac
  shopt -u nocasematch

  # Push su ramo protetto: si guarda SEGMENTO PER SEGMENTO, non tutto il comando.
  # Altrimenti `git checkout -b x main && git push -u origin x` viene negato per la
  # parola "main" che sta nel checkout, non nel push. Falso positivo osservato il 13/09:
  # induce a spezzare i comandi finche' il guardiano smette di lamentarsi, che e'
  # un'abitudine peggiore del problema che risolve.
  SEGMENTI=$(printf '%s' "$CMD" | sed 's/&&/\n/g; s/||/\n/g; s/;/\n/g; s/|/\n/g') \
    || rotto "sed e' uscito con $? mentre spezzavo il comando"
  while IFS= read -r seg; do
    [[ "$seg" =~ (^|[[:space:]])git[[:space:]]+push($|[[:space:]]) ]] || continue
    # il ramo di destinazione e' l'ultimo token, oppure la parte dopo i due punti
    if [[ "$seg" =~ (^|[[:space:]])(main|master)([[:space:]]|$) ]] \
       || [[ "$seg" =~ :(main|master)([[:space:]]|$) ]]; then
      deny "push su ramo protetto"
    fi
  done <<< "$SEGMENTI"

  PROD='(^|[^a-z])(prod|production|live)([^a-z]|$)'

  # --- kubernetes ---
  if [[ "$CMD" =~ (^|[[:space:]|])(kubectl|helm|kubens|kubectx|flux|argocd)([[:space:]]|$) ]] && [[ "$CMD" =~ $PROD ]]; then
    # i segreti non si leggono, nemmeno in lettura
    if [[ "$CMD" =~ (secret|secrets) ]]; then
      deny "lettura di segreti su produzione"
    fi
    LETTURA='(^|[[:space:]])(get|describe|logs|top|events|explain|api-resources|version|cluster-info|history|status|list)([[:space:]]|$)'
    MUTANTE='(^|[[:space:]])(apply|create|delete|patch|replace|edit|scale|rollout|annotate|label|set|drain|cordon|uncordon|taint|exec|cp|port-forward|proxy|attach|debug|run|install|uninstall|upgrade|rollback|sync)([[:space:]]|$)'
    if [[ "$CMD" =~ $MUTANTE ]]; then
      deny "comando che modifica la produzione"
    elif [[ "$CMD" =~ $LETTURA ]]; then
      : # diagnosi ammessa
    else
      deny "comando su produzione di cui non riconosco il verbo"
    fi
  fi

  # --- terraform ---
  if [[ "$CMD" =~ terraform[[:space:]]+(apply|destroy|import|taint|state[[:space:]]+(rm|mv|push)) ]] && [[ ! "$CMD" =~ (staging|dev|test) ]]; then
    deny "terraform che modifica lo stato fuori da staging"
  fi

  # --- database ---
  if [[ "$CMD" =~ (DROP[[:space:]]+(TABLE|DATABASE|SCHEMA|COLLECTION)|TRUNCATE[[:space:]]+TABLE|dropDatabase|deleteMany[[:space:]]*\([[:space:]]*\{[[:space:]]*\}) ]]; then
    deny "operazione distruttiva sui dati"
  fi

  # --- credenziali cloud di produzione ---
  if [[ "$CMD" =~ (aws[[:space:]]+.*--profile[[:space:]]+prod|gcloud[[:space:]]+.*--project[[:space:]]+[^[:space:]]*prod) ]]; then
    deny "credenziali cloud di produzione"
  fi
  exit 0
}
# SVEGLIA (03/10): il gate gira sotto un limite ricavato dal timeout di hooks.json.
# Se lo supera nega, invece di farsi terminare da Claude Code e lasciar passare.
. "$(dirname "$0")/sveglia.sh" 2>/dev/null || rotto "non trovo sveglia.sh accanto allo script"
con_sveglia guard-prod.sh corpo
