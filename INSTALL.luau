-- London Simulator installer
-- Paste ALL of this into Roblox Studio's Command Bar and press Enter.
-- It creates every folder and script in the right place, replacing old copies.
-- Made by tools/build_installer.py from the files in src/, so don't edit this file by hand.

local function folder(parent: Instance, name: string): Instance
	local existing = parent:FindFirstChild(name)
	if existing then
		return existing
	end
	local newFolder = Instance.new("Folder")
	newFolder.Name = name
	newFolder.Parent = parent
	return newFolder
end

-- Names of the scripts this installer puts in each folder, so old ones that were removed or renamed can go
local installed: { [Instance]: { [string]: boolean } } = {}

local function put(parent: Instance, className: string, name: string, source: string)
	local old = parent:FindFirstChild(name)
	if old then
		old:Destroy()
	end
	local newScript: any = Instance.new(className)
	newScript.Name = name
	newScript.Source = source
	newScript.Parent = parent
	installed[parent] = installed[parent] or {}
	installed[parent][name] = true
end

-- Deletes scripts in our folders that aren't in the repo any more (e.g. a script that was renamed)
local function removeOldScripts(parent: Instance)
	local keep = installed[parent] or {}
	for _, child in parent:GetChildren() do
		if child:IsA("LuaSourceContainer") and not keep[child.Name] then
			print("Removed old script " .. child:GetFullName())
			child:Destroy()
		end
	end
end

