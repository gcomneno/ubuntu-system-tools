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

### `who-uses`
Trova dove un pacchetto, una dipendenza, un binario o un identificatore è referenziato.

### `security-health`
Legge eventi rilevanti del journal locale, inclusi sudo, login/logout e warning kernel.

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
