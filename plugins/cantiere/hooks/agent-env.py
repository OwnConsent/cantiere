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
    cmd = re.sub(r"<<-?\s*(['\"]?)(\w+)\1.*?\n\s*\2\b", " ", cmd, flags=re.S)
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
          f"dichiara a mano: togli {VAR} dal comando e rilancialo cosi' com'e'.",
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
    ruolo = tipo.split(":", 1)[-1] if tipo else "orchestrator"
    # solo caratteri sicuri in un nome di ruolo: nessuna iniezione nella shell
    if not re.fullmatch(r"[A-Za-z0-9._-]{1,64}", ruolo):
        ruolo = "sconosciuto"

    motivo = manomissione(cmd, ruolo)
    if motivo:
        nega(motivo)
    if ruolo not in ruoli_validi() and CREA_COMMIT.search(senza_prosa(cmd)):
        print(f"FIRMA: commit negato. L'agente «{tipo or ruolo}» non e' un ruolo di "
              f"cantiere e non puo' firmare un commit o un merge. Riporta il lavoro "
              f"a chi ti ha lanciato: committa un ruolo di cantiere.", file=sys.stderr)
        sys.exit(2)

    nuovo = dict(ti)
    nuovo["command"] = f"export {VAR}={ruolo}; {cmd}"
    json.dump({"hookSpecificOutput": {"hookEventName": "PreToolUse",
                                      "updatedInput": nuovo}}, sys.stdout)
    sys.exit(0)

if __name__ == "__main__":
    main()
