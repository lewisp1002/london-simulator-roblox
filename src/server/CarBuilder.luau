-- Builds every vehicle in the game. Cars.luau uses CarBuilder.build both for drivable vehicles and for
-- the display models in the menu.
-- If ServerStorage → VehicleBodies has a detailed body with the vehicle's id (made from the free Swat Motors
-- Company models by tools/prepare_vehicle_bodies.luau), that body is bolted onto our own invisible chassis.
-- Otherwise the vehicle is built out of parts: body, windows, wheels, lights, number plates, seats and liveries,
-- shaped like the real thing (hatchbacks, saloons, a black cab, red buses, Battenburg police cars, an ambulance).
-- Measurements are in studs. The front of a vehicle is -Z and the driver sits on the right (+X), like in the UK.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Vehicles = require(ReplicatedStorage.Shared.Vehicles)

type Vehicle = Vehicles.Vehicle

-- Car parts slide with no friction: the Driving script controls speed and grip itself
local SLIDING = PhysicalProperties.new(0.7, 0, 0, 100, 100)
-- A heavy, low chassis stops the car tipping over
local HEAVY_SLIDING = PhysicalProperties.new(3, 0, 0, 100, 100)

local GLASS = Color3.fromRGB(28, 36, 44)
local TRIM = Color3.fromRGB(26, 26, 28)
local CHROME = Color3.fromRGB(185, 188, 194)
local TYRE = Color3.fromRGB(20, 20, 20)
local HEADLIGHT = Color3.fromRGB(225, 228, 230)
local TAILLIGHT = Color3.fromRGB(150, 8, 12)
local INDICATOR_OFF = Color3.fromRGB(150, 95, 30)
local BLUE_OFF = Color3.fromRGB(25, 35, 75)
local BATTENBURG_BLUE = Color3.fromRGB(12, 45, 150)
local BATTENBURG_YELLOW = Color3.fromRGB(250, 215, 20)
local BATTENBURG_GREEN = Color3.fromRGB(0, 120, 60)
local HEADLIGHT_ON = Color3.fromRGB(255, 252, 235)
local TAILLIGHT_ON = Color3.fromRGB(255, 25, 30)
local INDICATOR_ON = Color3.fromRGB(255, 160, 20)
local BLUE_ON = Color3.fromRGB(40, 100, 255)

-- Colours for part-built vehicles when the vehicle has no paint of its own
local LIVERY_PAINT: { [string]: Color3 } = {
	Police = Color3.fromRGB(236, 237, 239),
	Ambulance = Color3.fromRGB(250, 220, 30),
	Taxi = Color3.fromRGB(22, 23, 26),
}
local DEFAULT_PAINT = Color3.fromRGB(170, 174, 180)

-- Passenger seats you can get into, at most (a double-decker has over 70 seats)
local MAX_PASSENGERS = 8

local BUS_ROUTES = { "24  Pimlico", "38  Victoria", "73  Stoke Newington", "159  Streatham", "12  Oxford Circus", "88  Clapham Common" }

type Shape = {
	kind: string, -- "car", "van" or "bus"
	length: number,
	width: number,
	wheelbase: number,
	wheelRadius: number,
	bodyBottom: number, -- height of the bottom of the painted body
	bodyHeight: number, -- the painted lower half, up to the bottom of the windows
	bonnet: number, -- front of the car to the bottom of the windscreen
	screen: number, -- how far the windscreen slopes back
	cabinHeight: number, -- height of the windows
	rear: number, -- how far the rear window slopes (0 for a flat back)
	boot: number, -- flat boot behind the rear window (0 for hatchbacks and estates)
	inset: number, -- how far the windows sit in from the sides
	decks: number?, -- buses only
	reverseSpeed: number?,
}

local SHAPES: { [string]: Shape } = {
	hatch = { kind = "car", length = 12.8, width = 6, wheelbase = 8, wheelRadius = 1.2, bodyBottom = 0.9, bodyHeight = 2.3, bonnet = 3, screen = 2.2, cabinHeight = 2.6, rear = 0.9, boot = 0, inset = 0.35 },
	saloon = { kind = "car", length = 14.6, width = 6.2, wheelbase = 8.8, wheelRadius = 1.25, bodyBottom = 0.9, bodyHeight = 2.3, bonnet = 3.6, screen = 2.6, cabinHeight = 2.6, rear = 2, boot = 2.4, inset = 0.4 },
	estate = { kind = "car", length = 15, width = 6.2, wheelbase = 9, wheelRadius = 1.25, bodyBottom = 0.9, bodyHeight = 2.3, bonnet = 3.6, screen = 2.6, cabinHeight = 2.6, rear = 0.6, boot = 0, inset = 0.4 },
	suv = { kind = "car", length = 15.4, width = 6.8, wheelbase = 9.4, wheelRadius = 1.5, bodyBottom = 1.3, bodyHeight = 2.6, bonnet = 3.6, screen = 2.2, cabinHeight = 2.7, rear = 0.8, boot = 0, inset = 0.4 },
	coupe = { kind = "car", length = 14.4, width = 6.4, wheelbase = 8.8, wheelRadius = 1.3, bodyBottom = 0.8, bodyHeight = 2, bonnet = 4.4, screen = 2.8, cabinHeight = 2.4, rear = 2.6, boot = 1.4, inset = 0.5 },
	cab = { kind = "car", length = 14.8, width = 6.4, wheelbase = 9.4, wheelRadius = 1.3, bodyBottom = 1, bodyHeight = 2.4, bonnet = 3.2, screen = 1.6, cabinHeight = 3.3, rear = 0.6, boot = 0.8, inset = 0.3 },
	van = { kind = "van", length = 19, width = 7.2, wheelbase = 11.6, wheelRadius = 1.5, bodyBottom = 1.2, bodyHeight = 2.6, bonnet = 2.6, screen = 1.6, cabinHeight = 2.4, rear = 0, boot = 0, inset = 0.2 },
	bus_single = { kind = "bus", decks = 1, length = 34, width = 8.4, wheelbase = 20, wheelRadius = 1.8, bodyBottom = 0.9, bodyHeight = 2.6, bonnet = 0, screen = 0, cabinHeight = 3.2, rear = 0, boot = 0, inset = 0, reverseSpeed = 16 },
	bus_double = { kind = "bus", decks = 2, length = 34, width = 8.4, wheelbase = 20, wheelRadius = 1.8, bodyBottom = 0.9, bodyHeight = 2.6, bonnet = 0, screen = 0, cabinHeight = 3.2, rear = 0, boot = 0, inset = 0, reverseSpeed = 16 },
}

