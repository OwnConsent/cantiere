# Definition of Done per ruolo

Un agente può dichiarare "fatto" solo se tutte le righe della sua sezione sono vere.
L'orchestratore verifica prima di passare allo stadio successivo.

| Ruolo | Fatto quando |
|---|---|
| @product-spec | ogni AC è osservabile dall'esterno; non-goal espliciti; `domande_aperte` vuoto |
| @architect | ADR scritto per ogni scelta che vincola più di un lotto; contratti aggiornati e committati |
| @database | migrazione con `up` e `down`; indici giustificati da un `EXPLAIN` allegato; nessun DDL distruttivo |
| @backend | compila, test verdi, nessuna query fuori dal layer dati, errori tipizzati |
| @frontend | usa solo token esistenti; stati loading/empty/error presenti; nessun valore hard-coded |
| @design | token esportati in `contracts/design-tokens.json`; ogni stato dei componenti specificato |
| @infrastructure | `plan` pulito su staging; nessuna risorsa senza tag owner e costo |
| @devops | pipeline verde end-to-end; rollback provato su staging |
| @qa-test | un test per ogni AC, scritto dalla spec e non dal codice; e2e del percorso critico |
| @code-reviewer | ogni finding ha file, riga e scenario; i non riproducibili sono stati scartati |
| @security | authz verificata sul percorso nuovo; nessun segreto; nessuna CVE critica introdotta |
| @privacy | ogni campo personale ha finalità, base giuridica e retention; data map aggiornata |
| @performance | budget dichiarati e misurati; nessuna regressione oltre soglia |
| @accessibility | nessuna violazione WCAG 2.2 AA bloccante; percorso completabile da tastiera |
| @seo | title/description/canonical/OG presenti; dati strutturati validi; heading in ordine |
| @sre-observability | la feature ha almeno un SLI e un alert; log strutturati con id di correlazione |
| @docs-writer | ADR e reference aggiornati nello stesso commit del cambiamento |
| @comms-release | note che dicono cosa cambia per chi usa il prodotto, non quali file sono cambiati |
| @data-analytics | eventi nella tassonomia, con owner e domanda a cui rispondono |

## Vale per tutti

Nessun ruolo ha finito finché non ha scritto le proprie voci di `journal/` secondo
`docs/JOURNAL.md`: le decisioni prese con le alternative scartate, i gate incontrati, i
tentativi falliti e le misure fatte. Scritte durante il lavoro, non ricostruite dopo.

| @case-study | ogni affermazione della traccia rimanda a una voce di journal; i fallimenti ci sono; i numeri di costo e durata sono quelli reali |
