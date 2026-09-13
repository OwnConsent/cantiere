---
name: collaudo
description: Collaudo di una pull request — ventaglio di verifica — revisione, test, sicurezza, privacy, performance e accessibilità in parallelo, con filtro avversariale dei finding. Usala su ogni PR prima del merge.
argument-hint: <numero della PR>
---

PR da verificare: **$ARGUMENTS**

1. Recupera il diff e la `spec.json` collegata.
2. Lancia **in parallelo**, ognuno con contesto pulito, su diff e contratti:
   `code-reviewer`, `qa-test`, `security`, `privacy`, `performance`, `accessibility`.
   Salta i ruoli non pertinenti al diff (nessun file di interfaccia ⇒ niente accessibility)
   e dichiara quali hai saltato e perché.
3. Raccogli i `findings.json`.
4. **Filtro avversariale**: per ogni finding di gravità alta o critica, delega a un agente
   distinto il compito di confutarlo. Chi non regge alla confutazione viene scartato.
5. Pubblica un solo commento di riepilogo, ordinato per gravità, con file e riga.
   I finding bloccanti in cima, separati dal resto.
6. Se non ci sono finding, scrivilo in una riga. È un esito legittimo.

Regola: un finding senza scenario concreto di rottura non arriva al commento.
Non approvare, non mergiare: il merge è un gate umano.
