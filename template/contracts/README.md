# contracts/ — l'unica superficie di contatto fra agenti

Ogni agente legge da qui prima di scrivere codice. Nessun agente modifica questi file
di propria iniziativa: le modifiche passano da `@architect` e da un ADR.

| File | Proprietario | Consumato da |
|---|---|---|
| `schema.graphql` | @architect | @backend, @frontend, @qa-test |
| `openapi.yaml` | @architect | @backend, @qa-test |
| `db/*.sql` | @database | @backend, @performance |
| `design-tokens.json` | @design | @frontend, @accessibility |
| `events.json` | @data-analytics | @frontend, @backend, @privacy |
| `data-map.json` | @privacy | @database, @backend, @security |
| `perf-budgets.json` | @performance | @devops (CI) |

Regola di compatibilità: una modifica che rompe un consumatore esistente richiede un
percorso di deprecazione dichiarato nell'ADR. Rimuovere un campo senza deprecazione è
un gate: si ferma.
