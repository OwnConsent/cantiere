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

echo; echo "Heredoc quotati: il corpo e' testo, la shell non lo espande (02/10)"
# $HOME/fuori.txt non esiste, ma la cartella che lo conterrebbe si': per il livello 3
# e' un percorso fuori dal progetto che si puo' toccare.
perimetro_prova() { # etichetta, comando, atteso
  local out rc
  out=$(python3 -c 'import sys,json;print(json.dumps({"tool_input":{"command":sys.argv[1]}}))' "$2" \
        | "$H/guard-paths.sh" 2>&1 >/dev/null); rc=$?
  verdetto "$rc" "$3" "$1" "$out"
}
perimetro_prova "--body-file - <<'EOF' che cita un percorso"  "gh pr create --title t --body-file - <<'EOF'
il collaudo gira in $HOME/fuori.txt e basta
EOF" pass
perimetro_prova "-F - <<'EOF' che cita un percorso"           "gh pr create --title t -F - <<'EOF'
il collaudo gira in $HOME/fuori.txt e basta
EOF" pass
perimetro_prova "cat > file <<'EOF', poi gh pr create -F"     "cat > corpo.md <<'EOF'
il collaudo gira in $HOME/fuori.txt e basta
EOF
gh pr create --title t -F corpo.md" pass
perimetro_prova '<<"EOF" e <<\EOF sono quotati'              "cat > a.md <<\"EOF\"
vedi $HOME/fuori.txt
EOF
cat > b.md <<\\EOF
vedi $HOME/fuori.txt
EOF" pass
perimetro_prova '--body=percorso in una parola'               "gh pr create --title t --body=$HOME/fuori.txt" pass
perimetro_prova 'heredoc NON quotato: resta scandito'         "gh pr create --title t -F - <<EOF
il collaudo gira in $HOME/fuori.txt e basta
EOF" deny
perimetro_prova "bash <<'EOF': il corpo e' codice"            "bash <<'EOF'
cat $HOME/fuori.txt
EOF" deny
perimetro_prova "cat <<'EOF' | bash: interprete sulla riga"   "cat <<'EOF' | bash
cat $HOME/fuori.txt
EOF" deny
perimetro_prova 'dopo la chiusura si torna a scandire'        "cat > a.md <<'EOF'
testo
EOF
cat $HOME/fuori.txt" deny
perimetro_prova 'heredoc quotato senza chiusura: scandito'    "cat <<'EOF'
cat $HOME/fuori.txt" deny
perimetro_prova 'heredoc quotato con una risalita: livello 4' "gh pr create --title t -F - <<'EOF'
il caso cat ../cmp/.env
EOF" deny

echo; echo "Heredoc quotati: elenco chiuso di chi li riceve (review della #18)"
# Si toglie il corpo solo per gh, git, tee e cat con redirezione su file, da soli
# sulla riga. Ogni altro comando lo esegue o lo usa come percorsi: resta scandito.
perimetro_prova "git commit -F - <<'EOF' che cita un percorso"  "git commit -F - <<'EOF'
il collaudo gira in $HOME/fuori.txt e basta
EOF" pass
perimetro_prova "tee file <<'EOF' che cita un percorso"       "tee nota.md <<'EOF'
il collaudo gira in $HOME/fuori.txt e basta
EOF" pass
perimetro_prova "source /dev/stdin <<'EOF'"                   "source /dev/stdin <<'EOF'
cat $HOME/fuori.txt
EOF" deny
perimetro_prova "xargs cat <<'EOF'"                           "xargs cat <<'EOF'
$HOME/fuori.txt
EOF" deny
perimetro_prova "while read ...; done <<'EOF'"                "while read f; do cat \"\$f\"; done <<'EOF'
$HOME/fuori.txt
EOF" deny
perimetro_prova "uv run - <<'EOF'"                            "uv run - <<'EOF'
cat $HOME/fuori.txt
EOF" deny
perimetro_prova "php <<'EOF'"                                 "php <<'EOF'
cat $HOME/fuori.txt
EOF" deny
perimetro_prova "bash<<'EOF' senza spazio"                    "bash<<'EOF'
cat $HOME/fuori.txt
EOF" deny
perimetro_prova "\"bash\" <<'EOF' fra virgolette"             "\"bash\" <<'EOF'
cat $HOME/fuori.txt
EOF" deny
perimetro_prova "gh ... <<'EOF' con una pipe sulla riga"      "gh pr create --title t -F - <<'EOF' | tee log
il collaudo gira in $HOME/fuori.txt e basta
EOF" deny
perimetro_prova "cat <<'EOF' da solo, fuori da una \$(...)"    "cat <<'EOF'
il collaudo gira in $HOME/fuori.txt e basta
EOF" deny
perimetro_prova "<<'X' dentro una stringa non e' un heredoc"  "echo \"<<'X'\"
cat $HOME/fuori.txt
X" deny
perimetro_prova "<<'X' dentro un commento non e' un heredoc"  "true # <<'X'
cat $HOME/fuori.txt
X" deny

# cat da solo dentro una $(...): testo solo se la $(...) e' il valore di un'opzione di
# testo di gh o git. Altrove decide chi la consuma, e sarebbe un elenco aperto.
perimetro_prova "git commit -m \"\$(cat <<'EOF' ...)\""        "git commit -m \"\$(cat <<'EOF'
il collaudo gira in $HOME/fuori.txt e basta
EOF
)\"" pass
perimetro_prova "gh ... --body=\"\$(cat <<'EOF' ...)\""        "gh pr create --title t --body=\"\$(cat <<'EOF'
il collaudo gira in $HOME/fuori.txt e basta
EOF
)\"" pass
perimetro_prova "bash -c \"\$(cat <<'EOF' ...)\""              "bash -c \"\$(cat <<'EOF'
cat $HOME/fuori.txt
EOF
)\"" deny
perimetro_prova "eval \"\$(cat <<'EOF' ...)\""                 "eval \"\$(cat <<'EOF'
cat $HOME/fuori.txt
EOF
)\"" deny
perimetro_prova "gh ...; bash -c \"\$(cat <<'EOF' ...)\""      "gh pr list --title t; bash -c \"\$(cat <<'EOF'
cat $HOME/fuori.txt
EOF
)\"" deny
perimetro_prova "python3 -m \"\$(...)\": -m di testo, ma non di gh"  "python3 -m \"\$(cat <<'EOF'
$HOME/fuori.txt
EOF
)\"" deny
perimetro_prova "gh su una riga, python3 -m sulla successiva" "gh pr list
python3 -m \"\$(cat <<'EOF'
$HOME/fuori.txt
EOF
)\"" deny
perimetro_prova "gh -F \"\$(cat <<'EOF' ...)\": -F non e' testo" "gh pr create --title t -F \"\$(cat <<'EOF'
$HOME/fuori.txt
EOF
)\"" deny
perimetro_prova "eval \"gh ... --body \\\"\$(cat <<'EOF'\\\"\""  "eval \"gh pr create --body \\\"\$(cat <<'EOF'
cat $HOME/fuori.txt
EOF
)\\\"\"" deny

# seconda review della #18: le forme comuni di commit, e un commento con un apostrofo
perimetro_prova "git commit -am \"\$(cat <<'EOF' ...)\""       "git commit -am \"\$(cat <<'EOF'
il collaudo gira in $HOME/fuori.txt e basta
EOF
)\"" pass
perimetro_prova "git commit -m\"\$(cat <<'EOF' ...)\" attaccata" "git commit -m\"\$(cat <<'EOF'
il collaudo gira in $HOME/fuori.txt e basta
EOF
)\"" pass
perimetro_prova "git commit -m \\ e il valore a capo"          "git commit -m \\
  \"\$(cat <<'EOF'
il collaudo gira in $HOME/fuori.txt e basta
EOF
)\"" pass
perimetro_prova "# don't forget sulla riga prima"             "# don't forget
git commit -m \"\$(cat <<'EOF'
il collaudo gira in $HOME/fuori.txt e basta
EOF
)\"" pass
perimetro_prova "git -C dir commit -F - <<'EOF'"              "git -C site commit -F - <<'EOF'
il collaudo gira in $HOME/fuori.txt e basta
EOF" pass
# l'elenco si fida del nome: se il nome puo' essere stato ridefinito, niente si toglie
perimetro_prova "gh() { bash; } e poi gh <<'EOF'"             "gh() { bash; }
gh <<'EOF'
cat $HOME/fuori.txt
EOF" deny
perimetro_prova "function gh { bash; }; gh <<'EOF'"           "function gh { bash; }
gh <<'EOF'
cat $HOME/fuori.txt
EOF" deny
perimetro_prova "alias gh=bash e poi gh <<'EOF'"              "alias gh=bash
gh <<'EOF'
cat $HOME/fuori.txt
EOF" deny
perimetro_prova "git -c 'alias.x=!bash' x <<'EOF'"            "git -c 'alias.x=!bash' x <<'EOF'
cat $HOME/fuori.txt
EOF" deny
perimetro_prova "git --exec-path=... commit -F - <<'EOF'"     "git --exec-path=bin commit -F - <<'EOF'
cat $HOME/fuori.txt
EOF" deny
perimetro_prova "gh() {...}; gh -m \"\$(cat <<'EOF' ...)\""    "gh() { bash -c \"\$2\"; }; gh -m \"\$(cat <<'EOF'
cat $HOME/fuori.txt
EOF
)\"" deny
perimetro_prova "git -c ... -m \"\$(cat <<'EOF' ...)\""        "git -c 'alias.x=!f() { bash -c \"\$2\"; }; f' x -m \"\$(cat <<'EOF'
cat $HOME/fuori.txt
EOF
)\"" deny

