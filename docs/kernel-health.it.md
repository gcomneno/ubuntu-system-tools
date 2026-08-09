# kernel-health

`kernel-health` è un analizzatore locale e completamente read-only dei warning
del kernel su più boot recenti. Raggruppa i warning per firma stabile e descrive
ricorrenza e dinamica quantitativa senza assegnare severity e senza tentare
correzioni automatiche.

## Modello di sicurezza

- sola lettura;
- nessun `sudo` automatico e nessun requisito root imposto dal tool;
- nessuna rete;
- nessun `sysctl`;
- nessuna scrittura in `/proc` o `/sys`;
- nessuna modifica a systemd o journal;
- nessun cleanup o fix automatico.

L'unica sorgente di dati di sistema della versione 1 è `journalctl -k`.

## Uso

```bash
kernel-health
kernel-health --boots 5
kernel-health --help
```

Il default è tre boot recenti. `--boots N` accetta interi positivi.

## Acquisizione

Per ogni boot richiesto il tool esegue l'equivalente di:

```bash
journalctl -k -p warning --boot=0 --no-pager -o cat
journalctl -k -p warning --boot=-1 --no-pager -o cat
```

I boot più vecchi proseguono con `-2`, `-3` e così via.

Un boot precedente non disponibile riduce la coverage ma non fa fallire il
comando. L'impossibilità di leggere il boot corrente è invece un errore
operativo. Il tool non riprova mai con privilegi elevati.

## Classificazione

Vengono riportate solo le firme presenti nel boot corrente.

- `NEW`: presente nel boot corrente e assente nei boot precedenti disponibili.
- `RECURRING`: presente nel boot corrente e in almeno un boot precedente
  disponibile.
- `INCREASING`: ricorrente e supportata da una regola quantitativa esplicita.

Nella versione 1 `INCREASING` si applica soltanto al warning noto
`delayed_fput`. La sequenza del boot corrente deve contenere almeno due valori,
essere strettamente crescente e terminare con un valore almeno doppio del
primo.

Un'analisi riuscita termina con exit status `0` anche in presenza di finding.
Uso non valido o impossibilità di leggere il boot corrente terminano con status
`2`.

## Firma stabile

La normalizzazione è volutamente conservativa.

1. Quando presenti vengono rimossi metadata comuni del journal come timestamp,
   hostname e prefisso `kernel:`.
2. I warning generici restano altrimenti invariati, evitando sostituzioni
   numeriche troppo aggressive che potrebbero fondere eventi diversi.
3. Un parser specifico riconosce:

   `workqueue: delayed_fput hogged CPU for >...us ... times, consider switching to WQ_UNBOUND`

   Per questo warning noto, soglia e contatore sono trattati come campi dinamici.
   La firma mostrata è:

   `workqueue: delayed_fput hogged CPU`

I contatori vengono conservati come sequenze ordinate per boot, ad esempio
`4 → 8 → 16`.

## Output e storico incompleto

Il report mostra la coverage dei boot. Se lo storico precedente non è
accessibile, la classificazione usa solo i boot leggibili e la coverage ridotta
resta visibile.

Eventuali diagnostiche di `journalctl` accompagnate da output comunque
utilizzabile non vengono copiate letteralmente: il report indica soltanto quanti
boot hanno prodotto diagnostiche, evitando di esporre dettagli locali inutili.

## Test

Acquisizione, parsing, normalizzazione, classificazione e rendering sono
separati. I test sostituiscono `journalctl` tramite l'hook interno
`KERNEL_HEALTH_JOURNALCTL`, quindi non dipendono dal journal reale né da
privilegi root.

Le fixture sanitizzate modellano le sequenze `delayed_fput` osservate su tre
boot.

## Evoluzioni escluse dalla v1

La versione 1 non introduce `--json` o `--porcelain`. Un contratto
machine-readable stabile potrà essere aggiunto quando servirà davvero a un
consumer.

Anche l'integrazione con `twr-weekly-health` resta rinviata finché non sarà
piccola e naturale. Parsing e classificazione dei warning devono restare di
proprietà di `kernel-health`, senza duplicazioni nel caller.
