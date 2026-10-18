-- Builds London when the game starts, from the road plan in LondonLayout and the buildings in LondonFill
-- (both made by tools/london_layout.py): the ground, the Thames with its walls and bridges, every road (see
-- RoadNetwork), the parks and landmarks, the three team depots, every building, garden, wall and tree,
-- street lamps, bus stops and crossings. About 5,400 by 4,600 studs and packed edge to edge like Birmingham
-- Vehicle Simulator: a dual carriageway ring road round the West End and the City, high streets, and grids of
-- terraced back streets with cars parked both sides.
--
-- It also fills in ReplicatedStorage → MapInfo, which the menus and minimap read:
--   attributes MenuCamera, ClockTower, Showroom_Car, Showroom_Bus, Showroom_Emergency
--   a StringValue "Minimap" listing the roads (as lines), roundabouts (circles), the river and parks
-- and Workspace → Depots (one model per team with "Spawn" parts), which Cars uses.
--
-- To look round it in Studio without pressing Play, run this in the Command Bar:
--   require(game.ServerScriptService.Server.LondonMap).build()

local CollectionService = game:GetService("CollectionService")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local CityBuildings = require(script.Parent.CityBuildings)
local LondonFill = require(script.Parent.LondonFill)
local LondonLayout = require(script.Parent.LondonLayout)
local RoadKit = require(script.Parent.RoadKit)
local RoadNetwork = require(script.Parent.RoadNetwork)
local TownBuildings = require(script.Parent.TownBuildings)
local TownKit = require(script.Parent.TownKit)
local TownProps = require(script.Parent.TownProps)

local C = TownKit.Colours
local box = TownKit.box
local ROAD_TOP = TownKit.ROAD_TOP
local PAVEMENT_TOP = TownKit.PAVEMENT_TOP

local MIN_X, MAX_X, MIN_Z, MAX_Z = LondonLayout.bounds[1], LondonLayout.bounds[3], LondonLayout.bounds[2], LondonLayout.bounds[4]
local RIVER_BED = -14
local WATER_TOP = -3
local WALL_TOP = 1.6 -- the river wall stands this far above the ground as a parapet

local LondonMap = {}

local layout: any = LondonLayout
local random = Random.new(2026) -- the same "random" city every time
local folder: Folder
local mapInfo: Configuration
local minimap: { { any } } = {}

-- What's on the ground, in 4-stud squares, so buildings don't land on roads ----------------------

local CELL = 4
local GRID_W = math.ceil((MAX_X - MIN_X) / CELL)
local GRID_H = math.ceil((MAX_Z - MIN_Z) / CELL)
local FREE, VERGE, ROAD, WATER, SITE, RAISED = 0, 1, 2, 3, 4, 6
local grid = buffer.create(GRID_W * GRID_H)

local function cellAt(x: number, z: number): number
	local i = math.floor((x - MIN_X) / CELL)
	local j = math.floor((z - MIN_Z) / CELL)
	if i < 0 or j < 0 or i >= GRID_W or j >= GRID_H then
		return SITE -- off the map counts as taken
	end
	return buffer.readu8(grid, j * GRID_W + i)
end

-- Writes `value` into every square inside a convex shape (flat corners in order). `rule` decides
-- whether to overwrite what's there: "always", "free" (only empty squares) or "notRoad".
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

-- Height of the ground: the riverbed in the river, otherwise flat
local function groundAt(x: number, z: number): number
	return if cellAt(x, z) == WATER then RIVER_BED else 0
end

-- The river ----------------------------------------------------------------------------------

type Bank = { points: { Vector3 }, dists: { number }, outward: { Vector3 } }

local riverPath: RoadKit.Path
local banks: { [number]: Bank } = {}

local function buildRiver()
	local controls = {}
	for _, p in layout.river.points do
		table.insert(controls, Vector3.new(p[1], 0, p[2]))
	end
	riverPath = RoadKit.path(controls, layout.river.radius)
	local half = layout.river.width / 2
	local points, normals = riverPath.points, riverPath.normals

	-- Mark the water, so nothing gets built in it and bridges know to stand on piers
	for k = 2, #points do
		local a, b = points[k - 1], points[k]
		fill({ a + normals[k - 1] * half, b + normals[k] * half, b - normals[k] * half, a - normals[k - 1] * half }, WATER, "always")
	end

	-- The water itself, and a muddy bed
	local terrain = Workspace.Terrain
	for k = 2, #points do
		local a, b = points[k - 1], points[k]
		local middle = (a + b) / 2
		local length = (b - a).Magnitude
		local frame = CFrame.lookAt(middle, middle + (b - a))
		terrain:FillBlock(frame * CFrame.new(0, (RIVER_BED + WATER_TOP) / 2, 0), Vector3.new(half * 2 + 8, WATER_TOP - RIVER_BED, length + 8), Enum.Material.Water)
	end
	local bed = RoadKit.strip(RoadKit.offset(points, normals, 0, RIVER_BED), normals, -half - 4, half + 4, { colour = Color3.fromRGB(70, 62, 50), material = Enum.Material.Mud, thickness = 3 })
	for _, part in bed do
		part.CanQuery = false
	end

	-- The two banks: 1 is the north bank (left of the river as it flows east), -1 the south
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