# con un comando dell'elenco il corpo si toglierebbe: qui << non apre niente
perimetro_prova "gh --body \"... <<'X'\": stringa, non heredoc"  "gh pr comment 1 --body \"usa <<'X' cosi\"
cat $HOME/fuori.txt
X" deny
perimetro_prova "git status # <<'X': commento, non heredoc"   "git status # <<'X'
cat $HOME/fuori.txt
X" deny

# Livello 2, eseguito a parte: un'area in .cantiere-deny non si legge passando il
# percorso nel corpo di un heredoc quotato. Il progetto di prova sta sotto /tmp, dove
# il livello 3 non nega niente: il diniego viene solo dall'elenco.
TD=$(mktemp -d); printf 'site/riservato\n' > "$TD/.cantiere-deny"
deny_prova() { # etichetta, comando, atteso: deny-elenco | pass
  local out rc esito
  out=$(python3 -c 'import sys,json;print(json.dumps({"tool_input":{"command":sys.argv[1]}}))' "$2" \
        | CLAUDE_PROJECT_DIR="$TD" "$H/guard-paths.sh" 2>&1 >/dev/null); rc=$?
  esito=pass
  [ "$rc" -eq 2 ] && case "$out" in *"riferimento a 'site/riservato'"*) esito=deny-elenco ;; *) esito=deny-altro ;; esac
  if [ "$esito" = "$3" ]; then printf "  ${V}ok${N}    %-52s %s\n" "$1" "$esito"; OK=$((OK+1))
  else printf "  ${X}KO${N}    %-52s atteso %s, ottenuto %s\n" "$1" "$3" "$esito"; KO=$((KO+1)); fi
}
deny_prova ".cantiere-deny: xargs cat <<'EOF' con l'area"     "xargs cat <<'EOF'
site/riservato/x
EOF" deny-elenco
deny_prova ".cantiere-deny: gh ... <<'EOF' che la cita"       "gh pr create --title t -F - <<'EOF'
il lotto non legge site/riservato/x
EOF" pass
rm -rf "$TD"

echo; echo "Sostituzioni di comando: dentro le virgolette doppie si eseguono (02/10)"
perimetro_prova '--body "$(cat /fuori)"'                      "gh pr create --title t --body \"\$(cat $HOME/fuori.txt)\"" deny
perimetro_prova '--body "... `cat /fuori` ..."'               "gh pr create --title t --body \"prima \`cat $HOME/fuori.txt\` dopo\"" deny
perimetro_prova '--body="$(cat /fuori) ..."'                  "gh pr create --title t --body=\"\$(cat $HOME/fuori.txt) x\"" deny
perimetro_prova 'sostituzione dentro una sostituzione'        "echo \"\$(echo \"\$(cat $HOME/fuori.txt)\")\"" deny
perimetro_prova "un apostrofo fra le doppie non la nasconde"   "gh pr create --title t --body \"l'hook legge \$(cat $HOME/fuori.txt) e basta\"" deny
perimetro_prova "heredoc non quotato: l'apostrofo non la nasconde" "gh pr create --title t -F - <<EOF
l'hook legge \$(cat $HOME/fuori.txt) e l'altro
EOF" deny
perimetro_prova "apostrofo in un commento, poi una sostituzione" "echo ciao # non c'e
echo \"x \$(cat $HOME/fuori.txt) y\"" deny
perimetro_prova "una ) fra apici non chiude la sostituzione"  "echo \"\$(echo ')'; cat $HOME/fuori.txt)\"" deny
perimetro_prova '--body "$(cat dentro/il/progetto)"'          'gh pr create --title t --body "$(cat docs/x.md)"' pass
perimetro_prova '--body "testo con /percorso/fuori"'          "gh pr create --title t --body \"testo con $HOME/fuori.txt dentro\"" pass
perimetro_prova "fra apici singoli non si esegue"             "git commit -m 'la forma \$(cat $HOME/fuori.txt) passava'" pass
perimetro_prova "--body \"\$(cat <<'EOF' ...)\" con un percorso" "gh pr create --title t --body \"\$(cat <<'EOF'
il collaudo gira in $HOME/fuori.txt e basta
EOF
)\"" pass

echo; echo "Fail-closed: se il parser si rompe, il comando e' negato (seconda review della #18)"
# Un hook che esce con 1 e' un errore non bloccante: il comando passerebbe.
perimetro_prova '1200 $( di fila: negato, non in errore'     "cat $HOME/fuori.txt $(printf '$(%.0s' $(seq 1200))" deny
perimetro_prova '1200 $( di fila, senza altro'               "echo $(printf '$(%.0s' $(seq 1200))" deny
out=$(python3 -c 'import json;print(json.dumps({"tool_input":{"command":"echo "+"$("*1200}}))' | "$H/guard-paths.sh" 2>&1 >/dev/null); rc=$?
case "$rc:$out" in
  2:*"troppe sostituzioni di comando annidate"*) printf "  ${V}ok${N}    %-52s %s\n" "1200 \$(: il diniego dice il motivo" "testo presente"; OK=$((OK+1)) ;;
  *) printf "  ${X}KO${N}    %-52s uscita %s\n" "1200 \$(: il diniego dice il motivo" "$rc"; KO=$((KO+1)) ;;
esac
out=$(printf '{"tool_input":{"command":123}}' | "$H/guard-paths.sh" 2>&1 >/dev/null); rc=$?
case "$rc:$out" in
  2:*"errore del parser"*) printf "  ${V}ok${N}    %-52s %s\n" "eccezione qualsiasi (comando non stringa): negato" "deny"; OK=$((OK+1)) ;;
  *) printf "  ${X}KO${N}    %-52s uscita %s\n" "eccezione qualsiasi (comando non stringa): negato" "$rc"; KO=$((KO+1)) ;;
