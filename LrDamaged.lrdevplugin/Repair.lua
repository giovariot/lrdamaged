-- Sostituzione del solo file master; il catalogo non viene toccato.

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

return Repair
