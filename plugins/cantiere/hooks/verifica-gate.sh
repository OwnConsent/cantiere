#!/usr/bin/env bash
# Verifica che i gate del cantiere blocchino davvero — SENZA eseguire nulla.
#
# Passa a ogni hook il payload che riceverebbe e guarda il verdetto. I comandi
# pericolosi non partono mai: l'hook li vede come testo e risponde, punto.
# Il caso dei segreti usa un file finto creato qui, mai un file vero.
#
#   ./verifica-gate.sh          dalla radice del progetto
set -uo pipefail
H="$(cd "$(dirname "$0")" && pwd)"
export CLAUDE_PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$PWD}"
OK=0; KO=0
V="\033[32m"; X="\033[31m"; N="\033[0m"

# Il livello 3 di guard-paths considera sicuri i prefissi di sistema (/tmp, /usr,
# /opt, ...). Se il progetto vive sotto uno di quelli, "uscire dal progetto" non
# risulta mai un'uscita e mezza suite passa per il motivo sbagliato: la prima
# volta che e' successo, il 14/09, sei verifiche di perimetro davano verde da
# sole. Non e' solo un artefatto della prova: un progetto clonato sotto /tmp non
# ha perimetro davvero.
case "$CLAUDE_PROJECT_DIR" in
  /usr/*|/bin/*|/sbin/*|/lib/*|/lib64/*|/etc/*|/opt/*|/tmp/*|/var/tmp/*|/dev/*|/proc/*|/snap/*|/run/*|/nix/*)
    printf "\n${X}ATTENZIONE${N}  il progetto sta sotto un prefisso di sistema (%s).\n" "$CLAUDE_PROJECT_DIR"
    printf "            Li' il perimetro di guard-paths non vale e le verifiche di\n"
    printf "            perimetro passano per il motivo sbagliato. Sposta il progetto\n"
    printf "            sotto \$HOME prima di fidarti di questo risultato.\n" ;;
esac

bash_hook() { # comando, hook, atteso(deny|pass)
  local out rc
  out=$(printf '%s' "{\"tool_input\":{\"command\":$(printf '%s' "$1" | python3 -c 'import sys,json;print(json.dumps(sys.stdin.read()))')}}" \
        | "$H/$2" 2>&1 >/dev/null); rc=$?
  verdetto "$rc" "$3" "$1" "$out"
}
file_hook() { # percorso, hook, atteso
  local out rc
  out=$(printf '{"tool_input":{"file_path":"%s"}}' "$1" | "$H/$2" 2>&1 >/dev/null); rc=$?
  verdetto "$rc" "$3" "file: $1" "$out"
}
verdetto() { # rc, atteso, etichetta, messaggio
  local esito; [ "$1" -eq 2 ] && esito=deny || esito=pass
  if [ "$esito" = "$2" ]; then
    printf "  ${V}ok${N}    %-52s %s\n" "$3" "$esito"; OK=$((OK+1))
  else
    printf "  ${X}KO${N}    %-52s atteso %s, ottenuto %s\n" "$3" "$2" "$esito"; KO=$((KO+1))
    [ -n "$4" ] && printf "        %s\n" "$4"
  fi
}

echo; echo "Gate umani — devono essere negati"
bash_hook 'gh pr merge 1 --squash'                    guard-prod.sh deny
bash_hook 'git push origin main'                      guard-prod.sh deny
bash_hook 'git push --force origin feature'           guard-prod.sh deny
bash_hook 'gh release create v1.0.0'                  guard-prod.sh deny

echo; echo "Push: il ramo conta, non la parola (falso positivo del 13/09)"
bash_hook 'git checkout -b fix/x main && git push -u origin fix/x' guard-prod.sh pass
bash_hook 'git switch -c docs/y origin/main && git push -u origin docs/y' guard-prod.sh pass
bash_hook 'git push -u origin issue-4-feature'   guard-prod.sh pass
bash_hook 'git push origin HEAD:main'            guard-prod.sh deny
bash_hook 'git checkout -b x && git push origin main' guard-prod.sh deny

echo; echo "Produzione — modifiche negate, diagnosi ammessa"
bash_hook 'kubectl apply -f x.yaml --context prod-eu' guard-prod.sh deny
bash_hook 'kubectl delete pod api-7 --context prod'   guard-prod.sh deny
bash_hook 'kubectl exec -it api-7 --context prod -- sh' guard-prod.sh deny
bash_hook 'helm upgrade api ./chart --kube-context prod' guard-prod.sh deny
bash_hook 'kubectl get pods --context prod'           guard-prod.sh pass
bash_hook 'kubectl logs api-7 --context prod --tail=100' guard-prod.sh pass
bash_hook 'kubectl describe pod api-7 --context prod' guard-prod.sh pass
bash_hook 'kubectl get secret db --context prod -o yaml' guard-prod.sh deny

echo; echo "Infrastruttura e dati"
bash_hook 'terraform apply -auto-approve'             guard-prod.sh deny
bash_hook 'terraform plan'                            guard-prod.sh pass
bash_hook 'db.utenti.deleteMany({})'                  guard-prod.sh deny
bash_hook 'DROP TABLE consensi;'                      guard-prod.sh deny

echo; echo "Perimetro — fuori dal progetto"
bash_hook 'cat ~/.ssh/id_ed25519'                     guard-paths.sh deny
bash_hook 'cat ../cmp/.env'                           guard-paths.sh deny
if [ -f "$CLAUDE_PROJECT_DIR/.cantiere-deny" ]; then
  bash_hook 'gh api repos/OwnConsent/cmp/contents/x'  guard-paths.sh deny
else
  printf "  ${X}--${N}    %-52s .cantiere-deny assente: niente da verificare\n" "elenco esplicito del progetto"
fi
bash_hook 'find .. -name .env'                        guard-paths.sh deny

echo; echo "Codice Python — // e stringhe assolute non sono percorsi (falso positivo del 13/09)"
bash_hook 'python3 -c "print(10 // 3)"'                  guard-paths.sh pass
bash_hook 'python3 -c "p=\"/api/v1/utenti\"; print(p)"' guard-paths.sh pass
bash_hook 'python3 -c "print(open(\"../cmp/.env\").read())"' guard-paths.sh deny

echo; echo "Separatori di shell: il ; non fa parte del percorso (falso positivo del 13/09)"
bash_hook "cd $CLAUDE_PROJECT_DIR; cat CLAUDE.md"      guard-paths.sh pass
bash_hook "cd $CLAUDE_PROJECT_DIR/docs; ls"            guard-paths.sh pass
bash_hook 'cd ../cmp; cat .env'                        guard-paths.sh deny
bash_hook 'cat ~/.ssh/id_rsa; echo fine'               guard-paths.sh deny

echo; echo "Prosa non e' un percorso: barre isolate e corpi di testo (13/09)"
bash_hook 'gh pr comment 17 --body "profilo: 150 ms / 1,6 Mbps / 750 kbps"' guard-paths.sh pass
bash_hook 'git commit -m "docs: soglie 150 ms / 1,6 Mbps"'                  guard-paths.sh pass
bash_hook 'gh pr create --title "perf / soglie" --body "sezione 3 / 4"'     guard-paths.sh pass
bash_hook 'gh pr comment 17 --body "$(cat ../cmp/.env)"'                    guard-paths.sh deny


echo; echo "Testo che comincia per / non e' un percorso (falso positivo del 15/09)"
bash_hook "sed -n '/FAIL/p' log.txt"                    guard-paths.sh pass
bash_hook "grep -E '/^area (site|api)/' log.txt"        guard-paths.sh pass
bash_hook 'gh run view 123 --log | grep /home/runner/work/x/y' guard-paths.sh pass
bash_hook 'cat /home/runner/work/ownconsent/ci.log'     guard-paths.sh pass
bash_hook 'cat /etc/hostname'                           guard-paths.sh pass
bash_hook "cp segreto.txt $HOME/uscita.txt"             guard-paths.sh deny
bash_hook 'cat ../cmp/.env'                             guard-paths.sh deny
bash_hook 'cd ../cmp; cat .env'                          guard-paths.sh deny

echo; echo "Lavoro normale — deve passare"
bash_hook 'npm run build'                             guard-prod.sh  pass
bash_hook 'go test -race ./...'                       guard-paths.sh pass
bash_hook 'git diff origin/main...HEAD'               guard-paths.sh pass
bash_hook 'kubectl get pods --context staging'        guard-prod.sh  pass

echo; echo "Segreti nei file — con un'esca, mai un file vero"
ESCA="$(mktemp -p "${TMPDIR:-/tmp}" esca-XXXX.js)"
# 36 caratteri esatti: il pattern di guard-secrets vuole ghp_ + 36.
# Se l'esca è piu' corta il test "fallisce" per colpa dell'esca, non dell'hook.
printf 'const t = "ghp_%s";\n' "$(printf '0%.0s' $(seq 36))" > "$ESCA"
file_hook "$ESCA" guard-secrets.sh deny
printf 'export const PORT = 3000;\n' > "$ESCA"
file_hook "$ESCA" guard-secrets.sh pass
rm -f "$ESCA"


echo; echo "Firma dei commit — su repo usa e getta, mai su questo"
# Dal 21/09 il ruolo arriva nella variabile CANTIERE_AGENT, che agent-env.py
# antepone ai comandi git. Si verifica la catena intera: payload di PreToolUse ->
# comando riscritto -> git hook -> trailer riconosciuto da git.
firma_prova() { # etichetta, agent_type (vuoto = filo principale, "-" = nessuna sessione), atteso
  local T R val cmd
  T=$(mktemp -d); R="$T/repo"; mkdir -p "$R"
  git -C "$R" init -q -b main >/dev/null 2>&1
  git -C "$R" config user.email prova@cantiere.invalid; git -C "$R" config user.name prova
  mkdir -p "$R/githooks"
  cp "$H/../../../template/githooks/prepare-commit-msg" "$R/githooks/" 2>/dev/null \
    || cp "$PWD/githooks/prepare-commit-msg" "$R/githooks/" 2>/dev/null \
    || { printf "  ${X}KO${N}    %-52s prepare-commit-msg non trovato\n" "$1"; KO=$((KO+1)); rm -rf "$T"; return; }
  chmod +x "$R/githooks/prepare-commit-msg"; git -C "$R" config core.hooksPath githooks
  echo a > "$R/a"; git -C "$R" add -A; git -C "$R" commit -qm base >/dev/null 2>&1
  git -C "$R" worktree add -q "$T/wt" -b lotto >/dev/null 2>&1
  cmd="cd '$T/wt' && echo b > b && git add -A && git commit -qm 'feat: x'"
  if [ "$2" != "-" ]; then
    cmd=$(printf '{"agent_type":"%s","tool_input":{"command":%s}}' "$2" \
          "$(printf '%s' "$cmd" | python3 -c 'import sys,json;print(json.dumps(sys.stdin.read()))')" \
          | python3 "$H/agent-env.py" \
          | python3 -c 'import sys,json;print(json.load(sys.stdin)["hookSpecificOutput"]["updatedInput"]["command"])')
  fi
  env -u CANTIERE_AGENT bash -c "$cmd" >/dev/null 2>&1
  val=$(git -C "$T/wt" log -1 --format='%(trailers:key=Cantiere-Agent,valueonly)' | tr -d '\n')
  [ -n "$val" ] || val="niente"
  if [ "$val" = "$3" ]; then printf "  ${V}ok${N}    %-52s %s\n" "$1" "$val"; OK=$((OK+1))
  else printf "  ${X}KO${N}    %-52s atteso %s, ottenuto %s\n" "$1" "$3" "$val"; KO=$((KO+1)); fi
  rm -rf "$T"
}
if command -v git >/dev/null 2>&1; then
  firma_prova 'subagente, in una worktree'           'cantiere:qa-test' qa-test
  firma_prova 'filo principale, in una worktree'     ''                 orchestrator
  firma_prova 'commit a mano, fuori da Claude Code'  '-'                niente
else
  printf "  ${X}KO${N}    %-52s git non installato\n" "firma dei commit"; KO=$((KO+1))
fi

echo; echo "Credenziali: la home si', il progetto no (21/09)"
bash_hook 'cat site/.npmrc'                            guard-paths.sh pass
bash_hook 'cat ~/.npmrc'                               guard-paths.sh deny
bash_hook 'cat $HOME/.netrc'                           guard-paths.sh deny

echo; echo "Troppo lavoro non committato: la scrittura si ferma"
TC=$(mktemp -d); git -C "$TC" init -q -b main
for n in $(seq 1 19); do echo x > "$TC/f$n"; done
file_hook "$TC/nuovo.txt" guard-commit.sh pass
echo x > "$TC/f20"
file_hook "$TC/nuovo.txt" guard-commit.sh deny
rm -rf "$TC"

echo; echo "Journal: conta il lavoro di questa sessione, non quello trovato sporco (20/09)"
journal_prova() { # etichetta, cosa fare dopo la foto, atteso(block|pass)
  local T r esito
  T=$(mktemp -d)
  ( cd "$T" && git init -q -b main && git config user.email t@t.invalid && git config user.name T \
    && mkdir -p site journal && echo a > site/a.md && git add -A && git commit -qm base \
    && echo "di un'altra sessione" >> site/a.md \
    && echo '{"session_id":"PROVA"}' | bash "$H/session-start.sh" >/dev/null 2>&1 \
    && eval "$2" )
  r=$(cd "$T" && echo '{"session_id":"PROVA"}' | bash "$H/journal-check.sh" 2>/dev/null)
  case "$r" in *'"block"'*) esito=block ;; *) esito=pass ;; esac
  if [ "$esito" = "$3" ]; then printf "  ${V}ok${N}    %-52s %s\n" "$1" "$esito"; OK=$((OK+1))
  else printf "  ${X}KO${N}    %-52s atteso %s, ottenuto %s\n" "$1" "$3" "$esito"; KO=$((KO+1)); fi
  rm -rf "$T"
}
journal_prova 'sola lettura, file gia sporco prima'  'true'                                   pass
journal_prova 'lavoro nuovo senza journal'           'echo b > site/b.md'                     block
journal_prova 'lavoro nuovo con journal'             'echo b > site/b.md; echo {} > journal/x.json' pass

echo
if [ "$KO" -eq 0 ]; then
  printf "${V}%d verifiche superate, 0 fallite.${N} I gate rispondono.\n\n" "$OK"
else
  printf "${X}%d fallite${N} su %d. Un gate che credi attivo e non lo è è peggio di nessun gate.\n\n" "$KO" "$((OK+KO))"
  exit 1
fi