esac

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
trova_githook() { # dal repo di cantiere, o dal progetto che ha copiato il template
  local f
  for f in "$H/../../../template/githooks/prepare-commit-msg" "$PWD/githooks/prepare-commit-msg"; do
    [ -f "$f" ] && { printf '%s' "$f"; return 0; }
  done
  return 1
}
firma_prova() { # etichetta, agent_type (vuoto = filo principale, "-" = nessuna sessione), atteso
  local T R val cmd
  T=$(mktemp -d); R="$T/repo"; mkdir -p "$R"
  git -C "$R" init -q -b main >/dev/null 2>&1
  git -C "$R" config user.email prova@cantiere.invalid; git -C "$R" config user.name prova
  mkdir -p "$R/githooks"
  cp "$(trova_githook)" "$R/githooks/" 2>/dev/null \
    || { printf "  ${X}KO${N}    %-52s prepare-commit-msg non trovato\n" "$1"; KO=$((KO+1)); rm -rf "$T"; return; }
  cp "$(dirname "$(trova_githook)")/ruoli" "$R/githooks/" 2>/dev/null
  chmod +x "$R/githooks/prepare-commit-msg"; git -C "$R" config core.hooksPath githooks
  echo a > "$R/a"; git -C "$R" add -A
  env -u CLAUDECODE -u CANTIERE_AGENT git -C "$R" commit -qm base >/dev/null 2>&1
  git -C "$R" worktree add -q "$T/wt" -b lotto >/dev/null 2>&1
  cmd="cd '$T/wt' && echo b > b && git add -A && git commit -qm 'feat: x'"
  if [ "$2" != "-" ]; then
    cmd=$(printf '{"agent_type":"%s","tool_input":{"command":%s}}' "$2" \
          "$(printf '%s' "$cmd" | python3 -c 'import sys,json;print(json.dumps(sys.stdin.read()))')" \
          | python3 "$H/agent-env.py" \
          | python3 -c 'import sys,json;print(json.load(sys.stdin)["hookSpecificOutput"]["updatedInput"]["command"])')
  fi
  # CLAUDECODE lo imposta Claude Code nei processi che lancia: qui lo si mette o lo
  # si toglie a mano, perche' la suite gira sia da una sessione sia in CI.
  if [ "$2" != "-" ]; then env -u CANTIERE_AGENT CLAUDECODE=1 bash -c "$cmd" >/dev/null 2>&1
  else env -u CANTIERE_AGENT -u CLAUDECODE bash -c "$cmd" >/dev/null 2>&1; fi
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
# Le worktree condividono .git: un commit sul ramo del lotto non e' raggiungibile da
# HEAD della sessione principale. Prima del 24/09 non veniva contato e journal-check
# taceva su un lavoro fatto e committato.
journal_prova 'lavoro committato su un altro ramo'   'git switch -qc lotto/x; echo b > site/b.md; git add site/b.md; git commit -qm lavoro; git switch -q main' block

# ---------------------------------------------------------------------------
# Aggiunte del 24/09 — gate a tempo, ts del journal, force-with-lease,
# livello 2 di guard-paths sugli argomenti.
# ---------------------------------------------------------------------------

write_hook() { # etichetta, percorso, contenuto, hook, atteso
  local out rc
  out=$(python3 -c 'import json,sys; print(json.dumps({"tool_input":{"file_path":sys.argv[1],"content":sys.argv[2]}}))' "$2" "$3" \
        | "$H/$4" 2>&1 >/dev/null); rc=$?
  verdetto "$rc" "$5" "$1" "$out"
}

tempo_prova() { # etichetta, eta_commit_minuti, sporco(si|no), comando, atteso
  local T out rc quando
  T=$(mktemp -d)
  quando=$(python3 -c "import time,sys; print(int(time.time())-int(sys.argv[1])*60)" "$2")
  (
    cd "$T" && git init -q -b main \
      && git config user.email t@t.invalid && git config user.name T \
      && mkdir -p site && echo a > site/a.md && git add -A \
      && GIT_AUTHOR_DATE="@$quando +0000" GIT_COMMITTER_DATE="@$quando +0000" \
         git commit -qm base
    [ "$3" = si ] && echo modifica >> "$T/site/a.md"
  ) >/dev/null 2>&1
  out=$(cd "$T" && CLAUDE_PROJECT_DIR="$T" python3 -c 'import json,sys; print(json.dumps({"tool_input":{"command":sys.argv[1]}}))' "$4" \
        | CLAUDE_PROJECT_DIR="$T" "$H/guard-tempo.py" 2>&1 >/dev/null); rc=$?
  verdetto "$rc" "$5" "$1" "$out"
  rm -rf "$T"
}

deny_prova() { # etichetta, comando, atteso
  local T out rc
  T=$(mktemp -d); mkdir -p "$T/journal"; printf 'progetto-vietato\n' > "$T/.cantiere-deny"
  out=$(cd "$T" && CLAUDE_PROJECT_DIR="$T" python3 -c 'import json,sys; print(json.dumps({"tool_input":{"command":sys.argv[1]}}))' "$2" \
        | CLAUDE_PROJECT_DIR="$T" "$H/guard-paths.py" 2>&1 >/dev/null); rc=$?
  verdetto "$rc" "$3" "$1" "$out"
  rm -rf "$T"
}

echo; echo "Gate a tempo sui commit — protegge l'attribuzione, non il lavoro"
tempo_prova 'commit vecchio 90 min, lavoro sporco'   90 si 'ls site'            deny
tempo_prova 'commit vecchio 90 min, albero pulito'   90 no 'ls site'            pass
tempo_prova 'commit di 2 minuti, lavoro sporco'       2 si 'ls site'            pass
tempo_prova 'la via d uscita non si blocca'          90 si 'git commit -am x'   pass
tempo_prova 'anche git status passa'                 90 si 'git status'         pass

echo; echo "ts del journal — l'orario si misura, non si ricorda"
write_hook 'ts di adesso'            journal/2026-09-24/x.json "{\"ts\":\"$(date -Is)\",\"tipo\":\"misura\"}" journal-ts.py pass
write_hook 'ts di tre ore prima'     journal/2026-09-24/x.json '{"ts":"2020-01-01T10:00:00+02:00"}'            journal-ts.py deny
write_hook 'ts illeggibile'          journal/2026-09-24/x.json '{"ts":"ieri sera"}'                            journal-ts.py deny
write_hook 'senza campo ts'          journal/2026-09-24/x.json '{"tipo":"misura"}'                             journal-ts.py pass
write_hook 'fuori da journal/'       site/src/pages/x.astro    '{"ts":"2020-01-01T10:00:00+02:00"}'            journal-ts.py pass
write_hook 'json non valido'         journal/2026-09-24/x.json 'non sono json'                                 journal-ts.py pass

echo; echo "push forzato: --force-with-lease e' il modo corretto, non un'eccezione"
bash_hook 'git push --force-with-lease origin lotto/l15' guard-prod.sh pass
bash_hook 'git push --force-with-lease origin main'      guard-prod.sh deny
bash_hook 'git push --force origin lotto/l15'            guard-prod.sh deny
bash_hook 'git push -f origin lotto/l15'                 guard-prod.sh deny

echo; echo "livello 2 di guard-paths: nominare non e' leggere (falsi positivi del 23/09)"
deny_prova 'il percorso vietato come argomento'  'cat progetto-vietato/note.md'                       deny
deny_prova 'citato in un messaggio di commit'    'git commit -m "la voce cita progetto-vietato"'      pass
deny_prova 'citato nel corpo di una PR'          'gh pr comment 1 --body "vedi progetto-vietato/x"'   pass
deny_prova 'citato dentro un heredoc'            'cat <<EOF > journal/x.json
{"nota":"progetto-vietato resta fuori"}
EOF'                                                                                                  pass

# ---------------------------------------------------------------------------
# Aggiunte del 01/10 — firma dal payload (primo strato), diniego nel git hook
# (secondo strato), avviso di main indietro.
# ---------------------------------------------------------------------------

agente_prova() { # etichetta, agent_type ('' = filo principale), comando, atteso: deny | niente | <ruolo>
  local uscita rc esito
  uscita=$(python3 -c 'import json,sys
d={"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":sys.argv[2]}}
if sys.argv[1]: d["agent_type"]=sys.argv[1]
print(json.dumps(d))' "$2" "$3" | "$H/agent-env.py" 2>/dev/null); rc=$?
  if [ "$rc" -eq 2 ]; then esito=deny
  elif [ -z "$uscita" ]; then esito=niente
  else esito=$(printf '%s' "$uscita" | python3 -c 'import sys,json,re
c=json.load(sys.stdin)["hookSpecificOutput"]["updatedInput"]["command"]
m=re.match(r"readonly CANTIERE_AGENT=(\S+); export CANTIERE_AGENT; ",c); print(m.group(1) if m else "malformato")')
  fi
  if [ "$esito" = "$4" ]; then printf "  ${V}ok${N}    %-52s %s\n" "$1" "$esito"; OK=$((OK+1))
  else printf "  ${X}KO${N}    %-52s atteso %s, ottenuto %s\n" "$1" "$4" "$esito"; KO=$((KO+1)); fi
}

echo; echo "Primo strato — agent-env.py: il ruolo viene dal payload, su ogni comando che nomina git"
agente_prova 'filo principale: git commit -m'          ''                 'git commit -m "x"'                    orchestrator
agente_prova 'subagente di cantiere: git commit -m'    'cantiere:qa-test' 'git commit -m "x"'                    qa-test
agente_prova 'git -C <dir> commit'                     'cantiere:devops'  'git -C /percorso commit -m x'         devops
agente_prova 'cd <dir> && git commit'                  ''                 'cd dir && git commit -m x'            orchestrator
agente_prova 'git commit -F - con heredoc'             ''                 "git commit -F - <<'EOF'
titolo
EOF"                                                                                                              orchestrator
agente_prova 'bash -c "git commit"'                    ''                 'bash -c "git commit -m x"'            orchestrator
agente_prova 'git merge --no-ff'                       'cantiere:qa-test' 'git merge --no-ff origin/x'           qa-test
agente_prova 'ruolo esplicito uguale al payload'       ''                 'CANTIERE_AGENT=orchestrator git commit -m x' orchestrator
# niente prefisso sui comandi che non nominano git: costerebbe un'approvazione a
# ogni comando (prova dei permessi del 02/10)
agente_prova 'script che non nomina git: niente prefisso' 'cantiere:devops' './scripts/x.sh'                     niente
agente_prova 'npm test: niente prefisso'               ''                 'npm test'                             niente
agente_prova 'ls: niente prefisso'                     'Explore'          'ls -la'                               niente
agente_prova 'make release: niente prefisso'           'cantiere:devops'  'make release'                         niente
agente_prova 'il messaggio cita la variabile'          ''                 'git commit -m "fix: CANTIERE_AGENT= vuota"' orchestrator
agente_prova 'heredoc che cita la variabile'           ''                 "git commit -F - <<'EOF'
prima era CANTIERE_AGENT=qa-test a mano
EOF"                                                                                                              orchestrator

echo; echo "Primo strato — fuori dalla stessa shell il readonly non vale: env e shell figlie negate"
agente_prova 'env con un altro ruolo'                  'cantiere:qa-test' 'env CANTIERE_AGENT=orchestrator git commit -m x' deny
agente_prova 'env con la variabile fra virgolette'     'cantiere:qa-test' 'env "CANTIERE_AGENT=orchestrator" git commit -m x' deny
agente_prova 'env con la variabile vuota'              ''                 'env CANTIERE_AGENT= git commit -m x'  deny
agente_prova 'env -u'                                  ''                 'env -u CANTIERE_AGENT git commit -m x' deny
agente_prova 'env --unset='                            ''                 'env --unset=CANTIERE_AGENT git commit -m x' deny
agente_prova '/usr/bin/env dopo un ;'                  'cantiere:qa-test' 'ls -m;/usr/bin/env CANTIERE_AGENT=orchestrator git commit -m x' deny
agente_prova 'env su uno script'                       'cantiere:qa-test' 'env CANTIERE_AGENT=orchestrator ./scripts/x.sh' deny
agente_prova 'bash -c con assegnazione'                ''                 'bash -c "CANTIERE_AGENT=qa-test git commit -m x"' deny
agente_prova 'sh -c con assegnazione'                  'cantiere:qa-test' "sh -c 'CANTIERE_AGENT=orchestrator git commit -m x'" deny
agente_prova 'bash -c con env dentro'                  'cantiere:qa-test' "bash -c 'env CANTIERE_AGENT=orchestrator git commit -m x'" deny
agente_prova 'bash <<EOF con assegnazione nel corpo'     'cantiere:qa-test' "bash <<'EOF'
CANTIERE_AGENT=orchestrator git commit -m x
EOF"                                                                                                              deny
agente_prova 'echo ... | bash con assegnazione'        'cantiere:qa-test' "echo 'CANTIERE_AGENT=orchestrator git commit -m x' | bash" deny
agente_prova 'echo ciao | bash: ammesso'               'cantiere:qa-test' 'echo ciao | bash'                     niente
agente_prova 'bash <<EOF senza la variabile: ammesso'  'cantiere:qa-test' "bash <<'EOF'
git status
EOF"                                                                                                              qa-test
agente_prova 'env con il ruolo del payload: ammesso'   'cantiere:qa-test' 'env CANTIERE_AGENT=qa-test git commit -m x' qa-test
agente_prova 'messaggio che cita env -u: non e un comando' ''             'git commit -m "nega env -u CANTIERE_AGENT e env CANTIERE_AGENT=x"' orchestrator
agente_prova 'git grep della variabile'                ''                 'git grep -n "CANTIERE_AGENT=" plugins' orchestrator
agente_prova 'heredoc che cita env'                    ''                 "git commit -F - <<'EOF'
prima: env CANTIERE_AGENT=qa-test git commit
EOF"                                                                                                              orchestrator

echo; echo "Primo strato — nella stessa shell il readonly regge: comando riscritto ed ESEGUITO (repo usa e getta)"
# Il payload e' di cantiere:qa-test e il comando prova a firmare da orchestrator, un
# ruolo valido che il secondo strato accetterebbe. Si esegue in /bin/bash, la shell
# del Bash tool, il comando riscritto da agent-env.py, con il git hook vero.
shell_prova() { # etichetta, forma (GC = il commit), atteso: <ruolo> | nessun-commit | negato-primo
  local T cmd val prima
  T=$(mktemp -d)
  ( unset CLAUDECODE CANTIERE_AGENT; git init -q -b main "$T/r" && cd "$T/r" && git config user.email p@p.invalid \
    && git config user.name p && echo a > a && git add -A && git commit -qm base \
    && mkdir githooks && cp "$(trova_githook)" "$(dirname "$(trova_githook)")/ruoli" githooks/ \
    && chmod +x githooks/prepare-commit-msg && git config core.hooksPath githooks && echo b > b && git add b \
    && printf '#!/bin/bash\nCANTIERE_AGENT=orchestrator git commit -qm t\n' > "$T/s.sh" \
    && printf '#!/bin/bash\ngit commit -qm t\n' > "$T/pulito.sh" && chmod +x "$T/s.sh" "$T/pulito.sh" ) >/dev/null 2>&1
  prima=$(git -C "$T/r" rev-parse HEAD)
  cmd="cd '$T/r' && ${2//GC/git commit -qm t}"; cmd="${cmd//SCRIPT/$T}"
  local orig="$cmd" primo uscita
  uscita=$(python3 -c 'import json,sys; print(json.dumps({"agent_type":"cantiere:qa-test","tool_input":{"command":sys.argv[1]}}))' "$cmd" \
        | "$H/agent-env.py" 2>/dev/null); primo=$?
  cmd=$(printf '%s' "$uscita" | python3 -c 'import sys,json;print(json.load(sys.stdin)["hookSpecificOutput"]["updatedInput"]["command"])' 2>/dev/null)
  # uscita 0 senza riscrittura: il comando non nomina git e gira cosi' com'e'
  [ "$primo" -eq 0 ] && [ -z "$cmd" ] && cmd="$orig"
  if [ "$primo" -eq 2 ]; then val=negato-primo
  else
    env -u CANTIERE_AGENT CLAUDECODE=1 /bin/bash -c "$cmd" >/dev/null 2>&1
    if [ "$(git -C "$T/r" rev-parse HEAD)" = "$prima" ]; then val=nessun-commit
    else val=$(git -C "$T/r" log -1 --format='%(trailers:key=Cantiere-Agent,valueonly)' | tr -d '\n'); [ -n "$val" ] || val=senza-firma; fi
  fi
  if [ "$val" = "$3" ]; then printf "  ${V}ok${N}    %-52s %s\n" "$1" "$val"; OK=$((OK+1))
  else printf "  ${X}KO${N}    %-52s atteso %s, ottenuto %s\n" "$1" "$3" "$val"; KO=$((KO+1)); fi
  rm -rf "$T"
}
shell_prova 'nessuna manomissione'                       'GC'                                        qa-test
shell_prova 'CANTIERE_AGENT=x git commit'                'CANTIERE_AGENT=orchestrator GC'            qa-test
shell_prova 'export CANTIERE_AGENT=x; ...'               'export CANTIERE_AGENT=orchestrator; GC'    qa-test
shell_prova 'export "CANTIERE_AGENT=x"; ...'             'export "CANTIERE_AGENT=orchestrator"; GC'  qa-test
shell_prova 'unset CANTIERE_AGENT; ...'                  'unset CANTIERE_AGENT; GC'                  qa-test
shell_prova 'declare CANTIERE_AGENT=x; ...'              'declare CANTIERE_AGENT=orchestrator; GC'   qa-test
shell_prova 'eval "CANTIERE_AGENT=x git commit"'         'eval "CANTIERE_AGENT=orchestrator GC"'     qa-test
shell_prova 'ls -m;CANTIERE_AGENT=x git commit'          'ls -m >/dev/null;CANTIERE_AGENT=orchestrator GC' qa-test
shell_prova 'local dentro una funzione'                  'f(){ local CANTIERE_AGENT=orchestrator; GC; }; f' qa-test
shell_prova 'CANTIERE_AGENT=x; git commit (si ferma)'    'CANTIERE_AGENT=orchestrator; GC'           nessun-commit
shell_prova 'in una sottoshell (si ferma)'               '(CANTIERE_AGENT=orchestrator; GC)'         nessun-commit
shell_prova 'export -n: il git hook nega'                'export -n CANTIERE_AGENT; GC'              nessun-commit
shell_prova 'CANTIERE_AGENT= vuota'                      'CANTIERE_AGENT= GC'                        qa-test
shell_prova 'script che non nomina git: lo nega il git hook' 'SCRIPT/pulito.sh'                       nessun-commit
shell_prova 'env CANTIERE_AGENT=x: negato prima'         'env CANTIERE_AGENT=orchestrator GC'        negato-primo
shell_prova 'bash -c con assegnazione: negato prima'     "bash -c 'CANTIERE_AGENT=orchestrator GC'"  negato-primo
shell_prova 'CONFINE: script che assegna e committa'     'SCRIPT/s.sh'                               orchestrator

echo; echo "Primo strato — chi non e' un ruolo di cantiere non committa"
agente_prova 'Explore: git -C con spazio, commit'      'Explore'          'git -C "/tmp/a b" commit -m x'        deny
agente_prova 'Explore: git merge-base legge'           'Explore'          'git merge-base main HEAD'             Explore
agente_prova 'general-purpose: git merge-tree legge'   'general-purpose'  'git merge-tree main lato'             general-purpose
agente_prova 'Explore: git commit-graph legge'         'Explore'          'git commit-graph verify'              Explore
agente_prova 'Explore: grep di "git commit"'           'Explore'          'grep -rn "git commit" plugins'        Explore
agente_prova 'general-purpose: echo che cita git merge' 'general-purpose' 'git log --oneline; echo "poi git merge"' general-purpose
agente_prova 'Explore: bash -c "git commit"'           'Explore'          'bash -c "git commit -m x"'            deny
agente_prova 'Explore: commit con heredoc in pipe'     'Explore'          "cat <<'EOF' | git commit -F -
titolo
EOF"                                                                                                              deny
agente_prova 'altro plugin, nome di un ruolo vero'     'altro:qa-test'    'git commit -m x'                      deny
agente_prova 'Explore: git commit'                     'Explore'          'git commit -m x'                      deny
agente_prova 'general-purpose: git -C <dir> commit'    'general-purpose'  'git -C /p commit -m x'                deny
agente_prova 'general-purpose: git merge'              'general-purpose'  'git merge --no-ff x'                  deny
agente_prova 'tipo di un altro plugin: commit'         'altro:revisore'   'cd d && git commit -m x'              deny
agente_prova 'nome non valido (sconosciuto): commit'   'due parole'       'git commit -m x'                      deny
agente_prova 'ruolo vero ma senza prefisso: commit'     'qa-test'          'git commit -m x'                      deny
agente_prova 'ruolo vero senza prefisso: merge'        'frontend'         'git merge --no-ff x'                  deny
agente_prova 'senza prefisso: git log, mai un ruolo vero' 'qa-test'       'git log --oneline -5'                 sconosciuto
agente_prova 'con il prefisso: ammesso'                'cantiere:frontend' 'git commit -m x'                     frontend
out=$(printf '{"agent_type":"qa-test","tool_input":{"command":"git commit -m x"}}' | "$H/agent-env.py" 2>&1 >/dev/null)
case "$out" in
  *"agent_type ricevuto: «qa-test»"*"cantiere:<ruolo>"*) printf "  ${V}ok${N}    %-52s %s\n" "il diniego riporta l'agent_type ricevuto" "testo presente"; OK=$((OK+1)) ;;
  *) printf "  ${X}KO${N}    %-52s %s\n" "il diniego riporta l'agent_type ricevuto" "testo assente"; KO=$((KO+1)) ;;
