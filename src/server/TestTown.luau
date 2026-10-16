-- Builds a small grid of London-style streets to test driving on, when the game starts.
-- It's only a stand-in until the real map is built in Studio: turn it off with Config.BuildTestTown.

local Workspace = game:GetService("Workspace")

local ROAD_LINES = { -300, -100, 100, 300 } -- where roads run, both north-south and east-west
local ROAD_WIDTH = 32
local ROAD_TOP = 0.1
local KERB_HEIGHT = 0.5
local PAVEMENT_TOP = ROAD_TOP + KERB_HEIGHT
local RING_ROAD_LIMIT = 30 -- mph, the outer roads
local SIDE_STREET_LIMIT = 20 -- mph, like most of central London
local DASH_LENGTH = 8
local DASH_GAP = 8

local ASPHALT = Color3.fromRGB(45, 45, 48)
local WHITE = Color3.fromRGB(235, 235, 235)
local YELLOW = Color3.fromRGB(240, 190, 20)
local PAVEMENT = Color3.fromRGB(165, 162, 155)
local GRASS = Color3.fromRGB(80, 130, 60)
local POST_OFFICE_RED = Color3.fromRGB(200, 16, 30)

local BUILDING_STYLES = {
	{ material = Enum.Material.Brick, color = Color3.fromRGB(140, 72, 52) }, -- red London brick
	{ material = Enum.Material.Brick, color = Color3.fromRGB(175, 145, 105) }, -- yellow stock brick
	{ material = Enum.Material.Limestone, color = Color3.fromRGB(225, 218, 200) }, -- Portland stone
	{ material = Enum.Material.Glass, color = Color3.fromRGB(110, 140, 160) }, -- office block
	{ material = Enum.Material.Concrete, color = Color3.fromRGB(150, 150, 150) },
}

local TestTown = {}

local folder: Folder

local function block(size: Vector3, position: Vector3, color: Color3, material: Enum.Material): Part
	local part = Instance.new("Part")
	part.Anchored = true
	part.Size = size
	part.Position = position
	part.Color = color
	part.Material = material
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = folder
	return part
end

-- Road paint: flat, can't be bumped into, and ignored by raycasts like the speed limit check
local function paint(size: Vector3, position: Vector3, color: Color3)
	local part = block(size, position, color, Enum.Material.SmoothPlastic)
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
end

local function speedLimitFor(line: number): number
	if line == ROAD_LINES[1] or line == ROAD_LINES[#ROAD_LINES] then
		return RING_ROAD_LIMIT
	end
	return SIDE_STREET_LIMIT
end

-- A straight bit of road between two junctions, with a dashed centre line and double yellows
local function road(center: Vector3, length: number, eastWest: boolean, speedLimit: number)
	-- Turns "along the road" and "across the road" into world directions
	local function at(along: number, across: number, y: number): Vector3
		return center + (if eastWest then Vector3.new(along, y, across) else Vector3.new(across, y, along))
	end
	local function sized(along: number, across: number, height: number): Vector3
		return if eastWest then Vector3.new(along, height, across) else Vector3.new(across, height, along)
	end

	local surface = block(sized(length, ROAD_WIDTH, 1), at(0, 0, ROAD_TOP - 0.5), ASPHALT, Enum.Material.Asphalt)
	surface:SetAttribute("SpeedLimit", speedLimit)

	local paintY = ROAD_TOP + 0.025
	local dashCount = math.floor(length / (DASH_LENGTH + DASH_GAP))
	local firstDash = -(dashCount - 1) * (DASH_LENGTH + DASH_GAP) / 2
	for i = 0, dashCount - 1 do
		paint(sized(DASH_LENGTH, 0.5, 0.05), at(firstDash + i * (DASH_LENGTH + DASH_GAP), 0, paintY), WHITE)
	end

	for _, side in { -1, 1 } do
		for _, fromKerb in { 1.2, 2 } do
			paint(sized(length, 0.4, 0.05), at(0, side * (ROAD_WIDTH / 2 - fromKerb), paintY), YELLOW)
		end
	end
end

local function phoneBox(position: Vector3)
	block(Vector3.new(3, 7, 3), position + Vector3.new(0, 3.5, 0), POST_OFFICE_RED, Enum.Material.SmoothPlastic)
	block(Vector3.new(3.4, 0.6, 3.4), position + Vector3.new(0, 7.3, 0), POST_OFFICE_RED, Enum.Material.SmoothPlastic)
end

-- The square between four roads: a pavement with buildings on it, or the park in the middle
local function cityBlock(minX: number, maxX: number, minZ: number, maxZ: number, isPark: boolean, random: Random)
	local width, depth = maxX - minX, maxZ - minZ
	local middle = Vector3.new((minX + maxX) / 2, 0, (minZ + maxZ) / 2)
	block(Vector3.new(width, 1, depth), middle + Vector3.new(0, PAVEMENT_TOP - 0.5, 0), PAVEMENT, Enum.Material.Pavement)

	if isPark then
		block(Vector3.new(width - 16, 0.2, depth - 16), middle + Vector3.new(0, PAVEMENT_TOP + 0.1, 0), GRASS, Enum.Material.Grass)
		phoneBox(Vector3.new(minX + 5, PAVEMENT_TOP, minZ + 5))
		return
	end

	-- Four buildings per block, set back from the kerb
	local lot = (width - 12 - 8) / 2
	for _, dx in { -1, 1 } do
		for _, dz in { -1, 1 } do
			local style = BUILDING_STYLES[random:NextInteger(1, #BUILDING_STYLES)]
			local height = random:NextInteger(28, 110)
			local size = Vector3.new(random:NextInteger(math.floor(lot) - 16, math.floor(lot)), height, random:NextInteger(math.floor(lot) - 16, math.floor(lot)))
			local center = middle + Vector3.new(dx * (lot + 8) / 2, PAVEMENT_TOP + height / 2, dz * (lot + 8) / 2)
			block(size, center, style.color, style.material)
		end
	end
end

function TestTown.build()
	folder = Instance.new("Folder")
	folder.Name = "TestTown"

	local half = ROAD_WIDTH / 2
	for _, x in ROAD_LINES do
		for _, z in ROAD_LINES do
			local junction = block(Vector3.new(ROAD_WIDTH, 1, ROAD_WIDTH), Vector3.new(x, ROAD_TOP - 0.5, z), ASPHALT, Enum.Material.Asphalt)
			junction:SetAttribute("SpeedLimit", math.max(speedLimitFor(x), speedLimitFor(z)))
		end
	end

	for i = 1, #ROAD_LINES - 1 do
		local from, to = ROAD_LINES[i], ROAD_LINES[i + 1]
		local length = to - from - ROAD_WIDTH
		local mid = (from + to) / 2
		for _, line in ROAD_LINES do
			road(Vector3.new(mid, 0, line), length, true, speedLimitFor(line))
			road(Vector3.new(line, 0, mid), length, false, speedLimitFor(line))
		end
	end

	-- Same "random" buildings every time, so the town doesn't change between visits
	local random = Random.new(2026)
	for i = 1, #ROAD_LINES - 1 do
		for j = 1, #ROAD_LINES - 1 do
			local isMiddle = i == 2 and j == 2
			cityBlock(ROAD_LINES[i] + half, ROAD_LINES[i + 1] - half, ROAD_LINES[j] + half, ROAD_LINES[j + 1] - half, isMiddle, random)
		end
	end

	folder.Parent = Workspace
end

return TestTown