-- Everything the part-making helpers need while one vehicle is being built
type Builder = {
	model: Model,
	origin: CFrame,
	chassis: BasePart,
	paint: Color3,
	bodyRoot: BasePart?, -- what the body hangs off, when it can lean (see buildFromBody)
}

local CarBuilder = {}

-- A part welded to the chassis. `at` is measured from the middle of the vehicle at road level.
local function part(b: Builder, name: string, size: Vector3, at: CFrame, colour: Color3, material: Enum.Material?, className: string?): Part
	-- Typed as a Part so callers can set Shape; WedgeParts made here just never use it
	local newPart = Instance.new((className or "Part") :: any) :: Part
	newPart.Name = name
	newPart.Size = size
	newPart.CFrame = b.origin * at
	newPart.Color = colour
	newPart.Material = material or Enum.Material.SmoothPlastic
	newPart.TopSurface = Enum.SurfaceType.Smooth
	newPart.BottomSurface = Enum.SurfaceType.Smooth
	newPart.CanCollide = false
	newPart.CanTouch = false
	newPart.Massless = true
	newPart.CustomPhysicalProperties = SLIDING
	newPart.Parent = b.model

	local weld = Instance.new("WeldConstraint")
	weld.Part0 = b.chassis
	weld.Part1 = newPart
	weld.Parent = newPart
	return newPart
end

-- A part in the vehicle's paint colour. The menu recolours anything marked "Paint" when you pick a colour.
local function painted(b: Builder, name: string, size: Vector3, at: CFrame, className: string?): Part
	local newPart = part(b, name, size, at, b.paint, Enum.Material.SmoothPlastic, className)
	newPart.Reflectance = 0.06
	newPart:SetAttribute("Paint", true)
	return newPart
end

local function glass(b: Builder, name: string, size: Vector3, at: CFrame, className: string?): Part
	local newPart = part(b, name, size, at, GLASS, Enum.Material.Glass, className)
	newPart.Transparency = 0.2
	newPart.Reflectance = 0.15
	return newPart
end

-- Marks a part as a lamp for the VehicleLights script: which switch works it ("Head", "Tail", "IndicatorL",
-- "IndicatorR", "BlueA", "BlueB" or "Beam") and how it looks when it's on. It starts off.
local function tagLamp(lamp: BasePart, role: string, onColour: Color3, onTransparency: number?)
	lamp:SetAttribute("LightRole", role)
	lamp:SetAttribute("OnColor", onColour)
	lamp:SetAttribute("OnTransparency", onTransparency or 0)
	lamp:SetAttribute("OffColor", lamp.Color)
	lamp:SetAttribute("OffTransparency", lamp.Transparency)
	lamp:SetAttribute("OffMaterial", lamp.Material.Name)
end

-- Words printed on a part's face: number plates, "POLICE", "TAXI", bus destinations
local function sign(host: BasePart, face: Enum.NormalId, text: string, textColour: Color3, background: Color3?, bold: boolean?)
	local surface = Instance.new("SurfaceGui")
	surface.Face = face
	surface.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	surface.PixelsPerStud = 60
	surface.LightInfluence = 0.6
	surface.Parent = host

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = if background then 0 else 1
	label.BackgroundColor3 = background or Color3.new()
	label.BorderSizePixel = 0
	label.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", if bold == false then Enum.FontWeight.Medium else Enum.FontWeight.Bold)
	label.TextScaled = true
	label.TextColor3 = textColour
	label.Text = text
	label.Parent = surface

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0.08, 0)
	padding.PaddingBottom = UDim.new(0.08, 0)
	padding.PaddingLeft = UDim.new(0.04, 0)
	padding.PaddingRight = UDim.new(0.04, 0)
	padding.Parent = label
end

-- Two rows of alternating squares down the side, the "Battenburg" pattern UK emergency vehicles use
local function battenburg(b: Builder, size: Vector3, at: CFrame, face: Enum.NormalId, first: Color3, second: Color3)
	local panel = part(b, "Livery", size, at, first)
	panel.Transparency = 1

	local surface = Instance.new("SurfaceGui")
	surface.Face = face
	surface.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	surface.PixelsPerStud = 20
	surface.LightInfluence = 1
	surface.Parent = panel

	local columns = math.max(4, math.round(size.Z / (size.Y / 2)))
	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.fromScale(1 / columns, 0.5)
	grid.CellPadding = UDim2.new()
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = surface

	for row = 0, 1 do
		for column = 0, columns - 1 do
			local square = Instance.new("Frame")
			square.BorderSizePixel = 0
			square.BackgroundColor3 = if (row + column) % 2 == 0 then first else second
			square.LayoutOrder = row * columns + column
			square.Parent = surface
		end
	end
end

local function plate(b: Builder, text: string, y: number, z: number, isFront: boolean)
	local newPart = part(b, "NumberPlate", Vector3.new(2.6, 0.6, 0.1), CFrame.new(0, y, z), Color3.new(1, 1, 1))
	newPart.Color = if isFront then Color3.fromRGB(245, 245, 245) else Color3.fromRGB(255, 205, 0)
	sign(newPart, if isFront then Enum.NormalId.Front else Enum.NormalId.Back, text, Color3.new(0, 0, 0))
