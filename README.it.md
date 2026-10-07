# ubuntu-system-tools

[English](README.md) | **Italiano**

Una raccolta di utility di sistema conservative per Ubuntu e Linux.

Il progetto privilegia strumenti piccoli, componibili e prevedibili, con dipendenze minime e comportamento CLI stabile.

## Filosofia

- lettura di default
- scrittura solo su richiesta esplicita
- nessuna escalation nascosta
- operazioni distruttive solo dopo conferma
- comportamento deterministico

## Installazione

Clona il repository:

```bash
git clone https://github.com/gcomneno/ubuntu-system-tools
cd ubuntu-system-tools
```

Installazione consigliata in modalità sviluppo, con link simbolici in `~/.local/bin`:

```bash
make install PREFIX=$HOME/.local
```

Se preferisci copie autonome:

```bash
make install-copy PREFIX=$HOME/.local
```

Installazione di sistema:

```bash
make install-system
```

Rimozione di un'installazione locale:

```bash
make uninstall PREFIX=$HOME/.local
```

## Esempi rapidi

Controllo eventi di sicurezza recenti:

```bash
security-health --since "24 hours ago"
```

Scansione ClamAV locale delle cartelle personali più comuni:

```bash
security-clamav-scan --yes
```

Esecuzione del controllo settimanale read-only:

```bash
weekly-health
```

Trascrizione locale di un messaggio audio:

```bash
audio-transcribe --doctor
audio-transcribe --language it --allow-download message.ogg
```

Ricerca dell'uso di un simbolo o dipendenza:

```bash
who-uses scan requests
```

Anteprima di file rigenerabili per sviluppatori:

```bash
hdd_cleanup
```

Scansione dei file di sviluppo eliminabili senza cancellare nulla:

```bash
garbage-collector ~/Progetti --max-depth 4
```

Controllo dello stato storage, dei progetti più grandi e della crescita rispetto a un checkpoint:

```bash
storage-check
storage-check --save-checkpoint "$HOME/.cache/ubuntu-system-tools/storage.env"
storage-check --checkpoint "$HOME/.cache/ubuntu-system-tools/storage.env"
storage-check --docker --ddev
storage-cleanup image IMAGE_REF_OR_ID
storage-cleanup volume VOLUME_NAME
storage-cleanup-proposal
```

Diagnosi di una coda CUPS:

```bash
printer-doctor doctor
```

Rimozione controllata di un pacchetto APT/dpkg:

```bash
safe-uninstall purge anydesk
```

Conversione di un PDF testuale in EPUB:

```bash
pdf2epub "Documento.pdf"
pdf2epub "Documento.pdf" "Documento-smart.epub"
```

## Strumenti inclusi

### `safe-uninstall`
Analizza e rimuove pacchetti APT/dpkg con un piano completo prima di qualsiasi modifica. Non gestisce Snap, Flatpak, AppImage, Docker o software installato manualmente.

### `hdd_cleanup`
Individua artefatti rigenerabili come `node_modules/`, `.venv/`, `target/` e cache comuni.

### `garbage-collector`
Scanner in sola lettura per artefatti eliminabili e spazio recuperabile stimato.

### `storage-check`

Vedi la guida completa del workflow: [Workflow Storage](docs/storage.it.md).

L'orchestratore storage resta read-only per impostazione predefinita. I flag
opzionali `--docker` e `--ddev` delegano ai tool dedicati
`storage-docker-audit` e `storage-ddev-audit`. Gli audit classificano
l'evidenza in modo conservativo come `ACTIVE`, `INACTIVE_PROTECTED`,
`STALE_CANDIDATE` oppure `UNKNOWN`; i layer Docker-only e DDEV-only non
promuovono mai un artefatto a `STALE_CONFIRMED`.

`storage-docker-audit` ispeziona storage Docker, riferimenti di
container/immagini/volumi e cache BuildKit senza eseguire operazioni
prune/remove. `storage-ddev-audit` correla registry DDEV, root dei progetti,
evidenza dei worktree Git e metadata approot generati. Un path generato
obsoleto viene riportato come `DDEV_METADATA_STATE=STALE_PATH`: non costituisce
autorità alla cancellazione.

### `storage-cleanup`

`storage-cleanup` è un tool controlled-action separato e safe-by-default. Non
usa `STALE_CANDIDATE` come autorità alla cancellazione e intenzionalmente non è
una modalità mutante di `storage-check`.

Accetta esattamente un target Docker di tipo immagine o volume. L'invocazione
predefinita produce soltanto una preview read-only. La mutazione richiede lo
stesso target esatto più `--apply`.

Prima di una rimozione applicata risolve il target, rifiuta riferimenti da
container sia running sia stopped e ripete il controllo immediatamente prima
di invocare Docker. Dopo una rimozione Docker riuscita verifica che il target
esatto sia effettivamente assente.

Operazioni supportate:

    storage-cleanup image IMAGE_REF_OR_ID
    storage-cleanup image IMAGE_REF_OR_ID --apply

    storage-cleanup volume VOLUME_NAME
    storage-cleanup volume VOLUME_NAME --apply

Il tool non esegue prune, non elimina container, non pulisce la cache BuildKit,
non effettua cancellazioni DDEV, non invoca `sudo` e non deduce autorità alla
mutazione da una classificazione di audit.

