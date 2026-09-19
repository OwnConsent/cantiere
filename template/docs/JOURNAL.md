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

## La terza regola: tre cose che non si scrivono a memoria

**L'orario si prende dall'orologio.** Il campo `ts` si ricava da `date -Is`, mai scritto a
mano. Il 15/09 alcune voci portavano orari inventati: un registro con orari plausibili ma
falsi e' peggio di un registro senza orari, perche' sembra una prova.

**Nessun conteggio di turni o di chiamate.** Non scrivere «ho usato N turni»: non lo sai.
Due volte il numero dichiarato e' risultato meta' di quello contato dal sistema — 15 contro
81 il 13/09, 24 contro 35 il 15/09. Se il dato serve, lo legge una persona da `/context`.

**Nessun trailer scritto a mano nei messaggi di commit.** `Cantiere-Agent:` e
`Co-Authored-By:` li mette il git hook. Un co-autore aggiunto a mano falsa l'attribuzione
e va rimosso.

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

## Le correzioni si aggiungono, non si sovrascrivono

Una voce sbagliata **non si modifica**: si scrive una voce nuova di tipo `correzione` che
cita l'id di quella superata e dice cosa era sbagliato e come lo si è scoperto. La voce
vecchia resta dov'è.

Un registro che si può riscrivere in silenzio non è una prova, è un racconto. E per il
corso è peggio ancora: la correzione è il momento più istruttivo che ci sia, e cancellarla
toglie proprio la parte che vale.

```json
{
  "tipo": "correzione",
  "corregge": "2026-09-13/1613-feature-gate.json",
  "cosa_era_sbagliato": "Dicevo che il messaggio non era arrivato all'agente.",
  "come_lo_so": "Il messaggio è arrivato più tardi e ha riavviato l'agente: 364k token.",
  "esito": "la voce superata resta, questa la corregge"
}
```

## Cosa non va nel journal

Dati personali, segreti, contenuto di variabili d'ambiente, e narrazione. Il journal
registra fatti e numeri; il racconto lo costruisce `@case-study` a partire da questi.