end

-- Headlights, tail lights and the four indicators. The VehicleLights script switches them on and off.
local function lights(b: Builder, width: number, front: number, back: number, y: number)
	for _, side in { -1, 1 } do
		local letter = if side < 0 then "L" else "R"

		local headlight = part(b, "Headlight", Vector3.new(1.3, 0.45, 0.12), CFrame.new(side * (width / 2 - 0.95), y, front - 0.06), HEADLIGHT)
		local beam = Instance.new("SpotLight")
		beam.Face = Enum.NormalId.Front
		beam.Range = 45
		beam.Angle = 70
		beam.Brightness = 4
		beam.Color = Color3.fromRGB(255, 248, 230)
		beam.Enabled = false
		beam.Parent = headlight
		tagLamp(headlight, "Head", HEADLIGHT_ON)

		local taillight = part(b, "Taillight", Vector3.new(1.3, 0.45, 0.12), CFrame.new(side * (width / 2 - 0.95), y, back + 0.06), TAILLIGHT)
		tagLamp(taillight, "Tail", TAILLIGHT_ON)

		local frontIndicator = part(b, "Indicator" .. "F" .. letter, Vector3.new(0.4, 0.35, 0.12), CFrame.new(side * (width / 2 - 0.12), y, front - 0.06), INDICATOR_OFF)
		local rearIndicator = part(b, "Indicator" .. "R" .. letter, Vector3.new(0.4, 0.35, 0.12), CFrame.new(side * (width / 2 - 0.12), y, back + 0.06), INDICATOR_OFF)
		tagLamp(frontIndicator, "Indicator" .. letter, INDICATOR_ON)
		tagLamp(rearIndicator, "Indicator" .. letter, INDICATOR_ON)
	end
end

local function blueLight(b: Builder, letter: string, size: Vector3, at: CFrame)
	local light = part(b, "BlueLight" .. letter, size, at, BLUE_OFF)
	local glow = Instance.new("PointLight")
	glow.Color = Color3.fromRGB(40, 90, 255)
	glow.Range = 18
	glow.Brightness = 5
	glow.Enabled = false
	glow.Parent = light
	tagLamp(light, "Blue" .. letter, BLUE_ON)
end

-- Wheels you can see (jointed so Driving can spin and steer them) and invisible balls that touch the road
local function wheels(b: Builder, shape: Shape)
	local r = shape.wheelRadius
	for _, z in { -shape.wheelbase / 2, shape.wheelbase / 2 } do
		for _, side in { -1, 1 } do
			local at = CFrame.new(side * (shape.width / 2 - 0.4), r, z)

			local wheel = Instance.new("Part")
			wheel.Name = "Wheel"
			wheel.Shape = Enum.PartType.Cylinder
			wheel.Size = Vector3.new(0.9, r * 2, r * 2)
			wheel.CFrame = b.origin * at
			wheel.Color = TYRE
			wheel.Material = Enum.Material.SmoothPlastic
			wheel.CanCollide = false
			wheel.CanTouch = false
			wheel.Massless = true
			wheel.Parent = b.model

			local hub = Instance.new("Part")
			hub.Name = "Hub"
			hub.Shape = Enum.PartType.Cylinder
			hub.Size = Vector3.new(0.96, r * 1.25, r * 1.25)
			hub.CFrame = wheel.CFrame
			hub.Color = CHROME
			hub.Material = Enum.Material.Metal
			hub.CanCollide = false
			hub.CanTouch = false
			hub.Massless = true
			hub.Parent = b.model
			local hubWeld = Instance.new("WeldConstraint")
			hubWeld.Part0 = wheel
			hubWeld.Part1 = hub
			hubWeld.Parent = hub

			local joint = Instance.new("Motor6D")
			joint.Name = "WheelJoint"
			joint.Part0 = b.chassis
			joint.Part1 = wheel
			joint.C0 = b.chassis.CFrame:ToObjectSpace(wheel.CFrame)
			joint:SetAttribute("Steers", z < 0)
			joint.Parent = b.chassis

			local contact = part(b, "TyreContact", Vector3.one * r * 2, at, TYRE)
			contact.Shape = Enum.PartType.Ball
			contact.Transparency = 1
			contact.CanCollide = true
		end
	end
end

