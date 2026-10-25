# HANDOVER

Ultimo aggiornamento: 2026-10-25

Elenco dei task e delle richieste: vedi `TODO.md`.

## Obiettivo

- Plugin per **Adobe Lightroom Classic** (SDK Lua) per Giovanni (gio91ber@gmail.com, GitHub `giovariot`).
- Trova le foto del catalogo con il file master danneggiato o mancante, cerca nella cartella scelta dall'utente il file corrispondente, mostra un riepilogo da confermare e sostituisce solo il file sul disco.
- Metadati, sviluppo e date del catalogo non devono cambiare.

## Stato attuale

- Il plugin è scritto e pubblicato sul branch `claude/blissful-curie-0ixde5` del repo `giovariot/lrdamaged`. Nessuna pull request creata (non richiesta). Ultimo commit prima di questo file: "Fix SDK usage found while checking against the official API reference".
- **Mai eseguito dentro Lightroom Classic** (non disponibile nell'ambiente di sviluppo). Interfaccia, chiamate `Lr*` e comportamento reale sono non provati.
- Verificato fuori da Lightroom con Lua 5.1 (libreria Python `lupa`) su file sintetici: decoder DC del JPEG (errore medio ~0,1 su 255), hash dell'anteprima, lettore EXIF su JPEG, NEF, CR3 e MRW, rilevamento di NEF/CR3 troncati, confronto EXIF e controllo di sintassi di tutti i `.lua`. Comandi in `tests/README.md`. Non verificato con RAW reali di fotocamera.
- Ogni chiamata dell'SDK è stata confrontata con il riferimento ufficiale (SDK 5/6) nel repo `giovariot/api-references`, cartella `lightroom-sdk/API-Reference/modules/`. Le correzioni sono elencate in `README.md`, sezione "API di Lightroom utilizzate".
- Non coperti dal riferimento: le chiavi di `Info.lua` e il comportamento di `f:picture` con un percorso di file temporaneo.

## Decisioni prese

- **Si sostituisce solo il file, senza rimuovere e reimportare la foto dal catalogo.** Perché: Giovanni ha chiesto che metadati, editing e date restino identici. Scartata la reimportazione con ripristino dei metadati (perdeva pile, copie virtuali e cronologia di sviluppo).
- **Il file danneggiato non viene cancellato**: va in `_lrdamaged_backup` accanto all'originale; se la copia fallisce c'è rollback.
- **Riconoscimento del sostituto**: stesso nome file, poi confronto EXIF (data, marca, modello, seriale, obiettivo, ISO, focale, diaframma, tempo). Un dato diverso scarta il candidato; la sola data diversa lo declassa a confidenza "bassa" (la data in Lightroom può essere stata modificata). Se l'EXIF manca o è insufficiente: hash percettivo 8x8 (soli coefficienti DC del JPEG, 4 rotazioni) tra l'anteprima di Lightroom e l'anteprima incorporata nel candidato. Altrimenti solo il nome, confidenza "bassa". Scartato un hash dei byte del file: l'anteprima di Lightroom è un'immagine rielaborata, non i byte del file.
- **Conferma obbligatoria** con finestra a due colonne; le righe a confidenza "bassa" partono deselezionate. Tolta la modalità "solo simulazione", resa superflua dalla conferma.
- **Lettore EXIF e decoder JPEG in Lua puro** (l'SDK non legge l'EXIF di file fuori catalogo). Il lettore copre JPEG, RAW basati su TIFF, Fujifilm RAF, Canon CR3, Minolta MRW; non copre Canon CRW, Sigma X3F, HEIC (ricadono su header e nome).
- Il controllo dei troncamenti confronta i dati dichiarati nelle strutture del file (strip, tile, anteprime, box `mdat`) con la dimensione reale.
- Le foto sostituite vengono aggiunte alla collezione `LR Damaged - sostituite` per ricostruire le anteprime (aggiunta senza che fosse richiesta: vedi `TODO.md`, "Da chiarire").

## File e percorsi chiave

- `LrDamaged.lrdevplugin/Info.lua`: manifest; voce di menu in `Libreria > Plug-in Extras`.
- `LrDamaged.lrdevplugin/Main.lua`: flusso completo (opzioni, scansione, indice, candidati, conferma, sostituzione, collezione, log).
- `LrDamaged.lrdevplugin/Integrity.lua`: controlli di integrità e elenco delle estensioni RAW.
- `LrDamaged.lrdevplugin/ExifReader.lua`: EXIF, anteprime incorporate, `maxEnd` per i troncamenti.
- `LrDamaged.lrdevplugin/JpegDC.lua`: decodifica DC del JPEG baseline e hash.
- `LrDamaged.lrdevplugin/Matcher.lua`: confronto EXIF/hash e scelta del candidato; unico punto che legge i metadati del catalogo.
- `LrDamaged.lrdevplugin/Finder.lua`: indice della cartella e candidati con lo stesso nome.
- `LrDamaged.lrdevplugin/Repair.lua`: backup, copia e rollback.
- `LrDamaged.lrdevplugin/Review.lua`: finestra di conferma.
- `README.md`: descrizione per l'utente, formati e verifica delle API. `tests/`: script di prova fuori da Lightroom (`tests/README.md`).
- Riferimento SDK: repo `giovariot/api-references` (privato, branch `main`), clonato in `/home/user/api-references`.
- Installazione in Lightroom: `File > Plug-in Manager > Aggiungi` e scegliere `LrDamaged.lrdevplugin`. Il log di ogni esecuzione è in `Documenti/LrDamaged_<data>.txt`.
- Per eseguire i test: `pip install lupa pillow`, poi i comandi in `tests/README.md`.

## Cose da sapere

- Il Lua di Lightroom è 5.1: niente operatori bit a bit, `goto` o `//`. Il `pcall` normale non può attraversare gli yield: nel codice che chiama l'SDK usare `LrTasks.pcall`.
- `LrFileUtils.recursiveFiles`: non uscire dal ciclo con `break` o `return`. `createAllDirectories` ritorna `true` solo se ha creato qualcosa: verificare con `exists`.
- `getRawMetadata('aperture')` è il denominatore f (es. 2,8) e `shutterSpeed` è in secondi. Le date di scatto si confrontano con `dateTimeOriginalISO8601` (primi 19 caratteri).
- `photo:requestJpegThumbnail` tratta le dimensioni come minimi; il codice scarta anteprime oltre 600 KB.
- Giovanni ha chiesto di **non inventare** funzioni dell'SDK: ogni nuova chiamata va controllata in `api-references`.
- Da questo ambiente non si raggiunge la documentazione online (rete bloccata); creare repo non è consentito all'integrazione GitHub (l'ha creato Giovanni). Nessun segreto nel progetto.
- Messaggi di commit con la riga `Co-Authored-By` e `Claude-Session` come da indicazioni della sessione; non indicare il modello nei file del repo.
- Giovanni usa RAW di Canon, Nikon, Sony, Fujifilm, Pentax, Panasonic "e così via".

## Prossimo passo

- Chiedere a Giovanni di caricare il plugin in Lightroom Classic su una copia del catalogo, provare con poche foto danneggiate e incollare gli errori mostrati; correggerli con il riferimento in `api-references` davanti. Poi risolvere i punti di `TODO.md` sotto "Da chiarire".
