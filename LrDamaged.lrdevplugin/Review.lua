-- Finestra di conferma: due colonne (originale / sostituto), selezione globale e per singola riga.

local LrBinding = import 'LrBinding'
local LrDialogs = import 'LrDialogs'
local LrFileUtils = import 'LrFileUtils'
local LrFunctionContext = import 'LrFunctionContext'
local LrPathUtils = import 'LrPathUtils'
local LrView = import 'LrView'

local ExifReader = require 'ExifReader'

local Review = {}

local CONF_LABEL = { alta = 'ALTA', media = 'MEDIA', bassa = 'BASSA (da verificare)' }

local function humanSize( n )
	if n >= 1048576 then return string.format( '%.1f MB', n / 1048576 ) end
	return string.format( '%d KB', math.max( 1, math.floor( n / 1024 ) ) )
end

local function writePreview( proposal, index )
	local data = ExifReader.extractPreview( proposal.path, proposal.exif, 1500, 400 * 1024 )
	if not data then return nil end
	local path = LrPathUtils.child( LrPathUtils.getStandardFilePath( 'temp' ), 'LrDamaged_prev_' .. index .. '.jpg' )
	local fh = io.open( path, 'wb' )
	if not fh then return nil end
	fh:write( data )
	fh:close()
	return path
end

-- items: lista di { photo, path, reason, proposal }
-- Ritorna la lista degli item approvati, oppure nil se l'utente annulla.
function Review.show( items )
	local approved
	local tempFiles = {}

	LrFunctionContext.callWithContext( 'LrDamaged.Review', function( context )
		local f = LrView.osFactory()
		local props = LrBinding.makePropertyTable( context )
		local updating = false

		local function refreshCount()
			local n = 0
			for i = 1, #items do
				if props[ 'sel' .. i ] then n = n + 1 end
			end
			props.count = string.format( 'Selezionate: %d di %d', n, #items )
			updating = true
			props.all = (n == #items)
			updating = false
		end

		for i, item in ipairs( items ) do
			props[ 'sel' .. i ] = item.proposal.confidence ~= 'bassa'
		end
		props.all = false
		props.count = ''
		refreshCount()

		props:addObserver( 'all', function( _, _, value )
			if updating then return end
			updating = true
			for i = 1, #items do props[ 'sel' .. i ] = value end
			updating = false
			refreshCount()
		end )
		for i = 1, #items do
			props:addObserver( 'sel' .. i, function() if not updating then refreshCount() end end )
		end

		local rows = {}
		for i, item in ipairs( items ) do
			local p = item.proposal
			local prev = writePreview( p, i )
			if prev then tempFiles[ #tempFiles + 1 ] = prev end

			local candidateThumb
			if prev then
				candidateThumb = f:picture { value = prev, width = 72, height = 72 }
			else
				candidateThumb = f:static_text { title = '(nessuna\nanteprima)', width = 72, height = 72 }
			end

			rows[ #rows + 1 ] = f:row {
				spacing = f:control_spacing(),
				f:checkbox { value = LrView.bind( 'sel' .. i ), title = '', width = 24 },
				f:row {
					width = 430,
					spacing = f:control_spacing(),
					f:catalog_photo { photo = item.photo, width = 72, height = 72 },
					f:column {
						spacing = 2,
						f:static_text { title = LrPathUtils.leafName( item.path ), font = '<system/bold>', width_in_chars = 45, truncation = 'middle' },
						f:static_text { title = item.path, width_in_chars = 45, truncation = 'middle' },
						f:static_text { title = 'Problema: ' .. item.reason, width_in_chars = 45, truncation = 'tail' },
					},
				},
				f:row {
					width = 450,
					spacing = f:control_spacing(),
					candidateThumb,
					f:column {
						spacing = 2,
						f:static_text { title = p.path, width_in_chars = 45, truncation = 'middle' },
						f:static_text { title = 'Dimensione: ' .. humanSize( p.size ) ..
							(p.candidates and p.candidates > 1 and ('  -  ' .. p.candidates .. ' candidati con questo nome') or ''),
							width_in_chars = 45, truncation = 'tail' },
						f:static_text { title = 'Corrispondenza ' .. CONF_LABEL[ p.confidence ] .. ': ' .. p.reason,
							width_in_chars = 45, height_in_lines = 2, truncation = 'tail' },
					},
				},
			}
			rows[ #rows + 1 ] = f:separator { fill_horizontal = 1 }
		end

		local contents = f:column {
			bind_to_object = props,
			spacing = f:control_spacing(),
			f:row {
				f:checkbox { title = 'Seleziona / deseleziona tutto', value = LrView.bind( 'all' ) },
				f:spacer { width = 20 },
				f:static_text { title = LrView.bind( 'count' ) },
			},
			f:row {
				spacing = f:control_spacing(),
				f:static_text { title = '', width = 24 },
				f:static_text { title = 'ORIGINALE (nel catalogo)', font = '<system/bold>', width = 430 },
				f:static_text { title = 'SOSTITUTO (trovato nella cartella)', font = '<system/bold>', width = 450 },
			},
			f:separator { fill_horizontal = 1 },
			f:scrolled_view {
				width = 960,
				height = 480,
				f:column( rows ),
			},
			f:static_text { title = 'Solo il file master viene sostituito (l\'originale danneggiato va in _lrdamaged_backup). Catalogo, metadati, date e sviluppo restano invariati.' },
		}

		local result = LrDialogs.presentModalDialog {
			title = 'LR Damaged - Conferma le sostituzioni',
			contents = contents,
			actionVerb = 'Sostituisci selezionate',
		}

		if result == 'ok' then
			approved = {}
			for i, item in ipairs( items ) do
				if props[ 'sel' .. i ] then approved[ #approved + 1 ] = item end
			end
		end
	end )

	for _, path in ipairs( tempFiles ) do LrFileUtils.delete( path ) end
	return approved
end

return Review
