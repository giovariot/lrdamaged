# TODO

Ultimo aggiornamento: 2026-10-25

## Richieste

- [fatto] Controllare le logiche del plugin e fare domande su finalità e problemi (il repo era vuoto: ho chiesto il codice e posto le domande).
- [in corso] Plugin per Lightroom Classic che identifichi le immagini danneggiate e permetta di scegliere una cartella dove trovare lo stesso file e sostituirlo, "ricaricandolo su Lightroom stesso". Implementato in `LrDamaged.lrdevplugin/`; **non ancora provato dentro Lightroom Classic** (serve Giovanni).
- [fatto] "I metadati, gli editing e le date devono rimanere uguali all'originale, quello che deve cambiare è solo il master danneggiato": la voce di catalogo non viene toccata, si sostituisce solo il file sul disco.
- [fatto] Riconoscere il file sostitutivo con i dati EXIF completi oltre al nome; se l'EXIF manca, confrontare la preview presente in Lightroom con il file tramite un hashing molto rapido.
- [fatto] Prima di sostituire, una finestra a due colonne (originali / sostituiti) con un controllo per selezionare o deselezionare tutto e la possibilità di deselezionare le singole sostituzioni.
- [fatto] Supportare tutti i formati RAW supportati da Lightroom (Canon, Nikon, Sony, Fujifilm, Pentax, Panasonic...).
- [in corso] Verificare che il codice Lua usi funzioni effettive di Lightroom (ufficiali e non), senza inventarne. Confrontato con il riferimento SDK 5/6 e corretto; resta la prova reale in Lightroom.
- [fatto] Creare un repo privato `API-references` su GitHub e caricarci la cartella `lightroom-sdk` (pagine scaricate da Giovanni): `giovariot/api-references`, branch `main`.
- [fatto] Eseguire le regole di precompressione (`TODO.md` e `HANDOVER.md` nella radice del progetto).

## Task di Claude

- [da fare] Provare il plugin in Lightroom Classic su una copia del catalogo e correggere gli errori che compaiono (richiesta: plugin Lightroom e verifica funzioni). Serve Giovanni, che incolla il testo degli errori.
- [da fare] Verificare che `f:picture` accetti il percorso di un file temporaneo come anteprima del sostituto; se no, usare un'alternativa (richiesta: finestra a due colonne). La documentazione descrive il valore come risorsa del plugin.
- [da fare] Provare il lettore EXIF e il controllo dei troncamenti con RAW reali delle marche usate da Giovanni, non solo con file sintetici (richiesta: tutti i RAW).
- [da fare] Aggiungere EXIF e anteprima per Canon CRW, Sigma X3F e HEIC, oggi gestiti solo dall'header e dal nome (richiesta: tutti i RAW). Opzionale.
- [da fare] Se il catalogo ha migliaia di foto danneggiate, impaginare la finestra di conferma, che oggi le mostra tutte insieme (richiesta: finestra a due colonne). Opzionale.

## Da chiarire

- Tipo di danno più frequente: file troncati o copiati a metà, oppure corrotti all'interno (RAW con header e coda integri)? Non ha risposto. Nel secondo caso i controlli attuali non lo rilevano e servirebbe un controllo sui pixel.
- La collezione `LR Damaged - sostituite`, dove finiscono le foto sostituite per rigenerare le anteprime, l'ho aggiunta io senza che fosse richiesta. Va bene tenerla o la togliamo?
- Le regole di precompressione valgono "in ogni progetto": vuole `TODO.md` e `HANDOVER.md` anche nel repo `giovariot/api-references`, che contiene solo documentazione? Per ora li ho messi solo in `lrdamaged`.
