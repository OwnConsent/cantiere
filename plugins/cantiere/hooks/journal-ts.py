#!/usr/bin/env python3
"""PreToolUse su Write. Nega una voce di journal il cui campo ts non coincide con
l'orologio di adesso.

La regola «il ts si prende da `date -Is` eseguito in quel momento, mai a memoria»
sta in session-start.sh e nella scheda di ogni agente dal 20/09. Il 23/09 due voci
di L14 portavano orari ricostruiti a posteriori: un journal con orari inventati non
e' un registro, e' un racconto — e su un registro ci si basa per capire quanto e'
costato un lotto e in quale ordine sono andate le cose.

Il controllo e' volutamente STRETTO nel campo e LARGO nella tolleranza: guarda solo
il campo ts, solo quando c'e', e concede una finestra ampia. Un hook che nega per
uno schema che non conosce produce falsi positivi, ed e' la famiglia di errori che
ci e' costata di piu'.

Tolleranza in minuti: CANTIERE_TOLLERANZA_TS, predefinita 15. A 0 il gate e' spento.
"""
import datetime as dt
import json
import os
import sys


def main():
    try:
        payload = json.load(sys.stdin)
    except Exception:
        sys.exit(0)

    try:
        tolleranza = int(os.environ.get("CANTIERE_TOLLERANZA_TS", "15"))
    except ValueError:
        tolleranza = 15
    if tolleranza <= 0:
        sys.exit(0)

    ti = payload.get("tool_input") or {}
    percorso = (ti.get("file_path") or "").replace("\\", "/")
    if "/journal/" not in f"/{percorso.lstrip('/')}" or not percorso.endswith(".json"):
        sys.exit(0)

    contenuto = ti.get("content")
    if not isinstance(contenuto, str):
        sys.exit(0)
    try:
        voce = json.loads(contenuto)
    except Exception:
        sys.exit(0)          # JSON non valido: lo dira' chi legge, non questo hook
    if not isinstance(voce, dict):
        sys.exit(0)

    grezzo = voce.get("ts")
    if not isinstance(grezzo, str) or not grezzo.strip():
        sys.exit(0)          # campo assente: non e' il mestiere di questo hook

    try:
        quando = dt.datetime.fromisoformat(grezzo.strip().replace("Z", "+00:00"))
    except ValueError:
        sys.stderr.write(
            f"TS NON LEGGIBILE: il campo ts della voce vale '{grezzo}', che non e' "
            "una data ISO. Prendilo da `date -Is` eseguito adesso.\n")
        sys.exit(2)

    adesso = dt.datetime.now(dt.timezone.utc)
    if quando.tzinfo is None:
        quando = quando.replace(tzinfo=adesso.astimezone().tzinfo)

    scarto = abs((adesso - quando).total_seconds()) / 60.0
    if scarto <= tolleranza:
        sys.exit(0)

    sys.stderr.write(
        f"TS RICOSTRUITO A MEMORIA: il campo ts vale '{grezzo}', che dista "
        f"{int(scarto)} minuti da adesso (tolleranza {tolleranza}). Esegui "
        "`date -Is` e usa quel valore. Se l'orario e' vecchio perche' la voce "
        "descrive un fatto di prima, il ts resta quello di ADESSO e il momento del "
        "fatto va nel corpo della voce: il ts dice quando hai scritto, non quando "
        "e' successo.\n")
    sys.exit(2)


if __name__ == "__main__":
    main()
