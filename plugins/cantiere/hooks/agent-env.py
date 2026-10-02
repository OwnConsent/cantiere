#!/usr/bin/env python3
"""PreToolUse su Bash. Dice al git hook chi sta lanciando il comando.

Il payload di PreToolUse porta `agent_type` quando la chiamata viene da un
subagente, e non lo porta quando viene dal filo principale. Qui lo si legge e
si antepone al comando `readonly CANTIERE_AGENT=<ruolo>; export CANTIERE_AGENT;`
(fino al 02/10 un semplice export, e solo sui comandi git): la variabile viaggia
con il processo, qualunque sia la cartella in cui il comando va a finire, e
githooks/prepare-commit-msg la legge.

Sostituisce il marcatore su file del 13-19/09, che era condiviso fra tutte le
worktree dello stesso repository: due sessioni in parallelo si sovrascrivevano
la firma a vicenda, e ogni SubagentStop di un agente annidato la riazzerava a
«orchestrator» (misurato il 20/09 con diagnostica-firma.sh).

Tre vincoli, tutti documentati:
- si restituisce `updatedInput` SENZA `permissionDecision`: il comando riscritto
  passa per la valutazione normale dei permessi, niente viene approvato in piu';
- deve essere l'UNICO hook che riscrive l'input di Bash: con due, vince l'ultimo
  a finire e l'ordine non e' deterministico;
- si riscrive OGNI comando Bash (dal 02/10; prima solo quelli che nominavano git):
  un commit puo' nascere da uno script, da `npm version`, da `make release`, e
  senza la variabile il git hook lo negava.

Fuori da Claude Code la variabile non esiste, quindi un commit fatto a mano da
una persona resta senza firma — ed e' giusto cosi'.

01/10 — la firma viene dal payload, mai dall'autodichiarazione (decisione di
Andrea). Fino a oggi un comando che conteneva gia' `CANTIERE_AGENT=` passava
senza riscrittura, qualunque valore portasse: un subagente qa-test che scriveva
`CANTIERE_AGENT=orchestrator git commit` firmava da orchestrator, e
`CANTIERE_AGENT= git commit` usciva senza firma. Misurato passando i payload
all'hook: le forme `git commit -m`, `git -C <dir> commit`, `cd <dir> && git
commit`, heredoc, `bash -c "git commit"` e `git merge` venivano riscritte tutte;
non riscritte solo quella con la variabile gia' nel comando e lo script che non
nomina git. Ora:
- un CANTIERE_AGENT esplicito e' ammesso solo se coincide col ruolo del payload;
  se lo svuota, lo toglie (unset, env -u) o lo forza a un altro valore: negato;
- un `git commit` o `git merge` da un agente che non e' un ruolo di cantiere
  (Explore, general-purpose, ...) e' negato, e il messaggio nomina il tipo.
L'elenco dei ruoli e' la cartella agents/ del plugin, non una copia.

02/10 — correzioni dalla review della PR: il corpo di un heredoc si toglie, la
riga che lo apre no (li' un ruolo forzato passava); il prefisso di un altro
plugin non vale come ruolo di cantiere; la manomissione si cerca solo nei comandi
che creano un commit, non in ogni comando che nomina git.

02/10 — solo `cantiere:<ruolo>` (decisione di Andrea). Un agent_type senza
prefisso e' negato come un agente fuori elenco, anche se il nome e' quello di un
ruolo: un agente locale del progetto chiamato `frontend` non deve firmare da
frontend. Misura: nei transcript di ownconsent-www fino al 25/09, con il plugin
caricato, 67 chiamate su 67 ai subagenti di cantiere portano `cantiere:<ruolo>`.
La documentazione non lo garantisce: «You can use just the agent name if no
plugin provides it, but must use the scoped form when ambiguous»
(code.claude.com/docs/en/sub-agents), e agent_type e' «custom agent name, or
plugin-scoped name like "my-plugin:reviewer"» (code.claude.com/docs/en/hooks).
Per questo il diniego riporta l'agent_type ricevuto: se una versione futura di
Claude Code cambia formato, si vede subito. Il filo principale, senza
agent_type, resta orchestrator.

02/10 — seconda review. La manomissione cercata solo dopo aver riconosciuto
`git commit` lasciava passare `CANTIERE_AGENT=orchestrator git "commit"` e
`... git -C "/tmp/a b" commit`: ora si cerca in ogni comando che nomina git,
fuori da virgolette e heredoc. Il verbo si riconosce fuori dalle virgolette e
senza trattino dopo: `git merge-base` e `grep "git commit"` da un agente non di
cantiere erano negati. -am, -F, --message= e -m attaccato sono prosa come -m.

CONFINE (decisione di Andrea). Questo hook e' un parser parziale della shell e
non sara' mai completo. Un agente che scrive uno script contenente
`CANTIERE_AGENT=<ruolo valido> git commit` e lo esegue falsifica la firma: qui
non si vede, e il git hook accetta il ruolo perche' e' valido. La firma protegge
da errore e dimenticanza, non da un agente che vuole falsificarla.
Regola per le review: un finding sul parser si corregge solo se apre una
falsificazione con un comando diretto o se blocca lavoro legittimo. Il resto va
nei limiti noti.

02/10 — terza review: la variabile diventa NON RIASSEGNABILE. Riconoscere la
manomissione nel testo del comando continuava a perdere forme
(`ls -m;CANTIERE_AGENT=x git commit`, `export "CANTIERE_AGENT=x"`). Ora il
prefisso e' `readonly ...; export ...`. Misurato in /bin/bash 5.2.21, la shell
del Bash tool (`/bin/bash -c "source <snapshot> && ... eval ..."`, non posix):
- `CANTIERE_AGENT=x git commit`, `export CANTIERE_AGENT=x`, `export "..."`,
  `declare`, `local`, `unset`, `eval "..."`, `readonly` di nuovo: errore
  «readonly variable», e il git hook vede comunque il ruolo vero;
- `CANTIERE_AGENT=x; git commit` e `(CANTIERE_AGENT=x; ...)`: la shell si ferma
  con uscita 1, nessun commit;
- `export -n CANTIERE_AGENT`: il git hook non vede la variabile e nega.
Fuori dalla stessa shell il readonly non vale, e sono le sole forme che questo
hook cerca ancora nel testo e nega: `env CANTIERE_AGENT=x`, `env -u`,
`bash -c` / `sh -c` con un'assegnazione nella stringa (la shell figlia eredita
il valore, non il readonly) e, dalla quarta review, una shell che legge da stdin
(`... | bash`, `bash <<EOF`) quando il comando nomina la variabile. Tolte perche' non servono piu': le regole sulle
stringhe fra virgolette, su -m/-F come prosa, su unset e sull'assegnazione
nella stessa shell.

Limiti noti: uno script che assegna la variabile e committa (il confine qui
sopra); `eval` o un altro interprete (python, perl) che lancia env o una shell;
una shell diversa da bash non e' stata misurata. Due falsi dinieghi noti e
lasciati: `bash -c 'git commit -m "... CANTIERE_AGENT=x ..."'` (il messaggio
quotato dentro la stringa e' letto come assegnazione) ed `echo git commit` da un
agente fuori elenco (git e commit come argomenti di un altro comando). E questo hook esiste solo se il
plugin e' attivo nella sessione.
"""
import json, os, re, shlex, sys