esac
agente_prova 'Explore: git log resta permesso'         'Explore'          'git log --oneline -5'                 Explore
agente_prova 'Explore: git log --grep commit'          'Explore'          'git log --grep "commit"'              Explore

echo; echo "Secondo strato — il git hook da solo, senza agent-env.py (repo usa e getta)"
# Git chiamato direttamente, quindi il primo strato non c'e': e' il caso di una
# sessione partita senza il plugin, misurato su ownconsent-www dal 26/09.
hook_prova() { # CLAUDECODE(si|no), valore di CANTIERE_AGENT ('' = vuota), operazione, atteso: negato | niente | <ruolo>
  local T R rc val prima etichetta
  local -a amb op
  etichetta="CLAUDECODE=$1 ruolo=[${2}] $3"
  trova_githook >/dev/null || { printf "  ${X}KO${N}    %-52s prepare-commit-msg non trovato\n" "$etichetta"; KO=$((KO+1)); return; }
  T=$(mktemp -d); R="$T/repo"
  (
    export -n CLAUDECODE CANTIERE_AGENT 2>/dev/null; unset CLAUDECODE CANTIERE_AGENT
    git init -q -b main "$R" && cd "$R" && git config user.email prova@cantiere.invalid && git config user.name prova \
      && echo a > a && git add -A && git commit -qm base \
      && git switch -qc lato && echo l > l && git add -A && git commit -qm lato \
      && git switch -q main && echo d > d && git add -A && git commit -qm d \
      && mkdir githooks && cp "$(trova_githook)" "$(dirname "$(trova_githook)")/ruoli" githooks/ \
      && chmod +x githooks/prepare-commit-msg && git config core.hooksPath githooks
  ) >/dev/null 2>&1
  prima=$(git -C "$R" rev-parse HEAD)
  amb=(env -u CLAUDECODE -u CANTIERE_AGENT)
  [ "$1" = si ] && amb+=(CLAUDECODE=1)
  [ -n "$2" ] && amb+=(CANTIERE_AGENT="$2")
  case "$3" in
    commit)      echo n > "$R/n"; git -C "$R" add -A; op=(commit -qm 'feat: x') ;;
    commit-nv)   echo n > "$R/n"; git -C "$R" add -A; op=(commit -qm 'feat: x' --no-verify) ;;
    merge)       op=(merge -q --no-ff --no-edit lato) ;;
    merge-nv)    op=(merge -q --no-ff --no-edit --no-verify lato) ;;
    amend)       op=(commit -q --amend --no-edit) ;;
    firma-a-mano) echo n > "$R/n"; git -C "$R" add -A; op=(commit -qm 'feat: x' -m 'Cantiere-Agent: orchestrator') ;;
    finto-rebase) mkdir "$(git -C "$R" rev-parse --absolute-git-dir)/rebase-merge"; echo n > "$R/n"; git -C "$R" add -A; op=(commit -qm 'feat: x') ;;
  esac
  "${amb[@]}" git -C "$R" "${op[@]}" >/dev/null 2>&1; rc=$?
  if [ "$rc" -ne 0 ] && [ "$(git -C "$R" rev-parse HEAD)" = "$prima" ]; then val=negato
  else
    val=$(git -C "$R" log -1 --format='%(trailers:key=Cantiere-Agent,valueonly)' | tr -d '\n')
    [ -n "$val" ] || val=niente
  fi
  if [ "$val" = "$4" ]; then printf "  ${V}ok${N}    %-52s %s\n" "$etichetta" "$val"; OK=$((OK+1))
  else printf "  ${X}KO${N}    %-52s atteso %s, ottenuto %s\n" "$etichetta" "$4" "$val"; KO=$((KO+1)); fi
  rm -rf "$T"
}
if command -v git >/dev/null 2>&1; then
  for o in commit commit-nv merge merge-nv amend; do
    hook_prova si ''       "$o" negato
    hook_prova si qa-test  "$o" qa-test
    hook_prova si Explore  "$o" negato
  done
  hook_prova si $'qa-test\nqualsiasi cosa' commit negato
  hook_prova si qa-test      firma-a-mano qa-test
  hook_prova si orchestrator firma-a-mano orchestrator
  hook_prova no ''           firma-a-mano orchestrator
  # collaudo di ownconsent-www #77: una cartella di rebase fatta con mkdir non apre
  # la porta a un commit senza ruolo. Fuori da Claude Code niente cambia.
  hook_prova si ''           finto-rebase negato
  hook_prova si Explore      finto-rebase negato
  hook_prova no ''           finto-rebase niente
  # fuori da Claude Code niente cambia: nessun diniego, i merge non si firmano, e
  # una persona che imposta la variabile ottiene il trailer che ha chiesto
  for o in commit commit-nv amend; do
    hook_prova no ''       "$o" niente
    hook_prova no qa-test  "$o" qa-test
    hook_prova no Explore  "$o" Explore
  done
  for o in merge merge-nv; do
    hook_prova no ''       "$o" niente
    hook_prova no qa-test  "$o" niente
    hook_prova no Explore  "$o" niente
  done
