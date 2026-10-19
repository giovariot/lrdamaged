-- Verifica che un file candidato sia davvero l'originale di una foto del catalogo.
-- 1) Confronto EXIF (data di scatto, marca/modello, seriale, ISO, focale, diaframma, tempo, obiettivo)
-- 2) Se l'EXIF del candidato manca o è insufficiente: confronto percettivo (aHash 8x8 sui DC JPEG)
--    tra l'anteprima di Lightroom e l'anteprima incorporata nel candidato.
-- 3) Se nemmeno questo è possibile: solo il nome, con confidenza "bassa".

local LrDate = import 'LrDate'
local LrTasks = import 'LrTasks'

local ExifReader = require 'ExifReader'
local JpegDC = require 'JpegDC'

local Matcher = {}

Matcher.HASH_OK = 10   -- distanza di Hamming (su 64) entro cui l'anteprima combacia
Matcher.HASH_MAYBE = 18

local RANK = { alta = 3, media = 2, bassa = 1 }
Matcher.RANK = RANK

local function norm( s )
	if not s then return nil end
	s = tostring( s ):lower():gsub( '[^%w]', '' )
	if s == '' then return nil end
	return s
end

local function sameText( a, b )
	a, b = norm( a ), norm( b )
	if not (a and b) then return nil end
	return a == b or a:find( b, 1, true ) ~= nil or b:find( a, 1, true ) ~= nil
end

local function near( a, b, tol )
	if not (a and b) or b == 0 then return nil end
	return math.abs( a / b - 1 ) <= tol
end

local function safe( fn )
	local ok, v = pcall( fn )
	if ok then return v end
	return nil
end

-- Metadati del catalogo (tutti opzionali, ogni accesso è protetto)
function Matcher.photoMeta( photo )
	local m = {}
	local iso = safe( function() return photo:getRawMetadata( 'dateTimeOriginalISO8601' ) end )
		or safe( function() return photo:getRawMetadata( 'dateTimeISO8601' ) end )
	if type( iso ) == 'string' and #iso >= 19 then m.datetime = iso:sub( 1, 19 ) end
	m.make = safe( function() return photo:getFormattedMetadata( 'cameraMake' ) end )
	m.model = safe( function() return photo:getFormattedMetadata( 'cameraModel' ) end )
	m.serial = safe( function() return photo:getFormattedMetadata( 'cameraSerialNumber' ) end )
	m.lens = safe( function() return photo:getFormattedMetadata( 'lens' ) end )
	m.iso = safe( function() return photo:getRawMetadata( 'isoSpeedRating' ) end )
	m.focal = safe( function() return photo:getRawMetadata( 'focalLength' ) end )
	m.aperture = safe( function() return photo:getRawMetadata( 'aperture' ) end )
	m.shutter = safe( function() return photo:getRawMetadata( 'shutterSpeed' ) end )
	return m
end

