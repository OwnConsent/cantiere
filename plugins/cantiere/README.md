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

## Il journal

Ogni agente scrive in `journal/` **mentre** lavora: decisioni con le alternative scartate,
gate incontrati, tentativi falliti, misure fatte. Vedi `docs/JOURNAL.md`.
È ciò che rende possibile `/lezione`, ed è anche ciò che rende rivedibile il lavoro degli
agenti a mesi di distanza.
