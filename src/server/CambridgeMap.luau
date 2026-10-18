-- Builds the Cambridge map when the game starts, from CambridgeLayout (made by tools/cambridge_layout.py): a
-- compact old city on the River Cam with the countryside and villages all round it, like Birmingham Vehicle
-- Simulator but with more different places to drive. About 13,000 by 10,000 studs.
--   * patchwork fields (grass, wheat, barley, ploughed earth, the odd yellow rapeseed field) with hedgerows and
--     trees along them, and woods here and there
--   * the Cam with grassy banks out in the country and stone edges through the colleges
--   * every road (see RoadNetwork), in the look of the AHDEV UK road pack, with hedges along the country lanes
--   * the railway with level crossings and two stations
--   * streets lined with buildings to suit each area: colleges, shops, terraces, semis, village houses, the
--     retail park, the science park, the hospital
--   * parks, the Market Square, the college chapel, the football ground, the airfield, and the team depots
--
-- It also fills in ReplicatedStorage → MapInfo, which the menus and minimap read (MenuCamera, Showroom_<team>,
-- Minimap, ParkedCars, Pavements), and Workspace → Depots (one model per team with "Spawn" parts).
--
-- To look round it in Studio without pressing Play, run this in the Command Bar:
--   require(game.ServerScriptService.Server.CambridgeMap).build()
-- and require(game.ServerScriptService.Server.CambridgeMap).clear() before saving or pressing Play.

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local CambridgeLayout = require(script.Parent.CambridgeLayout)
local CityBuildings = require(script.Parent.CityBuildings)
local RoadKit = require(script.Parent.RoadKit)
local RoadNetwork = require(script.Parent.RoadNetwork)
local TownBuildings = require(script.Parent.TownBuildings)
local TownKit = require(script.Parent.TownKit)
local TownProps = require(script.Parent.TownProps)

local C = TownKit.Colours
local box = TownKit.box
local ROAD_TOP = TownKit.ROAD_TOP
local PAVEMENT_TOP = TownKit.PAVEMENT_TOP
local KERB_WIDTH = TownKit.KERB_WIDTH

local layout: any = CambridgeLayout
local MIN_X, MAX_X, MIN_Z, MAX_Z = layout.bounds[1], layout.bounds[3], layout.bounds[2], layout.bounds[4]
local RIVER_BED = -8
local WATER_TOP = -1.6

local CambridgeMap = {}

local random = Random.new(2026) -- the same "random" city every time
local folder: Folder
local mapInfo: Configuration
local minimap: { { any } } = {}
local farAway: Model

