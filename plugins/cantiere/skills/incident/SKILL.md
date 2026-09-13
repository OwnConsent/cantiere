---
name: incident
description: Triage di un problema in produzione — delimitazione, correlazione con i deploy, diagnosi, mitigazione proposta e PR di fix. Usala quando qualcosa è rotto in esercizio.
argument-hint: <sintomo osservato>
---

Incidente: **$ARGUMENTS**

Delega a `incident-responder` e segui la sua procedura. Mantieni una cronologia con orari
mentre il lavoro procede: dopo non la ricostruisci.

1. **Delimita** prima di ipotizzare: da quando, quanti, quali percorsi, quale ambiente.
2. **Correla** con deploy, migrazioni, cambi di configurazione e feature flag delle due ore
   precedenti.
3. **Verifica** ogni ipotesi con una query di log o una metrica. Non dedurre dal codice ciò
   che i dati possono dire.
4. **Mitigazione**: prepara rollback o feature flag e descrivi l'effetto atteso. Non eseguire
   su produzione — è un gate.
5. **Fix**: PR minima sulla causa, più il test di regressione da `qa-test`.
6. **Postmortem**: cronologia, causa, perché non è stato intercettato prima, quale controllo
   manca. Delega a `sre-observability` l'alert che avrebbe anticipato il problema.

Se dopo tre ipotesi verificate la causa non emerge, fermati e riporta cosa hai escluso.
