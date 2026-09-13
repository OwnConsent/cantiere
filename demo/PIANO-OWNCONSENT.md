# Caso demo — dal primo commit al primo cliente servito

Il team di Cantiere viene messo alla prova sul go-to-market di **OwnConsent**, una
piattaforma di gestione del consenso (CMP) venduta in tre modalità. L'arco del corso non
si ferma al sito: arriva al primo cliente che paga e riceve il servizio.

## Perché non solo il sito

Un sito vetrina userebbe cinque ruoli su ventitré e mostrerebbe un team sovradimensionato
al proprio compito — che è la prima obiezione che farà una platea di tecnici. Portando
l'arco fino al primo cliente servito, ogni ruolo ha un lavoro reale:

| Ruolo | Cosa fa davvero in questo caso |
|---|---|
| `product-spec` | tre modalità di vendita = tre percorsi di attivazione, non tre schede di prezzo |
| `architect` | dove passa il confine fra tenant, e cosa è comune alle tre modalità |
| `database` | tenant, piani, sottoscrizioni, conteggio richieste ad alto volume |
| `backend` | registrazione, pagamento, emissione licenza, quote |
| `frontend` | sito pubblico, configuratore, area cliente |
| `design` | sistema visivo e i tre percorsi di attivazione |
| `infrastructure` | istanza dedicata per cliente in modalità hosted |
| `devops` | rilascio, e il provisioning come passo di pipeline |
| `privacy` | il caso più bello: la CMP il cui sito deve rispettare la propria CMP |
| `security` | isolamento fra tenant sul percorso di pagamento e di delivery |
| `performance` | il tetto richieste è un percorso caldo, non una `if` |
| `accessibility` | un prodotto di compliance con un sito non accessibile è una contraddizione |
| `seo` | tre modalità di vendita, tre intenzioni di ricerca diverse |
| `sre-observability` | il tetto richieste è letteralmente uno SLI |
| `data-analytics` | quale delle tre modalità viene scelta, e dove si abbandona |
| `comms-release` | l'annuncio, quando c'è un numero da raccontare |

## Le tre modalità

**SaaS** — l'utente si registra, paga un canone mensile, configura tutto da noi e riceve
il servizio da noi. Piani per volume di richieste. Il tetto è un limite di prodotto:
va progettato, misurato e comunicato prima di essere superato.

**Hosted** — istanziamo risorse dedicate per il cliente e il prezzo dipende dalla taglia
(disco, memoria, CPU). Il provisioning diventa parte della pipeline, non un ticket.

**On-premise** — il cliente installa da sé. Licenza annuale, e la registrazione della CMP
presso IAB Europe la fa lui a proprio nome.

## Arco in dieci tappe

| # | Tappa | Esito osservabile |
|---|---|---|
| 01 | Specifica delle tre modalità | `spec.json` con criteri verificabili e le domande aperte che fermano la catena |
| 02 | Contratti prima del codice | schema, token, tassonomia eventi, data map committati |
| 03 | Sito pubblico | home, funzionalità, i tre percorsi, documentazione, pagine legali |
| 04 | Registrazione e pagamento | un utente si registra e paga un piano SaaS |
| 05 | Quote e conteggio richieste | il tetto esiste, si misura e avvisa prima di essere raggiunto |
| 06 | Provisioning hosted | un cliente hosted ottiene la propria istanza dalla pipeline |
| 07 | Licenza on-premise | emissione licenza e guida alla registrazione CMP del cliente |
| 08 | Collaudo completo | sei revisori, finding confermati e finding scartati |
| 09 | I due gate | merge e promozione a produzione, con una persona |
| 10 | Prima richiesta servita | misura, comunicazione, e il primo ritorno che rientra nel backlog |

## I limiti da dichiarare in aula

Sono parte del contenuto, non note a piè di pagina: un corso che mostra un sistema senza
limiti insegna la cosa sbagliata.

- **I prezzi sono una decisione umana.** Fasce per volume, costo per taglia, importo della
  licenza: nessun agente può inventarli, e un listino inventato pubblicato non è una demo
  innocua. O sono decisi prima, o le pagine vanno marcate come dimostrative.
- **Le pagine legali sono bozze.** Informativa, condizioni, DPA: un agente le imposta, una
  persona competente le approva. Non è un gate del sistema, è un gate professionale — ed è
  un buon momento per spiegare la differenza.
- **La registrazione CMP presso IAB Europe è un atto del titolare.** Nessun agente la fa e
  nessuno dovrebbe poterla fare: è un limite giuridico, non una lacuna tecnica.
- **Il primo cliente del corso è finto.** Pagamento in modalità di test, dominio di
  dimostrazione. Va detto, altrimenti i numeri della tappa 10 non significano niente.