else
  printf "  ${X}KO${N}    %-52s git non installato\n" "git hook"; KO=$((KO+1))
fi

echo; echo "Secondo strato — la firma e' di chi fa QUESTO commit: quella ereditata si sostituisce"
eredita_prova() { # sorgente, atteso (<ruolo>x<quante firme>), [mantieni CLAUDECODE: si|no]
  local T R val etichetta sess
  etichetta="qa-test su un commit firmato devops: $1"
  T=$(mktemp -d); R="$T/repo"
  (
    unset CLAUDECODE CANTIERE_AGENT
    git init -q -b main "$R" && cd "$R" && git config user.email prova@cantiere.invalid && git config user.name prova \
      && mkdir githooks && cp "$(trova_githook)" "$(dirname "$(trova_githook)")/ruoli" githooks/ \
      && chmod +x githooks/prepare-commit-msg && git config core.hooksPath githooks \
      && echo a > a && git add -A && git commit -qm base \
      && git switch -qc lato && echo l > l && git add -A \
      && CLAUDECODE=1 CANTIERE_AGENT=devops git commit -qm lato && git switch -q main
    sess="CLAUDECODE=1"; [ "${3:-si}" = no ] && sess="NIENTE=1"
    export "$sess" CANTIERE_AGENT=qa-test GIT_EDITOR=true
    case "$1" in
      amend)        git switch -q lato && git commit -q --amend --no-edit ;;
      amend-m)      git switch -q lato && git commit -q --amend -m "$(git log -1 --format=%B)" ;;
      commit-C)     echo n > n && git add -A && git commit -q -C lato ;;
      commit-c)     echo n > n && git add -A && git commit -q -c lato ;;
      cherry-pick)  git cherry-pick lato ;;
      revert)       git switch -q lato && git revert --no-edit HEAD ;;
      squash)       git merge -q --squash lato && git commit -q --no-edit ;;
      merge-m)      echo n > n && git add -A && CANTIERE_AGENT=devops git commit -qm d \
                      && git merge -q --no-ff -m 'merge' -m 'Cantiere-Agent: devops' lato ;;
      due-firme)    echo n > n && git add -A && git commit -qm 'feat: x' -m 'Cantiere-Agent: devops