local folder1 = game:GetService("ReplicatedStorage")
local folder2 = folder(folder1, "Shared")
put(folder2, "ModuleScript", "Config", [[
-- Game-wide settings. Change the numbers here to rebalance the game.

local Config = {}

Config.CurrencySymbol = "£"

-- Money a brand new player starts with
Config.StartingCash = 500

-- Placeholder income until jobs exist: everyone gets paid on a timer.
-- Set the interval to 10 while testing so you don't have to wait.
Config.PaychequeAmount = 100
Config.PaychequeIntervalSeconds = 300

-- How often everyone's data is saved, on top of saving when they leave
Config.AutosaveIntervalSeconds = 120

-- Changing this name starts everyone from scratch (e.g. to wipe test data before launch)
Config.DataStoreName = "PlayerData_v1"

-- Builds a small grid of streets to drive around until the real London map exists
Config.BuildTestTown = true

-- 1 stud is about 0.28 metres, so 1 stud per second is about 0.626 mph
Config.MphPerStudPerSecond = 0.626

-- How the car handles. Speeds are in studs per second (multiply by 0.626 for mph).
Config.Car = {
	TopSpeed = 112, -- about 70 mph
	ReverseSpeed = 24, -- about 15 mph
	Acceleration = 14, -- 0-60 mph in about 7 seconds
	BrakeDeceleration = 45,
	CoastDeceleration = 6, -- slowing down when you let go of the accelerator
	SideGrip = 120, -- how quickly sideways sliding is cancelled out
	CorneringGrip = 50, -- limits how sharply you can turn at speed
	MaxTurnRate = 1.4, -- radians per second, at low speed
	SteeringLockDegrees = 35,
	SteeringResponse = 5, -- how quickly the wheel turns from straight to full lock (per second)
	Wheelbase = 8.8, -- distance between front and back wheels
	WheelRadius = 1.3,
	HandbrakeDeceleration = 70, -- Space while driving
	SpawnCooldownSeconds = 3,
	-- New cars are "ghosts" other cars drive through for this long, so nobody gets rammed at the spawn
	GhostSeconds = 5,
}

-- The teams you pick from the menu, in the order they're shown
Config.Teams = {
	{
		name = "Car",
		icon = "🚗",
		colour = Color3.fromRGB(90, 140, 230),
		description = "Drive your own car, race your mates and run a taxi",
		showcase = "kestrel_saloon", -- the vehicle shown on the team's card
	},
	{
		name = "Bus",
		icon = "🚌",
		colour = Color3.fromRGB(225, 60, 55),
		description = "Drive London's red buses and pick up passengers",
		showcase = "capital_decker",
	},
	{
		name = "Emergency",
		icon = "🚓",
		colour = Color3.fromRGB(245, 195, 50),
		description = "Police and ambulance: answer calls across London",
		showcase = "police_kestrel",
	},
}

return Config
]])
put(folder2, "ModuleScript", "Format", [[
-- Turns numbers into text for the UI.

local Config = require(script.Parent.Config)

local Format = {}

-- 1250 -> "£1,250"
function Format.money(amount: number): string
	local digits = tostring(math.floor(math.abs(amount)))
	local withCommas = digits:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
	local sign = if amount < 0 then "-" else ""
	return sign .. Config.CurrencySymbol .. withCommas
end

return Format
]])
put(folder2, "ModuleScript", "Vehicles", [[
-- Every vehicle in the game: its name, which team drives it, what it costs and how fast it goes.
-- The menu's vehicle picker shows these, and CarBuilder (on the server) builds the body for each "style".
-- Speeds are in studs per second (multiply by 0.626 for mph). Prices are in pounds.
-- No real car makers: every name here is made up.

export type Vehicle = {
	id: string,
	name: string,
	team: string,
	price: number, -- 0 means everyone gets it free
	style: string, -- body shape, see CarBuilder
	livery: string?, -- "Police", "Ambulance", "Taxi" or "Unmarked"
	electric: boolean?,
	paint: number, -- default colour, from Vehicles.Paints
	fixedPaint: boolean?, -- true for police, ambulances and buses, which can't be repainted
	topSpeed: number,
	acceleration: number,
}

local Vehicles = {}

-- Colours you can pick in Customise
Vehicles.Paints = {
	{ name = "Arctic White", colour = Color3.fromRGB(236, 237, 239) },
	{ name = "Jet Black", colour = Color3.fromRGB(22, 23, 26) },
	{ name = "Silver", colour = Color3.fromRGB(170, 174, 180) },
	{ name = "Gunmetal", colour = Color3.fromRGB(80, 84, 92) },
	{ name = "Pillar Box Red", colour = Color3.fromRGB(200, 20, 30) },
	{ name = "Racing Green", colour = Color3.fromRGB(10, 70, 40) },
	{ name = "Royal Blue", colour = Color3.fromRGB(35, 75, 170) },
	{ name = "Navy", colour = Color3.fromRGB(24, 32, 64) },
	{ name = "Sky Blue", colour = Color3.fromRGB(130, 175, 215) },
	{ name = "Sunshine Yellow", colour = Color3.fromRGB(245, 200, 40) },
	{ name = "Tangerine", colour = Color3.fromRGB(225, 110, 30) },
	{ name = "Plum", colour = Color3.fromRGB(85, 35, 80) },
	{ name = "Bronze", colour = Color3.fromRGB(120, 85, 55) },
	{ name = "Teal", colour = Color3.fromRGB(30, 130, 130) },
	{ name = "Bus Red", colour = Color3.fromRGB(215, 25, 32) },
	{ name = "Ambulance Yellow", colour = Color3.fromRGB(250, 220, 30) },
}

local WHITE, BLACK, SILVER, GUNMETAL, RED, GREEN, BLUE, NAVY = 1, 2, 3, 4, 5, 6, 7, 8
local BUS_RED, AMBULANCE_YELLOW = 15, 16

Vehicles.List = {
	-- Car team
	{ id = "ashby_hatch", name = "Ashby Hatch", team = "Car", price = 0, style = "hatch", paint = RED, topSpeed = 105, acceleration = 13 },
	{ id = "kestrel_saloon", name = "Kestrel Saloon", team = "Car", price = 0, style = "saloon", paint = SILVER, topSpeed = 112, acceleration = 14 },
	{ id = "kestrel_estate", name = "Kestrel Estate", team = "Car", price = 1500, style = "estate", paint = NAVY, topSpeed = 112, acceleration = 14 },
	{ id = "hackney_cab", name = "Hackney Cab", team = "Car", price = 3000, style = "cab", livery = "Taxi", electric = true, paint = BLACK, topSpeed = 100, acceleration = 15 },
	{ id = "montrose_suv", name = "Montrose SUV", team = "Car", price = 6000, style = "suv", paint = GUNMETAL, topSpeed = 115, acceleration = 15 },
	{ id = "regent_gt", name = "Regent GT", team = "Car", price = 12000, style = "coupe", paint = GREEN, topSpeed = 140, acceleration = 20 },
	-- Bus team (London buses are always red)
	{ id = "metro_single", name = "Metro Single", team = "Bus", price = 0, style = "bus_single", paint = BUS_RED, fixedPaint = true, topSpeed = 75, acceleration = 9 },
	{ id = "capital_decker", name = "Capital Decker", team = "Bus", price = 0, style = "bus_double", paint = BUS_RED, fixedPaint = true, topSpeed = 70, acceleration = 8 },
	{ id = "capital_decker_e", name = "Capital Decker E", team = "Bus", price = 8000, style = "bus_double", electric = true, paint = BUS_RED, fixedPaint = true, topSpeed = 75, acceleration = 11 },
	-- Emergency team
	{ id = "police_kestrel", name = "Kestrel Response", team = "Emergency", price = 0, style = "saloon", livery = "Police", paint = WHITE, fixedPaint = true, topSpeed = 125, acceleration = 17 },
	{ id = "ambulance", name = "Paramedic Van", team = "Emergency", price = 0, style = "van", livery = "Ambulance", paint = AMBULANCE_YELLOW, fixedPaint = true, topSpeed = 100, acceleration = 12 },
	{ id = "police_unmarked", name = "Kestrel Unmarked", team = "Emergency", price = 3500, style = "saloon", livery = "Unmarked", paint = BLUE, topSpeed = 130, acceleration = 18 },
	{ id = "police_montrose", name = "Montrose Response", team = "Emergency", price = 5000, style = "suv", livery = "Police", paint = WHITE, fixedPaint = true, topSpeed = 120, acceleration = 16 },
} :: { Vehicle }

Vehicles.ById = {} :: { [string]: Vehicle }
for _, vehicle in Vehicles.List do
	Vehicles.ById[vehicle.id] = vehicle
end

-- The vehicles a team can drive, in menu order
function Vehicles.forTeam(team: string): { Vehicle }
	local list = {}
	for _, vehicle in Vehicles.List do
		if vehicle.team == team then
			table.insert(list, vehicle)
		end
	end
	return list
end

-- The colour a vehicle is painted, given the paint the player picked (or nil for its default)
function Vehicles.paintColour(vehicle: Vehicle, picked: number?): Color3
	local index = if picked and not vehicle.fixedPaint and Vehicles.Paints[picked] then picked else vehicle.paint
	return Vehicles.Paints[index].colour
end

return Vehicles
]])
removeOldScripts(folder2)
local folder3 = game:GetService("ServerScriptService")
local folder4 = folder(folder3, "Server")
put(folder4, "ModuleScript", "CarBuilder", [[
-- Builds vehicles out of parts: body, windows, wheels, lights, number plates, seats and liveries.
-- They're stand-ins until proper 3D models are bought, but each one is shaped like the real thing:
-- hatchbacks, saloons, a black cab, red buses, Battenburg police cars and a yellow ambulance.
-- Cars.luau uses CarBuilder.build both for drivable vehicles and for the display models in the menu.
-- Measurements are in studs. The front of a vehicle is -Z and the driver sits on the right (+X), like in the UK.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

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

		local taillight = part(b, "Taillight", Vector3.new(1.3, 0.45, 0.12), CFrame.new(side * (width / 2 - 0.95), y, back + 0.06), TAILLIGHT, Enum.Material.Neon)
		taillight.Transparency = 0.15

		part(b, "Indicator" .. "F" .. letter, Vector3.new(0.4, 0.35, 0.12), CFrame.new(side * (width / 2 - 0.12), y, front - 0.06), INDICATOR_OFF)
		part(b, "Indicator" .. "R" .. letter, Vector3.new(0.4, 0.35, 0.12), CFrame.new(side * (width / 2 - 0.12), y, back + 0.06), INDICATOR_OFF)
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
	weld.Part0 = b.chassis
	weld.Part1 = newSeat
	weld.Parent = newSeat
	return newSeat
end

-- Builds a vehicle standing on the road at `origin`, facing the way `origin` faces.
-- Returns the model, its driver's seat and its passenger seat.
function CarBuilder.build(vehicle: Vehicle, origin: CFrame, paint: Color3, plateText: string): (Model, VehicleSeat, Seat)
	local shape = SHAPES[vehicle.style] or SHAPES.saloon

	local model = Instance.new("Model")
	model.Name = vehicle.name
	model:SetAttribute("VehicleId", vehicle.id)
	model:SetAttribute("ArcadeHandling", true) -- tells the Driving script to drive it
	model:SetAttribute("TopSpeed", vehicle.topSpeed)
	model:SetAttribute("Acceleration", vehicle.acceleration)
	model:SetAttribute("ReverseSpeed", shape.reverseSpeed or 24)
	model:SetAttribute("Wheelbase", shape.wheelbase)
	model:SetAttribute("WheelRadius", shape.wheelRadius)
	model:SetAttribute("GroundRay", shape.wheelRadius + 2.4)
	model:SetAttribute("HasBlueLights", vehicle.livery == "Police" or vehicle.livery == "Ambulance" or vehicle.livery == "Unmarked")

	-- The invisible box the physics engine moves. Everything you see is welded to it.
	local chassis = Instance.new("Part")
	chassis.Name = "Chassis"
	chassis.Size = Vector3.new(shape.width - 0.6, 1.6, shape.length - 1.2)
	chassis.CFrame = origin * CFrame.new(0, shape.wheelRadius + 0.8, 0)
	chassis.Transparency = 1
	chassis.CustomPhysicalProperties = HEAVY_SLIDING
	chassis.RootPriority = 127
	chassis.TopSurface = Enum.SurfaceType.Smooth
	chassis.BottomSurface = Enum.SurfaceType.Smooth
	chassis.Parent = model
	model.PrimaryPart = chassis

	local b: Builder = { model = model, origin = origin, chassis = chassis, paint = paint }
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
	return model, driverSeat, passengerSeat
end

return CarBuilder
]])
put(folder4, "ModuleScript", "Cars", [[
-- Spawns and looks after players' vehicles: one each, built by CarBuilder.
-- The driving itself happens in the Driving LocalScript, on the driver's own device, so it feels instant.
-- Vehicles appear at your team's depot (a model in Workspace → Depots with "Spawn" parts in it).

local Players = game:GetService("Players")
local PhysicsService = game:GetService("PhysicsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Vehicles = require(ReplicatedStorage.Shared.Vehicles)
local CarBuilder = require(script.Parent.CarBuilder)
local PlayerData = require(script.Parent.PlayerData)
local Remotes = require(script.Parent.Remotes)

local CAR = Config.Car

-- Car parts slide with no friction: the Driving script controls speed and grip itself
local SLIDING = PhysicalProperties.new(0.7, 0, 0, 100, 100)
-- Parked cars grip the road hard so they don't get shoved around, like a handbrake
local PARKED = PhysicalProperties.new(0.7, 2, 0, 100, 100)

-- Collision groups: "Ghost" vehicles drive straight through other vehicles for a few seconds after spawning
local CARS_GROUP = "Cars"
local GHOST_GROUP = "GhostCars"

local PLATE_LETTERS = "ABCDEFGHJKLMNOPRSTUVWXY" -- UK plates skip I, Q and Z
local PLATE_AGES = { "24", "74", "25", "75", "26", "76" }

local Cars = {}

local carsFolder: Folder
local carsByPlayer: { [Player]: Model } = {}
local lastSpawnTime: { [Player]: number } = {}
local random = Random.new()

local function randomLetter(): string
	local i = random:NextInteger(1, #PLATE_LETTERS)
	return PLATE_LETTERS:sub(i, i)
end

-- London-style number plate, e.g. "LK74 XRB"
local function randomPlate(): string
	local age = PLATE_AGES[random:NextInteger(1, #PLATE_AGES)]
	return "L" .. randomLetter() .. age .. " " .. randomLetter() .. randomLetter() .. randomLetter()
end

local function getHumanoid(player: Player): Humanoid?
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health > 0 then
		return humanoid
	end
	return nil
end

local function setCollisionGroup(car: Model, group: string)
	for _, descendant in car:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.CollisionGroup = group
		end
	end
end

local function setParked(car: Model, parked: boolean)
	for _, child in car:GetChildren() do
		if child.Name == "TyreContact" and child:IsA("BasePart") then
			child.CustomPhysicalProperties = if parked then PARKED else SLIDING
		end
	end
end

local function addPrompt(seat: BasePart, actionText: string, objectText: string, key: Enum.KeyCode, offset: number): ProximityPrompt
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = actionText
	prompt.ObjectText = objectText
	prompt.KeyboardKeyCode = key
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	-- The seats are side by side, so stack the two prompts instead of drawing them on top of each other
	prompt.UIOffset = Vector2.new(0, offset)
	prompt.Parent = seat
	return prompt
end

-- Seats, prompts and network ownership for a freshly built car
local function wireUp(car: Model, owner: Player, driverSeat: VehicleSeat, passengerSeat: Seat)
	local chassis = car.PrimaryPart :: BasePart
	local drivePrompt = addPrompt(driverSeat, "Drive", owner.DisplayName .. "'s " .. car.Name, Enum.KeyCode.E, -42)
	local passengerPrompt = addPrompt(passengerSeat, "Get in", owner.DisplayName .. "'s " .. car.Name, Enum.KeyCode.F, 42)

	drivePrompt.Triggered:Connect(function(player)
		local humanoid = getHumanoid(player)
		if player == owner and humanoid and not humanoid.SeatPart and not driverSeat.Occupant then
			driverSeat:Sit(humanoid)
		end
	end)

	passengerPrompt.Triggered:Connect(function(player)
		local humanoid = getHumanoid(player)
		if humanoid and not humanoid.SeatPart and not passengerSeat.Occupant then
			passengerSeat:Sit(humanoid)
		end
	end)

	driverSeat:GetPropertyChangedSignal("Occupant"):Connect(function()
		if not chassis:IsDescendantOf(Workspace) then
			return -- the car is being removed
		end
		local humanoid = driverSeat.Occupant
		local driver = humanoid and Players:GetPlayerFromCharacter(humanoid.Parent)
		if humanoid and driver ~= owner then
			-- Only the owner can drive their car
			local seatWeld = driverSeat:FindFirstChild("SeatWeld")
			if seatWeld then
				seatWeld:Destroy()
			end
			return
		end
		drivePrompt.Enabled = humanoid == nil
		setParked(car, driver == nil)
		if driver == nil then
			car:SetAttribute("Indicator", nil) -- switch indicators off when you get out
		end
		-- The driver's device runs the car's physics while they drive, so there's no lag
		chassis:SetNetworkOwner(driver)
	end)

	passengerSeat:GetPropertyChangedSignal("Occupant"):Connect(function()
		passengerPrompt.Enabled = passengerSeat.Occupant == nil
	end)
end

-- A free parking space at the team's depot, or next to the player if there's no depot in the map
local function findSpawn(player: Player, root: BasePart): CFrame
	local depots = Workspace:FindFirstChild("Depots")
	local team = player.Team
	local depot = depots and team and depots:FindFirstChild(team.Name)
	if depot then
		local spots = {}
		for _, child in depot:GetChildren() do
			if child.Name == "Spawn" and child:IsA("BasePart") then
				table.insert(spots, child)
			end
		end
		for _, spot in spots do
			local taken = false
			for _, car in carsFolder:GetChildren() do
				local chassis = (car :: Model).PrimaryPart
				if chassis and (chassis.Position - spot.Position).Magnitude < 14 then
					taken = true
					break
				end
			end
			if not taken then
				return spot.CFrame
			end
		end
		if #spots > 0 then
			return spots[random:NextInteger(1, #spots)].CFrame
		end
	end

	-- No depot: put the car right where they're standing, facing the way they face
	local facing = root.CFrame.LookVector * Vector3.new(1, 0, 1)
	if facing.Magnitude < 0.01 then
		facing = Vector3.new(0, 0, -1)
	end
	local ground = root.Position - Vector3.new(0, 3, 0)
	return CFrame.lookAt(ground, ground + facing.Unit)
end

function Cars.despawn(player: Player)
	local car = carsByPlayer[player]
	if car then
		car:Destroy()
	end
	carsByPlayer[player] = nil
end

local function spawnVehicle(player: Player, vehicleId: unknown)
	if typeof(vehicleId) ~= "string" then
		return
	end
	local vehicle = Vehicles.ById[vehicleId]
	if not vehicle then
		return
	end
	if not player.Team or player.Team.Name ~= vehicle.team then
		Remotes.notify(player, "Wrong team", `Join the {vehicle.team} team to drive the {vehicle.name}.`, "Red")
		return
	end
	if not PlayerData.owns(player, vehicle.id) then
		Remotes.notify(player, "Not yours yet", `Buy the {vehicle.name} first.`, "Red")
		return
	end

	local now = os.clock()
	if now - (lastSpawnTime[player] or -math.huge) < CAR.SpawnCooldownSeconds then
		return
	end
	local humanoid = getHumanoid(player)
	local root = humanoid and humanoid.RootPart
	if not humanoid or not root then
		return
	end
	lastSpawnTime[player] = now

	-- Get out of any seat first, then remove their old car
	humanoid.Sit = false
	Cars.despawn(player)

	local origin = findSpawn(player, root)
	local paint = Vehicles.paintColour(vehicle, PlayerData.paintOf(player, vehicle.id))
	local car, driverSeat, passengerSeat = CarBuilder.build(vehicle, origin, paint, randomPlate())
	car.Name = vehicle.name
	car:SetAttribute("OwnerUserId", player.UserId)
	wireUp(car, player, driverSeat, passengerSeat)
	setParked(car, true)

	-- Start as a ghost so nobody can ram you while you get going
	setCollisionGroup(car, GHOST_GROUP)
	car.Parent = carsFolder
	carsByPlayer[player] = car
	driverSeat:Sit(humanoid)

	task.delay(Config.Car.GhostSeconds, function()
		if car.Parent then
			setCollisionGroup(car, CARS_GROUP)
			Remotes.notify(player, "Collisions on", "Other players can now hit your vehicle. Drive carefully!", "Yellow")
		end
	end)
end

-- Lights, indicators and blue lights. The driver asks, the server sets an attribute, and VehicleLights
-- on every player's device makes the bulbs flash.
local function control(player: Player, action: unknown)
	local car = carsByPlayer[player]
	local humanoid = getHumanoid(player)
	if not car or not humanoid or typeof(action) ~= "string" then
		return
	end
	local driverSeat = car:FindFirstChild("DriverSeat") :: VehicleSeat?
	if not driverSeat or driverSeat.Occupant ~= humanoid then
		return -- only the driver can work the switches
	end

	if action == "Lights" then
		car:SetAttribute("Headlights", not car:GetAttribute("Headlights"))
	elseif action == "Left" or action == "Right" or action == "Hazard" then
		car:SetAttribute("Indicator", if car:GetAttribute("Indicator") == action then nil else action)
	elseif action == "BlueLights" and car:GetAttribute("HasBlueLights") then
		car:SetAttribute("BlueLights", not car:GetAttribute("BlueLights"))
	end
end

-- Display copies of every vehicle for the menu: ReplicatedStorage → VehicleModels → <vehicle id>.
-- They're anchored, can't be sat in and can't be bumped into.
local function buildDisplayModels()
	local folder = Instance.new("Folder")
	folder.Name = "VehicleModels"
	for _, vehicle in Vehicles.List do
		local model = CarBuilder.build(vehicle, CFrame.new(), Vehicles.paintColour(vehicle, nil), "LDN 5IM")
		model.Name = vehicle.id
		for _, descendant in model:GetDescendants() do
			if descendant:IsA("BasePart") then
				descendant.Anchored = true
				descendant.CanCollide = false
				descendant.CanQuery = false
			end
			if descendant:IsA("Seat") then
				descendant.Disabled = true
			elseif descendant:IsA("VehicleSeat") then
				descendant.Disabled = true
			end
		end
		model.Parent = folder
	end
	folder.Parent = ReplicatedStorage
end

function Cars.start()
	PhysicsService:RegisterCollisionGroup(CARS_GROUP)
	PhysicsService:RegisterCollisionGroup(GHOST_GROUP)
	PhysicsService:CollisionGroupSetCollidable(GHOST_GROUP, CARS_GROUP, false)
	PhysicsService:CollisionGroupSetCollidable(GHOST_GROUP, GHOST_GROUP, false)

	carsFolder = Instance.new("Folder")
	carsFolder.Name = "Cars"
	carsFolder.Parent = Workspace

	buildDisplayModels()

	Remotes.event("SpawnVehicle").OnServerEvent:Connect(spawnVehicle)
	Remotes.event("CarControl").OnServerEvent:Connect(control)
	Remotes.event("ReturnToMenu").OnServerEvent:Connect(function(player)
		local humanoid = getHumanoid(player)
		if humanoid then
			humanoid.Sit = false
		end
		Cars.despawn(player)
	end)
	-- "Spawn" on the main menu: walk around instead of driving, starting at a spawn point
	Remotes.event("SpawnOnFoot").OnServerEvent:Connect(function(player)
		Cars.despawn(player)
		player:LoadCharacterAsync()
	end)

	Players.PlayerRemoving:Connect(function(player)
		Cars.despawn(player)
		lastSpawnTime[player] = nil
	end)
end

return Cars
]])
put(folder4, "ModuleScript", "Garage", [[
-- Teams, buying vehicles and picking paint colours: everything the menu asks the server to do
-- before you drive off.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Teams = game:GetService("Teams")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Vehicles = require(ReplicatedStorage.Shared.Vehicles)
local Cars = require(script.Parent.Cars)
local PlayerData = require(script.Parent.PlayerData)
local Remotes = require(script.Parent.Remotes)

local Garage = {}

local function makeTeams()
	for _, info in Config.Teams do
		local team = Teams:FindFirstChild(info.name) :: Team?
		if not team then
			local newTeam = Instance.new("Team")
			newTeam.Name = info.name
			newTeam.Parent = Teams
			team = newTeam
		end
		local teamToUse = team :: Team
		teamToUse.TeamColor = BrickColor.new(info.colour)
		teamToUse.AutoAssignable = false -- everyone picks a team in the menu
	end
end

local function chooseTeam(player: Player, teamName: unknown)
	if typeof(teamName) ~= "string" then
		return
	end
	local team = Teams:FindFirstChild(teamName)
	if not team or not team:IsA("Team") or player.Team == team then
		return
	end
	-- Changing team puts your old team's vehicle away
	Cars.despawn(player)
	player.Neutral = false
	player.Team = team
end

local function buyVehicle(player: Player, vehicleId: unknown): (boolean, string)
	if typeof(vehicleId) ~= "string" then
		return false, "That vehicle doesn't exist."
	end
	local vehicle = Vehicles.ById[vehicleId]
	if not vehicle then
		return false, "That vehicle doesn't exist."
	end
	if not PlayerData.isLoaded(player) then
		return false, "Your garage is still loading. Try again in a moment."
	end
	if PlayerData.owns(player, vehicle.id) then
		return true, "You already own it."
	end
	if not PlayerData.trySpend(player, vehicle.price) then
		return false, `You need {Format.money(vehicle.price)} for the {vehicle.name}.`
	end
	PlayerData.giveVehicle(player, vehicle.id)
	return true, `The {vehicle.name} is yours. Enjoy!`
end

local function setPaint(player: Player, vehicleId: unknown, paint: unknown)
	if typeof(vehicleId) ~= "string" then
		return
	end
	local vehicle = Vehicles.ById[vehicleId]
	if not vehicle or vehicle.fixedPaint or not PlayerData.owns(player, vehicle.id) then
		return
	end
	if paint == nil then
		PlayerData.setPaint(player, vehicle.id, nil) -- back to the factory colour
	elseif typeof(paint) == "number" and Vehicles.Paints[paint] then
		PlayerData.setPaint(player, vehicle.id, paint)
	end
end

function Garage.start()
	makeTeams()
	Remotes.event("ChooseTeam").OnServerEvent:Connect(chooseTeam)
	Remotes.event("SetPaint").OnServerEvent:Connect(setPaint)
	Remotes.func("BuyVehicle").OnServerInvoke = buyVehicle

	-- Nobody's on a team until they pick one
	Players.PlayerAdded:Connect(function(player)
		player.Neutral = true
	end)
end

return Garage
]])
put(folder4, "ModuleScript", "LightingSetup", [[
-- A bright British day with fluffy clouds, like Birmingham Vehicle Simulator: soft shadows, haze in the distance, gentle colour grading.
-- The "Future" lighting technology can't be set from code, so the game file sets it (Lighting → Technology in Studio).

local Lighting = game:GetService("Lighting")
local Workspace = game:GetService("Workspace")

local LightingSetup = {}

-- Swaps out whatever the place already had (the Baseplate template adds some), so there's only one of each
local function freshEffect(className: string, parent: Instance): any
	for _, child in parent:GetChildren() do
		if child.ClassName == className then
			child:Destroy()
		end
	end
	local effect: any = Instance.new(className :: any)
	effect.Parent = parent
	return effect
end

function LightingSetup.apply()
	Lighting.ClockTime = 13.5
	Lighting.GeographicLatitude = 51.5 -- London, so the sun sits where it should
	Lighting.Brightness = 3
	Lighting.Ambient = Color3.fromRGB(40, 40, 45)
	Lighting.OutdoorAmbient = Color3.fromRGB(128, 128, 135)
	Lighting.EnvironmentDiffuseScale = 1 -- light bounces off the sky onto everything
	Lighting.EnvironmentSpecularScale = 1 -- shiny things (car paint, glass) reflect the sky
	Lighting.GlobalShadows = true
	Lighting.ShadowSoftness = 0.3
	Lighting.ExposureCompensation = 0.1

	local atmosphere = freshEffect("Atmosphere", Lighting) :: Atmosphere
	atmosphere.Density = 0.3
	atmosphere.Offset = 0.1
	atmosphere.Color = Color3.fromRGB(199, 199, 199)
	atmosphere.Decay = Color3.fromRGB(106, 112, 125)
	atmosphere.Glare = 0.2
	atmosphere.Haze = 1.2

	local bloom = freshEffect("BloomEffect", Lighting) :: BloomEffect
	bloom.Intensity = 0.5
	bloom.Size = 24
	bloom.Threshold = 1.8

	local grading = freshEffect("ColorCorrectionEffect", Lighting) :: ColorCorrectionEffect
	grading.Brightness = 0.02
	grading.Contrast = 0.12
	grading.Saturation = 0.02
	grading.TintColor = Color3.fromRGB(255, 250, 245)

	local sunRays = freshEffect("SunRaysEffect", Lighting) :: SunRaysEffect
	sunRays.Intensity = 0.05
	sunRays.Spread = 0.8

	local clouds = freshEffect("Clouds", Workspace.Terrain) :: Clouds
	clouds.Cover = 0.55
	clouds.Density = 0.7
	clouds.Color = Color3.fromRGB(235, 235, 235)
end

return LightingSetup
]])
put(folder4, "Script", "Main", [[
-- Starts everything on the server.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Cars = require(script.Parent.Cars)
local Garage = require(script.Parent.Garage)
local LightingSetup = require(script.Parent.LightingSetup)
local PlayerData = require(script.Parent.PlayerData)
local TestTown = require(script.Parent.TestTown)
local TrafficLights = require(script.Parent.TrafficLights)

LightingSetup.apply()
PlayerData.start()
if Config.BuildTestTown then
	TestTown.build()
end
TrafficLights.start()
Cars.start()
Garage.start()

-- Placeholder income until jobs are added: pay everyone on a timer
while true do
	task.wait(Config.PaychequeIntervalSeconds)
	for _, player in Players:GetPlayers() do
		PlayerData.addCash(player, Config.PaychequeAmount)
	end
end
]])
put(folder4, "ModuleScript", "PlayerData", [[
-- Loads, saves and changes each player's saved data: cash, the vehicles they own and the colours they picked.
-- Other server scripts use it like this:
--   PlayerData.addCash(player, 50)
--   if PlayerData.owns(player, "regent_gt") then ... end
-- The client can read it too, through attributes on the player: "Cash", "Owned_<vehicle id>" and "Paint_<vehicle id>".

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Vehicles = require(ReplicatedStorage.Shared.Vehicles)

local MAX_ATTEMPTS = 3

type Data = {
	cash: number,
	owned: { string }, -- ids of vehicles they've bought
	paints: { [string]: number }, -- vehicle id -> paint number they picked
}

type Session = {
	data: Data,
	-- Stays false if loading failed, so a Roblox outage can never overwrite someone's real save
	canSave: boolean,
}

local PlayerData = {}

local sessions: { [Player]: Session } = {}

-- This fails until the game is published, so the game still runs, just without saving
local storeOk, store = pcall(DataStoreService.GetDataStore, DataStoreService, Config.DataStoreName)
if not storeOk then
	warn("[PlayerData] Saving is off until the game is published:", store)
end

local function keyFor(player: Player): string
	return "player_" .. player.UserId
end

-- DataStore calls sometimes fail for a moment, so try a few times before giving up
local function retry(action: () -> ...any): (boolean, any)
	local ok, result = false, nil
	for attempt = 1, MAX_ATTEMPTS do
		ok, result = pcall(action)
		if ok or attempt == MAX_ATTEMPTS then
			break
		end
		task.wait(attempt * 2)
	end
	return ok, result
end

-- Copies a save into fresh data, skipping anything broken or for vehicles that no longer exist
local function readSave(saved: any, data: Data)
	if type(saved) ~= "table" then
		return
	end
	if type(saved.cash) == "number" then
		data.cash = saved.cash
	end
	if type(saved.owned) == "table" then
		for _, id in saved.owned do
			if type(id) == "string" and Vehicles.ById[id] and not table.find(data.owned, id) then
				table.insert(data.owned, id)
			end
		end
	end
	if type(saved.paints) == "table" then
		for id, paint in saved.paints do
			if type(id) == "string" and Vehicles.ById[id] and type(paint) == "number" and Vehicles.Paints[paint] then
				data.paints[id] = paint
			end
		end
	end
end

local function onPlayerAdded(player: Player)
	local data: Data = {
		cash = Config.StartingCash,
		owned = {},
		paints = {},
	}
	local canSave = false

	if storeOk then
		local ok, saved = retry(function()
			return store:GetAsync(keyFor(player))
		end)
		if ok then
			readSave(saved, data)
			canSave = true
		else
			warn(`[PlayerData] Couldn't load {player.Name}'s data, so it won't be saved this session:`, saved)
		end
	end

	if player.Parent ~= Players then
		return -- they left while their data was loading
	end

	sessions[player] = { data = data, canSave = canSave }
	for _, id in data.owned do
		player:SetAttribute("Owned_" .. id, true)
	end
	for id, paint in data.paints do
		player:SetAttribute("Paint_" .. id, paint)
	end
	player:SetAttribute("Cash", data.cash)
end

local function save(player: Player)
	local session = sessions[player]
	if not session or not session.canSave then
		return
	end
	local ok, err = retry(function()
		store:SetAsync(keyFor(player), session.data, { player.UserId })
	end)
	if not ok then
		warn(`[PlayerData] Couldn't save {player.Name}'s data:`, err)
	end
end

local function onPlayerRemoving(player: Player)
	save(player)
	sessions[player] = nil
end

function PlayerData.isLoaded(player: Player): boolean
	return sessions[player] ~= nil
end

function PlayerData.addCash(player: Player, amount: number)
	local session = sessions[player]
	if not session then
		return -- their data hasn't loaded yet
	end
	session.data.cash += amount
	player:SetAttribute("Cash", session.data.cash)
end

-- Takes money only if they've got enough. Returns true if it worked.
function PlayerData.trySpend(player: Player, amount: number): boolean
	local session = sessions[player]
	if not session or session.data.cash < amount then
		return false
	end
	session.data.cash -= amount
	player:SetAttribute("Cash", session.data.cash)
	return true
end

-- Free vehicles (price 0) count as owned by everyone
function PlayerData.owns(player: Player, vehicleId: string): boolean
	local vehicle = Vehicles.ById[vehicleId]
	if not vehicle then
		return false
	end
	if vehicle.price == 0 then
		return true
	end
	local session = sessions[player]
	return session ~= nil and table.find(session.data.owned, vehicleId) ~= nil
end

function PlayerData.giveVehicle(player: Player, vehicleId: string)
	local session = sessions[player]
	if not session or table.find(session.data.owned, vehicleId) then
		return
	end
	table.insert(session.data.owned, vehicleId)
	player:SetAttribute("Owned_" .. vehicleId, true)
end

function PlayerData.paintOf(player: Player, vehicleId: string): number?
	local session = sessions[player]
	return session and session.data.paints[vehicleId]
end

function PlayerData.setPaint(player: Player, vehicleId: string, paint: number?)
	local session = sessions[player]
	if not session then
		return
	end
	local paints: { [string]: number? } = session.data.paints
	paints[vehicleId] = paint
	player:SetAttribute("Paint_" .. vehicleId, paint)
end

function PlayerData.start()
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	-- Catch anyone who joined before this script started (happens when testing in Studio)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end

	-- The server is shutting down: save everyone at once and wait until every save finishes
	game:BindToClose(function()
		local pending = 0
		for _, player in Players:GetPlayers() do
			pending += 1
			task.spawn(function()
				save(player)
				pending -= 1
			end)
		end
		while pending > 0 do
			task.wait()
		end
	end)

	task.spawn(function()
		while true do
			task.wait(Config.AutosaveIntervalSeconds)
			for _, player in Players:GetPlayers() do
				task.spawn(save, player)
			end
		end
	end)
end

return PlayerData
]])
put(folder4, "ModuleScript", "Remotes", [[
-- Makes the RemoteEvents and RemoteFunctions the menus and HUD use to talk to the server.
-- They all live in ReplicatedStorage → Remotes, so client scripts can find them by name.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = {}

local folder = Instance.new("Folder")
folder.Name = "Remotes"
folder.Parent = ReplicatedStorage

function Remotes.event(name: string): RemoteEvent
	local remote = Instance.new("RemoteEvent")
	remote.Name = name
	remote.Parent = folder
	return remote
end

function Remotes.func(name: string): RemoteFunction
	local remote = Instance.new("RemoteFunction")
	remote.Name = name
	remote.Parent = folder
	return remote
end

-- Pop-up messages at the top of a player's screen, e.g. Remotes.notify(player, "Bought!", "It's in your garage")
local notifyRemote = Remotes.event("Notify")
function Remotes.notify(player: Player, title: string, body: string?, colour: string?)
	notifyRemote:FireClient(player, title, body, colour)
end

return Remotes
]])
put(folder4, "ModuleScript", "TestTown", [[
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
]])
put(folder4, "ModuleScript", "TownBuildings", [[
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
]])
put(folder4, "ModuleScript", "TownKit", [[
-- Basic building blocks for the test town: anchored parts, road paint and signs with words on them.
-- TownProps, TownBuildings and TestTown all use these, so the whole town shares one set of colours and heights.

local CollectionService = game:GetService("CollectionService")

local TownKit = {}

-- Heights, in studs. Roads sit just above the ground and pavements are one kerb higher.
TownKit.ROAD_TOP = 0.1
TownKit.KERB_HEIGHT = 0.5
TownKit.PAVEMENT_TOP = TownKit.ROAD_TOP + TownKit.KERB_HEIGHT
TownKit.FLOOR = 11 -- one storey of a building

TownKit.Colours = {
	Asphalt = Color3.fromRGB(58, 58, 62),
	White = Color3.fromRGB(235, 235, 232),
	Yellow = Color3.fromRGB(240, 190, 20),
	Pavement = Color3.fromRGB(168, 165, 158),
	Kerb = Color3.fromRGB(140, 138, 132),
	Grass = Color3.fromRGB(78, 128, 58),
	Hedge = Color3.fromRGB(45, 90, 40),
	PostOfficeRed = Color3.fromRGB(200, 16, 30),
	StreetBlack = Color3.fromRGB(28, 30, 32),
	LampGrey = Color3.fromRGB(110, 112, 116),
	Stone = Color3.fromRGB(205, 198, 182),
	Portland = Color3.fromRGB(226, 219, 201),
	Gothic = Color3.fromRGB(206, 186, 142),
	RedBrick = Color3.fromRGB(140, 70, 50),
	StockBrick = Color3.fromRGB(170, 150, 118),
	Stucco = Color3.fromRGB(236, 232, 222),
	Slate = Color3.fromRGB(70, 72, 78),
	Glass = Color3.fromRGB(70, 92, 108),
	Concrete = Color3.fromRGB(158, 158, 154),
	Water = Color3.fromRGB(60, 90, 100),
	Bronze = Color3.fromRGB(80, 62, 40),
	Gold = Color3.fromRGB(205, 165, 70),
	TreeTrunk = Color3.fromRGB(85, 65, 45),
	Leaves = Color3.fromRGB(62, 110, 48),
}

local folder: Instance? = nil

-- Everything made after this goes into `parent`
function TownKit.setParent(parent: Instance)
	folder = parent
end

function TownKit.getParent(): Instance?
	return folder
end

-- An anchored block. `cframe` is its centre.
function TownKit.box(size: Vector3, cframe: CFrame, colour: Color3, material: Enum.Material?, className: string?): Part
	-- Typed as a Part so callers can set Shape; WedgeParts made here just never use it
	local part = Instance.new((className or "Part") :: any) :: Part
	part.Anchored = true
	part.Size = size
	part.CFrame = cframe
	part.Color = colour
	part.Material = material or Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.CanTouch = false
	part.Parent = folder
	return part
end

-- Roblox won't make a part bigger than 2048 studs, so big flat areas (grass, the riverbed) are cut into tiles.
-- `size` and `centre` are for the whole area; it can't be turned.
function TownKit.tiles(size: Vector3, centre: Vector3, colour: Color3, material: Enum.Material?): { Part }
	local MAX = 2000
	local countX, countZ = math.ceil(size.X / MAX), math.ceil(size.Z / MAX)
	local tileX, tileZ = size.X / countX, size.Z / countZ
	local made = {}
	for i = 0, countX - 1 do
		for j = 0, countZ - 1 do
			local x = centre.X - size.X / 2 + tileX * (i + 0.5)
			local z = centre.Z - size.Z / 2 + tileZ * (j + 0.5)
			table.insert(made, TownKit.box(Vector3.new(tileX, size.Y, tileZ), CFrame.new(x, centre.Y, z), colour, material))
		end
	end
	return made
end

-- A decoration that cars and players pass through and raycasts ignore (lamps' heads, signs, paint)
function TownKit.detail(size: Vector3, cframe: CFrame, colour: Color3, material: Enum.Material?, className: string?): Part
	local part = TownKit.box(size, cframe, colour, material, className)
	part.CanCollide = false
	part.CanQuery = false
	return part
end

-- Flat road paint at road level, turned `angle` radians around the vertical
function TownKit.paint(sizeX: number, sizeZ: number, position: Vector3, colour: Color3?, angle: number?): Part
	local cframe = CFrame.new(position.X, TownKit.ROAD_TOP + 0.02, position.Z) * CFrame.Angles(0, angle or 0, 0)
	local part = TownKit.detail(Vector3.new(sizeX, 0.05, sizeZ), cframe, colour or TownKit.Colours.White)
	part.CastShadow = false
	return part
end

-- A vertical cylinder standing on the ground at `base`
function TownKit.post(diameter: number, height: number, base: Vector3, colour: Color3, material: Enum.Material?): Part
	local part = TownKit.box(Vector3.new(height, diameter, diameter), CFrame.new(base + Vector3.new(0, height / 2, 0)) * CFrame.Angles(0, 0, math.pi / 2), colour, material)
	part.Shape = Enum.PartType.Cylinder
	return part
end

-- Words printed on one face of a part
function TownKit.text(host: BasePart, face: Enum.NormalId, text: string, colour: Color3, background: Color3?, weight: Enum.FontWeight?): TextLabel
	local surface = Instance.new("SurfaceGui")
	surface.Face = face
	surface.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	surface.PixelsPerStud = 30
	surface.LightInfluence = 0.8
	surface.MaxDistance = 400 -- don't bother drawing words nobody's close enough to read
	surface.Parent = host

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = if background then 0 else 1
	label.BackgroundColor3 = background or Color3.new()
	label.BorderSizePixel = 0
	label.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", weight or Enum.FontWeight.Bold)
	label.TextScaled = true
	label.TextColor3 = colour
	label.Text = text
	label.Parent = surface

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0.12, 0)
	padding.PaddingBottom = UDim.new(0.12, 0)
	padding.PaddingLeft = UDim.new(0.05, 0)
	padding.PaddingRight = UDim.new(0.05, 0)
	padding.Parent = label
	return label
end

function TownKit.tag(instance: Instance, tagName: string)
	CollectionService:AddTag(instance, tagName)
end

-- A CFrame at `position` facing `direction` (flattened so it's level)
function TownKit.facing(position: Vector3, direction: Vector3): CFrame
	local flat = Vector3.new(direction.X, 0, direction.Z)
	return CFrame.lookAt(position, position + flat.Unit)
end

return TownKit
]])
put(folder4, "ModuleScript", "TownProps", [[
-- Street furniture and road markings for the test town: lamp posts, trees, red phone and post boxes,
-- bus stops, bollards, railings, traffic lights, zebra crossings and speed cameras.
-- Each function puts one thing in the world. `cframe` arguments face the way the thing faces.

local TownKit = require(script.Parent.TownKit)

local C = TownKit.Colours
local PAVEMENT_TOP = TownKit.PAVEMENT_TOP
local box, detail, post, paint = TownKit.box, TownKit.detail, TownKit.post, TownKit.paint

local TownProps = {}

-- `at` is a point on the pavement
local function onPavement(at: Vector3): Vector3
	return Vector3.new(at.X, PAVEMENT_TOP, at.Z)
end

-- A grey London street lamp leaning its head out over the road. `towardRoad` points at the road.
function TownProps.lampPost(at: Vector3, towardRoad: Vector3)
	local base = onPavement(at)
	post(0.5, 15, base, C.LampGrey, Enum.Material.Metal)
	local frame = TownKit.facing(base + Vector3.new(0, 15, 0), towardRoad)
	local head = detail(Vector3.new(1, 0.45, 4.2), frame * CFrame.new(0, 0, -1.9), C.LampGrey, Enum.Material.Metal)
	TownKit.tag(head, "StreetLight")
end

function TownProps.tree(at: Vector3, scale: number?)
	local s = scale or 1
	local base = Vector3.new(at.X, at.Y, at.Z)
	post(1.2 * s, 9 * s, base, C.TreeTrunk, Enum.Material.Wood)
	local leaves = C.Leaves
	box(Vector3.new(10, 9, 10) * s, CFrame.new(base + Vector3.new(0, 12 * s, 0)), leaves, Enum.Material.Grass, "Part").Shape = Enum.PartType.Ball
	local top = box(Vector3.new(7, 7, 7) * s, CFrame.new(base + Vector3.new(1.5 * s, 16 * s, -1 * s)), leaves:Lerp(Color3.new(0.3, 0.5, 0.2), 0.15), Enum.Material.Grass)
	top.Shape = Enum.PartType.Ball
end

-- A tall conifer, for the woods round the edge of the map
function TownProps.pine(at: Vector3, scale: number)
	post(1.4 * scale, 8 * scale, at, C.TreeTrunk, Enum.Material.Wood)
	for i = 0, 2 do
		local width = (11 - i * 3) * scale
		local cone = box(Vector3.new(width, 9 * scale, width), CFrame.new(at + Vector3.new(0, (9 + i * 6.5) * scale, 0)), Color3.fromRGB(40, 75, 45), Enum.Material.Grass)
		cone.Shape = Enum.PartType.Ball
	end
end

function TownProps.bin(at: Vector3)
	local base = onPavement(at)
	post(1.6, 3.2, base, C.StreetBlack, Enum.Material.Metal)
	detail(Vector3.new(1.8, 0.3, 1.8), CFrame.new(base + Vector3.new(0, 3.3, 0)), C.Gold, Enum.Material.Metal)
end

function TownProps.bollard(at: Vector3)
	local base = onPavement(at)
	post(0.8, 3, base, C.StreetBlack, Enum.Material.Metal)
	post(0.86, 0.35, base + Vector3.new(0, 2.2, 0), C.White)
end

-- The classic red telephone box
function TownProps.phoneBox(at: Vector3, facing: Vector3)
	local frame = TownKit.facing(onPavement(at), facing)
	box(Vector3.new(3.4, 8, 3.4), frame * CFrame.new(0, 4, 0), C.PostOfficeRed)
	box(Vector3.new(3.8, 0.8, 3.8), frame * CFrame.new(0, 8.4, 0), C.PostOfficeRed)
	local panel = detail(Vector3.new(2.6, 4.6, 0.1), frame * CFrame.new(0, 4.3, -1.75), Color3.fromRGB(40, 50, 55), Enum.Material.Glass)
	panel.Transparency = 0.3
	local sign = detail(Vector3.new(2.8, 0.6, 0.1), frame * CFrame.new(0, 7.3, -1.76), C.StreetBlack)
	TownKit.text(sign, Enum.NormalId.Front, "TELEPHONE", C.White)
end

-- A red pillar box for posting letters
function TownProps.postBox(at: Vector3, facing: Vector3)
	local frame = TownKit.facing(onPavement(at), facing)
	local body = box(Vector3.new(4.6, 1.9, 1.9), frame * CFrame.new(0, 2.3, 0) * CFrame.Angles(0, 0, math.pi / 2), C.PostOfficeRed)
	body.Shape = Enum.PartType.Cylinder
	box(Vector3.new(2.1, 0.5, 2.1), frame * CFrame.new(0, 4.8, 0), C.StreetBlack)
	detail(Vector3.new(1, 0.15, 0.1), frame * CFrame.new(0, 3.6, -0.96), C.StreetBlack)
end

function TownProps.bench(at: Vector3, facing: Vector3)
	local frame = TownKit.facing(onPavement(at), facing)
	box(Vector3.new(5, 0.3, 1.6), frame * CFrame.new(0, 1.6, 0), C.TreeTrunk, Enum.Material.Wood)
	detail(Vector3.new(5, 1.2, 0.25), frame * CFrame.new(0, 2.4, 0.75), C.TreeTrunk, Enum.Material.Wood)
	for _, x in { -2.1, 2.1 } do
		detail(Vector3.new(0.25, 1.5, 1.4), frame * CFrame.new(x, 0.75, 0), C.StreetBlack, Enum.Material.Metal)
	end
end

-- Black railings along `length` studs, starting at `from` and going in `direction`
function TownProps.railing(from: Vector3, direction: Vector3, length: number, colour: Color3?)
	local frame = TownKit.facing(onPavement(from), direction)
	local paintColour = colour or C.StreetBlack
	for _, height in { 1.2, 3.2 } do
		detail(Vector3.new(0.2, 0.2, length), frame * CFrame.new(0, height, -length / 2), paintColour, Enum.Material.Metal)
	end
	local posts = math.max(2, math.floor(length / 4))
	for i = 0, posts do
		local z = -length * i / posts
		box(Vector3.new(0.25, 3.4, 0.25), frame * CFrame.new(0, 1.7, z), paintColour, Enum.Material.Metal)
	end
end

-- A bus shelter, the red stop sign on its pole, and the yellow "BUS STOP" box painted on the road.
-- `frame` sits on the kerb edge facing the road.
function TownProps.busStop(frame: CFrame)
	local shelter = frame * CFrame.new(0, PAVEMENT_TOP, 5)
	local glassColour = Color3.fromRGB(150, 175, 185)
	local back = detail(Vector3.new(12, 6.5, 0.15), shelter * CFrame.new(0, 3.5, 2), glassColour, Enum.Material.Glass)
	back.Transparency = 0.55
	back.CanCollide = true
	for _, x in { -6, 6 } do
		box(Vector3.new(0.3, 7.5, 0.3), shelter * CFrame.new(x, 3.75, 2), C.StreetBlack, Enum.Material.Metal)
		box(Vector3.new(0.3, 7.5, 0.3), shelter * CFrame.new(x, 3.75, -1), C.StreetBlack, Enum.Material.Metal)
	end
	detail(Vector3.new(12.6, 0.3, 4), shelter * CFrame.new(0, 7.6, 0.5), C.StreetBlack, Enum.Material.Metal)
	box(Vector3.new(8, 0.3, 1.2), shelter * CFrame.new(0, 1.8, 1.4), C.StreetBlack, Enum.Material.Metal)

	local pole = frame * CFrame.new(9, PAVEMENT_TOP, 1.2)
	box(Vector3.new(0.35, 10, 0.35), pole * CFrame.new(0, 5, 0), C.LampGrey, Enum.Material.Metal)
	local flag = detail(Vector3.new(2.6, 2.6, 0.15), pole * CFrame.new(0, 9, 0) * CFrame.Angles(0, math.pi / 2, 0), Color3.fromRGB(210, 30, 35))
	TownKit.text(flag, Enum.NormalId.Front, "BUS STOP", C.White)
	TownKit.text(flag, Enum.NormalId.Back, "BUS STOP", C.White)

	-- Road markings: a yellow box with "BUS STOP" written in it
	local road = frame * CFrame.new(0, 0, -5)
	local level = CFrame.new(0, TownKit.ROAD_TOP + 0.02 - road.Position.Y, 0)
	for _, z in { -4, 4 } do
		local line = paint(40, 0.4, Vector3.zero, C.Yellow)
		line.CFrame = road * level * CFrame.new(0, 0, z)
	end
	-- Turned so the words read the right way up for traffic in the near lane (we drive on the left)
	local words = paint(8, 3, Vector3.zero, C.Yellow)
	words.CFrame = road * level * CFrame.Angles(0, math.pi / 2, 0)
	words.Transparency = 1
	local label = TownKit.text(words, Enum.NormalId.Top, "BUS STOP", C.Yellow)
	label.TextTransparency = 0.05
end

-- Traffic light head on a pole. `frame` sits on the pavement facing the drivers it controls.
-- The TrafficLights script finds the lamps by their names (Red, Amber, Green) and the tag.
function TownProps.trafficLight(frame: CFrame, junctionId: string, axis: string)
	local base = frame * CFrame.new(0, PAVEMENT_TOP, 0)
	box(Vector3.new(0.5, 11, 0.5), base * CFrame.new(0, 5.5, 0), C.LampGrey, Enum.Material.Metal)

	local head = Instance.new("Model")
	head.Name = "TrafficLight"
	head:SetAttribute("Junction", junctionId)
	head:SetAttribute("Axis", axis)
	TownKit.tag(head, "TrafficLight")

	local housing = detail(Vector3.new(1.5, 4.2, 1.1), base * CFrame.new(0, 10, -0.5), C.StreetBlack, Enum.Material.Metal)
	housing.Parent = head
	local backboard = detail(Vector3.new(2.3, 5, 0.12), base * CFrame.new(0, 10, 0.06), C.StreetBlack)
	backboard.Parent = head
	for i, name in { "Red", "Amber", "Green" } do
		local lamp = detail(Vector3.new(0.25, 1, 1), base * CFrame.new(0, 11.35 - (i - 1) * 1.35, -1.08) * CFrame.Angles(0, math.pi / 2, 0), Color3.fromRGB(40, 40, 40), Enum.Material.SmoothPlastic)
		lamp.Shape = Enum.PartType.Cylinder
		lamp.Name = name
		lamp.Parent = head
	end
	head.Parent = TownKit.getParent()
end

-- Black-and-white striped pole with a flashing amber globe, one each side of a zebra crossing
function TownProps.belisha(at: Vector3)
	local base = onPavement(at)
	for i = 0, 5 do
		local stripe = box(Vector3.new(1.4, 0.4, 0.4), CFrame.new(base + Vector3.new(0, 0.7 + i * 1.4, 0)) * CFrame.Angles(0, 0, math.pi / 2), if i % 2 == 0 then C.StreetBlack else C.White, Enum.Material.SmoothPlastic)
		stripe.Shape = Enum.PartType.Cylinder
	end
	local globe = detail(Vector3.new(1.4, 1.4, 1.4), CFrame.new(base + Vector3.new(0, 9.1, 0)), Color3.fromRGB(255, 160, 20), Enum.Material.Neon)
	globe.Shape = Enum.PartType.Ball
	TownKit.tag(globe, "BelishaGlobe")
end

-- White stripes across the road with zig-zags either side. `frame` is the middle of the road,
-- facing along it; `width` is how wide the road is.
function TownProps.zebra(frame: CFrame, width: number)
	local level = CFrame.new(0, TownKit.ROAD_TOP + 0.02 - frame.Position.Y, 0)
	local stripes = math.floor(width / 2.4)
	for i = 0, stripes - 1 do
		local x = -width / 2 + 1.2 + i * 2.4
		local stripe = paint(1.2, 8, Vector3.zero)
		stripe.CFrame = frame * level * CFrame.new(x, 0, 0)
	end
	-- Zig-zag lines along both kerbs, both sides of the crossing
	for _, side in { -1, 1 } do
		for _, direction in { -1, 1 } do
			for i = 0, 7 do
				local z = direction * (6 + i * 2.6)
				local zig = paint(0.35, 2.9, Vector3.zero)
				zig.CFrame = frame * level * CFrame.new(side * (width / 2 - 1.6), 0, z) * CFrame.Angles(0, if i % 2 == 0 then 0.35 else -0.35, 0)
			end
		end
	end
end

-- The double dashed "give way" line across the lane that's coming up to a junction.
-- `frame` is on the junction edge in the middle of that lane, facing the junction.
function TownProps.giveWay(frame: CFrame, laneWidth: number)
	local level = CFrame.new(0, TownKit.ROAD_TOP + 0.02 - frame.Position.Y, 0)
	local dashes = math.floor(laneWidth / 2.6)
	for row = 0, 1 do
		for i = 0, dashes - 1 do
			local x = -laneWidth / 2 + 1.3 + i * 2.6
			local dash = paint(1.6, 0.5, Vector3.zero)
			dash.CFrame = frame * level * CFrame.new(x, 0, 1.4 + row * 1.2)
		end
	end
end

-- A solid stop line and a straight-on arrow before a set of traffic lights
function TownProps.stopLine(frame: CFrame, laneWidth: number)
	local level = CFrame.new(0, TownKit.ROAD_TOP + 0.02 - frame.Position.Y, 0)
	local line = paint(laneWidth - 1, 0.7, Vector3.zero)
	line.CFrame = frame * level * CFrame.new(0, 0, 1.8)
	local shaft = paint(0.6, 7, Vector3.zero)
	shaft.CFrame = frame * level * CFrame.new(0, 0, 12)
	local head = TownKit.detail(Vector3.new(2.4, 0.05, 2.4), frame * level * CFrame.new(0, 0, 7.4) * CFrame.Angles(0, math.pi / 4, 0), C.White)
	head.CastShadow = false
end

-- A yellow speed camera on a grey pole, pointing back along the road at oncoming cars
function TownProps.speedCamera(frame: CFrame, limit: number)
	local base = frame * CFrame.new(0, PAVEMENT_TOP, 0)
	box(Vector3.new(0.6, 10, 0.6), base * CFrame.new(0, 5, 0), C.LampGrey, Enum.Material.Metal)
	local camera = box(Vector3.new(1.8, 2.2, 3.2), base * CFrame.new(0, 10.4, 0), Color3.fromRGB(245, 205, 30))
	camera:SetAttribute("SpeedLimit", limit)
	TownKit.tag(camera, "SpeedCamera")
	detail(Vector3.new(1.2, 1.2, 0.1), base * CFrame.new(0, 10.4, -1.62), C.StreetBlack, Enum.Material.Glass)
end

-- A round speed limit sign on a pole
function TownProps.limitSign(at: Vector3, facing: Vector3, limit: number)
	local frame = TownKit.facing(onPavement(at), facing)
	box(Vector3.new(0.3, 8, 0.3), frame * CFrame.new(0, 4, 0), C.LampGrey, Enum.Material.Metal)
	local disc = detail(Vector3.new(0.15, 2.6, 2.6), frame * CFrame.new(0, 8.6, -0.2) * CFrame.Angles(0, math.pi / 2, 0), Color3.fromRGB(210, 30, 30))
	disc.Shape = Enum.PartType.Cylinder
	local face = detail(Vector3.new(1.9, 1.9, 0.05), frame * CFrame.new(0, 8.6, -0.3), C.White)
	TownKit.text(face, Enum.NormalId.Front, tostring(limit), Color3.new(0, 0, 0))
end

return TownProps
]])
put(folder4, "ModuleScript", "TrafficLights", [[
-- Runs every set of traffic lights in the map, UK style: red, red and amber, green, amber, red.
-- Each light head is a Model tagged "TrafficLight" with lamps called Red, Amber and Green, and two attributes:
--   Junction: which junction it belongs to (heads with the same name change together)
--   Axis: "NS" or "EW", which way the traffic it controls is going
-- The junction's current state is written to ReplicatedStorage → TrafficSignals as an attribute
-- (e.g. "NS" = green for north-south), ready for red-light cameras later.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GREEN_SECONDS = 14
local AMBER_SECONDS = 3
local RED_AMBER_SECONDS = 2
local ALL_RED_SECONDS = 2

local LIT = {
	Red = Color3.fromRGB(255, 45, 35),
	Amber = Color3.fromRGB(255, 165, 0),
	Green = Color3.fromRGB(40, 255, 120),
}
local OFF = Color3.fromRGB(38, 36, 34)

-- What each axis shows in each step of the cycle
type Step = { ns: { string }, ew: { string }, seconds: number, green: string? }
local CYCLE: { Step } = {
	{ ns = { "Green" }, ew = { "Red" }, seconds = GREEN_SECONDS, green = "NS" },
	{ ns = { "Amber" }, ew = { "Red" }, seconds = AMBER_SECONDS },
	{ ns = { "Red" }, ew = { "Red" }, seconds = ALL_RED_SECONDS },
	{ ns = { "Red" }, ew = { "Red", "Amber" }, seconds = RED_AMBER_SECONDS },
	{ ns = { "Red" }, ew = { "Green" }, seconds = GREEN_SECONDS, green = "EW" },
	{ ns = { "Red" }, ew = { "Amber" }, seconds = AMBER_SECONDS },
	{ ns = { "Red" }, ew = { "Red" }, seconds = ALL_RED_SECONDS },
	{ ns = { "Red", "Amber" }, ew = { "Red" }, seconds = RED_AMBER_SECONDS },
}

local TrafficLights = {}

local function show(head: Instance, lit: { string })
	for _, name in { "Red", "Amber", "Green" } do
		local lamp = head:FindFirstChild(name)
		if lamp and lamp:IsA("BasePart") then
			local on = table.find(lit, name) ~= nil
			lamp.Color = if on then LIT[name] else OFF
			lamp.Material = if on then Enum.Material.Neon else Enum.Material.SmoothPlastic
		end
	end
end

local function runJunction(id: string, heads: { Instance }, signals: Configuration, startStep: number)
	-- Attribute names can only use letters, numbers and underscores, so "120,480" becomes "Junction_120_480"
	local attribute = "Junction_" .. (id:gsub("[^%w]", "_"))
	local step = startStep
	while true do
		local current = CYCLE[step]
		for _, head in heads do
			show(head, if head:GetAttribute("Axis") == "NS" then current.ns else current.ew)
		end
		signals:SetAttribute(attribute, current.green or "None")
		task.wait(current.seconds)
		step = step % #CYCLE + 1
	end
end

function TrafficLights.start()
	local signals = Instance.new("Configuration")
	signals.Name = "TrafficSignals"
	signals.Parent = ReplicatedStorage

	local junctions: { [string]: { Instance } } = {}
	for _, head in CollectionService:GetTagged("TrafficLight") do
		local id = head:GetAttribute("Junction")
		if typeof(id) == "string" then
			junctions[id] = junctions[id] or {}
			table.insert(junctions[id], head)
		end
	end

	-- Start each junction at a different point in the cycle so the whole town doesn't change at once
	local random = Random.new(42)
	for id, heads in junctions do
		task.spawn(runJunction, id, heads, signals, random:NextInteger(1, #CYCLE))
	end
end

return TrafficLights
]])
removeOldScripts(folder4)
local folder5 = game:GetService("StarterPlayer")
local folder6 = folder5:WaitForChild("StarterPlayerScripts")
local folder7 = folder(folder6, "Client")
put(folder7, "LocalScript", "Dashboard", [[
-- What you see while driving, laid out like Birmingham Vehicle Simulator:
--   bottom left: a panel with your speed in mph, the speed limit, the day and time, and a minimap
--     of the roads around you (other players are blue dots, you're the white arrow in the middle)
--   right: the driving controls list
-- The minimap reads the roads from ReplicatedStorage → MapInfo → Minimap, which TestTown writes.

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Ui = require(script.Parent:WaitForChild("Ui"))
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local LIMIT_CHECK_SECONDS = 0.25
local MAP_SCALE = 0.32 -- pixels per stud
local PANEL_WIDTH, PANEL_HEIGHT = 300, 232
local MAP_TOP = 58 -- the speed and time sit above the map

local C = Ui.Colours
local player = Players.LocalPlayer

local gui = Ui.screen("Dashboard", 4)
gui.Enabled = false

local panel = Ui.panel({
	AnchorPoint = Vector2.new(0, 1),
	Position = UDim2.new(0, 16, 1, -16),
	Size = UDim2.fromOffset(PANEL_WIDTH, PANEL_HEIGHT),
	Parent = gui,
})
panel.BackgroundTransparency = 0.18

local speedLabel = Ui.label("0", 36, Enum.FontWeight.Bold, {
	Position = UDim2.fromOffset(16, 8),
	Size = UDim2.fromOffset(0, 40),
	AutomaticSize = Enum.AutomaticSize.X,
	TextXAlignment = Enum.TextXAlignment.Left,
	Parent = panel,
})
local unitLabel = Ui.label("mph", 12, Enum.FontWeight.Medium, {
	Size = UDim2.fromOffset(30, 16),
	TextXAlignment = Enum.TextXAlignment.Left,
	TextColor3 = C.Muted,
	Parent = panel,
})

-- Speed limit roundel: a white disc with a red ring
local limitSign = Ui.make("Frame", { Size = UDim2.fromOffset(34, 34), BackgroundColor3 = Color3.new(1, 1, 1), Visible = false, Parent = panel })
Ui.corner(limitSign, 17)
Ui.make("UIStroke", { Color = Color3.fromRGB(215, 30, 30), Thickness = 4, Parent = limitSign })
local limitLabel = Ui.label("", 15, Enum.FontWeight.Bold, { Size = UDim2.fromScale(1, 1), TextColor3 = Color3.new(0, 0, 0), Parent = limitSign })

local clockLabel = Ui.label("", 12, Enum.FontWeight.Medium, {
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -16, 0, 14),
	Size = UDim2.fromOffset(120, 16),
	TextXAlignment = Enum.TextXAlignment.Right,
	Parent = panel,
})

-- The map: a CanvasGroup clips it to the rounded panel even when it's turned
local mapWindow = Ui.make("CanvasGroup", {
	Position = UDim2.fromOffset(0, MAP_TOP),
	Size = UDim2.new(1, 0, 1, -MAP_TOP),
	BackgroundColor3 = Color3.fromRGB(22, 24, 30),
	BackgroundTransparency = 0.25,
	BorderSizePixel = 0,
	Parent = panel,
})
Ui.corner(mapWindow, 14)
local mapCentre = Vector2.new(PANEL_WIDTH / 2, (PANEL_HEIGHT - MAP_TOP) * 0.62)
-- `pivot` turns around the player; `world` slides so the player stays in the middle
local pivot = Ui.make("Frame", { Position = UDim2.fromOffset(mapCentre.X, mapCentre.Y), Size = UDim2.new(), BackgroundTransparency = 1, Parent = mapWindow })
local world = Ui.make("Frame", { Size = UDim2.new(), BackgroundTransparency = 1, Parent = pivot })
local dots = Ui.make("Frame", { Size = UDim2.new(), BackgroundTransparency = 1, ZIndex = 5, Parent = world })

local ROAD_COLOURS = {
	side = Color3.fromRGB(120, 124, 132),
	main = Color3.fromRGB(165, 168, 176),
	dual = Color3.fromRGB(200, 202, 210),
	yard = Color3.fromRGB(70, 74, 82),
	water = Color3.fromRGB(45, 85, 130),
	park = Color3.fromRGB(40, 85, 50),
}
local ROAD_ORDER = { water = 1, park = 1, yard = 2, side = 3, main = 4, dual = 5 }

local function drawMap()
	local mapInfo = ReplicatedStorage:WaitForChild("MapInfo", 30)
	local data = mapInfo and mapInfo:WaitForChild("Minimap", 30)
	if not data or not data:IsA("StringValue") then
		return
	end
	local ok, rects = pcall(function(): any
		return HttpService:JSONDecode(data.Value)
	end)
	if not ok or type(rects) ~= "table" then
		return
	end
	for _, rect in rects do
		local x, z, sizeX, sizeZ, kind = rect[1], rect[2], rect[3], rect[4], rect[5]
		local isRoad = kind == "side" or kind == "main" or kind == "dual"
		-- Draw roads thinner than they really are so the map stays readable
		local thin = if isRoad then 0.55 else 1
		local width = if isRoad and sizeX < sizeZ then math.max(3, sizeX * MAP_SCALE * thin) else sizeX * MAP_SCALE
		local height = if isRoad and sizeZ <= sizeX then math.max(3, sizeZ * MAP_SCALE * thin) else sizeZ * MAP_SCALE
		local frame = Ui.make("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(x * MAP_SCALE, z * MAP_SCALE),
			Size = UDim2.fromOffset(width, height),
			BackgroundColor3 = ROAD_COLOURS[kind] or ROAD_COLOURS.side,
			BorderSizePixel = 0,
			ZIndex = ROAD_ORDER[kind] or 3,
			Parent = world,
		})
		frame.BackgroundTransparency = if kind == "yard" then 0.4 else 0
	end
end
task.spawn(drawMap)

-- You: a white arrow in the middle, always pointing up
local arrow = Ui.label("▲", 18, Enum.FontWeight.Bold, {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromOffset(mapCentre.X, mapCentre.Y),
	Size = UDim2.fromOffset(20, 20),
	ZIndex = 10,
	Parent = mapWindow,
})
arrow.TextStrokeTransparency = 0.3

local playerDots: { [Player]: Frame } = {}
local function dotFor(other: Player): Frame
	local existing = playerDots[other]
	if existing then
		return existing
	end
	local dot: Frame = Ui.make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(9, 9),
		BackgroundColor3 = Color3.fromRGB(80, 140, 255),
		BorderSizePixel = 0,
		ZIndex = 6,
		Parent = dots,
	})
	Ui.corner(dot, 5)
	Ui.make("UIStroke", { Color = Color3.new(1, 1, 1), Thickness = 1.5, Parent = dot })
	playerDots[other] = dot
	return dot
end
Players.PlayerRemoving:Connect(function(other)
	local dot = playerDots[other]
	if dot then
		dot:Destroy()
		playerDots[other] = nil
	end
end)

-- Driving controls on the right --------------------------------------------------------------

local controlsList = Ui.make("Frame", {
	AnchorPoint = Vector2.new(1, 1),
	Position = UDim2.new(1, -16, 1, -16),
	Size = UDim2.fromOffset(220, 0),
	AutomaticSize = Enum.AutomaticSize.Y,
	BackgroundTransparency = 1,
	Parent = gui,
})
Ui.make("UIListLayout", { Padding = UDim.new(0, 7), HorizontalAlignment = Enum.HorizontalAlignment.Right, SortOrder = Enum.SortOrder.LayoutOrder, Parent = controlsList })

local blueLightsRow: Frame? = nil
for order, control in {
	{ "Steering", "WASD" },
	{ "Handbrake", "Space" },
	{ "Indicators", "Q-E" },
	{ "Hazards", "B" },
	{ "Lights", "L" },
	{ "Blue lights", "R" },
	{ "Get out", "F" },
} do
	local row = Ui.make("Frame", { Size = UDim2.new(1, 0, 0, 28), BackgroundTransparency = 1, LayoutOrder = order, Parent = controlsList })
	local key = Ui.label(control[2], 13, Enum.FontWeight.Medium, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.fromOffset(0, 28),
		AutomaticSize = Enum.AutomaticSize.X,
		Parent = row,
	})
	Ui.padding(key, 9, 0)
	Ui.corner(key, 14)
	Ui.make("UIStroke", { ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Color = Color3.new(1, 1, 1), Thickness = 1.5, Parent = key })
	local action = Ui.label(control[1], 14, Enum.FontWeight.Regular, {
		Size = UDim2.new(1, -70, 1, 0),
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = row,
	})
	action.TextStrokeTransparency = 0.6
	key.TextStrokeTransparency = 0.7
	if control[1] == "Blue lights" then
		blueLightsRow = row
	end
end

local function applyControlsSetting()
	controlsList.Visible = Ui.settings.Controls
end
Ui.SettingChanged:Connect(applyControlsSetting)
applyControlsSetting()

-- Every frame while driving ----------------------------------------------------------------

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

local speedLimit: number? = nil
local sinceLimitCheck = math.huge

RunService.Heartbeat:Connect(function(dt)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local seat = humanoid and humanoid.SeatPart
	if Ui.menuOpen or not seat or not seat:IsA("VehicleSeat") then
		gui.Enabled = false
		sinceLimitCheck = math.huge
		return
	end
	gui.Enabled = true
	local car = seat.Parent :: Instance

	sinceLimitCheck += dt
	if sinceLimitCheck >= LIMIT_CHECK_SECONDS then
		sinceLimitCheck = 0
		rayParams.FilterDescendantsInstances = { car, character :: Instance }
		local hit = Workspace:Raycast(seat.Position, Vector3.new(0, -10, 0), rayParams)
		local limit = hit and hit.Instance:GetAttribute("SpeedLimit")
		speedLimit = if typeof(limit) == "number" then limit else nil
		clockLabel.Text = os.date("%a %H:%M") :: string
		if blueLightsRow then
			blueLightsRow.Visible = car:GetAttribute("HasBlueLights") == true
		end
	end

	local mph = math.floor(math.abs(seat.AssemblyLinearVelocity:Dot(seat.CFrame.LookVector)) * Config.MphPerStudPerSecond + 0.5)
	speedLabel.Text = tostring(mph)
	speedLabel.TextColor3 = if speedLimit and mph > speedLimit then C.Red else C.Text
	local speedWidth = speedLabel.TextBounds.X
	unitLabel.Position = UDim2.fromOffset(16 + speedWidth + 4, 30)
	limitSign.Visible = speedLimit ~= nil
	limitSign.Position = UDim2.fromOffset(16 + speedWidth + 38, 12)
	limitLabel.Text = if speedLimit then tostring(speedLimit) else ""

	-- Slide and turn the map so you're in the middle, facing up
	local position = seat.Position
	world.Position = UDim2.fromOffset(-position.X * MAP_SCALE, -position.Z * MAP_SCALE)
	local look = seat.CFrame.LookVector
	pivot.Rotation = if Ui.settings.TurnMap then -90 - math.deg(math.atan2(look.Z, look.X)) else 0
	arrow.Rotation = if Ui.settings.TurnMap then 0 else 90 + math.deg(math.atan2(look.Z, look.X))

	for _, other in Players:GetPlayers() do
		if other ~= player then
			local otherCharacter = other.Character
			local root = otherCharacter and otherCharacter:FindFirstChild("HumanoidRootPart") :: BasePart?
			local dot = dotFor(other)
			dot.Visible = root ~= nil
			if root then
				dot.Position = UDim2.fromOffset(root.Position.X * MAP_SCALE, root.Position.Z * MAP_SCALE)
			end
		end
	end
end)
]])
put(folder7, "LocalScript", "Driving", [[
-- Drives the vehicle you're sitting in the driver's seat of.
-- It runs on your own device (the server hands the driver control of the car's physics), so steering feels instant.
-- Each vehicle carries its own top speed, acceleration and size as attributes (set by CarBuilder),
-- so a bus drives like a bus and a sports car like a sports car.
-- Keys while driving, like Birmingham Vehicle Simulator: Space handbrake, F get out, L lights,
-- Q / E indicators, B hazards, R blue lights.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local carControl = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("CarControl") :: RemoteEvent

local CAR = Config.Car
local STEERING_LOCK = math.rad(CAR.SteeringLockDegrees)

local player = Players.LocalPlayer
local driving: RBXScriptConnection? = nil
local handbrake = false
local normalMinZoom: number? = nil -- the camera's closest zoom before we got in, to put back after

-- Moves `value` towards `target` by at most `step`
local function approach(value: number, target: number, step: number): number
	if value < target then
		return math.min(value + step, target)
	end
	return math.max(value - step, target)
end

-- A number the vehicle carries as an attribute, or the default from Config
local function stat(car: Instance, name: string, default: number): number
	local value = car:GetAttribute(name)
	return if typeof(value) == "number" then value else default
end

local SWITCHES: { [Enum.KeyCode]: string } = {
	[Enum.KeyCode.L] = "Lights",
	[Enum.KeyCode.Q] = "Left",
	[Enum.KeyCode.E] = "Right",
	[Enum.KeyCode.B] = "Hazard",
	[Enum.KeyCode.R] = "BlueLights",
}

local function onSwitch(_: string, state: Enum.UserInputState, input: InputObject): Enum.ContextActionResult
	if state == Enum.UserInputState.Begin then
		local action = SWITCHES[input.KeyCode]
		if action then
			carControl:FireServer(action)
		end
	end
	return Enum.ContextActionResult.Sink
end

-- Space is the handbrake while driving, so it mustn't make you jump out of the seat
local function onHandbrake(_: string, state: Enum.UserInputState): Enum.ContextActionResult
	handbrake = state == Enum.UserInputState.Begin or state == Enum.UserInputState.Change
	return Enum.ContextActionResult.Sink
end

local function onGetOut(_: string, state: Enum.UserInputState): Enum.ContextActionResult
	if state == Enum.UserInputState.Begin then
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid.Sit = false
		end
	end
	return Enum.ContextActionResult.Sink
end

local function bindKeys()
	local priority = Enum.ContextActionPriority.High.Value
	ContextActionService:BindActionAtPriority("CarSwitches", onSwitch, false, priority, Enum.KeyCode.L, Enum.KeyCode.Q, Enum.KeyCode.E, Enum.KeyCode.B, Enum.KeyCode.R)
	ContextActionService:BindActionAtPriority("Handbrake", onHandbrake, false, priority, Enum.KeyCode.Space, Enum.KeyCode.ButtonA)
	ContextActionService:BindActionAtPriority("GetOut", onGetOut, false, priority, Enum.KeyCode.F, Enum.KeyCode.ButtonY)
end

local function unbindKeys()
	ContextActionService:UnbindAction("CarSwitches")
	ContextActionService:UnbindAction("Handbrake")
	ContextActionService:UnbindAction("GetOut")
	handbrake = false
end

local function stopDriving()
	if driving then
		driving:Disconnect()
		driving = nil
	end
	unbindKeys()
	if normalMinZoom then
		player.CameraMinZoomDistance = normalMinZoom
		normalMinZoom = nil
	end
end

local function startDriving(seat: VehicleSeat)
	local car = seat.Parent :: Model
	local chassis = car.PrimaryPart
	if not chassis or not car:GetAttribute("ArcadeHandling") then
		return -- not one of our cars: bought cars usually come with their own driving scripts
	end
	bindKeys()

	-- Keep the camera far enough back to see the whole vehicle: a bus is over twice as long as a car
	normalMinZoom = player.CameraMinZoomDistance
	player.CameraMinZoomDistance = math.max(normalMinZoom :: number, chassis.Size.Z * 1.25)

	local topSpeed = stat(car, "TopSpeed", CAR.TopSpeed)
	local reverseSpeed = stat(car, "ReverseSpeed", CAR.ReverseSpeed)
	local acceleration = stat(car, "Acceleration", CAR.Acceleration)
	local wheelbase = stat(car, "Wheelbase", CAR.Wheelbase)
	local wheelRadius = stat(car, "WheelRadius", CAR.WheelRadius)
	local groundRay = stat(car, "GroundRay", 3.5)

	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = { car, player.Character :: Instance }

	local wheelJoints: { Motor6D } = {}
	for _, joint in chassis:GetChildren() do
		if joint:IsA("Motor6D") then
			table.insert(wheelJoints, joint)
		end
	end

	local steer = 0
	local wheelSpin = 0

	driving = RunService.Heartbeat:Connect(function(dt)
		local cframe = chassis.CFrame
		local forward, right, up = cframe.LookVector, cframe.RightVector, cframe.UpVector

		local velocity = chassis.AssemblyLinearVelocity
		local forwardSpeed = velocity:Dot(forward)
		local sideSpeed = velocity:Dot(right)
		local upSpeed = velocity:Dot(up)

		-- Turn the steering wheel gradually, even with a keyboard
		steer = approach(steer, seat.SteerFloat, CAR.SteeringResponse * dt)

		-- Turn the front wheels and spin all of them as the car moves (just for looks)
		wheelSpin -= forwardSpeed * dt / wheelRadius
		for _, joint in wheelJoints do
			local steerAngle = if joint:GetAttribute("Steers") then -steer * STEERING_LOCK else 0
			joint.Transform = CFrame.Angles(0, steerAngle, 0) * CFrame.Angles(wheelSpin, 0, 0)
		end

		-- Only accelerate and steer while the wheels are on the ground
		if not Workspace:Raycast(chassis.Position, -up * groundRay, rayParams) then
			return
		end

		local throttle = seat.ThrottleFloat
		if handbrake then
			forwardSpeed = approach(forwardSpeed, 0, CAR.HandbrakeDeceleration * dt)
		elseif throttle > 0 then
			if forwardSpeed < 0 then
				forwardSpeed = approach(forwardSpeed, 0, CAR.BrakeDeceleration * dt) -- rolling backwards: brake first
			else
				forwardSpeed = approach(forwardSpeed, topSpeed, acceleration * throttle * dt)
			end
		elseif throttle < 0 then
			if forwardSpeed > 0 then
				forwardSpeed = approach(forwardSpeed, 0, CAR.BrakeDeceleration * dt) -- moving forwards: brake first
			else
				forwardSpeed = approach(forwardSpeed, -reverseSpeed, acceleration * -throttle * dt)
			end
		else
			forwardSpeed = approach(forwardSpeed, 0, CAR.CoastDeceleration * dt)
		end

		-- Tyres grip the road, so cancel out any sideways sliding
		sideSpeed = approach(sideSpeed, 0, CAR.SideGrip * dt)
		chassis.AssemblyLinearVelocity = forward * forwardSpeed + right * sideSpeed + up * upSpeed

		-- Turn like a real car: tighter at low speed, no turning on the spot, never more than the tyres can grip
		local speed = math.abs(forwardSpeed)
		local maxTurnRate = math.min(CAR.MaxTurnRate, CAR.CorneringGrip / math.max(speed, 1))
		local turnRate = math.min(speed * math.tan(STEERING_LOCK) / wheelbase, maxTurnRate)
		local yaw = -steer * turnRate * math.sign(forwardSpeed)
		local spin = chassis.AssemblyAngularVelocity
		chassis.AssemblyAngularVelocity = spin - up * spin:Dot(up) + up * yaw
	end)
end

local function onCharacterAdded(character: Model)
	local humanoid = character:WaitForChild("Humanoid") :: Humanoid
	humanoid:GetPropertyChangedSignal("SeatPart"):Connect(function()
		stopDriving()
		local seat = humanoid.SeatPart
		-- Hide "Drive" and "Get in" prompts while you're sitting in a car, so they don't cover it
		ProximityPromptService.Enabled = seat == nil
		if seat and seat:IsA("VehicleSeat") then
			startDriving(seat)
		end
	end)
end

player.CharacterAdded:Connect(onCharacterAdded)
player.CharacterRemoving:Connect(function()
	stopDriving()
	ProximityPromptService.Enabled = true
end)
if player.Character then
	onCharacterAdded(player.Character)
end
]])
put(folder7, "LocalScript", "Hud", [[
-- The bar across the top of the screen while you play, laid out like Birmingham Vehicle Simulator:
--   top left: a Menu button next to Roblox's own buttons (asks before putting your vehicle away)
--   top right: settings, the shop and your cash (with a "+£100" pill when you earn money)
-- It also shows the server's pop-up messages.

local GuiService = game:GetService("GuiService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Ui = require(script.Parent:WaitForChild("Ui"))
local Format = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Format"))

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local returnRemote = remotes:WaitForChild("ReturnToMenu") :: RemoteEvent
local notifyRemote = remotes:WaitForChild("Notify") :: RemoteEvent

local C = Ui.Colours
local player = Players.LocalPlayer

local gui = Ui.screen("Hud", 5)

-- A round dark button or pill in the top bar
local function topButton(text: string, size: UDim2, parent: Instance): TextButton
	local button = Ui.button(text, "clear", { Size = size, TextSize = 16, Parent = parent })
	button.BackgroundColor3 = C.Panel
	button.BackgroundTransparency = 0.2
	Ui.corner(button, 22)
	return button
end

-- Top left, just right of Roblox's buttons (GuiService tells us where their space ends)
local menuButton = topButton("      Menu", UDim2.fromOffset(104, 44), gui)
-- Three short lines for the "menu" icon (the font doesn't have one)
for i = 0, 2 do
	Ui.make("Frame", {
		Position = UDim2.fromOffset(18, 15 + i * 6),
		Size = UDim2.fromOffset(16, 2),
		BackgroundColor3 = C.Text,
		BorderSizePixel = 0,
		Parent = menuButton,
	})
end
local function placeMenuButton()
	local inset = GuiService.TopbarInset
	local height = math.max(inset.Height, 44)
	menuButton.Position = UDim2.fromOffset(inset.Min.X + 8, (height - 44) / 2 + (if inset.Height > 0 then 0 else 12))
end
placeMenuButton()
GuiService:GetPropertyChangedSignal("TopbarInset"):Connect(placeMenuButton)

-- Top right
local topRight = Ui.make("Frame", {
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -12, 0, 8),
	Size = UDim2.fromOffset(0, 44),
	AutomaticSize = Enum.AutomaticSize.X,
	BackgroundTransparency = 1,
	Parent = gui,
})
Ui.make("UIListLayout", {
	FillDirection = Enum.FillDirection.Horizontal,
	HorizontalAlignment = Enum.HorizontalAlignment.Right,
	Padding = UDim.new(0, 8),
	SortOrder = Enum.SortOrder.LayoutOrder,
	Parent = topRight,
})
local settingsButton = topButton("⚙", UDim2.fromOffset(44, 44), topRight)
settingsButton.LayoutOrder = 1
settingsButton.TextSize = 20
local shopButton = topButton("🛒", UDim2.fromOffset(44, 44), topRight)
shopButton.LayoutOrder = 2
local cashPill = topButton("", UDim2.fromOffset(0, 44), topRight)
cashPill.LayoutOrder = 3
cashPill.AutomaticSize = Enum.AutomaticSize.X
cashPill.Visible = false -- hidden until their data has loaded
Ui.padding(cashPill, 16, 0)

-- Pop-up windows ------------------------------------------------------------------------------

local function dialog(title: string, width: number, height: number): (Frame, () -> ())
	local backdrop = Ui.make("TextButton", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.5,
		AutoButtonColor = false,
		Text = "",
		Visible = false,
		ZIndex = 10,
		Parent = gui,
	})
	local window = Ui.panel({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(width, height),
		ZIndex = 11,
		Parent = backdrop,
	})
	window.BackgroundTransparency = 0.04
	Ui.padding(window, 22, 18)
	local close = Ui.make("TextButton", {
		Size = UDim2.fromOffset(24, 24),
		BackgroundTransparency = 1,
		FontFace = Ui.font(Enum.FontWeight.SemiBold),
		TextSize = 18,
		TextColor3 = C.Text,
		Text = "×",
		ZIndex = 12,
		Parent = window,
	})
	Ui.label(title, 20, Enum.FontWeight.SemiBold, {
		Position = UDim2.fromOffset(34, 0),
		Size = UDim2.new(1, -34, 0, 24),
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 12,
		Parent = window,
	})
	local function hide()
		backdrop.Visible = false
	end
	close.Activated:Connect(hide)
	return window, function()
		backdrop.Visible = true
	end
end

-- "Return to the menu?"
local confirmBackdrop = Ui.make("Frame", {
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = Color3.new(0, 0, 0),
	BackgroundTransparency = 0.55,
	Visible = false,
	ZIndex = 10,
	Parent = gui,
})
local confirm = Ui.panel({
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(360, 150),
	ZIndex = 11,
	Parent = confirmBackdrop,
})
confirm.BackgroundTransparency = 0.04
Ui.padding(confirm, 20, 18)
Ui.label("Return to the menu?", 18, Enum.FontWeight.SemiBold, { Size = UDim2.new(1, 0, 0, 22), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 12, Parent = confirm })
Ui.label("Your vehicle will be put away. You can get it out again from the menu.", 13, Enum.FontWeight.Regular, {
	Position = UDim2.fromOffset(0, 28),
	Size = UDim2.new(1, 0, 0, 34),
	TextWrapped = true,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextYAlignment = Enum.TextYAlignment.Top,
	TextColor3 = C.Muted,
	ZIndex = 12,
	Parent = confirm,
})
local confirmButtons = Ui.make("Frame", { AnchorPoint = Vector2.new(1, 1), Position = UDim2.fromScale(1, 1), Size = UDim2.fromOffset(230, 38), BackgroundTransparency = 1, ZIndex = 12, Parent = confirm })
local stayButton = Ui.button("Stay", "dark", { Size = UDim2.new(0.38, -5, 1, 0), ZIndex = 12, Parent = confirmButtons })
local leaveButton = Ui.button("Return to menu", "light", { Position = UDim2.new(0.38, 5, 0, 0), Size = UDim2.new(0.62, -5, 1, 0), ZIndex = 12, Parent = confirmButtons })

menuButton.Activated:Connect(function()
	confirmBackdrop.Visible = true
end)
stayButton.Activated:Connect(function()
	confirmBackdrop.Visible = false
end)
leaveButton.Activated:Connect(function()
	confirmBackdrop.Visible = false
	returnRemote:FireServer()
	Ui.requestMenu()
end)

-- Settings
local settingsWindow, showSettings = dialog("Settings", 420, 260)
local settingRows = Ui.make("Frame", { Position = UDim2.fromOffset(0, 40), Size = UDim2.new(1, 0, 1, -40), BackgroundTransparency = 1, ZIndex = 12, Parent = settingsWindow })
Ui.make("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder, Parent = settingRows })

local function toggleRow(label: string, setting: string, order: number)
	local row = Ui.make("TextButton", {
		Size = UDim2.new(1, 0, 0, 46),
		BackgroundColor3 = C.Raised,
		BackgroundTransparency = 0.3,
		AutoButtonColor = false,
		Text = "",
		LayoutOrder = order,
		ZIndex = 12,
		Parent = settingRows,
	})
	Ui.corner(row, 10)
	Ui.label(label, 14, Enum.FontWeight.Medium, { Position = UDim2.fromOffset(14, 0), Size = UDim2.new(1, -80, 1, 0), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 13, Parent = row })
	local track = Ui.make("Frame", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -14, 0.5, 0), Size = UDim2.fromOffset(40, 22), BorderSizePixel = 0, ZIndex = 13, Parent = row })
	Ui.corner(track, 11)
	local knob = Ui.make("Frame", { AnchorPoint = Vector2.new(0, 0.5), Size = UDim2.fromOffset(18, 18), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, ZIndex = 14, Parent = track })
	Ui.corner(knob, 9)
	local function draw()
		local on = (Ui.settings :: any)[setting] == true
		track.BackgroundColor3 = if on then C.Green else Color3.fromRGB(70, 74, 84)
		knob.Position = if on then UDim2.new(1, -20, 0.5, 0) else UDim2.new(0, 2, 0.5, 0)
	end
	draw()
	row.Activated:Connect(function()
		Ui.setSetting(setting, not (Ui.settings :: any)[setting])
		draw()
	end)
end
toggleRow("Shadows", "Shadows", 1)
toggleRow("Show driving controls", "Controls", 2)
toggleRow("Turn the minimap with your car", "TurnMap", 3)

Ui.SettingChanged:Connect(function(name, value)
	if name == "Shadows" then
		Lighting.GlobalShadows = value -- only changes it on this device
	end
end)
settingsButton.Activated:Connect(showSettings)

-- The shop isn't open yet (roadmap step 13), but the button shows what's coming
local shopWindow, showShop = dialog("Shop", 420, 210)
Ui.label("Cash packs, game passes and redeem codes are coming soon.\n\nFor now, earn money by playing: everyone gets paid every few minutes.", 14, Enum.FontWeight.Regular, {
	Position = UDim2.fromOffset(0, 44),
	Size = UDim2.new(1, 0, 1, -44),
	TextWrapped = true,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextYAlignment = Enum.TextYAlignment.Top,
	TextColor3 = C.Muted,
	ZIndex = 12,
	Parent = shopWindow,
})
shopButton.Activated:Connect(showShop)
cashPill.Activated:Connect(showShop)

-- Cash -------------------------------------------------------------------------------------------

local function showGain(amount: number)
	local pill = Ui.label("+" .. Format.money(amount), 13, Enum.FontWeight.SemiBold, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -16, 0, 58),
		Size = UDim2.fromOffset(0, 24),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 0,
		BackgroundColor3 = Color3.fromRGB(55, 150, 85),
		Parent = gui,
	})
	pill.BackgroundTransparency = 0
	Ui.corner(pill, 12)
	Ui.padding(pill, 10, 0)
	local tween = TweenService:Create(pill, TweenInfo.new(1.6, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		Position = pill.Position + UDim2.fromOffset(0, 18),
		TextTransparency = 1,
		BackgroundTransparency = 1,
	})
	tween.Completed:Once(function()
		pill:Destroy()
	end)
	task.delay(1, function()
		tween:Play()
	end)
end

local lastCash: number? = nil
local function onCashChanged()
	local cash = player:GetAttribute("Cash")
	if typeof(cash) ~= "number" then
		return
	end
	if lastCash and cash > lastCash then
		showGain(cash - lastCash)
	end
	lastCash = cash
	cashPill.Text = "💷  " .. Format.money(cash)
	cashPill.Visible = true
end
player:GetAttributeChangedSignal("Cash"):Connect(onCashChanged)
onCashChanged()

-- Hide the HUD while the menu is open
Ui.MenuChanged:Connect(function(open)
	gui.Enabled = not open
	if open then
		confirmBackdrop.Visible = false
	end
end)
gui.Enabled = not Ui.menuOpen

notifyRemote.OnClientEvent:Connect(function(title, body, colour)
	if typeof(title) == "string" then
		Ui.toast(title, if typeof(body) == "string" then body else nil, Ui.colourNamed(if typeof(colour) == "string" then colour else nil))
	end
end)
]])
put(folder7, "LocalScript", "MapLife", [[
-- Little bits of movement in the town, done on your own device so they're smooth:
--   the big wheel on the south bank turns slowly
--   the amber globes on zebra crossings flash

local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local WHEEL_SPEED = math.rad(1.2) -- radians per second: one turn takes about five minutes
local GLOBE_ON = Color3.fromRGB(255, 160, 20)
local GLOBE_OFF = Color3.fromRGB(120, 80, 30)

-- Remember where each wheel started, so it turns around its hub rather than drifting
local wheels: { [Model]: CFrame } = {}
local function addWheel(instance: Instance)
	if instance:IsA("Model") then
		wheels[instance] = instance:GetPivot()
	end
end
CollectionService:GetInstanceAddedSignal("BigWheelRotor"):Connect(addWheel)
CollectionService:GetInstanceRemovedSignal("BigWheelRotor"):Connect(function(instance)
	if instance:IsA("Model") then
		wheels[instance] = nil
	end
end)
for _, instance in CollectionService:GetTagged("BigWheelRotor") do
	addWheel(instance)
end

local elapsed = 0
local globesLit = true
RunService.Heartbeat:Connect(function(dt)
	elapsed += dt

	for wheel, start in wheels do
		local hub = wheel:GetAttribute("Hub")
		if typeof(hub) == "Vector3" and wheel.Parent then
			-- Spin around the hub's axle, which points north-south (the Z axis)
			local turn = CFrame.new(hub) * CFrame.Angles(0, 0, elapsed * WHEEL_SPEED) * CFrame.new(-hub)
			wheel:PivotTo(turn * start)
		end
	end

	local lit = elapsed % 1 < 0.5
	if lit ~= globesLit then
		globesLit = lit
		for _, globe in CollectionService:GetTagged("BelishaGlobe") do
			if globe:IsA("BasePart") then
				globe.Color = if lit then GLOBE_ON else GLOBE_OFF
				globe.Material = if lit then Enum.Material.Neon else Enum.Material.SmoothPlastic
			end
		end
	end
end)
]])
put(folder7, "LocalScript", "Menu", [[
-- The menus you see when you join or press Menu: the main menu (Drive / Spawn / Close), the team picker,
-- the vehicle picker (filmed live at your team's depot) and customising your paint.
-- Laid out like Birmingham Vehicle Simulator (see docs/BVS-NOTES.md), with our own London look and names.

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SocialService = game:GetService("SocialService")
local StarterGui = game:GetService("StarterGui")
local Teams = game:GetService("Teams")
local Workspace = game:GetService("Workspace")

local Ui = require(script.Parent:WaitForChild("Ui"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Format = require(Shared:WaitForChild("Format"))
local Vehicles = require(Shared:WaitForChild("Vehicles"))

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local chooseTeamRemote = remotes:WaitForChild("ChooseTeam") :: RemoteEvent
local buyRemote = remotes:WaitForChild("BuyVehicle") :: RemoteFunction
local setPaintRemote = remotes:WaitForChild("SetPaint") :: RemoteEvent
local spawnRemote = remotes:WaitForChild("SpawnVehicle") :: RemoteEvent
local spawnOnFootRemote = remotes:WaitForChild("SpawnOnFoot") :: RemoteEvent
local vehicleModels = ReplicatedStorage:WaitForChild("VehicleModels")
local mapInfo = ReplicatedStorage:WaitForChild("MapInfo", 15)

type Vehicle = Vehicles.Vehicle

local C = Ui.Colours
local player = Players.LocalPlayer
local camera = Workspace.CurrentCamera

local gui = Ui.screen("Menu", 10)
gui.Enabled = false

-- Blurs the world behind the main menu and team picker (only on this device)
local blur = Instance.new("BlurEffect")
blur.Name = "MenuBlur"
blur.Size = 0
blur.Parent = Lighting

local shade = Ui.make("Frame", {
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = Color3.new(0, 0, 0),
	BackgroundTransparency = 0.45,
	BorderSizePixel = 0,
	Parent = gui,
})

-- Player controls, switched off while the menu is open
local controls: any = nil
task.spawn(function()
	local ok, playerModule = pcall(function(): any
		local module = player:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule")
		return (require :: any)(module) -- Roblox's own module, so the type checker can't see inside it
	end)
	if ok and playerModule then
		controls = playerModule:GetControls()
		if Ui.menuOpen then
			controls:Disable()
		end
	end
end)

-- The menu flies the camera to fixed shots
local cameraTarget: CFrame? = nil
RunService:BindToRenderStep("MenuCamera", Enum.RenderPriority.Camera.Value + 1, function()
	if cameraTarget then
		camera.CameraType = Enum.CameraType.Scriptable
		camera.CFrame = camera.CFrame:Lerp(cameraTarget, 0.12)
	end
end)

local function mapSetting(name: string): any
	return if mapInfo then mapInfo:GetAttribute(name) else nil
end

-- Ask the server to send this player the parts around a spot, in case the place streams the map in
local function streamAround(position: Vector3)
	task.spawn(function()
		pcall(function()
			player:RequestStreamAroundAsync(position)
		end)
	end)
end

local function flyTo(shot: CFrame, snap: boolean?)
	streamAround(shot.Position)
	cameraTarget = shot
	if snap then
		camera.CameraType = Enum.CameraType.Scriptable
		camera.CFrame = shot
	end
end

local function menuShot(): CFrame
	local shot = mapSetting("MenuCamera")
	return if typeof(shot) == "CFrame" then shot else camera.CFrame
end

local function isOwned(vehicle: Vehicle): boolean
	return vehicle.price == 0 or player:GetAttribute("Owned_" .. vehicle.id) == true
end

local function paintOf(vehicle: Vehicle): Color3
	local picked = player:GetAttribute("Paint_" .. vehicle.id)
	return Vehicles.paintColour(vehicle, if typeof(picked) == "number" then picked else nil)
end

local function cash(): number
	local value = player:GetAttribute("Cash")
	return if typeof(value) == "number" then value else 0
end

local function recolour(model: Instance, colour: Color3)
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") and descendant:GetAttribute("Paint") then
			descendant.Color = colour
		end
	end
end

-- A vehicle in a little 3D window, seen from the front left like a showroom photo
local function showVehicle(viewport: ViewportFrame, vehicleId: string, paint: Color3?)
	viewport:ClearAllChildren()
	local source = vehicleModels:FindFirstChild(vehicleId)
	if not source then
		return
	end
	local model = source:Clone() :: Model
	if paint then
		recolour(model, paint)
	end
	model:PivotTo(CFrame.new())
	model.Parent = viewport
	local size = model:GetExtentsSize()
	local viewCamera = Instance.new("Camera")
	viewCamera.FieldOfView = 30
	viewCamera.Parent = viewport
	viewport.CurrentCamera = viewCamera
	local focus = Vector3.new(0, size.Y * 0.42, 0)
	local direction = Vector3.new(-0.8, 0.42, -1).Unit
	local distance = size.Z * 1.55 + 6
	viewCamera.CFrame = CFrame.lookAt(focus + direction * distance, focus)
end

local function viewport(props: { [string]: any }): ViewportFrame
	local frame = Ui.make("ViewportFrame", props)
	frame.BackgroundColor3 = props.BackgroundColor3 or Color3.fromRGB(8, 9, 12)
	frame.Ambient = Color3.fromRGB(165, 165, 172)
	frame.LightColor = Color3.new(1, 1, 1)
	frame.LightDirection = Vector3.new(-1, -1.2, -0.4)
	return frame
end

local function backButton(parent: Instance, text: string, onClick: () -> ())
	local button = Ui.button("‹  " .. text, "dark", {
		Position = UDim2.fromOffset(24, 72),
		Size = UDim2.fromOffset(0, 40),
		AutomaticSize = Enum.AutomaticSize.X,
		TextSize = 15,
		Parent = parent,
	})
	Ui.padding(button, 16, 0)
	button.Activated:Connect(onClick)
end

local function cashPill(parent: Instance): TextLabel
	local pill = Ui.panel({
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -24, 0, 72),
		Size = UDim2.fromOffset(0, 40),
		AutomaticSize = Enum.AutomaticSize.X,
		Parent = parent,
	})
	Ui.padding(pill, 16, 0)
	return Ui.label("", 16, Enum.FontWeight.SemiBold, { Size = UDim2.fromScale(0, 1), AutomaticSize = Enum.AutomaticSize.X, Parent = pill })
end

-- Screens ---------------------------------------------------------------------------------

local screens: { [string]: Frame } = {}
local function screen(name: string): Frame
	local frame = Ui.make("Frame", { Name = name, Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false, Parent = gui })
	screens[name] = frame
	return frame
end

local mainScreen = screen("Main")
local teamScreen = screen("Teams")
local pickerScreen = screen("Picker")

local openMenu: () -> ()
local closeMenu: () -> ()
local showTeams: () -> ()
local showPicker: (team: string) -> ()

local function showScreen(name: string)
	for screenName, frame in screens do
		frame.Visible = screenName == name
	end
	local blurred = name ~= "Picker"
	shade.Visible = blurred
	blur.Size = if blurred then 18 else 0
end

-- Main menu: logo, three big cards and two wide buttons ------------------------------------

local logo = Ui.make("Frame", {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0.15, 0),
	Size = UDim2.fromOffset(560, 116),
	BackgroundTransparency = 1,
	Parent = mainScreen,
})
for i, stripe in { { icon = "🚶", colour = C.Walk }, { icon = "🚗", colour = C.Blue }, { icon = "🚌", colour = C.Red } } do
	local bar = Ui.make("Frame", {
		Position = UDim2.fromOffset(18 - (i - 1) * 9, (i - 1) * 39),
		Size = UDim2.fromOffset(150, 34),
		BackgroundColor3 = stripe.colour,
		BorderSizePixel = 0,
		Parent = logo,
	})
	Ui.corner(bar, 5)
	Ui.label(stripe.icon, 20, nil, { Size = UDim2.fromScale(1, 1), Parent = bar })
end
Ui.label("LONDON", 76, Enum.FontWeight.Bold, {
	Position = UDim2.fromOffset(186, -8),
	Size = UDim2.fromOffset(380, 80),
	TextXAlignment = Enum.TextXAlignment.Left,
	Parent = logo,
})
Ui.label("S I M U L A T O R", 27, Enum.FontWeight.Medium, {
	Position = UDim2.fromOffset(190, 76),
	Size = UDim2.fromOffset(380, 34),
	TextXAlignment = Enum.TextXAlignment.Left,
	Parent = logo,
})

local cardRow = Ui.make("Frame", {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0.44, 0),
	Size = UDim2.fromOffset(150 * 3 + 20 * 2, 180),
	BackgroundTransparency = 1,
	Parent = mainScreen,
})
Ui.make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 20), SortOrder = Enum.SortOrder.LayoutOrder, Parent = cardRow })

local function bigCard(icon: string, text: string, colour: Color3, order: number, onClick: () -> ())
	local card = Ui.make("TextButton", {
		Size = UDim2.fromOffset(150, 180),
		BackgroundColor3 = C.Panel,
		BackgroundTransparency = 0.15,
		AutoButtonColor = false,
		Text = "",
		LayoutOrder = order,
		Parent = cardRow,
	})
	Ui.corner(card, 14)
	Ui.outline(card)
	Ui.label(icon, 40, nil, { Position = UDim2.fromOffset(0, 36), Size = UDim2.new(1, 0, 0, 50), TextColor3 = colour, Parent = card })
	Ui.label(text, 20, Enum.FontWeight.SemiBold, { Position = UDim2.fromOffset(0, 104), Size = UDim2.new(1, 0, 0, 26), Parent = card })
	local underline = Ui.make("Frame", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -12),
		Size = UDim2.fromOffset(56, 4),
		BackgroundColor3 = colour,
		BorderSizePixel = 0,
		Parent = card,
	})
	Ui.corner(underline, 2)
	card.MouseEnter:Connect(function()
		card.BackgroundColor3 = C.Raised
	end)
	card.MouseLeave:Connect(function()
		card.BackgroundColor3 = C.Panel
	end)
	card.Activated:Connect(onClick)
end

bigCard("🚗", "Drive", C.Blue, 1, function()
	showTeams()
end)
bigCard("🚶", "Spawn", C.Walk, 2, function()
	spawnOnFootRemote:FireServer()
	closeMenu()
end)
bigCard("×", "Close", C.Red, 3, function()
	closeMenu()
end)

local wideRow = Ui.make("Frame", {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0.44, 200),
	Size = UDim2.fromOffset(490, 50),
	BackgroundTransparency = 1,
	Parent = mainScreen,
})
local avatarButton = Ui.button("👤  Change avatar", "dark", { Size = UDim2.new(0.5, -8, 1, 0), Parent = wideRow })
avatarButton.Activated:Connect(function()
	Ui.toast("Coming soon", "Changing your avatar in the game is on the way. For now, change it on the Roblox website.", C.Blue)
end)
local inviteButton = Ui.button("➕  Invite friends", "dark", { Position = UDim2.new(0.5, 8, 0, 0), Size = UDim2.new(0.5, -8, 1, 0), Parent = wideRow })
inviteButton.Activated:Connect(function()
	local ok = pcall(function()
		SocialService:PromptGameInvite(player)
	end)
	if not ok then
		Ui.toast("Invites don't work here", "Inviting friends works once the game is published and you're playing it on Roblox.", C.Red)
	end
end)

