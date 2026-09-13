---
name: lezione
description: Genera il materiale didattico di una tappa o dell'intero progetto a partire dal journal, dalla storia git e dalle PR. Usala a fine tappa, mai durante la costruzione.
argument-hint: <tappa o intervallo, es. "modulo 3" oppure "v0.1.0..v0.2.0">
---

Materiale da produrre per: **$ARGUMENTS**

1. **Raccogli.** Leggi le voci di `journal/` nell'intervallo, i commit, le PR con i loro
   commenti di collaudo e gli esiti CI. Metti in fila i fatti con i loro orari.
2. **Controlla la copertura.** Confronta i commit dell'intervallo con le voci di journal:
   ogni cambiamento significativo dovrebbe avere una voce. Elenca in cima quelli che non
   ce l'hanno — sono buchi nel materiale, e vanno colmati chiedendo al ruolo competente,
   non inventati.
3. **Verifica il rapporto fallimenti/successi.** Se nell'intervallo non c'è nessuna voce
   `fallimento` né `gate`, segnalalo: quasi sempre vuol dire journal reticente, non lavoro
   perfetto. Un caso studio senza intoppi non è credibile davanti a una platea di tecnici.
4. **Delega a `case-study`** la scrittura dei quattro output: moduli, slide, racconto,
   copione video.
5. **Estrai i numeri** dal journal e dai log CI: costo per stadio, durata, finding
   confermati su finding grezzi, quante volte un gate si è attivato. I numeri reggono una
   lezione meglio di qualunque affermazione.
6. **Proponi i tag git** per le tappe, senza crearli.

Non modificare codice del progetto. Non creare tag. Non pubblicare nulla.
