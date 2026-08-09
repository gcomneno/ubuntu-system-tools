# Pacchetto release Linux

[English](linux-release-package.md) | [Italiano]

I pacchetti ufficiali di release vengono pubblicati **solo per Linux**.

Per la v0.3.0 gli asset della release sono:

- `ubuntu-system-tools-v0.3.0-linux.tar.gz`
- `ubuntu-system-tools-v0.3.0-linux.tar.gz.sha256`

L'archivio è indipendente dall'architettura: contiene le utility shell/Python del repository come file eseguibili, non binari compilati.

## Verificare il download

Tenere archivio e file di checksum nella stessa directory, quindi eseguire:

```bash
sha256sum -c ubuntu-system-tools-v0.3.0-linux.tar.gz.sha256
```

Non installare un archivio il cui checksum non risulti valido.

## Estrarre

```bash
tar -xzf ubuntu-system-tools-v0.3.0-linux.tar.gz
cd ubuntu-system-tools-v0.3.0-linux
```

## Installazione locale utente

Il prefisso predefinito è `~/.local`, quindi gli strumenti vengono copiati in `~/.local/bin`:

```bash
./install.sh
```

L'installer della release usa **copie eseguibili autonome**. Non crea collegamenti simbolici verso il pacchetto estratto.

Se `~/.local/bin` non è già presente nel `PATH`, aggiungerlo con la normale configurazione della propria shell.

## Prefisso personalizzato

Usare un percorso assoluto:

```bash
./install.sh --prefix "$HOME/tools"
```

Per un'installazione di sistema, l'elevazione dei privilegi deve rimanere esplicita ed esterna all'installer:

```bash
sudo ./install.sh --prefix /usr/local
```

`install.sh` non invoca mai `sudo` internamente.

## File esistenti e `--force`

Prima di copiare qualsiasi file, l'installer verifica tutte le destinazioni.

- i file regolari identici sono accettati;
- file divergenti e symlink vengono rifiutati;
- se il preflight fallisce non viene eseguita un'installazione parziale;
- `--force` è disponibile soltanto per una destinazione verificata esplicitamente.

```bash
./install.sh --force
```

## Dipendenze

Il pacchetto **non** installa automaticamente dipendenze del sistema operativo o Python. Ogni strumento mantiene lo stesso contratto di dipendenze documentato nel repository.

Tra gli esempi: Calibre per le conversioni ebook reali, CUPS per la diagnostica delle stampanti e `faster-whisper` per la trascrizione audio.

## Disinstallazione

L'installer registra un manifest SHA-256 sotto il prefisso scelto e installa un disinstallatore sicuro versionato.

Con il prefisso predefinito:

```bash
~/.local/share/ubuntu-system-tools/uninstall-v0.3.0.sh
```

Con un prefisso personalizzato:

```bash
/percorso/prefisso/share/ubuntu-system-tools/uninstall-v0.3.0.sh --prefix /percorso/prefisso
```

Il disinstallatore verifica tutti gli strumenti installati prima di rimuovere qualsiasi cosa. Se un file è cambiato dopo l'installazione, la rimozione viene rifiutata a meno di passare esplicitamente `--force` dopo averlo verificato.

## Creare il pacchetto dai sorgenti

Su Linux:

```bash
make package-linux VERSION=v0.3.0
```

La directory di output predefinita è `dist/`. Il builder produce sia l'archivio `.tar.gz` sia il relativo file `.sha256`. Build ripetute dallo stesso albero sorgente sono byte-identiche.

## Non previsto nella v0.3.0

La release v0.3.0 non pubblica intenzionalmente:

- pacchetti Windows;
- pacchetti macOS;
- pacchetti `.deb`;
- Snap;
- Flatpak;
- AppImage.
