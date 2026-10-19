-- Controlli di integrità a livello di file (nessuna decodifica dell'immagine).
-- Rileva: file mancante, vuoto/troppo piccolo, header errato, JPEG/PNG troncati,
-- RAW/TIFF/CR3 troncati (dati dichiarati oltre la fine del file), coda riempita di zeri.

local LrFileUtils = import 'LrFileUtils'
local LrPathUtils = import 'LrPathUtils'

local ExifReader = require 'ExifReader'

local Integrity = {}

local MIN_SIZE = 1024
local TAIL_ZERO_BYTES = 4096

-- Estensioni RAW (e TIFF) gestite da Lightroom Classic.
Integrity.RAW_EXTENSIONS = {
	'3fr',                                  -- Hasselblad
	'ari',                                  -- ARRI
	'arw', 'srf', 'sr2',                    -- Sony
	'bay',                                  -- Casio
	'cap', 'eip', 'iiq',                    -- Phase One
	'cr2', 'cr3', 'crw',                    -- Canon
	'dcr', 'dcs', 'kdc', 'k25',             -- Kodak
	'dng',                                  -- Adobe / Leica / Pentax / smartphone
	'erf',                                  -- Epson
	'fff',                                  -- Imacon / Hasselblad
	'gpr',                                  -- GoPro
	'mef',                                  -- Mamiya
	'mos',                                  -- Leaf
	'mrw',                                  -- Minolta
	'nef', 'nrw',                           -- Nikon
	'orf',                                  -- Olympus / OM System
	'pef', 'ptx',                           -- Pentax
	'raf',                                  -- Fujifilm
	'raw', 'rw2', 'rwl',                    -- Panasonic / Leica
	'rwz',                                  -- Rawzor
	'srw',                                  -- Samsung
	'x3f',                                  -- Sigma
	'tif', 'tiff',
}

local RAW = {}
for _, e in ipairs( Integrity.RAW_EXTENSIONS ) do RAW[ e ] = true end

-- Firme di inizio file plausibili per un RAW: TIFF (anche Olympus/Panasonic), Phase One, Sigma, Minolta,
-- Canon CRW (CIFF), Fujifilm RAF; i formati ISO-BMFF (CR3, HEIC) si riconoscono da 'ftyp' a offset 4.
local RAW_MAGICS = { 'II*\0', 'MM\0*', 'IIU\0', 'IIRO', 'IIRS', 'MMOR', 'IIII', 'FOVb', '\0MRM', 'II\26\0', 'FUJIFILM', 'ARRI' }

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

local function looksLikeRaw( head )
	if head:sub( 5, 8 ) == 'ftyp' then return true end
	for _, magic in ipairs( RAW_MAGICS ) do
		if head:sub( 1, #magic ) == magic then return true end
	end
	return false
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
	elseif RAW[ ext ] or ext == 'heic' or ext == 'heif' or ext == 'hif' then
		if not looksLikeRaw( head ) then
			return false, 'header ' .. ext:upper() .. ' non valido'
		end
		-- Confronta i dati dichiarati nel file (strip, tile, anteprime, box mdat) con la dimensione reale
		local ok, _, info = pcall( ExifReader.read, path )
		if ok and info and info.maxEnd and info.maxEnd > size then
			return false, string.format( 'file troncato (dati dichiarati fino a %d byte, file di %d)', info.maxEnd, size )
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
