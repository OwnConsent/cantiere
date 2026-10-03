#!/usr/bin/env python3
"""PreToolUse. Nega il comando successivo quando c'e' lavoro non committato e
l'ultimo commit — o l'inizio della sessione, se non ha ancora committato — e' piu'
vecchio di N minuti.

Perche' serve accanto a guard-commit.sh, che conta i file: la soglia sui file vede
un lotto che SCRIVE molto, non un lotto che MISURA per due ore e scrive poco. In
L14 (23-24/09) quattro agenti su cinque sono arrivati al tetto dei turni
(riportato da chi ha condotto la sessione; da git non e' verificabile, perche'
un agente che si ferma senza committare e senza scrivere non lascia traccia —
che e' esattamente il problema che questo hook esiste per chiudere); il loro
lavoro l'ha committato la sessione principale.

Su main, sui 33 commit di L14, i ruoli nei trailer sono tre — orchestrator 28,
qa-test 4, architect 1 — e 4 commit portano il trailer orchestrator con dentro il
lavoro di un altro ruolo. Il caso peggiore non e' il nome sbagliato: @frontend e'
assente da ENTRAMBI i registri, zero trailer e zero voci di journal, e il suo
codice sta dentro due commit dell'orchestratore, 31 file. Due agenti fermatisi al
tetto senza committare e senza scrivere non sono stati attribuiti male: sono
spariti. Misura: ownconsent-www,
journal/2026-09-24/125146-orchestrator-misura.json.

Il journal e' piu' fedele dei trailer, non fedele: @qa-test ha 5 consegne nel
journal contro 4 commit firmati, e @frontend non compare in nessuno dei due.

Quindi il gate a tempo non protegge il lavoro dalla perdita: protegge
l'ATTRIBUZIONE. Un trailer Cantiere-Agent e' vero solo quanto e' tempestivo il
commit che lo porta.

Non blocca mai la via d'uscita: i comandi git che servono a committare, guardare
lo stato o pushare passano sempre. Non blocca una sessione senza lavoro sporco:
zero file modificati, zero motivi per fermarla.

Minuti: CANTIERE_MINUTI_COMMIT, predefinito 20. A 0 il gate e' spento.
"""
import json
import os
import re
import subprocess
import sys
import time

# La via d'uscita, e le letture che servono a decidere come uscire.
VIA_USCITA = re.compile(
    r"\bgit\s+(commit|add|push|stash|status|diff|log|rev-parse|switch|checkout|"
    r"restore|rebase|merge|worktree|fetch|pull|show|hash-object)\b"
)


def git(d, *a):
    return subprocess.run(["git", "-C", d, *a],
                          capture_output=True, text=True).stdout


def rotto(msg):
    """Il gate non ha potuto decidere: un gate guasto nega (README del plugin,
    «Gate e informativi»). La via d'uscita resta aperta solo se il gate arriva a
    leggere il comando: `git commit`, `git status` e gli altri passano prima."""
    sys.stderr.write(
        f"gate in errore: guard-tempo: {msg}: non so da quanto non committi, quindi "
        "nego. Riportalo ad Andrea invece di aggirarlo.\n")
    sys.exit(2)


def cartella(payload):
    ti = payload.get("tool_input") or {}
    f = ti.get("file_path") or ""
    if f:
        d = os.path.dirname(os.path.abspath(f)) or "."
        while not os.path.isdir(d) and d != os.path.dirname(d):
            d = os.path.dirname(d)
        return d
    return os.environ.get("CLAUDE_PROJECT_DIR") or os.getcwd()


def inizio_sessione(d, sid):
    if not sid:
        return None
    sicuro = "".join(c for c in sid if c.isalnum() or c in "-_")[:80]
    p = os.path.join(d, ".work", "sessioni", f"{sicuro}.json")
    try:
        return float(json.load(open(p, encoding="utf-8"))["inizio"])
    except Exception:
        return None


def esamina(payload):
    ti = payload.get("tool_input")
    if not isinstance(ti, dict):
        rotto("nel payload manca tool_input")
    if not any(isinstance(ti.get(k), str) and ti[k].strip() for k in ("command", "file_path")):
        rotto("nel payload non c'e' ne' tool_input.command ne' tool_input.file_path")

    try:
        minuti = int(os.environ.get("CANTIERE_MINUTI_COMMIT", "20"))
    except ValueError:
        minuti = 20
    if minuti <= 0:
        sys.exit(0)

    cmd = (payload.get("tool_input") or {}).get("command") or ""
    if VIA_USCITA.search(cmd):
        sys.exit(0)

    d = cartella(payload)
    if not os.path.isdir(d):
        rotto(f"la cartella di progetto non esiste ({d})")
    if not git(d, "rev-parse", "--git-dir").strip():
        sys.exit(0)

    stato = subprocess.run(["git", "-C", d, "status", "--porcelain",
                            "--untracked-files=normal"], capture_output=True, text=True)
    if stato.returncode != 0:
        rotto(f"git status e' uscito con {stato.returncode}")
    sporchi = [r for r in stato.stdout.splitlines() if r.strip()]
    if not sporchi:
        sys.exit(0)

    riferimenti = []
    ct = git(d, "log", "-1", "--format=%ct").strip()
    if ct.isdigit():
        riferimenti.append(int(ct))
    avvio = inizio_sessione(d, payload.get("session_id") or "")
    if avvio:
        riferimenti.append(avvio)
    if not riferimenti:
        sys.exit(0)

    eta = (time.time() - max(riferimenti)) / 60.0
    if eta <= minuti:
        sys.exit(0)

    sys.stderr.write(
        f"COMMIT PRIMA DI CONTINUARE: sono passati {int(eta)} minuti dall'ultimo "
        f"commit (soglia {minuti}) e ci sono {len(sporchi)} file non committati. "
        "Committa e pusha adesso quello che hai fatto finora, sul ramo del lotto, "
        "poi riprendi. Non e' una questione di non perdere lavoro: se il tetto dei "
        "turni arriva ora, il tuo lavoro lo committera' qualcun altro e il trailer "
        "Cantiere-Agent portera' il suo nome. In L14 e' successo a 4 commit su 33, "
        "e i due @frontend sono spariti da entrambi i registri.\n")
    sys.exit(2)


def lavoro():
    # FAIL-CLOSED (03/10). Misurato: un payload che non e' un oggetto, un tool_input
    # che non e' un oggetto o git assente dal PATH facevano uscire l'hook con 1, e un
    # payload illeggibile con 0. Per Claude Code sono errori non bloccanti: il comando
    # passava. sys.exit() solleva SystemExit e non e' un'eccezione di queste.
    try:
        payload = json.load(sys.stdin)
    except Exception as e:
        rotto(f"il payload non e' JSON valido ({type(e).__name__})")
    try:
        esamina(payload)
    except Exception as e:
        rotto(f"{type(e).__name__}: {e}")


def main():
    # SVEGLIA (03/10): un gate che supera il timeout di hooks.json viene terminato da
    # Claude Code e l'azione passa. lavoro() gira sotto una sveglia piu' corta, ricavata
    # da quel timeout: allo scadere si nega. Vedi sveglia.py.
    try:
        from sveglia import con_sveglia
        con_sveglia("guard-tempo.py", lavoro, rotto)
    except Exception as e:
        rotto(f"la sveglia non e' partita ({type(e).__name__}: {e})")


if __name__ == "__main__":
    main()