-- Cars and the black cab: a painted lower body with a glass cabin on top
local function carBody(b: Builder, shape: Shape, vehicle: Vehicle, plateText: string): (Vector3, Vector3)
	local length, width = shape.length, shape.width
	local front, back = -length / 2, length / 2
	local bodyTop = shape.bodyBottom + shape.bodyHeight
	local cabinTop = bodyTop + shape.cabinHeight
	local glassWidth = width - 2 * shape.inset
	local screenStart = front + shape.bonnet
	local cabinStart = screenStart + shape.screen
	local rearStart = back - shape.boot - shape.rear
	local cabinLength = rearStart - cabinStart
	local cabinMiddle = cabinStart + cabinLength / 2
	local windowY = bodyTop + shape.cabinHeight / 2

	local body = painted(b, "Body", Vector3.new(width, shape.bodyHeight, length), CFrame.new(0, shape.bodyBottom + shape.bodyHeight / 2, 0))
	body.CanCollide = true

	glass(b, "Windscreen", Vector3.new(glassWidth, shape.cabinHeight, shape.screen), CFrame.new(0, windowY, screenStart + shape.screen / 2), "WedgePart")
	glass(b, "Windows", Vector3.new(glassWidth, shape.cabinHeight, cabinLength), CFrame.new(0, windowY, cabinMiddle))
	painted(b, "Roof", Vector3.new(glassWidth + 0.1, 0.3, cabinLength + 0.3), CFrame.new(0, cabinTop + 0.15, cabinMiddle))
	if shape.rear > 0 then
		glass(b, "RearWindow", Vector3.new(glassWidth, shape.cabinHeight, shape.rear), CFrame.new(0, windowY, rearStart + shape.rear / 2) * CFrame.Angles(0, math.pi, 0), "WedgePart")
	end

	for _, side in { -1, 1 } do
		local x = side * (glassWidth / 2 + 0.03)
		painted(b, "Pillar", Vector3.new(0.12, shape.cabinHeight, 0.45), CFrame.new(x, windowY, cabinStart + cabinLength * 0.42))
		painted(b, "Pillar", Vector3.new(0.12, shape.cabinHeight, 0.4), CFrame.new(x, windowY, rearStart - 0.2))
		painted(b, "Mirror", Vector3.new(0.6, 0.35, 0.3), CFrame.new(side * (width / 2 + 0.28), bodyTop + 0.35, cabinStart + 0.15))
		part(b, "Sill", Vector3.new(0.1, 0.3, length * 0.5), CFrame.new(side * (width / 2 + 0.03), shape.bodyBottom + 0.15, 0), TRIM)
		part(b, "DoorHandle", Vector3.new(0.08, 0.12, 0.5), CFrame.new(side * (width / 2 + 0.04), bodyTop - 0.45, cabinStart + 0.6), CHROME, Enum.Material.Metal)
	end

	part(b, "Bumper", Vector3.new(width + 0.1, 0.6, 0.4), CFrame.new(0, shape.bodyBottom + 0.3, front - 0.08), TRIM)
	part(b, "Bumper", Vector3.new(width + 0.1, 0.6, 0.4), CFrame.new(0, shape.bodyBottom + 0.3, back + 0.08), TRIM)
	part(b, "Grille", Vector3.new(width * 0.42, 0.6, 0.1), CFrame.new(0, shape.bodyBottom + shape.bodyHeight * 0.55, front - 0.05), TRIM)

	lights(b, width, front, back, shape.bodyBottom + shape.bodyHeight * 0.68)
	plate(b, plateText, shape.bodyBottom + 0.85, front - 0.32, true)
	plate(b, plateText, shape.bodyBottom + 1.05, back + 0.32, false)

	if vehicle.livery == "Police" then
		local height = shape.bodyHeight * 0.62
		for _, side in { -1, 1 } do
			battenburg(b, Vector3.new(0.05, height, length * 0.78), CFrame.new(side * (width / 2 + 0.03), shape.bodyBottom + shape.bodyHeight * 0.48, 0), if side < 0 then Enum.NormalId.Left else Enum.NormalId.Right, BATTENBURG_BLUE, BATTENBURG_YELLOW)
		end
		local barZ = cabinStart + cabinLength * 0.35
		part(b, "LightBar", Vector3.new(width * 0.62, 0.3, 1), CFrame.new(0, cabinTop + 0.45, barZ), TRIM)
		blueLight(b, "A", Vector3.new(width * 0.29, 0.34, 0.9), CFrame.new(-width * 0.155, cabinTop + 0.62, barZ))
		blueLight(b, "B", Vector3.new(width * 0.29, 0.34, 0.9), CFrame.new(width * 0.155, cabinTop + 0.62, barZ))
		local word = part(b, "PoliceSign", Vector3.new(2.6, 0.5, 0.1), CFrame.new(0, shape.bodyBottom + 1.75, back + 0.06), b.paint)
		word.Transparency = 1
		sign(word, Enum.NormalId.Back, "POLICE", BATTENBURG_BLUE)
	elseif vehicle.livery == "Unmarked" then
		-- Hidden blue lights in the grille and behind the rear window
		blueLight(b, "A", Vector3.new(0.6, 0.25, 0.1), CFrame.new(-0.7, shape.bodyBottom + shape.bodyHeight * 0.55, front - 0.11))
		blueLight(b, "B", Vector3.new(0.6, 0.25, 0.1), CFrame.new(0.7, shape.bodyBottom + shape.bodyHeight * 0.55, front - 0.11))
		blueLight(b, "A", Vector3.new(0.7, 0.18, 0.18), CFrame.new(-0.8, bodyTop + 0.2, rearStart + 0.3))
		blueLight(b, "B", Vector3.new(0.7, 0.18, 0.18), CFrame.new(0.8, bodyTop + 0.2, rearStart + 0.3))
	elseif vehicle.livery == "Taxi" then
		local taxiSign = part(b, "TaxiSign", Vector3.new(1.8, 0.5, 0.7), CFrame.new(0, cabinTop + 0.55, cabinStart + 0.6), Color3.fromRGB(255, 190, 40), Enum.Material.Neon)
		sign(taxiSign, Enum.NormalId.Front, "TAXI", Color3.new(0, 0, 0))
		sign(taxiSign, Enum.NormalId.Back, "TAXI", Color3.new(0, 0, 0))
	end

	local seatY = shape.bodyBottom + 0.35
	local seatZ = cabinStart + 0.9
	local driver = Vector3.new(width / 2 - shape.inset - 1.3, seatY, seatZ)
	return driver, driver * Vector3.new(-1, 1, 1)
end

