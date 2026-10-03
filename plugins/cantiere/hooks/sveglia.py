#!/usr/bin/env python3
"""La sveglia dei gate: quanto puo' durare un gate prima di negare da solo.

Un hook che supera il `timeout` di hooks.json viene terminato da Claude Code insieme
al suo involucro, e l'azione PASSA in silenzio (misurato il 03/10 con Claude Code
2.1.288; la documentazione: «on PreToolUse ... a timed-out command hook lets the tool
call continue», code.claude.com/docs/en/hooks). Un gate che scade e' un gate che si
rompe, quindi deve negare: per farlo deve svegliarsi PRIMA di Claude Code.

Il limite non e' scritto qui: si ricava dal `timeout` che hooks.json dichiara per
quell'hook, meno MARGINE. Cambiare il timeout in hooks.json sposta la sveglia; non
c'e' un secondo numero da tenere allineato. Se l'hook e' registrato piu' volte vale
il timeout piu' corto.

  sveglia.py <nome-in-hooks.json>      stampa i secondi (lo usa sveglia.sh)
  from sveglia import con_sveglia      per i gate Python

Limite noto: se la sveglia non scatta prima del timeout (MARGINE troppo piccolo per
una macchina lenta, o un timeout cambiato a mano fuori da hooks.json) si torna al
caso di partenza: Claude Code termina l'hook e l'azione passa.
"""
import json, os, signal, sys

# Secondi fra la sveglia e il timeout di Claude Code: il tempo per scrivere il
# diniego e uscire. I gate impiegano decine di millisecondi; due secondi bastano.
MARGINE = 2

def sveglia(hook):
    conf = json.load(open(os.path.join(os.path.dirname(os.path.abspath(__file__)),
                                       "hooks.json"), encoding="utf-8"))
    tempi = [h["timeout"] for gruppi in conf["hooks"].values() for g in gruppi
             for h in g["hooks"] if f'/hooks/{hook}"' in h["command"]]
    if not tempi:
        raise LookupError(f"{hook} non e' registrato in hooks.json")
    limite = min(tempi) - MARGINE
    if limite <= 0:
        raise ValueError(f"il timeout di {hook} in hooks.json ({min(tempi)} s) non "
                         f"lascia il margine di {MARGINE} s")
    return limite

class _Scaduto(Exception):
    pass

def con_sveglia(hook, corpo, rotto):
    """Esegue corpo() in un processo figlio e lo aspetta per sveglia(hook) secondi.
    Allo scadere lo termina e chiama rotto(). Un figlio, e non signal.alarm nello
    stesso processo: Python serve i segnali fra un'istruzione e l'altra, e una regex
    che non finisce (il modo piu' probabile in cui un parser si pianta) non
    lascerebbe mai girare il gestore."""
    limite = sveglia(hook)
    sys.stdout.flush(); sys.stderr.flush()
    figlio = os.fork()
    if figlio == 0:
        codice = 0
        try:
            corpo()
        except SystemExit as e:
            codice = e.code if isinstance(e.code, int) else (0 if e.code is None else 1)
        except BaseException:
            import traceback
            traceback.print_exc()
            codice = 1
        try:
            sys.stdout.flush(); sys.stderr.flush()
        finally:
            os._exit(codice)
    def scaduto(*_):
        raise _Scaduto()
    signal.signal(signal.SIGALRM, scaduto)
    signal.alarm(limite)
    try:
        _, stato = os.waitpid(figlio, 0)
        signal.alarm(0)
    except _Scaduto:
        try:
            os.kill(figlio, signal.SIGKILL)
            os.waitpid(figlio, 0)
        except OSError:
            pass
        rotto(f"tempo esaurito dopo {limite} s (il timeout in hooks.json e' "
              f"{limite + MARGINE} s)")
    sys.exit(os.waitstatus_to_exitcode(stato) if os.WIFEXITED(stato) else 1)

if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit("uso: sveglia.py <nome dell'hook in hooks.json>")
    try:
        print(sveglia(sys.argv[1]))
    except Exception as e:
        sys.exit(f"{type(e).__name__}: {e}")
