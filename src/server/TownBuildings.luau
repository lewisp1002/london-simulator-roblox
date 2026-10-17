-- Buildings for the test town: terraced houses, high street shops, office towers, council flats,
-- a park, a square with a column, a riverside palace with a clock tower, the team depots and a big wheel.
-- Each building is a few big parts with window strips and pillars on top, so the whole town stays fast.
-- `frame` arguments sit in the middle of a building's front wall at pavement level, facing the street.

local TownKit = require(script.Parent.TownKit)
local TownProps = require(script.Parent.TownProps)

local C = TownKit.Colours
local FLOOR = TownKit.FLOOR
local PAVEMENT_TOP = TownKit.PAVEMENT_TOP
local ROAD_TOP = TownKit.ROAD_TOP
local box, detail = TownKit.box, TownKit.detail

local DOOR_COLOURS = {
	Color3.fromRGB(20, 22, 26),
	Color3.fromRGB(25, 40, 80),
	Color3.fromRGB(140, 20, 25),
	Color3.fromRGB(20, 70, 45),
	Color3.fromRGB(230, 190, 40),
	Color3.fromRGB(240, 240, 238),
}

local FASCIA_COLOURS = {
	Color3.fromRGB(25, 40, 80),
	Color3.fromRGB(20, 70, 45),
	Color3.fromRGB(150, 25, 30),
	Color3.fromRGB(30, 30, 32),
	Color3.fromRGB(110, 60, 120),
	Color3.fromRGB(200, 120, 30),
	Color3.fromRGB(40, 110, 140),
	Color3.fromRGB(230, 225, 215),
}

-- Made-up shop names: no real brands
local SHOP_NAMES = {
	"Corner Café", "Thames Books", "Fish & Chips", "Mayfair Barbers", "Bakery", "Launderette",
	"Newsagent", "Florist", "Kebab House", "Phone Repairs", "Estate Agents", "Chemist",
	"Bistro", "Hardware", "Off Licence", "Charity Shop", "Tailors", "Pie & Mash",
	"Noodle Bar", "Opticians", "Dry Cleaners", "Pizzeria", "Butchers", "Greengrocer",
}

local GLASS_WINDOW = Color3.fromRGB(45, 58, 68)

local TownBuildings = {}

local function window(size: Vector3, cframe: CFrame): BasePart
	local pane = detail(size, cframe, GLASS_WINDOW, Enum.Material.Glass)
	pane.Reflectance = 0.2
	pane.CanCollide = true
	return pane
end