### `storage-cleanup-proposal`

`storage-cleanup-proposal` è un bridge read-only tra l'evidenza dell'audit
Docker e la revisione umana esplicita. Consuma esclusivamente record Docker
`STALE_CANDIDATE` relativi a immagini e volumi e produce un manifest di
proposal deterministico.

Il proposal layer non concede autorità alla cancellazione:

    STALE_CANDIDATE != STALE_CONFIRMED
    PROPOSAL != AUTHORITY

Per le immagini il proposal usa l'ID Docker immutabile invece di un tag
modificabile. Per i volumi usa il nome esatto del volume.

Ogni proposal contiene soltanto un comando di preview, per esempio:

    storage-cleanup image IMAGE_ID
    storage-cleanup volume VOLUME_NAME

Il tool non emette mai `--apply`, non effettua mutazioni Docker o DDEV, non
propone la cache BuildKit e fallisce chiuso se la sorgente dell'audit Docker
non dichiara esplicitamente sia `STALE_CONFIRMED_COUNT=0` sia
`AUTOMATIC_DELETION=NO`.

Il manifest riporta sempre:

    REVIEW_REQUIRED=YES
    AUTHORITY=NO
    AUTOMATIC_DELETION=NO

Il tool viene eseguito come utente corrente, non invoca mai `sudo` e richiede
l'helper `storage-docker-audit` insieme ai comandi standard `sort`, `awk` e
`grep`. L'audit delegato richiede il normale accesso Docker dell'utente.

Riferimenti Docker locali e nomi dei volumi possono comparire nell'output
diagnostico; il proposal va quindi revisionato prima di essere pubblicato.

Controllo in sola lettura dello stato storage e dell'attribuzione della crescita.

Caratteristiche:

- stato del filesystem root e spazio disponibile
- misura di `$HOME`, `/var` e della root progetti quando completamente leggibili
- individuazione dei progetti più grandi con soglie configurabili
- confronto con un checkpoint esplicito
- `--save-checkpoint` scrive esclusivamente il file di checkpoint selezionato
- le misure incomplete vengono riportate come `UNAVAILABLE`
- nessuna cancellazione e nessuna cleanup automatica

La root progetti predefinita è `$PROJECTS_DIR`, se definita, altrimenti
`$HOME/Progetti`.

Override opzionali:

```text
STORAGE_ROOT_WARN_PERCENT
STORAGE_PROJECT_ELEPHANT_MIN_BYTES
STORAGE_PROJECT_ELEPHANT_MAX_DEPTH
```

Exit status `1`: controllo completato ma soglia di utilizzo root raggiunta.
Exit status `2`: input non valido, checkpoint malformato o errore operativo.

### `who-uses`
Trova dove un pacchetto, una dipendenza, un binario o un identificatore è referenziato.

### `security-health`
Legge eventi rilevanti del journal locale, inclusi sudo, login/logout e warning kernel.

### `security-clamav-scan`
Scansione ClamAV sicura e in sola lettura per cartelle locali dell'utente, oppure
per una scansione esplicita di `/`.

Caratteristiche:

- lettura ricorsiva e sola lettura
- target predefiniti: `Downloads`, `Desktop` oppure `Scrivania`, e `Documents`
- modalità `--full` esplicita per `/`, con avviso chiaro sulle scansioni lunghe
- lock non bloccante per utente per rifiutare le esecuzioni concorrenti
- log sotto XDG state di default
- nessuna quarantena, nessuna cancellazione, nessun `freshclam`, nessuna gestione automatica dei pacchetti

### `weekly-health`
Orchestrazione portabile settimanale per `security-health`, `kernel-health` e
`security-clamav-scan --yes`.

Caratteristiche:

- risoluzione rigorosa degli helper con fallimento su ambiguità
- preserva gli exit code dei componenti nel riepilogo
- riporta uno status aggregato `0`, `1`, `2`, `130` o `143`
- non duplica la logica dei singoli strumenti

### `printer-doctor`
Diagnosi e recupero per code CUPS.

### `audio-transcribe`
Trascrizione locale con `faster-whisper`, senza download automatici del modello.

### `bulk-epub-to-azw3`
Conversione in massa di ebook con Calibre, con modalità `dry-run`, `preflight`, manifest, quarantena e debug.

### `pdf2epub`
Convertitore prudente da PDF testuale a EPUB, basato su `pdftotext -layout` + pulizia del flusso + `ebook-convert`.

## Requisiti

- Bash
- Python 3
- `ripgrep` (`rg`)
- Calibre (`ebook-convert`) per le conversioni reali
- `unzip` per il preflight EPUB
- `faster-whisper` solo per `audio-transcribe`

## Obiettivi di progetto

- piccolo
- comprensibile
- scriptabile
- deterministico
- sicuro per impostazione predefinita

## Cosa il repository non fa

- nessuna installazione automatica
- nessuna azione distruttiva senza opt-in
- nessuna escalation nascosta
- nessuna orchestrazione pesante o non richiesta

## Stato

Stabile, volutamente piccolo e in evoluzione lenta.

## Nota di sicurezza

Gli strumenti lavorano solo in locale. Alcuni comandi possono mostrare informazioni sensibili: verifica sempre l'output prima di condividerlo.

## Policy

Vedi `POLICY.md`.
