#!/usr/bin/env python3
"""Nega i comandi di shell che escono dal perimetro della sessione.

Quattro livelli:
  1. credenziali — sempre, non configurabile;
  2. percorsi vietati elencati in .cantiere-deny, cercati fra gli argomenti;
  3. token che, risolti, cadono fuori dal progetto e fuori dalle cartelle di sistema,
     e che esistono o potrebbero essere creati;
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
    (r"\bid_rsa\b", "chiave privata"), (r"\bid_ed25519\b", "chiave privata"),
]


# .npmrc e .netrc sono credenziali solo nella home dell'utente: li' stanno i token del
# registry e le password FTP. Un .npmrc DENTRO il progetto e' configurazione normale —
# site/.npmrc contiene only-built-dependencies[]=esbuild — e fino al 21/09 veniva
# bloccato lo stesso, lasciando un agente senza modo di leggere la propria build.
# Si negano quindi le forme che puntano alla home, e ogni token che risolto cade fuori
# dal progetto; quelli dentro il progetto passano.
CRED_HOME = re.compile(r"(~|\$HOME|\$\{HOME\})/\.(npmrc|netrc)\b")
CRED_NOMI = (".npmrc", ".netrc")


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

    m = CRED_HOME.search(cmd)
    if m:
        deny(f"accesso a {m.group(0)} (credenziali dell'utente)")

    # Tokenizzazione, prima di tutto il resto: i livelli 2 e 3 lavorano sugli
    # ARGOMENTI, non sul comando come stringa.
    # shlex con punctuation_chars tratta ; | & < > come token a se' MA rispetta le
    # virgolette: risolve insieme i due falsi positivi visti finora.
    #   13/09  `cd /percorso; cat x` -> senza questo, il token era "/percorso;"
    #   15/09  `grep -E '/^area (site|api)/'` -> spezzare a mano sul "|" rompeva
    #          una regex fra virgolette, shlex falliva e il token diventava "'/^area"
    try:
        lex = shlex.shlex(cmd, posix=True, punctuation_chars=True)
        lex.whitespace_split = True
        tokens = list(lex)
    except ValueError:
        tokens = re.split(r"\s+", cmd)

    # Argomenti che per definizione sono TESTO: il corpo di un commento, un messaggio
    # di commit, un titolo. Analizzarli come percorsi ha prodotto tre falsi positivi il
    # 13/09 — barre isolate in «150 ms / 1,6 Mbps», una virgola dopo una barra, il
    # corpo di una PR. Il livello 4 continua a scandire TUTTO il comando, quindi una
    # fuga vera dentro un --body resta negata.
    TESTO = {"-m", "--message", "--body", "-b", "--title", "-t", "--notes", "-d",
             "--description", "--subject"}

    argomenti = []
    salta_prossimo = False
    for raw in tokens:
        if salta_prossimo:
            salta_prossimo = False
            continue
        if raw in TESTO:
            salta_prossimo = True
            continue
        argomenti.append(raw)

    # 2 — elenco esplicito del progetto, cercato NEGLI ARGOMENTI.
    # .cantiere-deny e' committato e vale per tutti. .cantiere-deny.local NON si
    # committa (sta in .gitignore) e vale solo per la worktree in cui si trova: serve
    # a un lotto che non deve leggere un'area. Il 20/09 L07 doveva scrivere i test
    # «senza leggere site/» e due agenti su cinque l'hanno letto durante un comando
    # operativo: un divieto scritto nel mandato e' una buona intenzione, questo e' un
    # rifiuto.
    #
    # Fino al 23/09 la voce si cercava nel comando INTERO. Tre volte in L14 ha negato
    # una voce di journal e il corpo di una PR che si limitavano a CITARE un percorso
    # vietato: nominare non e' leggere, e un gate che confonde le due cose insegna ad
    # aggirarlo riscrivendo le frasi. Ora si guardano gli argomenti, salvo quelli che
    # contengono spazi — un corpo di codice, un heredoc — di cui si occupa il livello 4.
    voci_deny = []
    for nome in (".cantiere-deny", ".cantiere-deny.local"):
        deny_file = os.path.join(project, nome)
        if not os.path.isfile(deny_file):
            continue
        for line in open(deny_file, encoding="utf-8", errors="replace"):
            voce = line.split("#", 1)[0].strip()
            if voce:
                voci_deny.append((voce, nome))
    for raw in argomenti:
        if re.search(r"\s", raw):
            continue
        basso = raw.lower()
        for voce, nome in voci_deny:
            if voce.lower() in basso:
                deny(f"riferimento a '{voce}' ({nome})")

    # 3 — token che sono percorsi.
    home = os.path.realpath(os.path.expanduser("~"))
    for raw in argomenti:
        tok = raw.split("=", 1)[1] if raw.startswith("--") and "=" in raw else raw
        tok = tok.strip("\"'`),;&|")          # punteggiatura di shell rimasta ai bordi
        if not tok or "://" in tok:
            continue
        # una barra isolata e' prosa, non un argomento di percorso.
        # SOLO barre: includere anche i punti farebbe passare "..", che e' una
        # risalita vera — regressione colta dalla suite il 13/09.
        if set(tok) <= {"/"}:
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
        if os.path.basename(resolved) in CRED_NOMI and fuori_perimetro(resolved, project):
            deny(f"accesso a {raw} (credenziali fuori dal progetto)")
        if resolved == home:
            continue
        if fuori_perimetro(resolved, project):
            # Un percorso fuori progetto fa danno solo se si puo' toccare: o esiste
            # (lo si puo' leggere), o esiste la cartella che lo conterrebbe (ci si
            # puo' scrivere). Un token che non soddisfa nessuna delle due non e' un
            # percorso di questa macchina: e' testo che comincia per "/".
            # Tre falsi positivi osservati il 15/09 — due regex (/FAIL/p, /^area/)
            # e un percorso del runner di GitHub letto dentro un log
            # (/home/runner/work/...), che qui non esiste.
            # Le risalite ../ restano negate SEMPRE dal livello 4, esistenti o no:
            # uscire esplicitamente dal progetto e' sospetto di per se'.
            if os.path.exists(resolved) or os.path.isdir(os.path.dirname(resolved)):
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
