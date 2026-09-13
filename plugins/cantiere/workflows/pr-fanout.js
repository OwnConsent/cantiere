export const meta = {
  name: 'pr-fanout',
  description: 'Verifica una PR con sei revisori paralleli e conferma ogni finding in modo avversariale',
  phases: [{ title: 'Revisione' }, { title: 'Conferma' }],
}

const DIMENSIONI = [
  { key: 'correttezza',   agente: 'code-reviewer',  quando: 'sempre' },
  { key: 'test',          agente: 'qa-test',        quando: 'sempre' },
  { key: 'sicurezza',     agente: 'security',       quando: 'authn/authz, input esterni, dipendenze' },
  { key: 'privacy',       agente: 'privacy',        quando: 'dati personali, cookie, tracciamento' },
  { key: 'performance',   agente: 'performance',    quando: 'percorsi caldi, query, dipendenze nuove' },
  { key: 'accessibilita', agente: 'accessibility',  quando: 'file di interfaccia' },
]

const SCHEMA_FINDING = {
  type: 'object',
  properties: {
    finding: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          file: { type: 'string' },
          riga: { type: 'number' },
          gravita: { type: 'string', enum: ['critica', 'alta', 'media', 'bassa'] },
          sintesi: { type: 'string' },
          scenario: { type: 'string' },
        },
        required: ['file', 'sintesi', 'scenario'],
      },
    },
  },
  required: ['finding'],
}

const SCHEMA_VERDETTO = {
  type: 'object',
  properties: {
    reale: { type: 'boolean' },
    motivo: { type: 'string' },
  },
  required: ['reale', 'motivo'],
}

const diff = args?.diff ?? 'il diff della PR corrente (usa `git diff origin/main...HEAD`)'

const risultati = await pipeline(
  DIMENSIONI,
  (d) =>
    agent(
      `Sei l'agente @${d.agente}. Rivedi ${diff} seguendo ${CLAUDE_PLUGIN_ROOT}/agents/${d.agente}.md.\n` +
        `Pertinenza: ${d.quando}. Se il diff non tocca la tua area, restituisci una lista vuota.\n` +
        `Leggi contracts/ e .work/*/spec.json. Ogni finding deve avere uno scenario concreto di rottura.`,
      { label: `revisione:${d.key}`, phase: 'Revisione', schema: SCHEMA_FINDING },
    ),
  (revisione) =>
    parallel(
      revisione.finding.map((f) => () =>
        agent(
          `Prova a CONFUTARE questo finding leggendo il codice reale.\n` +
            `File: ${f.file}:${f.riga ?? '?'}\nSintesi: ${f.sintesi}\nScenario: ${f.scenario}\n` +
            `Se lo scenario non è riproducibile nel codice così com'è, reale = false.`,
          { label: `conferma:${f.file}`, phase: 'Conferma', schema: SCHEMA_VERDETTO },
        ).then((v) => ({ ...f, verdetto: v })),
      ),
    ),
)

const confermati = risultati
  .flat()
  .filter(Boolean)
  .filter((f) => f.verdetto?.reale)
  .sort((a, b) => ['critica', 'alta', 'media', 'bassa'].indexOf(a.gravita) - ['critica', 'alta', 'media', 'bassa'].indexOf(b.gravita))

return { confermati, totale_grezzi: risultati.flat().length }