-- Team picker -------------------------------------------------------------------------------

backButton(teamScreen, "Back", function()
	showScreen("Main")
end)
Ui.label("Choose your team", 46, Enum.FontWeight.Regular, {
	Position = UDim2.new(0.12, 0, 0, 120),
	Size = UDim2.fromOffset(700, 56),
	TextXAlignment = Enum.TextXAlignment.Left,
	Parent = teamScreen,
})
Ui.label("Pick a service and hit the road", 20, Enum.FontWeight.Regular, {
	Position = UDim2.new(0.12, 0, 0, 178),
	Size = UDim2.fromOffset(700, 28),
	TextXAlignment = Enum.TextXAlignment.Left,
	TextColor3 = C.Muted,
	Parent = teamScreen,
})

local teamRow = Ui.make("Frame", {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 236),
	Size = UDim2.new(0.76, 0, 0, 440),
	BackgroundTransparency = 1,
	Parent = teamScreen,
})
Ui.make("UIListLayout", {
	FillDirection = Enum.FillDirection.Horizontal,
	Padding = UDim.new(0, 24),
	HorizontalAlignment = Enum.HorizontalAlignment.Center,
	SortOrder = Enum.SortOrder.LayoutOrder,
	Parent = teamRow,
})

local memberStrips: { [string]: { count: TextLabel, faces: Frame } } = {}
local headshots: { [number]: string } = {}

