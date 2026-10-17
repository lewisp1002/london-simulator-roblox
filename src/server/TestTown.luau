-- Builds a stand-in London to drive round when the game starts: about 3,000 studs across, with the Thames
-- along the south, two bridges, a clock tower, a high street, terraced streets, offices, two parks,
-- working traffic lights, zebra crossings, bus stops, speed cameras and the three team depots.
-- It's only a stand-in until the real map is built: turn it off with Config.BuildTestTown.
-- Sizes follow docs/BVS-NOTES.md: lanes about 12 studs wide, 12-stud pavements, 11-stud storeys.
--
-- It also fills in ReplicatedStorage → MapInfo, which the menus and minimap read:
--   attributes MenuCamera, Showroom_Car, Showroom_Bus, Showroom_Emergency (CFrames)
--   a StringValue "Minimap" listing every road and the river as rectangles
-- A hand-built map needs the same MapInfo and a Workspace → Depots folder (see Cars.luau).

local CollectionService = game:GetService("CollectionService")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local TownBuildings = require(script.Parent.TownBuildings)
local TownKit = require(script.Parent.TownKit)
local TownProps = require(script.Parent.TownProps)

local C = TownKit.Colours
local ROAD_TOP = TownKit.ROAD_TOP
local PAVEMENT_TOP = TownKit.PAVEMENT_TOP
local box = TownKit.box

local PAVEMENT = 12 -- width of the pavement round every block
local WIDTH = { side = 28, main = 40, dual = 72 }
local LIMIT = { side = 20, main = 30, dual = 40 } -- mph
local DUAL_RESERVATION = 12 -- grass strip down the middle of the dual carriageway

type Line = { at: number, kind: string, bridge: boolean?, highStreet: boolean? }

-- Roads running north to south, by their x position. The two "bridge" roads cross the river.
local X_LINES: { Line } = {
	{ at = -1500, kind = "main" },
	{ at = -1140, kind = "side" },
	{ at = -800, kind = "main", bridge = true },
	{ at = -480, kind = "side" },
	{ at = -180, kind = "side" },
	{ at = 120, kind = "main", bridge = true },
	{ at = 440, kind = "side" },
	{ at = 760, kind = "side" },
	{ at = 1080, kind = "main" },
	{ at = 1440, kind = "main" },
}

-- Roads running west to east, by their z position (south is +z). The last two are either side of the river.
local EMBANKMENT = 480
local SOUTH_BANK_ROAD = 900
local Z_LINES: { Line } = {
	{ at = -1500, kind = "main" },
	{ at = -1150, kind = "side" },
	{ at = -800, kind = "dual" },
	{ at = -460, kind = "side" },
	{ at = -160, kind = "main", highStreet = true },
	{ at = 160, kind = "side" },
	{ at = EMBANKMENT, kind = "main" },
	{ at = SOUTH_BANK_ROAD, kind = "main" },
}