-- Grass everywhere outside the river: a strip along each bank that follows it exactly, and a grid of
-- slightly lower tiles for everywhere else (the river loops round, so it can't be done in simple strips)
local groundModel: Model

local function buildGround()
	-- The ground is always loaded on every player's device: the strips are long, and with streaming Roblox
	-- left out the ones whose middle was far away, so you could see under the map
	groundModel = Instance.new("Model")
	groundModel.Name = "Ground"
	groundModel.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	groundModel.Parent = folder
	TownKit.setParent(groundModel)
	local half = layout.river.width / 2
	local points, normals = riverPath.points, riverPath.normals
	local grass = { colour = C.Grass, material = Enum.Material.Grass, thickness = 4 }
	local flat = RoadKit.offset(points, normals, 0, 0)
	RoadKit.strip(flat, normals, half, half + 170, grass)
	RoadKit.strip(flat, normals, -half - 170, -half, grass)

	-- How far a spot is from the middle of the river
	local function riverDistance(x: number, z: number): number
		local best = math.huge
		for k = 2, #points do
			local a, b = points[k - 1], points[k]
			local abX, abZ = b.X - a.X, b.Z - a.Z
			local len2 = abX * abX + abZ * abZ
			local t = if len2 > 0 then math.clamp(((x - a.X) * abX + (z - a.Z) * abZ) / len2, 0, 1) else 0
			local dx, dz = a.X + abX * t - x, a.Z + abZ * t - z
			local d = dx * dx + dz * dz
			if d < best then
				best = d
			end
		end
		return math.sqrt(best)
	end
	local CELL_SIZE = 40
	local reach = CELL_SIZE * 0.71 -- half the diagonal of a tile
	local columns = math.ceil((MAX_X - MIN_X) / CELL_SIZE)
	local function lay(from: number, to: number, z: number)
		-- In pieces, because Roblox won't make a part longer than 2,048 studs
		while from < to - 0.01 do
			local width = math.min(to - from, 2000)
			box(Vector3.new(width, 4, CELL_SIZE), CFrame.new(from + width / 2, -2.05, z + CELL_SIZE / 2), C.Grass, Enum.Material.Grass)
			from += width
		end
	end
	for z = MIN_Z, MAX_Z - 1, CELL_SIZE do
		local runStart: number? = nil
		for i = 0, columns - 1 do
			local x = MIN_X + i * CELL_SIZE
			local land = riverDistance(x + CELL_SIZE / 2, z + CELL_SIZE / 2) - reach > half + 2
			if land and not runStart then
				runStart = x
			elseif not land and runStart then
				lay(runStart, x, z)
				runStart = nil
			end
		end
		if runStart then
			lay(runStart, MIN_X + columns * CELL_SIZE, z)
		end
	end
	TownKit.setParent(folder)
end

-- Where roads cross a bank, as distances along it, so the walls and riverside paths have gaps for bridges
local function bridgeGaps(bank: Bank, roads: { RoadNetwork.Road }): { { number } }
	local gaps = {}
	for _, road in roads do
		local points = road.path.points
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
						local half = (road.hw + (if road.side == "pavement" then road.sideWidth else 0)) / math.max(sine, 0.3) + 5
						table.insert(gaps, { along - half, along + half })
					end
				end
			end
		end
	end
	return gaps
end

local function piecesOf(bank: Bank, gaps: { { number } }): { { Vector3 } }
	local pieces = {}
	local current: { Vector3 } = {}
	local function inGap(s: number): boolean
		for _, gap in gaps do
			if s > gap[1] and s < gap[2] then
				return true
			end
		end
		return false
	end
	for k, p in bank.points do
		if inGap(bank.dists[k]) then
			if #current >= 2 then
				table.insert(pieces, current)
			end
			current = {}
		else
			table.insert(current, p)
		end
	end
	if #current >= 2 then
		table.insert(pieces, current)
	end
	return pieces
end

-- Stone walls along both banks, and a riverside walk with trees and lamps where there's room
local function buildRiverWalls(roads: { RoadNetwork.Road })
	for _, side in { 1, -1 } do
		local bank = banks[side]
		-- Put extra points along the straights so gaps can start and stop part way along them
		local dense: Bank = { points = {}, dists = {}, outward = {} }
		for k = 1, #bank.points do
			if k > 1 then
				local a, b = bank.points[k - 1], bank.points[k]
				local steps = math.max(1, math.floor((b - a).Magnitude / 20))
				for j = 1, steps - 1 do
					table.insert(dense.points, a:Lerp(b, j / steps))
					table.insert(dense.dists, bank.dists[k - 1] + (bank.dists[k] - bank.dists[k - 1]) * j / steps)
					table.insert(dense.outward, bank.outward[k])
				end
			end
			table.insert(dense.points, bank.points[k])
			table.insert(dense.dists, bank.dists[k])
			table.insert(dense.outward, bank.outward[k])
		end
		local gaps = bridgeGaps(dense, roads)
		for _, piece in piecesOf(dense, gaps) do
			RoadKit.wall(piece, RIVER_BED - 2, WALL_TOP, 3, C.Stone, Enum.Material.Limestone)
		end
		-- The riverside walk: only where the land behind the wall is free
		local walk = { colour = C.Pavement, material = Enum.Material.Pavement, thickness = 2.5 }
		local count = 0
		for k = 2, #dense.points do
			local a, b = dense.points[k - 1], dense.points[k]
			local mid = (a + b) / 2 + dense.outward[k] * 9
			local s = (dense.dists[k - 1] + dense.dists[k]) / 2
			local blocked = false
			for _, gap in gaps do
				if s > gap[1] - 4 and s < gap[2] + 4 then
					blocked = true
				end
			end
			if blocked or cellAt(mid.X, mid.Z) ~= FREE or a.X < MIN_X or b.X > MAX_X then
				continue
			end
			local oa, ob = dense.outward[k - 1], dense.outward[k]
			local inner0, inner1 = a + oa * 1.5 + Vector3.new(0, PAVEMENT_TOP, 0), b + ob * 1.5 + Vector3.new(0, PAVEMENT_TOP, 0)
			local outer0, outer1 = a + oa * 16 + Vector3.new(0, PAVEMENT_TOP, 0), b + ob * 16 + Vector3.new(0, PAVEMENT_TOP, 0)
			RoadKit.quad(inner0, outer0, outer1, inner1, walk)
			fill({ a, b, b + ob * 18, a + oa * 18 }, VERGE, "free")
			count += 1
			if count % 3 == 0 then
				local at = mid + dense.outward[k] * 3
				TownProps.tree(Vector3.new(at.X, PAVEMENT_TOP, at.Z), 1.1)
			elseif count % 3 == 1 then
				TownProps.lampPost(mid - dense.outward[k] * 5, -dense.outward[k])
			end
		end
	end
end

-- Roads into the grid -------------------------------------------------------------------------

local function markRoads(result: RoadNetwork.Result)
	-- Raised roads first, then ground-level roads over the top of them, then pavements round both
	for pass = 1, 3 do
		for _, road in result.roads do
			local path = road.path
			local outer = road.hw + road.sideWidth + 2
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

-- Parks, landmarks and depots ----------------------------------------------------------------

local function makeDepot(name: string, depots: Folder): Model
	local depot = Instance.new("Model")
	depot.Name = name
	depot.Parent = depots
	return depot
end

local function buildSites(result: RoadNetwork.Result, depots: Folder)
	for _, site in layout.sites do
		local kind, x0, z0, x1, z1 = site[1], site[2], site[3], site[4], site[5]
		fill(rectangle(x0, z0, x1, z1), SITE, "notRoad")
		if kind == "hydepark" or kind == "stjames" or kind == "regentspark" or kind == "kenningtonpark" or kind == "square" then
			TownBuildings.park(x0, x1, z0, z1, random)
			table.insert(minimap, { (x0 + x1) / 2, (z0 + z1) / 2, x1 - x0, z1 - z0, "park" })
		elseif kind == "palace" then
			-- The palace faces the river, with the clock tower at the end by the bridge
			local length = (x1 - x0) - 90
			local front = Vector3.new(x0 + length / 2 + 10, PAVEMENT_TOP, z1 - 12)
			box(Vector3.new(x1 - x0, 0.4, z1 - z0), CFrame.new((x0 + x1) / 2, PAVEMENT_TOP - 0.2, (z0 + z1) / 2), C.Pavement, Enum.Material.Pavement)
			TownBuildings.palace(CFrame.lookAt(front, front + Vector3.new(0, 0, 1)), length, 70)
			local tower = Vector3.new(x1 - 40, PAVEMENT_TOP, z1 - 40)
			TownBuildings.clockTower(tower)
			mapInfo:SetAttribute("ClockTower", tower)
			for _ = 1, 6 do
				TownProps.tree(Vector3.new(x0 + 20 + random:NextNumber() * (length - 20), PAVEMENT_TOP, z0 + 10 + random:NextNumber() * 30), 1.2)
			end
		elseif kind == "bigwheel" then
			box(Vector3.new(x1 - x0, 0.4, z1 - z0), CFrame.new((x0 + x1) / 2, PAVEMENT_TOP - 0.2, (z0 + z1) / 2), C.Pavement, Enum.Material.Pavement)
			TownBuildings.bigWheel(Vector3.new((x0 + x1) / 2, 150, (z0 + z1) / 2), 135)
		elseif kind == "battersea" then
			box(Vector3.new(x1 - x0, 0.4, z1 - z0), CFrame.new((x0 + x1) / 2, PAVEMENT_TOP - 0.2, (z0 + z1) / 2), C.Pavement, Enum.Material.Pavement)
			TownBuildings.powerStation(Vector3.new((x0 + x1) / 2, 0, (z0 + z1) / 2), (x1 - x0) - 50, (z1 - z0) - 50)
		end
	end

	-- Sites that face a road: the depots and the motorway services
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
		elseif site.kind == "services" then
			TownBuildings.services(frame, site.width, site.depth)
		end
	end

	-- A column with lions in the middle of Trafalgar Square's roundabout
	for _, node in result.nodes do
		if node.name == "Trafalgar Square" then
			TownBuildings.column(node.pos + Vector3.new(0, TownKit.KERB_HEIGHT, 0))
		end
	end
end

-- Districts (for the street furniture): boxes of { kind, min x, min z, max x, max z } -------------

local function districtAt(x: number, z: number): string
	for _, d in layout.districts do
		if x >= d[2] and x <= d[4] and z >= d[3] and z <= d[5] then
			return d[1]
		end
	end
	return "terraces"
end

-- Buildings, gardens, walls and trees, from LondonFill --------------------------------------------

-- Buildings from the bought packs: ServerStorage → BuildingKit, made by tools/prepare_building_kit.luau.
-- Each one's front faces -Z with the middle of its front edge at the origin.
local kitModels: { [string]: Model } = {}
local kitParts = 0

local function loadKit()
	table.clear(kitModels)
	kitParts = 0
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

-- If the place doesn't have the kit, part-built stand-ins of the same kind
local KIT_FALLBACK: { [string]: string } = {
	terrace = "victorian", semi = "victorian", detached = "victorian", large = "georgian", shop = "shops", shopwide = "shops",
}

local LAWNS = { Color3.fromRGB(86, 136, 62), Color3.fromRGB(96, 142, 66), Color3.fromRGB(78, 126, 58), Color3.fromRGB(104, 146, 74) }
local FENCE = Color3.fromRGB(112, 84, 58)
local WALL_BRICK = Color3.fromRGB(132, 72, 54)

-- A spot facing `deg` (0 = north) at (x, z), on the ground
local function frameAt(x: number, z: number, deg: number, y: number?): CFrame
	return CFrame.new(x, y or 0, z) * CFrame.Angles(0, math.rad(deg), 0)
end

-- Spots where parked cars go (see buildStreetFurniture); car parks add to them here
local parkingSpots: { { number } } = {}

-- Stand-ins for far away. With streaming on, each player only has the buildings near them; everything
-- further off would vanish and leave grass. So every building also gets one plain block, a little smaller
-- than it and the same colour, in a model that every player always has. Up close it's hidden inside the
-- real building; far off it's the skyline.
local farAway: Model

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

-- For a kit building: a block inside its walls, below the roof (worked out once per kit model)
type KitStandIn = { offset: CFrame, size: Vector3, colour: Color3, material: Enum.Material }
local kitStandIns: { [string]: KitStandIn } = {}

local function kitStandIn(template: Model): KitStandIn
	local known = kitStandIns[template.Name]
	if known then
		return known
	end
	local cf, size = template:GetBoundingBox()
	local biggest: BasePart? = nil
	local volume = 0
	for _, part in template:GetDescendants() do
		if part:IsA("BasePart") and part.Transparency < 0.5 then
			local v = part.Size.X * part.Size.Y * part.Size.Z
			if v > volume then
				biggest, volume = part, v
			end
		end
	end
	local height = size.Y * 0.62
	local info: KitStandIn = {
		offset = template:GetPivot():ToObjectSpace(cf) * CFrame.new(0, -size.Y / 2 + height / 2, 0),
		size = Vector3.new(size.X * 0.84, height, size.Z * 0.7),
		colour = if biggest then biggest.Color else Color3.fromRGB(140, 90, 70),
		-- Plain, whatever the kit uses: some kit materials looked odd stretched over a whole block
		material = Enum.Material.SmoothPlastic,
	}
	kitStandIns[template.Name] = info
	return info
end

local function buildBuildings(): number
	local fill: any = LondonFill
	local styles = fill.styles
	local count = 0
	for _, b in fill.buildings do
		local isKit, style, x, z, deg = b[1] == 1, styles[b[2]], b[3], b[4], b[5]
		local width, depth, storeys, seed, isBack, flank = b[6], b[7], b[8], b[9], b[10] == 1, b[11] or 0
		local frame = frameAt(x, z, deg)
		if isKit then
			local template = kitModels[style]
			if template then
				local building = template:Clone()
				building:PivotTo(frame * CFrame.new(0, 0.05, 0))
				-- Small pieces (window frames, trims, gutters, plants) are just for looks: out of the physics engine
				for _, part in building:GetDescendants() do
					if part:IsA("BasePart") then
						part.CanTouch = false
						local size = part.Size
						if math.min(size.X, size.Y, size.Z) < 1.2 or size.X * size.Y * size.Z < 400 then
							part.CanCollide = false
							part.CanQuery = false
						end
					end
				end
				building.Parent = TownKit.getParent()
				local info = kitStandIn(template)
				standIn(building:GetPivot() * info.offset, info.size, info.colour, info.material)
				local parts = template:GetAttribute("Parts")
				kitParts += if typeof(parts) == "number" then parts else 0
				local kind = template:GetAttribute("Kind")
				-- Shops come right up to the pavement
				if kind == "shop" or kind == "shopwide" then
					box(Vector3.new(width, PAVEMENT_TOP, 1.6), frame * CFrame.new(0, PAVEMENT_TOP / 2, -0.7), C.Pavement, Enum.Material.Pavement)
				end
			else
				local kind = string.match(style, "^(%a+)_") or "terrace"
				CityBuildings.build(KIT_FALLBACK[kind] or "victorian", frame, width, depth, 2, seed, 0, false)
			end
		else
			local model = CityBuildings.build(style, frame, width, depth, storeys, seed, flank, isBack)
			-- The first part of every part-built building is its main body
			local body = model:FindFirstChildWhichIsA("BasePart")
			if body and body.Size.Y > 6 then
				standIn(body.CFrame, body.Size - Vector3.new(1.6, 0.8, 1.6), body.Color, body.Material)
			end
		end
		count += 1
	end
	return count
end

-- Back gardens with fences, paved yards with walls, car parks
local function buildGardens()
	local fill: any = LondonFill
	for index, g in fill.gardens do
		local kind, x, z, deg, w, d = g[1], g[2], g[3], g[4], g[5], g[6]
		local frame = frameAt(x, z, deg)
		if kind == 1 then
			TownKit.detail(Vector3.new(w, 0.2, d), frame * CFrame.new(0, 0.1, d / 2), LAWNS[index % #LAWNS + 1], Enum.Material.Grass)
			-- Fences down one side and across the back (the next garden along has the other side)
			box(Vector3.new(0.4, 5, d), frame * CFrame.new(w / 2 - 0.2, 2.5, d / 2), FENCE, Enum.Material.WoodPlanks)
			box(Vector3.new(w, 5, 0.4), frame * CFrame.new(0, 2.5, d - 0.2), FENCE, Enum.Material.WoodPlanks)
			if random:NextNumber() < 0.15 and w > 10 and d > 12 then
				box(Vector3.new(6, 6, 5), frame * CFrame.new(-w / 2 + 4, 3, d - 4), Color3.fromRGB(96, 76, 54), Enum.Material.WoodPlanks)
			end
		elseif kind == 2 then
			TownKit.detail(Vector3.new(w, 0.2, d), frame * CFrame.new(0, 0.1, d / 2), Color3.fromRGB(150, 148, 142), Enum.Material.Concrete)
			box(Vector3.new(w, 7, 0.8), frame * CFrame.new(0, 3.5, d - 0.4), WALL_BRICK, Enum.Material.Brick)
			if random:NextNumber() < 0.3 and w > 8 then
				box(Vector3.new(4, 4.5, 3), frame * CFrame.new(-w / 2 + 3, 2.25, d - 3), Color3.fromRGB(40, 70, 50), Enum.Material.Metal)
			end
		else
			box(Vector3.new(w, 0.2, d), frame * CFrame.new(0, 0.1, d / 2), Color3.fromRGB(92, 92, 95), Enum.Material.Asphalt)
			box(Vector3.new(w, 4, 0.6), frame * CFrame.new(0, 2, d - 0.3), Color3.fromRGB(60, 62, 64), Enum.Material.Metal)
			-- A row of bays along the back, with cars in most of them
			local bays = math.floor((w - 2) / 11)
			for i = 0, bays - 1 do
				local bx = -w / 2 + 1 + (i + 0.5) * (w - 2) / bays
				if i > 0 then
					local line = TownKit.detail(Vector3.new(0.3, 0.05, 15), frame * CFrame.new(bx - (w - 2) / bays / 2, 0.23, d - 9), C.White, Enum.Material.SmoothPlastic)
					line.CastShadow = false
				end
				if d > 20 and random:NextNumber() < 0.6 then
					local spot = (frame * CFrame.new(bx, 0.2, d - 10)).Position
					table.insert(parkingSpots, { math.round(spot.X * 10) / 10, 0.2, math.round(spot.Z * 10) / 10, math.round(deg) })
				end
			end
		end
	end
end

-- Walls, fences, hedges and railings in the gaps along the streets
local function buildWalls()
	local fill: any = LondonFill
	for _, w in fill.walls do
		local kind = w[1]
		local a, b = Vector3.new(w[2], 0, w[3]), Vector3.new(w[4], 0, w[5])
		local length = (b - a).Magnitude
		if length < 0.5 then
			continue
		end
		local mid = (a + b) / 2
		local frame = CFrame.lookAt(mid, mid + (b - a))
		if kind == 1 then
			box(Vector3.new(0.9, 4.5, length), frame * CFrame.new(0, 2.25, 0), WALL_BRICK, Enum.Material.Brick)
			box(Vector3.new(1.3, 0.4, length), frame * CFrame.new(0, 4.7, 0), C.Stone, Enum.Material.Concrete)
		elseif kind == 2 then
			box(Vector3.new(0.4, 6, length), frame * CFrame.new(0, 3, 0), Color3.fromRGB(70, 90, 70), Enum.Material.DiamondPlate)
		elseif kind == 3 then
			box(Vector3.new(2.2, 4.5, length), frame * CFrame.new(0, 2.25, 0), C.Hedge, Enum.Material.LeafyGrass)
		else
			local rail = box(Vector3.new(0.25, 3.5, length), frame * CFrame.new(0, PAVEMENT_TOP + 1.75, 0), C.StreetBlack, Enum.Material.Metal)
			rail.Transparency = 0.4
			box(Vector3.new(0.4, 0.3, length), frame * CFrame.new(0, PAVEMENT_TOP + 3.5, 0), C.StreetBlack, Enum.Material.Metal)
		end
	end
end

-- Trees and bushes. Each row is { x, z, size, form }: form 1 a round tree, 2 a tall slim one (woods),
-- 3 a broad spreading one (parks), 4 a bush.
local TREE_FORMS: { [number]: string? } = { [2] = "tall", [3] = "wide" }

local function buildTrees()
	local fill: any = LondonFill
	for _, t in fill.trees do
		local at = Vector3.new(t[1], 0, t[2])
		if t[4] == 4 then
			TownProps.bush(at, t[3])
		else
			TownProps.tree(at, t[3], TREE_FORMS[t[4] or 1])
		end
	end
end

-- Street furniture -----------------------------------------------------------------------------

-- Spots along the kerbs where parked cars go. ParkedCars (on each player's device) puts cars in the ones
-- near you. Each spot is { x, y, z, degrees turned }.

-- Lamp posts, a few trees, bus stops, zebra crossings and motorway lights. Kept sparse, like BVS, so the
-- streets look clean. Also works out where cars park.
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
		-- Stretches where nobody parks: bus stops and crossings
		local noParking: { { number } } = {}

		if road.side == "pavement" then
			-- One lamp post every 120 studs, swapping sides, at the kerb
			local s = s0 + 30
			local lampSide = if index % 2 == 0 then 1 else -1
			local count = 0
			while s < s1 - 20 do
				if onGround(s) and s > road.sideFrom[lampSide] + 10 and s < road.sideTo[lampSide] - 10 then
					local p, _, n = RoadKit.at(path, s)
					TownProps.lampPost(p + n * lampSide * (road.hw + 1.4), -n * lampSide)
					count += 1
					-- Trees only along the dual carriageways
					if road.kind == "dual" and count % 2 == 0 then
						local treeAt = p + n * -lampSide * (road.hw + road.sideWidth - 2.5)
						TownProps.tree(Vector3.new(treeAt.X, PAVEMENT_TOP, treeAt.Z), 0.85)
					end
				end
				s += 120
				lampSide = -lampSide
			end
			-- A bus stop on the longer main roads
			if (road.kind == "main" or road.kind == "dual" or road.kind == "high") and s1 - s0 > 700 then
				local at = s0 + (s1 - s0) * 0.5
				if onGround(at) then
					local p, _, n = RoadKit.at(path, at)
					local stopSide = if index % 2 == 0 then 1 else -1
					local kerb = Vector3.new(p.X, 0, p.Z) + n * stopSide * road.hw
					TownProps.busStop(CFrame.lookAt(kerb, kerb - n * stopSide))
					local _, along = RoadKit.at(path, at)
					TownProps.bin(kerb + n * stopSide * 2.5 - along * 11, -n * stopSide)
					table.insert(noParking, { at - 30, at + 30 })
				end
			end
			-- A telephone box on each high street: the red classic in the middle of town, modern ones further out
			if road.kind == "high" or (road.kind == "main" and index % 5 == 0) then
				local at = s0 + (s1 - s0) * 0.3
				if onGround(at) then
					local p, _, n = RoadKit.at(path, at)
					local district = districtAt(p.X, p.Z)
					local central = district == "westminster" or district == "westend" or district == "city"
					local spot = p + n * -(road.hw + 2.5)
					TownProps.phoneBox(Vector3.new(spot.X, 0, spot.Z), n, not central)
					table.insert(noParking, { at - 12, at + 12 })
				end
			end
			-- A zebra crossing halfway along the high streets and some side streets
			if road.kind == "high" or ((road.kind == "street" or road.kind == "back") and random:NextNumber() < 0.25 and s1 - s0 > 200) then
				local at = (s0 + s1) / 2 + (if road.kind == "high" then 0 else 40)
				if onGround(at) then
					local p, direction, n = RoadKit.at(path, at)
					TownProps.zebra(CFrame.lookAt(Vector3.new(p.X, 0, p.Z), Vector3.new(p.X, 0, p.Z) + direction), road.hw * 2)
					for _, kerbSide in { -1, 1 } do
						for _, along in { -4.5, 4.5 } do
							TownProps.belisha(p + n * kerbSide * (road.hw + 1.5) + direction * along)
						end
					end
					table.insert(noParking, { at - 32, at + 32 })
				end
			end
			-- Speed humps on the back streets: a low rounded hump across both lanes every hundred studs or so
			-- (not under the parked cars), like the ones all over London's side streets
			if road.kind == "back" and s1 - s0 > 180 then
				local at = s0 + 55
				while at < s1 - 55 do
					local blocked = not onGround(at)
					for _, range in noParking do
						if at > range[1] - 12 and at < range[2] + 12 then
							blocked = true
						end
					end
					if not blocked then
						local p, _, n = RoadKit.at(path, at)
						local lanes = road.hw - (road.profile.parking or 0)
						local height, along = 0.55, 9
						-- A slice off the top of a wide cylinder gives a smooth rounded hump
						local radius = (along * along / 4 + height * height) / (2 * height)
						local hump = box(Vector3.new(lanes * 2, radius * 2, radius * 2), CFrame.fromMatrix(Vector3.new(p.X, ROAD_TOP + height - radius, p.Z), n, Vector3.yAxis), C.Asphalt, Enum.Material.Asphalt)
						hump.Shape = Enum.PartType.Cylinder
						hump.CastShadow = false
						hump:SetAttribute("SpeedLimit", road.limit)
					end
					at += random:NextNumber(100, 135)
				end
			end
			-- Street trees in the wider pavements of the main roads and high streets
			if (road.kind == "main" or road.kind == "high") and road.sideWidth >= 14 then
				local at = s0 + 40
				local treeSide = if index % 2 == 0 then 1 else -1
				while at < s1 - 40 do
					local blocked = not onGround(at) or at < road.sideFrom[treeSide] + 25 or at > road.sideTo[treeSide] - 25
					for _, range in noParking do
						if at > range[1] - 8 and at < range[2] + 8 then
							blocked = true
						end
					end
					if not blocked then
						local p, _, n = RoadKit.at(path, at)
						local spot = p + n * treeSide * (road.hw + road.sideWidth - 3.2)
						TownProps.tree(Vector3.new(spot.X, PAVEMENT_TOP, spot.Z), random:NextNumber(0.55, 0.75))
					end
					at += random:NextNumber(70, 95)
					treeSide = -treeSide
				end
			end
		elseif road.kind == "motorway" or road.kind == "westway" then
			-- Tall lights down the middle
			local s = s0
			while s < s1 do
				local p, _, n = RoadKit.at(path, s)
				local height = 22
				TownKit.post(0.8, height, p + Vector3.new(0, 0.25, 0), C.LampGrey, Enum.Material.Metal)
				for _, side in { 1, -1 } do
					local arm = TownKit.detail(Vector3.new(0.4, 0.4, 7), CFrame.lookAt(p + Vector3.new(0, height, 0) + n * side * 3.5, p + Vector3.new(0, height, 0) + n * side * 7), C.LampGrey, Enum.Material.Metal)
					arm.CastShadow = false
					local head = TownKit.detail(Vector3.new(1.2, 0.4, 2.6), CFrame.lookAt(p + Vector3.new(0, height - 0.3, 0) + n * side * 7.5, p + n * side * 20 + Vector3.new(0, height - 0.3, 0)), C.LampGrey, Enum.Material.Metal)
					TownKit.tag(head, "StreetLight")
				end
				s += 160
			end
		end
		-- Speed limit signs where the faster roads start, for the traffic turning onto them
		if (road.kind == "dual" or road.kind == "arterial") and s1 - s0 > 200 then
			for _, info in { { s0 + 22, 1 }, { s1 - 22, -1 } } do
				local at, side = info[1], info[2]
				local node = if side > 0 then road.a else road.b
				if node.kind ~= "attach" and node.kind ~= "end" and onGround(at) then
					local p, direction, n = RoadKit.at(path, at)
					local spot = p + n * side * (road.hw + 2.5)
					TownProps.limitSign(Vector3.new(spot.X, 0, spot.Z), direction * -side, road.limit)
				end
			end
		end
		-- A grass verge between the road and the pavement on the big dual carriageways, with trees along it
		if road.kind == "arterial" and road.side == "pavement" then
			local grass = { colour = C.Grass, material = Enum.Material.Grass, thickness = 0.3, collide = false }
			for _, side in { 1, -1 } do
				local from, to = road.sideFrom[side] + 6, road.sideTo[side] - 6
				if to - from > 20 and onGround((from + to) / 2) then
					local points, normals = RoadKit.slice(path, from, to)
					local inner, outer = road.hw + 0.8, road.hw + 8.5
					local lift = PAVEMENT_TOP - ROAD_TOP + 0.03
					if side > 0 then
						RoadKit.strip(points, normals, inner, outer, grass, lift)
					else
						RoadKit.strip(points, normals, -outer, -inner, grass, lift)
					end
					local at = from + random:NextNumber(10, 30)
					while at < to - 10 do
						if onGround(at) then
							local p, _, n = RoadKit.at(path, at)
							local spot = p + n * side * (road.hw + 4.6)
							TownProps.tree(Vector3.new(spot.X, PAVEMENT_TOP, spot.Z), random:NextNumber(0.7, 0.95))
						end
						at += random:NextNumber(48, 70)
					end
				end
			end
		end
		-- Down the middle of the dual carriageways: trees on the big ones, a low clipped hedge on the others
		if (road.kind == "arterial" or road.kind == "dual") and s1 - s0 > 90 then
			local at = s0 + 30
			while at < s1 - 30 do
				if onGround(at) then
					local p, direction = RoadKit.at(path, at)
					if road.kind == "arterial" then
						TownProps.tree(Vector3.new(p.X, PAVEMENT_TOP, p.Z), random:NextNumber(0.6, 0.8))
						at += random:NextNumber(42, 60)
					else
						local length = math.min(26, s1 - 30 - at)
						if length > 6 then
							local mid = RoadKit.at(path, at + length / 2)
							local base = Vector3.new(mid.X, PAVEMENT_TOP + 1.6, mid.Z)
							box(Vector3.new(3, 3.2, length), CFrame.lookAt(base, base + direction), C.Hedge, Enum.Material.LeafyGrass)
						end
						at += length + random:NextNumber(10, 18)
					end
				else
					at += 20
				end
			end
		end
		if road.kind == "arterial" and s1 - s0 > 800 then
			-- A speed camera on the South Circular
			local p, direction, n = RoadKit.at(path, s0 + (s1 - s0) * 0.5)
			local at = p + n * (road.hw + 4)
			TownProps.speedCamera(TownKit.facing(Vector3.new(at.X, 0, at.Z), -direction), road.limit)
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
					-- Leave some gaps, like a real street
					if not blocked and random:NextNumber() < 0.72 then
						local p, direction, n = RoadKit.at(path, s)
						local at = p + n * side * (road.hw - parking / 2)
						-- Facing the way the traffic on that side goes
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

-- Pavements for the people walking about: a line of points down the middle of each pavement
-- (the Pedestrians client script walks people along them). Each line is { x1, z1, x2, z2, ... }.
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
				local at = p + n * side * (road.hw + road.sideWidth * 0.5)
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

-- The edge of the world: the city carrying on into the haze, and invisible walls so nobody drives off it

local SKYLINE = { Color3.fromRGB(150, 110, 92), Color3.fromRGB(160, 156, 148), Color3.fromRGB(128, 118, 112), Color3.fromRGB(176, 168, 152), Color3.fromRGB(110, 120, 130) }

local function buildEdges()
	-- Grass out past the edge, so the distant buildings stand on something
	local reach = 900
	local width, depth = MAX_X - MIN_X, MAX_Z - MIN_Z
	for _, info in {
		{ Vector3.new(width + reach * 2, 4, reach), Vector3.new((MIN_X + MAX_X) / 2, -2, MIN_Z - reach / 2) },
		{ Vector3.new(width + reach * 2, 4, reach), Vector3.new((MIN_X + MAX_X) / 2, -2, MAX_Z + reach / 2) },
		{ Vector3.new(reach, 4, depth), Vector3.new(MIN_X - reach / 2, -2, (MIN_Z + MAX_Z) / 2) },
		{ Vector3.new(reach, 4, depth), Vector3.new(MAX_X + reach / 2, -2, (MIN_Z + MAX_Z) / 2) },
	} do
		for _, tile in TownKit.tiles(info[1], info[2], C.Grass, Enum.Material.Grass) do
			tile.Parent = groundModel
		end
	end
	-- The map's outline (not a square: it curves in and out). Along it, an invisible wall so nobody drives
	-- off, and plain blocks of different heights a little way out: in the haze they read as more city.
	local outline: { Vector3 } = {}
	for _, p in layout.outline do
		table.insert(outline, Vector3.new(p[1], 0, p[2]))
	end
	-- Which way is "out": the outline goes round one way or the other, so check against the middle
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
		local d = 0
		while d < length do
			local w = random:NextNumber(40, 100)
			local deep = random:NextNumber(40, 90)
			local h = random:NextNumber(30, 140)
			local at = a + along * math.min(d + w / 2, length) + outward * (random:NextNumber(60, 320) + deep / 2)
			standIn(CFrame.lookAt(at + Vector3.new(0, h / 2, 0), at + Vector3.new(0, h / 2, 0) - outward), Vector3.new(w, h, deep), SKYLINE[random:NextInteger(1, #SKYLINE)], Enum.Material.Concrete)
			d += w + random:NextNumber(0, 30)
		end
	end
end

-- The clock tower shows London time ------------------------------------------------------------

-- British time: GMT in winter, BST (one hour ahead) in summer
local function londonTime(): (number, number)
	local utc = os.date("!*t", os.time()) :: any
	local function lastSunday(month: number): number
		local lastDay = os.date("!*t", os.time({ year = utc.year, month = month, day = 31, hour = 12 })) :: any
		return 31 - (lastDay.wday - 1)
	end
	local month, day = utc.month, utc.day
	local summer = (month > 3 and month < 10)
		or (month == 3 and (day > lastSunday(3) or (day == lastSunday(3) and utc.hour >= 1)))
		or (month == 10 and (day < lastSunday(10) or (day == lastSunday(10) and utc.hour < 1)))
	local hour = (utc.hour + (if summer then 1 else 0)) % 24
	return hour, utc.min
end

local function runClock()
	while true do
		local hour, minute = londonTime()
		for _, face in CollectionService:GetTagged("ClockFace") do
			for _, descendant in face:GetDescendants() do
				if descendant.Name == "HourHand" and descendant:IsA("Frame") then
					descendant.Rotation = (hour % 12 + minute / 60) * 30
				elseif descendant.Name == "MinuteHand" and descendant:IsA("Frame") then
					descendant.Rotation = minute * 6
				end
			end
		end
		task.wait(20)
	end
end

-- Putting it all together ----------------------------------------------------------------------

function LondonMap.build()
	local started = os.clock()
	-- Start from nothing, so running it again in Studio replaces the old map
	local old = Workspace:FindFirstChild("London")
	if old then
		old:Destroy()
	end
	local oldDepots = Workspace:FindFirstChild("Depots")
	if oldDepots then
		oldDepots:Destroy()
	end
	Workspace.Terrain:Clear()
	buffer.fill(grid, 0, 0)
	table.clear(minimap)

	mapInfo = ReplicatedStorage:FindFirstChild("MapInfo") :: Configuration? or Instance.new("Configuration")
	mapInfo.Name = "MapInfo"
	mapInfo:ClearAllChildren()
	mapInfo.Parent = ReplicatedStorage

	folder = Instance.new("Folder")
	folder.Name = "London"
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

	-- In Studio, say how long each stage took (handy if the build ever gets slow or stuck)
	local stageStart = os.clock()
	local function stage(name: string)
		if RunService:IsStudio() then
			print(string.format("[LondonMap] %s (%.1fs)", name, os.clock() - stageStart))
		end
		stageStart = os.clock()
	end
	buildRiver()
	buildGround()
	stage("river and ground")
	local result = RoadNetwork.build(layout, groundAt, function(x: number, z: number): boolean
		return cellAt(x, z) == ROAD
	end, markRoads)
	stage("roads")
	buildRiverWalls(result.roads)
	buildSites(result, depots)
	stage("river walls and sites")
	loadKit()
	table.clear(parkingSpots)
	local buildings = buildBuildings()
	stage("buildings")
	buildGardens()
	buildWalls()
	buildTrees()
	stage("gardens, walls and trees")
	buildStreetFurniture(result)
	stage("street furniture")
	collectPavements(result)
	buildEdges()
	stage("edges")

	for _, entry in result.minimap do
		table.insert(minimap, entry)
	end
	-- The river for the minimap, as wide lines
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
	local tower = mapInfo:GetAttribute("ClockTower")
	-- Across the river from the palace, with the bridge and the clock tower in shot
	local lookAt = if typeof(tower) == "Vector3" then tower + Vector3.new(-40, 60, 0) else Vector3.new(0, 60, 0)
	mapInfo:SetAttribute("MenuCamera", CFrame.lookAt(Vector3.new(-560, 80, 690), lookAt))

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

	-- Players walking about start in St James's Park, by the palace
	local spawn = Workspace:FindFirstChildOfClass("SpawnLocation")
	if spawn then
		spawn.CFrame = CFrame.new(-1400, PAVEMENT_TOP + 1.2, 80)
	end

	local parts = 0
	for _, descendant in folder:GetDescendants() do
		if descendant:IsA("BasePart") then
			parts += 1
		end
	end
	print(string.format("[LondonMap] Built London: %d roads, %d buildings (%d parts from the building kit), %d parking spaces, %d parts in %.1f seconds", #result.roads, buildings, kitParts, #parkingSpots, parts, os.clock() - started))
	return result
end

-- Removes the map (for example after building it in Studio to look round, so the place file stays small
-- and the game builds it fresh when it starts)
function LondonMap.clear()
	for _, name in { "London", "Depots" } do
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

-- Starts the clock tower once the game is running
function LondonMap.startClock()
	task.spawn(runClock)
end

return LondonMap