-- A row of terraced houses with pitched slate roofs, chimneys and coloured front doors
function TownBuildings.terraceRow(frame: CFrame, length: number, depth: number, floors: number, wall: Color3, random: Random)
	local houses = math.max(1, math.floor(length / 16))
	local houseWidth = length / houses
	local height = floors * FLOOR + 1
	local material = if wall == C.Stucco then Enum.Material.Plaster else Enum.Material.Brick

	box(Vector3.new(length, height, depth), frame * CFrame.new(0, height / 2, depth / 2), wall, material)
	for floor = 0, floors - 1 do
		window(Vector3.new(length - 0.6, 4.8, 0.25), frame * CFrame.new(0, floor * FLOOR + 5.5, -0.1))
	end
	for i = 0, houses do
		local x = -length / 2 + i * houseWidth
		box(Vector3.new(1.8, height - 0.2, 0.5), frame * CFrame.new(x, height / 2, -0.2), wall, material)
		if i < houses then
			box(Vector3.new(1.2, height - 0.2, 0.5), frame * CFrame.new(x + houseWidth / 2, height / 2, -0.2), wall, material)
			local door = box(Vector3.new(2.8, 7, 0.4), frame * CFrame.new(x + houseWidth * 0.25, 3.5, -0.3), DOOR_COLOURS[random:NextInteger(1, #DOOR_COLOURS)])
			door.CanCollide = true
			detail(Vector3.new(3.6, 0.5, 1.4), frame * CFrame.new(x + houseWidth * 0.25, 0.25, -0.9), C.Stone)
		end
		if i % 2 == 0 and i > 0 and i < houses then
			box(Vector3.new(2.2, 5, 3.5), frame * CFrame.new(x, height + 6.5, depth / 2), wall:Lerp(Color3.new(0, 0, 0), 0.15), Enum.Material.Brick)
		end
	end

	local roofHeight = 7
	box(Vector3.new(length, roofHeight, depth / 2), frame * CFrame.new(0, height + roofHeight / 2, depth / 4), C.Slate, Enum.Material.Slate, "WedgePart")
	box(Vector3.new(length, roofHeight, depth / 2), frame * CFrame.new(0, height + roofHeight / 2, depth * 3 / 4) * CFrame.Angles(0, math.pi, 0), C.Slate, Enum.Material.Slate, "WedgePart")
end

-- Shops on the ground floor with painted signs, flats above
function TownBuildings.shopRow(frame: CFrame, length: number, depth: number, floors: number, wall: Color3, random: Random)
	local units = math.max(1, math.floor(length / 20))
	local unitWidth = length / units
	local height = floors * FLOOR + 1
	local material = if wall == C.Stucco then Enum.Material.Plaster else Enum.Material.Brick

	box(Vector3.new(length, height, depth), frame * CFrame.new(0, height / 2, depth / 2), wall, material)
	local shopfront = window(Vector3.new(length - 0.6, 7.2, 0.25), frame * CFrame.new(0, 4.4, -0.1))
	shopfront.Transparency = 0.15
	for floor = 1, floors - 1 do
		window(Vector3.new(length - 0.6, 4.8, 0.25), frame * CFrame.new(0, floor * FLOOR + 5.5, -0.1))
	end
	for i = 0, units do
		local x = -length / 2 + i * unitWidth
		box(Vector3.new(1.4, height - 0.2, 0.5), frame * CFrame.new(x, height / 2, -0.2), wall, material)
		if i < units then
			for _, fraction in { 1 / 3, 2 / 3 } do
				box(Vector3.new(1.2, height - FLOOR, 0.5), frame * CFrame.new(x + unitWidth * fraction, FLOOR + (height - FLOOR) / 2, -0.2), wall, material)
			end
			local fasciaColour = FASCIA_COLOURS[random:NextInteger(1, #FASCIA_COLOURS)]
			local fascia = detail(Vector3.new(unitWidth - 1.6, 2.4, 0.6), frame * CFrame.new(x + unitWidth / 2, 9.4, -0.4), fasciaColour)
			local textColour = if fasciaColour == FASCIA_COLOURS[8] then Color3.fromRGB(30, 30, 30) else Color3.fromRGB(250, 245, 230)
			TownKit.text(fascia, Enum.NormalId.Front, SHOP_NAMES[random:NextInteger(1, #SHOP_NAMES)], textColour, nil, Enum.FontWeight.Medium)
		end
	end
	box(Vector3.new(length + 0.4, 1, 1.2), frame * CFrame.new(0, height - 0.5, -0.3), C.Stone, Enum.Material.Limestone)
end

-- A plain building with rows of windows: offices, the police station
function TownBuildings.plainRow(frame: CFrame, length: number, depth: number, floors: number, wall: Color3, material: Enum.Material?)
	local height = floors * FLOOR + 1
	local wallMaterial = material or Enum.Material.Brick
	box(Vector3.new(length, height, depth), frame * CFrame.new(0, height / 2, depth / 2), wall, wallMaterial)
	for floor = 0, floors - 1 do
		window(Vector3.new(length - 0.6, 5, 0.25), frame * CFrame.new(0, floor * FLOOR + 5.5, -0.1))
	end
	local count = math.max(1, math.floor(length / 7))
	for i = 0, count do
		box(Vector3.new(1.6, height - 0.2, 0.5), frame * CFrame.new(-length / 2 + i * length / count, height / 2, -0.2), wall, wallMaterial)
	end
	box(Vector3.new(length + 0.4, 1, 1.2), frame * CFrame.new(0, height - 0.5, -0.3), C.Stone, Enum.Material.Limestone)
end

-- An office block or tower of flats. `style` is "glass", "stone" or "concrete".
function TownBuildings.tower(centre: Vector3, sizeX: number, sizeZ: number, height: number, style: string)
	local base = Vector3.new(centre.X, PAVEMENT_TOP, centre.Z)
	local middle = CFrame.new(base + Vector3.new(0, height / 2, 0))
	local floors = math.floor(height / FLOOR)

	if style == "glass" then
		local body = box(Vector3.new(sizeX, height, sizeZ), middle, C.Glass, Enum.Material.Glass)
		body.Reflectance = 0.3
		for floor = 1, floors - 1 do
			detail(Vector3.new(sizeX + 0.5, 0.8, sizeZ + 0.5), CFrame.new(base + Vector3.new(0, floor * FLOOR, 0)), Color3.fromRGB(200, 202, 206), Enum.Material.Metal)
		end
		local mullions = math.floor(sizeX / 10)
		for i = 1, mullions - 1 do
			local x = -sizeX / 2 + i * sizeX / mullions
			for _, z in { -sizeZ / 2 - 0.2, sizeZ / 2 + 0.2 } do
				detail(Vector3.new(0.5, height, 0.4), CFrame.new(base + Vector3.new(x, height / 2, z)), Color3.fromRGB(175, 178, 184), Enum.Material.Metal)
			end
		end
	else
		local wall = if style == "stone" then C.Portland else C.Concrete
		local material = if style == "stone" then Enum.Material.Limestone else Enum.Material.Concrete
		box(Vector3.new(sizeX, height, sizeZ), middle, wall, material)
		for floor = 0, floors - 1 do
			window(Vector3.new(sizeX + 0.3, 5, sizeZ + 0.3), CFrame.new(base + Vector3.new(0, floor * FLOOR + 5.5, 0)))
		end
		local spacing = if style == "stone" then 6 else 8
		for _, along in { "x", "z" } do
			local span = if along == "x" then sizeX else sizeZ
			local across = if along == "x" then sizeZ else sizeX
			local count = math.floor(span / spacing)
			for i = 1, count - 1 do
				local offset = -span / 2 + i * span / count
				for _, side in { -1, 1 } do
					local position = if along == "x"
						then Vector3.new(offset, height / 2, side * (across / 2 + 0.25))
						else Vector3.new(side * (across / 2 + 0.25), height / 2, offset)
					local size = if along == "x" then Vector3.new(1.6, height, 0.6) else Vector3.new(0.6, height, 1.6)
					box(size, CFrame.new(base + position), wall, material)
				end
			end
		end
	end
	-- Lift motor room on the roof
	box(Vector3.new(sizeX * 0.4, 8, sizeZ * 0.4), CFrame.new(base + Vector3.new(0, height + 4, 0)), C.Concrete, Enum.Material.Concrete)
end

-- Grass, paths, a pond, trees and benches inside a low hedge
function TownBuildings.park(minX: number, maxX: number, minZ: number, maxZ: number, random: Random)
	local width, depth = maxX - minX, maxZ - minZ
	local middle = Vector3.new((minX + maxX) / 2, 0, (minZ + maxZ) / 2)
	local grass = box(Vector3.new(width, 0.3, depth), CFrame.new(middle.X, PAVEMENT_TOP + 0.15, middle.Z), C.Grass, Enum.Material.Grass)
	TownKit.tag(grass, "MapPark")

	local top = PAVEMENT_TOP + 0.3
	for _, alongX in { true, false } do
		local size = if alongX then Vector3.new(width, 0.1, 10) else Vector3.new(10, 0.1, depth)
		detail(size, CFrame.new(middle.X, top + 0.05, middle.Z), Color3.fromRGB(196, 180, 150), Enum.Material.Sand).CanCollide = true
	end

	-- Hedge round the edge, with gaps where the paths come out
	local gap = 14
	for _, side in { -1, 1 } do
		local z = middle.Z + side * (depth / 2 - 1)
		local x = middle.X + side * (width / 2 - 1)
		local half = (width - gap) / 2
		for _, part in { -1, 1 } do
			box(Vector3.new(half, 3.5, 2), CFrame.new(middle.X + part * (gap / 2 + half / 2), top + 1.75, z), C.Hedge, Enum.Material.Grass)
		end
		local halfDepth = (depth - gap) / 2
		for _, part in { -1, 1 } do
			box(Vector3.new(2, 3.5, halfDepth), CFrame.new(x, top + 1.75, middle.Z + part * (gap / 2 + halfDepth / 2)), C.Hedge, Enum.Material.Grass)
		end
	end

	-- Pond in one corner
	local pondCentre = middle + Vector3.new(width * 0.24, 0, depth * 0.24)
	local pondSize = math.min(width, depth) * 0.3
	local pond = box(Vector3.new(0.4, pondSize, pondSize * 1.4), CFrame.new(pondCentre.X, top + 0.1, pondCentre.Z) * CFrame.Angles(0, 0, math.pi / 2), C.Water, Enum.Material.Glass)
	pond.Shape = Enum.PartType.Cylinder
	pond.Transparency = 0.15
	pond.Reflectance = 0.3

	for _ = 1, math.floor(width * depth / 2200) do
		local x = minX + 8 + random:NextNumber() * (width - 16)
		local z = minZ + 8 + random:NextNumber() * (depth - 16)
		local nearPath = math.abs(x - middle.X) < 10 or math.abs(z - middle.Z) < 10
		local nearPond = (Vector3.new(x, 0, z) - pondCentre).Magnitude < pondSize
		if not nearPath and not nearPond then
			TownProps.tree(Vector3.new(x, top, z), 0.9 + random:NextNumber() * 0.5)
		end
	end
	for _, offset in { -0.3, 0.3 } do
		TownProps.bench(Vector3.new(middle.X + width * offset, 0, middle.Z + 7), Vector3.new(0, 0, -1))
		TownProps.bench(Vector3.new(middle.X + 7, 0, middle.Z + depth * offset), Vector3.new(-1, 0, 0))
	end
end

local function fountain(centre: Vector3)
	local base = Vector3.new(centre.X, PAVEMENT_TOP, centre.Z)
	TownKit.post(28, 2, base, C.Stone, Enum.Material.Limestone)
	local water = TownKit.post(25, 0.3, base + Vector3.new(0, 1.8, 0), C.Water, Enum.Material.Glass)
	water.Transparency = 0.2
	water.Reflectance = 0.3
	water.CanCollide = false
	TownKit.post(3, 7, base, C.Stone, Enum.Material.Limestone)
	TownKit.post(9, 1, base + Vector3.new(0, 7, 0), C.Stone, Enum.Material.Limestone)
	local spout = TownKit.post(1.2, 4, base + Vector3.new(0, 8, 0), Color3.fromRGB(200, 225, 235), Enum.Material.Glass)
	spout.Transparency = 0.4
	spout.CanCollide = false
end

-- A cobbled square with a tall column, two fountains and benches: where everyone spawns
function TownBuildings.plaza(minX: number, maxX: number, minZ: number, maxZ: number)
	local width, depth = maxX - minX, maxZ - minZ
	local middle = Vector3.new((minX + maxX) / 2, 0, (minZ + maxZ) / 2)
	box(Vector3.new(width, 0.2, depth), CFrame.new(middle.X, PAVEMENT_TOP + 0.1, middle.Z), Color3.fromRGB(150, 145, 138), Enum.Material.Cobblestone)
	local top = PAVEMENT_TOP + 0.2

	-- The column, offset from the spawn point in the middle of the map
	local column = Vector3.new(middle.X - width * 0.22, top, middle.Z)
	box(Vector3.new(30, 2, 30), CFrame.new(column + Vector3.new(0, 1, 0)), C.Stone, Enum.Material.Limestone)
	box(Vector3.new(24, 2, 24), CFrame.new(column + Vector3.new(0, 3, 0)), C.Stone, Enum.Material.Limestone)
	box(Vector3.new(13, 16, 13), CFrame.new(column + Vector3.new(0, 12, 0)), C.Portland, Enum.Material.Limestone)
	TownKit.post(6, 110, column + Vector3.new(0, 20, 0), C.Portland, Enum.Material.Limestone)
	box(Vector3.new(9, 4, 9), CFrame.new(column + Vector3.new(0, 132, 0)), C.Bronze, Enum.Material.Metal)
	box(Vector3.new(2.4, 8, 2.4), CFrame.new(column + Vector3.new(0, 138, 0)), C.Bronze, Enum.Material.Metal)
	box(Vector3.new(3.2, 1, 3.2), CFrame.new(column + Vector3.new(0, 142.5, 0)), C.Bronze, Enum.Material.Metal)
	for _, offset in { Vector3.new(1, 0, 0), Vector3.new(-1, 0, 0), Vector3.new(0, 0, 1), Vector3.new(0, 0, -1) } do
		local lion = TownKit.facing(column + offset * 12 + Vector3.new(0, 4, 0), offset)
		box(Vector3.new(4, 4, 9), lion * CFrame.new(0, 2, 0), C.Bronze, Enum.Material.Metal)
		box(Vector3.new(4.4, 4.4, 3.6), lion * CFrame.new(0, 4.6, -3.4), C.Bronze, Enum.Material.Metal)
	end

	fountain(Vector3.new(column.X + 55, 0, middle.Z - depth * 0.28))
	fountain(Vector3.new(column.X + 55, 0, middle.Z + depth * 0.28))

	-- Rows of plane trees along the north and south sides, like a London square
	for x = minX + 16, maxX - 16, 26 do
		for _, z in { minZ + 12, maxZ - 12 } do
			TownProps.tree(Vector3.new(x, top, z), 1.15)
		end
	end
	for _, z in { -0.4, 0.4 } do
		TownProps.bench(Vector3.new(middle.X + width * 0.2, 0, middle.Z + depth * z * 0.6), Vector3.new(0, 0, -z))
	end
	TownProps.phoneBox(Vector3.new(maxX - 6, 0, minZ + 6), Vector3.new(1, 0, 0))
	TownProps.phoneBox(Vector3.new(maxX - 6, 0, minZ + 11), Vector3.new(1, 0, 0))
	TownProps.postBox(Vector3.new(maxX - 6, 0, maxZ - 8), Vector3.new(1, 0, 0))
end

-- A clock face for the clock tower. The server turns the hands to London time (see TestTown).
local function clockFace(host: BasePart, face: Enum.NormalId)
	local surface = Instance.new("SurfaceGui")
	surface.Face = face
	surface.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	surface.PixelsPerStud = 20
	surface.LightInfluence = 0.5
	surface.Parent = host

	local dial = Instance.new("Frame")
	dial.AnchorPoint = Vector2.new(0.5, 0.5)
	dial.Position = UDim2.fromScale(0.5, 0.5)
	dial.Size = UDim2.fromScale(0.92, 0.92)
	dial.BackgroundColor3 = Color3.fromRGB(245, 240, 225)
	dial.Parent = surface
	local round = Instance.new("UICorner")
	round.CornerRadius = UDim.new(0.5, 0)
	round.Parent = dial
	local rim = Instance.new("UIStroke")
	rim.Thickness = 10
	rim.Color = Color3.fromRGB(30, 30, 32)
	rim.Parent = dial

	for hour = 1, 12 do
		local angle = math.rad(hour * 30)
		local tick = Instance.new("Frame")
		tick.AnchorPoint = Vector2.new(0.5, 0.5)
		tick.Position = UDim2.fromScale(0.5 + 0.4 * math.sin(angle), 0.5 - 0.4 * math.cos(angle))
		tick.Size = UDim2.fromScale(0.035, if hour % 3 == 0 then 0.13 else 0.08)
		tick.Rotation = hour * 30
		tick.BackgroundColor3 = Color3.fromRGB(30, 30, 32)
		tick.BorderSizePixel = 0
		tick.Parent = dial
	end

	-- Each hand sits in a square frame the size of the dial, so turning the frame turns the hand around the middle
	for _, hand in { { name = "HourHand", width = 0.045, length = 0.26 }, { name = "MinuteHand", width = 0.03, length = 0.4 } } do
		local pivot = Instance.new("Frame")
		pivot.Name = hand.name
		pivot.Size = UDim2.fromScale(1, 1)
		pivot.BackgroundTransparency = 1
		pivot.Parent = dial
		local bar = Instance.new("Frame")
		bar.AnchorPoint = Vector2.new(0.5, 1)
		bar.Position = UDim2.fromScale(0.5, 0.5)
		bar.Size = UDim2.fromScale(hand.width, hand.length)
		bar.BackgroundColor3 = Color3.fromRGB(20, 20, 22)
		bar.BorderSizePixel = 0
		bar.Parent = pivot
	end
	TownKit.tag(host, "ClockFace")
end

local function pinnacle(at: Vector3, height: number, colour: Color3)
	box(Vector3.new(1.6, height, 1.6), CFrame.new(at + Vector3.new(0, height / 2, 0)), colour, Enum.Material.Limestone)
	box(Vector3.new(0.6, 3, 0.6), CFrame.new(at + Vector3.new(0, height + 1.5, 0)), C.Gold, Enum.Material.Metal)
end

-- The clock tower: a tall stone shaft, four clock faces, a belfry and a stepped spire
function TownBuildings.clockTower(base: Vector3)
	local stone = C.Gothic
	local shaftHeight = 150
	local width = 26
	box(Vector3.new(width, shaftHeight, width), CFrame.new(base + Vector3.new(0, shaftHeight / 2, 0)), stone, Enum.Material.Limestone)
	for i = 1, 3 do
		local offset = -width / 2 + i * width / 4
		for _, side in { -1, 1 } do
			box(Vector3.new(1.4, shaftHeight, 0.8), CFrame.new(base + Vector3.new(offset, shaftHeight / 2, side * (width / 2 + 0.3))), stone, Enum.Material.Limestone)
			box(Vector3.new(0.8, shaftHeight, 1.4), CFrame.new(base + Vector3.new(side * (width / 2 + 0.3), shaftHeight / 2, offset)), stone, Enum.Material.Limestone)
		end
	end
	for y = 25, shaftHeight - 1, 25 do
		detail(Vector3.new(width + 1.4, 1, width + 1.4), CFrame.new(base + Vector3.new(0, y, 0)), stone:Lerp(Color3.new(0, 0, 0), 0.1), Enum.Material.Limestone)
	end

	local stageSize = 30
	local stage = box(Vector3.new(stageSize, 30, stageSize), CFrame.new(base + Vector3.new(0, shaftHeight + 15, 0)), stone, Enum.Material.Limestone)
	detail(Vector3.new(stageSize + 0.8, 1.2, stageSize + 0.8), CFrame.new(base + Vector3.new(0, shaftHeight, 0)), C.Gold, Enum.Material.Metal)
	detail(Vector3.new(stageSize + 0.8, 1.2, stageSize + 0.8), CFrame.new(base + Vector3.new(0, shaftHeight + 30, 0)), C.Gold, Enum.Material.Metal)
	for _, faceInfo in {
		{ direction = Vector3.new(0, 0, -1), face = Enum.NormalId.Front },
		{ direction = Vector3.new(0, 0, 1), face = Enum.NormalId.Back },
		{ direction = Vector3.new(-1, 0, 0), face = Enum.NormalId.Left },
		{ direction = Vector3.new(1, 0, 0), face = Enum.NormalId.Right },
	} do
		local panel = detail(Vector3.new(23, 23, 23), stage.CFrame + faceInfo.direction * 3.8, stone, Enum.Material.Limestone)
		panel.Transparency = 1
		clockFace(panel, faceInfo.face)
	end

	local belfryBottom = shaftHeight + 30
	box(Vector3.new(24, 18, 24), CFrame.new(base + Vector3.new(0, belfryBottom + 9, 0)), stone, Enum.Material.Limestone)
	for _, direction in { Vector3.new(1, 0, 0), Vector3.new(-1, 0, 0), Vector3.new(0, 0, 1), Vector3.new(0, 0, -1) } do
		local size = if direction.X ~= 0 then Vector3.new(0.3, 12, 15) else Vector3.new(15, 12, 0.3)
		detail(size, CFrame.new(base + Vector3.new(0, belfryBottom + 9, 0) + direction * 12.1), Color3.fromRGB(25, 25, 28))
	end
	for _, corner in { Vector3.new(1, 0, 1), Vector3.new(-1, 0, 1), Vector3.new(1, 0, -1), Vector3.new(-1, 0, -1) } do
		pinnacle(base + Vector3.new(0, shaftHeight + 30, 0) + corner * 14, 10, stone)
		pinnacle(base + Vector3.new(0, belfryBottom + 18, 0) + corner * 11, 8, stone)
	end

	local spireBottom = belfryBottom + 18
	local steps = {
		{ size = 26, height = 3, colour = C.Gold },
		{ size = 20, height = 12, colour = C.Slate },
		{ size = 15, height = 12, colour = C.Slate },
		{ size = 10, height = 12, colour = C.Slate },
		{ size = 5, height = 10, colour = C.Slate },
	}
	local y = spireBottom
	for _, step in steps do
		local material = if step.colour == C.Gold then Enum.Material.Metal else Enum.Material.Slate
		box(Vector3.new(step.size, step.height, step.size), CFrame.new(base + Vector3.new(0, y + step.height / 2, 0)), step.colour, material)
		y += step.height
	end
	box(Vector3.new(1, 16, 1), CFrame.new(base + Vector3.new(0, y + 8, 0)), C.Gold, Enum.Material.Metal)
end

-- The long Gothic palace by the river, with a square tower at the far end
function TownBuildings.palace(frame: CFrame, length: number, depth: number)
	local stone = C.Gothic
	local height = 46
	box(Vector3.new(length, height, depth), frame * CFrame.new(0, height / 2, depth / 2), stone, Enum.Material.Limestone)
	for floor = 0, 3 do
		window(Vector3.new(length + 0.3, 5.5, depth + 0.3), frame * CFrame.new(0, floor * FLOOR + 6, depth / 2))
	end
	local count = math.floor(length / 6)
	for i = 0, count do
		local x = -length / 2 + i * length / count
		for _, z in { -0.3, depth + 0.3 } do
			box(Vector3.new(1.3, height + 5, 0.8), frame * CFrame.new(x, (height + 5) / 2, z), stone, Enum.Material.Limestone)
		end
		if i % 2 == 0 then
			pinnacle((frame * CFrame.new(x, height + 5, -0.3)).Position, 4, stone)
		end
	end
	box(Vector3.new(length - 4, 10, depth * 0.5), frame * CFrame.new(0, height + 5, depth / 2), C.Slate, Enum.Material.Slate, "WedgePart")
	-- The square tower at the far end
	local tower = frame * CFrame.new(length / 2 - 20, 0, depth / 2)
	box(Vector3.new(40, 140, 40), tower * CFrame.new(0, 70, 0), stone, Enum.Material.Limestone)
	for floor = 1, 11 do
		window(Vector3.new(40.3, 5, 40.3), tower * CFrame.new(0, floor * FLOOR + 6, 0))
	end
	for _, corner in { Vector3.new(1, 0, 1), Vector3.new(-1, 0, 1), Vector3.new(1, 0, -1), Vector3.new(-1, 0, -1) } do
		local at = (tower * CFrame.new(corner * 19.5)).Position
		box(Vector3.new(4, 150, 4), CFrame.new(at + Vector3.new(0, 75, 0)), stone, Enum.Material.Limestone)
		pinnacle(at + Vector3.new(0, 150, 0), 12, stone)
	end
end

-- Big flat-roofed shed with columns, for the bus garage and the petrol station canopy
local function canopy(centre: Vector3, sizeX: number, sizeZ: number, height: number, roofColour: Color3, columns: { Vector3 })
	box(Vector3.new(sizeX, 1.6, sizeZ), CFrame.new(centre + Vector3.new(0, height, 0)), roofColour, Enum.Material.Metal)
	for _, offset in columns do
		box(Vector3.new(1.4, height, 1.4), CFrame.new(centre + offset + Vector3.new(0, height / 2, 0)), Color3.fromRGB(220, 220, 222), Enum.Material.Metal)
	end
end

-- Parking bays painted on a yard
local function bays(from: Vector3, step: Vector3, count: number, length: number, along: Vector3)
	for i = 0, count do
		local at = from + step * i
		local line = TownKit.paint(0.5, length, at)
		line.CFrame = TownKit.facing(Vector3.new(at.X, ROAD_TOP + 0.02, at.Z), along)
	end
end

-- The Car team's depot: a petrol station forecourt with pumps, a canopy and a mini market
function TownBuildings.petrolStation(minX: number, maxX: number, minZ: number, maxZ: number, depot: Model)
	local centreX = (minX + maxX) / 2
	local forecourt = Vector3.new(centreX, ROAD_TOP, minZ + 80)
	local columns = {}
	for _, x in { -30, 0, 30 } do
		for _, z in { -16, 16 } do
			table.insert(columns, Vector3.new(x, 0, z))
		end
	end
	canopy(forecourt, 76, 44, 17, Color3.fromRGB(235, 235, 235), columns)
	detail(Vector3.new(76.4, 2.6, 44.4), CFrame.new(forecourt + Vector3.new(0, 17, 0)), Color3.fromRGB(30, 130, 70))
	local band = detail(Vector3.new(20, 2.2, 0.2), CFrame.new(forecourt + Vector3.new(0, 17, -22.3)), Color3.fromRGB(30, 130, 70))
	TownKit.text(band, Enum.NormalId.Front, "PETROL", C.White)
	for _, x in { -30, 30 } do
		local island = forecourt + Vector3.new(x, 0, 0)
		box(Vector3.new(4, 0.6, 26), CFrame.new(island + Vector3.new(0, 0.3, 0)), C.Kerb, Enum.Material.Concrete)
		for _, z in { -7, 7 } do
			box(Vector3.new(2.4, 5.5, 3), CFrame.new(island + Vector3.new(0, 3.35, z)), Color3.fromRGB(200, 30, 35))
			detail(Vector3.new(2.5, 1.2, 1.6), CFrame.new(island + Vector3.new(0, 4.6, z)), C.StreetBlack, Enum.Material.Glass)
		end
	end

	-- The mini market behind the forecourt
	local shop = CFrame.new(centreX, PAVEMENT_TOP, minZ + 150)
	box(Vector3.new(80, 0.6, 34), shop * CFrame.new(0, -0.3, 0), C.Pavement, Enum.Material.Pavement)
	box(Vector3.new(60, 15, 26), shop * CFrame.new(0, 7.5, 4), Color3.fromRGB(70, 72, 76), Enum.Material.Concrete)
	window(Vector3.new(44, 8, 0.3), shop * CFrame.new(-6, 4.6, -9))
	local fascia = detail(Vector3.new(60.4, 3, 0.8), shop * CFrame.new(0, 13.2, -9.2), Color3.fromRGB(30, 130, 70))
	TownKit.text(fascia, Enum.NormalId.Front, "MINI MART", C.White)

	-- Price board by the road
	local totem = Vector3.new(maxX - 14, PAVEMENT_TOP, minZ + 16)
	box(Vector3.new(6, 14, 1.4), CFrame.new(totem + Vector3.new(0, 7, 0)), Color3.fromRGB(30, 130, 70))
	local prices = detail(Vector3.new(5, 6, 0.1), CFrame.new(totem + Vector3.new(0, 8, -0.75)), C.StreetBlack)
	TownKit.text(prices, Enum.NormalId.Front, "UNLEADED 139.9\nDIESEL 146.9", Color3.fromRGB(255, 200, 40))

	-- Parking spaces along the front, facing the road
	local first = minX + 22
	local spacing = 14
	local count = math.floor((maxX - minX - 44) / spacing)
	bays(Vector3.new(first - spacing / 2, 0, minZ + 26), Vector3.new(spacing, 0, 0), count, 18, Vector3.new(0, 0, 1))
	for i = 0, count - 1 do
		local spawn = detail(Vector3.new(6, 1, 14), TownKit.facing(Vector3.new(first + i * spacing, ROAD_TOP, minZ + 26), Vector3.new(0, 0, -1)), C.White)
		spawn.Name = "Spawn"
		spawn.Transparency = 1
		spawn.Parent = depot
	end
	-- Out in the daylight between the parking spaces and the canopy, so the car isn't in shadow
	depot:SetAttribute("ShowroomSpot", TownKit.facing(Vector3.new(centreX, ROAD_TOP, minZ + 46), Vector3.new(1, 0, -0.35)))
end

-- The Bus team's depot: a big garage shed with a yard of bus bays
function TownBuildings.busGarage(minX: number, maxX: number, minZ: number, maxZ: number, depot: Model)
	local centreZ = (minZ + maxZ) / 2
	local shed = Vector3.new(minX + 80, ROAD_TOP, centreZ)
	local columns = {}
	for _, x in { -55, 0, 55 } do
		for z = -110, 110, 55 do
			table.insert(columns, Vector3.new(x, 0, z))
		end
	end
	canopy(shed, 120, 240, 26, Color3.fromRGB(120, 125, 130), columns)
	box(Vector3.new(2, 26, 240), CFrame.new(shed + Vector3.new(-60, 13, 0)), C.RedBrick, Enum.Material.Brick)
	local sign = detail(Vector3.new(0.4, 5, 60), CFrame.new(shed + Vector3.new(60.3, 23, 0)), Color3.fromRGB(210, 30, 35))
	TownKit.text(sign, Enum.NormalId.Right, "BUS GARAGE", C.White)

	local spawnX = maxX - 50
	local spacing = 22
	local count = math.floor((maxZ - minZ - 40) / spacing)
	local first = minZ + 20 + spacing / 2
	bays(Vector3.new(spawnX, 0, first - spacing / 2), Vector3.new(0, 0, spacing), count, 40, Vector3.new(1, 0, 0))
	for i = 0, count - 1 do
		local spawn = detail(Vector3.new(9, 1, 34), TownKit.facing(Vector3.new(spawnX, ROAD_TOP, first + i * spacing), Vector3.new(1, 0, 0)), C.White)
		spawn.Name = "Spawn"
		spawn.Transparency = 1
		spawn.Parent = depot
	end
	depot:SetAttribute("ShowroomSpot", TownKit.facing(Vector3.new(minX + 178, ROAD_TOP, centreZ - 30), Vector3.new(0.2, 0, -1)))
end

-- The Emergency team's depot: a brick police station with a blue lamp, and a yard behind the gates
function TownBuildings.policeStation(minX: number, maxX: number, minZ: number, maxZ: number, depot: Model)
	local centreX = (minX + maxX) / 2
	-- The station faces the yard (south); its back is on the north road
	local station = CFrame.new(centreX, PAVEMENT_TOP, minZ + 70)
	box(Vector3.new(200, 0.6, 70), CFrame.new(centreX, PAVEMENT_TOP - 0.3, minZ + 35), C.Pavement, Enum.Material.Pavement)
	TownBuildings.plainRow(station * CFrame.Angles(0, math.pi, 0), 180, 50, 3, C.RedBrick)
	local sign = detail(Vector3.new(40, 4, 0.6), station * CFrame.new(0, 9.4, 0.5), Color3.fromRGB(15, 40, 120))
	TownKit.text(sign, Enum.NormalId.Back, "POLICE", C.White)
	-- The traditional blue lamp over the door
	local lamp = detail(Vector3.new(2, 2.6, 2), station * CFrame.new(0, 14, 2), Color3.fromRGB(40, 90, 230), Enum.Material.Neon)
	local glow = Instance.new("PointLight")
	glow.Color = Color3.fromRGB(60, 110, 255)
	glow.Range = 14
	glow.Parent = lamp

	local spawnZ = maxZ - 40
	local spacing = 14
	local first = minX + 30
	local count = math.floor((maxX - minX - 60) / spacing)
	bays(Vector3.new(first - spacing / 2, 0, spawnZ), Vector3.new(spacing, 0, 0), count, 20, Vector3.new(0, 0, 1))
	for i = 0, count - 1 do
		local spawn = detail(Vector3.new(7, 1, 19), TownKit.facing(Vector3.new(first + i * spacing, ROAD_TOP, spawnZ), Vector3.new(0, 0, 1)), C.White)
		spawn.Name = "Spawn"
		spawn.Transparency = 1
		spawn.Parent = depot
	end
	depot:SetAttribute("ShowroomSpot", TownKit.facing(Vector3.new(centreX + 30, ROAD_TOP, minZ + 150), Vector3.new(1, 0, 0.4)))
end

-- The big observation wheel on the south bank. The spinning part is tagged so MapLife turns it on every player's device.
function TownBuildings.bigWheel(hub: Vector3, radius: number)
	local rotor = Instance.new("Model")
	rotor.Name = "BigWheelRotor"
	rotor.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	rotor:SetAttribute("Hub", hub)
	local parent = TownKit.getParent()
	TownKit.setParent(rotor)

	local white = Color3.fromRGB(235, 237, 240)
	local segments = 40
	for i = 0, segments - 1 do
		local angle = i / segments * math.pi * 2
		local position = hub + Vector3.new(math.cos(angle), math.sin(angle), 0) * radius
		detail(Vector3.new(2 * math.pi * radius / segments + 0.6, 2.4, 3), CFrame.new(position) * CFrame.Angles(0, 0, angle + math.pi / 2), white, Enum.Material.Metal)
	end
	local spokes = 20
	for i = 0, spokes - 1 do
		local angle = i / spokes * math.pi * 2
		local spoke = detail(Vector3.new(radius, 0.5, 0.5), CFrame.new(hub + Vector3.new(math.cos(angle), math.sin(angle), 0) * radius / 2) * CFrame.Angles(0, 0, angle), white, Enum.Material.Metal)
		spoke.Shape = Enum.PartType.Cylinder
	end
	local capsules = 32
	for i = 0, capsules - 1 do
		local angle = i / capsules * math.pi * 2
		local capsule = detail(Vector3.new(7, 7, 7), CFrame.new(hub + Vector3.new(math.cos(angle), math.sin(angle), 0) * (radius + 4.5)), Color3.fromRGB(190, 215, 230), Enum.Material.Glass)
		capsule.Shape = Enum.PartType.Ball
		capsule.Transparency = 0.25
	end
	local hubPart = detail(Vector3.new(8, 10, 10), CFrame.new(hub) * CFrame.Angles(0, math.pi / 2, 0), white, Enum.Material.Metal)
	hubPart.Shape = Enum.PartType.Cylinder

	TownKit.setParent(parent :: Instance)
	rotor.Parent = parent
	TownKit.tag(rotor, "BigWheelRotor")

	-- Legs leaning back from the hub to the ground on the land side
	for _, x in { -36, 36 } do
		local foot = Vector3.new(hub.X + x, PAVEMENT_TOP, hub.Z + 70)
		local legLength = (hub - foot).Magnitude
		box(Vector3.new(3, 3, legLength), CFrame.lookAt((hub + foot) / 2, foot), white, Enum.Material.Metal)
	end
end

return TownBuildings
