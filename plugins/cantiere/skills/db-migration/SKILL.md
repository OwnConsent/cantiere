---
name: db-migration
description: Scrive una migrazione di schema reversibile con piano di esecuzione, revisione e gate sulle operazioni distruttive. Usala per qualunque cambiamento di struttura del database.
argument-hint: <cosa deve cambiare>
---

Migrazione richiesta: **$ARGUMENTS**

1. `database` legge lo schema attuale e `contracts/db/`, e progetta il cambiamento.
2. Applica il pattern **espandi → migra → contrai**: mai aggiungere e rimuovere nello stesso
   passaggio. La rimozione va in una migrazione successiva, dopo che il codice non usa più
   la vecchia struttura.
3. Scrivi `up` e `down`. Senza `down` non è finita.
4. Su tabelle grandi: indici `CONCURRENTLY`, backfill a lotti con pausa, nessun lock lungo
   su percorso caldo. Dichiara la durata stimata e il lock atteso.
5. Esegui su un database locale o di staging e allega il risultato, incluso `EXPLAIN` per
   ogni indice nuovo.
6. `privacy` verifica ogni colonna nuova che possa contenere dati personali.
7. `code-reviewer` rivede la migrazione e il rollback.

**Gate**: `DROP`, `DROP COLUMN`, `TRUNCATE` e qualunque perdita di dato si preparano ma non
si eseguono. Scrivi cosa verrebbe perso e fermati.
