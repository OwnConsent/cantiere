#!/usr/bin/env bash
# PROVA ubuntu-26.04 — blocco 6: perche' falliscono i tre casi «git non finisce».
# Non corregge nulla e non fa fallire il passo. verifica-gate.sh non viene toccato:
# la controprova gira su una copia del repository fatta sotto $RUNNER_TEMP.
set -u

echo "=== BLOCCO 6a: un link simbolico di nome dormi a sleep ==="
link_prova() { # etichetta, bersaglio del link
  local d t0 t1 rc
  d=$(mktemp -d); ln -s "$2" "$d/dormi"
  echo "--- $1"
  echo "    link: $d/dormi -> $(readlink "$d/dormi")   [reale: $(readlink -f "$d/dormi")]"
  t0=$(date +%s.%N); "$d/dormi" 3 2>"$d/err"; rc=$?; t1=$(date +%s.%N)
  echo "    uscita: $rc"
  echo "    durata: $(awk -v a="$t0" -v b="$t1" 'BEGIN{printf "%.3f", b-a}') s"
  echo "    stderr: $(if [ -s "$d/err" ]; then cat "$d/err"; else echo "(vuoto)"; fi)"
  rm -rf "$d"
}
link_prova 'link a $(command -v sleep)' "$(command -v sleep)"
link_prova 'link a $(readlink -f "$(command -v sleep)")' "$(readlink -f "$(command -v sleep)")"

echo
echo "=== BLOCCO 6b: i tre casi con un finto git che e' uno script (exec sleep 30) ==="
C="$RUNNER_TEMP/copia-blocco-6"; rm -rf "$C"; mkdir -p "$C"
cp -r "$GITHUB_WORKSPACE/plugins" "$GITHUB_WORKSPACE/template" "$C/"
S="$C/plugins/cantiere/hooks/verifica-gate.sh"
# 1) il finto git non passa piu' dal link dormi; 2) il messaggio si stampa anche quando il caso e' ok
sed -i \
  -e 's|^printf .#!/bin/sh\\nexec "%s/bin/dormi" 30\\n. "\$SV" > "\$SV/bin/git"|printf '"'"'#!/bin/sh\\nexec sleep 30\\n'"'"' > "$SV/bin/git"|' \
  -e "/^riporta 'journal-check: git non finisce'/a printf '        messaggio: %s\\\\n' \"\$(head -c 400 \"\$FC/err\")\"" \
  -e "/^riporta 'journal-check: secondo giro, lascia e lo dice'/a printf '        messaggio: %s\\\\n' \"\$(head -c 400 \"\$SV/out\")\"" \
  -e "/^riporta 'guard-tempo: git non finisce'/a printf '        messaggio: %s\\\\n' \"\$(head -c 400 \"\$FC/err\")\"" \
  "$S"
echo "--- differenze della copia rispetto a verifica-gate.sh"
diff "$GITHUB_WORKSPACE/plugins/cantiere/hooks/verifica-gate.sh" "$S"
echo "    (diff: uscita $?)"
echo "python3: $(python3 --version 2>&1)"
P="$RUNNER_TEMP/progetto-prova-blocco-6"; rm -rf "$P"
if mkdir -p "$P" && cd "$P" && git init -q -b main \
   && git config user.email ci@cantiere.invalid && git config user.name ci \
   && printf 'OwnConsent/cmp\n' > .cantiere-deny && echo segnaposto > CLAUDE.md \
   && git add -A && git commit -qm base; then
  CLAUDE_PROJECT_DIR="$P" bash "$S" > "$RUNNER_TEMP/blocco-6.out" 2>&1; rc=$?
  echo "--- i tre casi, dalla suite della copia (uscita della suite: $rc)"
  sed -E 's/\x1b\[[0-9;]*m//g' "$RUNNER_TEMP/blocco-6.out" \
    | grep -A1 -E "journal-check: git non finisce|journal-check: secondo giro|guard-tempo: git non finisce"
  echo "--- tutti i KO della copia"
  sed -E 's/\x1b\[[0-9;]*m//g' "$RUNNER_TEMP/blocco-6.out" | grep -A1 -E '^  KO ' || echo "    nessun KO"
  echo "--- conteggio della copia"
  sed -E 's/\x1b\[[0-9;]*m//g' "$RUNNER_TEMP/blocco-6.out" | grep -E 'verifiche superate|fallite'
else
  echo "preparazione del progetto di prova fallita"
fi
cd /

echo
echo "=== BLOCCO 6c: un GNU coreutils installato a parte ==="
if dpkg-query -W -f='${Package} ${Version} ${Status}\n' gnu-coreutils 2>&1; then
  echo "--- file del pacchetto che si chiamano *sleep"
  trovati=$(dpkg -L gnu-coreutils | grep -E '/[^/]*sleep$')
  echo "${trovati:-    nessuno}"
  for f in $trovati; do
    [ -x "$f" ] && [ ! -d "$f" ] || continue
    echo "\$ $f --version | head -1"
    echo "    | $("$f" --version 2>&1 | head -1)   [reale: $(readlink -f "$f")]"
  done
  echo "--- directory degli eseguibili del pacchetto"
  dpkg -L gnu-coreutils | grep -E '/(bin|libexec)/' | xargs -r -n1 dirname | sort | uniq -c
else
  echo "    pacchetto gnu-coreutils non installato"
fi
for n in gnusleep gsleep; do echo "command -v $n: $(command -v $n || echo "non trovato")"; done
exit 0
