# Test fuori da Lightroom

Verificano con Lua 5.1 (via `pip install lupa pillow`) la parte che non dipende dall'SDK: lettore EXIF, decoder DC/hash,
controlli di integrità e confronto EXIF. Non provano interfaccia e chiamate `Lr*` (servono Lightroom Classic).

```
mkdir -p /tmp/lrt && cd /tmp/lrt
python3 <repo>/tests/gen.py && python3 <repo>/tests/gen2.py     # genera JPEG/NEF/CR3/MRW sintetici
python3 <repo>/tests/test.py     # decoder DC (errore medio ~0.1/255), EXIF JPEG/NEF, hash
python3 <repo>/tests/test2.py    # Integrity + EXIF su CR3, MRW, NEF troncato
python3 <repo>/tests/syn.py      # sintassi di tutti i .lua + compareExif/decideFromExif
```
Gli script usano il percorso `/home/user/lrdamaged/LrDamaged.lrdevplugin`: se il repo è altrove, sostituiscilo.
