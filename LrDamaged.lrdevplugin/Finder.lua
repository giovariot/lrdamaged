-- Ricerca del file sostitutivo (stesso nome) dentro una cartella scelta.

local LrFileUtils = import 'LrFileUtils'
local LrPathUtils = import 'LrPathUtils'
local LrTasks = import 'LrTasks'

local Integrity = require 'Integrity'

local Finder = {}

-- Indicizza ricorsivamente la cartella: nome file (minuscolo) -> lista di percorsi.
-- Ritorna nil se l'utente annulla.
function Finder.buildIndex( folder, progress )
	local index, count = {}, 0
	for path in LrFileUtils.recursiveFiles( folder ) do
		local key = LrPathUtils.leafName( path ):lower()
		local list = index[ key ]
		if not list then
			list = {}
			index[ key ] = list
		end
		list[ #list + 1 ] = path

		count = count + 1
		if count % 200 == 0 then
			LrTasks.yield()
			if progress and progress:isCanceled() then return nil end
		end
	end
	return index, count
end

-- Sceglie il miglior candidato integro per il file originale.
-- Ritorna candidato, numeroCandidatiValidi  oppure  nil, motivo
function Finder.pick( index, originalPath )
	local list = index[ LrPathUtils.leafName( originalPath ):lower() ]
	if not list then
		return nil, 'nessun file con lo stesso nome nella cartella'
	end

	local original = originalPath:lower()
	local best, bestSize, valid, lastReason = nil, -1, 0, nil
	for _, path in ipairs( list ) do
		if path:lower() ~= original then
			local ok, reason = Integrity.check( path )
			if ok then
				valid = valid + 1
				local size = Integrity.fileSize( path )
				if size > bestSize then
					best, bestSize = path, size
				end
			else
				lastReason = reason
			end
		end
	end

	if not best then
		return nil, 'candidati trovati ma tutti danneggiati (' .. tostring( lastReason ) .. ')'
	end
	return best, valid
end

return Finder
