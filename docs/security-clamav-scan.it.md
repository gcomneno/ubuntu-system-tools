# security-clamav-scan

`security-clamav-scan` è uno scanner ClamAV locale e in sola lettura per
directory dell'utente e per una scansione completa esplicita. Non esegue
riparazioni, quarantene o cancellazioni.

## Modello di sicurezza

- sola lettura;
- nessun `sudo` e nessuna escalation nascosta;
- nessuna installazione di pacchetti, nessun `freshclam`, nessun download di
  firme;
- nessuna quarantena, copia, spostamento o cancellazione dei file scansionati;
- nessuna rete implicita;
- `clamscan` ricorsivo con scansione su altri filesystem disabilitata;
- lock non bloccante per utente per rifiutare esecuzioni concorrenti;
- i log possono contenere path e nomi file sensibili.

Per default il tool scrive solo log ausiliari sotto una directory di stato
controllata dall'utente, salvo che venga fornito `--log-dir`.

## Uso

```bash
security-clamav-scan
security-clamav-scan --target /percorso/directory
security-clamav-scan --full --yes
security-clamav-scan --log-dir /tmp/clamav-logs
```

Opzioni:

- `--target PATH` scansiona una directory in modo ricorsivo; ripetibile; i
  target espliciti sostituiscono i target predefiniti;
- `--full` scansiona `/` in modo ricorsivo e mostra un avviso molto visibile;
- `--log-dir PATH` scrive i log nella directory indicata;
- `--yes` salta solo la conferma sulla durata;
- `-h`, `--help` mostra l'help.

## Ambito

I target predefiniti vengono usati solo se esistono e solo se non viene fornito
un target esplicito:

- `$HOME/Downloads`;
- `$HOME/Desktop` oppure `$HOME/Scrivania`;
- `$HOME/Documents`.

Lo strumento non include implicitamente `/tmp`, `/var/tmp` o altri path di
sistema. Se nessun target predefinito è disponibile, il comando fallisce in
modo chiuso invece di allargare l'ambito.

I valori passati con `--target` devono identificare directory esistenti. Il tool
rifiuta target mancanti, ambigui o che amplierebbero l'ambito tramite symlink.

`--full` seleziona esplicitamente `/` ed è l'unica modalità che può scansionare
l'albero completo del filesystem.

## Log

La directory di log predefinita è:

```text
${XDG_STATE_HOME:-$HOME/.local/state}/ubuntu-system-tools/clamav/
```

Ogni esecuzione crea un file separato in quella directory. I log sono
deliberatamente dettagliati per essere consultabili dopo la scansione, quindi
possono contenere path e nomi file locali. Non condividerli senza controllo.

Se la directory di log non è creabile o scrivibile, il comando termina con exit
code `2`.

## Requisiti ClamAV

`security-clamav-scan` è volutamente ristretto. Si aspetta uno scanner ClamAV
installato dall'utente e database di firme locali, ma non installa né aggiorna
niente da solo.

L'implementazione controlla le directory locali delle firme e fallisce in modo
chiuso se non trova database utilizzabili. Non esegue `freshclam`.

## Concorrenza

Un lock `flock` non bloccante per utente impedisce esecuzioni concorrenti:

- se il lock è già occupato, il comando fallisce con exit `2`;
- il tool non termina altri processi per prendere il lock;
- la pulizia del lock è automatica all'uscita e sui signal.

## Exit code

- `0` - scansione completata e pulita;
- `1` - ClamAV ha rilevato una detection; nessun file è stato modificato;
- `2` - uso non valido o errore operativo;
- `3` - l'utente ha annullato prima della scansione;
- `130` - interrotto da `SIGINT`;
- `143` - terminato da `SIGTERM`.

L'annullamento prima della scansione non viene mai riportato come clean.

## Avviso full-scan

`--full` mostra un avviso prominente prima che la scansione inizi. La conferma è
interattiva salvo `--yes`.

## Test

I selftest usano `clamscan` finto e directory HOME/XDG isolate, così la CI non
ha bisogno di una vera installazione ClamAV né di campioni malware.