-- Funzione pura (testabile fuori da Lightroom).
-- Ritorna { compared = n, mismatches = {...}, date = 'match'|'mismatch'|nil, matched = {...} }
function Matcher.compareExif( meta, exif )
	local r = { compared = 0, mismatches = {}, matched = {}, date = nil }
	local function hard( name, result, detail )
		if result == nil then return end
		r.compared = r.compared + 1
		if result then r.matched[ #r.matched + 1 ] = name
		else r.mismatches[ #r.mismatches + 1 ] = name .. ' (' .. detail .. ')' end
	end

	if meta.datetime and exif.datetime then
		r.compared = r.compared + 1
		if meta.datetime == exif.datetime then
			r.date = 'match'
			r.matched[ #r.matched + 1 ] = 'data'
		else
			r.date = 'mismatch'
		end
	end

	hard( 'marca', sameText( meta.make, exif.make ), tostring( meta.make ) .. ' <> ' .. tostring( exif.make ) )
	hard( 'modello', sameText( meta.model, exif.model ), tostring( meta.model ) .. ' <> ' .. tostring( exif.model ) )
	hard( 'seriale', (norm( meta.serial ) and norm( exif.serial )) and norm( meta.serial ) == norm( exif.serial ) or nil,
		tostring( meta.serial ) .. ' <> ' .. tostring( exif.serial ) )
	hard( 'obiettivo', sameText( meta.lens, exif.lens ), tostring( meta.lens ) .. ' <> ' .. tostring( exif.lens ) )
	if type( meta.iso ) == 'number' and exif.iso then
		hard( 'ISO', meta.iso == exif.iso, meta.iso .. ' <> ' .. exif.iso )
	end
	if type( meta.focal ) == 'number' and exif.focal then
		hard( 'focale', math.abs( meta.focal - exif.focal ) <= math.max( 0.6, exif.focal * 0.02 ), meta.focal .. ' <> ' .. exif.focal )
	end
	-- Il valore grezzo può essere un numero f oppure un valore APEX: accetta entrambe le interpretazioni.
	if type( meta.aperture ) == 'number' and exif.fnumber then
		hard( 'diaframma', near( meta.aperture, exif.fnumber, 0.04) or near( 2 ^ (meta.aperture / 2), exif.fnumber, 0.04 ),
			meta.aperture .. ' <> f/' .. exif.fnumber )
	end
	-- Il tempo di posa grezzo può essere in secondi oppure APEX (Tv).
	if type( meta.shutter ) == 'number' and exif.exposure then
		hard( 'tempo', near( meta.shutter, exif.exposure, 0.06 ) or near( 2 ^ (-meta.shutter), exif.exposure, 0.06 ),
			meta.shutter .. ' <> ' .. exif.exposure )
	end
	return r
end

-- Funzione pura: decide la confidenza dal confronto EXIF.
-- Ritorna confidence, reason   oppure   nil, 'scartato: ...'   oppure   false (EXIF insufficiente)
function Matcher.decideFromExif( cmp )
	if #cmp.mismatches > 0 then
		return nil, 'EXIF diverso: ' .. table.concat( cmp.mismatches, ', ' )
	end
	if cmp.date == 'mismatch' then
		if cmp.compared >= 3 then
			return 'bassa', 'altri dati EXIF coincidono ma la data è diversa (' .. table.concat( cmp.matched, ', ' ) .. ')'
		end
		return false
	end
	if cmp.date == 'match' and cmp.compared >= 3 then
		return 'alta', 'EXIF coincidente: ' .. table.concat( cmp.matched, ', ' )
	end
	if cmp.date == 'match' and cmp.compared >= 2 then
		return 'media', 'EXIF coincidente: ' .. table.concat( cmp.matched, ', ' )
	end
	if not cmp.date and cmp.compared >= 3 then
		return 'media', 'EXIF coincidente (senza data): ' .. table.concat( cmp.matched, ', ' )
	end
	return false
end

-- Hash dell'anteprima di Lightroom (4 rotazioni). Calcolato al massimo una volta per foto.
function Matcher.lrPreviewHashes( photo )
	local done, data = false, nil
	local request = photo:requestJpegThumbnail( 160, 160, function( d )
		data = d
		done = true
	end )
	local t0 = LrDate.currentTime()
	while not done and LrDate.currentTime() - t0 < 5 do
		LrTasks.sleep( 0.05 )
	end
	local _ = request -- mantiene il riferimento fino alla fine della richiesta
	if not data then return nil end
	return JpegDC.hashes( JpegDC.decode( data ) )
end

-- Valuta un candidato. ctx = { photo, meta, lrHashes (cache) }
-- Ritorna proposta { path, confidence, reason, exif, size } oppure nil, motivoScarto
function Matcher.evaluate( ctx, candidatePath )
	local exif, info = ExifReader.read( candidatePath )
	local size = info and info.size or 0

	if exif then
		local confidence, reason = Matcher.decideFromExif( Matcher.compareExif( ctx.meta, exif ) )
		if confidence then
			return { path = candidatePath, confidence = confidence, reason = reason, exif = exif, size = size }
		elseif confidence == nil then
			return nil, reason
		end
	end

	-- EXIF assente o insufficiente: confronto percettivo delle anteprime
	local candPreview = ExifReader.extractPreview( candidatePath, exif or info )
	local candHash = candPreview and JpegDC.hashes( JpegDC.decode( candPreview ) )
	if candHash then
		if ctx.lrHashes == nil then
			ctx.lrHashes = Matcher.lrPreviewHashes( ctx.photo ) or false
		end
		if ctx.lrHashes then
			local d = JpegDC.distance( ctx.lrHashes[ 1 ], candHash )
			if d <= Matcher.HASH_OK then
				return { path = candidatePath, confidence = 'media', exif = exif or info, size = size,
					reason = string.format( 'anteprima simile (distanza %d/64), EXIF assente o insufficiente', d ) }
			elseif d <= Matcher.HASH_MAYBE then
				return { path = candidatePath, confidence = 'bassa', exif = exif or info, size = size,
					reason = string.format( 'anteprima solo in parte simile (distanza %d/64): foto con ritagli/modifiche?', d ) }
			end
			return nil, string.format( 'anteprima diversa (distanza %d/64)', d )
		end
	end

	return { path = candidatePath, confidence = 'bassa', exif = exif or info, size = size,
		reason = 'solo nome file (EXIF e anteprima non utilizzabili)' }
end

-- Sceglie la migliore proposta tra i candidati con lo stesso nome.
-- Ritorna proposta, numeroCandidatiValutati  oppure  nil, motivo
function Matcher.best( ctx, candidates )
	local best, notes = nil, {}
	for _, path in ipairs( candidates ) do
		local p, why = Matcher.evaluate( ctx, path )
		if p then
			if not best or RANK[ p.confidence ] > RANK[ best.confidence ]
				or (RANK[ p.confidence ] == RANK[ best.confidence ] and p.size > best.size) then
				best = p
			end
		else
			notes[ #notes + 1 ] = path .. ': ' .. tostring( why )
		end
	end
	if not best then
		return nil, 'nessun candidato compatibile (' .. table.concat( notes, '; ' ) .. ')'
	end
	best.candidates = #candidates
	return best
end

return Matcher