for order, info in Config.Teams do
	local column = Ui.make("Frame", { Size = UDim2.new(1 / 3, -16, 1, 0), BackgroundTransparency = 1, LayoutOrder = order, Parent = teamRow })
	local card = Ui.make("TextButton", {
		Size = UDim2.new(1, 0, 0, 330),
		BackgroundColor3 = Color3.fromRGB(10, 11, 14),
		AutoButtonColor = false,
		Text = "",
		Parent = column,
	})
	Ui.corner(card, 16)
	Ui.outline(card)
	local window = viewport({ Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(14, 15, 19), Parent = card })
	Ui.corner(window, 16)
	showVehicle(window, info.showcase, nil)
	-- Fade to black at the bottom so the words are easy to read
	local fade = Ui.make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0), BorderSizePixel = 0, Parent = card })
	Ui.corner(fade, 16)
	Ui.make("UIGradient", {
		Rotation = 90,
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.55, 1), NumberSequenceKeypoint.new(1, 0.1) }),
		Parent = fade,
	})
	Ui.label(info.icon .. "  " .. info.name, 30, Enum.FontWeight.SemiBold, {
		Position = UDim2.new(0, 20, 1, -86),
		Size = UDim2.new(1, -40, 0, 36),
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = card,
	})
	Ui.label(info.description, 14, Enum.FontWeight.Regular, {
		Position = UDim2.new(0, 20, 1, -46),
		Size = UDim2.new(1, -40, 0, 34),
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextColor3 = Color3.fromRGB(215, 218, 225),
		Parent = card,
	})
	local accent = Ui.make("Frame", { Size = UDim2.new(1, 0, 0, 4), BackgroundColor3 = info.colour, BorderSizePixel = 0, Parent = card })
	Ui.corner(accent, 2)
	card.MouseEnter:Connect(function()
		accent.Size = UDim2.new(1, 0, 0, 6)
	end)
	card.MouseLeave:Connect(function()
		accent.Size = UDim2.new(1, 0, 0, 4)
	end)
	card.Activated:Connect(function()
		chooseTeamRemote:FireServer(info.name)
		showPicker(info.name)
	end)

	local members = Ui.panel({ Position = UDim2.fromOffset(0, 342), Size = UDim2.new(1, 0, 0, 88), Parent = column })
	Ui.padding(members, 16, 12)
	Ui.label("Current members", 14, Enum.FontWeight.Medium, { Size = UDim2.new(1, 0, 0, 18), TextXAlignment = Enum.TextXAlignment.Left, Parent = members })
	local count = Ui.label("0 players", 13, Enum.FontWeight.Regular, { Size = UDim2.new(1, 0, 0, 18), TextXAlignment = Enum.TextXAlignment.Right, TextColor3 = C.Muted, Parent = members })
	local faces = Ui.make("Frame", { Position = UDim2.fromOffset(0, 28), Size = UDim2.new(1, 0, 0, 36), BackgroundTransparency = 1, Parent = members })
	Ui.make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder, Parent = faces })
	memberStrips[info.name] = { count = count, faces = faces }
