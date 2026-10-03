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

PRINCIPIO. Quando si allenta un gate, l'allentamento e' un ELENCO CHIUSO di casi
ammessi, mai un elenco di casi pericolosi da escludere. La prima versione della PR
18 toglieva il corpo degli heredoc quotati salvo per gli interpreti noti, e ogni
interprete dimenticato e' diventato un'uscita: `source /dev/stdin <<'EOF'`,
`xargs cat <<'EOF'`, `while read ...; done <<'EOF'`, `uv run - <<'EOF'`, `php`,
`bash<<'EOF'` (review della #18, 02/10).

FAIL-CLOSED. Un hook che va in eccezione esce con un codice che Claude Code tratta
come errore non bloccante: il comando passa. Ogni errore del parser deve diventare
un diniego. Misurato nella seconda review della #18: 1200 `$(` di fila mandavano
percorri in RecursionError, l'hook usciva con 1 e i livelli 2, 3 e 4 non giravano.
Ora la profondita' ha un limite, e main() trasforma in diniego ogni eccezione.

02/10 — heredoc quotati e sostituzioni di comando (misurato passando i payload):
- il corpo di un heredoc con delimitatore quotato (<<'EOF', <<"EOF", <<\EOF) e'
  testo, la shell non lo espande; shlex non conosce gli heredoc e lo spezzava in
  parole, cosi' `gh pr create --body-file - <<'EOF'` era negato perche' la
  descrizione citava un percorso fuori dal progetto. Quel corpo si toglie prima dei
  livelli 2 e 3 SOLO se la riga che apre l'heredoc e' un comando solo, e il comando
  e' nell'elenco: gh, git, tee, cat con redirezione su file. Una voce in piu', per
  la forma piu' usata, `--body "$(cat <<'EOF' ...)"`: cat da solo dentro una $(...),
  ma solo se quella $(...) e' il valore di un'opzione di testo (--body, -m, --title
  e le altre dell'elenco TESTO) di gh o di git, nella forma separata o
  --opzione="...". In ogni altra $(...) decide chi la consuma (`bash -c`, `eval`),
  e lasciarlo decidere sarebbe di nuovo un elenco aperto: li' il corpo resta
  scandito. Valgono anche `git commit -am "$(...)"` (opzioni corte in gruppo che
  finiscono in m), la forma attaccata `-m"$(...)"` e `-m \` con il valore a capo;
- l'elenco si fida del NOME del comando, quindi il corpo non si toglie se quel nome
  puo' essere stato cambiato nello stesso comando: una definizione di funzione
  (`gh() { bash; }`, `function`), un `alias`, o git con un'opzione globale diversa
  da -C (`git -c alias.x=!bash x <<'EOF'`). Si guarda il comando senza i corpi degli
  heredoc quotati e senza il contenuto delle sostituzioni, a ogni livello e in quelli
  che lo contengono;
  Nessun'altra parte della riga ne cambia il destino: con una pipe, un `;`, un `&&`,
  una sostituzione o un altro comando sulla riga il corpo resta scandito, e cosi' in
  ogni caso fuori elenco, come prima;
- << si riconosce solo fuori dalle virgolette e fuori dai commenti: `echo "<<'X'"`
  seguito da comandi veri li faceva sparire come «corpo»;
- --opzione=valore con un'opzione di testo (--body=...) e' testo come la forma
  separata;
- dentro una stringa fra virgolette doppie la shell esegue $(...) e i backtick.
  Il token ha spazi e il livello 3 lo saltava, il livello 4 cerca solo risalite:
  `--body "$(cat /percorso/assoluto/fuori)"` passava. Ora il contenuto di ogni
  sostituzione si scandisce come un comando, ai livelli 2 e 3. Fra apici singoli
  no: la shell non la esegue. Le parentesi di $(...) si contano rispettando le
  virgolette e saltando i corpi degli heredoc;
- nei corpi di heredoc rimasti e nei commenti le sostituzioni si cercano SENZA
  stato delle virgolette: li' un apostrofo non apre niente, e «l'hook legge
  $(cat /fuori)» nascondeva la sostituzione.

CONFINE. Come agent-env.py, questo hook e' un parser parziale della shell e non
sara' mai completo: un finding sul parser si corregge solo se apre un'uscita con
un comando diretto o se blocca lavoro legittimo. Limiti noti:
- un heredoc quotato che diventa codice piu' tardi: `cat <<'EOF' > x.sh` e poi
  `bash x.sh`; un alias gia' scritto nella configurazione di git o di gh, o una
  loro estensione, che lancia una shell;
- `bash -c "testo con /percorso/assoluto"` ed `eval "..."` SENZA sostituzione: il
  token ha spazi e non si scandisce, come un corpo di codice;
- falsi dinieghi sui comandi fuori elenco: un heredoc quotato che cita un percorso
  fuori dal progetto resta negato se lo riceve un altro comando, se il comando ha
  un prefisso (`VAR=x gh ...`, `/usr/bin/gh`), se sulla riga c'e' una pipe, un
  altro comando o una sostituzione, o se l'heredoc sta in una $(...) non fra
  virgolette. E `$(cat <<'EOF' ...)` come valore di un'opzione che non e'
  nell'elenco TESTO (-F vuole un file), o di gh/git dopo `then`, `do`, `{`. E
  quando nel comando compare `nome()`, `function` o `alias` anche solo in un titolo;
- una risalita ../ citata in prosa resta negata dal livello 4, per scelta;
- un percorso assoluto dentro un corpo di codice (`python3 -c "open('/x/y')"`): il
  token ha spazi e non c'e' risalita;
- un `case` dentro $(...): la `)` del pattern chiude la sostituzione prima del
  dovuto e il resto non si scandisce come suo contenuto;
- una sostituzione citata in un commento si scandisce lo stesso (falso diniego).

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

FINE_PAROLA = " \t\n;|&<>()"


PROFONDITA_MASSIMA = 40


def percorri(s, i=0, chiusa=False, profondita=0):
    """Percorre un testo di shell da i, a un solo livello. Restituisce:
    (fine, sostituzioni, heredoc, commenti, a_capo).
    - sostituzioni: (inizio, fine, contenuto) di ogni $(...) e `...` che la shell
      eseguirebbe, cioe' fuori dalle virgolette o dentro le doppie, non fra apici
      singoli;
    - heredoc: per ognuno la riga che lo apre, il corpo (con la riga di chiusura) e
      se il delimitatore e' quotato. << conta solo fuori da virgolette e commenti, e
      un heredoc senza chiusura non c'e';
    - commenti: da # a fine riga;
    - a_capo: gli a capo fuori dalle virgolette, cioe' quelli che chiudono un comando.
    Con chiusa=True si ferma alla ) che chiude la $( gia' aperta: e' cosi' che le
    parentesi si contano rispettando virgolette e corpi di heredoc."""
    if profondita > PROFONDITA_MASSIMA:
        raise ValueError("troppe sostituzioni di comando annidate")
    n = len(s)
    sost, heredoc, commenti, attesi, a_capo = [], [], [], [], []
    doppio, aperte, riga = False, 0, i
    while i < n:
        c = s[i]
        if c == "\\":
            i += 2
            continue
        if c == "'" and not doppio:
            j = s.find("'", i + 1)
            i = n if j < 0 else j + 1
            continue
        if c == '"':
            doppio = not doppio
        elif c == "$" and s[i + 1:i + 2] == "(":
            j = percorri(s, i + 2, True, profondita + 1)[0]
            sost.append((i, j, s[i + 2:j - 1] if s[j - 1:j] == ")" else s[i + 2:j]))
            i = j
            continue
        elif c == "`":
            j = i + 1
            while j < n and s[j] != "`":
                j += 2 if s[j] == "\\" else 1
            sost.append((i, min(j + 1, n), s[i + 1:j]))
            i = j + 1
            continue
        elif doppio:
            pass
        elif c == "(":
            aperte += 1
        elif c == ")":
            if chiusa and aperte == 0:
                return i + 1, sost, heredoc, commenti, a_capo
            aperte = max(aperte - 1, 0)
        elif c == "#" and (i == 0 or s[i - 1] in FINE_PAROLA):
            j = s.find("\n", i)
            j = n if j < 0 else j
            commenti.append((i, j))
            i = j
            continue
        elif c == "<" and s[i + 1:i + 2] == "<" and s[i + 2:i + 3] != "<" and s[i - 1:i] != "<":
            j = i + 2
            if s[j:j + 1] == "-":
                j += 1
            while j < n and s[j] in " \t":
                j += 1
            delim, quotato = "", False
            while j < n and s[j] not in FINE_PAROLA:
                if s[j] in "'\"":
                    k = s.find(s[j], j + 1)
                    k = n if k < 0 else k
                    delim, quotato, j = delim + s[j + 1:k], True, k + 1
                elif s[j] == "\\":
                    delim, quotato, j = delim + s[j + 1:j + 2], True, j + 2
                else:
                    delim, j = delim + s[j], j + 1
            if delim:
                attesi.append((delim, quotato))
            i = j
            continue
        elif c == "\n":
            a_capo.append(i)
            fine_riga = i          # i avanza a ogni corpo: la riga che li apre finisce qui
            for delim, quotato in attesi:
                pos, fine = i + 1, None
                while pos <= n:
                    k = s.find("\n", pos)
                    k = n if k < 0 else k
                    if s[pos:k].strip() == delim:
                        fine = k
                        break
                    pos = k + 1
                if fine is None:
                    break
                heredoc.append({"riga": (riga, fine_riga), "corpo": (i + 1, min(fine + 1, n)),
                                "quotato": quotato})
                i = fine
            attesi = []
            riga = i + 1
        i += 1
    return n, sost, heredoc, commenti, a_capo


def fine_senza_stato(s, i):
    """La fine di una $( aperta prima di i, contando le parentesi e basta."""
    aperte = 1
    while i < len(s) and aperte:
        aperte += {"(": 1, ")": -1}.get(s[i], 0)
        i += 1
    return i


def sostituzioni_senza_stato(s):
    """Le sostituzioni in un testo dove le virgolette non contano: il corpo di un
    heredoc, un commento. Un apostrofo li' non apre niente."""
    trovate, i = [], 0
    while i < len(s):
        if s[i] == "$" and s[i + 1:i + 2] == "(":
            j = fine_senza_stato(s, i + 2)
            trovate.append(s[i + 2:j - 1] if s[j - 1:j] == ")" else s[i + 2:j])
            i = j
        elif s[i] == "`":
            j = s.find("`", i + 1)
            j = len(s) if j < 0 else j
            trovate.append(s[i + 1:j])
            i = j + 1
        else:
            i += 1
    return trovate


def parole(testo):
    """Il testo spezzato in parole come fa la shell, o None se non si riesce. Una
    barra rovesciata seguita da a capo continua la riga: si toglie prima."""
    try:
        lex = shlex.shlex(testo.replace("\\\n", ""), posix=True, punctuation_chars=True)
        lex.whitespace_split = True
        lex.commenters = ""
        return list(lex)
    except ValueError:
        return None


def separa(t):
    return bool(t) and set(t) <= set(";|&()")


def git_senza_opzioni(resto):
    """Le parole dopo `git`: ammessa solo l'opzione globale -C <cartella>. -c e
    --config-env definiscono alias e comandi, --exec-path cambia cosa gira."""
    while resto[:1] == ["-C"]:
        resto = resto[2:]
    return not resto[:1] or not resto[0].startswith("-")


def riga_di_testo(riga, valore_di_testo):
    """ELENCO CHIUSO: la riga che apre un heredoc quotato ne fa un testo solo se e'
    un comando solo e il comando e' gh, git, tee, o cat con redirezione su file.
    cat da solo vale solo dentro una $(...) che e' il valore di un'opzione di testo
    di gh o git (valore_di_testo). Tutto il resto resta scandito."""
    if "`" in riga or "$(" in riga:
        return False
    p = parole(riga)
    if not p or any(separa(t) for t in p):
        return False
    if p[0] in ("gh", "tee"):
        return True
    if p[0] == "git":
        return git_senza_opzioni(p[1:])
    if p[0] == "cat":
        resto, scrive = p[1:], False
        while len(resto) >= 2 and resto[0] in ("<<", ">", ">>"):
            scrive = scrive or resto[0] != "<<"
            resto = resto[2:]
        return not resto and (scrive or valore_di_testo)
    return False


SEGNO = "__CANTIERE_SOST_%d__"
CORTE_DI_TESTO = tuple(o for o in TESTO if not o.startswith("--"))
DEFINISCE = re.compile(r"[\w.-]+\s*\(\s*\)|\bfunction\b|\balias\b")


def senza(cmd, pezzi, a=0, b=None):
    """cmd[a:b] con ogni pezzo (inizio, fine, sostituto) rimpiazzato."""
    b = len(cmd) if b is None else b
    fuori, da = "", a
    for x, y, con in sorted(pezzi):
        if x < da or y > b:
            continue
        fuori, da = fuori + cmd[da:x] + con, y
    return fuori + cmd[da:b]


def valori_di_testo(cmd, sost, heredoc, commenti, a_capo):
    """Gli indici delle sostituzioni che sono il valore di un'opzione di testo di gh
    o di git: `gh ... --body "$(...)"`, `git commit -m "$(...)"`, --body="$(...)",
    `git commit -am "$(...)"`, -m"$(...)". Si mette un segnaposto al posto di ogni
    sostituzione, si tolgono commenti e corpi di heredoc, si spezza in parole, e si
    guarda il comando che contiene il segnaposto. Nel dubbio, nessuna."""
    if "__CANTIERE_SOST_" in cmd:
        return set()
    pezzi = [(a, b, SEGNO % k) for k, (a, b, _) in enumerate(sost)]
    pezzi += [(h["corpo"][0], h["corpo"][1], "") for h in heredoc]
    pezzi += [(a, b, "") for a, b in commenti]
    pezzi += [(a, a + 1, " ; ") for a in a_capo]
    p = parole(senza(cmd, pezzi))
    if p is None:
        return set()
    trovati = set()
    for k in range(len(sost)):
        segno = SEGNO % k
        dove = [n for n, t in enumerate(p) if segno in t]
        if len(dove) != 1:
            continue
        n = inizio = dove[0]
        while inizio > 0 and not separa(p[inizio - 1]):
            inizio -= 1
        git = p[inizio] == "git"
        if p[inizio] != "gh" and not (git and git_senza_opzioni(p[inizio + 1:n])):
            continue
        prima = p[n - 1] if n > inizio + 1 else ""
        attaccata = p[n].startswith(tuple(o + segno for o in CORTE_DI_TESTO)) or bool(git and re.match(r"-[A-Za-z]*m" + segno, p[n]))
        if prima in TESTO \
           or (p[n].startswith("--") and p[n].split("=", 1)[0] in TESTO) \
           or (git and re.fullmatch(r"-[A-Za-z]*m", prima)) \
           or attaccata:
            trovati.add(k)
    return trovati


def analizza_shell(cmd, valore_di_testo, definito):
    """(testo, sostituzioni, definito): il comando senza i corpi di heredoc che sono
    testo; per ogni sostituzione di comando il contenuto da scandire a sua volta, con
    il suo contesto (se e' il valore di un'opzione di testo di gh o git); e se qui, o
    in un livello che contiene questo, un nome di comando puo' essere stato
    ridefinito: allora nessun corpo si toglie."""
    _, sost, heredoc, commenti, a_capo = percorri(cmd)
    quotati = [(h["corpo"][0], h["corpo"][1], "") for h in heredoc if h["quotato"]]
    definito = definito or bool(DEFINISCE.search(
        senza(cmd, [(a, b, " ") for a, b, _ in sost] + quotati)))
    di_testo = set() if definito else valori_di_testo(cmd, sost, heredoc, commenti, a_capo)
    dentro = [(contenuto, k in di_testo) for k, (_, _, contenuto) in enumerate(sost)]
    tolti = []
    for h in heredoc:
        a, b = h["corpo"]
        stessa_riga = [x for x in heredoc if x["riga"] == h["riga"]]
        riga = senza(cmd, [(x, y, "") for x, y in commenti], *h["riga"])
        if not definito and all(x["quotato"] for x in stessa_riga) and riga_di_testo(riga, valore_di_testo):
            tolti.append((a, b, ""))
        else:
            dentro += [(x, False) for x in sostituzioni_senza_stato(cmd[a:b])]
    for a, b in commenti:
        dentro += [(x, False) for x in sostituzioni_senza_stato(cmd[a:b])]
    return senza(cmd, tolti), dentro, definito


def livelli_2_3(cmd, project, voci_deny, home, livello=0, valore_di_testo=False, definito=False):
    testo, dentro_tutte, definito = analizza_shell(cmd, valore_di_testo, definito)

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
    if dentro_tutte and livello >= 8:
        deny("troppe sostituzioni di comando annidate: non le esamino tutte")
    for dentro, di_testo in dentro_tutte:
        livelli_2_3(dentro, project, voci_deny, home, livello + 1, di_testo, definito)


def esamina(dati):
    cmd = dati.get("tool_input", {}).get("command", "")
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


def main():
    try:
        dati = json.load(sys.stdin)
    except Exception:
        sys.exit(0)
    # FAIL-CLOSED: un'eccezione qui farebbe uscire l'hook con 1, che per Claude Code
    # e' un errore non bloccante. deny() e sys.exit() sollevano SystemExit e passano.
    try:
        esamina(dati)
    except Exception as e:
        deny(f"errore del parser ({type(e).__name__}: {e}): comando non esaminato, quindi negato")


if __name__ == "__main__":
    main()
