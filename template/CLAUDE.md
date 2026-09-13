# Istruzioni di progetto

> Compila questo file. Gli agenti lo leggono tutti: quello che scrivi qui vale
> più di qualunque prompt successivo.

## Cosa è questo progetto
<!-- Una frase. A chi serve, cosa fa. -->

## Stack
- Linguaggi/framework:
- Database:
- Deploy:

## Comandi
| Scopo | Comando |
|---|---|
| Install | |
| Test | |
| Lint | |
| Typecheck | |
| Build | |
| Migrazioni | |
| E2E | |

## Convenzioni
- Branch: `tipo/<id-issue>-<slug>` (es. `feat/123-consent-log`)
- Commit: Conventional Commits, in inglese, imperativo.
- Ogni PR referenzia la issue e allega `.work/<id>/spec.json`.

## Regole non negoziabili
1. I contratti in `contracts/` si leggono prima di scrivere codice e si modificano solo via `@architect`.
2. Chi scrive il codice non scrive i test di accettazione: quelli sono di `@qa-test`.
3. Nessun push diretto su `main`, nessun merge di PR, nessun comando su contesto di produzione.
4. Nessun segreto nei file, nei log o nei commenti di PR.
5. Ogni campo di dato personale nuovo passa da `@privacy` prima del merge.
6. Se un'informazione manca, si apre una domanda sulla issue. Non si indovina.

## Misura, non dedurre
Prima di dichiarare che qualcosa funziona: eseguilo. Prima di dire che una query è lenta:
`EXPLAIN`. Le affermazioni non verificate vanno marcate come tali.
