#!/usr/bin/env python3
"""Nega i comandi di shell che escono dal perimetro della sessione.

Quattro livelli:
  1. credenziali — sempre, non configurabile;
  2. percorsi vietati elencati in .cantiere-deny alla radice del progetto;
  3. token che, risolti, cadono fuori dal progetto e fuori dalle cartelle di sistema;
  4. risalite ../ cercate nel comando intero, corpi di codice compresi.

Il livello 3 salta i token che contengono spazi: un corpo di codice (python3 -c,
node -e, uno heredoc) arriva come un unico token pieno di "/" che non sono percorsi
— la divisione intera //, una stringa che inizia per /, una regex. Analizzarlo lì
produce falsi positivi. Il livello 4 recupera ciò che conta davvero, perché per
uscire dal progetto da dentro del codice serve comunque una risalita.

Exit 2 = negato, il motivo su stderr torna all'agente.
"""
import json, os, re, sys, shlex

SAFE_PREFIXES = ("/usr", "/bin", "/sbin", "/lib", "/lib64", "/etc", "/opt",
                 "/tmp", "/var/tmp", "/dev", "/proc", "/snap", "/run",
                 "/home/linuxbrew", "/nix")

CRED = [
    (r"\.ssh/", "chiavi SSH"), (r"\.aws/", "credenziali AWS"),
    (r"\.kube/config", "kubeconfig"), (r"\.config/gh/", "token GitHub CLI"),
    (r"\.docker/config\.json", "credenziali Docker"), (r"\.gnupg/", "chiavi GPG"),
    (r"\.netrc", "netrc"), (r"\.npmrc", "npmrc"),
    (r"\bid_rsa\b", "chiave privata"), (r"\bid_ed25519\b", "chiave privata"),
]


def deny(msg):
    sys.stderr.write(
        f"GATE: {msg} — fuori dal perimetro di questa sessione. "
        "Se ti serve davvero, chiedilo a una persona invece di aggirarlo.\n")
    sys.exit(2)


def fuori_perimetro(risolto, project):
    if risolto == project or risolto.startswith(project + os.sep):
        return False
    if risolto.startswith(SAFE_PREFIXES):
        return False
    return True


def main():
    try:
        cmd = json.load(sys.stdin).get("tool_input", {}).get("command", "")
    except Exception:
        sys.exit(0)
    if not cmd.strip():
        sys.exit(0)

    project = os.path.realpath(os.environ.get("CLAUDE_PROJECT_DIR") or os.getcwd())

    # 1 — credenziali, qualunque forma
    for pat, what in CRED:
        if re.search(pat, cmd):
            deny(f"accesso a {what}")

    # 2 — elenco esplicito del progetto
    deny_file = os.path.join(project, ".cantiere-deny")
    if os.path.isfile(deny_file):
        for line in open(deny_file, encoding="utf-8", errors="replace"):
            voce = line.split("#", 1)[0].strip()
            if voce and voce.lower() in cmd.lower():
                deny(f"riferimento a '{voce}'")

    # 3 — token che sono percorsi
    try:
        tokens = shlex.split(cmd, comments=False)
    except ValueError:
        tokens = re.split(r"\s+", cmd)

    home = os.path.realpath(os.path.expanduser("~"))
    for raw in tokens:
        tok = raw.split("=", 1)[1] if raw.startswith("--") and "=" in raw else raw
        if not tok or "://" in tok:
            continue
        # corpo di codice, non un percorso: se ne occupa il livello 4
        if re.search(r"\s", tok):
            continue
        # ".." e "." da soli sono percorsi: senza questo, `find .. -name .env` passa
        if not (tok.startswith(("/", "~", ".")) or "/" in tok):
            continue
        expanded = os.path.expanduser(tok)
        resolved = os.path.realpath(expanded if os.path.isabs(expanded)
                                    else os.path.join(project, expanded))
        if resolved == home:
            continue
        if fuori_perimetro(resolved, project):
            deny(f"il percorso '{raw}' porta fuori dal progetto ({resolved})")

    # 4 — risalite ../ ovunque, anche dentro il codice
    for m in re.finditer(r"(?:\.\./)+[\w./\-]*", cmd):
        risalita = m.group(0)
        risolto = os.path.realpath(os.path.join(project, risalita))
        if fuori_perimetro(risolto, project):
            deny(f"la risalita '{risalita}' porta fuori dal progetto ({risolto})")

    sys.exit(0)


if __name__ == "__main__":
    main()
