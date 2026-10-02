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
m=re.match(r"export CANTIERE_AGENT=(\S+); ",c); print(m.group(1) if m else "malformato")')
  fi
  if [ "$esito" = "$4" ]; then printf "  ${V}ok${N}    %-52s %s\n" "$1" "$esito"; OK=$((OK+1))
  else printf "  ${X}KO${N}    %-52s atteso %s, ottenuto %s\n" "$1" "$4" "$esito"; KO=$((KO+1)); fi
}

echo; echo "Primo strato — agent-env.py: il ruolo viene dal payload, su ogni forma di comando git"
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
agente_prova 'script che non nomina git (limite noto)' ''                 './scripts/x.sh'                       niente
agente_prova 'il messaggio cita la variabile'          ''                 'git commit -m "fix: CANTIERE_AGENT= vuota"' orchestrator
agente_prova 'heredoc che cita la variabile'           ''                 "git commit -F - <<'EOF'
prima era CANTIERE_AGENT=qa-test a mano
EOF"                                                                                                              orchestrator

echo; echo "Primo strato — la firma non si dichiara a mano"
agente_prova 'ruolo forzato a un altro valore'         'cantiere:qa-test' 'CANTIERE_AGENT=orchestrator git commit -m x' deny
agente_prova 'export di un altro ruolo, poi commit'    ''                 'export CANTIERE_AGENT=qa-test && git commit -m x' deny
agente_prova 'variabile svuotata'                      ''                 'CANTIERE_AGENT= git commit -m x'      deny
agente_prova 'variabile svuotata con le virgolette'    ''                 'CANTIERE_AGENT="" git commit -m x'    deny
agente_prova 'variabile tolta con env -u'              ''                 'env -u CANTIERE_AGENT git commit -m x' deny
agente_prova 'variabile tolta con unset'               ''                 'unset CANTIERE_AGENT; git commit -m x' deny
agente_prova 'forzata dentro bash -c'                  ''                 'bash -c "CANTIERE_AGENT=qa-test git commit -m x"' deny
agente_prova 'forzata su un merge'                     ''                 'CANTIERE_AGENT=devops git merge --no-ff x' deny
agente_prova 'forzata sulla riga che apre un heredoc'   'cantiere:qa-test' "cat <<'EOF' | CANTIERE_AGENT=orchestrator git commit -F -
titolo
EOF"                                                                                                              deny
agente_prova 'git grep della variabile non e manomissione' ''             'git grep -n "CANTIERE_AGENT=" plugins' orchestrator
agente_prova 'git log -S della variabile'              'cantiere:qa-test' 'git log -S"CANTIERE_AGENT=" --oneline' qa-test

echo; echo "Primo strato — chi non e' un ruolo di cantiere non committa"
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
      a-mano)       echo n > n && git add -A && git commit -qm 'feat: x' -m 'Cantiere-Agent: orchestrator' ;;
    esac
  ) >/dev/null 2>&1
  val=$(git -C "$R" log -1 HEAD --format=%B | grep -E '^[[:space:]]*Cantiere-Agent:' | sed 's/^ *Cantiere-Agent: //' | sort | uniq -c | awk '{printf "%sx%s ", $2, $1}' | sed 's/ $//')
  [ -n "$val" ] || val=niente
  if [ "$val" = "$2" ]; then printf "  ${V}ok${N}    %-52s %s\n" "$etichetta" "$val"; OK=$((OK+1))
  else printf "  ${X}KO${N}    %-52s atteso %s, ottenuto %s\n" "$etichetta" "$2" "$val"; KO=$((KO+1)); fi
  rm -rf "$T"
}
for o in amend amend-m commit-C commit-c cherry-pick revert squash merge-m a-mano; do
  eredita_prova "$o" qa-testx1
done
# fuori da Claude Code un amend non tocca la firma che c'e'
eredita_prova amend devopsx1 no

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
