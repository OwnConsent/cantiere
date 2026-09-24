#!/usr/bin/env bash
# PreToolUse su Bash. Blocca i comandi che possono CAMBIARE la produzione o
# scavalcare i due gate umani.
#
# Diagnosi in sola lettura su produzione: AMMESSA. @incident-responder deve poter
# guardare log, pod ed eventi per capire cosa è rotto; un gate che glielo impedisce
# non rende il sistema più sicuro, rende l'incidente più lungo.
# Eccezione dentro l'eccezione: i segreti non si leggono comunque.
set -uo pipefail
INPUT=$(cat)
CMD=$(printf '%s' "$INPUT" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("tool_input",{}).get("command",""))' 2>/dev/null || echo "")
[ -z "$CMD" ] && exit 0

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
SEGMENTI=$(printf '%s' "$CMD" | sed 's/&&/\n/g; s/||/\n/g; s/;/\n/g; s/|/\n/g')
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
