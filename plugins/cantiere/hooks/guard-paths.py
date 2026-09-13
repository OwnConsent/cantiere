#!/usr/bin/env python3
"""Nega i comandi di shell che escono dal perimetro della sessione.

Tre livelli:
  1. credenziali — sempre, non configurabile;
  2. percorsi vietati elencati in .cantiere-deny alla radice del progetto;
  3. qualunque percorso che, risolto, cade fuori dal progetto e fuori dalle
     cartelle di sistema. È questo che chiude il caso `cat ../cmp/.env`.

Exit 2 = negato, il motivo su stderr torna all'agente.
"""
import json, os, re, sys, shlex

def deny(msg):
    sys.stderr.write(
        f"GATE: {msg} — fuori dal perimetro di questa sessione. "
        "Se ti serve davvero, chiedilo a una persona invece di aggirarlo.\n")
    sys.exit(2)

try:
    cmd = json.load(sys.stdin).get("tool_input", {}).get("command", "")
except Exception:
    sys.exit(0)
if not cmd.strip():
    sys.exit(0)

project = os.path.realpath(os.environ.get("CLAUDE_PROJECT_DIR") or os.getcwd())

# 1 — credenziali, qualunque forma
CRED = [
    (r"\.ssh/", "chiavi SSH"), (r"\.aws/", "credenziali AWS"),
    (r"\.kube/config", "kubeconfig"), (r"\.config/gh/", "token GitHub CLI"),
    (r"\.docker/config\.json", "credenziali Docker"), (r"\.gnupg/", "chiavi GPG"),
    (r"\.netrc", "netrc"), (r"\.npmrc", "npmrc"),
    (r"\bid_rsa\b", "chiave privata"), (r"\bid_ed25519\b", "chiave privata"),
]
for pat, what in CRED:
    if re.search(pat, cmd):
        deny(f"accesso a {what}")

# 2 — elenco esplicito del progetto
deny_file = os.path.join(project, ".cantiere-deny")
entries = []
if os.path.isfile(deny_file):
    for line in open(deny_file, encoding="utf-8", errors="replace"):
        line = line.split("#", 1)[0].strip()
        if line:
            entries.append(line)
for e in entries:
    if e.lower() in cmd.lower():
        deny(f"riferimento a '{e}'")

# 3 — percorsi risolti fuori perimetro
SAFE_PREFIXES = ("/usr", "/bin", "/sbin", "/lib", "/lib64", "/etc", "/opt",
                 "/tmp", "/var/tmp", "/dev", "/proc", "/snap", "/run",
                 "/home/linuxbrew", "/nix")
try:
    tokens = shlex.split(cmd, comments=False)
except ValueError:
    tokens = re.split(r"\s+", cmd)

for raw in tokens:
    tok = raw.split("=", 1)[1] if raw.startswith("--") and "=" in raw else raw
    if "://" in tok or not tok:
        continue
    # ".." e "." da soli sono percorsi: senza questo, `find .. -name .env` passa
    looks_like_path = tok.startswith(("/", "~", ".")) or "/" in tok
    if not looks_like_path:
        continue
    expanded = os.path.expanduser(tok)
    resolved = os.path.realpath(expanded if os.path.isabs(expanded)
                                else os.path.join(project, expanded))
    if resolved == project or resolved.startswith(project + os.sep):
        continue
    if resolved.startswith(SAFE_PREFIXES):
        continue
    home = os.path.realpath(os.path.expanduser("~"))
    if resolved == home:
        continue
    deny(f"il percorso '{raw}' porta fuori dal progetto ({resolved})")

sys.exit(0)
