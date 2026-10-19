-- Sostituzione del file danneggiato e (opzionale) reimportazione in catalogo.

local LrFileUtils = import 'LrFileUtils'
local LrPathUtils = import 'LrPathUtils'

local Integrity = require 'Integrity'

local Repair = {}

local BACKUP_DIR = '_lrdamaged_backup'

-- Sposta il file danneggiato (se esiste) in una cartella di backup accanto all'originale
-- e copia il file sostitutivo al suo posto. In caso di errore ripristina lo stato iniziale.
function Repair.replaceFile( originalPath, candidatePath )
	local parent = LrPathUtils.parent( originalPath )
	local backupPath = nil

	if LrFileUtils.exists( parent ) ~= 'directory' then
		if not LrFileUtils.createAllDirectories( parent ) then
			return false, 'impossibile creare la cartella ' .. parent
		end
	end

	if LrFileUtils.exists( originalPath ) == 'file' then
		local backupDir = LrPathUtils.child( parent, BACKUP_DIR )
		if not LrFileUtils.createAllDirectories( backupDir ) then
			return false, 'impossibile creare la cartella di backup'
		end
		backupPath = LrFileUtils.chooseUniqueFileName( LrPathUtils.child( backupDir, LrPathUtils.leafName( originalPath ) ) )
		if not LrFileUtils.move( originalPath, backupPath ) then
			return false, 'impossibile spostare il file danneggiato nel backup'
		end
	end

	local function rollback( msg )
		if LrFileUtils.exists( originalPath ) == 'file' then
			LrFileUtils.delete( originalPath )
		end
		if backupPath then
			LrFileUtils.move( backupPath, originalPath )
		end
		return false, msg
	end

	if not LrFileUtils.copy( candidatePath, originalPath ) then
		return rollback( 'copia del file sostitutivo non riuscita' )
	end
	if Integrity.fileSize( originalPath ) ~= Integrity.fileSize( candidatePath ) then
		return rollback( 'verifica dimensione dopo la copia fallita' )
	end

	return true, backupPath
end

-- Salva i dati del catalogo che andrebbero persi rimuovendo la foto.
function Repair.snapshot( photo )
	local snap = {
		rating = photo:getRawMetadata( 'rating' ),
		label = photo:getRawMetadata( 'colorNameForLabel' ),
		pick = photo:getRawMetadata( 'pickStatus' ),
		keywords = photo:getRawMetadata( 'keywords' ) or {},
		title = photo:getFormattedMetadata( 'title' ),
		caption = photo:getFormattedMetadata( 'caption' ),
		collections = {},
	}
	local ok, develop = pcall( function() return photo:getDevelopSettings() end )
	if ok then snap.develop = develop end

	local ok2, colls = pcall( function() return photo:getContainedCollections() end )
	if ok2 and colls then
		for _, c in ipairs( colls ) do
			if not c:isSmartCollection() then
				snap.collections[ #snap.collections + 1 ] = c
			end
		end
	end
	return snap
end

-- Da chiamare dentro catalog:withWriteAccessDo.
-- Rimuove la vecchia voce di catalogo, reimporta il file e riapplica i metadati salvati.
function Repair.reimport( catalog, oldPhoto, path, snap )
	catalog:removePhoto( oldPhoto )
	local newPhoto = catalog:addPhoto( path )
	if not newPhoto then
		return nil, 'importazione in catalogo non riuscita'
	end

	local function try( fn ) pcall( fn ) end
	try( function() if snap.rating then newPhoto:setRawMetadata( 'rating', snap.rating ) end end )
	try( function() if snap.label and snap.label ~= 'none' then newPhoto:setRawMetadata( 'colorNameForLabel', snap.label ) end end )
	try( function() if snap.pick then newPhoto:setRawMetadata( 'pickStatus', snap.pick ) end end )
	try( function() if snap.title and snap.title ~= '' then newPhoto:setRawMetadata( 'title', snap.title ) end end )
	try( function() if snap.caption and snap.caption ~= '' then newPhoto:setRawMetadata( 'caption', snap.caption ) end end )
	for _, kw in ipairs( snap.keywords ) do
		try( function() newPhoto:addKeyword( kw ) end )
	end
	for _, c in ipairs( snap.collections ) do
		try( function() c:addPhotos( { newPhoto } ) end )
	end
	if snap.develop then
		try( function() newPhoto:applyDevelopSettings( snap.develop ) end )
	end
	return newPhoto
end

return Repair
