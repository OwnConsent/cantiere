---
name: feature
description: Porta una issue dalla specifica alla PR aperta, coordinando product-spec, architect e i ruoli di costruzione. Usala come punto di ingresso di ogni feature nuova.
argument-hint: <url o numero della issue>
---

Feature richiesta: **$ARGUMENTS**

Esegui gli stadi 01→03 della pipeline. Delega, non implementare tu.

1. **Specifica** — delega a `product-spec`. Se `spec.json` esce con `domande_aperte` non
   vuoto, fermati qui, commenta la issue con le domande e riporta.
2. **Piano e contratti** — delega a `orchestrator` per `plan.json`; poi `architect`,
   `database` e `design` aggiornano `contracts/` in un commit separato, prima dell'implementazione.
   **Prima di passare al passo 3, pusha il ramo del lotto su `origin`.** Le worktree degli
   agenti nascono da `origin`: quello che non e' stato pushato, per loro non esiste.
3. **Costruzione** — l'orchestratore assegna i lotti ai ruoli di costruzione. Lotti che non
   condividono file girano in parallelo in worktree separate. A ogni agente che lavora in
   worktree **di' esplicitamente il nome del ramo del lotto**: la sua worktree parte da
   `origin/main` e senza quel nome lavorerebbe su una base priva del passo 2. Il 15/09 e'
   successo, e le worktree sono state rifatte a mano.
4. **Verifica locale** — esegui i comandi di test dichiarati in `CLAUDE.md`. Se falliscono,
   rimanda al ruolo competente con l'errore esatto. Massimo due rimandi.
5. **PR** — apri la PR con: link alla issue, `spec.json` allegata, lista dei lotti,
   comandi di verifica eseguiti con il loro esito, e le decisioni che richiedono una persona.

Non mergiare. Non fare deploy. Non modificare `contracts/` fuori dal passo 2.
