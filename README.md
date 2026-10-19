# LR Damaged

Plugin per Adobe Lightroom Classic che individua le immagini danneggiate del catalogo e le sostituisce con
il file omonimo trovato in una cartella scelta dall'utente.

## Installazione
`File > Plug-in Manager > Aggiungi` e seleziona la cartella `LrDamaged.lrdevplugin`.
Uso: `Libreria > Plug-in Extras > Trova e sostituisci immagini danneggiate...`

## Come funziona
1. **Scansione** (foto selezionate o intero catalogo). Una foto è "danneggiata" se il file è mancante, vuoto o
   < 1 KB, ha header non valido (JPEG/PNG/TIFF/RAW/HEIC/RAF), è un JPEG/PNG troncato oppure ha la coda azzerata.
2. **Ricerca e riconoscimento**: la cartella scelta viene indicizzata ricorsivamente; si cercano i file con lo
   stesso nome (case-insensitive) e integri. Ogni candidato viene verificato così:
   - **EXIF** (lettore in Lua puro per JPEG, TIFF e RAW basati su TIFF come CR2/NEF/ARW/DNG/ORF/RW2/PEF, più RAF):
     data di scatto, marca, modello, seriale, obiettivo, ISO, focale, diaframma, tempo, confrontati con i dati del
     catalogo. Un dato diverso scarta il candidato; la sola data diversa lo declassa a confidenza *bassa*.
     Confidenza *alta* = data + almeno altri 2 dati coincidenti; *media* = pochi dati coincidenti.
   - **Se l'EXIF manca o è insufficiente**: hash percettivo (aHash 8x8, confronto di Hamming su 4 rotazioni)
     tra l'anteprima di Lightroom e l'anteprima JPEG incorporata nel candidato. Si decodificano solo i
     coefficienti DC dei blocchi 8x8 (niente IDCT), quindi su una miniatura costa pochi millisecondi.
     Distanza <= 10/64 = *media*, <= 18 = *bassa* (es. foto ritagliata/modificata), oltre = scartato.
   - **Se non è possibile nemmeno questo**: solo nome file, confidenza *bassa*.
   Tra più candidati vince la confidenza più alta, poi il file più grande.
   Non supportati per EXIF/anteprima: CR3, HEIC (ricadono sul solo nome).
2b. **Conferma**: prima di toccare qualsiasi file compare una finestra a due colonne (originale | sostituto, con
   anteprime, motivo e confidenza), con "seleziona/deseleziona tutto" e una casella per ogni riga. Le
   corrispondenze di confidenza bassa partono deselezionate.
3. **Sostituzione**: il file danneggiato viene spostato in `_lrdamaged_backup` accanto all'originale, il
   sostitutivo viene copiato nello stesso percorso e verificato (rollback automatico in caso di errore).
4. **Catalogo invariato**: la voce di catalogo non viene rimossa né reimportata, quindi metadati, date,
   sviluppo, collezioni, pile e copie virtuali restano identici; cambia solo il file master sul disco.
   Le foto sostituite vengono aggiunte alla collezione `LR Damaged - sostituite`: selezionale e usa
   `Libreria > Anteprime > Crea anteprime in formato standard` per rigenerare le anteprime.
   **Non** usare `Leggi metadati dal file` (sovrascriverebbe i metadati del catalogo con quelli del sostituto).
5. Un log viene scritto in `Documenti/LrDamaged_<data>.txt`.

Nulla viene modificato finché non confermi nella finestra di riepilogo; anche le righe non approvate finiscono nel log.

## Limiti noti
- I controlli sono a livello di file, non decodificano i pixel: un RAW corrotto a metà ma con header e coda
  integri non viene rilevato.
- Il sostituto dovrebbe avere stesse dimensioni e orientamento dell'originale, altrimenti ritaglio e sviluppo
  salvati nel catalogo potrebbero non combaciare (il plugin non lo verifica).
- Il codice non è stato eseguito dentro Lightroom Classic (non disponibile nell'ambiente di sviluppo):
  provarlo prima su una copia del catalogo. Il decoder DC e il lettore EXIF sono stati verificati con Lua 5.1
  fuori da Lightroom; interfaccia, `requestJpegThumbnail` e i nomi dei metadati dell'SDK vanno verificati in Lightroom.
- Se in Lightroom hai modificato la data di scatto di una foto, la data non combacerà con l'EXIF del file.
- L'hash dell'anteprima può fallire su foto molto ritagliate o convertite in B/N (finiscono come *bassa*).
