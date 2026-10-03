# Cantiere

23 ruoli che portano una issue dalla specifica alla produzione, più un osservatore che
trasforma il lavoro in materiale didattico. Due soli interventi umani: merge su `main`
e deploy in produzione.

## Cosa contiene

    agents/     24 ruoli (23 in cantiere + case-study)
    skills/     /feature /collaudo /db-migration /release-notes /incident /lezione
    hooks/      gate meccanici e controllo del journal
    workflows/  collaudo parallelo con conferma avversariale dei finding
    docs/       protocollo di handoff, definition of done, formato del journal, template ADR

## Comandi

    /feature <issue>        specifica -> piano -> contratti -> costruzione -> PR
    /collaudo <pr>          sei revisori in parallelo, finding confermati uno per uno
    /db-migration <cosa>    migrazione reversibile, gate sulle operazioni distruttive
    /incident <sintomo>     delimita, correla, diagnostica, propone il fix
    /release-notes <tag>    note dai commit e dalle specifiche
    /lezione <tappa>        moduli, slide, racconto e copione video dal journal

## I gate

Non sono frasi nel prompt: sono blocchi. `guard-prod.sh` nega push su ramo protetto, merge
di PR, comandi Kubernetes o Terraform su contesto di produzione e DDL distruttivo.
`guard-secrets.sh` blocca il salvataggio di un file che contiene un segreto.
`journal-check.sh` non lascia chiudere una sessione che ha cambiato codice senza lasciare
traccia.

## Gate e informativi: cosa succede quando un hook si rompe

**Un gate che si rompe nega. Un informativo che si rompe lo dice.** `hooks.json` non
ammette commenti, quindi il principio sta qui.

Perché serve scriverlo: per Claude Code solo l'uscita 2 blocca. Un hook che esce con 1
(un'eccezione), con 127 (interprete assente dal `PATH`), che scade o che stampa un JSON
troncato è un «errore non bloccante»: l'azione passa e all'agente non arriva niente.
Misurato il 03/10 con Claude Code 2.1.288 su ognuno dei quattro eventi. Un gate scritto
senza pensarci è quindi aperto proprio quando è guasto.

| Hook | Evento | Tipo | Quando si rompe |
|---|---|---|---|
| `guard-paths.sh` | PreToolUse, Bash | gate | nega il comando |
| `guard-prod.sh` | PreToolUse, Bash | gate | nega il comando |
| `guard-tempo.py` | PreToolUse, Bash/Edit/Write | gate | nega il comando o la scrittura |
| `agent-env.py` | PreToolUse, Bash | gate | nega il comando: senza il suo prefisso la firma si può autodichiarare |
| `guard-commit.sh` | PreToolUse, Edit/Write | gate | nega la scrittura |
| `journal-ts.py` | PreToolUse, Write | gate | nega la scrittura |
| `guard-secrets.sh` | PostToolUse, Edit/Write | gate | il file è già scritto: dice all'agente che NON è stato controllato |
| `journal-check.sh` | Stop | gate | nega la chiusura una volta; al secondo giro lascia chiudere e lo dice a chi guarda |
| `verify-after-edit.sh` | PostToolUse, Edit/Write | informativo | non blocca; lo dice nel contesto |
| `session-start.sh` | SessionStart | informativo | non blocca; lo dice nel contesto |

Due strati per i guasti, e servono tutti e due:

- **dentro lo script**: payload che non è JSON, campo atteso mancante, eccezione, comando
  esterno assente diventano un diniego che comincia con `gate in errore:` e dice il motivo;
- **in `hooks.json`**: ogni comando è un involucro di shell attorno allo script. Se lo
  script non parte nemmeno (interprete assente, bit di esecuzione perso) non c'è niente
  che possa intercettarlo dall'interno: l'involucro trasforma in 2 ogni uscita diversa
  da 0, e lascia intatto quello che un'uscita 0 scrive su stdout. È scritto per `/bin/sh`,
  non per bash: è con `/bin/sh -c` che Claude Code lancia gli hook.

Chi aggiunge un hook decide prima se è un gate o un informativo, gli mette l'involucro
del suo tipo e aggiunge a `verifica-gate.sh` i casi in cui si rompe.

C'è un terzo strato, per il **timeout**. Un hook che supera il `timeout` di `hooks.json`
viene terminato da Claude Code insieme al suo involucro, e l'azione passa in silenzio:
un gate che scade è un gate che si rompe. Ogni gate gira quindi sotto una sveglia più
corta, e allo scadere nega con `gate in errore: <hook>: tempo esaurito`. La sveglia non
è un numero scritto nello script: `sveglia.py` la ricava dal `timeout` che `hooks.json`
dichiara per quell'hook, meno un margine di 2 secondi. Per cambiare il limite di un gate
si cambia il suo `timeout` in `hooks.json`, e basta.

Cosa serve sulla macchina: **Python 3.8 o successivo** come `python3`, bash, git e i
comandi di base (`cat`, `sed`, `grep`, `dirname`, `sleep`, `mkdir`). La CI esegue
`verifica-gate.sh` due volte: con il Python del runner e con il 3.8. Un gate in shell
controlla i comandi esterni che usa prima di cominciare, e se uno manca nega con
`gate in errore: … comando esterno mancante`.

La foto di avvio (`.work/sessioni/<sessione>.json`) sta nella cartella in cui la
sessione è partita. Un hook gira nella cartella corrente dell'agente, che dopo un `cd`
non è più quella: `journal-check` e `guard-tempo` la ritrovano con `CLAUDE_PROJECT_DIR`,
che resta la cartella di avvio (misurato il 03/10 nel checkout principale, in una
worktree, dopo un `cd` in una sottocartella e dopo un `cd` in un'altra worktree).

Limiti noti: se la sveglia non scatta prima del timeout (misurato portandola oltre:
il comando parte) si torna al caso di partenza; gli hook informativi non hanno sveglia,
e se scadono non arriva niente nel contesto.

## Il journal

Ogni agente scrive in `journal/` **mentre** lavora: decisioni con le alternative scartate,
gate incontrati, tentativi falliti, misure fatte. Vedi `docs/JOURNAL.md`.
È ciò che rende possibile `/lezione`, ed è anche ciò che rende rivedibile il lavoro degli
agenti a mesi di distanza.