local WEST, EAST = X_LINES[1].at, X_LINES[#X_LINES].at
local NORTH = Z_LINES[1].at
local RIVER_NORTH, RIVER_SOUTH = 540, 840 -- the river walls
local SOUTH = 1300 -- southern edge of the south bank
local MARGIN = 600 -- grass beyond the outer roads

local TestTown = {}

local folder: Folder
local mapInfo: Configuration
local random = Random.new(2026) -- same "random" town every time
-- Each entry is { centre x, centre z, size x, size z, kind }
local minimap: { { any } } = {}

local function addToMinimap(centreX: number, centreZ: number, sizeX: number, sizeZ: number, kind: string)
	local entry: { any } = { math.round(centreX), math.round(centreZ), math.round(sizeX), math.round(sizeZ), kind }
	table.insert(minimap, entry)
end

local function widthOf(line: Line): number
	return WIDTH[line.kind]
end

local function crosses(x: Line, z: Line): boolean
	if z.at == SOUTH_BANK_ROAD then
		return x.bridge == true
	end
	return true
end

-- One straight piece of road between two junctions
local function roadSegment(alongZ: boolean, line: Line, from: number, to: number)
	local length = to - from
	if length < 1 then
		return
	end
	local width = widthOf(line)
	local middle = (from + to) / 2
	local centre = if alongZ then Vector3.new(line.at, 0, middle) else Vector3.new(middle, 0, line.at)
	local frame = CFrame.lookAt(centre, centre + (if alongZ then Vector3.zAxis else Vector3.xAxis))
	local level = ROAD_TOP + 0.02

	local surface = box(Vector3.new(width, 1, length), frame * CFrame.new(0, ROAD_TOP - 0.5, 0), C.Asphalt, Enum.Material.Asphalt)
	surface:SetAttribute("SpeedLimit", LIMIT[line.kind])
	addToMinimap(centre.X, centre.Z, if alongZ then width else length, if alongZ then length else width, line.kind)

	local function paintAt(sizeX: number, sizeZ: number, x: number, z: number, colour: Color3?)
		local part = TownKit.paint(sizeX, sizeZ, Vector3.zero, colour)
		part.CFrame = frame * CFrame.new(x, level, z)
	end

	if line.kind == "dual" then
		-- Grass down the middle with trees, a dashed line in the middle of each side, solid white edges
		local reservation = box(Vector3.new(DUAL_RESERVATION, 0.5, length), frame * CFrame.new(0, ROAD_TOP + 0.25, 0), C.Grass, Enum.Material.Grass)
		reservation:SetAttribute("SpeedLimit", LIMIT.dual)
		for z = -length / 2 + 20, length / 2 - 20, 60 do
			TownProps.tree((frame * CFrame.new(0, PAVEMENT_TOP, z)).Position, 1.1)
		end
		local laneMiddle = DUAL_RESERVATION / 2 + (width - DUAL_RESERVATION) / 4
		for _, side in { -1, 1 } do
			for z = -length / 2 + 8, length / 2 - 8, 20 do
				paintAt(0.5, 10, side * laneMiddle, z)
			end
			paintAt(0.4, length, side * (width / 2 - 1.2), 0)
			paintAt(0.4, length, side * (DUAL_RESERVATION / 2 + 1), 0)
		end
	else
		local dash = if line.kind == "main" then 12 else 8
		local gap = if line.kind == "main" then 8 else 10
		local count = math.floor(length / (dash + gap))
		local first = -(count - 1) * (dash + gap) / 2
		for i = 0, count - 1 do
			paintAt(0.5, dash, 0, first + i * (dash + gap))
		end
		for _, side in { -1, 1 } do
			for _, fromKerb in { 1.1, 1.8 } do
				paintAt(0.35, length, side * (width / 2 - fromKerb), 0, C.Yellow)
			end
		end
	end

	-- A zebra crossing halfway along each piece of the high street
	if line.highStreet and length > 140 then
		TownProps.zebra(frame, width)
		for _, side in { -1, 1 } do
			for _, along in { -4.5, 4.5 } do
				TownProps.belisha((frame * CFrame.new(side * (width / 2 + 1.5), 0, along)).Position)
			end
		end
	end

	-- Bus stops on main roads, on the left-hand kerb for traffic heading along the road
	if line.kind == "main" and length > 160 then
		local travel = frame.LookVector
		local left = -travel:Cross(Vector3.yAxis)
		local kerb = frame.Position + left * (width / 2) + travel * (-length * 0.2)
		if kerb.X < WEST or kerb.X > EAST or kerb.Z < NORTH then
			-- That kerb is on the outside edge of the map with no pavement, so use the other side
			travel, left = -travel, -left
			kerb = frame.Position + left * (width / 2) + travel * (-length * 0.2)
		end
		TownProps.busStop(TownKit.facing(Vector3.new(kerb.X, 0, kerb.Z), -left))
	end
end

-- A bridge across the river: road deck, pavements, green railings and stone piers
local function bridge(line: Line)
	local width = widthOf(line)
	local x = line.at
	local span = RIVER_SOUTH - RIVER_NORTH
	local middleZ = (RIVER_NORTH + RIVER_SOUTH) / 2
	local deckWidth = width + 2 * 8
	box(Vector3.new(deckWidth, 3, span), CFrame.new(x, ROAD_TOP - 2.5, middleZ), C.Stone, Enum.Material.Limestone)
	for _, side in { -1, 1 } do
		local pavementX = x + side * (width / 2 + 4)
		box(Vector3.new(8, 1.5, span), CFrame.new(pavementX, PAVEMENT_TOP - 0.75, middleZ), C.Pavement, Enum.Material.Pavement)
		box(Vector3.new(1, 3.4, span), CFrame.new(x + side * (deckWidth / 2 - 0.5), PAVEMENT_TOP + 1.7, middleZ), Color3.fromRGB(40, 95, 65), Enum.Material.Metal)
		for z = RIVER_NORTH + 20, RIVER_SOUTH - 20, 50 do
			TownProps.lampPost(Vector3.new(x + side * (deckWidth / 2 - 2), 0, z), Vector3.new(-side, 0, 0))
		end
	end
	for _, z in { RIVER_NORTH + span / 3, RIVER_NORTH + span * 2 / 3 } do
		box(Vector3.new(deckWidth + 4, 16, 12), CFrame.new(x, -8.5, z), C.Stone, Enum.Material.Limestone)
	end
end

-- Where a road meets a junction: traffic lights, a stop line or a give-way line, depending on the roads
local function junctionApproach(centre: Vector3, travel: Vector3, approach: Line, other: Line, lit: boolean, id: string)
	local roadWidth = widthOf(approach)
	local edge = centre - travel * (widthOf(other) / 2)
	local left = -travel:Cross(Vector3.yAxis)
	local laneWidth = if approach.kind == "dual" then (roadWidth - DUAL_RESERVATION) / 2 else roadWidth / 2
	local laneCentre = edge + left * (roadWidth / 2 - laneWidth / 2)
	local laneFrame = CFrame.lookAt(laneCentre, laneCentre + travel)

	if lit then
		TownProps.stopLine(laneFrame, laneWidth)
		local corner = edge + left * (roadWidth / 2 + 2) - travel * 2
		TownProps.trafficLight(TownKit.facing(corner, -travel), id, if math.abs(travel.Z) > 0.5 then "NS" else "EW")
		TownProps.railing(edge + left * (roadWidth / 2 + 0.8) - travel * 5, -travel, 16)
	elseif approach.kind == "side" and other.kind ~= "side" then
		TownProps.giveWay(laneFrame, laneWidth)
	end
end

local function buildRoads()
	-- Junctions first
	for _, x in X_LINES do
		for _, z in Z_LINES do
			if crosses(x, z) and (z.at <= EMBANKMENT or x.bridge) then
				local wx, wz = widthOf(x), widthOf(z)
				local junction = box(Vector3.new(wx, 1, wz), CFrame.new(x.at, ROAD_TOP - 0.5, z.at), C.Asphalt, Enum.Material.Asphalt)
				junction:SetAttribute("SpeedLimit", math.max(LIMIT[x.kind], LIMIT[z.kind]))
				addToMinimap(x.at, z.at, wx, wz, if LIMIT[x.kind] > LIMIT[z.kind] then x.kind else z.kind)
			end
		end
	end

	-- North-south roads, junction to junction
	for _, x in X_LINES do
		local stops: { Line } = {}
		for _, z in Z_LINES do
			if crosses(x, z) and (z.at <= EMBANKMENT or x.bridge) then
				table.insert(stops, z)
			end
		end
		for i = 1, #stops - 1 do
			local a, b = stops[i], stops[i + 1]
			roadSegment(true, x, a.at + widthOf(a) / 2, b.at - widthOf(b) / 2)
			if a.at == EMBANKMENT and b.at == SOUTH_BANK_ROAD then
				bridge(x)
			end
		end
	end

	-- West-east roads. The south bank road only meets the bridges, so it runs past the other roads' ends.
	for _, z in Z_LINES do
		local stops: { { at: number, width: number } } = {}
		for _, x in X_LINES do
			if crosses(x, z) then
				table.insert(stops, { at = x.at, width = widthOf(x) })
			end
		end
		if z.at == SOUTH_BANK_ROAD then
			table.insert(stops, 1, { at = WEST - 20, width = 0 })
			table.insert(stops, { at = EAST + 20, width = 0 })
		end
		for i = 1, #stops - 1 do
			local a, b = stops[i], stops[i + 1]
			roadSegment(false, z, a.at + a.width / 2, b.at - b.width / 2)
		end
	end

	-- Traffic lights where two big roads meet, give-way lines where side streets join them
	for _, x in X_LINES do
		for _, z in Z_LINES do
			if crosses(x, z) and z.at <= EMBANKMENT then
				local centre = Vector3.new(x.at, 0, z.at)
				local lit = x.kind ~= "side" and z.kind ~= "side" and x.at ~= WEST and x.at ~= EAST and z.at ~= NORTH
				local id = `{x.at},{z.at}`
				if z.at > NORTH then
					junctionApproach(centre, Vector3.new(0, 0, 1), x, z, lit, id) -- coming from the north
				end
				if z.at < EMBANKMENT or x.bridge then
					junctionApproach(centre, Vector3.new(0, 0, -1), x, z, lit, id) -- from the south
				end
				if x.at > WEST then
					junctionApproach(centre, Vector3.new(1, 0, 0), z, x, lit, id) -- from the west
				end
				if x.at < EAST then
					junctionApproach(centre, Vector3.new(-1, 0, 0), z, x, lit, id) -- from the east
				end
			end
		end
	end
end

-- Street lamps (and trees on the big roads) along one kerb of a block
local function dressKerb(from: Vector3, to: Vector3, towardRoad: Vector3, trees: boolean)
	local length = (to - from).Magnitude
	local along = (to - from).Unit
	local inset = -towardRoad * 1.6
	local count = math.floor((length - 32) / 80)
	for i = 0, count do
		local at = from + along * (16 + i * 80) + inset
		TownProps.lampPost(at, towardRoad)
		if i % 3 == 1 then
			TownProps.bin(at + along * 3 - towardRoad * 0.5)
		end
		if trees and i < count then
			TownProps.tree(Vector3.new(at.X, PAVEMENT_TOP, at.Z) + along * 40 - towardRoad * 1.5, 0.9)
		end
	end
end

-- Splits a long side of a block into runs of houses of different heights and colours
local function rowsAlong(start: CFrame, length: number, depth: number, build: (CFrame, number, number) -> ())
	local position = -length / 2
	while length / 2 - position > 20 do
		local remaining = length / 2 - position
		local runLength = if remaining < 140 then remaining else random:NextInteger(64, 128)
		build(start * CFrame.new(position + runLength / 2, 0, 0), runLength, depth)
		position += runLength
	end
end

local WALLS = { C.RedBrick, C.RedBrick, C.StockBrick, C.StockBrick, C.Stucco }

-- Buildings round all four sides of a block, with gardens or a yard in the middle
local function perimeterRows(minX: number, maxX: number, minZ: number, maxZ: number, depth: number, kind: string)
	local middleX, middleZ = (minX + maxX) / 2, (minZ + maxZ) / 2
	local function build(frame: CFrame, length: number, rowDepth: number)
		local wall = WALLS[random:NextInteger(1, #WALLS)]
		if kind == "shops" then
			TownBuildings.shopRow(frame, length, rowDepth, random:NextInteger(3, 4), wall, random)
		else
			TownBuildings.terraceRow(frame, length, rowDepth, random:NextInteger(2, 3), wall, random)
		end
	end
	rowsAlong(CFrame.lookAt(Vector3.new(middleX, PAVEMENT_TOP, minZ), Vector3.new(middleX, PAVEMENT_TOP, minZ - 1)), maxX - minX, depth, build)
	rowsAlong(CFrame.lookAt(Vector3.new(middleX, PAVEMENT_TOP, maxZ), Vector3.new(middleX, PAVEMENT_TOP, maxZ + 1)), maxX - minX, depth, build)
	local sideLength = (maxZ - minZ) - 2 * depth
	if sideLength > 20 then
		rowsAlong(CFrame.lookAt(Vector3.new(minX, PAVEMENT_TOP, middleZ), Vector3.new(minX - 1, PAVEMENT_TOP, middleZ)), sideLength, depth, build)
		rowsAlong(CFrame.lookAt(Vector3.new(maxX, PAVEMENT_TOP, middleZ), Vector3.new(maxX + 1, PAVEMENT_TOP, middleZ)), sideLength, depth, build)
	end
	-- Back gardens in the middle
	local gardenX, gardenZ = maxX - minX - 2 * depth, maxZ - minZ - 2 * depth
	if gardenX > 0 and gardenZ > 0 then
		box(Vector3.new(gardenX, 0.2, gardenZ), CFrame.new(middleX, PAVEMENT_TOP + 0.1, middleZ), C.Grass, Enum.Material.Grass)
		for _ = 1, 3 do
			TownProps.tree(Vector3.new(middleX + (random:NextNumber() - 0.5) * gardenX * 0.7, PAVEMENT_TOP, middleZ + (random:NextNumber() - 0.5) * gardenZ * 0.7), 1.2)
		end
	end
end

local function offices(minX: number, maxX: number, minZ: number, maxZ: number)
	local lotX, lotZ = (maxX - minX) / 2, (maxZ - minZ) / 2
	for _, i in { 0, 1 } do
		for _, j in { 0, 1 } do
			local centre = Vector3.new(minX + lotX * (i + 0.5), 0, minZ + lotZ * (j + 0.5))
			local roll = random:NextNumber()
			local style = if roll < 0.5 then "glass" elseif roll < 0.85 then "stone" else "concrete"
			local height = random:NextInteger(9, 26) * TownKit.FLOOR
			TownBuildings.tower(centre, lotX - random:NextInteger(14, 30), lotZ - random:NextInteger(14, 30), height, style)
		end
	end
end

local function councilFlats(minX: number, maxX: number, minZ: number, maxZ: number)
	box(Vector3.new(maxX - minX, 0.2, maxZ - minZ), CFrame.new((minX + maxX) / 2, PAVEMENT_TOP + 0.1, (minZ + maxZ) / 2), C.Grass, Enum.Material.Grass)
	local lotX = (maxX - minX) / 2
	for _, i in { 0, 1 } do
		local centre = Vector3.new(minX + lotX * (i + 0.5), 0, (minZ + maxZ) / 2 + (if i == 0 then -30 else 30))
		TownBuildings.tower(centre, 40, 90, random:NextInteger(8, 14) * TownKit.FLOOR, "concrete")
	end
	for _ = 1, 6 do
		TownProps.tree(Vector3.new(minX + random:NextNumber() * (maxX - minX), PAVEMENT_TOP, minZ + random:NextNumber() * (maxZ - minZ)), 1.2)
	end
end

local function makeDepot(name: string, depots: Folder): Model
	local depot = Instance.new("Model")
	depot.Name = name
	depot.Parent = depots
	return depot
end

local function buildBlocks(depots: Folder)
	local northLines = {}
	for _, z in Z_LINES do
		if z.at <= EMBANKMENT then
			table.insert(northLines, z)
		end
	end

	for i = 1, #X_LINES - 1 do
		for j = 1, #northLines - 1 do
			local west, east = X_LINES[i], X_LINES[i + 1]
			local north, south = northLines[j], northLines[j + 1]
			local minX, maxX = west.at + widthOf(west) / 2, east.at - widthOf(east) / 2
			local minZ, maxZ = north.at + widthOf(north) / 2, south.at - widthOf(south) / 2
			local innerMinX, innerMaxX = minX + PAVEMENT, maxX - PAVEMENT
			local innerMinZ, innerMaxZ = minZ + PAVEMENT, maxZ - PAVEMENT
			local middle = Vector3.new((minX + maxX) / 2, 0, (minZ + maxZ) / 2)

			local use = "terraces"
			if west.at == -180 and north.at == -160 then
				use = "plaza"
			elseif west.at == -480 and north.at == -160 then
				use = "petrol"
			elseif (west.at == -800 or west.at == -480) and north.at == -460 then
				use = "park"
			elseif west.at == 120 and north.at == 160 then
				use = "palace"
			elseif west.at == -180 and north.at == 160 then
				use = "police"
			elseif west.at == 760 and north.at == -160 then
				use = "bus"
			elseif west.at >= 440 and (north.at == -1150 or north.at == -800) then
				use = "offices"
			elseif north.at == -460 or north.at == -160 then
				use = "shops"
			elseif random:NextNumber() < 0.15 then
				use = "flats"
			end

			local isDepot = use == "petrol" or use == "police" or use == "bus"
			if isDepot then
				-- Depot yards are at road level so you can drive straight out
				local yard = box(Vector3.new(maxX - minX, 1, maxZ - minZ), CFrame.new(middle.X, ROAD_TOP - 0.5, middle.Z), C.Asphalt, Enum.Material.Asphalt)
				yard:SetAttribute("SpeedLimit", 10)
				addToMinimap(middle.X, middle.Z, maxX - minX, maxZ - minZ, "yard")
			else
				box(Vector3.new(maxX - minX, 1, maxZ - minZ), CFrame.new(middle.X, PAVEMENT_TOP - 0.5, middle.Z), C.Pavement, Enum.Material.Pavement)
				local bigRoads = { north = north.kind ~= "side", south = south.kind ~= "side", west = west.kind ~= "side", east = east.kind ~= "side" }
				dressKerb(Vector3.new(minX, 0, minZ), Vector3.new(maxX, 0, minZ), Vector3.new(0, 0, -1), bigRoads.north)
				dressKerb(Vector3.new(maxX, 0, maxZ), Vector3.new(minX, 0, maxZ), Vector3.new(0, 0, 1), bigRoads.south)
				dressKerb(Vector3.new(minX, 0, maxZ), Vector3.new(minX, 0, minZ), Vector3.new(-1, 0, 0), bigRoads.west)
				dressKerb(Vector3.new(maxX, 0, minZ), Vector3.new(maxX, 0, maxZ), Vector3.new(1, 0, 0), bigRoads.east)
			end

			if use == "terraces" then
				perimeterRows(innerMinX, innerMaxX, innerMinZ, innerMaxZ, 26, "terraces")
				if random:NextNumber() < 0.3 then
					TownProps.postBox(Vector3.new(minX + 4, 0, minZ + 20), Vector3.new(-1, 0, 0))
				end
			elseif use == "shops" then
				perimeterRows(innerMinX, innerMaxX, innerMinZ, innerMaxZ, 30, "shops")
				TownProps.phoneBox(Vector3.new(minX + 5, 0, minZ + 34), Vector3.new(-1, 0, 0))
				TownProps.postBox(Vector3.new(maxX - 4, 0, maxZ - 34), Vector3.new(1, 0, 0))
			elseif use == "flats" then
				councilFlats(innerMinX, innerMaxX, innerMinZ, innerMaxZ)
			elseif use == "offices" then
				offices(innerMinX, innerMaxX, innerMinZ, innerMaxZ)
			elseif use == "park" then
				TownBuildings.park(innerMinX, innerMaxX, innerMinZ, innerMaxZ, random)
				addToMinimap(middle.X, middle.Z, innerMaxX - innerMinX, innerMaxZ - innerMinZ, "park")
			elseif use == "plaza" then
				TownBuildings.plaza(innerMinX, innerMaxX, innerMinZ, innerMaxZ)
			elseif use == "palace" then
				local tower = Vector3.new(innerMinX + 15, PAVEMENT_TOP, innerMaxZ - 15)
				TownBuildings.clockTower(tower)
				local palaceStart = innerMinX + 40
				local palaceLength = innerMaxX - palaceStart
				TownBuildings.palace(CFrame.lookAt(Vector3.new(palaceStart + palaceLength / 2, PAVEMENT_TOP, innerMaxZ), Vector3.new(palaceStart + palaceLength / 2, PAVEMENT_TOP, innerMaxZ + 1)), palaceLength, 70)
				box(Vector3.new(innerMaxX - innerMinX, 0.2, innerMaxZ - innerMinZ - 110), CFrame.new(middle.X, PAVEMENT_TOP + 0.1, innerMinZ + (innerMaxZ - innerMinZ - 110) / 2), C.Grass, Enum.Material.Grass)
				for _ = 1, 8 do
					TownProps.tree(Vector3.new(innerMinX + 50 + random:NextNumber() * (innerMaxX - innerMinX - 60), PAVEMENT_TOP, innerMinZ + 10 + random:NextNumber() * 150), 1.3)
				end
				mapInfo:SetAttribute("ClockTower", tower)
			elseif use == "petrol" then
				TownBuildings.petrolStation(minX, maxX, minZ, maxZ, makeDepot("Car", depots))
			elseif use == "police" then
				TownBuildings.policeStation(minX, maxX, minZ, maxZ, makeDepot("Emergency", depots))
			elseif use == "bus" then
				TownBuildings.busGarage(minX, maxX, minZ, maxZ, makeDepot("Bus", depots))
			end
		end
	end
end

-- Grass everywhere, a channel for the river, the river walls and the water itself
local function buildGroundAndRiver()
	local width = EAST - WEST + 2 * MARGIN
	local middleX = (WEST + EAST) / 2
	local northDepth = RIVER_NORTH - (NORTH - MARGIN)
	TownKit.tiles(Vector3.new(width, 4, northDepth), Vector3.new(middleX, -2, RIVER_NORTH - northDepth / 2), C.Grass, Enum.Material.Grass)
	local southDepth = (SOUTH + MARGIN) - RIVER_SOUTH
	TownKit.tiles(Vector3.new(width, 4, southDepth), Vector3.new(middleX, -2, RIVER_SOUTH + southDepth / 2), C.Grass, Enum.Material.Grass)

	local riverWidth = RIVER_SOUTH - RIVER_NORTH
	local riverMiddle = (RIVER_NORTH + RIVER_SOUTH) / 2
	TownKit.tiles(Vector3.new(width, 4, riverWidth), Vector3.new(middleX, -18, riverMiddle), Color3.fromRGB(70, 62, 50), Enum.Material.Mud)
	Workspace.Terrain:FillBlock(CFrame.new(middleX, -9.5, riverMiddle), Vector3.new(width, 13, riverWidth - 6), Enum.Material.Water)
	addToMinimap(middleX, riverMiddle, width, riverWidth, "water")

	-- Riverside walks on both banks, cut where the bridges come through
	local bridgeGaps = {}
	local deckGaps = {}
	for _, x in X_LINES do
		if x.bridge then
			table.insert(bridgeGaps, { x.at - widthOf(x) / 2, x.at + widthOf(x) / 2 })
			table.insert(deckGaps, { x.at - widthOf(x) / 2 - 8, x.at + widthOf(x) / 2 + 8 })
		end
	end

	-- River walls, standing a little above the path as a parapet, with gaps where the bridges start
	for _, z in { RIVER_NORTH + 1.5, RIVER_SOUTH - 1.5 } do
		local from = WEST - MARGIN
		for i = 1, #deckGaps + 1 do
			local to = if deckGaps[i] then deckGaps[i][1] else EAST + MARGIN
			box(Vector3.new(to - from, 20, 3), CFrame.new((from + to) / 2, -6, z), C.Stone, Enum.Material.Limestone)
			from = if deckGaps[i] then deckGaps[i][2] else to
		end
	end
	local embankmentEdge = EMBANKMENT + WIDTH.main / 2
	local southRoadEdge = SOUTH_BANK_ROAD - WIDTH.main / 2
	for _, walk in { { embankmentEdge, RIVER_NORTH }, { RIVER_SOUTH, southRoadEdge } } do
		local from = WEST - MARGIN
		local pieces = {}
		for _, gap in bridgeGaps do
			table.insert(pieces, { from, gap[1] })
			from = gap[2]
		end
		table.insert(pieces, { from, EAST + MARGIN })
		local z0, z1 = walk[1], walk[2]
		for _, piece in pieces do
			local x0, x1 = piece[1], piece[2]
			box(Vector3.new(x1 - x0, 1, z1 - z0), CFrame.new((x0 + x1) / 2, PAVEMENT_TOP - 0.5, (z0 + z1) / 2), C.Pavement, Enum.Material.Pavement)
		end
		local riverSide = if z1 == RIVER_NORTH then 1 else -1
		local treeZ = (if riverSide == 1 then z1 else z0) - riverSide * 6
		for x = WEST, EAST, 60 do
			local clear = true
			for _, gap in bridgeGaps do
				if x > gap[1] - 20 and x < gap[2] + 20 then
					clear = false
				end
			end
			if riverSide == -1 and math.abs(x - 300) < 100 then
				clear = false -- keep clear of the big wheel
			end
			if clear then
				TownProps.tree(Vector3.new(x, PAVEMENT_TOP, treeZ), 1.1)
				TownProps.lampPost(Vector3.new(x + 30, 0, (z0 + z1) / 2 + riverSide * 4), Vector3.new(0, 0, -riverSide))
			end
		end
	end
end

-- The south bank: an arts centre, the big wheel, some offices and houses
local function buildSouthBank()
	local landTop = SOUTH_BANK_ROAD + WIDTH.main / 2
	local landDepth = 200
	TownKit.tiles(Vector3.new(EAST - WEST + 40, 1, landDepth), Vector3.new((WEST + EAST) / 2, PAVEMENT_TOP - 0.5, landTop + landDepth / 2), C.Pavement, Enum.Material.Pavement)
	dressKerb(Vector3.new(WEST, 0, landTop), Vector3.new(EAST, 0, landTop), Vector3.new(0, 0, -1), true)
	local buildFrom = landTop + PAVEMENT

	TownBuildings.bigWheel(Vector3.new(300, 150, (RIVER_SOUTH + SOUTH_BANK_ROAD - WIDTH.main / 2) / 2), 138)
	-- Arts centre: low concrete blocks
	for _, info in { { -330, 120, 60, 26 }, { -200, 90, 80, 40 }, { -60, 70, 50, 20 } } do
		box(Vector3.new(info[2], info[4], info[3]), CFrame.new(info[1], PAVEMENT_TOP + info[4] / 2, buildFrom + 20 + info[3] / 2), C.Concrete, Enum.Material.Concrete)
	end
	for x = 600, 1350, 150 do
		TownBuildings.tower(Vector3.new(x, 0, buildFrom + 60), 70, 70, random:NextInteger(8, 20) * TownKit.FLOOR, if random:NextNumber() < 0.6 then "glass" else "stone")
	end
	local terraceFront = CFrame.lookAt(Vector3.new(-1000, PAVEMENT_TOP, buildFrom), Vector3.new(-1000, PAVEMENT_TOP, buildFrom - 1))
	rowsAlong(terraceFront, 900, 26, function(frame, length, depth)
		TownBuildings.terraceRow(frame, length, depth, random:NextInteger(2, 3), WALLS[random:NextInteger(1, #WALLS)], random)
	end)
end

-- Woods round the edge, and invisible walls so nobody drives off the end of the world
local function buildEdges()
	local function pinesAlong(from: Vector3, to: Vector3)
		local length = (to - from).Magnitude
		local along = (to - from).Unit
		for d = 0, length, 42 do
			local jitter = Vector3.new(random:NextNumber() - 0.5, 0, random:NextNumber() - 0.5) * 16
			TownProps.pine(from + along * d + jitter, 1.6 + random:NextNumber() * 0.8)
		end
	end
	local out = 70
	pinesAlong(Vector3.new(WEST - out, 0, NORTH - out), Vector3.new(EAST + out, 0, NORTH - out))
	pinesAlong(Vector3.new(WEST - out, 0, NORTH - out), Vector3.new(WEST - out, 0, RIVER_NORTH - 30))
	pinesAlong(Vector3.new(EAST + out, 0, NORTH - out), Vector3.new(EAST + out, 0, RIVER_NORTH - 30))
	pinesAlong(Vector3.new(WEST - out, 0, SOUTH + 20), Vector3.new(EAST + out, 0, SOUTH + 20))

	local wallDistance = MARGIN - 100
	local width = EAST - WEST + 2 * wallDistance
	local depth = SOUTH - NORTH + 2 * wallDistance
	local middle = Vector3.new((WEST + EAST) / 2, 50, (NORTH + SOUTH) / 2)
	for _, info in {
		{ Vector3.new(width, 100, 4), Vector3.new(0, 0, -depth / 2) },
		{ Vector3.new(width, 100, 4), Vector3.new(0, 0, depth / 2) },
		{ Vector3.new(4, 100, depth), Vector3.new(-width / 2, 0, 0) },
		{ Vector3.new(4, 100, depth), Vector3.new(width / 2, 0, 0) },
	} do
		for _, wall in TownKit.tiles(info[1], middle + info[2], C.Grass) do
			wall.Transparency = 1
		end
	end
end

local function speedCameras()
	TownProps.speedCamera(TownKit.facing(Vector3.new(-330, 0, -800 - WIDTH.dual / 2 - 2), Vector3.new(-1, 0, 0)), LIMIT.dual)
	TownProps.speedCamera(TownKit.facing(Vector3.new(600, 0, -800 + WIDTH.dual / 2 + 2), Vector3.new(1, 0, 0)), LIMIT.dual)
	TownProps.speedCamera(TownKit.facing(Vector3.new(1080 + WIDTH.main / 2 + 2, 0, -630), Vector3.new(0, 0, -1)), LIMIT.main)
	TownProps.speedCamera(TownKit.facing(Vector3.new(-640, 0, EMBANKMENT + WIDTH.main / 2 + 2), Vector3.new(1, 0, 0)), LIMIT.main)
	-- Signs where the dual carriageway's 40 starts
	TownProps.limitSign(Vector3.new(WEST + 40, 0, -800 - WIDTH.dual / 2 - 3), Vector3.new(-1, 0, 0), LIMIT.dual)
	TownProps.limitSign(Vector3.new(EAST - 40, 0, -800 + WIDTH.dual / 2 + 3), Vector3.new(1, 0, 0), LIMIT.dual)
end

-- British time, so the clock tower is right: GMT in winter, BST (one hour ahead) in summer
local function londonTime(): (number, number)
	local utc = os.date("!*t", os.time()) :: any
	-- March and October both have 31 days, so the last Sunday is 31 minus how far the 31st is past a Sunday
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

function TestTown.build()
	mapInfo = ReplicatedStorage:FindFirstChild("MapInfo") :: Configuration? or Instance.new("Configuration")
	mapInfo.Name = "MapInfo"
	mapInfo.Parent = ReplicatedStorage

	folder = Instance.new("Folder")
	folder.Name = "TestTown"
	TownKit.setParent(folder)

	local depots = Workspace:FindFirstChild("Depots") :: Folder? or Instance.new("Folder")
	local depotsFolder = depots :: Folder
	depotsFolder.Name = "Depots"

	-- The place's own baseplate would fill in the river, so drop it well out of the way while the town is up
	local baseplate = Workspace:FindFirstChild("Baseplate")
	if baseplate and baseplate:IsA("BasePart") then
		baseplate.Position = Vector3.new(baseplate.Position.X, -80, baseplate.Position.Z)
	end

	buildGroundAndRiver()
	buildRoads()
	buildBlocks(depotsFolder)
	buildSouthBank()
	buildEdges()
	speedCameras()

	folder.Parent = Workspace
	depotsFolder.Parent = Workspace

	-- Tell the menus where to point the camera
	for _, depot in depotsFolder:GetChildren() do
		local spot = depot:GetAttribute("ShowroomSpot")
		if typeof(spot) == "CFrame" then
			mapInfo:SetAttribute("Showroom_" .. depot.Name, spot)
		end
	end
	local tower = mapInfo:GetAttribute("ClockTower")
	local lookAt = if typeof(tower) == "Vector3" then tower + Vector3.new(0, 110, 0) else Vector3.new(0, 60, 0)
	mapInfo:SetAttribute("MenuCamera", CFrame.lookAt(Vector3.new(-330, 55, 1010), lookAt))

	local minimapData = Instance.new("StringValue")
	minimapData.Name = "Minimap"
	minimapData.Value = HttpService:JSONEncode(minimap)
	minimapData.Parent = mapInfo

	local parts = 0
	for _, descendant in folder:GetDescendants() do
		if descendant:IsA("BasePart") then
			parts += 1
		end
	end
	print(`[TestTown] Built London: {parts} parts`)

	task.spawn(runClock)
end

return TestTown