-- The ambulance: a short bonnet, then a tall box body
local function vanBody(b: Builder, shape: Shape, vehicle: Vehicle, plateText: string): (Vector3, Vector3)
	local length, width = shape.length, shape.width
	local front, back = -length / 2, length / 2
	local bodyTop = shape.bodyBottom + shape.bodyHeight
	local screenStart = front + shape.bonnet
	local boxStart = screenStart + shape.screen
	local boxHeight = 4.8
	local boxLength = back - boxStart

	local body = painted(b, "Body", Vector3.new(width, shape.bodyHeight, length), CFrame.new(0, shape.bodyBottom + shape.bodyHeight / 2, 0))
	body.CanCollide = true
	local box = painted(b, "Box", Vector3.new(width, boxHeight, boxLength), CFrame.new(0, bodyTop + boxHeight / 2, boxStart + boxLength / 2))
	box.CanCollide = true

	glass(b, "Windscreen", Vector3.new(width - 0.5, shape.cabinHeight, shape.screen), CFrame.new(0, bodyTop + shape.cabinHeight / 2, screenStart + shape.screen / 2), "WedgePart")
	painted(b, "CabRoof", Vector3.new(width - 0.5, boxHeight - shape.cabinHeight, shape.screen), CFrame.new(0, bodyTop + shape.cabinHeight + (boxHeight - shape.cabinHeight) / 2, screenStart + shape.screen / 2))
	for _, side in { -1, 1 } do
		glass(b, "SideWindow", Vector3.new(0.1, 2, 2.6), CFrame.new(side * (width / 2 + 0.03), bodyTop + 1.2, boxStart + 1.6))
		painted(b, "Mirror", Vector3.new(0.7, 0.6, 0.3), CFrame.new(side * (width / 2 + 0.35), bodyTop + 0.9, boxStart + 0.2))
	end

	part(b, "Bumper", Vector3.new(width + 0.1, 0.7, 0.4), CFrame.new(0, shape.bodyBottom + 0.35, front - 0.08), TRIM)
	part(b, "Bumper", Vector3.new(width + 0.1, 0.7, 0.4), CFrame.new(0, shape.bodyBottom + 0.35, back + 0.08), TRIM)
	part(b, "Grille", Vector3.new(width * 0.5, 0.8, 0.1), CFrame.new(0, shape.bodyBottom + shape.bodyHeight * 0.55, front - 0.05), TRIM)
	lights(b, width, front, back, shape.bodyBottom + shape.bodyHeight * 0.7)
	plate(b, plateText, shape.bodyBottom + 0.95, front - 0.32, true)
	plate(b, plateText, shape.bodyBottom + 1.1, back + 0.32, false)

	if vehicle.livery == "Ambulance" then
		for _, side in { -1, 1 } do
			battenburg(b, Vector3.new(0.05, 2.4, boxLength * 0.9), CFrame.new(side * (width / 2 + 0.03), bodyTop - 0.2, boxStart + boxLength / 2), if side < 0 then Enum.NormalId.Left else Enum.NormalId.Right, BATTENBURG_GREEN, BATTENBURG_YELLOW)
		end
		local word = part(b, "AmbulanceSign", Vector3.new(width * 0.8, 0.9, 0.1), CFrame.new(0, bodyTop + boxHeight - 0.8, boxStart - 0.06), b.paint)
		word.Transparency = 1
		sign(word, Enum.NormalId.Front, "AMBULANCE", BATTENBURG_GREEN)
		local top = bodyTop + boxHeight + 0.2
		blueLight(b, "A", Vector3.new(1.2, 0.4, 0.6), CFrame.new(-width / 2 + 0.7, top, boxStart + 0.4))
		blueLight(b, "B", Vector3.new(1.2, 0.4, 0.6), CFrame.new(width / 2 - 0.7, top, boxStart + 0.4))
		blueLight(b, "B", Vector3.new(1, 0.4, 0.5), CFrame.new(-width / 2 + 0.6, top, back - 0.4))
		blueLight(b, "A", Vector3.new(1, 0.4, 0.5), CFrame.new(width / 2 - 0.6, top, back - 0.4))
	end

	local driver = Vector3.new(width / 2 - 1.6, shape.bodyBottom + 0.5, boxStart + 1.4)
	return driver, driver * Vector3.new(-1, 1, 1)
end