end

local function headshot(userId: number): string
	if headshots[userId] then
		return headshots[userId]
	end
	local ok, image = pcall(function()
		return Players:GetUserThumbnailAsync(userId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size48x48)
	end)
	headshots[userId] = if ok then image else ""
	return headshots[userId]
end

local function refreshMembers()
	for teamName, strip in memberStrips do
		local team = Teams:FindFirstChild(teamName) :: Team?
		local list: { Player } = if team then team:GetPlayers() else {}
		strip.count.Text = `{#list} {if #list == 1 then "player" else "players"}`
		for _, child in strip.faces:GetChildren() do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		for index, member in list do
			if index > 6 then
				local more = Ui.label(`+{#list - 6}`, 13, Enum.FontWeight.SemiBold, { Size = UDim2.fromOffset(36, 36), BackgroundTransparency = 0, BackgroundColor3 = C.Raised, LayoutOrder = 7, Parent = strip.faces })
				more.BackgroundTransparency = 0
				Ui.corner(more, 18)
				break
			end
			local face = Ui.make("ImageLabel", { Size = UDim2.fromOffset(36, 36), BackgroundColor3 = C.Raised, LayoutOrder = index, Parent = strip.faces })
			Ui.corner(face, 18)
			task.spawn(function()
				face.Image = headshot(member.UserId)
			end)
		end
	end
