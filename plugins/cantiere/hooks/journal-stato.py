#!/usr/bin/env python3
"""Fotografia dello stato del repository, per journal-check.

  journal-stato.py foto   <session_id>   all'avvio della sessione
  journal-stato.py esame  <session_id>   alla chiusura: stampa DUE numeri,
                                         file di lavoro cambiati e voci di journal nuove

Il controllo precedente usava la data di modifica dei file (find -newer): in una
checkout toccata da piu' sessioni, attribuiva a questa sessione le modifiche
fatte da un'altra. Il 20/09 ha bloccato una sessione di sola lettura per due file
modificati prima che cominciasse — e l'agente, giustamente, si e' rifiutato di
scrivere una voce di journal per un lavoro mai fatto.

Ora si confronta il CONTENUTO: all'avvio si registra l'hash di ogni file modificato
o non tracciato e il commit di partenza; alla chiusura conta solo cio' che e'
diverso da quella foto, piu' i file toccati dai commit fatti da allora.
La foto e' per session_id: sessioni parallele nella stessa cartella non si
sovrascrivono.
"""
import json, os, subprocess, sys, time

ESCLUSI = ("journal/", "corso/", ".work/", ".claude/")

def git(*a):
    return subprocess.run(["git", *a], capture_output=True, text=True).stdout

def sporchi():
    out = {}
    raw = subprocess.run(["git", "status", "--porcelain", "-z", "--untracked-files=all"],
                         capture_output=True).stdout.decode("utf-8", "replace")
    voci = raw.split("\0")
    i = 0
    while i < len(voci):
        v = voci[i]; i += 1
        if len(v) < 4:
            continue
        stato, p = v[:2], v[3:]
        if stato[0] in "RC":          # rinomina: il campo successivo e' il nome vecchio
            i += 1
        if os.path.isfile(p):
            h = git("hash-object", "--", p).strip()
        else:
            h = "ASSENTE"
        out[p] = h
    return out

def percorso(sid):
    os.makedirs(".work/sessioni", exist_ok=True)
    sicuro = "".join(c for c in sid if c.isalnum() or c in "-_")[:80] or "anonima"
    return f".work/sessioni/{sicuro}.json"

def foto(sid):
    stato = {"inizio": time.time(), "head": git("rev-parse", "HEAD").strip(),
             "sporchi": sporchi()}
    with open(percorso(sid), "w", encoding="utf-8") as f:
        json.dump(stato, f)

def esame(sid):
    p = percorso(sid)
    if not os.path.isfile(p):
        print("0 0"); return
    s = json.load(open(p, encoding="utf-8"))
    ora = sporchi()
    cambiati = {f for f, h in ora.items() if s["sporchi"].get(f) != h}
    cambiati |= {f for f in s["sporchi"] if f not in ora}   # tornati puliti o committati
    # file toccati dai commit fatti DURANTE la sessione (tempo di commit >= avvio)
    if s.get("head"):
        log = git("log", "--format=@%ct", "--name-only", f'{s["head"]}..HEAD')
        dentro = False
        for riga in log.splitlines():
            if riga.startswith("@"):
                dentro = int(riga[1:]) >= int(s["inizio"]) - 5
            elif riga.strip() and dentro:
                cambiati.add(riga.strip())
    lavoro = [f for f in cambiati if not f.startswith(ESCLUSI)]
    voci = [f for f in cambiati if f.startswith("journal/") and f.endswith(".json")]
    print(len(lavoro), len(voci))

if __name__ == "__main__":
    if len(sys.argv) != 3 or sys.argv[1] not in ("foto", "esame"):
        sys.exit(0)
    try:
        {"foto": foto, "esame": esame}[sys.argv[1]](sys.argv[2])
    except Exception:
        if sys.argv[1] == "esame":
            print("0 0")
