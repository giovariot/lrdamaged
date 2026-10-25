import struct, io, random
from PIL import Image, ImageDraw
import os
exec(open(os.path.join(os.path.dirname(os.path.abspath(__file__)),'gen.py')).read().split("for name,sub,kw")[0])
tb=io.BytesIO(); make(9).save(tb,'JPEG',quality=80); tb=tb.getvalue()
pv=io.BytesIO(); make(9,640,480).save(pv,'JPEG',quality=80); pv=pv.getvalue()
def ent(tag,typ,cnt,val): return struct.pack('<HHI',tag,typ,cnt)+val
def tiff_ifd0(make,model,exif_off=None):
    # tiny TIFF: header + IFD0(make, model) 
    ms=make+b'\0'; md=model+b'\0'
    n=2; ifd_len=2+n*12+4
    d0=8+ifd_len
    ifd=struct.pack('<H',n)+ent(0x10F,2,len(ms),struct.pack('<I',d0))+ent(0x110,2,len(md),struct.pack('<I',d0+len(ms)))+struct.pack('<I',0)
    return b'II*\0'+struct.pack('<I',8)+ifd+ms+md
def tiff_exif():
    dt=b'2023:07:08 09:10:11\0'
    n=3; ifd_len=2+n*12+4; d0=8+ifd_len
    ifd=struct.pack('<H',n)+ent(0x8827,3,1,struct.pack('<HH',1600,0))+ent(0x9003,2,len(dt),struct.pack('<I',d0))+ent(0x829D,5,1,struct.pack('<I',d0+len(dt)))+struct.pack('<I',0)
    return b'II*\0'+struct.pack('<I',8)+ifd+dt+struct.pack('<II',56,10)
def box(t,payload): return struct.pack('>I',8+len(payload))+t+payload
canon=bytes([0x85,0xC0,0xB6,0x87,0x82,0x0F,0x11,0xE0,0x81,0x11,0xF4,0xCE,0x46,0x2B,0x6A,0x48])
prvwg=bytes([0xEA,0xF4,0x2B,0x5E,0x1C,0x98,0x4B,0x88,0xB9,0xFB,0xB7,0xDC,0x40,0x6E,0x4D,0x16])
cmt=box(b'CMT1',tiff_ifd0(b'Canon',b'Canon EOS R6'))+box(b'CMT2',tiff_exif())+box(b'THMB',struct.pack('>IHHII',0,160,120,len(tb),0)+tb)
moov=box(b'moov',box(b'uuid',canon+cmt))
prvw=box(b'uuid',prvwg+box(b'PRVW',struct.pack('>IHHHH',0,1,640,480,0)+struct.pack('>I',len(pv))+pv))
ftyp=box(b'ftyp',b'crx \0\0\0\1crx isom')
mdat=box(b'mdat',bytes(random.getrandbits(8) for _ in range(20000)))
open('fake.cr3','wb').write(ftyp+moov+prvw+mdat)
open('trunc.cr3','wb').write((ftyp+moov+prvw+mdat)[:-9000])
# MRW
tt=tiff_ifd0(b'MINOLTA',b'DiMAGE A2')
mrw=b'\0MRM'+struct.pack('>I',8+len(tt))+b'\0TTW'+struct.pack('>I',len(tt))+tt+b'\0PRD'+struct.pack('>I',4)+b'xxxx'
# dataOffset counts bytes after the 8 byte header
mrw=b'\0MRM'+struct.pack('>I',8+len(tt)+8+4)+b'\0TTW'+struct.pack('>I',len(tt))+tt+b'\0PRD'+struct.pack('>I',4)+b'xxxx'+bytes(2000)
open('fake.mrw','wb').write(mrw)
# truncated NEF-like: strip declared beyond EOF
def strip_tiff(total_strip):
    n=4; ifd_len=2+n*12+4; d0=8+ifd_len
    ifd=struct.pack('<H',n)+ent(0x103,3,1,struct.pack('<HH',1,0))+ent(0x111,4,1,struct.pack('<I',d0))+ent(0x117,4,1,struct.pack('<I',total_strip))+ent(0x10F,2,6,struct.pack('<I',0))+struct.pack('<I',0)
    return b'II*\0'+struct.pack('<I',8)+ifd
raw=strip_tiff(30000)+bytes(random.getrandbits(8) for _ in range(30000))
open('good.nef','wb').write(raw); open('cut.nef','wb').write(raw[:20000])
