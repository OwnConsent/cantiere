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

## Come si scrive un mandato — misurato il 19-21/09

- **Il modello si decide una volta, poi si replica.** Lo stesso lavoro ha prodotto due
  file in 45 turni con un mandato che faceva ri-progettare a ogni elemento, e sei con
  «il modello e' deciso, copialo». Il tetto dei turni non e' il collo di bottiglia: e'
  lo strumento che lo mostra.
- **Un mandato di verifica dice dove salvare e quando fermarsi.** Scrivi ogni finding
  su file appena trovato; fermati a fine perimetro; una copertura parziale dichiarata
  e' una consegna. Cinque revisori su cinque senza queste righe hanno consegnato zero.
- **Si delega quando il lavoro e' parallelo o la separazione dei ruoli e' portante.**
  Non si delega il lavoro sequenziale dentro un lotto che la sessione ha gia' in
  contesto: in L06 costava circa 100.000 token a pagina, spesi a riscoprire. Quando un
  pezzo lo scrive il filo principale, il journal lo dice.
- **Un lotto che non deve leggere un'area** — i test scritti dalla spec senza guardare
  il codice — mette quell'area in `.cantiere-deny.local` nella SUA worktree, prima di
  partire. Non si committa. Il divieto nel mandato da solo e' stato violato due volte
  su cinque.

## Una sessione per worktree

La checkout principale e' di Andrea. Ogni lotto, ogni sessione, ogni agente lavora in una
worktree sua. Il 20/09 due sessioni nella stessa cartella si sono spostate il ramo sotto
i piedi e un'anteprima sulla porta di un'altra ha prodotto una misura falsa. Una sessione
non sopravvive al suo lotto: un turno di una sessione vissuta quattro giorni e' costato
sette volte un turno di una sessione nata e chiusa nello stesso pomeriggio.

Non mergiare. Non fare deploy. Non modificare `contracts/` fuori dal passo 2.