VAR = "CANTIERE_AGENT"
SHELL = {"sh", "bash", "zsh", "dash", "ksh"}

def ruoli_validi():
    d = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "agents")
    try:
        return {f[:-3] for f in os.listdir(d) if f.endswith(".md")}
    except OSError:
        return set()

def parole(cmd):
    """Il comando spezzato come lo spezza la shell: una stringa fra virgolette e'
    una parola sola, `;`, `&&`, `|` sono parole a se'. Il corpo di un heredoc e'
    testo e si toglie; la riga che lo apre si esegue e resta."""
    cmd = re.sub(r"(<<-?\s*(['\"]?)(\w+)\2[^\n]*)\n.*?\n\s*\3\b", r"\1", cmd, flags=re.S)
    cmd = cmd.replace("\n", " ; ")
    lex = shlex.shlex(cmd, posix=True, punctuation_chars=True)
    lex.whitespace_split = True
    lex.commenters = ""
    try:
        return list(lex)
    except ValueError:            # virgolette non chiuse: si spezza sugli spazi
        return cmd.split()

def esamina(cmd, ruolo, livello=0, nomina=False):
    """(motivo, crea): il motivo di un diniego, se il comando porta la variabile
    fuori dal readonly con env o con una shell figlia; e se crea un commit."""
    motivo, crea = None, False
    p = parole(cmd)
    for i, parola in enumerate(p):
        coda = []
        for q in p[i + 1:]:
            if q and not q.strip(";&|()"):
                break
            coda.append(q)
        nome = parola.rsplit("/", 1)[-1]
        if nome == "env":
            for k, a in enumerate(coda):
                if a.startswith(VAR + "=") and a[len(VAR) + 1:] != ruolo:
                    motivo = f"env assegna {VAR}=«{a[len(VAR) + 1:]}»"
                if a in ("-u" + VAR, "--unset=" + VAR) or \
                   (a in ("-u", "--unset") and coda[k + 1:k + 2] == [VAR]):
                    motivo = f"env toglie {VAR}"
        elif nome in SHELL:
            # una shell che legge i comandi da stdin (`... | bash`, `bash <<EOF`):
            # non si guarda dentro, si nega se il comando nomina la variabile
            if nomina and (p[i - 1:i] in (["|"], ["|&"]) and i > 0
                           or any(a.startswith("<<") for a in coda)):
                motivo = f"una shell figlia ({nome}) legge da stdin un testo che nomina {VAR}"
            for k, a in enumerate(coda[:-1]):
                if re.fullmatch(r"-[A-Za-z]*c", a):
                    dentro = coda[k + 1]
                    for m in re.finditer(r"(?<![\w$])" + VAR + r"=([^\s;&|)]*)", dentro):
                        if m.group(1).strip("\"'") != ruolo:
                            motivo = f"una shell figlia ({nome} -c) assegna {VAR}"
                    if livello < 3:
                        m2, c2 = esamina(dentro, ruolo, livello + 1, nomina)
                        motivo, crea = motivo or m2, crea or c2
                    break
        elif nome == "git":
            k = 0
            while k < len(coda) and coda[k].startswith("-"):
                k += 2 if coda[k] in ("-C", "-c") else 1
            if coda[k:k + 1] in (["commit"], ["merge"]):
                crea = True
    return motivo, crea

