import lupa.lua51 as lupa, glob
L=lupa.LuaRuntime(encoding=None)
for f in sorted(glob.glob('/home/user/lrdamaged/LrDamaged.lrdevplugin/*.lua')):
    r=L.eval("function(p) local f,e=loadfile(p) return f and 'ok' or e end")(f.encode())
    print(f.split('/')[-1], r)
L.execute(r"""
package.path='/home/user/lrdamaged/LrDamaged.lrdevplugin/?.lua;'..package.path
function import(n) return {currentTime=os.time, sleep=function() end, pcall=pcall} end
M=require('Matcher')
local meta={datetime='2022-01-02T03:04:05',make='NIKON CORPORATION',model='NIKON D850',iso=800,focal=200,aperture=4,shutter=0.002}
local ex={datetime='2022-01-02T03:04:05',make='NIKON CORPORATION',model='NIKON D850',iso=800,focal=200,fnumber=4,exposure=0.002}
print(M.decideFromExif(M.compareExif(meta,ex)))
meta.shutter=0.002
ex.exposure=1/512; print(M.decideFromExif(M.compareExif(meta,ex)))
meta.aperture=4 -- Av 4 -> f/4
ex.fnumber=4; print(M.decideFromExif(M.compareExif(meta,ex)))
ex.iso=400; print(M.decideFromExif(M.compareExif(meta,ex)))
ex.iso=800; ex.datetime='2022-01-02T03:04:06'; print(M.decideFromExif(M.compareExif(meta,ex)))
ex.datetime=nil; print(M.decideFromExif(M.compareExif({make='x'},{make='x'})))
""")
