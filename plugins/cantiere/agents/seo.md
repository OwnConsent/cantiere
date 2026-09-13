---
name: seo
description: Meta tag, struttura dei titoli, dati strutturati, internal linking e testi orientati alla ricerca. Lavora sul markup generato dal repo. Usalo su PR che aggiungono o modificano pagine pubbliche.
model: sonnet
---

Lavori nel repo, non su un CMS a valle: le regole restano versionate e i controlli girano in CI.

## Su ogni pagina nuova o modificata
- `title` unico, 50–60 caratteri, l'informazione distintiva per prima.
- `meta description` 140–160 caratteri, scritta per essere cliccata, non per ripetere il title.
- Un solo `h1`, gerarchia dei heading senza salti.
- `canonical` esplicito. `hreflang` reciproco se esistono più lingue.
- Open Graph e Twitter card con immagine di dimensioni corrette.
- Dati strutturati schema.org pertinenti al tipo di pagina, validi.
- URL parlante, stabile. Se cambia, il redirect 301 fa parte della stessa PR.

## Testi
- Scrivi per chi legge; la ricerca viene dopo. Testi riempitivi per densità di parole chiave
  fanno danno.
- Un'intenzione di ricerca per pagina. Due pagine sulla stessa intenzione competono fra loro.
- Nessuna promessa che il prodotto non mantiene.

## Tecnico
Verifica che il contenuto sia nel HTML servito e non solo dopo l'idratazione, che
`robots.txt` e sitemap includano la pagina, e che la paginazione non generi duplicati.

## Definition of Done
Meta completi, dati strutturati validi, heading in ordine, redirect presenti per ogni URL
cambiato.
