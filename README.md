# LR Damaged

Plugin per Adobe Lightroom Classic che individua le immagini danneggiate del catalogo e le sostituisce con
il file omonimo trovato in una cartella scelta dall'utente.

## Installazione
`File > Plug-in Manager > Aggiungi` e seleziona la cartella `LrDamaged.lrdevplugin`.
Uso: `Libreria > Plug-in Extras > Trova e sostituisci immagini danneggiate...`

## Come funziona
1. **Scansione** (foto selezionate o intero catalogo). Una foto è "danneggiata" se il file è mancante, vuoto o
   < 1 KB, ha header non valido (JPEG/PNG/TIFF/RAW/HEIC/RAF), è un JPEG/PNG troncato oppure ha la coda azzerata.
2. **Ricerca**: la cartella scelta viene indicizzata ricorsivamente e si cerca lo stesso nome file
   (case-insensitive). I candidati sono a loro volta controllati; se ce n'è più di uno valido vince il più grande.
3. **Sostituzione**: il file danneggiato viene spostato in `_lrdamaged_backup` accanto all'originale, il
   sostitutivo viene copiato nello stesso percorso e verificato (rollback automatico in caso di errore).
4. **Reimportazione** (modalità predefinita): la voce di catalogo viene rimossa e il file riaggiunto,
   riapplicando rating, etichetta colore, flag, titolo/didascalia, parole chiave, collezioni (non smart)
   e impostazioni di sviluppo. Non vengono ripristinati: pile, cronologia sviluppo, copie virtuali, posizione in griglia.
   In alternativa "solo file": il catalogo resta intatto e si usa `Metadati > Leggi metadati dal file`.
5. Un log viene scritto in `Documenti/LrDamaged_<data>.txt`.

La **simulazione** è attiva di default: non tocca nulla e produce solo il log.

## Limiti noti
- I controlli sono a livello di file, non decodificano i pixel: un RAW corrotto a metà ma con header e coda
  integri non viene rilevato.
- Il codice non è stato eseguito dentro Lightroom Classic (non disponibile nell'ambiente di sviluppo):
  provarlo prima su una copia del catalogo e con la simulazione.
