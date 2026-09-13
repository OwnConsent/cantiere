---
name: release-notes
description: Genera release notes e materiale di annuncio a partire dai commit e dalle specifiche delle issue collegate. Usala al momento di un rilascio.
argument-hint: <tag, es. v1.4.0>
---

Rilascio: **$ARGUMENTS**

1. Estrai i commit fra l'ultimo tag e questo, raggruppati per tipo.
2. Per ogni gruppo recupera la `spec.json` della issue collegata: serve il problema risolto,
   non l'implementazione.
3. Chiedi a `data-analytics` i numeri disponibili e a `performance` le misure prima/dopo.
   Se non ci sono, non inventarli: ometti la voce.
4. `comms-release` scrive le note nella struttura: Da sapere (breaking change) · Novità ·
   Miglioramenti · Correzioni.
5. `docs-writer` aggiorna il changelog tecnico e la reference.
6. `privacy` verifica che le note non descrivano trattamenti non dichiarati nell'informativa.

Consegna la bozza. Non creare il tag, non pubblicare: sono gate umani.
