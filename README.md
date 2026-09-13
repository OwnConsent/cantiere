# Cantiere

Un team di 23 agenti che porta una issue dalla specifica alla produzione, più un osservatore
che trasforma il lavoro fatto in materiale didattico. Due soli interventi umani: merge su
`main` e deploy in produzione.

Questo repository contiene il plugin e il template di progetto. Il caso demo che lo mette
alla prova — il go-to-market di OwnConsent nelle sue tre modalità di vendita — è descritto
in `demo/PIANO-OWNCONSENT.md` e vive in un repository separato.

## Installazione

    /plugin marketplace add <org>/cantiere
    /plugin install cantiere@cantiere

Poi, nel repository di progetto:

    cp -r template/. .
    cat template/gitignore-append.txt >> .gitignore

E compila `CLAUDE.md` e `contracts/` con la realtà del progetto. È il passo che conta di più:
un'ora qui vale più di venti prompt dopo.

## Gate lato GitHub

Il plugin blocca ciò che passa da Claude Code. Il resto va chiuso su GitHub, una volta sola:

- branch protection su `main`: PR obbligatoria, check verdi, niente push diretti;
- Environment `production` con "Required reviewers";
- segreto `CLAUDE_CODE_OAUTH_TOKEN` in Actions — i workflow usano il tuo abbonamento
  invece della fatturazione a token. Generalo con `claude setup-token`, poi
  `gh secret set CLAUDE_CODE_OAUTH_TOKEN --repo <org>/<repo>`. Il token è personale:
  per un uso condiviso serve invece una chiave API o la federazione OIDC.

Finché non li attivi, gli hook sono l'unica difesa e valgono solo dove gira Claude Code.

## Ordine di adozione

Non attivare i 23 ruoli al primo giro: produrrebbero ventitré modi di sbagliare insieme e
nessuno capirebbe quale. L'ordine che regge:

1. `product-spec` e `code-reviewer` — da soli cambiano la qualità di tutto il resto;
2. i ruoli di costruzione, che sono la parte di cui conosci già il comportamento atteso;
3. i revisori specialistici, uno alla volta, finché i suoi commenti non sono affidabili;
4. l'esercizio, quando c'è qualcosa in produzione da esercitare.

Per togliere un ruolo: spostalo fuori da `plugins/cantiere/agents/`.

## Struttura

    .claude-plugin/marketplace.json   il marketplace da cui si installa
    plugins/cantiere/                 il plugin: agenti, skill, hook, workflow, docs
    template/                         da copiare nel repository di progetto
    demo/PIANO-OWNCONSENT.md          il caso su cui il team viene messo alla prova

## Stato

Versione 0.1.0. Due cose da verificare prima di usarlo su un progetto vero:

- la versione di `anthropics/claude-code-action` nei workflow, rispetto alla documentazione
  corrente di GitHub Actions;
- i server MCP in `template/.mcp.json`: Figma e Postgres sono pacchetti di terze parti,
  tieni solo quelli che usi davvero — ognuno costa contesto a ogni agente che lo carica.
