# pdf2epub

[English](pdf2epub.md) | **Italiano**

`pdf2epub` converte un PDF testuale in EPUB con una pipeline prudente:

1. estrae il testo con `pdftotext -layout`;
2. pulisce il flusso e prova a promuovere le sezioni riconoscibili;
3. affida a Calibre (`ebook-convert`) la generazione finale dell'EPUB e del sommario.

## Quando usarlo

Usalo quando il PDF contiene testo vero e un'impaginazione ragionevole. Va bene per documenti con sezioni, paragrafi e tabelle semplici.

Non è il candidato giusto per PDF scansiti o per layout molto grafici, con colonne complesse, box sovrapposti o impaginazioni da rivista.

## Requisiti

- `pdftotext`
- `pdfinfo`
- `ebook-convert` (Calibre)
- `python3`

Su Ubuntu, i pacchetti utili sono in genere `poppler-utils` per `pdftotext` e `pdfinfo`, più `calibre` per `ebook-convert`.

## Uso

```bash
pdf2epub "Documento.pdf"
pdf2epub "Documento.pdf" "Documento-smart.epub"
```

Se non passi un output, il comando crea un file con lo stesso nome base e estensione `.epub`.

## Vantaggi rispetto alla conversione diretta

- preserva meglio il testo lineare di partenza;
- prova a distinguere i titoli dalle righe di tabella;
- genera un EPUB con sommario automatico più utile;
- riduce l'effetto “spaghetti tipografico”.

## Limiti

- non fa OCR;
- non può ricostruire perfettamente layout molto complessi;
- il risultato dipende molto dalla qualità del layer testuale nel PDF.
