-- Decodifica "solo DC" di un JPEG baseline: ricava la luminanza media di ogni blocco 8x8
-- senza IDCT. Serve per un hash percettivo (aHash 8x8) molto veloce su miniature.
-- Non supporta JPEG progressive/arithmetic: in quel caso decode() ritorna nil.

local JpegDC = {}

local floor = math.floor

local function u16( s, p )
	local a, b = s:byte( p, p + 1 )
	if not b then return nil end
	return a * 256 + b
end

local function buildHuff( counts, symbols )
	local t = { maxcode = {}, mincode = {}, valptr = {}, vals = symbols }
	local code, k = 0, 0
	for l = 1, 16 do
		t.valptr[ l ] = k
		t.mincode[ l ] = code
		code = code + counts[ l ]
		k = k + counts[ l ]
		t.maxcode[ l ] = counts[ l ] > 0 and (code - 1) or -1
		code = code * 2
	end
	return t
end

-- Ritorna { bw, bh, grid } con grid[ (y*bw)+x+1 ] = luminanza media (0..255) del blocco, oppure nil
function JpegDC.decode( data )
	if not data or data:sub( 1, 2 ) ~= '\255\216' then return nil end

	local qt, hdc, hac, comps, restart = {}, {}, {}, nil, 0
	local width, height
	local pos = 3
	local len = #data

	while pos < len do
		if data:byte( pos ) ~= 255 then return nil end
		while data:byte( pos + 1 ) == 255 do pos = pos + 1 end
		local m = data:byte( pos + 1 )
		pos = pos + 2

		if m == 0xD8 or m == 0x01 or (m >= 0xD0 and m <= 0xD7) then
			-- marker senza lunghezza
		elseif m == 0xD9 then
			return nil
		else
			local seglen = u16( data, pos )
			if not seglen then return nil end
			local seg, endp = pos + 2, pos + seglen

			if m == 0xDB then
				local p = seg
				while p < endp do
					local pt = data:byte( p )
					local prec, id = floor( pt / 16 ), pt % 16
					p = p + 1
					qt[ id ] = prec == 0 and data:byte( p ) or u16( data, p )
					p = p + (prec == 0 and 64 or 128)
				end
			elseif m == 0xC4 then
				local p = seg
				while p < endp do
					local tc = data:byte( p )
					local class, id = floor( tc / 16 ), tc % 16
					local counts, total = {}, 0
					for i = 1, 16 do
						counts[ i ] = data:byte( p + i )
						total = total + counts[ i ]
					end
					local symbols = {}
					for i = 1, total do symbols[ i - 1 ] = data:byte( p + 16 + i ) end
					local t = buildHuff( counts, symbols )
					if class == 0 then hdc[ id ] = t else hac[ id ] = t end
					p = p + 17 + total
				end
			elseif m == 0xC0 or m == 0xC1 then
				if data:byte( seg ) ~= 8 then return nil end
				height, width = u16( data, seg + 1 ), u16( data, seg + 3 )
				local n = data:byte( seg + 5 )
				comps = {}
				for i = 1, n do
					local p = seg + 6 + (i - 1) * 3
					local hv = data:byte( p + 1 )
					comps[ i ] = { id = data:byte( p ), h = floor( hv / 16 ), v = hv % 16, tq = data:byte( p + 2 ), pred = 0 }
				end
			elseif m == 0xC2 or (m >= 0xC3 and m <= 0xCF and m ~= 0xC4 and m ~= 0xC8 and m ~= 0xCC) then
				return nil -- progressive / lossless / arithmetic
			elseif m == 0xDD then
				restart = u16( data, seg )
			elseif m == 0xDA then
				if not (comps and width and height and width > 0 and height > 0) then return nil end
				local ns = data:byte( seg )
				if ns ~= #comps then return nil end
				for i = 1, ns do
					local cs, tt = data:byte( seg + 1 + (i - 1) * 2 ), data:byte( seg + 2 + (i - 1) * 2 )
					for _, c in ipairs( comps ) do
						if c.id == cs then c.dcT, c.acT = hdc[ floor( tt / 16 ) ], hac[ tt % 16 ] end
					end
				end
				for _, c in ipairs( comps ) do
					if not (c.dcT and c.acT and qt[ c.tq ]) then return nil end
				end
				return JpegDC._scan( data, endp, comps, qt, restart, width, height )
			end
			pos = endp
		end
	end
	return nil
end

