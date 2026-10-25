import lupa.lua51 as lupa
L=lupa.LuaRuntime(unpack_returned_tuples=True)
L.execute(r"""
package.path='/home/user/lrdamaged/LrDamaged.lrdevplugin/?.lua;'..package.path
local stubs={
 LrFileUtils={exists=function(p) local f=io.open(p,'rb') if f then f:close() return 'file' end return false end,
   fileAttributes=function(p) local f=io.open(p,'rb') local s=f:seek('end') f:close() return {fileSize=s} end},
 LrPathUtils={extension=function(p) return p:match('%.([^./]+)$') or '' end},
}
function import(n) return stubs[n] or {} end
local E=require('ExifReader'); local I=require('Integrity'); local J=require('JpegDC')
local function show(p)
  local r,info=E.read(p)
  local ok,why=I.check(p)
  local s=p..': '
  if r then s=s..string.format('%s|%s|%s|iso=%s|f=%s|prev=%d ',tostring(r.make),tostring(r.model),tostring(r.datetime),tostring(r.iso),tostring(r.fnumber),#r.previews) else s=s..'no-exif ' end
  s=s..'maxEnd='..tostring(info and info.maxEnd)..' check='..tostring(ok)..' '..tostring(why)
  if r then local pv=E.extractPreview(p,r); if pv then local dc=J.decode(pv); s=s..' hash='..tostring(dc~=nil) end end
  print(s)
end
for _,p in ipairs{'fake.cr3','trunc.cr3','fake.mrw','good.nef','cut.nef','fake.nef','exif.jpg'} do show(p) end
""")
