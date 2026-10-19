-- Lettore EXIF minimale in Lua puro (nessuna dipendenza dall'SDK di Lightroom).
-- Supporta: JPEG (APP1/Exif), TIFF e RAW basati su TIFF (CR2, NEF, NRW, ARW, SR2, SRF, DNG, ORF, RW2, RWL,
-- PEF, SRW, 3FR, FFF, IIQ, ERF, MEF, KDC, DCR, MOS, GPR...), Fujifilm RAF, Canon CR3 (ISO-BMFF), Minolta MRW.
-- Non supporta (read() ritorna nil): Canon CRW (CIFF), Sigma X3F, HEIC. Per questi resta il solo controllo header.
-- info.maxEnd = byte massimo occupato dai dati dichiarati nelle strutture del file: se supera la
-- dimensione reale il file è troncato.

local ExifReader = {}

local floor = math.floor

local TYPE_SIZE = { [1] = 1, [2] = 1, [3] = 2, [4] = 4, [5] = 8, [6] = 1, [7] = 1, [8] = 2, [9] = 4, [10] = 8, [11] = 4, [12] = 8 }

local function u16( s, p, le )
	local a, b = s:byte( p, p + 1 )
	if not b then return nil end
	if le then return a + b * 256 end
	return a * 256 + b
end

local function u32( s, p, le )
	local a, b, c, d = s:byte( p, p + 3 )
	if not d then return nil end
	if le then return a + b * 256 + c * 65536 + d * 16777216 end
	return ((a * 256 + b) * 256 + c) * 256 + d
end

-- Lettore ad accesso casuale sul file: rd( pos0based, len ) -> stringa o nil
local function openReader( path )
	local f = io.open( path, 'rb' )
	if not f then return nil end
	local size = f:seek( 'end' )
	local function rd( pos, len )
		if pos < 0 or pos >= size then return nil end
		if pos + len > size then len = size - pos end
		f:seek( 'set', pos )
		return f:read( len )
	end
	return rd, size, function() f:close() end
end

-- Parsing di una IFD. base = offset TIFF nel file. Ritorna mappa tag -> entry, offset IFD successiva
local function parseIFD( rd, base, off, le )
	local head = rd( base + off, 2 )
	if not head then return nil end
	local n = u16( head, 1, le )
	if not n or n > 512 then return nil end
	local buf = rd( base + off + 2, n * 12 + 4 )
	if not buf or #buf < n * 12 then return nil end
	local entries = {}
	for i = 0, n - 1 do
		local p = i * 12 + 1
		local tag = u16( buf, p, le )
		entries[ tag ] = { type = u16( buf, p + 2, le ), count = u32( buf, p + 4, le ), raw = buf:sub( p + 8, p + 11 ) }
	end
	return entries, u32( buf, n * 12 + 1, le ) or 0
end

local function entryBytes( rd, base, e, le )
	local size = ( TYPE_SIZE[ e.type ] or 1 ) * e.count
	if size <= 4 then return e.raw:sub( 1, size ) end
	if size > 65536 then return nil end
	return rd( base + u32( e.raw, 1, le ), size )
end

local function getString( rd, base, e, le )
	if not e or e.type ~= 2 then return nil end
	local s = entryBytes( rd, base, e, le )
	if not s then return nil end
	s = s:gsub( '%z.*$', '' ):gsub( '^%s+', '' ):gsub( '%s+$', '' )
	if s == '' then return nil end
	return s
end

local function getNumber( rd, base, e, le, index )
	if not e then return nil end
	index = index or 0
	local s = entryBytes( rd, base, e, le )
	if not s then return nil end
	local t = e.type
	if t == 3 then return u16( s, index * 2 + 1, le )
	elseif t == 4 or t == 9 then return u32( s, index * 4 + 1, le )
	elseif t == 1 or t == 7 then return s:byte( index + 1 )
	elseif t == 5 then
		local n, d = u32( s, index * 8 + 1, le ), u32( s, index * 8 + 5, le )
		if n and d and d ~= 0 then return n / d end
	end
	return nil
end

local function isJpegAt( rd, pos )
	return rd( pos, 2 ) == '\255\216'
end

-- Raccoglie le anteprime JPEG dichiarate in una IFD
local function collectPreview( rd, base, entries, le, out )
	local off, len = getNumber( rd, base, entries[ 0x201 ], le ), getNumber( rd, base, entries[ 0x202 ], le )
	if not (off and len) then
		local comp = getNumber( rd, base, entries[ 0x103 ], le )
		if comp == 6 or comp == 7 then
			off, len = getNumber( rd, base, entries[ 0x111 ], le ), getNumber( rd, base, entries[ 0x117 ], le )
		end
	end
	if off and len and len > 0 and isJpegAt( rd, base + off ) then
		out[ #out + 1 ] = { pos = base + off, len = len }
	end
end

local function declaredEnd( rd, base, e, le )
	local best = 0
	local offE, cntE = e[ 0x111 ], e[ 0x117 ]
	if not (offE and cntE) then offE, cntE = e[ 0x144 ], e[ 0x145 ] end
	if offE and cntE and offE.count == cntE.count and offE.count > 0 then
		local last = offE.count - 1
		local o, c = getNumber( rd, base, offE, le, last ), getNumber( rd, base, cntE, le, last )
		if o and c and c > 0 then best = base + o + c end
	end
	local po, pl = getNumber( rd, base, e[ 0x201 ], le ), getNumber( rd, base, e[ 0x202 ], le )
	if po and pl and base + po + pl > best then best = base + po + pl end
	return best
end

local function readExifFields( rd, base, off, le, info )
	local e = parseIFD( rd, base, off, le )
	if not e then return end
	info.dateTimeOriginal = info.dateTimeOriginal or getString( rd, base, e[ 0x9003 ], le )
	info.exposure = info.exposure or getNumber( rd, base, e[ 0x829A ], le )
	info.fnumber = info.fnumber or getNumber( rd, base, e[ 0x829D ], le )
	info.iso = info.iso or getNumber( rd, base, e[ 0x8827 ], le )
	info.focal = info.focal or getNumber( rd, base, e[ 0x920A ], le )
	info.lens = info.lens or getString( rd, base, e[ 0xA434 ], le )
	info.serial = info.serial or getString( rd, base, e[ 0xA431 ], le )
end

-- mode: 'file' = TIFF a livello di file (traccia maxEnd), 'embedded' = TIFF incorporato (JPEG/RAF/MRW/CR3),
--       'exif' = il primo IFD è direttamente l'Exif IFD (box CMT2 dei CR3)
local function readTiff( rd, base, info, mode )
	mode = mode or 'embedded'
	local hdr = rd( base, 8 )
	if not hdr then return false end
	local le
	local bom = hdr:sub( 1, 2 )
	if bom == 'II' then le = true elseif bom == 'MM' then le = false else return false end
	local first = u32( hdr, 5, le )
	if not first then return false end

	if mode == 'exif' then
		readExifFields( rd, base, first, le, info )
		return true
	end

	local track = (mode == 'file')
	local visited, queue, n = {}, { first }, 0
	local exifPtr
	while #queue > 0 and n < 12 do
		local off = table.remove( queue, 1 )
		if off > 0 and not visited[ off ] then
			visited[ off ] = true
			n = n + 1
			local e, nextOff = parseIFD( rd, base, off, le )
			if e then
				if n == 1 then
					info.make = getString( rd, base, e[ 0x010F ], le )
					info.model = getString( rd, base, e[ 0x0110 ], le )
					info.orientation = getNumber( rd, base, e[ 0x0112 ], le )
					info.dateTimeFallback = getString( rd, base, e[ 0x0132 ], le )
				end
				if e[ 0x8769 ] then exifPtr = exifPtr or getNumber( rd, base, e[ 0x8769 ], le ) end
				collectPreview( rd, base, e, le, info.previews )
				if track then
					local d = declaredEnd( rd, base, e, le )
					if d > (info.maxEnd or 0) then info.maxEnd = d end
				end
				if e[ 0x014A ] then
					for i = 0, math.min( e[ 0x014A ].count, 6 ) - 1 do
						local sub = getNumber( rd, base, e[ 0x014A ], le, i )
						if sub then queue[ #queue + 1 ] = sub end
					end
				end
				if nextOff and nextOff > 0 then queue[ #queue + 1 ] = nextOff end
			end
		end
	end

	if exifPtr then readExifFields( rd, base, exifPtr, le, info ) end
	return true
end

-- Itera i box ISO-BMFF in [from, to): fn( type, payloadStart, boxEnd, headerSize, boxStart )
local function eachBox( rd, from, to, fn )
	local pos = from
	while pos + 8 <= to do
		local h = rd( pos, 16 )
		if not h or #h < 8 then return end
		local bsize, btype, hdr = u32( h, 1, false ), h:sub( 5, 8 ), 8
		if bsize == 1 then
			if #h < 16 then return end
			bsize, hdr = u32( h, 9, false ) * 4294967296 + u32( h, 13, false ), 16
		elseif bsize == 0 then
			bsize = to - pos
		end
		if bsize < hdr then return end
		if fn( btype, pos + hdr, pos + bsize, hdr, pos ) == false then return end
		pos = pos + bsize
	end
end

local CANON_META_UUID = '\133\192\182\135\130\015\017\224\129\017\244\206\070\043\106\072'
local CANON_PRVW_UUID = '\234\244\043\094\028\152\075\136\185\251\183\220\064\110\077\022'

-- Aggiunge a info.previews il JPEG contenuto in un box (THMB / PRVW): cerca il marcatore SOI nel preambolo
local function addBoxJpeg( rd, payload, boxEnd, info )
	local pre = rd( payload, 64 )
	if not pre then return end
	local i = pre:find( '\255\216\255', 1, true )
	if i and boxEnd - (payload + i - 1) > 0 then
		info.previews[ #info.previews + 1 ] = { pos = payload + i - 1, len = boxEnd - (payload + i - 1) }
	end
end

-- Canon CR3 e altri ISO-BMFF. Imposta info.maxEnd dai box di primo livello.
local function readBmff( rd, size, info )
	local found = false
	eachBox( rd, 0, size, function( btype, payload, boxEnd )
		if boxEnd > (info.maxEnd or 0) then info.maxEnd = boxEnd end
		if btype == 'moov' then
			eachBox( rd, payload, math.min( boxEnd, size ), function( t2, p2, e2 )
				if t2 == 'uuid' and rd( p2, 16 ) == CANON_META_UUID then
					eachBox( rd, p2 + 16, math.min( e2, size ), function( t3, p3, e3 )
						if t3 == 'CMT1' then
							found = readTiff( rd, p3, info, 'embedded' ) or found
						elseif t3 == 'CMT2' then
							found = readTiff( rd, p3, info, 'exif' ) or found
						elseif t3 == 'THMB' then
							addBoxJpeg( rd, p3, e3, info )
						end
					end )
				end
			end )
		elseif btype == 'uuid' and rd( payload, 16 ) == CANON_PRVW_UUID then
			eachBox( rd, payload + 16, math.min( boxEnd, size ), function( t2, p2, e2 )
				if t2 == 'PRVW' then addBoxJpeg( rd, p2, e2, info ) end
			end )
		end
	end )
	return found
end

-- Minolta MRW: blocchi "\0XXX" + lunghezza; il blocco TTW contiene un TIFF
local function readMrw( rd, info )
	local head = rd( 0, 8 )
	local dataOff = u32( head, 5, false )
	if not dataOff then return false end
	local pos, found = 8, false
	while pos < dataOff + 8 do
		local h = rd( pos, 8 )
		if not h or #h < 8 then break end
		local len = u32( h, 5, false )
		if h:sub( 2, 4 ) == 'TTW' then
			found = readTiff( rd, pos + 8, info, 'embedded' )
			break
		end
		pos = pos + 8 + len
	end
	return found
end

-- "2019:05:04 18:22:10" -> "2019-05-04T18:22:10"
local function isoDate( s )
	if not s then return nil end
	local y, mo, d, h, mi, se = s:match( '^(%d%d%d%d)[:%-](%d%d)[:%-](%d%d)[ T](%d%d):(%d%d):(%d%d)' )
	if not y or y == '0000' then return nil end
	return string.format( '%s-%s-%sT%s:%s:%s', y, mo, d, h, mi, se )
end

-- Ritorna tabella { make, model, serial, lens, datetime, iso, fnumber, exposure, focal, previews } oppure nil
function ExifReader.read( path )
	local rd, size, close = openReader( path )
	if not rd then return nil end

	local info = { previews = {} }
	local ok, found = pcall( function()
		local head = rd( 0, 12 )
		if not head then return false end
		local b2 = head:sub( 1, 2 )

		if head:sub( 5, 8 ) == 'ftyp' then
			return readBmff( rd, size, info )

		elseif head:sub( 1, 4 ) == '\0MRM' then
			return readMrw( rd, info )

		elseif b2 == 'II' or b2 == 'MM' then
			return readTiff( rd, 0, info, 'file' )

		elseif head:sub( 1, 8 ) == 'FUJIFILM' then
			local meta = rd( 84, 8 )
			local jpegOff, jpegLen = u32( meta, 1, false ), u32( meta, 5, false )
			if not (jpegOff and jpegLen) then return false end
			local pos = jpegOff + 2
			local res = false
			while pos < jpegOff + jpegLen do
				local m = rd( pos, 4 )
				if not m or m:byte( 1 ) ~= 255 then break end
				local seglen = u16( m, 3, false )
				if m:byte( 2 ) == 0xE1 and rd( pos + 4, 6 ) == 'Exif\0\0' then
					res = readTiff( rd, pos + 10, info, 'embedded' )
					break
				end
				pos = pos + 2 + seglen
			end
			if jpegLen > 0 then info.previews[ #info.previews + 1 ] = { pos = jpegOff, len = jpegLen } end
			return res

		elseif b2 == '\255\216' then
			local pos = 2
			while pos < size do
				local m = rd( pos, 4 )
				if not m or m:byte( 1 ) ~= 255 then break end
				local marker, seglen = m:byte( 2 ), u16( m, 3, false )
				if marker == 0xDA or marker == 0xD9 then break end
				if marker == 0xE1 and rd( pos + 4, 6 ) == 'Exif\0\0' then
					return readTiff( rd, pos + 10, info, 'embedded' )
				end
				pos = pos + 2 + seglen
			end
			return false
		end
		return false
	end )

	local result = nil
	if ok and found then
		info.datetime = isoDate( info.dateTimeOriginal ) or isoDate( info.dateTimeFallback )
		if info.make or info.model or info.datetime or info.iso or info.fnumber or info.exposure or info.focal then
			result = info
		end
	end
	info.path, info.size = path, size
	close()
	return result, info
end

-- Estrae il JPEG di anteprima incorporato più piccolo (>= minLen byte). Per i JPEG senza miniatura
-- usa il file intero se non supera maxWholeJpeg byte. Ritorna stringa JPEG oppure nil.
function ExifReader.extractPreview( path, info, minLen, maxWholeJpeg )
	minLen = minLen or 1500
	maxWholeJpeg = maxWholeJpeg or 600 * 1024
	local rd, size, close = openReader( path )
	if not rd then return nil end
	local best
	if info and info.previews then
		for _, p in ipairs( info.previews ) do
			if p.len >= minLen and (not best or p.len < best.len) then best = p end
		end
	end
	local data
	if best then
		data = rd( best.pos, best.len )
	else
		local ext = path:lower():match( '%.(%w+)$' )
		if (ext == 'jpg' or ext == 'jpeg') and size <= maxWholeJpeg then
			data = rd( 0, size )
		end
	end
	close()
	return data
end

return ExifReader