Cantiere-Agent: seo
Co-Authored-By: Umano <umano@esempio.invalid>' ;;
      a-mano)       echo n > n && git add -A && git commit -qm 'feat: x' -m 'Cantiere-Agent: orchestrator' ;;
    esac
  ) >/dev/null 2>&1
  val=$(git -C "$R" log -1 HEAD --format='%(trailers:key=Cantiere-Agent,valueonly)' | grep . | sort | uniq -c | awk '{printf "%sx%s ", $2, $1}' | sed 's/ $//')
  [ -n "$val" ] || val=niente
  if [ "$val" = "$2" ]; then printf "  ${V}ok${N}    %-52s %s\n" "$etichetta" "$val"; OK=$((OK+1))
  else printf "  ${X}KO${N}    %-52s atteso %s, ottenuto %s\n" "$etichetta" "$2" "$val"; KO=$((KO+1)); fi
  rm -rf "$T"
}
for o in amend amend-m commit-C commit-c cherry-pick revert squash merge-m due-firme a-mano; do
  eredita_prova "$o" qa-testx1
done
# fuori da Claude Code un amend non tocca la firma che c'e'
eredita_prova amend devopsx1 no

echo; echo "Secondo strato — il corpo del messaggio non si tocca; se la riscrittura fallisce, si nega"
corpo_prova() { # etichetta, python (vero|rotto), atteso
  local T val rc
  T=$(mktemp -d)
  ( unset CLAUDECODE CANTIERE_AGENT; git init -q -b main "$T/r" && cd "$T/r" && git config user.email p@p.invalid \
    && git config user.name p && mkdir githooks && cp "$(trova_githook)" "$(dirname "$(trova_githook)")/ruoli" githooks/ \
    && chmod +x githooks/prepare-commit-msg && git config core.hooksPath githooks && echo a > a && git add -A \
    && mkdir "$T/bin" && printf '#!/bin/sh\nexit 1\n' > "$T/bin/python3" && chmod +x "$T/bin/python3" ) >/dev/null 2>&1
  (
    cd "$T/r"; [ "$2" = rotto ] && PATH="$T/bin:$PATH"
    env -u CLAUDECODE CLAUDECODE=1 CANTIERE_AGENT=qa-test PATH="$PATH" git commit -q -m 'docs: esempio' \
      -m 'Esempio di trailer:
Cantiere-Agent: devops
va in fondo al messaggio.' -m 'Cantiere-Agent: devops'
  ) >/dev/null 2>&1; rc=$?
  if [ "$rc" -ne 0 ] && ! git -C "$T/r" rev-parse -q --verify HEAD >/dev/null 2>&1; then val=negato
  else
    val="corpo:$(git -C "$T/r" log -1 --format=%b | sed '/^$/q' | grep -c '^Cantiere-Agent: devops$') firma:$(git -C "$T/r" log -1 --format='%(trailers:key=Cantiere-Agent,valueonly)' | grep . | tr '\n' ',')"
  fi
  if [ "$val" = "$3" ]; then printf "  ${V}ok${N}    %-52s %s\n" "$1" "$val"; OK=$((OK+1))
  else printf "  ${X}KO${N}    %-52s atteso %s, ottenuto %s\n" "$1" "$3" "$val"; KO=$((KO+1)); fi
  rm -rf "$T"
}
corpo_prova 'riga del corpo «Cantiere-Agent:» resta'       vero  'corpo:1 firma:qa-test,'
corpo_prova 'python3 in errore: commit negato'           rotto negato

echo; echo "Secondo strato — solo i trailer riconosciuti da git (collaudo di ownconsent-www #77)"
# L'ultimo paragrafo e' prosa con una riga che comincia per «Cantiere-Agent:»: per
# `git interpret-trailers --parse` non e' un blocco di trailer. In sessione la riga
# spariva; fuori da Claude Code faceva uscire l'hook senza firmare.
trailer_prova() { # etichetta, CLAUDECODE(si|no), scenario (prosa|amend), atteso
  local T val
  T=$(mktemp -d)
  ( unset CLAUDECODE CANTIERE_AGENT; git init -q -b main "$T/r" && cd "$T/r" && git config user.email p@p.invalid \
    && git config user.name p && mkdir githooks && cp "$(trova_githook)" "$(dirname "$(trova_githook)")/ruoli" githooks/ \
    && chmod +x githooks/prepare-commit-msg && git config core.hooksPath githooks && echo a > a && git add -A
    case "$3" in amend|alias*) CLAUDECODE=1 CANTIERE_AGENT=devops git commit -q -m 'feat: x' -m 'Reviewed-by: Umano <u@e.invalid>' ;; esac
    # review della PR 17: con un alias git restituisce la chiave riscritta
    [ "$3" = alias ] && git config trailer.coauthor.key 'Co-authored-by'
    [ "$3" = alias-nome ] && git config trailer.Cantiere-Agent.key 'Ruolo'
    [ "$2" = si ] && export CLAUDECODE=1
    export CANTIERE_AGENT=qa-test
    case "$3" in
      prosa) git commit -q -m 'docs: esempio' -m 'Nota sul formato della firma.
Cantiere-Agent: ora gestito dal nuovo hook
Il resto del paragrafo e'"'"' prosa.' ;;
      amend|alias*) git commit -q --amend --no-edit ;;
    esac ) >/dev/null 2>&1
  case "$3" in alias*)
    # dal messaggio grezzo: con l'alias configurato anche git log rinominerebbe le chiavi
    val="firme:$(git -C "$T/r" log -1 --format=%B 2>/dev/null | sed -n 's/^Cantiere-Agent: //p' | tr '\n' ',') coautori-cantiere:$(git -C "$T/r" log -1 --format=%B 2>/dev/null | grep -ci '^Co-Authored-By: cantiere-')"
    if [ "$val" = "$4" ]; then printf "  ${V}ok${N}    %-52s %s\n" "$1" "$val"; OK=$((OK+1))
    else printf "  ${X}KO${N}    %-52s atteso %s, ottenuto %s\n" "$1" "$4" "$val"; KO=$((KO+1)); fi
    rm -rf "$T"; return ;;
  esac
  val="prosa:$(git -C "$T/r" log -1 --format=%B 2>/dev/null | grep -c '^Cantiere-Agent: ora gestito dal nuovo hook$') firma:$(git -C "$T/r" log -1 --format='%(trailers:key=Cantiere-Agent,valueonly)' 2>/dev/null | grep . | tr '\n' ',')"
  if [ "$val" = "$4" ]; then printf "  ${V}ok${N}    %-52s %s\n" "$1" "$val"; OK=$((OK+1))
  else printf "  ${X}KO${N}    %-52s atteso %s, ottenuto %s\n" "$1" "$4" "$val"; KO=$((KO+1)); fi
  rm -rf "$T"
}
trailer_prova 'in sessione: prosa «Cantiere-Agent:» in fondo resta' si prosa 'prosa:1 firma:qa-test,'
trailer_prova 'fuori: la prosa non ferma la firma'               no prosa 'prosa:1 firma:qa-test,'
trailer_prova 'in sessione: amend, firma vera sostituita'        si amend 'prosa:0 firma:qa-test,'
trailer_prova 'fuori: amend, firma vera non duplicata'           no amend 'prosa:0 firma:devops,'
trailer_prova 'amend con alias trailer.coauthor.key'             si alias 'firme:qa-test, coautori-cantiere:1'
trailer_prova 'amend con alias che rinomina Cantiere-Agent'      si alias-nome 'firme:qa-test, coautori-cantiere:1'

