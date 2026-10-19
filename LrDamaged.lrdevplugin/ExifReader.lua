-- Lettore EXIF minimale in Lua puro (nessuna dipendenza dall'SDK di Lightroom).
-- Supporta JPEG (APP1/Exif), TIFF e RAW basati su TIFF (CR2, NEF, ARW, DNG, ORF, RW2, PEF...) e RAF.
-- Non supporta CR3/HEIC: per questi read() ritorna nil.

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

local function readTiff( rd, base, info )
	local hdr = rd( base, 8 )
	if not hdr then return false end
	local le
	local bom = hdr:sub( 1, 2 )
	if bom == 'II' then le = true elseif bom == 'MM' then le = false else return false end
	local first = u32( hdr, 5, le )
	if not first then return false end

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

	if exifPtr then
		local e = parseIFD( rd, base, exifPtr, le )
		if e then
			info.dateTimeOriginal = getString( rd, base, e[ 0x9003 ], le )
			info.exposure = getNumber( rd, base, e[ 0x829A ], le )
			info.fnumber = getNumber( rd, base, e[ 0x829D ], le )
			info.iso = getNumber( rd, base, e[ 0x8827 ], le )
			info.focal = getNumber( rd, base, e[ 0x920A ], le )
			info.lens = getString( rd, base, e[ 0xA434 ], le )
			info.serial = getString( rd, base, e[ 0xA431 ], le )
		end
	end
	return true
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

		if b2 == 'II' or b2 == 'MM' then
			return readTiff( rd, 0, info )

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
					res = readTiff( rd, pos + 10, info )
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
					return readTiff( rd, pos + 10, info )
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
