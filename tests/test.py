import lupa.lua51 as lupa, io, statistics
from PIL import Image
L = lupa.LuaRuntime(unpack_returned_tuples=True, encoding=None)
L.execute("package.path='/home/user/lrdamaged/LrDamaged.lrdevplugin/?.lua;'..package.path")
J = L.eval("require('JpegDC')"); E = L.eval("require('ExifReader')")
for n in ['a444','a420','arst','prog']:
    data=open(n+'.jpg','rb').read()
    dc=J.decode(data)
    if dc is None: print(n,'decode nil'); continue
    im=Image.open(n+'.jpg').convert('L')
    bw,bh=dc[b'bw'],dc[b'bh']
    errs=[]
    for y in range(bh):
        for x in range(bw):
            blk=im.crop((x*8,y*8,min(x*8+8,im.width),min(y*8+8,im.height)))
            exp=statistics.mean(blk.get_flattened_data() if hasattr(blk,'get_flattened_data') else blk.getdata())
            got=dc[b'grid'][y*dc[b'stride']+x+1]
            errs.append(abs(exp-got))
    print(n,bw,bh,'mean err %.2f max %.2f'%(statistics.mean(errs),max(errs)))
r,_=E.read(b'exif.jpg'); print({k:r[k.encode()] for k in ['make','model','datetime','iso','fnumber','exposure','focal','lens']})
r,_=E.read(b'fake.nef'); print({k:r[k.encode()] for k in ['make','model','datetime','iso','fnumber','exposure','focal']}, len(r[b'previews']))
pv=E.extractPreview(b'fake.nef',r); print(len(pv) if pv else None)
dc=J.decode(pv); h=J.hashes(dc)
im=Image.open('fake.nef') if False else None
# hash: same thumb vs rotated / different
import io
def hashof(img):
    b=io.BytesIO(); img.save(b,'JPEG',quality=70); return J.hashes(J.decode(b.getvalue()))
base=Image.open(io.BytesIO(pv)); 
hb=hashof(base)
hb_rot=hashof(base.rotate(90,expand=True))
hother=hashof(Image.open('a420.jpg'))
def lt(t): return L.table_from([L.table_from(list(t[i].values())) for i in range(1,5)])
print('same',J.distance(hb[1],hb), 'scaled', J.distance(hashof(base.resize((80,60)))[1],hb), 'rot', J.distance(hb_rot[1],hb),'other',J.distance(hother[1],hb))