function JpegDC._scan( data, p, comps, qt, restart, width, height )
	local bitbuf, bitcnt = 0, 0
	local eof = false

	local function nextBit()
		if bitcnt == 0 then
			local b = data:byte( p )
			if not b then eof = true; b = 0
			elseif b == 255 then
				local nb = data:byte( p + 1 )
				if nb == 0 then p = p + 2
				else b = 0 end -- marker: non avanzare, riempie con zeri
			else
				p = p + 1
			end
			bitbuf, bitcnt = b, 8
		end
		bitcnt = bitcnt - 1
		local bit = floor( bitbuf / 2 ^ bitcnt ) % 2
		return bit
	end

	local function receive( s )
		local v = 0
		for _ = 1, s do v = v * 2 + nextBit() end
		return v
	end

	local function decodeHuff( t )
		local code = 0
		for l = 1, 16 do
			code = code * 2 + nextBit()
			local mx = t.maxcode[ l ]
			if mx >= 0 and code <= mx and code >= t.mincode[ l ] then
				return t.vals[ t.valptr[ l ] + code - t.mincode[ l ] ]
			end
		end
		return nil
	end

	local hmax, vmax = 1, 1
	for _, c in ipairs( comps ) do
		if c.h > hmax then hmax = c.h end
		if c.v > vmax then vmax = c.v end
	end
	if #comps == 1 then hmax, vmax = comps[ 1 ].h, comps[ 1 ].v end
	local mcux = math.ceil( width / (8 * hmax) )
	local mcuy = math.ceil( height / (8 * vmax) )

	local y = comps[ 1 ]
	local gw, gh = mcux * y.h, mcuy * y.v
	local grid = {}
	local ydcq = qt[ y.tq ]

	local count = 0
	for mcy = 0, mcuy - 1 do
		for mcx = 0, mcux - 1 do
			if restart > 0 and count > 0 and count % restart == 0 then
				bitcnt = 0
				if data:byte( p ) == 255 then
					local rm = data:byte( p + 1 )
					if rm and rm >= 0xD0 and rm <= 0xD7 then p = p + 2 end
				end
				for _, c in ipairs( comps ) do c.pred = 0 end
			end
			count = count + 1

			for ci, c in ipairs( comps ) do
				for by = 0, c.v - 1 do
					for bx = 0, c.h - 1 do
						local s = decodeHuff( c.dcT )
						if not s or eof then return nil end
						local diff = 0
						if s > 0 then
							diff = receive( s )
							if diff < 2 ^ (s - 1) then diff = diff - (2 ^ s - 1) end
						end
						c.pred = c.pred + diff

						local k = 1
						while k < 64 do
							local rs = decodeHuff( c.acT )
							if not rs or eof then return nil end
							local sz, run = rs % 16, floor( rs / 16 )
							if sz == 0 then
								if run == 15 then k = k + 16 else break end
							else
								k = k + run + 1
								for _ = 1, sz do nextBit() end
							end
						end

						if ci == 1 then
							local gx, gy = mcx * y.h + bx, mcy * y.v + by
							grid[ gy * gw + gx + 1 ] = c.pred * ydcq / 8 + 128
						end
					end
				end
			end
		end
	end

	return { bw = math.min( gw, math.ceil( width / 8 ) ), bh = math.min( gh, math.ceil( height / 8 ) ), stride = gw, grid = grid }
end

-- Riduce la griglia a 8x8 (medie per cella) e ritorna 4 hash a 64 bit (rotazioni 0/90/180/270)
-- come array di 0/1.
function JpegDC.hashes( dc )
	if not dc or dc.bw < 2 or dc.bh < 2 then return nil end
	local cells = {}
	for cy = 0, 7 do
		local y0 = floor( cy * dc.bh / 8 )
		local y1 = math.max( y0 + 1, floor( (cy + 1) * dc.bh / 8 ) )
		for cx = 0, 7 do
			local x0 = floor( cx * dc.bw / 8 )
			local x1 = math.max( x0 + 1, floor( (cx + 1) * dc.bw / 8 ) )
			local sum, n = 0, 0
			for yy = y0, y1 - 1 do
				for xx = x0, x1 - 1 do
					sum = sum + (dc.grid[ yy * dc.stride + xx + 1 ] or 128)
					n = n + 1
				end
			end
			cells[ cy * 8 + cx + 1 ] = sum / n
		end
	end

	local function toBits( c )
		local total = 0
		for i = 1, 64 do total = total + c[ i ] end
		local mean, bits = total / 64, {}
		for i = 1, 64 do bits[ i ] = c[ i ] > mean and 1 or 0 end
		return bits
	end

	local out, cur = {}, cells
	for r = 1, 4 do
		out[ r ] = toBits( cur )
		local rot = {}
		for i = 0, 7 do
			for j = 0, 7 do
				rot[ i * 8 + j + 1 ] = cur[ (7 - j) * 8 + i + 1 ]
			end
		end
		cur = rot
	end
	return out
end

-- Distanza di Hamming minima tra l'hash a e le 4 rotazioni di b (0..64)
function JpegDC.distance( a, bRotations )
	local best = 65
	for _, b in ipairs( bRotations ) do
		local d = 0
		for i = 1, 64 do
			if a[ i ] ~= b[ i ] then d = d + 1 end
		end
		if d < best then best = d end
	end
	return best
end

return JpegDC
