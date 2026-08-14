# weekly-health

`weekly-health` è un orchestratore locale e in sola lettura per i tre
componenti di security health del repository:

1. `security-health`
2. `kernel-health`
3. `security-clamav-scan --yes`

Non duplica la logica interna dei singoli strumenti. Si limita a risolverli,
eseguirli, raccogliere gli status e stampare un riepilogo chiaro.

## Modello di sicurezza

- sola orchestrazione read-only;
- nessun `sudo` e nessuna escalation nascosta;
- nessuna gestione dei pacchetti;
- nessuna attività di rete;
- nessuna riparazione, quarantena o cancellazione;
- nessun tentativo di terminare processi non correlati;
- nessuna installazione automatica degli helper mancanti.

Il report può contenere path sensibili o output del journal perché include
l'output dei componenti chiamati.

## Risoluzione

Lo strumento risolve gli helper in modo conservativo:

- prima preferisce la directory che contiene l'eseguibile `weekly-health` se
  tutti e tre gli helper sono presenti lì;
- altrimenti usa `PATH` solo se tutti gli helper risolvono nella stessa
  directory;
- se la risoluzione manca o è ambigua, il tool fallisce in modo chiuso con exit
  code `2`.

Questo rende equivalenti installazioni via symlink, via copia e via pacchetto,
purché i tre helper siano installati insieme.

## Ordine di esecuzione

L'ordine dei componenti è fisso:

1. `security-health`
2. `kernel-health`
3. `security-clamav-scan --yes`

Il passo di scansione viene sempre eseguito con `--yes`; `weekly-health` non
gestisce una conferma propria sulla durata.

## Contratto degli status

Ogni componente mantiene il proprio exit status nel report.

- `0` - pulito;
- `1` - finding;
- `2` - errore operativo;
- `3` - la scansione ClamAV è stata annullata prima di partire;
- `130` - interrotto da `SIGINT`;
- `143` - terminato da `SIGTERM`.

Regole dello status aggregato:

- qualsiasi `SIGINT` o `SIGTERM` viene propagato come `130` o `143`;
- qualsiasi errore operativo obbligatorio produce status aggregato `2`;
- l'annullamento ClamAV `3` viene trattato come errore aggregato `2` perché la
  scansione non è partita;
- altrimenti, qualsiasi finding produce `1`;
- solo controlli completamente puliti producono `0`.

## Output

Il report usa sezioni ben delimitate per ogni componente e un blocco finale di
riepilogo con lo status dei componenti e quello aggregato.

## Test

I selftest usano helper finti per verificare risoluzione, ordine, propagazione
degli status e gestione dei signal senza toccare il sistema reale.
