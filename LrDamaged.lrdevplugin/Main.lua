local LrApplication = import 'LrApplication'
local LrBinding = import 'LrBinding'
local LrDate = import 'LrDate'
local LrDialogs = import 'LrDialogs'
local LrFunctionContext = import 'LrFunctionContext'
local LrPathUtils = import 'LrPathUtils'
local LrProgressScope = import 'LrProgressScope'
local LrTasks = import 'LrTasks'
local LrView = import 'LrView'

local Integrity = require 'Integrity'
local Finder = require 'Finder'
local Repair = require 'Repair'

local function askOptions( context )
	local f = LrView.osFactory()
	local props = LrBinding.makePropertyTable( context )
	props.scope = 'selection'
	props.dryRun = true
	props.folder = ''

	local contents = f:column {
		bind_to_object = props,
		spacing = f:control_spacing(),
		f:static_text { title = 'Ambito della scansione' },
		f:radio_button { title = 'Solo foto selezionate', value = LrView.bind( 'scope' ), checked_value = 'selection' },
		f:radio_button { title = 'Tutto il catalogo', value = LrView.bind( 'scope' ), checked_value = 'catalog' },
		f:separator { fill_horizontal = 1 },
		f:static_text { title = 'Cartella dove cercare i file sostitutivi (ricerca ricorsiva)' },
		f:row {
			f:static_text { title = LrView.bind( 'folder' ), width_in_chars = 50, truncation = 'middle' },
			f:push_button {
				title = 'Scegli cartella...',
				action = function()
					local r = LrDialogs.runOpenPanel {
						title = 'Cartella con i file sostitutivi',
						canChooseFiles = false,
						canChooseDirectories = true,
						allowsMultipleSelection = false,
					}
					if r and r[ 1 ] then props.folder = r[ 1 ] end
				end,
			},
		},
		f:separator { fill_horizontal = 1 },
		f:static_text { title = 'Verrà sostituito solo il file master: voce di catalogo, metadati, date e sviluppo restano invariati.' },
		f:checkbox { title = 'Solo simulazione (non modifica nulla)', value = LrView.bind( 'dryRun' ) },
	}

	local result = LrDialogs.presentModalDialog {
		title = 'LR Damaged - Sostituisci immagini danneggiate',
		contents = contents,
		actionVerb = 'Avvia',
	}
	if result ~= 'ok' then return nil end
	if props.folder == '' then
		LrDialogs.message( 'LR Damaged', 'Seleziona la cartella con i file sostitutivi.', 'warning' )
		return nil
	end
	return { scope = props.scope, dryRun = props.dryRun, folder = props.folder }
end

local function writeLog( lines )
	local dir = LrPathUtils.getStandardFilePath( 'documents' )
	local name = 'LrDamaged_' .. LrDate.timeToUserFormat( LrDate.currentTime(), '%Y%m%d_%H%M%S' ) .. '.txt'
	local path = LrPathUtils.child( dir, name )
	local fh = io.open( path, 'w' )
	if not fh then return nil end
	fh:write( table.concat( lines, '\n' ), '\n' )
	fh:close()
	return path
end