end

showTeams = function()
	showScreen("Teams")
	flyTo(menuShot())
	refreshMembers()
end

-- Vehicle picker ---------------------------------------------------------------------------

local pickerTeam = "Car"
local pickerFilter = "All"
local selectedId: string? = nil
local previewModel: Model? = nil
local customising = false

backButton(pickerScreen, "Back to teams", function()
	showTeams()
end)
local pickerCash = cashPill(pickerScreen)

-- Darken the bottom of the screen behind the picker
local bottomFade = Ui.make("Frame", {
	AnchorPoint = Vector2.new(0, 1),
	Position = UDim2.fromScale(0, 1),
	Size = UDim2.new(1, 0, 0, 340),
	BackgroundColor3 = Color3.new(0, 0, 0),
	BorderSizePixel = 0,
	ZIndex = 0,
	Parent = pickerScreen,
})
Ui.make("UIGradient", {
	Rotation = 90,
	Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0.25) }),
	Parent = bottomFade,
})

local nameLabel = Ui.label("", 40, Enum.FontWeight.Bold, {
	AnchorPoint = Vector2.new(0, 1),
	Position = UDim2.new(0, 28, 1, -236),
	Size = UDim2.new(0.5, 0, 0, 48),
	TextXAlignment = Enum.TextXAlignment.Left,
	Parent = pickerScreen,
})
local statusLabel = Ui.label("", 15, Enum.FontWeight.Medium, {
	AnchorPoint = Vector2.new(0, 1),
	Position = UDim2.new(0, 30, 1, -212),
	Size = UDim2.new(0.5, 0, 0, 20),
	TextXAlignment = Enum.TextXAlignment.Left,
	RichText = true,
	Parent = pickerScreen,
})