-- London buses: red, flat-fronted, with one or two decks of windows and the doors on the left (kerb) side
local function busBody(b: Builder, shape: Shape, plateText: string): (Vector3, Vector3)
	local length, width = shape.length, shape.width
	local front, back = -length / 2, length / 2
	local decks = shape.decks or 1
	local panelTop = shape.bodyBottom + shape.bodyHeight
	local deckHeight = shape.cabinHeight
	local between = 1.4

	local lower = painted(b, "Body", Vector3.new(width, shape.bodyHeight, length), CFrame.new(0, shape.bodyBottom + shape.bodyHeight / 2, 0))
	lower.CanCollide = true

	local y = panelTop
	for deck = 1, decks do
		local band = glass(b, "Windows", Vector3.new(width - 0.1, deckHeight, length - 0.6), CFrame.new(0, y + deckHeight / 2, 0.1))
		band.CanCollide = true
		painted(b, "RearPanel", Vector3.new(width, deckHeight, 0.5), CFrame.new(0, y + deckHeight / 2, back - 0.25))
		-- Window pillars along both sides
		local pillars = math.floor((length - 4) / 5)
		for i = 0, pillars do
			local z = front + 2 + i * ((length - 4) / pillars)
			for _, side in { -1, 1 } do
				painted(b, "Pillar", Vector3.new(0.14, deckHeight, 0.55), CFrame.new(side * (width / 2 - 0.02), y + deckHeight / 2, z))
			end
		end
		y += deckHeight
		local isTop = deck == decks
		local bandHeight = if isTop then 0.9 else between
		painted(b, if isTop then "Roof" else "Between", Vector3.new(width, bandHeight, length), CFrame.new(0, y + bandHeight / 2, 0)).CanCollide = true
		if not isTop then
			-- The destination screen sits between the decks on a double-decker
			local screen = part(b, "Destination", Vector3.new(width * 0.72, between * 0.8, 0.12), CFrame.new(0, y + between / 2, front - 0.07), TRIM)
			sign(screen, Enum.NormalId.Front, BUS_ROUTES[math.random(1, #BUS_ROUTES)], Color3.fromRGB(255, 170, 20), TRIM, false)
		end
		y += bandHeight
	end
	if decks == 1 then
		local screen = part(b, "Destination", Vector3.new(width * 0.72, 0.75, 0.12), CFrame.new(0, panelTop + deckHeight + 0.45, front - 0.07), TRIM)
		sign(screen, Enum.NormalId.Front, BUS_ROUTES[math.random(1, #BUS_ROUTES)], Color3.fromRGB(255, 170, 20), TRIM, false)
	end

	-- Doors on the left, at the front and in the middle
	for _, z in { front + 3.5, 1 } do
		glass(b, "Door", Vector3.new(0.12, panelTop + deckHeight - 1.2, 3.4), CFrame.new(-width / 2 - 0.04, (panelTop + deckHeight + 1.2) / 2, z))
	end
	for _, side in { -1, 1 } do
		part(b, "Mirror", Vector3.new(0.3, 1.4, 0.3), CFrame.new(side * (width / 2 + 0.45), panelTop + 1.6, front + 0.4), TRIM)
	end

	part(b, "Bumper", Vector3.new(width + 0.1, 0.8, 0.4), CFrame.new(0, shape.bodyBottom + 0.4, front - 0.1), TRIM)
	part(b, "Bumper", Vector3.new(width + 0.1, 0.8, 0.4), CFrame.new(0, shape.bodyBottom + 0.4, back + 0.1), TRIM)
	lights(b, width, front, back, shape.bodyBottom + 1.3)
	plate(b, plateText, shape.bodyBottom + 0.5, front - 0.34, true)
	plate(b, plateText, shape.bodyBottom + 1.8, back + 0.32, false)

	local driver = Vector3.new(width / 2 - 1.7, shape.bodyBottom + 0.9, front + 2.6)
	return driver, Vector3.new(-1.5, shape.bodyBottom + 0.9, front + 7)
end

local function seat(b: Builder, className: string, at: Vector3): BasePart
	local newSeat = Instance.new(className :: any) :: BasePart
	newSeat.Name = if className == "VehicleSeat" then "DriverSeat" else "PassengerSeat"
	newSeat.Size = Vector3.new(2, 0.4, 2)
	newSeat.CFrame = b.origin * CFrame.new(at)
	newSeat.Transparency = 1
	newSeat.CanCollide = false
	newSeat.CanTouch = false
	newSeat.Massless = true
	newSeat.CustomPhysicalProperties = SLIDING
	if newSeat:IsA("VehicleSeat") then
		newSeat.HeadsUpDisplay = false -- we draw our own speedometer
	end
	newSeat.Parent = b.model
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = b.bodyRoot or b.chassis
	weld.Part1 = newSeat
	weld.Parent = newSeat
	return newSeat
end

-- The model every vehicle starts as, with the numbers the Driving script reads
local function newModel(vehicle: Vehicle, wheelbase: number, wheelRadius: number, reverseSpeed: number): Model
	local model = Instance.new("Model")
	model.Name = vehicle.name
	-- The whole vehicle loads in at once for other players, never half a car
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	model:SetAttribute("VehicleId", vehicle.id)
	model:SetAttribute("ArcadeHandling", true) -- tells the Driving script to drive it
	model:SetAttribute("TopSpeed", vehicle.topSpeed)
	model:SetAttribute("Acceleration", vehicle.acceleration)
	if vehicle.brakes then
		model:SetAttribute("Brakes", vehicle.brakes)
	end
	if vehicle.grip then
		model:SetAttribute("Grip", vehicle.grip)
	end
	-- For the engine sounds (VehicleEffects): big vehicles sound deeper, and some cars pop and bang
	local isBus = vehicle.team == "Bus"
	local isVan = vehicle.style == "van" or vehicle.style == "cab"
	model:SetAttribute("EnginePitch", if isBus then 0.55 elseif isVan then 0.8 else 1)
	model:SetAttribute("EngineVolume", if vehicle.electric then 0 else if isBus then 0.8 else 1)
	if vehicle.pops then
		model:SetAttribute("Pops", true)
	end
	if vehicle.engine then
		model:SetAttribute("EngineSound", vehicle.engine)
	end
	if vehicle.gears then
		model:SetAttribute("Gears", vehicle.gears)
	end
	model:SetAttribute("ReverseSpeed", reverseSpeed)
	model:SetAttribute("Wheelbase", wheelbase)
	model:SetAttribute("WheelRadius", wheelRadius)
	model:SetAttribute("GroundRay", wheelRadius + 2.4)
	return model
end

-- The invisible box the physics engine moves, `height` above the road. Everything you see is welded to it.
local function newChassis(model: Model, size: Vector3, origin: CFrame, height: number): Part
	local chassis = Instance.new("Part")
	chassis.Name = "Chassis"
	chassis.Size = size
	chassis.CFrame = origin * CFrame.new(0, height, 0)
	chassis.Transparency = 1
	chassis.CustomPhysicalProperties = HEAVY_SLIDING
	chassis.RootPriority = 127
	chassis.TopSurface = Enum.SurfaceType.Smooth
	chassis.BottomSurface = Enum.SurfaceType.Smooth
	-- The model's pivot sits on the road under the middle of the car, so PivotTo puts the wheels on the ground
	chassis.PivotOffset = CFrame.new(0, -height, 0)
	chassis.Parent = model
	model.PrimaryPart = chassis
	return chassis
end

local function vectorAttribute(instance: Instance, name: string, default: Vector3): Vector3
	local value = instance:GetAttribute(name)
	return if typeof(value) == "Vector3" then value else default
end

-- A vehicle made from a detailed body (see the top of this file). The body's parts are welded to our chassis,
-- the wheel parts to a hub each so Driving can spin and steer them, and our own seats go where the model's were.
local function buildFromBody(vehicle: Vehicle, template: Model, origin: CFrame, paint: Color3?): (Model, VehicleSeat, { Seat })
	local size = vectorAttribute(template, "BodySize", Vector3.new(7, 5.5, 16))
	local width, height, length = size.X, size.Y, size.Z
	local isBus = vehicle.team == "Bus"
	local radiusValue = template:GetAttribute("WheelRadius")
	local r = if typeof(radiusValue) == "number" then radiusValue else 1.3

	-- Where the middle of each wheel is
	local track = width / 2 - 1
	local hubs: { [string]: Vector3 } = {
		FL = vectorAttribute(template, "WheelFL", Vector3.new(-track, r, -length * 0.32)),
		FR = vectorAttribute(template, "WheelFR", Vector3.new(track, r, -length * 0.32)),
		RL = vectorAttribute(template, "WheelRL", Vector3.new(-track, r, length * 0.3)),
		RR = vectorAttribute(template, "WheelRR", Vector3.new(track, r, length * 0.3)),
	}
	local wheelbase = (hubs.RL.Z + hubs.RR.Z) / 2 - (hubs.FL.Z + hubs.FR.Z) / 2

	local model = newModel(vehicle, wheelbase, r, if isBus then 16 else 24)
	local chassis = newChassis(model, Vector3.new(width * 0.8, 1.6, length - 1), origin, r + 0.8)
	local b: Builder = { model = model, origin = origin, chassis = chassis, paint = paint or DEFAULT_PAINT }

	-- An invisible box filling the rest of the body, so nobody can walk into the car or stand on the chassis
	local hullBottom = r + 1.6
	local hullHeight = height * 0.9 - hullBottom
	if hullHeight > 0.5 then
		local hull = part(b, "Hull", Vector3.new(width * 0.8, hullHeight, length - 1.5), CFrame.new(0, hullBottom + hullHeight / 2, 0), TYRE)
		hull.Transparency = 1
		hull.CanCollide = true
	end

	-- A hub for each wheel, jointed to the chassis, plus an invisible ball that touches the road
	local hubParts: { [string]: BasePart } = {}
	for corner, at in hubs do
		local hub = Instance.new("Part")
		hub.Name = "WheelHub"
		hub.Size = Vector3.one * 0.4
		hub.CFrame = origin * CFrame.new(at)
		hub.Transparency = 1
		hub.CanCollide = false
		hub.CanTouch = false
		hub.CanQuery = false
		hub.Massless = true
		hub.Parent = model
		hubParts[corner] = hub

		local joint = Instance.new("Motor6D")
		joint.Name = "WheelJoint"
		joint.Part0 = chassis
		joint.Part1 = hub
		joint.C0 = chassis.CFrame:ToObjectSpace(hub.CFrame)
		joint:SetAttribute("Steers", corner:sub(1, 1) == "F")
		joint.Parent = chassis

		local contact = part(b, "TyreContact", Vector3.one * r * 2, CFrame.new(at.X, r, at.Z), TYRE)
		contact.Shape = Enum.PartType.Ball
		contact.Transparency = 1
		contact.CanCollide = true
	end

	-- The body hangs off the chassis on a joint, so it can lean: VehicleEffects on every device squats it
	-- when you accelerate, dips the nose when you brake and rolls it in corners. The wheels stay on the chassis.
	-- The joint is in BodyRoot, not the chassis: the Driving script treats every joint in the chassis as a wheel.
	local bodyRoot = Instance.new("Part")
	bodyRoot.Name = "BodyRoot"
	bodyRoot.Size = Vector3.one * 0.4
	bodyRoot.CFrame = origin * CFrame.new(0, r, 0)
	bodyRoot.Transparency = 1
	bodyRoot.CanCollide = false
	bodyRoot.CanTouch = false
	bodyRoot.CanQuery = false
	bodyRoot.Massless = true
	bodyRoot.Parent = model
	local bodyJoint = Instance.new("Motor6D")
	bodyJoint.Name = "BodyJoint"
	bodyJoint.Part0 = chassis
	bodyJoint.Part1 = bodyRoot
	bodyJoint.C0 = chassis.CFrame:ToObjectSpace(bodyRoot.CFrame)
	bodyJoint.Parent = bodyRoot
	b.bodyRoot = bodyRoot

	-- Where the exhausts are, for the pops and flames
	local exhaust = vehicle.exhaust or Vector3.new(width * 0.3, r * 0.55, length / 2 - 0.3)
	for _, side in { -1, 1 } do
		local tip = Instance.new("Attachment")
		tip.Name = if side < 0 then "ExhaustL" else "ExhaustR"
		tip.CFrame = CFrame.new(exhaust.X * side, exhaust.Y - r, exhaust.Z)
		tip.Parent = bodyRoot
	end

	-- The body itself: everything is welded on and weighs nothing, so only the chassis matters to the physics
	local isEmergency = vehicle.team == "Emergency"
	local hasBlue, hasHeadBeam = false, false
	local body = template:Clone()
	body:PivotTo(origin)
	for _, item in body:GetChildren() do
		if item:IsA("BasePart") then
			item.Anchored = false
			item.CanCollide = false
			item.CanTouch = false
			item.CanQuery = false
			item.Massless = true

			local corner = item:GetAttribute("Wheel")
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = if typeof(corner) == "string" and hubParts[corner] then hubParts[corner] else bodyRoot
			weld.Part1 = item
			weld.Parent = item

			if item:GetAttribute("Paint") then
				item:SetAttribute("BaseColour", item.Color) -- so the menu can put the original colour back
				if paint then
					item.Color = paint
				end
			end

			-- No light shadows: they update slower than a car moves, so the beams would seem to lag behind it
			for _, light in item:GetChildren() do
				if light:IsA("Light") then
					light.Shadows = false
				end
			end

			local role = item:GetAttribute("LightRole")
			if role == "BlueA" or role == "BlueB" then
				if isEmergency then
					hasBlue = true
				else
					-- Only emergency vehicles flash: on anything else these are just coloured trim, so keep their look
					local onColour = item:GetAttribute("OnColor")
					local onTransparency = item:GetAttribute("OnTransparency")
					item.Material = Enum.Material.Neon
					item.Color = if typeof(onColour) == "Color3" then onColour else item.Color
					item.Transparency = if typeof(onTransparency) == "number" then onTransparency else item.Transparency
					item:SetAttribute("LightRole", nil)
				end
			elseif role == "Head" and item:FindFirstChildWhichIsA("SpotLight") then
				hasHeadBeam = true
			end
			item.Parent = model
		end
	end
	body:Destroy()
	model:SetAttribute("HasBlueLights", hasBlue)

	-- A glow under the car: a thin strip of light just above the road, with a light that lights the ground
	if vehicle.underglow then
		local glow = Instance.new("Part")
		glow.Name = "Underglow"
		glow.Size = Vector3.new(width * 0.7, 0.1, length * 0.75)
		glow.CFrame = origin * CFrame.new(0, 0.35, 0)
		glow.Color = vehicle.underglow
		glow.Material = Enum.Material.Neon
		glow.Transparency = 0.35
		glow.CanCollide = false
		glow.CanTouch = false
		glow.CanQuery = false
		glow.Massless = true
		glow.CastShadow = false
		glow.Parent = model
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = chassis
		weld.Part1 = glow
		weld.Parent = glow
		local light = Instance.new("SurfaceLight")
		light.Face = Enum.NormalId.Bottom
		light.Color = vehicle.underglow
		light.Brightness = 4
		light.Range = 9
		light.Angle = 150
		light.Parent = glow
	end

	-- Headlight beams, for bodies whose headlights don't light up the road
	if not hasHeadBeam then
		for _, side in { -1, 1 } do
			local holder = part(b, "HeadBeam", Vector3.new(0.4, 0.4, 0.2), CFrame.new(side * width * 0.3, r + 0.9, -length / 2 + 0.3), HEADLIGHT)
			holder.Transparency = 1
			local beam = Instance.new("SpotLight")
			beam.Face = Enum.NormalId.Front
			beam.Range = 45
			beam.Angle = 70
			beam.Brightness = 4
			beam.Color = Color3.fromRGB(255, 248, 230)
			beam.Shadows = false
			beam.Enabled = false
			beam.Parent = holder
			tagLamp(holder, "Beam", HEADLIGHT, 1)
		end
	end

	-- Seats where the model had them. The front passenger seat comes first.
	local driverValue = template:GetAttribute("DriverSeat")
	local driverAt = if typeof(driverValue) == "CFrame"
		then driverValue.Position
		elseif isBus then Vector3.new(width * 0.22, r + 2.6, -length / 2 + 5)
		else Vector3.new(width * 0.2, r + 0.2, -length * 0.03)
	-- Lowered a bit on low cars, so the top of your head doesn't poke out through the roof
	local drop = Vector3.new(0, vehicle.seatDrop or 0, 0)
	driverAt -= drop
	local spots: { Vector3 } = {}
	local countValue = template:GetAttribute("SeatCount")
	for i = 1, if typeof(countValue) == "number" then countValue else 0 do
		local value = template:GetAttribute("Seat" .. i)
		if typeof(value) == "CFrame" then
			table.insert(spots, value.Position - drop)
		end
	end
	if #spots == 0 then
		table.insert(spots, if isBus then driverAt + Vector3.new(-width * 0.4, 0, 6) else driverAt * Vector3.new(-1, 1, 1))
	end
	table.sort(spots, function(first, second)
		return (first - driverAt).Magnitude < (second - driverAt).Magnitude
	end)

	local driverSeat = seat(b, "VehicleSeat", driverAt) :: any
	local passengers: { Seat } = {}
	for i = 1, math.min(#spots, MAX_PASSENGERS) do
		table.insert(passengers, seat(b, "Seat", spots[i]) :: any)
	end
	return model, driverSeat, passengers
end

-- A vehicle built out of parts, for vehicles with no detailed body
local function buildFromParts(vehicle: Vehicle, origin: CFrame, paint: Color3?, plateText: string): (Model, VehicleSeat, { Seat })
	local shape = SHAPES[vehicle.style] or SHAPES.saloon
	local model = newModel(vehicle, shape.wheelbase, shape.wheelRadius, shape.reverseSpeed or 24)
	model:SetAttribute("HasBlueLights", vehicle.livery == "Police" or vehicle.livery == "Ambulance" or vehicle.livery == "Unmarked")
	local chassis = newChassis(model, Vector3.new(shape.width - 0.6, 1.6, shape.length - 1.2), origin, shape.wheelRadius + 0.8)

	local colour = paint or LIVERY_PAINT[vehicle.livery or ""] or DEFAULT_PAINT
	local b: Builder = { model = model, origin = origin, chassis = chassis, paint = colour }
	local driverAt, passengerAt
	if shape.kind == "bus" then
		driverAt, passengerAt = busBody(b, shape, plateText)
	elseif shape.kind == "van" then
		driverAt, passengerAt = vanBody(b, shape, vehicle, plateText)
	else
		driverAt, passengerAt = carBody(b, shape, vehicle, plateText)
	end
	wheels(b, shape)

	local driverSeat = seat(b, "VehicleSeat", driverAt) :: any
	local passengerSeat = seat(b, "Seat", passengerAt) :: any
	return model, driverSeat, { passengerSeat }
end

-- Builds a vehicle standing on the road at `origin`, facing the way `origin` faces.
-- `paint` is nil to keep a detailed body's own colours.
-- Returns the model, its driver's seat and its passenger seats (front passenger first).
function CarBuilder.build(vehicle: Vehicle, origin: CFrame, paint: Color3?, plateText: string): (Model, VehicleSeat, { Seat })
	local bodies = ServerStorage:FindFirstChild("VehicleBodies")
	local template = bodies and bodies:FindFirstChild(vehicle.id)
	if template and template:IsA("Model") then
		return buildFromBody(vehicle, template, origin, paint)
	end
	return buildFromParts(vehicle, origin, paint, plateText)
end

return CarBuilder
