#!/usr/bin/env bash
# PROVA ubuntu-26.04 — blocchi 1-3: ambiente, coreutils, comportamenti.
# Non si ferma al primo errore: ogni comando stampa il suo output e la sua uscita.
# Lo stesso script gira su ubuntu-24.04 (job prova-2404) per il confronto.
set -u

prova() { # comando, eseguito da bash -o pipefail -c
  local out rc
  out=$(bash -o pipefail -c "$1" 2>&1); rc=$?
  printf '$ %s\n' "$1"
  printf '%s\n' "$out" | sed 's/^/    | /'
  printf '    uscita: %s\n' "$rc"
}

echo "=== BLOCCO 1: ambiente ==="
# ImageOS e ImageVersion sono le variabili dell'immagine: gli stessi valori che la
# preparazione del job stampa come Image e Version.
echo "Image: ${ImageOS:-non impostata}"
echo "Version: ${ImageVersion:-non impostata}"
prova 'grep -E "^(PRETTY_NAME|VERSION_ID)=" /etc/os-release'
prova 'python3 --version'
prova 'readlink -f "$(command -v python3)"'
prova 'bash --version | head -1'
prova 'jq --version'

echo
echo "=== BLOCCO 2: coreutils ==="
for c in stat date od ls mktemp timeout tr head wc; do
  prova "$c --version | head -1"
  prova "readlink -f \"\$(command -v $c)\""
done
echo "--- pacchetti ---"
prova "dpkg-query -W -f='\${Package} \${Version} \${Status}\n' 'coreutils*' 'rust-coreutils*' 'gnu-coreutils*'"
echo "--- verdetto per comando (dalla prima riga di --version) ---"
for c in stat date od ls mktemp timeout tr head wc; do
  riga=$($c --version 2>&1 | head -1)
  case "$riga" in
    *uutils*)          echo "$c: uutils  [$riga]" ;;
    *"GNU coreutils"*) echo "$c: GNU     [$riga]" ;;
    *)                 echo "$c: ?       [$riga]" ;;
  esac
done

echo
echo "=== BLOCCO 3: comportamenti usati dai nostri script ==="
D=$(mktemp -d) && cd "$D" || { echo "mktemp -d o cd falliti: blocco 3 non eseguibile"; exit 0; }
printf 'abcde' > f
prova 'stat -c %s f'
prova 'date -d @0 +%s'
prova "printf 'AB\n' | od -An -tx1"
prova 'd=$(mktemp -d); rc=$?; echo "$d"; [ -d "$d" ] && echo "e una directory, permessi $(stat -c %a "$d")"; rmdir "$d"; exit $rc'
prova 'timeout 1 sleep 2; echo $?'

echo
echo "=== BLOCCO 3b (in piu'): forme usate alla lettera da verifica-gate.sh ==="
chmod 640 f
prova 'stat -c %a f'
prova 'date -Is'
prova 'e=$(mktemp -p "${TMPDIR:-/tmp}" esca-XXXX.js); rc=$?; echo "$e"; rm -f "$e"; exit $rc'
prova "printf 'a\nb\n' | wc -l | tr -d ' '"
cd / && rm -rf "$D"
exit 0