local actionRow = Ui.make("Frame", {
	AnchorPoint = Vector2.new(1, 1),
	Position = UDim2.new(1, -28, 1, -214),
	Size = UDim2.fromOffset(360, 48),
	BackgroundTransparency = 1,
	Parent = pickerScreen,
})
local customiseButton = Ui.button("Customise", "dark", { Size = UDim2.new(0.42, -6, 1, 0), Parent = actionRow })
local mainButton = Ui.button("Spawn", "light", { Position = UDim2.new(0.42, 6, 0, 0), Size = UDim2.new(0.58, -6, 1, 0), Parent = actionRow })

-- The list of vehicles along the bottom, with tabs above it
local listArea = Ui.make("Frame", {
	AnchorPoint = Vector2.new(0, 1),
	Position = UDim2.new(0, 0, 1, -16),
	Size = UDim2.new(1, 0, 0, 186),
	BackgroundTransparency = 1,
	Parent = pickerScreen,
})
local tabRow = Ui.make("Frame", { Position = UDim2.fromOffset(28, 0), Size = UDim2.new(1, -56, 0, 26), BackgroundTransparency = 1, Parent = listArea })
Ui.make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 22), SortOrder = Enum.SortOrder.LayoutOrder, Parent = tabRow })
local ownedCount = Ui.label("", 13, Enum.FontWeight.Regular, {
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -28, 0, 2),
	Size = UDim2.fromOffset(240, 20),
	TextXAlignment = Enum.TextXAlignment.Right,
	TextColor3 = C.Muted,
	RichText = true,
	Parent = listArea,
})
local carousel = Ui.make("ScrollingFrame", {
	Position = UDim2.fromOffset(0, 40),
	Size = UDim2.new(1, 0, 0, 146),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	ScrollingDirection = Enum.ScrollingDirection.X,
	AutomaticCanvasSize = Enum.AutomaticSize.X,
	CanvasSize = UDim2.new(),
	ScrollBarThickness = 4,
	Parent = listArea,
})
Ui.padding(carousel, 28, 6)
Ui.make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 12), SortOrder = Enum.SortOrder.LayoutOrder, Parent = carousel })

-- The customise sheet, which takes the list's place
local sheet = Ui.panel({
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -16),
	Size = UDim2.new(1, -56, 0, 186),
	Visible = false,
	Parent = pickerScreen,
})
Ui.padding(sheet, 20, 16)
Ui.label("Customise", 20, Enum.FontWeight.SemiBold, { Size = UDim2.fromOffset(300, 24), TextXAlignment = Enum.TextXAlignment.Left, Parent = sheet })
local sheetSubtitle = Ui.label("", 13, Enum.FontWeight.Regular, {
	Position = UDim2.fromOffset(0, 26),
	Size = UDim2.fromOffset(500, 18),
	TextXAlignment = Enum.TextXAlignment.Left,
	TextColor3 = C.Muted,
	Parent = sheet,
})
Ui.label("Body colour", 14, Enum.FontWeight.SemiBold, { Position = UDim2.fromOffset(0, 58), Size = UDim2.fromOffset(200, 18), TextXAlignment = Enum.TextXAlignment.Left, Parent = sheet })
local swatches = Ui.make("ScrollingFrame", {
	Position = UDim2.fromOffset(0, 86),
	Size = UDim2.new(1, 0, 0, 64),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	ScrollingDirection = Enum.ScrollingDirection.X,
	AutomaticCanvasSize = Enum.AutomaticSize.X,
	CanvasSize = UDim2.new(),
	ScrollBarThickness = 3,
	Parent = sheet,
})
Ui.padding(swatches, 4, 4)
Ui.make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder, Parent = swatches })
local fixedNote = Ui.label("This vehicle's livery can't be changed.", 14, Enum.FontWeight.Regular, {
	Position = UDim2.fromOffset(0, 96),
	Size = UDim2.fromOffset(500, 20),
	TextXAlignment = Enum.TextXAlignment.Left,
	TextColor3 = C.Muted,
	Visible = false,
	Parent = sheet,
})
local sheetButtons = Ui.make("Frame", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 0), Size = UDim2.fromOffset(330, 42), BackgroundTransparency = 1, Parent = sheet })
local resetButton = Ui.button("Reset", "dark", { Size = UDim2.new(0.4, -6, 1, 0), Parent = sheetButtons })
local doneButton = Ui.button("Back to vehicles", "light", { Position = UDim2.new(0.4, 6, 0, 0), Size = UDim2.new(0.6, -6, 1, 0), Parent = sheetButtons })

local refreshPicker: () -> ()

local function selectedVehicle(): Vehicle?
	return if selectedId then Vehicles.ById[selectedId] else nil
end

-- Puts the selected vehicle at the depot's display spot and points the camera at it
local function showPreview(vehicle: Vehicle)
	if previewModel then
		previewModel:Destroy()
		previewModel = nil
	end
	local source = vehicleModels:FindFirstChild(vehicle.id)
	if not source then
		return
	end
	local spot = mapSetting("Showroom_" .. pickerTeam)
	if typeof(spot) ~= "CFrame" then
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		spot = if root then root.CFrame * CFrame.new(0, -3, -20) else CFrame.new(0, 0.1, 0)
	end
	local model = source:Clone() :: Model
	recolour(model, paintOf(vehicle))
	model:PivotTo(spot)
	model.Parent = Workspace
	previewModel = model

	local size = model:GetExtentsSize()
	local length = math.max(size.Z, size.X)
	local focus = spot.Position + Vector3.new(0, size.Y * 0.38, 0)
	local offset = spot.LookVector * (length * 0.75 + 5) - spot.RightVector * (length * 0.62 + 4) + Vector3.new(0, size.Y * 0.35 + 2, 0)
	flyTo(CFrame.lookAt(focus + offset, focus - Vector3.new(0, size.Y * 0.25, 0)))
end

local function selectVehicle(vehicleId: string)
	selectedId = vehicleId
	local vehicle = Vehicles.ById[vehicleId]
	if vehicle then
		showPreview(vehicle)
	end
	refreshPicker()
end

local function vehicleCard(vehicle: Vehicle, order: number)
	local owned = isOwned(vehicle)
	local card = Ui.make("TextButton", {
		Size = UDim2.fromOffset(150, 132),
		BackgroundColor3 = C.Panel,
		BackgroundTransparency = 0.1,
		AutoButtonColor = false,
		Text = "",
		LayoutOrder = order,
		Parent = carousel,
	})
	Ui.corner(card, 12)
	if vehicle.id == selectedId then
		Ui.make("UIStroke", { ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Color = Color3.new(1, 1, 1), Thickness = 2, Parent = card })
	else
		Ui.outline(card)
	end
	local window = viewport({ Position = UDim2.fromOffset(6, 6), Size = UDim2.new(1, -12, 0, 88), Parent = card })
	Ui.corner(window, 9)
	showVehicle(window, vehicle.id, paintOf(vehicle))
	if owned then
		local badge = Ui.label("✓ Owned", 11, Enum.FontWeight.SemiBold, {
			Position = UDim2.fromOffset(12, 12),
			Size = UDim2.fromOffset(62, 20),
			BackgroundTransparency = 0,
			BackgroundColor3 = Color3.fromRGB(60, 160, 90),
			Parent = card,
		})
		badge.BackgroundTransparency = 0
		Ui.corner(badge, 6)
	else
		local price = Ui.label(Format.money(vehicle.price), 12, Enum.FontWeight.SemiBold, {
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -12, 0, 72),
			Size = UDim2.fromOffset(80, 18),
			TextXAlignment = Enum.TextXAlignment.Right,
			Parent = card,
		})
		price.TextStrokeTransparency = 0.5
	end
	Ui.label(vehicle.name .. (if vehicle.electric then " ⚡" else ""), 13, Enum.FontWeight.SemiBold, {
		Position = UDim2.fromOffset(10, 100),
		Size = UDim2.new(1, -20, 0, 22),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = card,
	})
	card.Activated:Connect(function()
		selectVehicle(vehicle.id)
	end)
end

local function tab(text: string, filter: string, count: number, order: number)
	local active = filter == pickerFilter
	local button = Ui.make("TextButton", {
		Size = UDim2.fromScale(0, 1),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 1,
		FontFace = Ui.font(if active then Enum.FontWeight.SemiBold else Enum.FontWeight.Regular),
		TextSize = 14,
		TextColor3 = if active then C.Text else C.Muted,
		RichText = true,
		Text = `{text}  <font color="#8c919c">{count}</font>`,
		LayoutOrder = order,
		Parent = tabRow,
	})
	if active then
		Ui.make("Frame", {
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.new(0, 0, 1, 2),
			Size = UDim2.new(1, 0, 0, 2),
			BackgroundColor3 = C.Text,
			BorderSizePixel = 0,
			Parent = button,
		})
	end
	button.Activated:Connect(function()
		pickerFilter = filter
		refreshPicker()
	end)
