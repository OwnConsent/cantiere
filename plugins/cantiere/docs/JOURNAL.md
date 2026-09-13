# journal/ — la traccia di quello che è successo davvero

Il journal è versionato e committato (a differenza di `.work/`, che è scratch).
Non è documentazione: è la registrazione contemporanea al lavoro.

## La regola che conta

**Si scrive mentre si lavora, non alla fine.** Un agente che a fine giro «racconta cosa è
successo» produce una ricostruzione plausibile a partire dal risultato: ha già in contesto
la soluzione, quindi tutte le scelte sembrano ovvie e le strade sbagliate scompaiono.
È esattamente il materiale che rende un caso studio non credibile.

Scrivere la voce fa parte della Definition of Done del lotto, non è un passaggio successivo.

## La seconda regola

**I fallimenti si registrano come i successi.** Un giro il cui journal contiene solo
decisioni riuscite è un journal incompleto, non un lavoro perfetto: vuol dire che l'agente
ha scritto solo ciò di cui andava fiero. Registra il tentativo scartato, il finding che non
ha retto alla confutazione, il gate che ha fermato tutto, la misura che ha smentito
l'assunzione, il giro costato il triplo del previsto.

## Struttura

    journal/
      2026-09-15/
        1412-database-decisione.json
        1436-database-fallimento.json
        1502-privacy-gate.json
        1530-performance-misura.json

## Formato

```json
{
  "ts": "2026-09-15T14:12:00+02:00",
  "agente": "database",
  "issue": "123",
  "lotto": "L1",
  "stadio": "03-costruzione",
  "tipo": "decisione",
  "titolo": "consent_log partizionata per mese",
  "contesto": "Attesi 3M consensi/mese per cliente enterprise; l'export mensile fa scansione completa.",
  "alternative": [
    { "opzione": "tabella unica + indice su created_at", "scartata_perche": "EXPLAIN: scansione da 4.2s sull'export" }
  ],
  "evidenza": ["EXPLAIN ANALYZE allegato al commit a1b2c3d", "export 4.2s -> 0.3s"],
  "esito": "applicata",
  "umano_coinvolto": false,
  "costo_token": 18400,
  "durata_s": 220
}
```

## Tipi di voce

| tipo | quando si scrive | campo che non può mancare |
|---|---|---|
| `decisione` | si è scelto fra alternative reali | `alternative` non vuoto |
| `gate` | un blocco ha fermato il lavoro | `chi_ha_deciso`, `cosa_serviva` |
| `fallimento` | un tentativo non ha funzionato | `cosa_si_e_imparato` |
| `misura` | si è misurato invece di dedurre | `evidenza` con numeri |
| `consegna` | un lotto è stato chiuso | `dod_soddisfatta` |

## Cosa non va nel journal

Dati personali, segreti, contenuto di variabili d'ambiente, e narrazione. Il journal
registra fatti e numeri; il racconto lo costruisce `@case-study` a partire da questi.
