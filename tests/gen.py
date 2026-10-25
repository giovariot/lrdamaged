import struct, io, random
from PIL import Image, ImageDraw, ImageFilter
from PIL.TiffImagePlugin import IFDRational
random.seed(1)
def make(seed, w=160, h=120):
    random.seed(seed)
    im = Image.new('RGB',(w,h),(random.randint(0,255),)*3)
    d = ImageDraw.Draw(im)
    for _ in range(12):
        x0,y0=random.randint(0,w),random.randint(0,h)
        d.rectangle([x0,y0,x0+random.randint(10,80),y0+random.randint(10,80)],fill=tuple(random.randint(0,255) for _ in range(3)))
    return im.filter(ImageFilter.GaussianBlur(2))
for name,sub,kw in [('a444',0,{}),('a420',2,{}),('arst',2,{'restart_marker_blocks':3})]:
    make(5, 200, 133).save(name+'.jpg', quality=85, subsampling=sub, **kw)
make(5,200,133).save('prog.jpg', progressive=True)
# JPEG with EXIF
ex = Image.Exif()
ex[0x010F]='Canon'; ex[0x0110]='EOS R5'
ei = ex.get_ifd(0x8769)
ei[0x9003]='2021:06:05 14:03:09'; ei[0x829A]=IFDRational(1,250); ei[0x829D]=IFDRational(28,10); ei[0x8827]=400; ei[0x920A]=IFDRational(85,1); ei[0xA434]='RF85mm'
make(7,320,240).save('exif.jpg', quality=90, exif=ex)

# Minimal TIFF "raw" with IFD0 + ExifIFD + IFD1 thumbnail
thumb = io.BytesIO(); make(9).save(thumb,'JPEG',quality=80); tb=thumb.getvalue()
def ent(tag,typ,cnt,val): return struct.pack('<HHI',tag,typ,cnt)+val
def build():
    make_s=b'NIKON CORPORATION\0'; model_s=b'NIKON D850\0'
    # layout: header(8) IFD0(2+4*12+4) ExifIFD(2+5*12+4) IFD1 ... then data
    ifd0_off=8; n0=4; ifd0_len=2+n0*12+4
    exif_off=ifd0_off+ifd0_len; ne=5; exif_len=2+ne*12+4
    ifd1_off=exif_off+exif_len; n1=2; ifd1_len=2+n1*12+4
    data_off=ifd1_off+ifd1_len
    make_off=data_off; model_off=make_off+len(make_s)
    dt=b'2022:01:02 03:04:05\0'; dt_off=model_off+len(model_s)
    rat_off=dt_off+len(dt)  # exposure rational, fnumber rational
    rats=struct.pack('<II',1,500)+struct.pack('<II',4,1)+struct.pack('<II',200,1)
    thumb_off=rat_off+len(rats)
    ifd0=struct.pack('<H',n0)+ent(0x10F,2,len(make_s),struct.pack('<I',make_off))+ent(0x110,2,len(model_s),struct.pack('<I',model_off))+ent(0x112,3,1,struct.pack('<HH',1,0))+ent(0x8769,4,1,struct.pack('<I',exif_off))+struct.pack('<I',ifd1_off)
    exif=struct.pack('<H',ne)+ent(0x829A,5,1,struct.pack('<I',rat_off))+ent(0x829D,5,1,struct.pack('<I',rat_off+8))+ent(0x8827,3,1,struct.pack('<HH',800,0))+ent(0x9003,2,len(dt),struct.pack('<I',dt_off))+ent(0x920A,5,1,struct.pack('<I',rat_off+16))+struct.pack('<I',0)
    ifd1=struct.pack('<H',n1)+ent(0x201,4,1,struct.pack('<I',thumb_off))+ent(0x202,4,1,struct.pack('<I',len(tb)))+struct.pack('<I',0)
    return b'II*\0'+struct.pack('<I',8)+ifd0+exif+ifd1+make_s+model_s+dt+rats+tb
open('fake.nef','wb').write(build())