-- Spots along the kerbs (and on drives) where parked cars go. ParkedCars (on each player's device) puts cars in
-- the ones near you. Each spot is { x, y, z, degrees turned }.
local parkingSpots: { { number } } = {}
local groundModel: Model

-- What's on the ground, in 4-stud squares, so buildings don't land on roads --------------------------

local CELL = 4
local GRID_W = math.ceil((MAX_X - MIN_X) / CELL)
local GRID_H = math.ceil((MAX_Z - MIN_Z) / CELL)
local FREE, VERGE, ROAD, WATER, SITE, BANK, RAISED, RAIL = 0, 1, 2, 3, 4, 5, 6, 7
local grid = buffer.create(GRID_W * GRID_H)

local function cellAt(x: number, z: number): number
	local i = math.floor((x - MIN_X) / CELL)
	local j = math.floor((z - MIN_Z) / CELL)
	if i < 0 or j < 0 or i >= GRID_W or j >= GRID_H then
		return SITE -- off the map counts as taken
	end
	return buffer.readu8(grid, j * GRID_W + i)
end

-- Writes `value` into every square inside a convex shape (flat corners in order). `rule` decides whether to
-- overwrite what's there: "always", "free" (only empty squares) or "notRoad".
local function fill(corners: { Vector3 }, value: number, rule: string)
	local minZ, maxZ = math.huge, -math.huge
	for _, c in corners do
		minZ = math.min(minZ, c.Z)
		maxZ = math.max(maxZ, c.Z)
	end
	local j0 = math.max(0, math.floor((minZ - MIN_Z) / CELL))
	local j1 = math.min(GRID_H - 1, math.floor((maxZ - MIN_Z) / CELL))
	for j = j0, j1 do
		local z = MIN_Z + (j + 0.5) * CELL
		local x0, x1 = math.huge, -math.huge
		for k = 1, #corners do
			local a, b = corners[k], corners[k % #corners + 1]
			if (a.Z <= z and b.Z >= z) or (b.Z <= z and a.Z >= z) then
				if math.abs(b.Z - a.Z) < 1e-6 then
					x0 = math.min(x0, a.X, b.X)
					x1 = math.max(x1, a.X, b.X)
				else
					local x = a.X + (b.X - a.X) * (z - a.Z) / (b.Z - a.Z)
					x0 = math.min(x0, x)
					x1 = math.max(x1, x)
				end
			end
		end
		if x0 <= x1 then
			local i0 = math.max(0, math.floor((x0 - MIN_X) / CELL + 0.5))
			local i1 = math.min(GRID_W - 1, math.floor((x1 - MIN_X) / CELL - 0.5))
			for i = i0, i1 do
				local index = j * GRID_W + i
				local current = buffer.readu8(grid, index)
				if rule == "always" or (rule == "free" and current == FREE) or (rule == "notRoad" and current ~= ROAD) then
					buffer.writeu8(grid, index, value)
				end
			end
		end
	end
end

local function circle(centre: Vector3, radius: number): { Vector3 }
	local out = {}
	for k = 0, 15 do
		local angle = k / 16 * 2 * math.pi
		table.insert(out, centre + Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius))
	end
	return out
end

local function rectangle(x0: number, z0: number, x1: number, z1: number): { Vector3 }
	return { Vector3.new(x0, 0, z0), Vector3.new(x1, 0, z0), Vector3.new(x1, 0, z1), Vector3.new(x0, 0, z1) }
end

-- The corners of a building's footprint, with its front edge's middle at `front`, facing `facing`
local function footprint(front: Vector3, facing: Vector3, width: number, depth: number): { Vector3 }
	local across = Vector3.new(-facing.Z, 0, facing.X)
	local back = -facing * depth
	return {
		front - across * width / 2, front + across * width / 2,
		front + across * width / 2 + back, front - across * width / 2 + back,
	}
end

-- Height of the ground: the riverbed in the river, otherwise flat
local function groundAt(x: number, z: number): number
	return if cellAt(x, z) == WATER then RIVER_BED else 0
end

-- Areas and villages ---------------------------------------------------------------------------

local function inPolygon(x: number, z: number, corners: { { number } }): boolean
	local inside = false
	local n = #corners
	local j = n
	for i = 1, n do
		local xi, zi = corners[i][1], corners[i][2]
		local xj, zj = corners[j][1], corners[j][2]
		if (zi > z) ~= (zj > z) and x < (xj - xi) * (z - zi) / (zj - zi) + xi then
			inside = not inside
		end
		j = i
	end
	return inside
end

-- Each area's bounding box, so most areas can be ruled out with four comparisons
local areaBounds: { { number } } = {}
for index, area in layout.areas do
	local x0, z0, x1, z1 = math.huge, math.huge, -math.huge, -math.huge
	for _, c in area[2] do
		x0, z0, x1, z1 = math.min(x0, c[1]), math.min(z0, c[2]), math.max(x1, c[1]), math.max(z1, c[2])
	end
	areaBounds[index] = { x0, z0, x1, z1 }
end

-- The kind of town area at a spot ("colleges", "oldcity", "suburb", ...), or nil outside the town
local function areaAt(x: number, z: number): string?
	for index, area in layout.areas do
		local b = areaBounds[index]
		if x >= b[1] and x <= b[3] and z >= b[2] and z <= b[4] and inPolygon(x, z, area[2]) then
			return area[1]
		end
	end
	return nil
end

-- Like areaAt, but "village" in a village. Villages only change what's built along the roads: behind the houses
-- and their gardens it's fields, hedges and woods like the rest of the countryside.
local function zoneAt(x: number, z: number): string?
	local area = areaAt(x, z)
	if area then
		return area
	end
	for _, v in layout.villages do
		local dx, dz = x - v[2], z - v[3]
		if dx * dx + dz * dz < v[4] * v[4] then
			return "village"
		end
	end
	return nil
end

-- The river ----------------------------------------------------------------------------------

type Bank = { points: { Vector3 }, dists: { number }, outward: { Vector3 } }

local riverPath: RoadKit.Path
local banks: { [number]: Bank } = {}
local BANK_STRIP = 40 -- how far from the water the grass laid along each bank takes over from the fields

local function buildRiver()
	local controls = {}
	for _, p in layout.river.points do
		table.insert(controls, Vector3.new(p[1], 0, p[2]))
	end
	riverPath = RoadKit.path(controls, layout.river.radius)
	local half = layout.river.width / 2
	local points, normals = riverPath.points, riverPath.normals

	-- Mark the water, so nothing gets built in it and bridges know to stand on piers, and the bank strips
	for k = 2, #points do
		local a, b = points[k - 1], points[k]
		local na, nb = normals[k - 1], normals[k]
		fill({ a + na * (half + BANK_STRIP), b + nb * (half + BANK_STRIP), b - nb * (half + BANK_STRIP), a - na * (half + BANK_STRIP) }, BANK, "always")
	end
	for k = 2, #points do
		local a, b = points[k - 1], points[k]
		fill({ a + normals[k - 1] * half, b + normals[k] * half, b - normals[k] * half, a - normals[k - 1] * half }, WATER, "always")
	end

	-- The water itself, and a muddy bed. The Cam is a slow, murky green-grey river, not a blue sea.
	local terrain = Workspace.Terrain
	terrain.WaterColor = Color3.fromRGB(64, 86, 78)
	terrain.WaterTransparency = 0.35
	terrain.WaterReflectance = 0.6
	terrain.WaterWaveSize = 0.04
	terrain.WaterWaveSpeed = 4
	for k = 2, #points do
		local a, b = points[k - 1], points[k]
		local middle = (a + b) / 2
		local length = (b - a).Magnitude
		local frame = CFrame.lookAt(middle, middle + (b - a))
		terrain:FillBlock(frame * CFrame.new(0, (RIVER_BED + WATER_TOP) / 2, 0), Vector3.new(half * 2 + 6, WATER_TOP - RIVER_BED, length + 6), Enum.Material.Water)
	end
	local bed = RoadKit.strip(RoadKit.offset(points, normals, 0, RIVER_BED), normals, -half - 3, half + 3, { colour = Color3.fromRGB(70, 62, 50), material = Enum.Material.Mud, thickness = 3 })
	for _, part in bed do
		part.CanQuery = false
	end

	-- The two banks
	for _, side in { 1, -1 } do
		local bankPoints = RoadKit.offset(points, normals, side * half)
		local dists = { 0 }
		for k = 2, #bankPoints do
			dists[k] = dists[k - 1] + (bankPoints[k] - bankPoints[k - 1]).Magnitude
		end
		local outward = {}
		for k, n in normals do
			outward[k] = n * side
		end
		banks[side] = { points = bankPoints, dists = dists, outward = outward }
	end
end

-- Where roads and the railway cross a bank, as distances along it, so the bank edges stop for bridges
local function bridgeGaps(bank: Bank, crossings: { { Vector3 } }, widths: { number }): { { number } }
	local gaps = {}
	for index, points in crossings do
		for k = 2, #points do
			local p, q = points[k - 1], points[k]
			for m = 2, #bank.points do
				local a, b = bank.points[m - 1], bank.points[m]
				local d1 = q - p
				local d2 = b - a
				local den = d1.X * d2.Z - d1.Z * d2.X
				if math.abs(den) > 1e-6 then
					local t = ((a.X - p.X) * d2.Z - (a.Z - p.Z) * d2.X) / den
					local u = ((a.X - p.X) * d1.Z - (a.Z - p.Z) * d1.X) / den
					if t >= 0 and t <= 1 and u >= 0 and u <= 1 then
						local along = bank.dists[m - 1] + u * (bank.dists[m] - bank.dists[m - 1])
						local sine = math.abs(Vector3.new(d1.X, 0, d1.Z).Unit:Cross(Vector3.new(d2.X, 0, d2.Z).Unit).Y)
						local half = widths[index] / math.max(sine, 0.3) + 4
						table.insert(gaps, { along - half, along + half })
					end
				end
			end
		end
	end
	return gaps
end

local function inGaps(s: number, gaps: { { number } }): boolean
	for _, gap in gaps do
		if s > gap[1] and s < gap[2] then
			return true
		end
	end
	return false
end

local railPath: RoadKit.Path?

-- The edges of the banks: dressed stone through the old city and the colleges, an earthy bank elsewhere
local function buildBanks(roads: { RoadNetwork.Road })
	local crossings: { { Vector3 } } = {}
	local widths: { number } = {}
	for _, road in roads do
		table.insert(crossings, road.path.points)
		table.insert(widths, road.hw + KERB_WIDTH + (if road.side == "pavement" then road.sideWidth else 0))
	end
	if railPath then
		table.insert(crossings, railPath.points)
		table.insert(widths, 12)
	end
	for _, side in { 1, -1 } do
		local bank = banks[side]
		local gaps = bridgeGaps(bank, crossings, widths)
		-- Walk the bank in short steps, making one piece of edge per run of the same kind
		local run: { Vector3 } = {}
		local runStone = false
		local function flush()
			if #run >= 2 then
				if runStone then
					RoadKit.wall(run, RIVER_BED - 1, 0.8, 2, C.Stone, Enum.Material.Limestone)
				else
					RoadKit.wall(run, RIVER_BED - 1, -0.05, 2.5, Color3.fromRGB(96, 80, 58), Enum.Material.Ground)
				end
			end
			run = {}
		end
		for k = 1, #bank.points do
			local p = bank.points[k]
			if inGaps(bank.dists[k], gaps) or p.X < MIN_X or p.X > MAX_X or p.Z < MIN_Z or p.Z > MAX_Z then
				flush()
				continue
			end
			local zone = zoneAt(p.X, p.Z)
			local stone = zone == "colleges" or zone == "backs" or zone == "oldcity"
			if #run > 0 and stone ~= runStone then
				flush()
			end
			runStone = stone
			table.insert(run, p)
		end
		flush()
	end
end

-- The ground: patchwork fields in the country, grass in town ------------------------------------

type Crop = { colour: Color3, material: Enum.Material, weight: number, wood: boolean? }
local CROPS: { Crop } = {
	{ colour = Color3.fromRGB(92, 132, 62), material = Enum.Material.Grass, weight = 30 }, -- pasture
	{ colour = Color3.fromRGB(106, 142, 70), material = Enum.Material.Grass, weight = 20 }, -- pasture
	{ colour = Color3.fromRGB(182, 166, 92), material = Enum.Material.Grass, weight = 15 }, -- ripe wheat
	{ colour = Color3.fromRGB(152, 156, 86), material = Enum.Material.Grass, weight = 10 }, -- barley
	{ colour = Color3.fromRGB(110, 88, 64), material = Enum.Material.Ground, weight = 11 }, -- ploughed
	{ colour = Color3.fromRGB(212, 196, 58), material = Enum.Material.Grass, weight = 4 }, -- rapeseed
	{ colour = Color3.fromRGB(122, 150, 76), material = Enum.Material.LeafyGrass, weight = 6 }, -- meadow
	{ colour = Color3.fromRGB(64, 92, 46), material = Enum.Material.LeafyGrass, weight = 4, wood = true }, -- wood
}
local TOWN_GRASS = Color3.fromRGB(88, 132, 62)
local FIELD_W, FIELD_H = 520, 440 -- the fields' size (FIELD_H a whole number of ground rows, so edges line up)
local GROUND_ROW = 40

local function hash(a: number, b: number): number
	local h = math.sin(a * 127.1 + b * 311.7) * 43758.5453
	return h - math.floor(h)
end

-- Which field a spot is in: fields are laid out in rows, each row shifted along a bit so they don't line up
local function fieldOf(x: number, z: number): (number, number)
	local row = math.floor((z - MIN_Z) / FIELD_H)
	local shift = hash(row, 7) * FIELD_W
	local column = math.floor((x - MIN_X + shift) / FIELD_W)
	return row, column
end

local function cropOf(row: number, column: number): number
	local total = 0
	for _, crop in CROPS do
		total += crop.weight
	end
	local roll = hash(row, column) * total
	for index, crop in CROPS do
		roll -= crop.weight
		if roll <= 0 then
			return index
		end
	end
	return 1
end

-- What the ground is at a spot: 0 nothing (river and its banks have their own), 1 town grass, 2+ a crop
local function groundKind(x: number, z: number): number
	local cell = cellAt(x, z)
	if cell == WATER or cell == BANK then
		return 0
	end
	if areaAt(x, z) then
		return 1
	end
	for _, site in layout.sites do
		if x >= site[2] and x <= site[4] and z >= site[3] and z <= site[5] then
			return 1
		end
	end
	local row, column = fieldOf(x, z)
	return 1 + cropOf(row, column)
end

local function buildGround()
	-- The ground is always loaded on every player's device: its strips are long, and with streaming Roblox
	-- left out the ones whose middle was far away, so you could see under the map
	groundModel = Instance.new("Model")
	groundModel.Name = "Ground"
	groundModel.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	groundModel.Parent = folder
	TownKit.setParent(groundModel)

	-- Grass along both banks of the river, following it exactly (water meadows out in the country)
	local half = layout.river.width / 2
	local points, normals = riverPath.points, riverPath.normals
	local grass = { colour = Color3.fromRGB(96, 138, 64), material = Enum.Material.Grass, thickness = 4 }
	local flat = RoadKit.offset(points, normals, 0, 0)
	RoadKit.strip(flat, normals, half, half + BANK_STRIP + 60, grass)
	RoadKit.strip(flat, normals, -half - BANK_STRIP - 60, -half, grass)

	-- Everywhere else, in rows; each row is cut into runs wherever the field changes
	local function lay(from: number, to: number, z: number, kind: number)
		local colour, material = TOWN_GRASS, Enum.Material.Grass
		if kind >= 2 then
			local crop = CROPS[kind - 1]
			colour, material = crop.colour, crop.material
		end
		while from < to - 0.01 do
			local width = math.min(to - from, 2000)
			box(Vector3.new(width, 4, GROUND_ROW), CFrame.new(from + width / 2, -2.05, z + GROUND_ROW / 2), colour, material)
			from += width
		end
	end
	local step = 20
	for z = MIN_Z, MAX_Z - 1, GROUND_ROW do
		local runStart: number? = nil
		local runKind = -1
		local x = MIN_X
		while x < MAX_X do
			-- A spot near the middle of the row: rows are 40 tall, and fields change on row lines
			local kind = groundKind(x + step / 2, z + GROUND_ROW / 2)
			-- Leave out the bit by the river if any corner of this piece is in the water
			if kind ~= 0 then
				for _, dz in { 2, GROUND_ROW - 2 } do
					local corner = cellAt(x + step / 2, z + dz)
					if corner == WATER then
						kind = 0
					end
				end
			end
			if kind ~= runKind then
				if runStart and runKind ~= 0 then
					lay(runStart, x, z, runKind)
				end
				runStart = x
				runKind = kind
			end
			x += step
		end
		if runStart and runKind ~= 0 then
			lay(runStart, MAX_X, z, runKind)
		end
	end
	TownKit.setParent(folder)
end

-- Roads into the grid -------------------------------------------------------------------------

local function markRoads(result: RoadNetwork.Result)
	-- Raised roads first, then ground-level roads over the top of them, then pavements and verges round both
	for pass = 1, 3 do
		for _, road in result.roads do
			local path = road.path
			local outer = road.hw + KERB_WIDTH + road.sideWidth + 2
			for k = 2, #path.points do
				local a, b = path.points[k - 1], path.points[k]
				local na, nb = path.normals[k - 1], path.normals[k]
				local high = (a.Y + b.Y) / 2 - ROAD_TOP > 1.5
				if pass == 1 and high then
					fill({ a + na * road.hw, b + nb * road.hw, b - nb * road.hw, a - na * road.hw }, RAISED, "notRoad")
				elseif pass == 2 and not high then
					fill({ a + na * road.hw, b + nb * road.hw, b - nb * road.hw, a - na * road.hw }, ROAD, "always")
				elseif pass == 3 then
					fill({ a + na * outer, b + nb * outer, b - nb * outer, a - na * outer }, VERGE, "free")
				end
			end
		end
	end
	for _, node in result.nodes do
		if node.reach > 0 then
			fill(circle(node.pos, node.reach), if node.pos.Y - ROAD_TOP > 1.5 then RAISED else ROAD, "notRoad")
			fill(circle(node.pos, node.reach + 14), VERGE, "free")
		end
	end
end

-- Hedgerows ---------------------------------------------------------------------------------------

local HEDGES = { Color3.fromRGB(58, 92, 42), Color3.fromRGB(66, 100, 46), Color3.fromRGB(52, 84, 40), Color3.fromRGB(72, 104, 50) }

-- A hedgerow from a to b, in pieces 20 to 45 studs long that each have their own height, thickness and shade of
-- green, so the top is ragged like a real one rather than one long box
local function hedge(a: Vector3, b: Vector3, height: number?)
	local length = (b - a).Magnitude
	if length < 2 then
		return
	end
	local direction = (b - a) / length
	local base = height or 5
	local s = 0
	while s < length - 0.5 do
		local piece = math.min(length - s, random:NextNumber(20, 45))
		if length - s - piece < 8 then
			piece = length - s
		end
		local h = base + random:NextNumber(-0.8, 1.8)
		local mid = a + direction * (s + piece / 2) + Vector3.new(0, h / 2, 0)
		box(Vector3.new(random:NextNumber(3, 4.2), h, piece + 1), CFrame.lookAt(mid, mid + direction), HEDGES[random:NextInteger(1, #HEDGES)], Enum.Material.LeafyGrass)
		s += piece
	end
end

-- Whether a tree at a spot is well clear of every road (so woods and hedgerow trees don't crowd the roads and
-- slip roads)
local function clearOfRoads(x: number, z: number, reach: number): boolean
	for _, offset in { { 0, 0 }, { reach, 0 }, { -reach, 0 }, { 0, reach }, { 0, -reach } } do
		local cell = cellAt(x + offset[1], z + offset[2])
		if cell == ROAD or cell == RAISED or cell == VERGE then
			return false
		end
	end
	return true
end

-- Whether a spot is open countryside (not town, not a road or its verge, not the river)
local function isCountry(x: number, z: number): boolean
	local cell = cellAt(x, z)
	return cell == FREE and areaAt(x, z) == nil
end

local function buildFieldHedges()
	-- Along every field edge: the row lines (east-west) and each row's own column lines (north-south)
	local trees = 0
	local function hedgeLine(from: Vector3, to: Vector3)
		local length = (to - from).Magnitude
		local direction = (to - from).Unit
		local s = 0
		local runStart: number? = nil
		local nextTree = random:NextNumber(30, 120)
		while s <= length do
			local p = from + direction * s
			local ok = isCountry(p.X, p.Z)
			if ok and not runStart then
				runStart = s
			elseif not ok and runStart then
				hedge(from + direction * runStart, from + direction * (s - 6))
				runStart = nil
			end
			if ok and s >= nextTree then
				if random:NextNumber() < 0.6 and clearOfRoads(p.X, p.Z, 12) then
					TownProps.tree(Vector3.new(p.X, 0, p.Z), random:NextNumber(1.1, 1.7), if random:NextNumber() < 0.3 then "wide" else nil)
					trees += 1
				end
				nextTree = s + random:NextNumber(50, 150)
			end
			s += 10
		end
		if runStart and length - runStart > 6 then
			hedge(from + direction * runStart, to)
		end
	end
	local rows = math.ceil((MAX_Z - MIN_Z) / FIELD_H)
	for row = 0, rows - 1 do
		local z0 = MIN_Z + row * FIELD_H
		local z1 = z0 + FIELD_H
		-- The row's top edge (shared with the row above)
		if row > 0 then
			hedgeLine(Vector3.new(MIN_X, 0, z0), Vector3.new(MAX_X, 0, z0))
		end
		-- The column edges in this row
		local shift = hash(row, 7) * FIELD_W
		local x = MIN_X - shift + FIELD_W
		while x < MAX_X do
			-- Skip edges between two pieces of the same wood
			local left = cropOf(row, math.floor((x - 1 - MIN_X + shift) / FIELD_W))
			local right = cropOf(row, math.floor((x + 1 - MIN_X + shift) / FIELD_W))
			if not (CROPS[left].wood and CROPS[right].wood) then
				hedgeLine(Vector3.new(x, 0, z0 + 2), Vector3.new(x, 0, z1 - 2))
			end
			x += FIELD_W
		end
	end
	return trees
end

-- Woods: trees all over the fields marked as woodland
local function buildWoods(): number
	local trees = 0
	local spacing = 40
	for z = MIN_Z + spacing / 2, MAX_Z, spacing do
		for x = MIN_X + spacing / 2, MAX_X, spacing do
			local px = x + random:NextNumber(-14, 14)
			local pz = z + random:NextNumber(-14, 14)
			if not isCountry(px, pz) or not clearOfRoads(px, pz, 16) then
				continue
			end
			local row, column = fieldOf(px, pz)
			if CROPS[cropOf(row, column)].wood then
				local roll = random:NextNumber()
				if roll < 0.82 then
					TownProps.tree(Vector3.new(px, 0, pz), random:NextNumber(1.1, 1.8), if roll < 0.35 then "tall" else nil)
				else
					TownProps.bush(Vector3.new(px, 0, pz), random:NextNumber(1, 1.6))
				end
				trees += 1
			end
		end
	end
	return trees
end

-- Hedges along the country roads, just outside the verge, with a tree now and then
local function buildRoadsideHedges(result: RoadNetwork.Result)
	for _, road in result.roads do
		if road.kind ~= "lane" and road.kind ~= "aroad" and road.kind ~= "link" then
			continue
		end
		local path = road.path
		for _, side in { 1, -1 } do
			local from, to = road.sideFrom[side] or road.startTrim, road.sideTo[side] or (path.length - road.endTrim)
			from += 12
			to -= 12
			local offset = side * (road.hw + road.sideWidth + 2)
			local runStart: Vector3? = nil
			local last: Vector3? = nil
			local lastDirection: Vector3? = nil
			local s = from
			while s <= to do
				local p, direction, n = RoadKit.at(path, s)
				local at = Vector3.new(p.X, 0, p.Z) + n * offset
				local onGround = math.abs(p.Y - ROAD_TOP) < 1
				local ok = onGround and zoneAt(at.X, at.Z) == nil and cellAt(at.X, at.Z) ~= ROAD and cellAt(at.X, at.Z) ~= WATER
				if ok then
					if not runStart then
						runStart = at
					elseif lastDirection and direction:Dot(lastDirection) < math.cos(math.rad(3)) then
						-- Bending: finish this straight piece and start the next from here
						hedge(runStart, last :: Vector3)
						runStart = last
					end
					if random:NextNumber() < 0.025 then
						TownProps.tree(at + n * side * 1.5, random:NextNumber(1, 1.5))
					end
				elseif runStart and last then
					hedge(runStart, last)
					runStart = nil
				end
				last = at
				lastDirection = if ok and (not lastDirection or direction:Dot(lastDirection) < math.cos(math.rad(3))) then direction else lastDirection
				s += 10
			end
			if runStart and last then
				hedge(runStart, last)
			end
		end
	end
end

-- The railway ------------------------------------------------------------------------------------

local BALLAST = { colour = Color3.fromRGB(122, 114, 104), material = Enum.Material.Pebble, thickness = 2 }
local SLEEPERS = { colour = Color3.fromRGB(78, 64, 52), material = Enum.Material.WoodPlanks, thickness = 0.3, collide = false }
local RAIL_COLOUR = Color3.fromRGB(150, 146, 140)
local TRACKS = { -4.2, 4.2 } -- two tracks, either side of the middle
local GAUGE = 2.6 -- half the distance between the rails

local function buildRailway()
	local controls = {}
	for _, p in layout.railway.points do
		table.insert(controls, Vector3.new(p[1], 0, p[2]))
	end
	local path = RoadKit.path(controls, 900)
	railPath = path
	-- Where the railway crosses a road at ground level, it's flush with the road: no ballast there
	local s = 0
	local pieces: { { number } } = {}
	local current: { number }? = nil
	while s <= path.length do
		local p = RoadKit.at(path, s)
		local onRoad = cellAt(p.X, p.Z) == ROAD
		if not onRoad and not current then
			local piece = { s, s }
			current = piece
			table.insert(pieces, piece)
		elseif onRoad then
			current = nil
		end
		if current then
			current[2] = s
		end
		s += 4
	end
	for _, piece in pieces do
		if piece[2] - piece[1] < 4 then
			continue
		end
		local points, normals = RoadKit.slice(path, piece[1], piece[2])
		local lifted = RoadKit.offset(points, normals, 0, 0.6)
		for _, part in RoadKit.strip(lifted, normals, -9, 9, BALLAST) do
			part.CanQuery = false
		end
		for _, track in TRACKS do
			RoadKit.strip(RoadKit.offset(points, normals, 0, 0.9), normals, track - 3.6, track + 3.6, SLEEPERS)
			for _, rail in { -GAUGE, GAUGE } do
				local railPoints = RoadKit.offset(points, normals, track + rail, 1.25)
				for k = 2, #railPoints do
					local a, b = railPoints[k - 1], railPoints[k]
					local length = (b - a).Magnitude
					if length > 0.1 then
						local mid = (a + b) / 2
						local part = TownKit.detail(Vector3.new(0.35, 0.45, length + 0.2), CFrame.lookAt(mid, mid + (b - a)), RAIL_COLOUR, Enum.Material.Metal)
						part.CastShadow = false
					end
				end
			end
		end
	end
	-- Keep buildings and fields' hedges off it
	for k = 2, #path.points do
		local a, b = path.points[k - 1], path.points[k]
		local na, nb = path.normals[k - 1], path.normals[k]
		fill({ a + na * 14, b + nb * 14, b - nb * 14, a - na * 14 }, RAIL, "free")
	end
	-- Over the river: two steel girders either side
	for k = 2, #path.points do
		local a, b = path.points[k - 1], path.points[k]
		local mid = (a + b) / 2
		if cellAt(mid.X, mid.Z) == WATER then
			local along = (b - a)
			local n = path.normals[k]
			for _, side in { 1, -1 } do
				local at = mid + n * side * 10 + Vector3.new(0, 2.5, 0)
				box(Vector3.new(1.5, 5, along.Magnitude + 2), CFrame.lookAt(at, at + along), Color3.fromRGB(70, 88, 96), Enum.Material.Metal)
			end
			box(Vector3.new(20, 2, along.Magnitude + 2), CFrame.lookAt(mid - Vector3.new(0, 0.6, 0), mid - Vector3.new(0, 0.6, 0) + along), Color3.fromRGB(70, 88, 96), Enum.Material.Metal)
		end
	end
	-- Level crossings: barriers raised either side, with warning lights, and the rails set into the road
	for _, crossing in layout.railway.crossings do
		local at = Vector3.new(crossing[1], 0, crossing[2])
		-- The nearest spot on the railway
		local s0 = 0
		local best = math.huge
		local probe = 0
		while probe <= path.length do
			local p = RoadKit.at(path, probe)
			local d = (Vector3.new(p.X, 0, p.Z) - at).Magnitude
			if d < best then
				best, s0 = d, probe
			end
			probe += 4
		end
		local p, direction, n = RoadKit.at(path, s0)
		local centre = Vector3.new(p.X, 0, p.Z)
		for _, track in TRACKS do
			for _, rail in { -GAUGE, GAUGE } do
				local railAt = centre + n * (track + rail) + Vector3.new(0, ROAD_TOP + 0.05, 0)
				local part = TownKit.detail(Vector3.new(0.35, 0.1, 48), CFrame.lookAt(railAt, railAt + direction), RAIL_COLOUR, Enum.Material.Metal)
				part.CastShadow = false
			end
		end
		for _, side in { 1, -1 } do
			for _, along in { 1, -1 } do
				local post = centre + n * side * 13 + direction * along * 18
				local base = Vector3.new(post.X, 0, post.Z)
				TownKit.post(0.6, 9, base, Color3.fromRGB(235, 235, 235), Enum.Material.Metal)
				-- The barrier arm, raised up
				local arm = TownKit.detail(Vector3.new(0.5, 16, 0.5), CFrame.new(base + Vector3.new(0, 9 + 8, 0)), Color3.fromRGB(240, 240, 240), Enum.Material.SmoothPlastic)
				arm.CastShadow = false
				for k = 0, 3 do
					local band = TownKit.detail(Vector3.new(0.55, 1.6, 0.55), CFrame.new(base + Vector3.new(0, 10.5 + k * 4, 0)), Color3.fromRGB(200, 20, 30), Enum.Material.SmoothPlastic)
					band.CastShadow = false
				end
				local lights = TownKit.detail(Vector3.new(3.2, 1.2, 0.6), CFrame.lookAt(base + Vector3.new(0, 6, 0), base + Vector3.new(0, 6, 0) - n * side), Color3.fromRGB(20, 20, 20), Enum.Material.Metal)
				lights.CastShadow = false
			end
		end
	end
	-- Stations: two long platforms with canopies, and the station building beside them
	for _, station in layout.railway.stations do
		local name, sx, sz = station[1], station[2], station[3]
		local at = Vector3.new(sx, 0, sz)
		local sBest, best = 0, math.huge
		local probe = 0
		while probe <= path.length do
			local p = RoadKit.at(path, probe)
			local d = (Vector3.new(p.X, 0, p.Z) - at).Magnitude
			if d < best then
				best, sBest = d, probe
			end
			probe += 4
		end
		local p, direction, n = RoadKit.at(path, sBest)
		local centre = Vector3.new(p.X, 0, p.Z)
		for _, side in { 1, -1 } do
			local platform = centre + n * side * 16
			box(Vector3.new(12, 3.4, 260), CFrame.lookAt(platform + Vector3.new(0, 1.7, 0), platform + Vector3.new(0, 1.7, 0) + direction), Color3.fromRGB(176, 172, 164), Enum.Material.Concrete)
			local edge = platform - n * side * 5.6 + Vector3.new(0, 3.45, 0)
			TownKit.detail(Vector3.new(0.8, 0.1, 258), CFrame.lookAt(edge, edge + direction), Color3.fromRGB(240, 210, 40), Enum.Material.SmoothPlastic).CastShadow = false
			local roof = platform + Vector3.new(0, 14, 0)
			box(Vector3.new(11, 0.8, 150), CFrame.lookAt(roof, roof + direction), Color3.fromRGB(60, 70, 80), Enum.Material.Metal)
			for k = -2, 2 do
				local column = platform + direction * k * 34 + n * side * 2
				TownKit.post(0.6, 13.6, column + Vector3.new(0, 3.4, 0), Color3.fromRGB(70, 80, 90), Enum.Material.Metal)
			end
			fill(rectangle(platform.X - 140, platform.Z - 140, platform.X + 140, platform.Z + 140), SITE, "free")
		end
		-- The building on the town side (towards the middle of the map)
		local townSide = if n:Dot(-centre) > 0 then 1 else -1
		local front = centre + n * townSide * 48
		local facing = n * townSide
		local clear = true
		for _, corner in footprint(front, facing, 120, 26) do
			local cell = cellAt(corner.X, corner.Z)
			if cell == ROAD or cell == RAISED or cell == WATER then
				clear = false
			end
		end
		if clear then
			CityBuildings.build(if name == "Cambridge" then "georgian" else "office", CFrame.lookAt(front, front + facing), 120, 26, 2, 11, 0, false)
		end
		table.insert(minimap, { "q" :: any, math.round(centre.X), math.round(centre.Z), 40, 260, math.round(math.deg(math.atan2(direction.X, direction.Z))), "yard" })
	end
	-- For the minimap
	for k = 2, #path.points, 2 do
		local a, b = path.points[k - 1], path.points[math.min(k + 1, #path.points)]
		table.insert(minimap, { "l" :: any, math.round(a.X), math.round(a.Z), math.round(b.X), math.round(b.Z), 10, "rail" })
	end
end

-- Buildings -----------------------------------------------------------------------------------------

-- Buildings from the bought packs: ServerStorage → BuildingKit, made by tools/prepare_building_kit.luau.
-- Each one's front faces -Z with the middle of its front edge at the origin.
local kitModels: { [string]: Model } = {}
local KIT_SIZES: { [string]: { any } } = {
	-- kind, width, depth (measured in Studio, see tools/london_fill.py)
	terrace_a = { "terrace", 98.9, 36.8 }, terrace_b = { "terrace", 98.8, 28.0 },
	semi_a = { "semi", 52.3, 28.2 }, semi_b = { "semi", 52.3, 28.2 }, semi_c = { "semi", 64.1, 41.3 },
	detached_a = { "detached", 32.6, 30.8 }, detached_b = { "detached", 51.4, 31.0 }, detached_c = { "detached", 24.2, 27.9 },
	detached_d = { "detached", 26.9, 27.9 }, gosford = { "detached", 17.8, 29.0 }, gosford_double = { "semi", 35.3, 29.0 },
	mitchell = { "large", 34.9, 32.4 }, windsor = { "large", 34.9, 32.4 }, darwick = { "large", 35.5, 29.3 },
	morton = { "large", 26.9, 29.0 }, duggen = { "large", 28.8, 32.0 },
	shop_1 = { "shop", 14.7, 34.2 }, shop_2 = { "shop", 14.7, 34.2 }, shop_3 = { "shop", 14.7, 34.2 }, shop_4 = { "shop", 14.7, 34.2 },
	shop_5 = { "shopwide", 41.1, 28.0 }, shop_6 = { "shop", 19.4, 36.9 }, shop_7 = { "shopwide", 41.2, 28.1 },
}

local function loadKit()
	table.clear(kitModels)
	local kitFolder = ServerStorage:FindFirstChild("BuildingKit")
	if not kitFolder then
		return
	end
	for _, model in kitFolder:GetChildren() do
		if model:IsA("Model") then
			kitModels[model.Name] = model
		end
	end
end

local function kitOfKind(kinds: { string }): string?
	local options = {}
	for name, info in KIT_SIZES do
		if kitModels[name] and table.find(kinds, info[1]) then
			table.insert(options, name)
		end
	end
	table.sort(options)
	if #options == 0 then
		return nil
	end
	return options[random:NextInteger(1, #options)]
end

-- Stand-ins for far away. With streaming on, each player only has the buildings near them; everything further
-- off would vanish. So every building also gets one plain block, a little smaller than it and the same colour,
-- in a model that every player always has. Up close it's hidden inside the real building; far off it's the
-- skyline.
local function standIn(cframe: CFrame, size: Vector3, colour: Color3, material: Enum.Material)
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Size = Vector3.new(math.max(1, size.X), math.max(1, size.Y), math.max(1, size.Z))
	part.CFrame = cframe
	part.Color = colour
	part.Material = material
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = farAway
end

-- What to build in each area: style (a CityBuildings style, or "kit:<kinds>" for the bought houses), width,
-- depth and storeys ranges, how far back from the pavement, and the gap to the next building
type Plan = { style: string, w: { number }, d: { number }, storeys: { number }, back: number, gap: { number } }

local function choosePlan(zone: string, roadKind: string): Plan?
	local r = random:NextNumber()
	if zone == "colleges" then
		return { style = "stone", w = { 60, 100 }, d = { 45, 60 }, storeys = { 3, 4 }, back = 0, gap = { 0, 8 } }
	elseif zone == "oldcity" or zone == "backs" then
		if r < 0.42 then
			return { style = "shops", w = { 22, 34 }, d = { 30, 36 }, storeys = { 3, 3 }, back = 0, gap = { 0, 0 } }
		elseif r < 0.72 then
			return { style = "georgian", w = { 26, 42 }, d = { 32, 38 }, storeys = { 3, 4 }, back = 0, gap = { 0, 0 } }
		elseif r < 0.9 then
			return { style = "stone", w = { 40, 64 }, d = { 40, 50 }, storeys = { 3, 4 }, back = 0, gap = { 0, 4 } }
		end
		return { style = "pub", w = { 22, 28 }, d = { 28, 32 }, storeys = { 2, 3 }, back = 0, gap = { 0, 0 } }
	elseif zone == "station" then
		return { style = "office", w = { 60, 90 }, d = { 44, 56 }, storeys = { 5, 7 }, back = 6, gap = { 10, 24 } }
	elseif zone == "terraces" then
		if roadKind == "high" or roadKind == "main" then
			return { style = if r < 0.75 then "shops" else "pub", w = { 18, 26 }, d = { 30, 34 }, storeys = { 2, 3 }, back = 0, gap = { 0, 0 } }
		end
		return { style = "kit:terrace", w = { 60, 90 }, d = { 30, 34 }, storeys = { 2, 2 }, back = 3, gap = { 0, 4 } }
	elseif zone == "suburb" then
		if roadKind == "high" then
			return { style = "kit:shop,shopwide", w = { 18, 26 }, d = { 30, 34 }, storeys = { 2, 2 }, back = 0, gap = { 0, 2 } }
		elseif r < 0.12 then
			return { style = "victorian", w = { 40, 70 }, d = { 28, 32 }, storeys = { 2, 3 }, back = 6, gap = { 4, 10 } }
		end
		return { style = "kit:semi,detached,large", w = { 30, 50 }, d = { 28, 32 }, storeys = { 2, 2 }, back = 14, gap = { 6, 14 } }
	elseif zone == "village" then
		if roadKind == "high" and r < 0.35 then
			return { style = "kit:shop,shopwide", w = { 18, 26 }, d = { 30, 34 }, storeys = { 2, 2 }, back = 0, gap = { 0, 4 } }
		elseif r < 0.06 then
			return { style = "pub", w = { 26, 32 }, d = { 28, 32 }, storeys = { 2, 2 }, back = 8, gap = { 10, 20 } }
		end
		return { style = "kit:detached,large", w = { 26, 40 }, d = { 28, 32 }, storeys = { 2, 2 }, back = 12, gap = { 14, 30 } }
	elseif zone == "retail" then
		return { style = "shed", w = { 110, 160 }, d = { 80, 100 }, storeys = { 1, 1 }, back = 50, gap = { 20, 40 } }
	elseif zone == "industrial" then
		return { style = if r < 0.5 then "warehouse" else "shed", w = { 70, 110 }, d = { 60, 80 }, storeys = { 1, 2 }, back = 22, gap = { 14, 30 } }
	elseif zone == "sciencepark" or zone == "westcam" then
		return { style = if r < 0.7 then "office" else "concrete", w = { 60, 90 }, d = { 40, 52 }, storeys = { 3, 4 }, back = 30, gap = { 30, 50 } }
	elseif zone == "hospital" then
		return { style = if r < 0.5 then "concrete" else "office", w = { 80, 120 }, d = { 50, 70 }, storeys = { 5, 8 }, back = 20, gap = { 20, 40 } }
	end
	return nil
end

-- Checks spots all over the footprint, about every 10 studs. The front row is checked 7 studs in: the strip
-- just past the pavement is marked as verge, and buildings stand right up against the pavement.
local function footprintFree(corners: { Vector3 }): boolean
	local frontLeft, frontRight, backLeft = corners[1], corners[2], corners[4]
	local across = frontRight - frontLeft
	local back = backLeft - frontLeft
	local width, depth = across.Magnitude, back.Magnitude
	if width < 1 or depth < 1 then
		return false
	end
	local acrossUnit, backUnit = across / width, back / depth
	local columns = math.max(2, math.ceil(width / 10))
	local rows = math.max(2, math.ceil(depth / 10))
	for row = 0, rows do
		local d = 7 + (depth - 8) * row / rows
		for column = 0, columns do
			local w = 1 + (width - 2) * column / columns
			local p = frontLeft + acrossUnit * w + backUnit * d
			if cellAt(p.X, p.Z) ~= FREE then
				return false
			end
		end
	end
	return true
end

local buildingCount = 0

local FENCE = Color3.fromRGB(112, 82, 56)
local GARDEN_WALLS = { Color3.fromRGB(150, 82, 62), Color3.fromRGB(170, 104, 78), Color3.fromRGB(196, 186, 168) }

-- A straight run of fence, wall or hedge from a to b, `height` tall and `thickness` thick
local function boundary(a: Vector3, b: Vector3, height: number, thickness: number, colour: Color3, material: Enum.Material)
	local length = (b - a).Magnitude
	if length < 1 then
		return
	end
	local mid = (a + b) / 2 + Vector3.new(0, height / 2, 0)
	local part = box(Vector3.new(thickness, height, length), CFrame.lookAt(mid, mid + (b - a)), colour, material)
	part.CanTouch = false
end

-- A house's plot. Behind it, a fenced back garden as deep as there's room for. Along the pavement, a low wall or
-- a clipped hedge, with a gap for the drive when the house is set back far enough (and now and then a car on it).
-- Call before the house's own ground is marked as taken.
local function garden(front: Vector3, facing: Vector3, width: number, depth: number, setback: number)
	local across = Vector3.new(-facing.Z, 0, facing.X)
	local half = width / 2 + 3
	local houseBack = front - facing * (depth + 1)
	local deep = 0
	for _, try in { 44, 30, 18 } do
		if footprintFree(footprint(houseBack + facing * 4, facing, width + 6, try + 4)) then
			deep = try
			break
		end
	end
	-- Out in the villages the ground is fields, so the plot gets its own lawn
	if not areaAt(front.X, front.Z) then
		local frontLine = front + facing * setback
		local backEdge = houseBack - facing * deep
		local middle = (frontLine + backEdge) / 2
		local lawn = box(Vector3.new(width + 6, 0.1, (frontLine - backEdge).Magnitude), CFrame.lookAt(middle, middle + facing), TOWN_GRASS, Enum.Material.Grass)
		lawn.CastShadow = false
		lawn.CanTouch = false
	end
	if deep > 0 then
		local backLine = houseBack - facing * deep
		boundary(backLine - across * half, backLine + across * half, 5.5, 0.4, FENCE, Enum.Material.WoodPlanks)
		for _, side in { -1, 1 } do
			boundary(houseBack + across * side * half, backLine + across * side * half, 5.5, 0.4, FENCE, Enum.Material.WoodPlanks)
		end
		fill(footprint(houseBack, facing, width + 6, deep), SITE, "free")
	end
	if setback < 2 then
		return
	end
	-- The front boundary, just inside the pavement
	local line = front + facing * (setback - 0.2)
	local isHedge = random:NextNumber() < 0.4
	local colour = if isHedge then HEDGES[random:NextInteger(1, #HEDGES)] else GARDEN_WALLS[random:NextInteger(1, #GARDEN_WALLS)]
	local material = if isHedge then Enum.Material.LeafyGrass else Enum.Material.Brick
	local height, thickness = if isHedge then 3.4 else 2.2, if isHedge then 2 else 0.8
	local function frontRun(x0: number, x1: number)
		if x1 - x0 > 1 then
			boundary(line + across * x0 - facing * thickness / 2, line + across * x1 - facing * thickness / 2, height, thickness, colour, material)
		end
	end
	if setback >= 10 then
		local driveSide = if random:NextNumber() < 0.5 then 1 else -1
		local driveMiddle = driveSide * (width / 2 - 6)
		frontRun(-half, driveMiddle - 5)
		frontRun(driveMiddle + 5, half)
		local drive = front + across * driveMiddle + facing * (setback / 2)
		local paving = box(Vector3.new(9, 0.12, setback), CFrame.lookAt(drive + Vector3.new(0, 0.01, 0), drive + Vector3.new(0, 0.01, 0) + facing), Color3.fromRGB(128, 124, 118), Enum.Material.Concrete)
		paving.CastShadow = false
		if setback >= 13 and random:NextNumber() < 0.45 then
			local degrees = math.deg(math.atan2(facing.X, facing.Z))
			table.insert(parkingSpots, { math.round(drive.X * 10) / 10, ROAD_TOP, math.round(drive.Z * 10) / 10, math.round(degrees) })
		end
	else
		frontRun(-half, half)
	end
end

local HOUSE_KINDS = { semi = true, detached = true, large = true, terrace = true }

-- Builds one building with the middle of its front edge at `front`, facing `facing` (towards the road).
-- `setback` (how far it stands back from the pavement) is given for homes that get a garden.
-- Returns the width it took up, or nil if it didn't fit.
local function placeBuilding(plan: Plan, front: Vector3, facing: Vector3, setback: number?): number?
	local frame = CFrame.lookAt(front, front + facing)
	local kitKinds = string.match(plan.style, "^kit:(.+)$")
	if kitKinds then
		local name = kitOfKind(string.split(kitKinds, ","))
		if name then
			local size = KIT_SIZES[name]
			local width, depth = size[2], size[3]
			local corners = footprint(front, facing, width + 2, depth + 2)
			if not footprintFree(corners) then
				return nil
			end
			local building = kitModels[name]:Clone()
			building:PivotTo(frame * CFrame.new(0, 0.05, 0))
			-- Small pieces (window frames, trims, gutters, plants) are just for looks: out of the physics engine
			for _, part in building:GetDescendants() do
				if part:IsA("BasePart") then
					part.CanTouch = false
					local s = part.Size
					if math.min(s.X, s.Y, s.Z) < 1.2 or s.X * s.Y * s.Z < 400 then
						part.CanCollide = false
						part.CanQuery = false
					end
				end
			end
			building.Parent = TownKit.getParent()
			local cf, bounds = building:GetBoundingBox()
			standIn(cf * CFrame.new(0, -bounds.Y * 0.2, 0), bounds * Vector3.new(0.84, 0.6, 0.7), Color3.fromRGB(150, 92, 70), Enum.Material.SmoothPlastic)
			if setback and HOUSE_KINDS[size[1]] then
				garden(front, facing, width, depth, setback)
			end
			fill(corners, SITE, "always")
			buildingCount += 1
			return width
		end
		-- No kit in this place: part-built houses instead
		plan = { style = "victorian", w = plan.w, d = plan.d, storeys = plan.storeys, back = plan.back, gap = plan.gap }
	end
	local width = random:NextNumber(plan.w[1], plan.w[2])
	local depth = random:NextNumber(plan.d[1], plan.d[2])
	local storeys = random:NextInteger(plan.storeys[1], plan.storeys[2])
	local corners = footprint(front, facing, width, depth)
	if not footprintFree(corners) then
		-- Try a narrower one
		width = plan.w[1]
		corners = footprint(front, facing, width, depth)
		if not footprintFree(corners) then
			return nil
		end
	end
	local model = CityBuildings.build(plan.style, frame, width, depth, storeys, random:NextInteger(1, 1e6), 0, false)
	if setback and not areaAt(front.X, front.Z) then
		-- A village pub or shop: grass round it rather than the field
		local middle = front + facing * setback / 2 - facing * depth / 2
		local lawn = box(Vector3.new(width + 12, 0.1, depth + setback + 10), CFrame.lookAt(middle, middle + facing), TOWN_GRASS, Enum.Material.Grass)
		lawn.CastShadow = false
		lawn.CanTouch = false
	end
	local body = model:FindFirstChildWhichIsA("BasePart")
	if body and body.Size.Y > 6 then
		standIn(body.CFrame, body.Size - Vector3.new(1.6, 0.8, 1.6), body.Color, body.Material)
	end
	fill(corners, SITE, "always")
	buildingCount += 1
	return width
end

-- Lines the streets in town and the villages with buildings, facing the road
local function buildStreets(result: RoadNetwork.Result)
	for _, road in result.roads do
		local kind = road.kind
		if kind == "motorway" or kind == "dual" or kind == "slip" or kind == "link" then
			continue
		end
		local path = road.path
		for _, side in { 1, -1 } do
			local from = (road.sideFrom[side] or road.startTrim) + 6
			local to = (road.sideTo[side] or (path.length - road.endTrim)) - 6
			local s = from + random:NextNumber(0, 6)
			while s < to do
				local p, _, n = RoadKit.at(path, s)
				if p.Y - ROAD_TOP > 1 then
					s += 20
					continue
				end
				local edge = road.hw + (if road.side == "pavement" then KERB_WIDTH + road.sideWidth else road.sideWidth)
				local probe = Vector3.new(p.X, 0, p.Z) + n * side * (edge + 10)
				local zone = zoneAt(probe.X, probe.Z)
				-- Out in the country, only the villages have houses along the roads
				if not zone or (road.side ~= "pavement" and zone ~= "village") then
					s += 30
					continue
				end
				local plan = choosePlan(zone, kind)
				if not plan then
					s += 30
					continue
				end
				local front = Vector3.new(p.X, 0, p.Z) + n * side * (edge + 0.5 + plan.back)
				local homes = zone == "suburb" or zone == "village" or zone == "terraces"
				local width = placeBuilding(plan, front, -n * side, if homes then plan.back else nil)
				if width then
					s += width + random:NextNumber(plan.gap[1], plan.gap[2])
				else
					s += 8
				end
			end
		end
	end
end

-- In the old city, the colleges and round the station the blocks are built up all the way through, so the space
-- behind the buildings along the streets gets more: college courts, and plain backs of shops and offices
local INFILL: { [string]: Plan } = {
	colleges = { style = "stone", w = { 50, 80 }, d = { 40, 60 }, storeys = { 3, 4 }, back = 0, gap = { 0, 0 } },
	oldcity = { style = "backdrop", w = { 28, 48 }, d = { 26, 40 }, storeys = { 3, 4 }, back = 0, gap = { 0, 0 } },
	station = { style = "office", w = { 50, 80 }, d = { 40, 50 }, storeys = { 4, 6 }, back = 0, gap = { 0, 0 } },
}
local FACINGS = { Vector3.new(0, 0, 1), Vector3.new(0, 0, -1), Vector3.new(1, 0, 0), Vector3.new(-1, 0, 0) }

local function buildInfill()
	for index, area in layout.areas do
		local plan = INFILL[area[1]]
		if not plan then
			continue
		end
		local b = areaBounds[index]
		for z = b[2] + 10, b[4], 22 do
			for x = b[1] + 10, b[3], 22 do
				if cellAt(x, z) == FREE and inPolygon(x, z, area[2]) then
					placeBuilding(plan, Vector3.new(x, 0, z), FACINGS[random:NextInteger(1, 4)])
				end
			end
		end
	end
end

-- Open land left in the suburbs (where no street reaches) becomes the green spaces every British suburb has:
-- playing fields with goals, allotments with sheds, and little copses, with trees dotted over whatever's left
local function rectFree(x0: number, z0: number, x1: number, z1: number): boolean
	for z = z0, z1, 10 do
		for x = x0, x1, 10 do
			if cellAt(x, z) ~= FREE then
				return false
			end
		end
	end
	return true
end

local function line(x0: number, z0: number, x1: number, z1: number)
	local a, b = Vector3.new(x0, 0.06, z0), Vector3.new(x1, 0.06, z1)
	local mark = TownKit.detail(Vector3.new(0.6, 0.06, (b - a).Magnitude + 0.6), CFrame.lookAt((a + b) / 2, b), C.White, Enum.Material.SmoothPlastic)
	mark.CastShadow = false
end

local function playingField(x0: number, z0: number, x1: number, z1: number)
	local cx, cz = (x0 + x1) / 2, (z0 + z1) / 2
	local hw, hd = (x1 - x0) / 2 - 20, (z1 - z0) / 2 - 20
	-- Touchlines, halfway line, centre circle and the two penalty boxes
	line(cx - hw, cz - hd, cx + hw, cz - hd)
	line(cx - hw, cz + hd, cx + hw, cz + hd)
	line(cx - hw, cz - hd, cx - hw, cz + hd)
	line(cx + hw, cz - hd, cx + hw, cz + hd)
	line(cx, cz - hd, cx, cz + hd)
	for k = 0, 11 do
		local a1, a2 = k / 12 * 2 * math.pi, (k + 1) / 12 * 2 * math.pi
		line(cx + math.cos(a1) * 18, cz + math.sin(a1) * 18, cx + math.cos(a2) * 18, cz + math.sin(a2) * 18)
	end
	for _, side in { -1, 1 } do
		local goalLine = cx + side * hw
		local boxEdge = goalLine - side * 32
		line(boxEdge, cz - 34, boxEdge, cz + 34)
		line(goalLine, cz - 34, boxEdge, cz - 34)
		line(goalLine, cz + 34, boxEdge, cz + 34)
		-- The goal: two posts and a crossbar
		for _, post in { -8, 8 } do
			TownKit.post(0.5, 8, Vector3.new(goalLine, 0, cz + post), C.White, Enum.Material.SmoothPlastic)
		end
		local bar = TownKit.detail(Vector3.new(0.5, 0.5, 16.5), CFrame.new(goalLine, 8, cz), C.White, Enum.Material.SmoothPlastic)
		bar.CanCollide = true
	end
	-- Trees along one long side
	for x = x0 + 10, x1 - 10, 26 do
		if random:NextNumber() < 0.8 then
			TownProps.tree(Vector3.new(x + random:NextNumber(-4, 4), 0, z1 - 6), random:NextNumber(1.1, 1.6))
		end
	end
end

local SOIL = Color3.fromRGB(96, 74, 54)
local CROP_GREENS = { Color3.fromRGB(82, 120, 58), Color3.fromRGB(104, 136, 64), Color3.fromRGB(70, 104, 50) }

local function allotments(x0: number, z0: number, x1: number, z1: number)
	-- Strips of dug earth and rows of vegetables, a shed on every few plots, a wire fence round it all
	local z = z0 + 8
	local index = 0
	while z < z1 - 14 do
		local x = x0 + 8
		while x < x1 - 30 do
			local plot = Vector3.new(x + 13, 0.03, z + 5)
			local dug = random:NextNumber() < 0.45
			local part = box(Vector3.new(26, 0.08, 10), CFrame.new(plot), if dug then SOIL else CROP_GREENS[random:NextInteger(1, #CROP_GREENS)], if dug then Enum.Material.Ground else Enum.Material.LeafyGrass)
			part.CastShadow = false
			part.CanTouch = false
			index += 1
			if index % 5 == 0 then
				local shed = box(Vector3.new(6, 6.5, 5), CFrame.new(x + 26, 3.25, z + 5), Color3.fromRGB(104, 80, 58), Enum.Material.WoodPlanks)
				shed.CanTouch = false
			end
			x += 32
		end
		z += 14
	end
	for _, edge in { { x0, z0, x1, z0 }, { x1, z0, x1, z1 }, { x1, z1, x0, z1 }, { x0, z1, x0, z0 } } do
		boundary(Vector3.new(edge[1], 0, edge[2]), Vector3.new(edge[3], 0, edge[4]), 5, 0.2, Color3.fromRGB(110, 120, 116), Enum.Material.DiamondPlate)
	end
end

local function copse(x0: number, z0: number, x1: number, z1: number)
	for z = z0 + 10, z1 - 10, 22 do
		for x = x0 + 10, x1 - 10, 22 do
			local at = Vector3.new(x + random:NextNumber(-8, 8), 0, z + random:NextNumber(-8, 8))
			if random:NextNumber() < 0.75 then
				TownProps.tree(at, random:NextNumber(1.1, 1.8), if random:NextNumber() < 0.3 then "tall" else nil)
			else
				TownProps.bush(at, random:NextNumber(1, 1.5))
			end
		end
	end
end

local function buildOpenLand(): number
	local made = 0
	for index, area in layout.areas do
		if area[1] ~= "suburb" and area[1] ~= "terraces" then
			continue
		end
		local b = areaBounds[index]
		for z = b[2] + 20, b[4] - 160, 60 do
			for x = b[1] + 20, b[3] - 230, 60 do
				local roll = random:NextNumber()
				local w, d = 230, 160
				if roll >= 0.5 then
					w, d = 170, 120
				end
				local x1, z1 = x + w, z + d
				if inPolygon(x, z, area[2]) and inPolygon(x1, z1, area[2]) and rectFree(x - 10, z - 10, x1 + 10, z1 + 10) then
					if roll < 0.5 then
						playingField(x, z, x1, z1)
					elseif roll < 0.8 then
						allotments(x, z, x1, z1)
					else
						copse(x, z, x1, z1)
					end
					fill(rectangle(x, z, x1, z1), SITE, "free")
					made += 1
				end
			end
		end
		-- Trees dotted over the rest
		for z = b[2] + 20, b[4], 45 do
			for x = b[1] + 20, b[3], 45 do
				local at = Vector3.new(x + random:NextNumber(-15, 15), 0, z + random:NextNumber(-15, 15))
				if random:NextNumber() < 0.3 and inPolygon(at.X, at.Z, area[2]) and clearOfRoads(at.X, at.Z, 14) and cellAt(at.X, at.Z) == FREE then
					TownProps.tree(at, random:NextNumber(1, 1.6), if random:NextNumber() < 0.3 then "wide" else nil)
				end
			end
		end
	end
	return made
end

-- The bigger sites (hospital, science park, retail park, industrial estate, university) also get buildings
-- dotted over the space behind the ones along the roads
local function buildCampuses()
	for _, area in layout.areas do
		local zone = area[1]
		if zone ~= "hospital" and zone ~= "sciencepark" and zone ~= "westcam" and zone ~= "retail" and zone ~= "industrial" then
			continue
		end
		local x0, z0, x1, z1 = math.huge, math.huge, -math.huge, -math.huge
		for _, c in area[2] do
			x0, z0, x1, z1 = math.min(x0, c[1]), math.min(z0, c[2]), math.max(x1, c[1]), math.max(z1, c[2])
		end
		local spacing = 150
		for z = z0 + spacing / 2, z1, spacing do
			for x = x0 + spacing / 2, x1, spacing do
				local at = Vector3.new(x + random:NextNumber(-20, 20), 0, z + random:NextNumber(-20, 20))
				if inPolygon(at.X, at.Z, area[2]) then
					local plan = choosePlan(zone, "town")
					if plan then
						local facing = if random:NextNumber() < 0.5 then Vector3.new(0, 0, 1) else Vector3.new(0, 0, -1)
						placeBuilding(plan, at + facing * 30, facing)
					end
				end
			end
		end
	end
end

-- Parks, landmarks and depots ----------------------------------------------------------------

local function makeDepot(name: string, depots: Folder): Model
	local depot = Instance.new("Model")
	depot.Name = name
	depot.Parent = depots
	return depot
end

-- A college chapel like King's: a long, tall stone building with big windows, buttresses and a pinnacle at
-- each corner, standing on a lawn by the river
local function chapel(frame: CFrame, length: number, width: number, height: number)
	local stone = Color3.fromRGB(214, 196, 150)
	box(Vector3.new(width, height, length), frame * CFrame.new(0, height / 2, 0), stone, Enum.Material.Limestone)
	-- Roof
	box(Vector3.new(width - 2, 3, length - 2), frame * CFrame.new(0, height + 1.5, 0), Color3.fromRGB(150, 148, 140), Enum.Material.Slate)
	-- Tall windows down both sides, between buttresses
	local bays = math.floor(length / 24)
	for k = 0, bays - 1 do
		local z = -length / 2 + (k + 0.5) * length / bays
		for _, side in { 1, -1 } do
			local window = TownKit.detail(Vector3.new(0.3, height * 0.68, length / bays * 0.62), frame * CFrame.new(side * (width / 2 + 0.1), height * 0.52, z), Color3.fromRGB(60, 70, 90), Enum.Material.Glass)
			window.Transparency = 0.1
			local buttress = box(Vector3.new(4, height * 0.9, 4), frame * CFrame.new(side * (width / 2 + 2), height * 0.45, z + length / bays / 2), stone, Enum.Material.Limestone)
			buttress.CanCollide = k < bays - 1
			TownKit.detail(Vector3.new(2, 8, 2), frame * CFrame.new(side * (width / 2 + 2), height + 4, z + length / bays / 2), stone, Enum.Material.Limestone)
		end
	end
	-- The four corner towers with spires
	for _, sx in { 1, -1 } do
		for _, sz in { 1, -1 } do
			local at = frame * CFrame.new(sx * (width / 2 - 1), 0, sz * (length / 2 - 1))
			box(Vector3.new(8, height + 18, 8), at * CFrame.new(0, (height + 18) / 2, 0), stone, Enum.Material.Limestone)
			local spire = TownKit.detail(Vector3.new(5, 14, 5), at * CFrame.new(0, height + 25, 0), stone, Enum.Material.Limestone)
			spire.CanCollide = false
		end
	end
	-- The great east and west windows
	for _, sz in { 1, -1 } do
		local window = TownKit.detail(Vector3.new(width * 0.6, height * 0.6, 0.3), frame * CFrame.new(0, height * 0.55, sz * (length / 2 + 0.1)), Color3.fromRGB(60, 70, 90), Enum.Material.Glass)
		window.Transparency = 0.1
	end
end

local function marketStalls(x0: number, z0: number, x1: number, z1: number)
	box(Vector3.new(x1 - x0, 0.4, z1 - z0), CFrame.new((x0 + x1) / 2, PAVEMENT_TOP - 0.2, (z0 + z1) / 2), Color3.fromRGB(150, 140, 128), Enum.Material.Cobblestone)
	local colours = { Color3.fromRGB(30, 80, 160), Color3.fromRGB(170, 30, 40), Color3.fromRGB(30, 120, 60), Color3.fromRGB(220, 200, 60), Color3.fromRGB(240, 240, 240) }
	for x = x0 + 18, x1 - 18, 24 do
		for z = z0 + 18, z1 - 18, 30 do
			local base = Vector3.new(x, PAVEMENT_TOP, z)
			for _, dx in { -5, 5 } do
				for _, dz in { -6, 6 } do
					TownKit.post(0.3, 8, base + Vector3.new(dx, 0, dz), Color3.fromRGB(80, 80, 80), Enum.Material.Metal)
				end
			end
			local canopy = box(Vector3.new(12, 0.6, 14), CFrame.new(base + Vector3.new(0, 8.3, 0)), colours[random:NextInteger(1, #colours)], Enum.Material.Fabric)
			canopy.CanCollide = false
			box(Vector3.new(10, 3, 4), CFrame.new(base + Vector3.new(0, 1.5, -4)), Color3.fromRGB(120, 90, 60), Enum.Material.WoodPlanks)
		end
	end
end

local function stadium(x0: number, z0: number, x1: number, z1: number)
	local middle = Vector3.new((x0 + x1) / 2, 0, (z0 + z1) / 2)
	local w, d = x1 - x0, z1 - z0
	box(Vector3.new(w - 80, 0.3, d - 80), CFrame.new(middle + Vector3.new(0, 0.15, 0)), Color3.fromRGB(70, 140, 60), Enum.Material.Grass)
	-- Stands on all four sides, stepped, with a roof
	local stand = Color3.fromRGB(150, 30, 40)
	local sides: { { offset: Vector3, length: number, turn: number } } = {
		{ offset = Vector3.new(0, 0, -(d / 2 - 20)), length = w - 40, turn = 0 },
		{ offset = Vector3.new(0, 0, d / 2 - 20), length = w - 40, turn = math.pi },
		{ offset = Vector3.new(-(w / 2 - 20), 0, 0), length = d - 40, turn = math.pi / 2 },
		{ offset = Vector3.new(w / 2 - 20, 0, 0), length = d - 40, turn = -math.pi / 2 },
	}
	for _, info in sides do
		local at = CFrame.new(middle + info.offset) * CFrame.Angles(0, info.turn, 0)
		for step = 0, 4 do
			box(Vector3.new(info.length, 3 + step * 3, 6), at * CFrame.new(0, (3 + step * 3) / 2, step * -6 + 12), if step % 2 == 0 then stand else Color3.fromRGB(240, 240, 240), Enum.Material.Concrete)
		end
		box(Vector3.new(info.length, 1, 34), at * CFrame.new(0, 26, 0), Color3.fromRGB(70, 70, 75), Enum.Material.Metal)
	end
	for _, sx in { 1, -1 } do
		for _, sz in { 1, -1 } do
			TownKit.post(1.2, 60, middle + Vector3.new(sx * (w / 2 - 8), 0, sz * (d / 2 - 8)), Color3.fromRGB(120, 120, 125), Enum.Material.Metal)
		end
	end
	fill(rectangle(x0, z0, x1, z1), SITE, "notRoad")
end

local function airfield(x0: number, z0: number, x1: number, z1: number)
	local middle = Vector3.new((x0 + x1) / 2, 0, (z0 + z1) / 2)
	box(Vector3.new(x1 - x0 - 100, 0.3, 70), CFrame.new(middle + Vector3.new(0, 0.15, 0)) * CFrame.Angles(0, math.rad(-8), 0), Color3.fromRGB(70, 70, 72), Enum.Material.Concrete)
	local dashes = math.floor((x1 - x0 - 160) / 120)
	for k = -dashes, dashes do
		local dash = TownKit.detail(Vector3.new(30, 0.05, 1.2), CFrame.new(middle + Vector3.new(0, 0.33, 0)) * CFrame.Angles(0, math.rad(-8), 0) * CFrame.new(k * 60, 0, 0), C.White, Enum.Material.Concrete)
		dash.CastShadow = false
	end
	-- Hangars and a control tower along the side nearest town
	for k = 0, 2 do
		local at = Vector3.new(x0 + 140 + k * 130, 0, z1 - 120)
		box(Vector3.new(100, 30, 80), CFrame.new(at + Vector3.new(0, 15, 0)), Color3.fromRGB(200, 204, 210), Enum.Material.CorrodedMetal)
	end
	local tower = Vector3.new(x0 + 560, 0, z1 - 110)
	box(Vector3.new(16, 40, 16), CFrame.new(tower + Vector3.new(0, 20, 0)), Color3.fromRGB(230, 230, 230), Enum.Material.Concrete)
	local cab = box(Vector3.new(22, 9, 22), CFrame.new(tower + Vector3.new(0, 44.5, 0)), Color3.fromRGB(60, 80, 96), Enum.Material.Glass)
	cab.Transparency = 0.2
	fill(rectangle(x0, z0, x1, z1), SITE, "notRoad")
end

-- Lakes (Milton Country Park): flat water in among the grass, with reeds and trees round the edge
local function lake(x0: number, z0: number, x1: number, z1: number)
	local middle = Vector3.new((x0 + x1) / 2, 0, (z0 + z1) / 2)
	local w, d = x1 - x0, z1 - z0
	local pools: { { offset: Vector3, share: number } } = {
		{ offset = Vector3.new(-w * 0.16, 0, -d * 0.1), share = 0.62 },
		{ offset = Vector3.new(w * 0.2, 0, d * 0.12), share = 0.5 },
	}
	for _, pool in pools do
		local centre = middle + pool.offset
		local size = math.min(w, d) * pool.share
		local water = box(Vector3.new(0.3, size, size * 1.3), CFrame.new(centre.X, 0.02, centre.Z) * CFrame.Angles(0, math.rad(20), math.pi / 2), C.Water, Enum.Material.Glass)
		water.Shape = Enum.PartType.Cylinder
		water.Transparency = 0.1
		water.Reflectance = 0.25
		water.CanCollide = false
		for k = 0, 13 do
			local angle = k / 14 * 2 * math.pi
			local edge = centre + CFrame.Angles(0, math.rad(20), 0):VectorToWorldSpace(Vector3.new(math.sin(angle) * size * 0.65 + 6, 0, math.cos(angle) * size * 0.5 + 6))
			if random:NextNumber() < 0.6 then
				TownProps.tree(edge, random:NextNumber(1, 1.5), if random:NextNumber() < 0.3 then "wide" else nil)
			else
				TownProps.bush(edge, random:NextNumber(1, 1.4))
			end
		end
	end
	fill(rectangle(x0, z0, x1, z1), SITE, "free")
end

-- An open common like Parker's Piece or Jesus Green: mown grass with paths across it corner to corner, lined
-- with trees, trees round the edge and benches. Roads and the river can run through it, so every path piece
-- and tree is checked against the ground first. `wild` ones (Coe Fen, Sheep's Green) have rough grass, more
-- trees and bushes, and only one path.
local PATH = Color3.fromRGB(194, 180, 152)

local function openGround(x: number, z: number): boolean
	local cell = cellAt(x, z)
	return cell == FREE or cell == SITE
end

local function commonPath(a: Vector3, b: Vector3, treeSpacing: number)
	local length = (b - a).Magnitude
	local direction = (b - a).Unit
	local across = Vector3.new(-direction.Z, 0, direction.X)
	local function lay(from: number, to: number)
		if to - from > 6 then
			local mid = a + direction * ((from + to) / 2) + Vector3.new(0, 0.01, 0)
			TownKit.detail(Vector3.new(7, 0.12, to - from), CFrame.lookAt(mid, mid + direction), PATH, Enum.Material.Sand).CastShadow = false
		end
	end
	local runStart: number? = nil
	local s = 0
	while s <= length do
		local p = a + direction * s
		local ok = openGround(p.X, p.Z)
		if ok and not runStart then
			runStart = s
		elseif not ok and runStart then
			lay(runStart, s - 4)
			runStart = nil
		end
		if ok and treeSpacing > 0 and s % treeSpacing < 4 and s > 20 and s < length - 20 then
			for _, side in { 1, -1 } do
				local at = p + across * side * 11
				if openGround(at.X, at.Z) then
					TownProps.tree(at, random:NextNumber(1.2, 1.6), "tall")
				end
			end
		end
		s += 4
	end
	if runStart then
		lay(runStart, length)
	end
end

local function common(x0: number, z0: number, x1: number, z1: number, wild: boolean)
	fill(rectangle(x0, z0, x1, z1), SITE, "free")
	local w, d = x1 - x0, z1 - z0
	if wild then
		box(Vector3.new(w, 0.1, d), CFrame.new((x0 + x1) / 2, 0.0, (z0 + z1) / 2), Color3.fromRGB(104, 136, 66), Enum.Material.LeafyGrass).CanCollide = false
	end
	-- Paths corner to corner (Parker's Piece's famous crossing), and across the middle on the bigger ones
	local corners = { Vector3.new(x0 + 6, 0, z0 + 6), Vector3.new(x1 - 6, 0, z0 + 6), Vector3.new(x1 - 6, 0, z1 - 6), Vector3.new(x0 + 6, 0, z1 - 6) }
	commonPath(corners[1], corners[3], if wild then 0 else 36)
	if not wild then
		commonPath(corners[2], corners[4], 36)
		if w > 500 then
			commonPath(Vector3.new(x0 + 6, 0, (z0 + z1) / 2), Vector3.new(x1 - 6, 0, (z0 + z1) / 2), 0)
		end
		-- A tall lamp where the paths cross
		local middle = Vector3.new((x0 + x1) / 2, 0, (z0 + z1) / 2)
		if openGround(middle.X, middle.Z) then
			TownProps.lampPost(middle + Vector3.new(4, 0, 0), Vector3.new(-1, 0, 0))
		end
	end
	-- Trees round the edge, with gaps
	local spacing = if wild then 22 else 34
	for _, edge in { { corners[1], corners[2] }, { corners[2], corners[3] }, { corners[3], corners[4] }, { corners[4], corners[1] } } do
		local a, b = edge[1], edge[2]
		local length = (b - a).Magnitude
		local direction = (b - a).Unit
		local inward = Vector3.new(-direction.Z, 0, direction.X)
		local s = 10
		while s < length - 10 do
			local at = a + direction * s + inward * random:NextNumber(4, 10)
			if openGround(at.X, at.Z) and random:NextNumber() < 0.8 then
				TownProps.tree(at, random:NextNumber(1.2, 1.8), if random:NextNumber() < 0.4 then "wide" else nil)
			end
			s += spacing + random:NextNumber(-6, 10)
		end
	end
	-- Scattered trees and bushes across the wild ones, a bench or two on the others
	if wild then
		for _ = 1, math.floor(w * d / 3000) do
			local at = Vector3.new(random:NextNumber(x0 + 10, x1 - 10), 0, random:NextNumber(z0 + 10, z1 - 10))
			if openGround(at.X, at.Z) then
				if random:NextNumber() < 0.5 then
					TownProps.tree(at, random:NextNumber(1, 1.7), if random:NextNumber() < 0.5 then "wide" else nil)
				else
					TownProps.bush(at, random:NextNumber(1, 1.6))
				end
			end
		end
	else
		for _, f in { 0.3, 0.7 } do
			local at = corners[1]:Lerp(corners[3], f) + Vector3.new(6, 0, -6)
			if openGround(at.X, at.Z) then
				TownProps.bench(at, (corners[3] - corners[1]).Unit:Cross(Vector3.yAxis))
			end
		end
	end
	table.insert(minimap, { (x0 + x1) / 2 :: any, (z0 + z1) / 2, w, d, "park" })
end

local function buildSites(depots: Folder)
	for _, site in layout.sites do
		local kind, x0, z0, x1, z1 = site[1], site[2], site[3], site[4], site[5]
		if kind == "parkerspiece" or kind == "jesusgreen" or kind == "midsummer" or kind == "coldhamscommon" then
			common(x0, z0, x1, z1, false)
		elseif kind == "coefen" or kind == "sheepsgreen" then
			common(x0, z0, x1, z1, true)
		elseif kind == "christspieces" or kind == "botanic" then
			-- Walled gardens: the hedged park with a pond
			fill(rectangle(x0, z0, x1, z1), SITE, "notRoad")
			TownBuildings.park(x0, x1, z0, z1, random)
			table.insert(minimap, { (x0 + x1) / 2 :: any, (z0 + z1) / 2, x1 - x0, z1 - z0, "park" })
		elseif kind == "marketsquare" then
			fill(rectangle(x0, z0, x1, z1), SITE, "notRoad")
			marketStalls(x0, z0, x1, z1)
		elseif kind == "kingscollege" then
			fill(rectangle(x0, z0, x1, z1), SITE, "notRoad")
			box(Vector3.new(x1 - x0, 0.3, z1 - z0), CFrame.new((x0 + x1) / 2, 0.15, (z0 + z1) / 2), Color3.fromRGB(96, 146, 70), Enum.Material.Grass)
			local frame = CFrame.new((x0 + x1) / 2 + 40, 0, (z0 + z1) / 2) * CFrame.Angles(0, math.pi / 2, 0)
			chapel(frame, 260, 56, 78)
			mapInfo:SetAttribute("Chapel", frame.Position)
			table.insert(minimap, { (x0 + x1) / 2 :: any, (z0 + z1) / 2, x1 - x0, z1 - z0, "park" })
		elseif kind == "stadium" then
			stadium(x0, z0, x1, z1)
		elseif kind == "airport" then
			airfield(x0, z0, x1, z1)
		elseif kind == "lakes" then
			lake(x0, z0, x1, z1)
		end
	end

	-- Sites that face a road: the depots
	for _, site in layout.frontSites do
		local front = Vector3.new(site.x, 0, site.z)
		local facing = Vector3.new(site.fx, 0, site.fz)
		local frame = CFrame.lookAt(front, front + facing)
		local across = frame.RightVector
		local back = -facing * site.depth
		fill({ front - across * site.width / 2, front + across * site.width / 2, front + across * site.width / 2 + back, front - across * site.width / 2 + back }, SITE, "notRoad")
		local centre = front + back / 2
		table.insert(minimap, { "q" :: any, math.round(centre.X), math.round(centre.Z), site.width, site.depth, math.round(math.deg(math.atan2(facing.X, facing.Z))), "yard" })
		if site.kind == "petrol" then
			TownBuildings.petrolStation(frame, site.width, site.depth, makeDepot("Car", depots))
		elseif site.kind == "busgarage" then
			TownBuildings.busGarage(frame, site.width, site.depth, makeDepot("Bus", depots))
		elseif site.kind == "police" then
			TownBuildings.policeStation(frame, site.width, site.depth, makeDepot("Emergency", depots))
		end
	end
end

-- Street furniture -----------------------------------------------------------------------------


-- The AHDEV pack's own special road pieces (zebra crossing, bus stop) fit our town streets exactly, so where
-- the place has the pack they're dropped onto the road (sitting a hair above it so the two never flicker)
local function packPiece(name: string): Model?
	local pack = ServerStorage:FindFirstChild("PackImport")
	local roads = pack and pack:FindFirstChild("AHDEV Roads")
	if not roads then
		return nil
	end
	for _, d in roads:GetDescendants() do
		if d:IsA("Model") and d.Name == name and not d:FindFirstAncestor("[DELETE] Example Layout") then
			return d
		end
	end
	return nil
end

type PackPiece = { model: Model, centre: CFrame, size: Vector3 }
local packCache: { [string]: PackPiece } = {}
local packMissing: { [string]: boolean } = {}

local function placePackPiece(name: string, at: Vector3, direction: Vector3): boolean
	local cached = packCache[name]
	if not cached then
		if packMissing[name] then
			return false
		end
		local model = packPiece(name)
		if not model then
			packMissing[name] = true
			return false
		end
		local cf, size = model:GetBoundingBox()
		cached = { model = model, centre = cf, size = size }
		packCache[name] = cached
	end
	local piece = cached.model:Clone()
	-- The pack's roads run along their Z: put the middle of the piece's road surface on ours. Its road is the
	-- quarter-stud slab at the bottom, so its top sits just above our road's top.
	local bottom = cached.centre.Position.Y - cached.size.Y / 2
	local pivotToCentre = piece:GetPivot():ToObjectSpace(cached.centre)
	local target = CFrame.lookAt(at, at + direction) * CFrame.new(0, (cached.centre.Position.Y - bottom) - 0.25 + ROAD_TOP + 0.03, 0)
	piece:PivotTo(target * pivotToCentre:Inverse())
	for _, d in piece:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanTouch = false
		elseif d:IsA("LuaSourceContainer") then
			d:Destroy()
		end
	end
	piece.Parent = TownKit.getParent()
	return true
end

local function buildStreetFurniture(result: RoadNetwork.Result)
	for index, road in result.roads do
		local path = road.path
		local s0, s1 = road.startTrim + 10, path.length - road.endTrim - 10
		if s1 - s0 < 40 then
			continue
		end
		local function onGround(s: number): boolean
			local p = RoadKit.at(path, s)
			return math.abs(p.Y - ROAD_TOP - groundAt(p.X, p.Z)) < 1
		end
		local noParking: { { number } } = {}
		local kind = road.kind

		if road.side == "pavement" then
			-- One lamp post every 110 studs, swapping sides, at the kerb
			local s = s0 + 30
			local lampSide = if index % 2 == 0 then 1 else -1
			while s < s1 - 20 do
				if onGround(s) and s > road.sideFrom[lampSide] + 10 and s < road.sideTo[lampSide] - 10 then
					local p, _, n = RoadKit.at(path, s)
					TownProps.lampPost(p + n * lampSide * (road.hw + KERB_WIDTH + 0.8), -n * lampSide)
				end
				s += 110
				lampSide = -lampSide
			end
			local middle = (s0 + s1) / 2
			-- Town streets the same size as the pack's: its zebra crossing or bus stop piece halfway along
			if kind == "town" and s1 - s0 > 160 and onGround(middle) then
				local p, direction = RoadKit.at(path, middle)
				local placed = false
				if index % 3 == 0 then
					placed = placePackPiece("[ROAD] Single Carriageway 1L Zebra Crossing", Vector3.new(p.X, 0, p.Z), direction)
				elseif index % 3 == 1 then
					placed = placePackPiece("[ROAD] Single Carriageway 1L Bus Stop", Vector3.new(p.X, 0, p.Z), direction)
				end
				if placed then
					table.insert(noParking, { middle - 30, middle + 30 })
				end
			end
			-- A bus stop on the longer main roads
			if (kind == "main" or kind == "high") and s1 - s0 > 600 then
				local at = s0 + (s1 - s0) * 0.5
				if onGround(at) then
					local p, along, n = RoadKit.at(path, at)
					local stopSide = if index % 2 == 0 then 1 else -1
					local kerb = Vector3.new(p.X, 0, p.Z) + n * stopSide * road.hw
					TownProps.busStop(CFrame.lookAt(kerb, kerb - n * stopSide))
					TownProps.bin(kerb + n * stopSide * 2.5 - along * 11, -n * stopSide)
					table.insert(noParking, { at - 30, at + 30 })
				end
			end
			-- A zebra crossing halfway along the high streets
			if kind == "high" and onGround(middle) then
				local p, direction, n = RoadKit.at(path, middle)
				TownProps.zebra(CFrame.lookAt(Vector3.new(p.X, 0, p.Z), Vector3.new(p.X, 0, p.Z) + direction), road.hw * 2)
				for _, kerbSide in { -1, 1 } do
					for _, along in { -4.5, 4.5 } do
						TownProps.belisha(p + n * kerbSide * (road.hw + 1.5) + direction * along)
					end
				end
				table.insert(noParking, { middle - 32, middle + 32 })
			end
			-- A red telephone box on the high streets
			if kind == "high" then
				local at = s0 + (s1 - s0) * 0.3
				if onGround(at) then
					local p, _, n = RoadKit.at(path, at)
					local spot = p + n * -(road.hw + KERB_WIDTH + 2.5)
					TownProps.phoneBox(Vector3.new(spot.X, 0, spot.Z), n, false)
					table.insert(noParking, { at - 12, at + 12 })
				end
			end
		end

		-- 30 limit signs where roads come into the villages and town, national limit signs going out
		if (kind == "aroad" or kind == "lane") and s1 - s0 > 200 then
			for _, info in { { s0 + 25, 1 }, { s1 - 25, -1 } } do
				local at, side = info[1], info[2]
				local p, direction, n = RoadKit.at(path, at)
				local inside = zoneAt(p.X, p.Z) ~= nil
				local beyond = RoadKit.at(path, at + side * 120)
				local outside = zoneAt(beyond.X, beyond.Z) == nil
				if onGround(at) and inside and outside then
					local spot = p + n * side * (road.hw + 3)
					TownProps.limitSign(Vector3.new(spot.X, 0, spot.Z), direction * -side, 30)
				end
			end
		end

		-- Parked cars along both kerbs, clear of junctions (where the double yellows are)
		local parking = road.profile.parking or 0
		if parking > 0 and road.side == "pavement" then
			for _, side in { 1, -1 } do
				local from, to = road.sideFrom[side] + 60, road.sideTo[side] - 60
				local s = from + random:NextNumber() * 10
				while s < to do
					local blocked = not onGround(s)
					for _, range in noParking do
						if s > range[1] and s < range[2] then
							blocked = true
						end
					end
					if not blocked and random:NextNumber() < 0.72 then
						local p, direction, n = RoadKit.at(path, s)
						local at = p + n * side * (road.hw - parking / 2)
						local facing = if side > 0 then direction else -direction
						local degrees = math.deg(math.atan2(-facing.X, -facing.Z))
						table.insert(parkingSpots, { math.round(at.X * 10) / 10, math.round(at.Y * 100) / 100, math.round(at.Z * 10) / 10, math.round(degrees) })
					end
					s += random:NextNumber(21, 25)
				end
			end
		end
	end
end

-- Pavements for the people walking about: a line of points down the middle of each pavement (the
-- Pedestrians client script walks people along them). Each line is { x1, z1, x2, z2, ... }.
local pavementLines: { { number } } = {}

local function collectPavements(result: RoadNetwork.Result)
	table.clear(pavementLines)
	for _, road in result.roads do
		if road.side ~= "pavement" then
			continue
		end
		local path = road.path
		for _, side in { 1, -1 } do
			local from = (road.sideFrom[side] or road.startTrim) + 4
			local to = (road.sideTo[side] or (path.length - road.endTrim)) - 4
			local flat: { number } = {}
			local s = from
			while s <= to do
				local p, _, n = RoadKit.at(path, s)
				if p.Y - ROAD_TOP > 1.5 then
					break -- not over bridges
				end
				local at = p + n * side * (road.hw + KERB_WIDTH + road.sideWidth * 0.5)
				table.insert(flat, math.round(at.X * 10) / 10)
				table.insert(flat, math.round(at.Z * 10) / 10)
				s += 24
			end
			if #flat >= 4 then
				table.insert(pavementLines, flat)
			end
		end
	end
end

-- The edge of the world: fields carrying on past it, an invisible wall so nobody drives off, and lines of
-- woodland out in the haze
local TREELINE = { Color3.fromRGB(52, 78, 44), Color3.fromRGB(60, 88, 50), Color3.fromRGB(46, 70, 40), Color3.fromRGB(66, 92, 54) }

local function buildEdges()
	local reach = 1200
	local width, depth = MAX_X - MIN_X, MAX_Z - MIN_Z
	for _, info in {
		{ Vector3.new(width + reach * 2, 4, reach), Vector3.new((MIN_X + MAX_X) / 2, -2.06, MIN_Z - reach / 2) },
		{ Vector3.new(width + reach * 2, 4, reach), Vector3.new((MIN_X + MAX_X) / 2, -2.06, MAX_Z + reach / 2) },
		{ Vector3.new(reach, 4, depth), Vector3.new(MIN_X - reach / 2, -2.06, (MIN_Z + MAX_Z) / 2) },
		{ Vector3.new(reach, 4, depth), Vector3.new(MAX_X + reach / 2, -2.06, (MIN_Z + MAX_Z) / 2) },
	} do
		for _, tile in TownKit.tiles(info[1], info[2], Color3.fromRGB(100, 136, 66), Enum.Material.Grass) do
			tile.Parent = groundModel
		end
	end
	local outline: { Vector3 } = {}
	for _, p in layout.outline do
		table.insert(outline, Vector3.new(p[1], 0, p[2]))
	end
	local middle = Vector3.zero
	for _, p in outline do
		middle += p
	end
	middle /= #outline
	for k = 1, #outline do
		local a, b = outline[k], outline[k % #outline + 1]
		local length = (b - a).Magnitude
		if length < 1 then
			continue
		end
		local along = (b - a).Unit
		local outward = Vector3.new(along.Z, 0, -along.X)
		if outward:Dot((a + b) / 2 - middle) < 0 then
			outward = -outward
		end
		local wallCentre = (a + b) / 2 + Vector3.new(0, 70, 0)
		local wall = box(Vector3.new(4, 140, length + 4), CFrame.lookAt(wallCentre, wallCentre + along), C.Grass)
		wall.Transparency = 1
		-- Woods and copses a little way out, as rounded green masses in the haze
		local d = 0
		while d < length do
			local w = random:NextNumber(50, 140)
			local deep = random:NextNumber(40, 100)
			local h = random:NextNumber(26, 48)
			local at = a + along * math.min(d + w / 2, length) + outward * (random:NextNumber(80, 420) + deep / 2)
			standIn(CFrame.lookAt(at + Vector3.new(0, h / 2, 0), at + Vector3.new(0, h / 2, 0) - outward), Vector3.new(w, h, deep), TREELINE[random:NextInteger(1, #TREELINE)], Enum.Material.LeafyGrass)
			d += w + random:NextNumber(10, 120)
		end
	end
end

-- Putting it all together ----------------------------------------------------------------------

function CambridgeMap.build()
	local started = os.clock()
	for _, name in { "Cambridge", "London", "Depots" } do
		local old = Workspace:FindFirstChild(name)
		if old then
			old:Destroy()
		end
	end
	Workspace.Terrain:Clear()
	buffer.fill(grid, 0, 0)
	table.clear(minimap)

	mapInfo = ReplicatedStorage:FindFirstChild("MapInfo") :: Configuration? or Instance.new("Configuration")
	mapInfo.Name = "MapInfo"
	mapInfo:ClearAllChildren()
	mapInfo.Parent = ReplicatedStorage

	folder = Instance.new("Folder")
	folder.Name = "Cambridge"
	TownKit.setParent(folder)
	farAway = Instance.new("Model")
	farAway.Name = "FarAway"
	farAway.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	farAway.Parent = folder
	local depots = Instance.new("Folder")
	depots.Name = "Depots"

	-- The place's own baseplate would cover the river, so drop it out of the way
	local baseplate = Workspace:FindFirstChild("Baseplate")
	if baseplate and baseplate:IsA("BasePart") then
		baseplate.Position = Vector3.new(baseplate.Position.X, -80, baseplate.Position.Z)
	end

	local stageStart = os.clock()
	local function stage(name: string)
		if RunService:IsStudio() then
			print(string.format("[CambridgeMap] %s (%.1fs)", name, os.clock() - stageStart))
		end
		stageStart = os.clock()
	end
	buildRiver()
	stage("river")
	local result = RoadNetwork.build(layout, groundAt, function(x: number, z: number): boolean
		return cellAt(x, z) == ROAD
	end, markRoads)
	stage("roads")
	buildGround()
	stage("ground and fields")
	buildRailway()
	buildBanks(result.roads)
	buildSites(depots)
	stage("railway, banks and sites")
	loadKit()
	table.clear(parkingSpots)
	buildingCount = 0
	buildStreets(result)
	buildInfill()
	buildCampuses()
	local openLand = buildOpenLand()
	stage("buildings")
	buildStreetFurniture(result)
	stage("street furniture")
	buildRoadsideHedges(result)
	local hedgeTrees = buildFieldHedges()
	local woodTrees = buildWoods()
	stage("hedges and woods")
	collectPavements(result)
	buildEdges()
	stage("edges")

	for _, entry in result.minimap do
		table.insert(minimap, entry)
	end
	local half = layout.river.width / 2
	for k = 2, #riverPath.points do
		local a, b = riverPath.points[k - 1], riverPath.points[k]
		table.insert(minimap, { "l" :: any, math.round(a.X), math.round(a.Z), math.round(b.X), math.round(b.Z), half * 2, "water" })
	end

	folder.Parent = Workspace
	depots.Parent = Workspace

	-- Tell the menus where to point the camera
	for _, depot in depots:GetChildren() do
		local spot = depot:GetAttribute("ShowroomSpot")
		if typeof(spot) == "CFrame" then
			mapInfo:SetAttribute("Showroom_" .. depot.Name, spot)
		end
	end
	-- Over the Backs, looking at the chapel with the river in front of it
	local chapelAt = mapInfo:GetAttribute("Chapel")
	local lookAt = if typeof(chapelAt) == "Vector3" then chapelAt + Vector3.new(0, 40, 0) else Vector3.new(-700, 40, 270)
	mapInfo:SetAttribute("MenuCamera", CFrame.lookAt(Vector3.new(-1150, 70, 520), lookAt))

	local minimapData = Instance.new("StringValue")
	minimapData.Name = "Minimap"
	minimapData.Value = HttpService:JSONEncode(minimap)
	minimapData.Parent = mapInfo

	local parkingData = Instance.new("StringValue")
	parkingData.Name = "ParkedCars"
	parkingData.Value = HttpService:JSONEncode(parkingSpots)
	parkingData.Parent = mapInfo

	local pavementData = Instance.new("StringValue")
	pavementData.Name = "Pavements"
	pavementData.Value = HttpService:JSONEncode(pavementLines)
	pavementData.Parent = mapInfo

	-- Players walking about start on Parker's Piece
	local spawn = Workspace:FindFirstChildOfClass("SpawnLocation")
	if spawn then
		spawn.CFrame = CFrame.new(660, PAVEMENT_TOP + 1.5, 330)
	end

	local parts = 0
	for _, descendant in folder:GetDescendants() do
		if descendant:IsA("BasePart") then
			parts += 1
		end
	end
	print(string.format("[CambridgeMap] Built Cambridge: %d roads, %d buildings, %d playing fields, allotments and copses, %d hedgerow and %d woodland trees, %d parking spaces, %d parts in %.1f seconds",
		#result.roads, buildingCount, openLand, hedgeTrees, woodTrees, #parkingSpots, parts, os.clock() - started))
	return result
end

-- Removes the map (for example after building it in Studio to look round, so the place file stays small and
-- the game builds it fresh when it starts)
function CambridgeMap.clear()
	for _, name in { "Cambridge", "Depots" } do
		local old = Workspace:FindFirstChild(name)
		if old then
			old:Destroy()
		end
	end
	local info = ReplicatedStorage:FindFirstChild("MapInfo")
	if info then
		info:Destroy()
	end
	Workspace.Terrain:Clear()
end

return CambridgeMap