echo; echo "Secondo strato — la firma va dove git la legge: prima delle forbici, dentro il blocco dei trailer"
inserisci_prova() { # etichetta, scenario, atteso
  local T val
  T=$(mktemp -d)
  ( unset CLAUDECODE CANTIERE_AGENT; git init -q -b main "$T/r" && cd "$T/r" && git config user.email p@p.invalid \
    && git config user.name p && mkdir githooks && cp "$(trova_githook)" "$(dirname "$(trova_githook)")/ruoli" githooks/ \
    && chmod +x githooks/prepare-commit-msg && git config core.hooksPath githooks && echo a > a && git add -A
    [ "$2" = crlf ] && sed -i 's/$/\r/' githooks/ruoli
    [ "$2" = spazio ] && sed -i 's/$/ /; s/^qa-test/\t&/' githooks/ruoli
    [ "$2" = amend-v ] && CLAUDECODE=1 CANTIERE_AGENT=devops git commit -qm base
    export CLAUDECODE=1 CANTIERE_AGENT=qa-test
    case "$2" in
      v)        GIT_EDITOR='sed -i 1s/^/titolo/' git commit -q -v ;;
      verbose)  GIT_EDITOR='sed -i 1s/^/titolo/' git -c commit.verbose=true commit -q ;;
      scissors) GIT_EDITOR='sed -i 1s/^/titolo/' git -c commit.cleanup=scissors commit -q ;;
      amend-v)  GIT_EDITOR=true git commit -q --amend -v ;;
      umano)    git commit -qm 'feat: y' -m 'Co-Authored-By: Umano <u@e.invalid>' ;;
      crlf|spazio) git commit -qm 'feat: y' ;;
      ripiegato) git commit -qm 'feat: y' -m 'Reviewed-by: A <a@b.invalid>
 su due righe
Refs: x' ;;
      cancelletto) git commit -qm 'fix: x' -m 'Closes
#123' ;;
      hashtag)  printf 'fix: x\n\ncorpo\n\n#hashtag\n' > ../m && git commit -q -F ../m ;;
      conflitto) CANTIERE_AGENT=devops git commit -qm base && git switch -qc lato && echo l > a && CANTIERE_AGENT=devops git commit -qam lato \
                 && git switch -q main && echo m > a && CANTIERE_AGENT=devops git commit -qam main2 \
                 && { git merge -q lato; echo r > a; git add -A; git commit -q --no-edit; } ;;
    esac ) >/dev/null 2>&1
  case "$2" in cancelletto|hashtag|conflitto)
    # la riga con # deve restare nel corpo, PRIMA della firma
    val="firma:$(git -C "$T/r" log -1 --format='%(trailers:key=Cantiere-Agent,valueonly)' 2>/dev/null | grep . | tr '\n' ',') cancelletto-prima-della-firma:$(git -C "$T/r" log -1 --format=%B | awk '/^#/{c=NR} /^Cantiere-Agent:/{f=NR} END{print (c && f && c<f) ? "si" : "no"}')"
    if [ "$val" = "$3" ]; then printf "  ${V}ok${N}    %-52s %s\n" "$1" "$val"; OK=$((OK+1))
    else printf "  ${X}KO${N}    %-52s atteso %s, ottenuto %s\n" "$1" "$3" "$val"; KO=$((KO+1)); fi
    rm -rf "$T"; return ;;
  esac
  val="firma:$(git -C "$T/r" log -1 --format='%(trailers:key=Cantiere-Agent,valueonly)' 2>/dev/null | grep . | tr '\n' ',')"
  [ "$2" = ripiegato ] && val="$val refs:$(git -C "$T/r" log -1 --format='%(trailers:key=Refs,valueonly)' | grep -c '^x$')"
  [ "$2" = umano ] && val="$val umano:$(git -C "$T/r" log -1 --format='%(trailers:key=Co-Authored-By,valueonly)' | grep -c '^Umano ')"
  if [ "$val" = "$3" ]; then printf "  ${V}ok${N}    %-52s %s\n" "$1" "$val"; OK=$((OK+1))
  else printf "  ${X}KO${N}    %-52s atteso %s, ottenuto %s\n" "$1" "$3" "$val"; KO=$((KO+1)); fi
  rm -rf "$T"
}
inserisci_prova 'git commit -v'                                v        'firma:qa-test,'
inserisci_prova 'commit.verbose=true'                          verbose  'firma:qa-test,'
inserisci_prova 'commit.cleanup=scissors'                      scissors 'firma:qa-test,'
inserisci_prova '--amend -v su un commit firmato devops'       amend-v  'firma:qa-test,'
inserisci_prova 'il Co-Authored-By di una persona resta trailer' umano  'firma:qa-test, umano:1'
inserisci_prova 'trailer ripiegato su due righe: resta trailer'  ripiegato 'firma:qa-test, refs:1'
inserisci_prova 'githooks/ruoli con fine riga CRLF'            crlf     'firma:qa-test,'
inserisci_prova 'githooks/ruoli con spazi in testa e in coda'  spazio   'firma:qa-test,'
inserisci_prova '-m con una riga che comincia con #'            cancelletto 'firma:qa-test, cancelletto-prima-della-firma:si'
inserisci_prova '-F con un #hashtag finale'                    hashtag     'firma:qa-test, cancelletto-prima-della-firma:si'
inserisci_prova 'merge con conflitto e blocco # Conflicts:'    conflitto   'firma:qa-test, cancelletto-prima-della-firma:si'

echo; echo "Secondo strato — un rebase sposta commit, non ne crea: le firme restano"
rebase_prova() { # etichetta, forma, atteso
  local T val
  T=$(mktemp -d)
  ( unset CLAUDECODE CANTIERE_AGENT; git init -q -b main "$T/r" && cd "$T/r" && git config user.email p@p.invalid \
    && git config user.name p && mkdir githooks && cp "$(trova_githook)" "$(dirname "$(trova_githook)")/ruoli" githooks/ \
    && chmod +x githooks/prepare-commit-msg && git config core.hooksPath githooks
    export CLAUDECODE=1 CANTIERE_AGENT=devops
    echo a > a && git add -A && git commit -qm base && git switch -qc lato
    for n in 1 2; do echo "$n" > "l$n"; git add -A; git commit -qm "lato $n"; done
    git switch -q main && echo m > m && git add -A && git commit -qm main2
    [ "$2" = conflitto ] && { echo c > l1; git add -A; git commit -qm scontro; }
    git switch -q lato
    export CANTIERE_AGENT=qa-test GIT_EDITOR=true
    case "$2" in
      semplice)  git rebase -q main ;;
      apply)     git rebase -q --apply main ;;
      pull)      git pull -q --rebase . main ;;
      reword)    GIT_SEQUENCE_EDITOR='sed -i 1s/^pick/reword/' git rebase -q -i main ;;
      squash)    GIT_SEQUENCE_EDITOR='sed -i 2s/^pick/squash/' git rebase -q -i main ;;
      fixup)     GIT_SEQUENCE_EDITOR='sed -i 2s/^pick/fixup/' git rebase -q -i main ;;
      edit)      GIT_SEQUENCE_EDITOR='sed -i 1s/^pick/edit/' git rebase -q -i main; echo x >> l1; git add -A
                 git commit -q --amend --no-edit; git rebase --continue ;;
      conflitto) git rebase -q main; echo r > l1; git add -A; git rebase --continue ;;
    esac ) >/dev/null 2>&1
  if [ -d "$T/r/.git/rebase-merge" ] || [ -d "$T/r/.git/rebase-apply" ] || ! git -C "$T/r" merge-base --is-ancestor main lato; then val=rebase-non-finito
  else val=$(git -C "$T/r" log main..lato --format=%B | sed -n 's/^ *Cantiere-Agent: //p' | sort -u | tr '\n' ',')
       val="${val:-niente}"; fi
  if [ "$val" = "$3" ]; then printf "  ${V}ok${N}    %-52s %s\n" "$1" "$val"; OK=$((OK+1))
  else printf "  ${X}KO${N}    %-52s atteso %s, ottenuto %s\n" "$1" "$3" "$val"; KO=$((KO+1)); fi
  rm -rf "$T"
}
rebase_prova 'git rebase main (backend merge)'           semplice  'devops,'
rebase_prova 'git rebase --apply main'                   apply     'devops,'
rebase_prova 'git pull --rebase'                         pull      'devops,'
rebase_prova 'rebase -i con reword'                      reword    'devops,'
rebase_prova 'rebase -i con squash'                      squash    'devops,'
rebase_prova 'rebase -i con fixup'                       fixup     'devops,'
rebase_prova 'rebase -i con edit e commit --amend'       edit      'devops,'
rebase_prova 'rebase con conflitto e --continue'         conflitto 'devops,'

echo; echo "Secondo strato — il diniego dice a una persona cosa fare (! ha CLAUDECODE=1)"
T=$(mktemp -d); ( unset CLAUDECODE CANTIERE_AGENT; git init -q -b main "$T" && cd "$T" && git config user.email p@p.invalid \
  && git config user.name p && mkdir githooks && cp "$(trova_githook)" "$(dirname "$(trova_githook)")/ruoli" githooks/ \
  && chmod +x githooks/prepare-commit-msg && git config core.hooksPath githooks && echo a > a && git add -A ) >/dev/null 2>&1
