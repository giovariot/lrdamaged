-- Ricerca del file sostitutivo (stesso nome) dentro una cartella scelta.

local LrFileUtils = import 'LrFileUtils'
local LrPathUtils = import 'LrPathUtils'
local LrTasks = import 'LrTasks'

local Integrity = require 'Integrity'

local Finder = {}

-- Indicizza ricorsivamente la cartella: nome file (minuscolo) -> lista di percorsi.
-- Ritorna nil se l'utente annulla.
function Finder.buildIndex( folder, progress )
	local index, count, canceled = {}, 0, false
	-- recursiveFiles lascia aperto un handle finché il ciclo non termina normalmente: niente break/return qui dentro
	for path in LrFileUtils.recursiveFiles( folder ) do
		if not canceled then
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
				if progress and progress:isCanceled() then canceled = true end
			end
		end
	end
	if canceled then return nil end
	return index, count
end

-- Percorsi candidati integri con lo stesso nome del file originale (escluso l'originale stesso).
-- Ritorna lista, oppure nil, motivo
function Finder.candidates( index, originalPath )
	local list = index[ LrPathUtils.leafName( originalPath ):lower() ]
	if not list then
		return nil, 'nessun file con lo stesso nome nella cartella'
	end

	local original = originalPath:lower()
	local valid, lastReason = {}, nil
	for _, path in ipairs( list ) do
		if path:lower() ~= original then
			local ok, reason = Integrity.check( path )
			if ok then valid[ #valid + 1 ] = path else lastReason = reason end
		end
	end

	if #valid == 0 then
		return nil, 'candidati trovati ma tutti danneggiati (' .. tostring( lastReason ) .. ')'
	end
	return valid
end

return Finder
