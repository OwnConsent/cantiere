#!/usr/bin/env python3
r"""Nega i comandi di shell che escono dal perimetro della sessione.

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
uscire dal progetto da dentro del codice serve quasi sempre una risalita.

02/10 — heredoc quotati e sostituzioni di comando (misurato passando i payload):
- il corpo di un heredoc con delimitatore quotato (<<'EOF', <<"EOF", <<\EOF) e'
  TESTO: la shell non lo espande. shlex non conosce gli heredoc e lo spezzava in
  parole, cosi' `gh pr create --body-file - <<'EOF'` era negato perche' la
  descrizione citava un percorso fuori dal progetto. Ora quel corpo si toglie prima
  dei livelli 2 e 3. Resta scandito se l'heredoc non e' quotato (li' $(...) si
  esegue) o se sulla riga che lo apre c'e' un interprete (bash, python3, ...):
  allora e' codice;
- --opzione=valore con un'opzione di testo (--body=...) e' testo come la forma
  separata;
- dentro una stringa fra virgolette doppie la shell esegue $(...) e i backtick.
  Il token ha spazi e il livello 3 lo saltava, il livello 4 cerca solo risalite:
  `--body "$(cat /percorso/assoluto/fuori)"` passava. Ora il contenuto di ogni
  sostituzione si scandisce come un comando, ai livelli 2 e 3. Fra apici singoli
  no: la shell non la esegue.

CONFINE. Come agent-env.py, questo hook e' un parser parziale della shell e non
sara' mai completo: un finding sul parser si corregge solo se apre un'uscita con
un comando diretto o se blocca lavoro legittimo. Limiti noti:
- un heredoc quotato che diventa codice piu' tardi: `cat <<'EOF' > x.sh` e poi
  `bash x.sh`, o un interprete su una riga diversa da quella che apre l'heredoc
  (sulla stessa riga, come `cat <<'EOF' | bash`, il corpo resta scandito);
- una risalita ../ citata in prosa resta negata dal livello 4, per scelta;
- un percorso assoluto dentro un corpo di codice (`python3 -c "open('/x/y')"`): il
  token ha spazi e non c'e' risalita;
- le parentesi di $(...) si contano senza guardare le virgolette al loro interno, e
  << dentro una stringa fra virgolette e' letto come heredoc.

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


TESTO = {"-m", "--message", "--body", "-b", "--title", "-t", "--notes", "-d",
         "--description", "--subject"}

INTERPRETE = re.compile(r"(sh|bash|zsh|dash|ksh|python[\d.]*|node|perl|ruby)")
APRE = re.compile(r"(?<!<)<<(?!<)-?\s*(?:(['\"])([\w.-]+)\1|\\([\w.-]+)|([\w.-]+))")


def senza_heredoc_quotati(cmd):
    """Il comando senza il corpo degli heredoc a delimitatore quotato: e' testo che
    la shell non espande. Resta dov'e' se l'heredoc non e' quotato, se sulla riga
    che lo apre c'e' un interprete, o se il delimitatore di chiusura non si trova."""
    righe, fuori, i = cmd.split("\n"), [], 0
    while i < len(righe):
        riga = righe[i]
        fuori.append(riga)
        i += 1
        interprete = any(INTERPRETE.fullmatch(p.rsplit("/", 1)[-1])
                         for p in re.split(r"[\s;|&()]+", riga))
        for m in APRE.finditer(riga):
            delim = m.group(2) or m.group(3) or m.group(4)
            fine = next((k for k in range(i, len(righe)) if righe[k].strip() == delim), None)
            if fine is None:
                break
            if not (m.group(2) or m.group(3)) or interprete:
                fuori.extend(righe[i:fine + 1])
            i = fine + 1
    return "\n".join(fuori)


def sostituzioni(s):
    """Il contenuto di ogni $(...) e di ogni `...` che la shell eseguirebbe: fuori
    dalle virgolette e dentro le doppie, non fra apici singoli."""
    trovate, i, n, singolo, doppio = [], 0, len(s), False, False
    while i < n:
        c = s[i]
        if singolo:
            singolo = c != "'"
        elif c == "\\":
            i += 1
        elif c == "'" and not doppio:
            singolo = True
        elif c == '"':
            doppio = not doppio
        elif c == "$" and s[i + 1:i + 2] == "(":
            j, aperte = i + 2, 1
            while j < n and aperte:
                aperte += {"(": 1, ")": -1}.get(s[j], 0)
                j += 1
            trovate.append(s[i + 2:j - 1] if not aperte else s[i + 2:])
            i = j
            continue
        elif c == "`":
            j = s.find("`", i + 1)
            j = n if j < 0 else j
            trovate.append(s[i + 1:j])
            i = j
        i += 1
    return trovate


def livelli_2_3(cmd, project, voci_deny, home, livello=0):
    testo = senza_heredoc_quotati(cmd)

    # Tokenizzazione, prima di tutto il resto: i livelli 2 e 3 lavorano sugli
    # ARGOMENTI, non sul comando come stringa.
    # shlex con punctuation_chars tratta ; | & < > come token a se' MA rispetta le
    # virgolette: risolve insieme i due falsi positivi visti finora.
    #   13/09  `cd /percorso; cat x` -> senza questo, il token era "/percorso;"
    #   15/09  `grep -E '/^area (site|api)/'` -> spezzare a mano sul "|" rompeva
    #          una regex fra virgolette, shlex falliva e il token diventava "'/^area"
    try:
        lex = shlex.shlex(testo, posix=True, punctuation_chars=True)
        lex.whitespace_split = True
        tokens = list(lex)
    except ValueError:
        tokens = re.split(r"\s+", testo)

    # Argomenti che per definizione sono TESTO: il corpo di un commento, un messaggio
    # di commit, un titolo. Analizzarli come percorsi ha prodotto tre falsi positivi il
    # 13/09 — barre isolate in «150 ms / 1,6 Mbps», una virgola dopo una barra, il
    # corpo di una PR. Il livello 4 continua a scandire TUTTO il comando, quindi una
    # fuga vera dentro un --body resta negata.
    argomenti = []
    salta_prossimo = False
    for raw in tokens:
        if salta_prossimo:
            salta_prossimo = False
            continue
        if raw in TESTO:
            salta_prossimo = True
            continue
        if raw.startswith("--") and raw.split("=", 1)[0] in TESTO:
            continue                      # --body=valore: testo come --body valore
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
    for raw in argomenti:
        if re.search(r"\s", raw):
            continue
        basso = raw.lower()
        for voce, nome in voci_deny:
            if voce.lower() in basso:
                deny(f"riferimento a '{voce}' ({nome})")

    # 3 — token che sono percorsi.
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

    # Le sostituzioni di comando si eseguono anche dentro una stringa fra virgolette
    # doppie o un argomento di testo: il loro contenuto e' un comando.
    if livello < 4:
        for dentro in sostituzioni(testo):
            livelli_2_3(dentro, project, voci_deny, home, livello + 1)


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

    voci_deny = []
    for nome in (".cantiere-deny", ".cantiere-deny.local"):
        deny_file = os.path.join(project, nome)
        if not os.path.isfile(deny_file):
            continue
        for line in open(deny_file, encoding="utf-8", errors="replace"):
            voce = line.split("#", 1)[0].strip()
            if voce:
                voci_deny.append((voce, nome))
    home = os.path.realpath(os.path.expanduser("~"))
    livelli_2_3(cmd, project, voci_deny, home)

    # 4 — risalite ../ ovunque, anche dentro il codice
    for m in re.finditer(r"(?:\.\./)+[\w./\-]*", cmd):
        risalita = m.group(0)
        risolto = os.path.realpath(os.path.join(project, risalita))
        if fuori_perimetro(risolto, project):
            deny(f"la risalita '{risalita}' porta fuori dal progetto ({risolto})")

    sys.exit(0)


if __name__ == "__main__":
    main()