out=$(env -u CANTIERE_AGENT CLAUDECODE=1 git -C "$T" commit -qm x 2>&1)
case "$out" in
  *"COMMIT NEGATO"*"Se sei una persona, committa da un terminale fuori da Claude Code: anche i comandi dati con ! hanno CLAUDECODE=1"*"non si scrive a mano"*)
     printf "  ${V}ok${N}    %-52s %s\n" "senza ruolo: il messaggio nomina il caso del !" "testo presente"; OK=$((OK+1)) ;;
  *) printf "  ${X}KO${N}    %-52s %s\n" "senza ruolo: il messaggio nomina il caso del !" "testo assente"; KO=$((KO+1)) ;;
esac
rm -rf "$T"

# review della PR 17: in sessione un rebase vero senza ruolo si ferma al primo commit
# riapplicato e resta a meta' (limite noto). Il diniego deve dire come uscirne.
T=$(mktemp -d); ( unset CLAUDECODE CANTIERE_AGENT; git init -q -b main "$T" && cd "$T" && git config user.email p@p.invalid \
  && git config user.name p && mkdir githooks && cp "$(trova_githook)" "$(dirname "$(trova_githook)")/ruoli" githooks/ \
  && chmod +x githooks/prepare-commit-msg && git config core.hooksPath githooks && echo a > a && git add -A && git commit -qm base \
  && git switch -qc lato && echo l > l && git add -A && git commit -qm lato \
  && git switch -q main && echo m > m && git add -A && git commit -qm main2 && git switch -q lato ) >/dev/null 2>&1
out=$(env -u CANTIERE_AGENT CLAUDECODE=1 git -C "$T" rebase main 2>&1)
case "$out" in
  *"COMMIT NEGATO"*"C'e' un rebase in corso: per annullarlo, git rebase --abort. Se sei una persona, rifallo da un terminale fuori da Claude Code."*)
     if [ -d "$T/.git/rebase-merge" ]; then printf "  ${V}ok${N}    %-52s %s\n" "rebase senza ruolo: negato, dice git rebase --abort" "testo presente"; OK=$((OK+1))
     else printf "  ${X}KO${N}    %-52s %s\n" "rebase senza ruolo: negato, dice git rebase --abort" "il rebase non e' fermo"; KO=$((KO+1)); fi ;;
  *) printf "  ${X}KO${N}    %-52s %s\n" "rebase senza ruolo: negato, dice git rebase --abort" "testo assente"; KO=$((KO+1)) ;;
esac
out=$(env -u CANTIERE_AGENT CLAUDECODE=1 git -C "$T" rebase --abort 2>&1; echo n > "$T/n"; git -C "$T" add -A; env -u CANTIERE_AGENT CLAUDECODE=1 git -C "$T" commit -qm x 2>&1)
case "$out" in
  *"rebase in corso"*) printf "  ${X}KO${N}    %-52s %s\n" "commit negato senza rebase: non lo nomina" "testo presente"; KO=$((KO+1)) ;;
  *"COMMIT NEGATO"*)   printf "  ${V}ok${N}    %-52s %s\n" "commit negato senza rebase: non lo nomina" "testo assente"; OK=$((OK+1)) ;;
  *) printf "  ${X}KO${N}    %-52s %s\n" "commit negato senza rebase: non lo nomina" "nessun diniego"; KO=$((KO+1)) ;;
esac
rm -rf "$T"

echo; echo "Avviso di main indietro — SessionStart, senza modificare niente"
# "Non modifica niente": stesso commit su main, stesso ramo, nessun file tracciato
# toccato. La foto di journal-stato scrive in .work/, che e' scratch e c'era gia'.
fermo() { printf '%s %s %s' "$(git -C "$1" rev-parse main)" "$(git -C "$1" symbolic-ref --short HEAD)" \
          "$(git -C "$1" status --porcelain --untracked-files=no | wc -l | tr -d ' ')"; }
sessione_prova() { # etichetta, scenario, atteso: avviso-indietro | avviso-fallito | avviso-scaduto | silenzio
  local T out esito prima dopo dove
  T=$(mktemp -d)
  (
    export -n CLAUDECODE CANTIERE_AGENT 2>/dev/null; unset CLAUDECODE CANTIERE_AGENT
    git init -q --bare -b main "$T/origin.git"
    git clone -q "$T/origin.git" "$T/altro" 2>/dev/null && cd "$T/altro" \
      && git config user.email t@t.invalid && git config user.name T \
      && git switch -qc main 2>/dev/null; echo a > a && git add -A && git commit -qm base && git push -q origin main
    git clone -q "$T/origin.git" "$T/principale" && cd "$T/principale" \
      && git config user.email t@t.invalid && git config user.name T
    case "$2" in
      allineato) : ;;
      *) cd "$T/altro" && echo b > b && git add -A && git commit -qm due && echo c > c && git add -A \
           && git commit -qm tre && git push -q origin main ;;
    esac
    cd "$T/principale"
    case "$2" in
      fetch-fallito)  git remote set-url origin "$T/non-esiste.git" ;;
      fetch-scaduto)  printf '#!/bin/sh\nsleep 20\n' > "$T/ssh-lento"; chmod +x "$T/ssh-lento"
                      git remote set-url origin 'ssh://git@cantiere.invalid/x.git' ;;
      # main (indietro) sta in una worktree collegata; il principale e' su un altro ramo
      worktree)       git switch -qc altro && git worktree add -q "$T/wt" main ;;
      altro-ramo)     git switch -qc lotto/x ;;
      senza-timeout)  : ;;
    esac
  ) >/dev/null 2>&1
  dove="$T/principale"; [ "$2" = worktree ] && dove="$T/wt"
  prima=$(fermo "$T/principale")
  if [ "$2" = senza-timeout ]; then
    out=$(cd "$dove" && echo '{"session_id":"PROVA"}' | env -u CLAUDECODE CANTIERE_TIMEOUT_CMD=timeout-che-non-esiste PATH="$(dirname "$(command -v git)"):$(dirname "$(command -v python3)"):/bin" bash "$H/session-start.sh" 2>/dev/null)
  elif [ "$2" = fetch-scaduto ]; then
    out=$(cd "$dove" && echo '{"session_id":"PROVA"}' | env -u CLAUDECODE GIT_SSH_COMMAND="$T/ssh-lento" CANTIERE_FETCH_LIMITE=1 bash "$H/session-start.sh" 2>/dev/null)
  else
    out=$(cd "$dove" && echo '{"session_id":"PROVA"}' | env -u CLAUDECODE bash "$H/session-start.sh" 2>/dev/null)
  fi
  dopo=$(fermo "$T/principale")
  case "$out" in
    *"indietro di 2 commit rispetto a origin/main"*"git pull --ff-only"*) esito=avviso-indietro ;;
    *"il fetch di origin/main e' scaduto dopo 1 s"*"git pull --ff-only"*) esito=avviso-scaduto ;;
    *"manca il comando timeout"*"git pull --ff-only"*)                    esito=avviso-senza-timeout ;;
    *"il fetch di origin/main e' fallito"*"git pull --ff-only"*)          esito=avviso-fallito ;;
    *ATTENZIONE*)                                                         esito=avviso-diverso ;;
    *"Cantiere attivo."*)                                                 esito=silenzio ;;
    *)                                                                    esito=nessuna-uscita ;;
  esac
  [ "$prima" = "$dopo" ] || esito="$esito+MODIFICATO"
  if [ "$esito" = "$3" ]; then printf "  ${V}ok${N}    %-52s %s\n" "$1" "$esito"; OK=$((OK+1))
  else printf "  ${X}KO${N}    %-52s atteso %s, ottenuto %s\n" "$1" "$3" "$esito"; KO=$((KO+1)); fi
  rm -rf "$T"
}
sessione_prova 'main indietro di 2 commit'               indietro       avviso-indietro
sessione_prova 'main allineato'                          allineato      silenzio
sessione_prova 'fetch fallito: lo dice'                  fetch-fallito  avviso-fallito
sessione_prova 'fetch scaduto al limite: lo dice'       fetch-scaduto  avviso-scaduto
sessione_prova 'manca timeout: lo dice, non «rete»'       senza-timeout  avviso-senza-timeout
sessione_prova 'main indietro, ma in una worktree collegata' worktree     silenzio
sessione_prova 'checkout principale su un altro ramo'    altro-ramo     silenzio

echo
if [ "$KO" -eq 0 ]; then
  printf "${V}%d verifiche superate, 0 fallite.${N} I gate rispondono.\n\n" "$OK"
else
  printf "${X}%d fallite${N} su %d. Un gate che credi attivo e non lo è è peggio di nessun gate.\n\n" "$KO" "$((OK+KO))"
  exit 1
fi
