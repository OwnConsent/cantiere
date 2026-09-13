#!/usr/bin/env bash
# PreToolUse su Bash. Blocca ogni comando che può toccare la produzione
# o saltare i due gate umani. Exit 2 = negato, stderr torna all'agente.
set -uo pipefail
INPUT=$(cat)
CMD=$(printf '%s' "$INPUT" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("tool_input",{}).get("command",""))' 2>/dev/null || echo "")
[ -z "$CMD" ] && exit 0

deny() { echo "GATE: $1 — questa azione richiede una persona. Prepara il cambiamento e fermati." >&2; exit 2; }

shopt -s nocasematch
case "$CMD" in
  *"git push"*" main"*|*"git push"*" master"*|*"git push --force"*) deny "push su ramo protetto" ;;
  *"gh pr merge"*)                                                  deny "merge di PR" ;;
  *"gh release create"*|*"gh workflow run"*deploy*prod*)            deny "release o deploy in produzione" ;;
esac

# contesti/namespace/workspace di produzione, qualunque strumento
if [[ "$CMD" =~ (kubectl|helm|kubens|kubectx|flux|argocd) ]] && [[ "$CMD" =~ (prod|production|live) ]]; then
  deny "comando Kubernetes su contesto di produzione"
fi
if [[ "$CMD" =~ terraform[[:space:]]+(apply|destroy) ]] && [[ ! "$CMD" =~ (staging|dev|test) ]]; then
  deny "terraform apply/destroy fuori da staging"
fi
if [[ "$CMD" =~ (DROP[[:space:]]+(TABLE|DATABASE|SCHEMA)|TRUNCATE[[:space:]]+TABLE) ]]; then
  deny "DDL distruttivo"
fi
if [[ "$CMD" =~ (aws[[:space:]]+.*--profile[[:space:]]+prod|gcloud[[:space:]]+.*prod) ]]; then
  deny "credenziali cloud di produzione"
fi
exit 0