end

local function refreshSwatches(vehicle: Vehicle)
	for _, child in swatches:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	swatches.Visible = not vehicle.fixedPaint
	fixedNote.Visible = vehicle.fixedPaint == true
	resetButton.Visible = not vehicle.fixedPaint
	if vehicle.fixedPaint then
		return
	end
	local picked = player:GetAttribute("Paint_" .. vehicle.id)
	local current = if typeof(picked) == "number" then picked else vehicle.paint
	for index, paint in Vehicles.Paints do
		local swatch = Ui.make("TextButton", {
			Size = UDim2.fromOffset(48, 48),
			BackgroundColor3 = paint.colour,
			AutoButtonColor = false,
			Text = "",
			LayoutOrder = index,
			Parent = swatches,
		})
		Ui.corner(swatch, 10)
		Ui.make("UIStroke", {
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
			Color = Color3.new(1, 1, 1),
			Thickness = if index == current then 3 else 1,
			Transparency = if index == current then 0 else 0.8,
			Parent = swatch,
		})
		swatch.Activated:Connect(function()
			setPaintRemote:FireServer(vehicle.id, index)
			if previewModel then
				recolour(previewModel, paint.colour)
			end
		end)
	end
end

refreshPicker = function()
	pickerCash.Text = "💷  " .. Format.money(cash())
	local all = Vehicles.forTeam(pickerTeam)
	local ownedTotal = 0
	for _, vehicle in all do
		if isOwned(vehicle) then
			ownedTotal += 1
		end
	end

	for _, child in tabRow:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	tab("All", "All", #all, 1)
	tab("Owned", "Owned", ownedTotal, 2)
	tab("Not owned", "NotOwned", #all - ownedTotal, 3)
	ownedCount.Text = `Vehicles owned  <b><font color="#ffffff">{ownedTotal} / {#all}</font></b>`

	for _, child in carousel:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	for order, vehicle in all do
		local owned = isOwned(vehicle)
		if pickerFilter == "All" or (pickerFilter == "Owned" and owned) or (pickerFilter == "NotOwned" and not owned) then
			vehicleCard(vehicle, order)
		end
	end

	local vehicle = selectedVehicle()
	if not vehicle then
		return
	end
	local owned = isOwned(vehicle)
	nameLabel.Text = vehicle.name
	local details = {}
	table.insert(details, if owned then `<font color="#5fd27d">Owned</font>` else Format.money(vehicle.price))
	if vehicle.electric then
		table.insert(details, "⚡ Electric")
	end
	table.insert(details, `Top speed {math.floor(vehicle.topSpeed * Config.MphPerStudPerSecond + 0.5)} mph`)
	statusLabel.Text = table.concat(details, "   ·   ")
	mainButton.Text = if owned then "Spawn" else `Buy  ·  {Format.money(vehicle.price)}`
	customiseButton.TextTransparency = if owned then 0 else 0.6
	sheetSubtitle.Text = `{vehicle.name}  ·  Every pick saves straight away`
	if customising then
		refreshSwatches(vehicle)
	end
end

local function setCustomising(on: boolean)
	customising = on
	sheet.Visible = on
	listArea.Visible = not on
	actionRow.Visible = not on
	local vehicle = selectedVehicle()
	if on and vehicle then
		refreshSwatches(vehicle)
	end
end

customiseButton.Activated:Connect(function()
	local vehicle = selectedVehicle()
	if vehicle and isOwned(vehicle) then
		setCustomising(true)
	elseif vehicle then
		Ui.toast("Buy it first", `You can customise the {vehicle.name} once it's yours.`, C.Blue)
	end
end)
doneButton.Activated:Connect(function()
	setCustomising(false)
end)
resetButton.Activated:Connect(function()
	local vehicle = selectedVehicle()
	if vehicle then
		setPaintRemote:FireServer(vehicle.id, nil)
		if previewModel then
			recolour(previewModel, Vehicles.paintColour(vehicle, nil))
		end
	end
end)

local spawning = false
mainButton.Activated:Connect(function()
	local vehicle = selectedVehicle()
	if not vehicle or spawning then
		return
	end
	if not isOwned(vehicle) then
		local ok, message = buyRemote:InvokeServer(vehicle.id)
		Ui.toast(if ok then "Bought!" else "Can't buy that yet", message, if ok then C.Green else C.Red)
		refreshPicker()
		return
	end

	spawning = true
	mainButton.Text = "Spawning…"
	spawnRemote:FireServer(vehicle.id)
	-- Close the menu as soon as we're sitting in the new vehicle
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local started = os.clock()
	while os.clock() - started < 6 do
		local seat = humanoid and humanoid.SeatPart
		if seat and seat:IsA("VehicleSeat") then
			spawning = false
			closeMenu()
			return
		end
		task.wait(0.1)
	end
	spawning = false
	refreshPicker()
	Ui.toast("Couldn't get your vehicle out", "Wait a moment and try again.", C.Red)
end)

showPicker = function(team: string)
	pickerTeam = team
	pickerFilter = "All"
	setCustomising(false)
	local list = Vehicles.forTeam(team)
	if not selectedId or not Vehicles.ById[selectedId] or Vehicles.ById[selectedId].team ~= team then
		selectedId = if list[1] then list[1].id else nil
	end
	showScreen("Picker")
	local vehicle = selectedVehicle()
	if vehicle then
		local spot = mapSetting("Showroom_" .. team)
		if typeof(spot) == "CFrame" then
			-- Jump straight there: the world might not have loaded around the depot yet
			streamAround(spot.Position)
		end
		showPreview(vehicle)
	end
	refreshPicker()
end

player.AttributeChanged:Connect(function()
	if gui.Enabled and screens.Picker.Visible then
		refreshPicker()
	end
end)

-- Opening and closing ------------------------------------------------------------------------

-- Roblox's own player list sits where our cash goes, so hide it while the menu is open
local function showPlayerList(show: boolean)
	pcall(function()
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, show)
	end)
end

openMenu = function()
	Ui.setMenuOpen(true)
	showPlayerList(false)
	gui.Enabled = true
	if controls then
		controls:Disable()
	end
	showScreen("Main")
	flyTo(menuShot(), true)
end

closeMenu = function()
	gui.Enabled = false
	blur.Size = 0
	if previewModel then
		previewModel:Destroy()
		previewModel = nil
	end
	cameraTarget = nil
	camera.CameraType = Enum.CameraType.Custom
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		camera.CameraSubject = humanoid
	end
	if controls then
		controls:Enable()
	end
	showPlayerList(true)
	Ui.setMenuOpen(false)
end

Ui.MenuRequested:Connect(openMenu)

-- Teams can be joined and left while the team picker is open, so keep the member lists fresh
task.spawn(function()
	while true do
		task.wait(3)
		if gui.Enabled and screens.Teams.Visible then
			refreshMembers()
		end
	end
end)

-- Show the menu when you first join
local character = player.Character or player.CharacterAdded:Wait()
character:WaitForChild("Humanoid")
task.wait(0.5)
openMenu()
]])
put(folder7, "ModuleScript", "Ui", [[
-- The shared look for every menu and the HUD: dark see-through panels, rounded corners and Montserrat text,
-- plus helpers the other client scripts use. Change a colour here and it changes everywhere.
-- It also holds what the client scripts need to share: whether the menu is open, the settings,
-- and the pop-up messages ("toasts") at the top of the screen.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local Ui = {}

Ui.Colours = {
	Panel = Color3.fromRGB(16, 18, 23),
	Raised = Color3.fromRGB(34, 37, 46),
	Text = Color3.new(1, 1, 1),
	Muted = Color3.fromRGB(160, 166, 178),
	Green = Color3.fromRGB(95, 210, 125),
	Red = Color3.fromRGB(235, 90, 80),
	Yellow = Color3.fromRGB(245, 195, 50),
	Blue = Color3.fromRGB(90, 140, 230),
	Walk = Color3.fromRGB(70, 195, 155),
}
Ui.PanelTransparency = 0.12

local MONTSERRAT = "rbxasset://fonts/families/Montserrat.json"

function Ui.font(weight: Enum.FontWeight?): Font
	return Font.new(MONTSERRAT, weight or Enum.FontWeight.Medium)
end

-- Makes an Instance and sets its properties in one go, e.g. Ui.make("Frame", { Size = ..., Parent = gui })
function Ui.make(className: string, props: { [string]: any }?, children: { Instance }?): any
	local object: any = Instance.new(className :: any)
	local parent = nil
	if props then
		for key, value in props do
			if key == "Parent" then
				parent = value
			else
				object[key] = value
			end
		end
	end
	if children then
		for _, child in children do
			child.Parent = object
		end
	end
	if parent then
		object.Parent = parent
	end
	return object
end

function Ui.corner(parent: Instance, radius: number?)
	Ui.make("UICorner", { CornerRadius = UDim.new(0, radius or 14), Parent = parent })
end

function Ui.outline(parent: Instance, transparency: number?, colour: Color3?)
	Ui.make("UIStroke", {
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Color = colour or Color3.new(1, 1, 1),
		Transparency = transparency or 0.9,
		Thickness = 1,
		Parent = parent,
	})
end

function Ui.padding(parent: Instance, x: number, y: number?)
	Ui.make("UIPadding", {
		PaddingLeft = UDim.new(0, x),
		PaddingRight = UDim.new(0, x),
		PaddingTop = UDim.new(0, y or x),
		PaddingBottom = UDim.new(0, y or x),
		Parent = parent,
	})
end

-- A full-screen ScreenGui. Higher `order` draws on top.
function Ui.screen(name: string, order: number): ScreenGui
	return Ui.make("ScreenGui", {
		Name = name,
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = order,
		Parent = Players.LocalPlayer:WaitForChild("PlayerGui"),
	})
end

-- The dark rounded panel everything sits on
function Ui.panel(props: { [string]: any }): Frame
	local frame = Ui.make("Frame", props)
	frame.BackgroundColor3 = props.BackgroundColor3 or Ui.Colours.Panel
	frame.BackgroundTransparency = props.BackgroundTransparency or Ui.PanelTransparency
	frame.BorderSizePixel = 0
	Ui.corner(frame, 14)
	Ui.outline(frame)
	return frame
end

function Ui.label(text: string, size: number, weight: Enum.FontWeight?, props: { [string]: any }?): TextLabel
	local label = Ui.make("TextLabel", props)
	label.BackgroundTransparency = 1
	label.FontFace = Ui.font(weight)
	label.TextSize = size
	label.TextColor3 = if props and props.TextColor3 then props.TextColor3 else Ui.Colours.Text
	label.Text = text
	return label
end

-- A rounded button. `style` is "light" (white, for the main action), "dark" or "clear".
function Ui.button(text: string, style: string, props: { [string]: any }?): TextButton
	local button = Ui.make("TextButton", props)
	button.AutoButtonColor = false
	button.BorderSizePixel = 0
	button.FontFace = Ui.font(Enum.FontWeight.SemiBold)
	button.TextSize = if props and props.TextSize then props.TextSize else 16
	button.Text = text
	local normal, hover
	if style == "light" then
		button.TextColor3 = Color3.fromRGB(15, 15, 18)
		normal, hover = Color3.fromRGB(245, 245, 247), Color3.fromRGB(215, 215, 220)
		button.BackgroundTransparency = 0
	else
		button.TextColor3 = Ui.Colours.Text
		normal, hover = Ui.Colours.Raised, Color3.fromRGB(52, 56, 68)
		button.BackgroundTransparency = if style == "clear" then 0.35 else 0.05
		Ui.outline(button)
	end
	button.BackgroundColor3 = normal
	Ui.corner(button, 12)
	button.MouseEnter:Connect(function()
		button.BackgroundColor3 = hover
	end)
	button.MouseLeave:Connect(function()
		button.BackgroundColor3 = normal
	end)
	return button
end

-- Shared state ------------------------------------------------------------------------------

Ui.menuOpen = false
local menuChanged = Instance.new("BindableEvent")
Ui.MenuChanged = menuChanged.Event -- fires with true/false when the menu opens or closes

function Ui.setMenuOpen(open: boolean)
	Ui.menuOpen = open
	menuChanged:Fire(open)
end

-- The HUD's Menu button asks for the menu through this, and the Menu script listens
local menuRequested = Instance.new("BindableEvent")
Ui.MenuRequested = menuRequested.Event
function Ui.requestMenu()
	menuRequested:Fire()
end

Ui.settings = {
	Shadows = true,
	Controls = true,
	TurnMap = true,
}
local settingChanged = Instance.new("BindableEvent")
Ui.SettingChanged = settingChanged.Event -- fires with (name, value)

function Ui.setSetting(name: string, value: boolean)
	(Ui.settings :: any)[name] = value
	settingChanged:Fire(name, value)
end

-- Toasts: pop-up messages at the top of the screen ---------------------------------------------

local toastList: Frame? = nil

local function getToastList(): Frame
	if toastList then
		return toastList
	end
	local gui = Ui.screen("Toasts", 50)
	local list = Ui.make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 16),
		Size = UDim2.fromOffset(380, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Parent = gui,
	})
	Ui.make("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder, Parent = list })
	toastList = list
	return list
end

local toastCount = 0

-- Ui.toast("Collisions on", "Other players can now hit you", Ui.Colours.Yellow)
function Ui.toast(title: string, body: string?, colour: Color3?, seconds: number?)
	local list = getToastList()
	local duration = seconds or 4
	toastCount += 1

	local card = Ui.panel({ Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = toastCount, Parent = list })
	Ui.padding(card, 14, 12)
	Ui.make("Frame", {
		Size = UDim2.fromOffset(8, 8),
		Position = UDim2.fromOffset(0, 5),
		BackgroundColor3 = colour or Ui.Colours.Yellow,
		Parent = card,
	}, { Ui.make("UICorner", { CornerRadius = UDim.new(1, 0) }) })
	Ui.label(title, 15, Enum.FontWeight.SemiBold, {
		Position = UDim2.fromOffset(18, 0),
		Size = UDim2.new(1, -18, 0, 18),
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = card,
	})
	if body then
		Ui.label(body, 13, Enum.FontWeight.Regular, {
			Position = UDim2.fromOffset(18, 22),
			Size = UDim2.new(1, -18, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = Ui.Colours.Muted,
			Parent = card,
		})
	end
	-- A bar along the bottom that shrinks until the toast goes
	local bar = Ui.make("Frame", {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 0, 1, 8),
		Size = UDim2.new(1, 0, 0, 3),
		BackgroundColor3 = colour or Ui.Colours.Yellow,
		BackgroundTransparency = 0.3,
		BorderSizePixel = 0,
		Parent = card,
	})
	TweenService:Create(bar, TweenInfo.new(duration, Enum.EasingStyle.Linear), { Size = UDim2.new(0, 0, 0, 3) }):Play()
	task.delay(duration, function()
		card:Destroy()
	end)
end

-- Colour names the server can send with a toast
function Ui.colourNamed(name: string?): Color3
	if name and (Ui.Colours :: any)[name] then
		return (Ui.Colours :: any)[name]
	end
	return Ui.Colours.Yellow
end

return Ui
]])
put(folder7, "LocalScript", "VehicleLights", [[
-- Makes every vehicle's lights work on your screen: headlights, indicators, hazards and blue lights.
-- The driver flicks a switch (see Driving), the server sets an attribute on the car, and this script
-- on every player's device does the flashing, so it's smooth and costs the server nothing.

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local INDICATOR_ON = Color3.fromRGB(255, 160, 20)
local INDICATOR_OFF = Color3.fromRGB(150, 95, 30)
local BLUE_ON = Color3.fromRGB(40, 100, 255)
local BLUE_OFF = Color3.fromRGB(25, 35, 75)
local HEADLIGHT_ON = Color3.fromRGB(255, 252, 235)
local HEADLIGHT_OFF = Color3.fromRGB(225, 228, 230)

local function setLamp(part: BasePart, on: boolean, onColour: Color3, offColour: Color3)
	part.Color = if on then onColour else offColour
	part.Material = if on then Enum.Material.Neon else Enum.Material.SmoothPlastic
	local glow = part:FindFirstChildWhichIsA("Light")
	if glow then
		glow.Enabled = on
	end
end

local elapsed = 0
RunService.Heartbeat:Connect(function(dt)
	elapsed += dt
	local cars = Workspace:FindFirstChild("Cars")
	if not cars then
		return
	end
	local blink = elapsed % 0.8 < 0.4 -- indicators: on for 0.4s, off for 0.4s
	local flashA = elapsed % 0.3 < 0.15 -- blue lights swap sides quickly

	for _, car in cars:GetChildren() do
		local indicator = car:GetAttribute("Indicator")
		local blueLights = car:GetAttribute("BlueLights") == true
		local headlights = car:GetAttribute("Headlights") == true
		for _, part in car:GetChildren() do
			if part:IsA("BasePart") then
				local name = part.Name
				if name:sub(1, 9) == "Indicator" then
					local isLeft = name:sub(-1) == "L"
					local on = blink and (indicator == "Hazard" or (indicator == "Left" and isLeft) or (indicator == "Right" and not isLeft))
					setLamp(part, on, INDICATOR_ON, INDICATOR_OFF)
				elseif name == "BlueLightA" then
					setLamp(part, blueLights and flashA, BLUE_ON, BLUE_OFF)
				elseif name == "BlueLightB" then
					setLamp(part, blueLights and not flashA, BLUE_ON, BLUE_OFF)
				elseif name == "Headlight" then
					setLamp(part, headlights, HEADLIGHT_ON, HEADLIGHT_OFF)
				end
			end
		end
	end
end)
]])
removeOldScripts(folder7)

print("London Simulator installed 22 scripts. Press Play to test!")
