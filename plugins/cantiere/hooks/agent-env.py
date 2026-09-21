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
"""
import json, re, sys

def main():
    try:
        d = json.load(sys.stdin)
    except Exception:
        sys.exit(0)
    ti = d.get("tool_input") or {}
    cmd = ti.get("command")
    if not isinstance(cmd, str) or not re.search(r"\bgit\b", cmd):
        sys.exit(0)
    if "CANTIERE_AGENT=" in cmd:          # gia' riscritto: non raddoppiare
        sys.exit(0)
    tipo = (d.get("agent_type") or "").strip()
    ruolo = tipo.split(":", 1)[-1] if tipo else "orchestrator"
    # solo caratteri sicuri in un nome di ruolo: nessuna iniezione nella shell
    if not re.fullmatch(r"[A-Za-z0-9._-]{1,64}", ruolo):
        ruolo = "sconosciuto"
    nuovo = dict(ti)
    nuovo["command"] = f"export CANTIERE_AGENT={ruolo}; {cmd}"
    json.dump({"hookSpecificOutput": {"hookEventName": "PreToolUse",
                                      "updatedInput": nuovo}}, sys.stdout)
    sys.exit(0)

if __name__ == "__main__":
    main()