local function run( context )
	local opts = askOptions( context )
	if not opts then return end

	local catalog = LrApplication.activeCatalog()
	local photos
	if opts.scope == 'selection' then
		photos = catalog:getTargetPhotos()
	else
		photos = catalog:getAllPhotos()
	end
	if #photos == 0 then
		LrDialogs.message( 'LR Damaged', 'Nessuna foto da analizzare.', 'info' )
		return
	end

	-- 1) Scansione
	local progress = LrProgressScope { title = 'LR Damaged: scansione', functionContext = context }
	local damaged = {}
	for i, photo in ipairs( photos ) do
		if progress:isCanceled() then return end
		progress:setPortionComplete( i - 1, #photos )
		local path = photo:getRawMetadata( 'path' )
		local ok, reason = Integrity.check( path )
		if not ok then
			damaged[ #damaged + 1 ] = { photo = photo, path = path, reason = reason }
		end
		if i % 20 == 0 then LrTasks.yield() end
	end

	if #damaged == 0 then
		progress:done()
		LrDialogs.message( 'LR Damaged', 'Analizzate ' .. #photos .. ' foto: nessuna risulta danneggiata.', 'info' )
		return
	end

	-- 2) Indice dei file sostitutivi
	progress:setCaption( 'Indicizzazione della cartella...' )
	local index, indexed = Finder.buildIndex( opts.folder, progress )
	if not index then return end

	-- 3) Sostituzione
	local log = {
		'LR Damaged - ' .. LrDate.timeToUserFormat( LrDate.currentTime(), '%Y-%m-%d %H:%M:%S' ),
		'Cartella sostitutivi: ' .. opts.folder .. ' (' .. indexed .. ' file indicizzati)',
		'Modalità: solo sostituzione del master' .. ( opts.dryRun and ' [SIMULAZIONE]' or '' ),
		'Foto analizzate: ' .. #photos .. ' - danneggiate: ' .. #damaged,
		'',
	}
	local replacedPhotos = {}
	local stats = { replaced = 0, notFound = 0, failed = 0 }

	progress:setTitle( 'LR Damaged: sostituzione' )
	for i, item in ipairs( damaged ) do
		if progress:isCanceled() then
			log[ #log + 1 ] = 'INTERROTTO dall\'utente'
			break
		end
		progress:setPortionComplete( i - 1, #damaged )
		progress:setCaption( LrPathUtils.leafName( item.path ) )

		local candidate, info = Finder.pick( index, item.path )
		if not candidate then
			stats.notFound = stats.notFound + 1
			log[ #log + 1 ] = string.format( 'NON TROVATO  %s [%s] -> %s', item.path, item.reason, info )
		elseif opts.dryRun then
			stats.replaced = stats.replaced + 1
			log[ #log + 1 ] = string.format( 'SOSTITUIREBBE %s [%s] <- %s (candidati validi: %d)', item.path, item.reason, candidate, info )
		else
			local ok, res = Repair.replaceFile( item.path, candidate )
			if ok then
				stats.replaced = stats.replaced + 1
				replacedPhotos[ #replacedPhotos + 1 ] = item.photo
				log[ #log + 1 ] = string.format( 'SOSTITUITO   %s [%s] <- %s (backup: %s)', item.path, item.reason, candidate, tostring( res ) )
			else
				stats.failed = stats.failed + 1
				log[ #log + 1 ] = string.format( 'ERRORE       %s -> %s', item.path, res )
			end
		end
		LrTasks.yield()
	end
	progress:done()

	-- Raccoglie le foto sostituite in una collezione, per ricostruire facilmente le anteprime.
	if #replacedPhotos > 0 then
		catalog:withWriteAccessDo( 'LR Damaged: collezione foto sostituite', function()
			local coll = catalog:createCollection( 'LR Damaged - sostituite', nil, true )
			if coll then coll:addPhotos( replacedPhotos ) end
		end )
	end

	local logPath = writeLog( log )
	LrDialogs.message(
		'LR Damaged - Risultato',
		string.format( 'Foto analizzate: %d\nDanneggiate: %d\n%s: %d\nNon trovate: %d\nErrori: %d\n\nLog: %s',
			#photos, #damaged, opts.dryRun and 'Sostituibili' or 'Sostituite', stats.replaced,
			stats.notFound, stats.failed, tostring( logPath ) ),
		'info' )
end

LrTasks.startAsyncTask( function()
	LrFunctionContext.callWithContext( 'LrDamaged', function( context )
		local ok, err = pcall( run, context )
		if not ok then
			LrDialogs.message( 'LR Damaged - errore', tostring( err ), 'critical' )
		end
	end )
end )
