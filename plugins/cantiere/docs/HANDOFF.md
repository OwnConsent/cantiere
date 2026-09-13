# Protocollo di handoff

Gli agenti si passano JSON, non prosa. Tutto sotto `.work/<issue-id>/` (in `.gitignore`,
tranne `spec.json` che va allegata alla PR).

## spec.json — prodotto da @product-spec
```json
{
  "id": "123",
  "titolo": "Log dei consensi esportabile",
  "problema": "Chi gestisce il sito non può dimostrare un consenso a distanza di mesi.",
  "criteri_accettazione": [
    { "id": "AC1", "dato": "un consenso registrato ieri", "quando": "esporto il CSV del mese", "allora": "la riga c'è con timestamp UTC e purpose id" }
  ],
  "non_goal": ["interfaccia di ricerca full-text"],
  "dati_personali": [{ "campo": "ip_hash", "finalita": "prova del consenso", "retention": "6 anni" }],
  "rischi": ["volume di scrittura sul path caldo"],
  "domande_aperte": []
}
```
Regola: `domande_aperte` non vuoto ⇒ la catena si ferma e si commenta la issue.

## plan.json — prodotto da @orchestrator
```json
{
  "lotti": [
    { "id": "L1", "agente": "database", "titolo": "tabella consent_log + indici", "file": ["migrations/**"], "dipende_da": [] },
    { "id": "L2", "agente": "backend", "titolo": "mutation + export", "file": ["internal/consent/**"], "dipende_da": ["L1"] }
  ],
  "contratti_da_aggiornare": ["contracts/schema.graphql", "contracts/db/consent_log.sql"],
  "budget_turni": 40
}
```
Regola: due lotti non possono dichiarare gli stessi `file`. Se succede, si serializzano.

## findings.json — prodotto da ogni revisore
```json
{
  "agente": "security",
  "finding": [
    {
      "file": "internal/consent/export.go",
      "riga": 88,
      "gravita": "alta",
      "categoria": "authz",
      "sintesi": "L'export non filtra per tenant.",
      "scenario": "Utente del tenant B chiama exportConsents e riceve le righe del tenant A.",
      "verdetto": "CONFERMATO"
    }
  ]
}
```
Regola: senza `scenario` concreto il finding viene scartato. È il filtro che tiene bassa
la rumorosità e rende la review automatica leggibile.
