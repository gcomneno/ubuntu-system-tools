# Workflow Storage

Ubuntu System Tools fornisce un workflow storage safety-first per osservare,
classificare, proporre, revisionare e pulire esplicitamente target Docker
selezionati.

Il workflow è intenzionalmente separato in distinti confini di autorità:

```text
osserva
→ misura
→ attribuisci
→ correla
→ classifica
→ proponi
→ revisione umana
→ target esatto
→ preview
→ apply esplicito
→ rivalida
→ pulisci
→ verifica
```

La regola centrale è:

```text
discovery != authority
classification != authority
proposal != authority
STALE_CANDIDATE != STALE_CONFIRMED
unknown != safe to delete
```

## Stato e crescita dello storage

`storage-check` è read-only per impostazione predefinita.

Riporta:

- utilizzo e spazio disponibile del filesystem root;
- dimensione di `$HOME`, `/var` e della root progetti configurata, quando leggibili;
- progetti di grandi dimensioni tramite soglie configurabili;
- crescita rispetto a un checkpoint esplicito.

Esempi:

```bash
storage-check
storage-check --save-checkpoint "$HOME/.cache/ubuntu-system-tools/storage.env"
storage-check --checkpoint "$HOME/.cache/ubuntu-system-tools/storage.env"
```

Gli audit Docker e DDEV possono essere delegati esplicitamente:

```bash
storage-check --docker --ddev
```

## Audit Docker

`storage-docker-audit` ispeziona container, immagini, volumi Docker e cache
BuildKit senza invocare prune o operazioni di rimozione.

L'evidenza viene classificata in modo conservativo come:

```text
ACTIVE
INACTIVE_PROTECTED
STALE_CANDIDATE
UNKNOWN
```

L'audit Docker non promuove mai un artefatto a `STALE_CONFIRMED`.

## Audit DDEV

`storage-ddev-audit` correla registry DDEV, root dei progetti, worktree Git e
metadata approot generati.

Un path generato obsoleto può essere riportato come:

```text
DDEV_METADATA_STATE=STALE_PATH
```

Questa è soltanto evidenza e non costituisce autorità alla cancellazione.

## Proposal di cleanup

`storage-cleanup-proposal` converte esclusivamente evidenza
`STALE_CANDIDATE` relativa a immagini e volumi Docker in un manifest
deterministico da revisionare.

Il proposal layer resta read-only:

```text
STALE_CANDIDATE != STALE_CONFIRMED
PROPOSAL != AUTHORITY
```

Per le immagini usa l'ID Docker immutabile. Per i volumi usa il nome esatto.

Esempio:

```bash
storage-cleanup-proposal
```

Il proposal contiene soltanto comandi di preview:

```text
storage-cleanup image IMAGE_ID
storage-cleanup volume VOLUME_NAME
```

Non emette mai `--apply`.

Il manifest dichiara sempre:

```text
REVIEW_REQUIRED=YES
AUTHORITY=NO
AUTOMATIC_DELETION=NO
```

Il proposal fallisce chiuso se la sorgente dell'audit Docker non dichiara
esplicitamente:

```text
STALE_CONFIRMED_COUNT=0
AUTOMATIC_DELETION=NO
```

La cache BuildKit non viene proposta per la cleanup.

## Cleanup exact-target

`storage-cleanup` è un tool controlled-action separato.

Accetta esattamente un target Docker di tipo immagine o volume.

La preview è predefinita:

```bash
storage-cleanup image IMAGE_REF_OR_ID
storage-cleanup volume VOLUME_NAME
```

La mutazione richiede lo stesso target esatto più `--apply` esplicito:

```bash
storage-cleanup image IMAGE_REF_OR_ID --apply
storage-cleanup volume VOLUME_NAME --apply
```

Prima della mutazione il tool:

1. risolve il target esatto;
2. rifiuta riferimenti da container running;
3. rifiuta riferimenti da container stopped;
4. ripete il controllo immediatamente prima della mutazione.

Dopo una rimozione Docker riuscita verifica che il target esatto sia
effettivamente assente.

Non:

- esegue prune generici;
- elimina container;
- pulisce la cache BuildKit;
- elimina progetti DDEV;
- invoca `sudo`;
- deduce autorità alla mutazione da una classificazione di audit.

## Modello di autorità

Il workflow Storage mantiene intenzionalmente separate evidenza, decisione e
mutazione:

```text
evidenza audit
    ↓
classificazione
    ↓
proposal
    ↓
revisione umana
    ↓
target esatto esplicito
    ↓
preview
    ↓
--apply esplicito
    ↓
rivalidazione
    ↓
mutazione
    ↓
verifica
```

Un candidato non viene mai trattato automaticamente come sicuro da eliminare.

## Privilegi e dipendenze

I tool di inspection e proposal vengono eseguiti come utente corrente e non
invocano `sudo`.

Le operazioni Docker richiedono il normale accesso Docker dell'utente.

Tra le dipendenze standard rilevanti figurano Bash, `sort`, `awk` e `grep`.

## Sensibilità dell'output

La diagnostica storage può contenere path locali dei progetti, riferimenti
Docker, image ID e nomi dei volumi.

Revisionare l'output prima di pubblicarlo o condividerlo.
