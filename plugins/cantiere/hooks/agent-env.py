#!/usr/bin/env python3
"""PreToolUse su Bash. Dice al git hook chi sta lanciando il comando.

Il payload di PreToolUse porta `agent_type` quando la chiamata viene da un
subagente, e non lo porta quando viene dal filo principale. Qui lo si legge e
si antepone al comando `export CANTIERE_AGENT=<ruolo>;`: la variabile viaggia
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
- si riscrive solo se il comando nomina git: nessun motivo di toccare il resto.

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

Limiti, coperti dal secondo strato (il git hook nega un commit senza ruolo
valido): uno script che lancia git senza nominarlo nel comando non viene
riscritto; un'assegnazione nascosta in un heredoc dato in pasto a una shell non
viene vista. E questo hook esiste solo se il plugin e' attivo nella sessione.
"""
import json, os, re, sys

VAR = "CANTIERE_AGENT"
# git, eventuali opzioni globali (-C dir, -c k=v, --no-pager, ...), poi il verbo
CREA_COMMIT = re.compile(
    r"\bgit\b(?:\s+(?:-[Cc]\s+\S+|--?[A-Za-z][\w-]*(?:=\S+)?))*\s+(commit|merge)\b")

def ruoli_validi():
    d = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "agents")
    try:
        return {f[:-3] for f in os.listdir(d) if f.endswith(".md")}
    except OSError:
        return set()

def senza_prosa(cmd):
    """Toglie il testo che non viene eseguito: corpi di heredoc e argomenti
    quotati di -m/--message/--body/--title. Un messaggio di commit che cita la
    variabile non e' un'assegnazione (stessa regola di guard-paths, 23/09)."""
    # del heredoc si toglie solo il CORPO: il resto della riga di apertura la shell
    # lo esegue (`cat <<EOF | CANTIERE_AGENT=x git commit -F -`), e va guardato
    cmd = re.sub(r"(<<-?\s*(['\"]?)(\w+)\2[^\n]*)\n.*?\n\s*\3\b", r"\1", cmd, flags=re.S)
    return re.sub(r"""(?:-m|--message|--body|--title)(?:=|\s+)("(?:\\.|[^"\\])*"|'[^']*')""",
                  " ", cmd)

def manomissione(cmd, ruolo):
    """Restituisce il motivo se il comando svuota, toglie o forza la variabile."""
    testo = senza_prosa(cmd)
    if re.search(r"\bunset\s+(?:-\w+\s+)*" + VAR + r"\b", testo):
        return f"il comando toglie {VAR} con unset"
    if re.search(r"(?:-u\s*|--unset[=\s]\s*)" + VAR + r"\b", testo):
        return f"il comando toglie {VAR} con env -u"
    for m in re.finditer(r"(?<![\w$])" + VAR + r"=(\"[^\"]*\"|'[^']*'|[^\s;&|)]*)", testo):
        valore = m.group(1).strip("\"'")
        if valore != ruolo:
            cosa = f"forza {VAR}=«{valore}»" if valore else f"svuota {VAR}"
            return f"il comando {cosa}, ma questa chiamata viene da «{ruolo}»"
    return None

def nega(motivo):
    print(f"FIRMA: {motivo}. La firma dei commit viene dalla sessione, non si "
          f"dichiara a mano: togli {VAR} dal comando che committa e rilancialo "
          f"(se la variabile compare solo come testo, committa in un comando a parte).",
          file=sys.stderr)
    sys.exit(2)

def main():
    try:
        d = json.load(sys.stdin)
    except Exception:
        sys.exit(0)
    ti = d.get("tool_input") or {}
    cmd = ti.get("command")
    if not isinstance(cmd, str) or not re.search(r"\bgit\b", cmd):
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

    # la manomissione conta solo dove nasce un commit: `git grep "CANTIERE_AGENT="`
    # o `git log -S` nominano la variabile senza firmare niente
    crea = CREA_COMMIT.search(senza_prosa(cmd))
    motivo = manomissione(cmd, ruolo) if crea else None
    if motivo:
        nega(motivo)
    if crea and not (di_cantiere and ruolo in ruoli_validi()):
        print(f"FIRMA: commit negato. agent_type ricevuto: «{tipo}». Firma un commit o "
              f"un merge solo un ruolo di cantiere, nella forma cantiere:<ruolo>. Riporta "
              f"il lavoro a chi ti ha lanciato: committa un ruolo di cantiere.",
              file=sys.stderr)
        sys.exit(2)

    nuovo = dict(ti)
    nuovo["command"] = f"export {VAR}={ruolo}; {cmd}"
    json.dump({"hookSpecificOutput": {"hookEventName": "PreToolUse",
                                      "updatedInput": nuovo}}, sys.stdout)
    sys.exit(0)

if __name__ == "__main__":
    main()
