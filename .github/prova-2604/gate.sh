#!/usr/bin/env bash
# PROVA ubuntu-26.04 — blocchi 4 e 5: verifica-gate.sh completo da un progetto di prova.
#   gate.sh <numero blocco> <versione attesa di python3, o vuoto>
# Non fa fallire il passo: scrive l'uscita in $RUNNER_TEMP/esito-blocco-<n>, e il job
# fallisce nel passo finale.
set -u
n="$1"; attesa="${2:-}"
echo "=== BLOCCO $n: verifica-gate.sh ==="
echo "python3: $(python3 --version 2>&1)  [$(readlink -f "$(command -v python3)")]"
rc=0
if [ -n "$attesa" ] && ! python3 --version 2>&1 | grep -q "^Python ${attesa//./\\.}\."; then
  echo "python3 non e' il $attesa atteso: verifica-gate.sh non eseguito"
  rc=97
else
  # stesso progetto di prova del job ci: sotto $RUNNER_TEMP, non sotto /tmp
  P="$RUNNER_TEMP/progetto-prova-blocco-$n"
  if mkdir -p "$P" && cd "$P" && git init -q -b main \
     && git config user.email ci@cantiere.invalid && git config user.name ci \
     && printf 'OwnConsent/cmp\n' > .cantiere-deny && echo segnaposto > CLAUDE.md \
     && git add -A && git commit -qm base; then
    CLAUDE_PROJECT_DIR="$P" bash "$GITHUB_WORKSPACE/plugins/cantiere/hooks/verifica-gate.sh"; rc=$?
  else
    echo "preparazione del progetto di prova fallita"; rc=98
  fi
fi
echo "=== ESITO BLOCCO $n: uscita $rc ==="
echo "$rc" > "$RUNNER_TEMP/esito-blocco-$n"
exit 0
