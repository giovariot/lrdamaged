-- Controlli di integrità a livello di file (nessuna decodifica dell'immagine).
-- Rileva: file mancante, vuoto/troppo piccolo, header errato, JPEG/PNG troncati,
-- coda riempita di zeri (file troncato o preallocato).

local LrFileUtils = import 'LrFileUtils'
local LrPathUtils = import 'LrPathUtils'

local Integrity = {}

local MIN_SIZE = 1024
local TAIL_ZERO_BYTES = 4096

local TIFF_MAGICS = { 'II*\0', 'MM\0*', 'IIU\0', 'IIRO', 'IIRS' }
local TIFF_LIKE = { tif = true, tiff = true, dng = true, cr2 = true, nef = true, nrw = true,
	arw = true, srf = true, sr2 = true, orf = true, rw2 = true, pef = true, srw = true,
	erf = true, kdc = true, dcr = true, mef = true, mos = true, iiq = true, x3f = false }
local FTYP_LIKE = { cr3 = true, heic = true, heif = true, hif = true }

local function readBytes( path, len, fromEnd )
	local f = io.open( path, 'rb' )
	if not f then return nil end
	local ok, data = pcall( function()
		if fromEnd then
			local size = f:seek( 'end' )
			len = math.min( len, size )
			f:seek( 'set', size - len )
		end
		return f:read( len )
	end )
	f:close()
	if ok then return data end
	return nil
end

-- Ritorna true oppure false, motivo
function Integrity.check( path )
	if LrFileUtils.exists( path ) ~= 'file' then
		return false, 'file mancante'
	end

	local attrs = LrFileUtils.fileAttributes( path )
	local size = attrs and attrs.fileSize or 0
	if size == 0 then
		return false, 'file vuoto (0 byte)'
	end

	local head = readBytes( path, 16, false )
	if not head then
		return false, 'file non leggibile'
	end
	if size < MIN_SIZE then
		return false, 'file troppo piccolo (' .. size .. ' byte)'
	end

	local ext = LrPathUtils.extension( path ):lower()
	local tail = readBytes( path, TAIL_ZERO_BYTES, true )

	if ext == 'jpg' or ext == 'jpeg' then
		if head:sub( 1, 2 ) ~= '\255\216' then
			return false, 'header JPEG non valido'
		end
		local last = tail and tail:sub( -64 ) or ''
		if not last:find( '\255\217', 1, true ) then
			return false, 'JPEG troncato (marcatore EOI assente)'
		end
	elseif ext == 'png' then
		if head:sub( 1, 8 ) ~= '\137PNG\r\n\26\n' then
			return false, 'header PNG non valido'
		end
		local last = tail and tail:sub( -12 ) or ''
		if not last:find( 'IEND', 1, true ) then
			return false, 'PNG troncato (chunk IEND assente)'
		end
	elseif TIFF_LIKE[ ext ] then
		local ok = false
		for _, magic in ipairs( TIFF_MAGICS ) do
			if head:sub( 1, 4 ) == magic then ok = true break end
		end
		if not ok then
			return false, 'header TIFF/RAW non valido'
		end
	elseif FTYP_LIKE[ ext ] then
		if head:sub( 5, 8 ) ~= 'ftyp' then
			return false, 'header ISO-BMFF non valido'
		end
	elseif ext == 'raf' then
		if head:sub( 1, 8 ) ~= 'FUJIFILM' then
			return false, 'header RAF non valido'
		end
	end

	if tail and #tail >= 512 and tail:match( '^%z*$' ) then
		return false, 'coda del file azzerata (probabile troncamento)'
	end

	return true
end

function Integrity.fileSize( path )
	local attrs = LrFileUtils.fileAttributes( path )
	return attrs and attrs.fileSize or 0
end

return Integrity
