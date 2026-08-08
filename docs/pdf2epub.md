# pdf2epub

`pdf2epub` converte un PDF testuale in EPUB usando una pipeline prudente:

1. estrae il testo con `pdftotext -layout`;
2. ripulisce il flusso e promuove le sezioni riconoscibili;
3. affida a Calibre (`ebook-convert`) la creazione finale dell'EPUB e del sommario.

## Quando usarlo

Usalo quando il PDF contiene testo vero e un'impaginazione ragionevole. Funziona bene con documenti che hanno sezioni, paragrafi e tabelle semplici.

Non è il candidato giusto per PDF scansiti o per impaginazioni molto grafiche, con colonne complesse, box sovrapposti o layout da rivista.

## Requisiti

- `pdftotext`
- `pdfinfo`
- `ebook-convert` (Calibre)
- `python3`

Su Ubuntu i pacchetti utili sono normalmente `poppler-utils` per `pdftotext` e `pdfinfo`, più `calibre` per `ebook-convert`.

## Uso

```bash
pdf2epub "Documento.pdf"
pdf2epub "Documento.pdf" "Documento-smart.epub"
```

Se non passi un output, il comando crea un file con lo stesso nome base e estensione `.epub`.

## Cosa fa in più rispetto a una conversione diretta

- preserva meglio il testo lineare di partenza;
- prova a distinguere i titoli dalle righe di tabella;
- genera un EPUB con sommario automatico più utile;
- evita il più possibile l'effetto “spaghetti tipografico”.

## Limiti

- I PDF restano una fonte imperfetta per gli ebook;
- la qualità dipende molto da come è stato generato il PDF;
- se il documento è una scansione, serve OCR prima della conversione;
- tabelle e layout complessi possono ancora richiedere rifinitura manuale.

## Filosofia operativa

Il comando è pensato per essere leggibile, deterministico e poco sorprendente. Fa una cosa sola, ma cerca di farla bene.