def main():
    try:
        d = json.load(sys.stdin)
    except Exception:
        sys.exit(0)
    ti = d.get("tool_input") or {}
    cmd = ti.get("command")
    if not isinstance(cmd, str) or not cmd.strip():
        sys.exit(0)
    tipo = (d.get("agent_type") or "").strip()
    # Solo `cantiere:<ruolo>` e' un ruolo di cantiere: ne' `altro:qa-test` ne' un
    # `qa-test` senza prefisso. A chi non lo e' non si inietta mai un nome che sta
    # nell'elenco: il secondo strato lo accetterebbe.
    spazio, _, nome = tipo.rpartition(":")
    if not tipo:
        ruolo = "orchestrator"
    elif spazio == "cantiere":
        ruolo = nome
    else:
        ruolo = "sconosciuto" if (spazio or nome in ruoli_validi()) else nome
    di_cantiere = not tipo or spazio == "cantiere"
    # solo caratteri sicuri in un nome di ruolo: nessuna iniezione nella shell
    if not re.fullmatch(r"[A-Za-z0-9._-]{1,64}", ruolo):
        ruolo = "sconosciuto"

    motivo, crea = esamina(cmd, ruolo, nomina=VAR in cmd)
    if motivo:
        print(f"FIRMA: {motivo}, ma questa chiamata viene da «{ruolo}». La firma dei "
              f"commit viene dalla sessione, non si dichiara a mano: togli {VAR} dal "
              f"comando e rilancialo.", file=sys.stderr)
        sys.exit(2)
    if crea and not (di_cantiere and ruolo in ruoli_validi()):
        print(f"FIRMA: commit negato. agent_type ricevuto: «{tipo}». Firma un commit o "
              f"un merge solo un ruolo di cantiere, nella forma cantiere:<ruolo>. Riporta "
              f"il lavoro a chi ti ha lanciato: committa un ruolo di cantiere.",
              file=sys.stderr)
        sys.exit(2)

    # readonly: nella stessa shell la variabile non si riassegna, non si toglie e
    # non si ridichiara (misure in testa al file)
    nuovo = dict(ti)
    nuovo["command"] = f"readonly {VAR}={ruolo}; export {VAR}; {cmd}"
    json.dump({"hookSpecificOutput": {"hookEventName": "PreToolUse",
                                      "updatedInput": nuovo}}, sys.stdout)
    sys.exit(0)

if __name__ == "__main__":
    main()
