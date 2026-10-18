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

-- While testing in Studio, every vehicle counts as yours (nothing is saved, so real players aren't affected)
Config.UnlockEverythingInStudio = true

-- Changing this name starts everyone from scratch (e.g. to wipe test data before launch)
Config.DataStoreName = "PlayerData_v1"

-- Builds London (roads, river, parks, buildings) when the game starts. See LondonMap and tools/london_layout.py.
-- Turn it off if the map is saved in the place file instead.
Config.BuildMap = true

-- 1 stud is about 0.28 metres, so 1 stud per second is about 0.626 mph
Config.MphPerStudPerSecond = 0.626

-- How the car handles. Speeds are in studs per second (multiply by 0.626 for mph).
Config.Car = {
	TopSpeed = 112, -- about 70 mph
	ReverseSpeed = 24, -- about 15 mph
	Acceleration = 14, -- 0-60 mph in about 7 seconds
	BrakeDeceleration = 45,
	CoastDeceleration = 6, -- slowing down when you let go of the accelerator
	CorneringGrip = 50, -- how hard the tyres grip in corners (see CarPhysics): 50 is about 0.95 g
	SteeringLockDegrees = 35, -- full lock when parking; less at speed
	Wheelbase = 8.8, -- distance between front and back wheels
	WheelRadius = 1.3,
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
		showcase = "halden_astor", -- the vehicle shown on the team's card
	},
	{
		name = "Bus",
		icon = "🚌",
		colour = Color3.fromRGB(225, 60, 55),
		description = "Drive London's red buses and pick up passengers",
		showcase = "capital_enviro",
	},
	{
		name = "Emergency",
		icon = "🚓",
		colour = Color3.fromRGB(245, 195, 50),
		description = "Police and ambulance: answer calls across London",
		showcase = "norvik_response",
	},
}

return Config
]])
put(folder2, "ModuleScript", "EngineSounds", [[
-- Real engine sounds for the cars that have them (a vehicle's `engine` in Vehicles; CarBuilder puts it on the
-- car as the "EngineSound" attribute). Each profile is a few recordings of the engine held at set revs.
-- VehicleEffects plays them all at once and blends between the two nearest the engine's rpm, speeding each
-- one up or down to match, which is how racing games make engines sound real.
-- Cars without a profile use VehicleEffects' own two-recording engine.
--
-- The rpm of each recording was worked out from its firing frequency (a straight-six fires 3 times a turn, so
-- rpm = frequency x 20), checked against BMW recordings labelled with their revs. The volumes even out how
-- loud each recording is. All are public Creator Store sounds, checked 18 Oct 2026.

export type Loop = {
	id: string,
	rpm: number, -- the revs it was recorded at
	volume: number,
}

export type Profile = {
	loops: { Loop }, -- lowest revs first
	farts: { string }?, -- the "brap" on a flat-out upshift (picked at random)
	fartVolume: number?,
	burble: string?, -- crackle when you lift off at high revs
	startup: string?, -- when someone gets in the driver's seat
}

local EngineSounds = {}

EngineSounds.Profiles = {
	-- BMW B58 3.0 turbo straight-six (M140i, M340i)
	b58 = {
		loops = {
			{ id = "rbxassetid://117441998977977", rpm = 730, volume = 0.95 }, -- B58_IDLE by oshakeel
			{ id = "rbxassetid://79449611704764", rpm = 2000, volume = 0.6 }, -- Engine_2000 BMW by drygkrakena
			{ id = "rbxassetid://139163114617276", rpm = 3760, volume = 0.6 }, -- b58lowrev by YaBoyZenvo
			{ id = "rbxassetid://113954634252023", rpm = 5600, volume = 0.68 }, -- b58midrev by YaBoyZenvo
			{ id = "rbxassetid://133672841771116", rpm = 7000, volume = 1.3 }, -- B58highrev by YaBoyZenvo
		},
		farts = {
			"rbxassetid://128640768661650", -- upshift by TA7A_IS9Here: 7 deep bangs in 0.2 s
			"rbxassetid://114592589407764", -- B9 Upshift: 8 bangs in 0.2 s
		},
		fartVolume = 2.4,
		burble = "rbxassetid://75835637931827", -- b58burble2 by CATTERGAMEMER1111
		startup = "rbxassetid://78811978152098", -- I6 3.0L BMW B58 140I ENG STARTUP by ttsoarrr
	},
} :: { [string]: Profile }

-- Every sound id in every profile, for loading them up front
function EngineSounds.allIds(): { string }
	local ids = {}
	for _, profile in EngineSounds.Profiles do
		for _, loop in profile.loops do
			table.insert(ids, loop.id)
		end
		local farts: { string } = profile.farts or {}
		for _, id in farts do
			table.insert(ids, id)
		end
		if profile.burble then
			table.insert(ids, profile.burble)
		end
		if profile.startup then
			table.insert(ids, profile.startup)
		end
	end
	return ids
end

return EngineSounds
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
put(folder2, "ModuleScript", "Gearbox", [[
-- A pretend gearbox, so cars rev up, change gear and sound like real ones. The car's speed is still what the
-- physics uses; this works out which gear it's in and how fast the engine is turning. Driving uses it for the
-- car you drive, and VehicleEffects uses it to make every car on the road sound right.
-- A car's "Gears" attribute picks the gearbox (see Gearbox.Boxes): 6 speeds unless it says otherwise.

local Gearbox = {}

Gearbox.IDLE = 750 -- rpm with the engine ticking over
Gearbox.REDLINE = 7000 -- rpm where it changes up (or hits the limiter in top gear)
Gearbox.UP_AT = 6600 -- rpm to change up at when you're on the accelerator
Gearbox.DOWN_AT = 2600 -- rpm to change down at
Gearbox.DOWN_BRAKING = 3800 -- rpm to change down at while braking, so it drops down the gears with a blip each

export type Box = {
	ratios: { number }, -- how much of the car's top speed each gear reaches at the redline
	pull: { number }, -- how hard each gear pulls compared with the car's acceleration figure
	shiftTime: number, -- seconds with no drive while it changes up
}

Gearbox.Boxes = {
	[6] = {
		ratios = { 0.22, 0.37, 0.52, 0.67, 0.83, 1.0 },
		pull = { 1.45, 1.25, 1.05, 0.88, 0.74, 0.62 },
		shiftTime = 0.2,
	},
	-- An 8-speed automatic like the ZF one in fast saloons and hot hatches: close ratios and quick changes
	[8] = {
		ratios = { 0.2, 0.31, 0.43, 0.55, 0.67, 0.79, 0.9, 1.0 },
		pull = { 1.5, 1.36, 1.2, 1.06, 0.93, 0.82, 0.72, 0.64 },
		shiftTime = 0.14,
	},
} :: { [number]: Box }

-- The gearbox for a car, from its "Gears" attribute
function Gearbox.boxFor(car: Instance): Box
	local gears = car:GetAttribute("Gears")
	return Gearbox.Boxes[if typeof(gears) == "number" then gears else 6] or Gearbox.Boxes[6]
end

-- The fastest a gear goes, in studs per second
function Gearbox.gearTop(box: Box, gear: number, topSpeed: number): number
	local ratio = box.ratios[math.clamp(gear, 1, #box.ratios)]
	return topSpeed * ratio
end

-- Engine speed in rpm, for a speed (studs per second) in a gear. Gear 0 is reverse.
function Gearbox.rpm(box: Box, speed: number, gear: number, topSpeed: number, reverseSpeed: number): number
	local top = if gear <= 0 then reverseSpeed * 1.15 else Gearbox.gearTop(box, gear, topSpeed)
	local share = math.clamp(math.abs(speed) / math.max(top, 1), 0, 1.04)
	return Gearbox.IDLE + (Gearbox.REDLINE - Gearbox.IDLE) * share
end

-- 0 at tick-over, 1 at the redline
function Gearbox.share(rpm: number): number
	return math.clamp((rpm - Gearbox.IDLE) / (Gearbox.REDLINE - Gearbox.IDLE), 0, 1)
end

-- How strong the engine is at an rpm (a little weak at the very bottom, strongest in the middle)
function Gearbox.torque(rpm: number): number
	local share = Gearbox.share(rpm)
	return 0.8 + 0.3 * math.sin(math.pi * math.clamp(share * 1.1, 0, 1))
end

-- The gear a car would be in at a speed, for cars we can only watch (other players'): changes up and down
-- at the same points the driver's own gearbox does, starting from the gear it was in
function Gearbox.guess(box: Box, speed: number, current: number, topSpeed: number, accelerating: boolean): number
	local top = #box.ratios
	local gear = math.clamp(current, 1, top)
	for _ = 1, top do
		local rpm = Gearbox.rpm(box, speed, gear, topSpeed, 1)
		if rpm >= (if accelerating then Gearbox.UP_AT else Gearbox.REDLINE * 0.9) and gear < top then
			gear += 1
		elseif rpm < Gearbox.DOWN_AT and gear > 1 then
			gear -= 1
		else
			break
		end
	end
	return gear
end

return Gearbox
]])
put(folder2, "ModuleScript", "Vehicles", [[
-- Every vehicle in the game: its name, which team drives it, what it costs and how fast it goes.
-- The menu's vehicle picker shows these. CarBuilder (on the server) uses the detailed body in
-- ServerStorage → VehicleBodies with the same id when there is one (made from free Swat Motors Company
-- models by tools/prepare_vehicle_bodies.luau), and otherwise builds a simple body from parts in the "style" shape.
-- Speeds are in studs per second (multiply by 0.626 for mph). Prices are in pounds.
-- No real car makers: every name here is made up.

export type Vehicle = {
	id: string,
	name: string,
	team: string,
	price: number, -- 0 means everyone gets it free
	style: string, -- shape of the simple parts body, used when there's no detailed body
	livery: string?, -- "Police", "Ambulance", "Taxi" or "Unmarked" (simple bodies only)
	electric: boolean?,
	paint: number?, -- colour from Vehicles.Paints; leave out to keep a detailed body's own colour
	fixedPaint: boolean?, -- true for police, ambulances and buses, which can't be repainted
	topSpeed: number,
	acceleration: number,
	brakes: number?, -- how hard it stops (studs per second per second); leave out for the normal brakes
	grip: number?, -- how hard it can corner at speed; leave out for normal
	underglow: Color3?, -- a glow under the car
	hero: boolean?, -- too detailed to use for parked cars
	seatDrop: number?, -- how far to lower the seats (studs), so tall players' heads stay inside the roof
	pops: boolean?, -- pops and bangs from the exhaust when you lift off or change gear
	exhaust: Vector3?, -- where the right-hand exhaust is on a detailed body (the left one is mirrored)
	engine: string?, -- real engine recordings to use (a profile in EngineSounds), instead of the made-up engine
	gears: number?, -- how many gears (a gearbox in Gearbox.Boxes); 6 if left out
	aChassis: boolean?, -- drive on its own A-Chassis model from ServerStorage.ChassisCars instead of our springs and tyres
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
	{ name = "Estoril Blue", colour = Color3.fromRGB(20, 55, 135) },
}

local BLACK = 2
local BUS_RED = 15
local ESTORIL_BLUE = 17

Vehicles.List = {
	-- Car team
	-- The cover car: a 2017 hot hatch with a 3.0 turbo straight-six, an 8-speed automatic that farts on every
	-- flat-out upshift, and real recordings of that engine. About 125 mph, 0-60 in about 3.3 s.
	{ id = "brenner_140", name = "Brenner 140 Sport", team = "Car", price = 0, style = "hatch", paint = ESTORIL_BLUE, topSpeed = 200, acceleration = 30, brakes = 75, grip = 88, hero = true, seatDrop = 0.8, pops = true, engine = "b58", gears = 8 },
	-- A big executive estate on its own A-Chassis physics, from a bought pack (see tools/prepare_chassis_cars.luau):
	-- kept on A-Chassis for now so it can be compared with our own springs and tyres on the 140 and 340
	{ id = "aurel_sovereign", name = "Aurel Sovereign", team = "Car", price = 0, style = "saloon", topSpeed = 190, acceleration = 26, hero = true, aChassis = true },
	-- The quick one, like the blue saloon in Birmingham Vehicle Simulator: about 130 mph flat out, 0-60 in
	-- about 3 seconds, strong brakes, a blue glow underneath, and pops and bangs from the exhaust
	{ id = "brenner_340", name = "Brenner 340 Sport", team = "Car", price = 0, style = "saloon", topSpeed = 208, acceleration = 32, brakes = 75, grip = 85, underglow = Color3.fromRGB(40, 90, 255), hero = true, seatDrop = 1.0, pops = true, exhaust = Vector3.new(2.35, 0.85, 8.6), engine = "b58", gears = 8 },
	{ id = "halden_astor", name = "Halden Astor", team = "Car", price = 0, style = "hatch", topSpeed = 110, acceleration = 14 },
	{ id = "halden_senator", name = "Halden Senator", team = "Car", price = 0, style = "saloon", topSpeed = 118, acceleration = 15 },
	{ id = "aurel_comet", name = "Aurel Comet", team = "Car", price = 2500, style = "hatch", topSpeed = 115, acceleration = 15 },
	{ id = "hackney_cab", name = "Hackney Cab", team = "Car", price = 3000, style = "cab", livery = "Taxi", electric = true, paint = BLACK, topSpeed = 100, acceleration = 15 },
	{ id = "jaxon_xr", name = "Jaxon XR", team = "Car", price = 6000, style = "saloon", topSpeed = 125, acceleration = 17 },
	{ id = "volta_glide", name = "Volta Glide", team = "Car", price = 9000, style = "suv", electric = true, topSpeed = 125, acceleration = 20 },
	{ id = "ridgeline_sport", name = "Ridgeline Sport", team = "Car", price = 14000, style = "suv", topSpeed = 135, acceleration = 19 },
	-- Bus team (London buses are always red)
	{ id = "metro_citaro", name = "Metro Single", team = "Bus", price = 0, style = "bus_single", paint = BUS_RED, fixedPaint = true, topSpeed = 75, acceleration = 9 },
	{ id = "capital_enviro", name = "Capital Decker", team = "Bus", price = 0, style = "bus_double", paint = BUS_RED, fixedPaint = true, topSpeed = 70, acceleration = 8 },
	{ id = "heritage_decker", name = "Heritage Decker", team = "Bus", price = 6000, style = "bus_double", fixedPaint = true, topSpeed = 60, acceleration = 7 },
	-- Emergency team
	{ id = "norvik_response", name = "Norvik XR Response", team = "Emergency", price = 0, style = "suv", livery = "Police", fixedPaint = true, topSpeed = 125, acceleration = 17 },
	{ id = "halden_astor_response", name = "Halden Astor Response", team = "Emergency", price = 0, style = "hatch", livery = "Police", fixedPaint = true, topSpeed = 120, acceleration = 16 },
	{ id = "halden_vantage_ambulance", name = "Halden Vantage Ambulance", team = "Emergency", price = 0, style = "van", livery = "Ambulance", fixedPaint = true, topSpeed = 100, acceleration = 12 },
	{ id = "brenner_paramedic", name = "Brenner Paramedic", team = "Emergency", price = 2500, style = "estate", livery = "Ambulance", fixedPaint = true, topSpeed = 120, acceleration = 17 },
	{ id = "norvik_admin", name = "Norvik Estate Admin", team = "Emergency", price = 2000, style = "estate", livery = "Police", fixedPaint = true, topSpeed = 118, acceleration = 16 },
	{ id = "police_carrier", name = "Police Carrier", team = "Emergency", price = 3000, style = "van", livery = "Police", fixedPaint = true, topSpeed = 95, acceleration = 11 },
	{ id = "norvik_urgent_care", name = "Norvik Urgent Care", team = "Emergency", price = 4500, style = "suv", livery = "Ambulance", fixedPaint = true, topSpeed = 120, acceleration = 16 },
	{ id = "norvik_traffic", name = "Norvik Estate Traffic", team = "Emergency", price = 5000, style = "estate", livery = "Police", fixedPaint = true, topSpeed = 130, acceleration = 18 },
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

-- The colour a vehicle is painted, given the paint the player picked (or nil for its default).
-- nil means "keep the detailed body's own colour".
function Vehicles.paintColour(vehicle: Vehicle, picked: number?): Color3?
	local index = if picked and not vehicle.fixedPaint and Vehicles.Paints[picked] then picked else vehicle.paint
	local paint = if index then Vehicles.Paints[index] else nil
	return if paint then paint.colour else nil
end

return Vehicles
]])
removeOldScripts(folder2)
local folder3 = game:GetService("ServerScriptService")
local folder4 = folder(folder3, "Server")
put(folder4, "ModuleScript", "CarBuilder", [[
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
]])
put(folder4, "ModuleScript", "Cars", [[
-- Spawns and looks after players' vehicles: one each, built by CarBuilder.
-- The driving itself happens in the Driving LocalScript, on the driver's own device, so it feels instant.
-- Cars with an A-Chassis model in ServerStorage → ChassisCars (made by tools/prepare_chassis_cars.luau) are
-- spawned from that instead: they drive on real physics with their own scripts, sounds and lights.
-- Vehicles appear at your team's depot (a model in Workspace → Depots with "Spawn" parts in it).

local Players = game:GetService("Players")
local PhysicsService = game:GetService("PhysicsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
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
-- A-Chassis cars' wheels and suspension: they touch the road but never car bodies, or a car's own wheels jam
-- against its wheel arches
local WHEELS_GROUP = "CarWheels"

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

-- The group a part goes in: an A-Chassis car's wheels and moving bits (Wheels and Misc) go in WHEELS_GROUP
local function groupFor(car: Model, part: BasePart, group: string): string
	if car:GetAttribute("ChassisCar") then
		for _, name in { "Wheels", "Misc" } do
			local folder = car:FindFirstChild(name)
			if folder and part:IsDescendantOf(folder) then
				return WHEELS_GROUP
			end
		end
	end
	return group
end

local function setCollisionGroup(car: Model, group: string)
	car:SetAttribute("BodyGroup", group)
	for _, descendant in car:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.CollisionGroup = groupFor(car, descendant, group)
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

local function addPrompt(seat: BasePart, actionText: string, objectText: string, key: Enum.KeyCode, gamepadKey: Enum.KeyCode, offset: number): ProximityPrompt
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = actionText
	prompt.ObjectText = objectText
	prompt.KeyboardKeyCode = key
	-- Each prompt its own controller button: with both on the same one, a controller could put the owner
	-- in the passenger seat, where they can't drive
	prompt.GamepadKeyCode = gamepadKey
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	-- Both prompts sit on the driver's seat, so stack them instead of drawing them on top of each other
	prompt.UIOffset = Vector2.new(0, offset)
	prompt.Parent = seat
	return prompt
end

-- Seats, prompts and network ownership for a freshly built car
local function wireUp(car: Model, owner: Player, driverSeat: VehicleSeat, passengerSeats: { Seat })
	local chassis = car.PrimaryPart :: BasePart
	local drivePrompt = addPrompt(driverSeat, "Drive", owner.DisplayName .. "'s " .. car.Name, Enum.KeyCode.E, Enum.KeyCode.ButtonX, -42)
	local passengerPrompt = addPrompt(driverSeat, "Get in", owner.DisplayName .. "'s " .. car.Name, Enum.KeyCode.F, Enum.KeyCode.ButtonY, 42)
	passengerPrompt.Name = "GetIn"
	passengerPrompt.Enabled = #passengerSeats > 0

	drivePrompt.Triggered:Connect(function(player)
		local humanoid = getHumanoid(player)
		if player == owner and humanoid and not humanoid.SeatPart and not driverSeat.Occupant then
			driverSeat:Sit(humanoid)
		end
	end)

	-- "Get in" puts you in the first free passenger seat, front seat first. The owner always gets the
	-- driver's seat if it's free: it's their car.
	passengerPrompt.Triggered:Connect(function(player)
		local humanoid = getHumanoid(player)
		if not humanoid or humanoid.SeatPart then
			return
		end
		if player == owner and not driverSeat.Occupant then
			driverSeat:Sit(humanoid)
			return
		end
		for _, passengerSeat in passengerSeats do
			if not passengerSeat.Occupant then
				passengerSeat:Sit(humanoid)
				return
			end
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
			car:SetAttribute("Horn", nil)
		end
		-- The driver's device runs the car's physics while they drive, so there's no lag
		if not chassis.Anchored then
			chassis:SetNetworkOwner(driver)
		end
	end)

	-- Hide "Get in" once every passenger seat is taken
	for _, passengerSeat in passengerSeats do
		passengerSeat:GetPropertyChangedSignal("Occupant"):Connect(function()
			local free = false
			for _, other in passengerSeats do
				free = free or other.Occupant == nil
			end
			passengerPrompt.Enabled = free
		end)
	end
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

-- An A-Chassis car, painted and placed, standing on the road at `origin`
local function buildChassisCar(template: Model, origin: CFrame, paint: Color3?): (Model, VehicleSeat, { Seat })
	local car = template:Clone()
	if paint then
		for _, part in car:GetDescendants() do
			if part:IsA("BasePart") and part:GetAttribute("Paint") then
				part.Color = paint
			end
		end
	end
	car:PivotTo(origin * CFrame.new(0, 0.3, 0))
	local driverSeat = car:FindFirstChild("DriveSeat") :: VehicleSeat
	local passengers: { Seat } = {}
	for _, d in car:GetDescendants() do
		if d:IsA("Seat") then
			table.insert(passengers, d)
		end
	end
	table.sort(passengers, function(a, b)
		return (a.Position - driverSeat.Position).Magnitude < (b.Position - driverSeat.Position).Magnitude
	end)
	return car, driverSeat, passengers
end

local function chassisTemplate(vehicleId: string): Model?
	local folder = ServerStorage:FindFirstChild("ChassisCars")
	local template = folder and folder:FindFirstChild(vehicleId)
	return if template and template:IsA("Model") and template:FindFirstChild("DriveSeat") then template else nil
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
	-- nil paint keeps a detailed body's own colours
	local paint = Vehicles.paintColour(vehicle, PlayerData.paintOf(player, vehicle.id))
	local template = if vehicle.aChassis then chassisTemplate(vehicle.id) else nil
	local car, driverSeat, passengerSeats
	if template then
		car, driverSeat, passengerSeats = buildChassisCar(template, origin, paint)
	else
		car, driverSeat, passengerSeats = CarBuilder.build(vehicle, origin, paint, randomPlate())
	end
	car.Name = vehicle.name
	car:SetAttribute("OwnerUserId", player.UserId)
	if template then
		-- For other players' devices to guess this car's revs from its speed (see VehicleEffects)
		car:SetAttribute("TopSpeed", vehicle.topSpeed)
		car:SetAttribute("Acceleration", vehicle.acceleration)
	end
	wireUp(car, player, driverSeat, passengerSeats)
	setParked(car, true)

	-- Start as a ghost so nobody can ram you while you get going
	setCollisionGroup(car, GHOST_GROUP)
	if template then
		-- A-Chassis adds its axles and suspension parts when it starts up: they need the right group too
		car.DescendantAdded:Connect(function(descendant)
			if descendant:IsA("BasePart") then
				local bodyGroup = car:GetAttribute("BodyGroup")
				descendant.CollisionGroup = groupFor(car, descendant, if typeof(bodyGroup) == "string" then bodyGroup else CARS_GROUP)
			end
		end)
	end
	car.Parent = carsFolder
	carsByPlayer[player] = car
	-- Sit them in it. Straight after getting out of the old car this can fail, so keep trying for a moment.
	-- An A-Chassis car has to finish setting itself up first (it unanchors the car when it's done), or it
	-- never hands the driver its controls.
	task.spawn(function()
		if template then
			for _ = 1, 60 do
				if not driverSeat.Anchored or not car.Parent then
					break
				end
				task.wait(0.1)
			end
			task.wait(0.2)
		end
		for _ = 1, 20 do
			if driverSeat.Occupant == humanoid or not car.Parent or not humanoid.Parent then
				break
			end
			humanoid.Sit = false
			driverSeat:Sit(humanoid)
			task.wait(0.1)
		end
	end)

	task.delay(Config.Car.GhostSeconds, function()
		if car.Parent then
			setCollisionGroup(car, CARS_GROUP)
			Remotes.notify(player, "Collisions on", "Other players can now hit your vehicle. Drive carefully!", "Yellow")
		end
	end)
end

-- Lights, indicators, blue lights and the horn. The driver asks, the server sets an attribute, and
-- VehicleLights / VehicleEffects on every player's device make the bulbs flash and the horn sound.
local function control(player: Player, action: unknown)
	local car = carsByPlayer[player]
	local humanoid = getHumanoid(player)
	if not car or not humanoid or typeof(action) ~= "string" then
		return
	end
	local driverSeat = (car:FindFirstChild("DriverSeat") or car:FindFirstChild("DriveSeat")) :: VehicleSeat?
	if not driverSeat or driverSeat.Occupant ~= humanoid then
		return -- only the driver can work the switches
	end

	if action == "Lights" then
		car:SetAttribute("Headlights", not car:GetAttribute("Headlights"))
	elseif action == "Left" or action == "Right" or action == "Hazard" then
		car:SetAttribute("Indicator", if car:GetAttribute("Indicator") == action then nil else action)
	elseif action == "BlueLights" and car:GetAttribute("HasBlueLights") then
		car:SetAttribute("BlueLights", not car:GetAttribute("BlueLights"))
	elseif action == "HornOn" then
		car:SetAttribute("Horn", true)
	elseif action == "HornOff" then
		car:SetAttribute("Horn", nil)
	end
end

-- Display copies of every vehicle for the menu: ReplicatedStorage → VehicleModels → <vehicle id>.
-- They're anchored, can't be sat in and can't be bumped into.
local function buildDisplayModels()
	local folder = Instance.new("Folder")
	folder.Name = "VehicleModels"
	for _, vehicle in Vehicles.List do
		-- A-Chassis cars are shown as themselves (without their scripts); everything else is built
		local template = if vehicle.aChassis then chassisTemplate(vehicle.id) else nil
		local model
		if template then
			model = buildChassisCar(template, CFrame.new(), Vehicles.paintColour(vehicle, nil))
			for _, descendant in model:GetDescendants() do
				if descendant:IsA("LuaSourceContainer") or descendant:IsA("Sound") or descendant:IsA("LayerCollector") then
					descendant:Destroy()
				end
			end
			model:PivotTo(CFrame.new())
		else
			model = CarBuilder.build(vehicle, CFrame.new(), Vehicles.paintColour(vehicle, nil), "LDN 5IM")
		end
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
	PhysicsService:RegisterCollisionGroup(WHEELS_GROUP)
	for _, other in { CARS_GROUP, GHOST_GROUP, WHEELS_GROUP } do
		PhysicsService:CollisionGroupSetCollidable(WHEELS_GROUP, other, false)
	end

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
put(folder4, "ModuleScript", "CityBuildings", [[
-- Buildings made from parts, in the styles of real London streets, for everywhere the bought building kit
-- doesn't cover: Georgian terraces, Victorian houses with bay windows, rows of shops with flats above,
-- red-brick mansion blocks, Portland stone offices, glass towers, 1960s concrete, warehouses, industrial
-- units, council tower blocks, corner pubs and corner shops, and plain blocks for round the edge of the map.
--
-- CityBuildings.build(style, frame, width, depth, storeys, seed, flank, isBack)
--   frame: the middle of the building's front edge, on the ground, looking out at the road
--   flank: 1 or -1 if the building is on a corner and its right (1) or left (-1) side faces a street too
--   isBack: it stands behind other buildings, so it only needs to look right from a distance
-- Each building is one Model that streams in and out as a whole.
--
-- Windows are made the cheap way: one sheet of glass over the whole face, with strips of wall (piers
-- between the windows and bands between the storeys) laid over it. That gives a full grid of windows for
-- a dozen parts a face instead of hundreds.

local TownKit = require(script.Parent.TownKit)

local box = TownKit.box
local PAVEMENT_TOP = TownKit.PAVEMENT_TOP

local CityBuildings = {}

-- Colours ------------------------------------------------------------------------------------------

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local RED_BRICK = { rgb(142, 72, 52), rgb(128, 66, 50), rgb(156, 86, 62), rgb(117, 58, 44), rgb(150, 96, 72), rgb(134, 80, 62) }
local STOCK_BRICK = { rgb(176, 152, 116), rgb(162, 140, 108), rgb(186, 164, 128), rgb(150, 128, 98) }
local STUCCO = { rgb(236, 232, 222), rgb(240, 236, 226), rgb(232, 226, 210), rgb(226, 222, 214) }
local RENDER = { rgb(214, 205, 186), rgb(196, 192, 180), rgb(224, 214, 190), rgb(204, 198, 188) }
local PORTLAND = rgb(226, 219, 201)
local STONE_TRIM = rgb(222, 214, 194)
local CONCRETE = { rgb(158, 158, 154), rgb(170, 168, 160), rgb(146, 146, 144), rgb(182, 178, 168) }
local GLASS = rgb(38, 50, 60)
local OFFICE_GLASS = { rgb(70, 98, 120), rgb(60, 84, 96), rgb(84, 108, 112), rgb(46, 62, 80), rgb(96, 116, 130) }
local SLATE = rgb(66, 68, 74)
local ROOF_FELT = rgb(52, 52, 55)
local DOORS = { rgb(20, 20, 22), rgb(30, 50, 90), rgb(110, 25, 30), rgb(25, 70, 45), rgb(235, 235, 230), rgb(200, 160, 40) }
local FASCIAS = { rgb(20, 60, 40), rgb(25, 35, 70), rgb(110, 25, 30), rgb(20, 20, 22), rgb(190, 30, 35), rgb(235, 235, 230), rgb(60, 30, 70), rgb(200, 150, 40), rgb(30, 110, 120) }
local PUB_PAINT = { rgb(24, 52, 36), rgb(80, 18, 24), rgb(18, 18, 20), rgb(22, 34, 62) }
local CLADDING = { rgb(170, 175, 180), rgb(120, 140, 160), rgb(150, 160, 150), rgb(190, 190, 185) }
local BAY_WHITE = rgb(236, 236, 230)

-- Made-up names, so there are no real shops or brands anywhere
local SHOP_NAMES = {
	"CAFÉ", "BARBERS", "NEWS & WINE", "LAUNDERETTE", "FRIED CHICKEN", "PHONE REPAIRS", "BAKERY", "FLORIST",
	"ESTATE AGENTS", "PHARMACY", "BOOKMAKERS", "DRY CLEANERS", "KEBAB HOUSE", "PIZZA", "GOLDEN DRAGON",
	"MINI MARKET", "OFF LICENCE", "NAILS & BEAUTY", "OPTICIANS", "HALAL BUTCHERS", "HARDWARE", "TAILORS",
	"FISH & CHIPS", "CHARITY SHOP", "PAWNBROKERS", "TRAVEL AGENTS", "CURRY HOUSE", "SANDWICH BAR", "VAPE SHOP",
	"KEY CUTTING", "PET SHOP", "BRIDGE CAFÉ", "FRESH CUTS", "LUCKY STAR", "CORNER STORES", "MARIO'S",
}
local PUB_NAMES = {
	"THE RED LION", "THE KING'S HEAD", "THE CROWN", "THE ROSE & CROWN", "THE WHITE HART", "THE PLOUGH",
	"THE GEORGE", "THE PRINCE ALBERT", "THE QUEEN'S ARMS", "THE NAG'S HEAD", "THE BLACK HORSE", "THE ROYAL OAK",
	"THE SHIP", "THE BELL", "THE SWAN", "THE ANGEL", "THE GREYHOUND", "THE COACH & HORSES", "THE DUKE OF YORK",
}
local FIRM_NAMES = {
	"CITY TYRES", "METRO TIMBER", "ACE MOTORS", "THAMES PLUMBING", "EAST END PRINTING", "DOCKSIDE STORAGE",
	"LONDON REMOVALS", "QUICK CLUTCH & BRAKE", "RIVERSIDE BUILDERS", "UNITED FABRICS", "BOROUGH SCAFFOLDING",
}

local function choose<T>(list: { T }, random: Random): T
	return list[random:NextInteger(1, #list)]
end

-- Building blocks -------------------------------------------------------------------------------

-- A part placed in the building's own space: x across, y up from the ground, z back from the front
local function piece(frame: CFrame, size: Vector3, x: number, y: number, z: number, colour: Color3, material: Enum.Material): Part
	return box(size, frame * CFrame.new(x, y, z), colour, material)
end

type Grid = {
	x0: number, -- across the face, from one end
	x1: number, -- to the other
	y0: number, -- bottom of the windowed part
	y1: number, -- top of the windowed part
	bay: number, -- one window and the wall beside it
	window: number, -- window width
	storey: number,
	pane: number, -- window height
	sill: number, -- from each storey's floor up to the bottom of its windows
}

-- A grid of windows on a face. `along` turns the face: "front" (z = at, looking out to -z), "back"
-- (z = at, looking out to +z), "right" (x = at, looking out to +x) or "left" (x = at, looking out to -x).
local WHITE_FRAME = Color3.fromRGB(238, 238, 232)
local SILL_STONE = Color3.fromRGB(214, 208, 192)

-- `frameColour` (optional) adds glazing bars (a bar down and across every window, like a sash window) and
-- a stone sill under each row of windows
local function windows(frame: CFrame, along: string, at: number, g: Grid, wall: Color3, material: Enum.Material, band: Color3?, glass: Color3?, frameColour: Color3?)
	local w, h = g.x1 - g.x0, g.y1 - g.y0
	if w < 2 or h < 2 then
		return
	end
	-- Turn the face so its own x runs across it and -z looks out
	local faceFrame: CFrame
	if along == "front" then
		faceFrame = frame * CFrame.new(0, 0, at)
	elseif along == "back" then
		faceFrame = frame * CFrame.new(0, 0, at) * CFrame.Angles(0, math.pi, 0)
	elseif along == "right" then
		faceFrame = frame * CFrame.new(at, 0, 0) * CFrame.Angles(0, -math.pi / 2, 0)
	else
		faceFrame = frame * CFrame.new(at, 0, 0) * CFrame.Angles(0, math.pi / 2, 0)
	end
	local cx, cy = (g.x0 + g.x1) / 2, (g.y0 + g.y1) / 2
	local sheet = piece(faceFrame, Vector3.new(w, h, 0.4), cx, cy, -0.1, glass or GLASS, Enum.Material.Glass)
	sheet.Reflectance = 0.08
	sheet.CastShadow = false
	local bays = math.max(1, math.round(w / g.bay))
	local bay = w / bays
	local pier = math.max(0.6, bay - g.window)
	for i = 0, bays do
		local pw = if i == 0 or i == bays then pier / 2 else pier
		local x = g.x0 + i * bay + (if i == 0 then pw / 2 elseif i == bays then -pw / 2 else 0)
		if pw > 0.05 then
			piece(faceFrame, Vector3.new(pw, h, 0.9), x, cy, -0.35, wall, material)
		end
	end
	local storeys = math.max(1, math.round(h / g.storey))
	local sh = h / storeys
	local function strip(yA: number, yB: number)
		if yB - yA > 0.05 then
			piece(faceFrame, Vector3.new(w, yB - yA, 0.9), cx, (yA + yB) / 2, -0.35, band or wall, material)
		end
	end
	strip(g.y0, g.y0 + g.sill)
	for f = 0, storeys - 1 do
		local head = g.y0 + f * sh + g.sill + g.pane
		local nextSill = if f == storeys - 1 then g.y1 else g.y0 + (f + 1) * sh + g.sill
		strip(math.min(head, nextSill), nextSill)
	end
	if frameColour then
		-- The bars sit just in front of the glass, so they only show through the window openings
		for i = 0, bays - 1 do
			local bar = piece(faceFrame, Vector3.new(0.32, h, 0.24), g.x0 + (i + 0.5) * bay, cy, -0.32, frameColour, Enum.Material.SmoothPlastic)
			bar.CastShadow = false
		end
		for f = 0, storeys - 1 do
			local floorY = g.y0 + f * sh
			local bar = piece(faceFrame, Vector3.new(w, 0.32, 0.24), cx, floorY + g.sill + g.pane * 0.55, -0.32, frameColour, Enum.Material.SmoothPlastic)
			bar.CastShadow = false
			-- A stone sill under each row of windows
			piece(faceFrame, Vector3.new(w + 0.2, 0.45, 1.5), cx, floorY + g.sill - 0.2, -0.75, SILL_STONE, Enum.Material.Limestone)
		end
	end
end

local function flatRoof(frame: CFrame, w: number, d: number, h: number, parapet: number, colour: Color3, material: Enum.Material, random: Random)
	piece(frame, Vector3.new(w, 0.5, d), 0, h + 0.25, d / 2, ROOF_FELT, Enum.Material.Concrete)
	if parapet > 0 then
		piece(frame, Vector3.new(w, parapet, 0.8), 0, h + parapet / 2, 0.4, colour, material)
		piece(frame, Vector3.new(w, parapet, 0.8), 0, h + parapet / 2, d - 0.4, colour, material)
	end
	-- A plant room or water tank or two on top
	if w < 14 or d < 14 then
		return
	end
	for _ = 1, random:NextInteger(0, 2) do
		local sx, sz = random:NextNumber(4, math.max(4.5, w * 0.3)), random:NextNumber(4, math.max(4.5, d * 0.3))
		local x = random:NextNumber(-w / 2 + sx / 2 + 1, w / 2 - sx / 2 - 1)
		local z = random:NextNumber(sz / 2 + 2, math.max(sz / 2 + 2.1, d - sz / 2 - 2))
		piece(frame, Vector3.new(sx, 4, sz), x, h + 2.5, z, rgb(150, 150, 148), Enum.Material.Metal)
	end
end

-- A slate roof with its ridge along the street
local function pitchedRoof(frame: CFrame, w: number, d: number, h: number, rise: number, colour: Color3?)
	local slate = colour or SLATE
	local front = box(Vector3.new(w + 0.6, rise, d / 2 + 0.4), frame * CFrame.new(0, h + rise / 2, d / 4 - 0.2), slate, Enum.Material.Slate, "WedgePart")
	local back = box(Vector3.new(w + 0.6, rise, d / 2 + 0.4), frame * CFrame.new(0, h + rise / 2, d * 3 / 4 + 0.2) * CFrame.Angles(0, math.pi, 0), slate, Enum.Material.Slate, "WedgePart")
	front.TopSurface = Enum.SurfaceType.Smooth
	back.TopSurface = Enum.SurfaceType.Smooth
	-- Gutters along the eaves
	local gutter = Color3.fromRGB(34, 34, 36)
	piece(frame, Vector3.new(w + 0.6, 0.5, 0.6), 0, h + 0.15, -0.5, gutter, Enum.Material.Plastic)
	piece(frame, Vector3.new(w + 0.6, 0.5, 0.6), 0, h + 0.15, d + 0.5, gutter, Enum.Material.Plastic)
end

-- A drainpipe down the front at x
local function drainpipe(frame: CFrame, x: number, h: number)
	piece(frame, Vector3.new(0.45, h, 0.45), x, h / 2, -0.75, Color3.fromRGB(34, 34, 36), Enum.Material.Plastic)
end

-- Chimney stacks along the ridge, one between each pair of houses
local function chimneys(frame: CFrame, w: number, d: number, top: number, count: number, colour: Color3)
	for i = 0, count do
		local x = math.clamp(-w / 2 + i * w / count, -w / 2 + 1.2, w / 2 - 1.2)
		piece(frame, Vector3.new(2.4, 5.5, 3.4), x, top + 1.5, d / 2, colour, Enum.Material.Brick)
		piece(frame, Vector3.new(0.9, 1.2, 0.9), x - 0.6, top + 4.8, d / 2, Color3.fromRGB(150, 80, 50), Enum.Material.Concrete)
		piece(frame, Vector3.new(0.9, 1.2, 0.9), x + 0.6, top + 4.8, d / 2, Color3.fromRGB(150, 80, 50), Enum.Material.Concrete)
	end
end

local function cornice(frame: CFrame, w: number, y: number, colour: Color3, depth: number?)
	piece(frame, Vector3.new(w + 0.8, 1.2, depth or 1.4), 0, y, -(depth or 1.4) / 2 + 0.6, colour, Enum.Material.Limestone)
end

-- A strip of paving between the pavement and the front of the building, so they meet neatly
local function apron(frame: CFrame, w: number)
	piece(frame, Vector3.new(w, PAVEMENT_TOP, 1.6), 0, PAVEMENT_TOP / 2, -0.7, TownKit.Colours.Pavement, Enum.Material.Pavement)
end

local function door(frame: CFrame, x: number, colour: Color3, wide: number?)
	piece(frame, Vector3.new(wide or 3.4, 7.6, 0.5), x, PAVEMENT_TOP + 3.8, -0.6, colour, Enum.Material.Wood)
end

local function sign(host: BasePart, text: string, colour: Color3, background: Color3?)
	TownKit.text(host, Enum.NormalId.Front, text, colour, background, Enum.FontWeight.Bold)
end

-- Styles --------------------------------------------------------------------------------------------

type Spec = { frame: CFrame, w: number, d: number, storeys: number, random: Random, flank: number, back: boolean }

-- Two-up two-down terraced houses with bay windows, chimneys and a slate roof
local function victorian(s: Spec)
	local f, w, d, r = s.frame, s.w, s.d, s.random
	local storeyH = 10
	local h = s.storeys * storeyH
	local wall = if r:NextNumber() < 0.7 then choose(RED_BRICK, r) else choose(STOCK_BRICK, r)
	piece(f, Vector3.new(w, h, d), 0, h / 2, d / 2, wall, Enum.Material.Brick)
	local houses = math.max(1, math.round(w / 16))
	local hw = w / houses
	local grid = { x0 = -w / 2, x1 = w / 2, y0 = 0, y1 = h, bay = hw / 2, window = 4.2, storey = storeyH, pane = 6, sill = 2.6 }
	windows(f, "front", 0, grid, wall, Enum.Material.Brick, nil, nil, WHITE_FRAME)
	local doorColour = choose(DOORS, r)
	for i = 0, houses - 1 do
		local left = -w / 2 + i * hw
		local mirrored = i % 2 == 1
		local doorX = left + (if mirrored then hw * 0.75 else hw * 0.25)
		local bayX = left + (if mirrored then hw * 0.25 else hw * 0.75)
		door(f, doorX, if r:NextNumber() < 0.3 then choose(DOORS, r) else doorColour)
		-- The bay window: a painted box sticking out, with glass on its front
		local bayW = math.min(7, hw / 2 - 0.8)
		piece(f, Vector3.new(bayW, 8.6, 2.4), bayX, PAVEMENT_TOP + 4.3, -1.2, BAY_WHITE, Enum.Material.Plaster)
		local pane = piece(f, Vector3.new(bayW - 1.4, 5.2, 0.3), bayX, PAVEMENT_TOP + 4.2, -2.45, GLASS, Enum.Material.Glass)
		pane.Reflectance = 0.15
	end
	pitchedRoof(f, w, d, h, math.min(d * 0.32, 9))
	for i = 0, houses do
		local x = -w / 2 + i * hw
		if i == 0 then
			x += 1.2
		elseif i == houses then
			x -= 1.2
		end
		piece(f, Vector3.new(2.2, 5, 3.2), x, h + math.min(d * 0.32, 9) - 0.5, d / 2, wall, Enum.Material.Brick)
	end
	apron(f, w)
end

-- Georgian terraces: tall sash windows, a white ground floor or all white stucco, a cornice and parapet
local function georgian(s: Spec)
	local f, w, d, r = s.frame, s.w, s.d, s.random
	local storeyH = 11
	local h = s.storeys * storeyH
	local stucco = r:NextNumber() < 0.45
	local wall = if stucco then choose(STUCCO, r) else choose(STOCK_BRICK, r)
	local material = if stucco then Enum.Material.Plaster else Enum.Material.Brick
	piece(f, Vector3.new(w, h, d), 0, h / 2, d / 2, wall, material)
	local grid = { x0 = -w / 2, x1 = w / 2, y0 = 0, y1 = h, bay = 8, window = 4, storey = storeyH, pane = 7.4, sill = 2.6 }
	windows(f, "front", 0, grid, wall, material, nil, nil, WHITE_FRAME)
	if not stucco then
		-- The ground floor rendered white, as on so many London terraces
		piece(f, Vector3.new(w, storeyH, 1.1), 0, storeyH / 2, -0.45, choose(STUCCO, r), Enum.Material.Plaster)
		local glassFront = piece(f, Vector3.new(w - 2, 6.6, 0.3), 0, 2.6 + 3.3, -1.05, GLASS, Enum.Material.Glass)
		glassFront.Reflectance = 0.15
		-- piers between the ground floor windows
		local bays = math.max(1, math.round(w / 8))
		for i = 1, bays - 1 do
			piece(f, Vector3.new(3.8, 6.8, 0.5), -w / 2 + i * w / bays, 2.6 + 3.3, -1.2, choose(STUCCO, r), Enum.Material.Plaster)
		end
	end
	local houses = math.max(1, math.round(w / 24))
	for i = 0, houses - 1 do
		local x = -w / 2 + (i + 0.5) * w / houses - 4
		door(f, x, choose(DOORS, r))
	end
	cornice(f, w, h - 1.6, STONE_TRIM)
	if r:NextNumber() < 0.55 then
		-- A slate roof rising behind a low parapet
		piece(f, Vector3.new(w, 1.6, 0.8), 0, h + 0.8, 0.4, wall, material)
		pitchedRoof(f, w, d, h, math.min(d * 0.3, 9))
		chimneys(f, w, d, h + math.min(d * 0.3, 9) - 1, math.max(1, math.round(w / 24)), wall)
	else
		flatRoof(f, w, d, h, 2.6, wall, material, r)
	end
	-- Black railings along the front
	local rail = piece(f, Vector3.new(w - 1, 3, 0.2), 0, PAVEMENT_TOP + 1.5, -1.3, rgb(18, 18, 20), Enum.Material.Metal)
	rail.Transparency = 0.45
	rail.CastShadow = false
	apron(f, w)
end

-- A row of shops with flats above
local function shops(s: Spec)
	local f, w, d, r = s.frame, s.w, s.d, s.random
	local groundH, storeyH = 12, 10
	local h = groundH + (s.storeys - 1) * storeyH
	local roll = r:NextNumber()
	local wall = if roll < 0.55 then choose(RED_BRICK, r) elseif roll < 0.8 then choose(STOCK_BRICK, r) else choose(RENDER, r)
	local material = if roll < 0.8 then Enum.Material.Brick else Enum.Material.Plaster
	piece(f, Vector3.new(w, h, d), 0, h / 2, d / 2, wall, material)
	local units = math.max(1, math.round(w / 18))
	local uw = w / units
	for i = 0, units - 1 do
		local x = -w / 2 + (i + 0.5) * uw
		local glass = piece(f, Vector3.new(uw - 2.2, 7.6, 0.4), x, PAVEMENT_TOP + 4.4, -0.3, GLASS, Enum.Material.Glass)
		glass.Reflectance = 0.2
		local fasciaColour = choose(FASCIAS, r)
		local fascia = piece(f, Vector3.new(uw - 0.8, 2.3, 1), x, PAVEMENT_TOP + 9.9, -0.6, fasciaColour, Enum.Material.SmoothPlastic)
		if r:NextNumber() < 0.75 then
			local light = fasciaColour.R + fasciaColour.G + fasciaColour.B > 2
			sign(fascia, choose(SHOP_NAMES, r), if light then rgb(30, 30, 30) else rgb(245, 240, 225))
		end
		if r:NextNumber() < 0.25 then
			-- A sloping awning over the window
			-- (a wedge is tallest at its back, so this one is high against the wall and low at the pavement)
			local awning = box(Vector3.new(uw - 1.6, 1.8, 3.4), f * CFrame.new(x, PAVEMENT_TOP + 8.2, -1.9), choose(FASCIAS, r), Enum.Material.Fabric, "WedgePart")
			awning.CanCollide = false
		end
	end
	for i = 0, units do
		local pw = if i == 0 or i == units then 0.8 else 1.2
		local x = -w / 2 + i * uw + (if i == 0 then pw / 2 elseif i == units then -pw / 2 else 0)
		piece(f, Vector3.new(pw, groundH, 1), x, groundH / 2, -0.5, wall, material)
	end
	local grid = { x0 = -w / 2, x1 = w / 2, y0 = groundH, y1 = h, bay = 7, window = 3.8, storey = storeyH, pane = 6, sill = 2.4 }
	windows(f, "front", 0, grid, wall, material, nil, nil, WHITE_FRAME)
	if s.flank ~= 0 then
		local side = { x0 = -d / 2, x1 = d / 2, y0 = groundH, y1 = h, bay = 7, window = 3.8, storey = storeyH, pane = 6, sill = 2.4 }
		windows(f * CFrame.new(0, 0, d / 2), if s.flank > 0 then "right" else "left", s.flank * w / 2, side, wall, material, nil, nil, WHITE_FRAME)
	end
	if r:NextNumber() < 0.3 then
		cornice(f, w, h - 1, STONE_TRIM)
		flatRoof(f, w, d, h, 2, wall, material, r)
	else
		pitchedRoof(f, w, d, h, math.min(d * 0.32, 10))
		chimneys(f, w, d, h + math.min(d * 0.32, 10) - 1, math.max(1, math.round(w / 20)), wall)
	end
	drainpipe(f, w / 2 - 0.6, h)
	apron(f, w)
end

-- Red-brick mansion blocks with stone bands, and shops along the bottom on the busier streets
local function mansion(s: Spec)
	local f, w, d, r = s.frame, s.w, s.d, s.random
	local storeyH = 11
	local h = s.storeys * storeyH
	local wall = if r:NextNumber() < 0.75 then choose(RED_BRICK, r) else choose(STOCK_BRICK, r)
	piece(f, Vector3.new(w, h, d), 0, h / 2, d / 2, wall, Enum.Material.Brick)
	local withShops = r:NextNumber() < 0.4 and not s.back
	local y0 = 0
	if withShops then
		y0 = storeyH + 1
		local units = math.max(1, math.round(w / 20))
		local uw = w / units
		for i = 0, units - 1 do
			local x = -w / 2 + (i + 0.5) * uw
			local glass = piece(f, Vector3.new(uw - 2.4, 7.6, 0.4), x, PAVEMENT_TOP + 4.4, -0.3, GLASS, Enum.Material.Glass)
			glass.Reflectance = 0.2
			local fascia = piece(f, Vector3.new(uw - 1, 2.2, 1), x, PAVEMENT_TOP + 9.8, -0.6, choose(FASCIAS, r), Enum.Material.SmoothPlastic)
			if r:NextNumber() < 0.6 then
				sign(fascia, choose(SHOP_NAMES, r), rgb(245, 240, 225))
			end
		end
		piece(f, Vector3.new(w, 1.4, 1.2), 0, y0 - 0.7, -0.6, STONE_TRIM, Enum.Material.Limestone)
	end
	local grid = { x0 = -w / 2, x1 = w / 2, y0 = y0, y1 = h, bay = 9, window = 4.4, storey = storeyH, pane = 7, sill = 2.6 }
	windows(f, "front", 0, grid, wall, Enum.Material.Brick, STONE_TRIM, nil, WHITE_FRAME)
	windows(f, "back", d, grid, wall, Enum.Material.Brick, nil)
	if s.flank ~= 0 then
		local side = { x0 = -d / 2, x1 = d / 2, y0 = y0, y1 = h, bay = 9, window = 4.4, storey = storeyH, pane = 7, sill = 2.6 }
		windows(f * CFrame.new(0, 0, d / 2), if s.flank > 0 then "right" else "left", s.flank * w / 2, side, wall, Enum.Material.Brick, STONE_TRIM, nil, WHITE_FRAME)
	end
	if not withShops then
		door(f, 0, choose(DOORS, r), 5)
	end
	cornice(f, w, h - 0.6, STONE_TRIM)
	-- A slate mansard roof with a storey in it
	piece(f, Vector3.new(w - 1, 8, d - 6), 0, h + 4, d / 2, SLATE, Enum.Material.Slate)
	apron(f, w)
end

-- Portland stone offices and government buildings
local function stone(s: Spec)
	local f, w, d, r = s.frame, s.w, s.d, s.random
	local storeyH = 11.5
	local h = s.storeys * storeyH
	local wall = PORTLAND
	piece(f, Vector3.new(w, h, d), 0, h / 2, d / 2, wall, Enum.Material.Limestone)
	-- A heavier base storey
	piece(f, Vector3.new(w, storeyH + 1, 1.2), 0, (storeyH + 1) / 2, -0.5, rgb(206, 198, 180), Enum.Material.Limestone)
	local baseGlass = piece(f, Vector3.new(w - 3, 7.5, 0.3), 0, PAVEMENT_TOP + 4.6, -1.15, GLASS, Enum.Material.Glass)
	baseGlass.Reflectance = 0.15
	local bays = math.max(1, math.round(w / 10))
	for i = 0, bays do
		local x = -w / 2 + i * w / bays
		piece(f, Vector3.new(if i == 0 or i == bays then 2 else 3.4, 8, 0.6), math.clamp(x, -w / 2 + 1, w / 2 - 1), PAVEMENT_TOP + 4.6, -1.3, rgb(206, 198, 180), Enum.Material.Limestone)
	end
	local grid = { x0 = -w / 2, x1 = w / 2, y0 = storeyH + 1, y1 = h, bay = 9, window = 4.2, storey = storeyH, pane = 7.6, sill = 2.4 }
	windows(f, "front", 0, grid, wall, Enum.Material.Limestone, nil, nil, Color3.fromRGB(64, 66, 70))
	windows(f, "back", d, grid, wall, Enum.Material.Limestone, nil)
	if s.flank ~= 0 then
		local side = { x0 = -d / 2, x1 = d / 2, y0 = storeyH + 1, y1 = h, bay = 9, window = 4.2, storey = storeyH, pane = 7.6, sill = 2.4 }
		windows(f * CFrame.new(0, 0, d / 2), if s.flank > 0 then "right" else "left", s.flank * w / 2, side, wall, Enum.Material.Limestone, nil, nil, Color3.fromRGB(64, 66, 70))
	end
	door(f, 0, rgb(30, 30, 32), 6)
	cornice(f, w, h - 0.4, STONE_TRIM, 2)
	-- A set-back top storey
	piece(f, Vector3.new(w - 4, storeyH - 2, d - 8), 0, h + (storeyH - 2) / 2, d / 2 + 1, rgb(210, 204, 190), Enum.Material.Limestone)
	flatRoof(f, w - 4, d - 8, h + storeyH - 2, 0, wall, Enum.Material.Limestone, r)
	apron(f, w)
end

-- Glass and steel offices. Taller ones stand on a podium.
local function office(s: Spec)
	local f, w, d, r = s.frame, s.w, s.d, s.random
	local storeyH = 12
	local storeys = s.storeys
	local glassColour = choose(OFFICE_GLASS, r)
	local frameColour = if r:NextNumber() < 0.5 then rgb(70, 72, 76) else rgb(200, 200, 196)
	if storeys <= 11 and r:NextNumber() < 0.5 then
		-- A stone or concrete framed office with a grid of big windows
		local h = storeys * storeyH
		local wall = if r:NextNumber() < 0.5 then PORTLAND else choose(CONCRETE, r)
		piece(f, Vector3.new(w, h, d), 0, h / 2, d / 2, wall, Enum.Material.Concrete)
		local grid = { x0 = -w / 2, x1 = w / 2, y0 = storeyH, y1 = h, bay = 10, window = 7, storey = storeyH, pane = 8, sill = 2 }
		windows(f, "front", 0, grid, wall, Enum.Material.Concrete, nil, glassColour, Color3.fromRGB(64, 66, 70))
		windows(f, "back", d, grid, wall, Enum.Material.Concrete, nil, glassColour)
		if s.flank ~= 0 then
			local side = { x0 = -d / 2, x1 = d / 2, y0 = storeyH, y1 = h, bay = 10, window = 7, storey = storeyH, pane = 8, sill = 2 }
			windows(f * CFrame.new(0, 0, d / 2), if s.flank > 0 then "right" else "left", s.flank * w / 2, side, wall, Enum.Material.Concrete, nil, glassColour, Color3.fromRGB(64, 66, 70))
		end
		local lobby = piece(f, Vector3.new(w - 2, storeyH - 1.5, 0.4), 0, PAVEMENT_TOP + (storeyH - 1.5) / 2, -0.3, glassColour, Enum.Material.Glass)
		lobby.Reflectance = 0.25
		flatRoof(f, w, d, h, 1.5, wall, Enum.Material.Concrete, r)
		apron(f, w)
		return
	end
	-- Curtain-wall glass: the whole body is glass, with a band round it at every floor
	local podium = if storeys > 12 then 3 else 0
	local tw, td = w, d
	local towerZ = d / 2
	if podium > 0 then
		local ph = podium * storeyH
		local podiumWall = choose(CONCRETE, r)
		piece(f, Vector3.new(w, ph, d), 0, ph / 2, d / 2, podiumWall, Enum.Material.Concrete)
		local lobby = piece(f, Vector3.new(w - 2, storeyH * 2 - 1, 0.4), 0, PAVEMENT_TOP + storeyH - 0.5, -0.3, glassColour, Enum.Material.Glass)
		lobby.Reflectance = 0.25
		-- Windows round the podium's upper floor
		local podiumGrid = { x0 = -w / 2, x1 = w / 2, y0 = storeyH * 2, y1 = ph, bay = 10, window = 7, storey = storeyH, pane = 7, sill = 2.5 }
		windows(f, "back", d, { x0 = -w / 2, x1 = w / 2, y0 = 2, y1 = ph, bay = 10, window = 7, storey = storeyH, pane = 7, sill = 2.5 }, podiumWall, Enum.Material.Concrete, nil, glassColour)
		windows(f, "front", 0, podiumGrid, podiumWall, Enum.Material.Concrete, nil, glassColour)
		local sideGrid = { x0 = -d / 2, x1 = d / 2, y0 = 2, y1 = ph, bay = 10, window = 7, storey = storeyH, pane = 7, sill = 2.5 }
		windows(f * CFrame.new(0, 0, d / 2), "right", w / 2, sideGrid, podiumWall, Enum.Material.Concrete, nil, glassColour)
		windows(f * CFrame.new(0, 0, d / 2), "left", -w / 2, sideGrid, podiumWall, Enum.Material.Concrete, nil, glassColour)
		tw, td = w * r:NextNumber(0.7, 0.88), d * r:NextNumber(0.7, 0.88)
		towerZ = d / 2 + r:NextNumber(-1, 1) * (d - td) / 4
		local body = piece(f, Vector3.new(tw, (storeys - podium) * storeyH, td), 0, ph + (storeys - podium) * storeyH / 2, towerZ, glassColour, Enum.Material.Glass)
		body.Reflectance = 0.3
		for k = podium + 1, storeys do
			piece(f, Vector3.new(tw + 0.4, 1, td + 0.4), 0, k * storeyH - 0.5, towerZ, frameColour, Enum.Material.Metal)
		end
		flatRoof(f * CFrame.new(0, 0, towerZ - td / 2), tw, td, storeys * storeyH, 2, frameColour, Enum.Material.Metal, r)
	else
		local h = storeys * storeyH
		local body = piece(f, Vector3.new(w, h, d), 0, h / 2, d / 2, glassColour, Enum.Material.Glass)
		body.Reflectance = 0.3
		for k = 1, storeys do
			piece(f, Vector3.new(w + 0.4, 1, d + 0.4), 0, k * storeyH - 0.5, d / 2, frameColour, Enum.Material.Metal)
		end
		flatRoof(f, w, d, h, 2, frameColour, Enum.Material.Metal, r)
	end
	-- Corner columns
	for _, cx in { -tw / 2, tw / 2 } do
		for _, cz in { towerZ - td / 2, towerZ + td / 2 } do
			piece(f, Vector3.new(1.2, storeys * storeyH, 1.2), cx, storeys * storeyH / 2, cz, frameColour, Enum.Material.Metal)
		end
	end
	apron(f, w)
end

-- 1960s concrete: ribbon windows and plain bands
local function concrete(s: Spec)
	local f, w, d, r = s.frame, s.w, s.d, s.random
	local storeyH = 10.5
	local h = s.storeys * storeyH
	local wall = choose(CONCRETE, r)
	piece(f, Vector3.new(w, h, d), 0, h / 2, d / 2, wall, Enum.Material.Concrete)
	local ribbon = r:NextNumber() < 0.5
	local grid = { x0 = -w / 2, x1 = w / 2, y0 = storeyH, y1 = h, bay = if ribbon then 6 else 8, window = if ribbon then 5.4 else 5, storey = storeyH, pane = if ribbon then 4.8 else 6, sill = 3 }
	windows(f, "front", 0, grid, wall, Enum.Material.Concrete, nil)
	windows(f, "back", d, grid, wall, Enum.Material.Concrete, nil)
	if s.flank ~= 0 then
		local side = { x0 = -d / 2, x1 = d / 2, y0 = storeyH, y1 = h, bay = grid.bay, window = grid.window, storey = storeyH, pane = grid.pane, sill = 3 }
		windows(f * CFrame.new(0, 0, d / 2), if s.flank > 0 then "right" else "left", s.flank * w / 2, side, wall, Enum.Material.Concrete, nil)
	end
	local lobby = piece(f, Vector3.new(w - 6, storeyH - 2, 0.4), 0, PAVEMENT_TOP + (storeyH - 2) / 2, -0.3, GLASS, Enum.Material.Glass)
	lobby.Reflectance = 0.2
	flatRoof(f, w, d, h, 1.2, wall, Enum.Material.Concrete, r)
	apron(f, w)
end

-- Victorian brick warehouses, with a column of loading doors and a hoist beam
local function warehouse(s: Spec)
	local f, w, d, r = s.frame, s.w, s.d, s.random
	local storeyH = 11
	local h = s.storeys * storeyH
	local wall = choose({ rgb(118, 58, 44), rgb(104, 54, 42), rgb(132, 70, 52), rgb(150, 128, 98) }, r)
	piece(f, Vector3.new(w, h, d), 0, h / 2, d / 2, wall, Enum.Material.Brick)
	local grid = { x0 = -w / 2, x1 = w / 2, y0 = 0, y1 = h, bay = 8, window = 3.6, storey = storeyH, pane = 5.6, sill = 3.2 }
	windows(f, "front", 0, grid, wall, Enum.Material.Brick, nil, nil, Color3.fromRGB(40, 40, 42))
	windows(f, "back", d, grid, wall, Enum.Material.Brick, nil)
	local doorsX = r:NextNumber(-w / 4, w / 4)
	piece(f, Vector3.new(5, h - 4, 0.8), doorsX, (h - 4) / 2 + 1, -0.7, rgb(60, 40, 28), Enum.Material.WoodPlanks)
	piece(f, Vector3.new(0.8, 0.8, 4), doorsX, h - 1.5, -2, rgb(30, 30, 32), Enum.Material.Metal)
	flatRoof(f, w, d, h, 2.5, wall, Enum.Material.Brick, r)
	apron(f, w)
end

-- Industrial units: metal cladding, roller doors, a shallow roof
local function shed(s: Spec)
	local f, w, d, r = s.frame, s.w, s.d, s.random
	local h = 18
	local wall = choose(CLADDING, r)
	piece(f, Vector3.new(w, h, d), 0, h / 2, d / 2, wall, Enum.Material.Metal)
	local doors = math.max(1, math.floor(w / 30))
	for i = 1, doors do
		local x = -w / 2 + i * w / (doors + 1)
		piece(f, Vector3.new(12, 13, 0.5), x, 6.5, -0.3, rgb(120, 122, 126), Enum.Material.DiamondPlate)
	end
	local office = piece(f, Vector3.new(math.min(14, w * 0.25), 3.5, 0.4), -w / 2 + math.min(14, w * 0.25) / 2 + 1, 12, -0.3, GLASS, Enum.Material.Glass)
	office.Reflectance = 0.2
	local board = piece(f, Vector3.new(math.min(w * 0.5, 30), 3, 0.6), 0, h - 2.2, -0.5, rgb(240, 240, 236), Enum.Material.SmoothPlastic)
	sign(board, choose(FIRM_NAMES, r), choose({ rgb(20, 60, 140), rgb(170, 30, 30), rgb(20, 20, 22), rgb(20, 110, 60) }, r))
	pitchedRoof(f, w, d, h, 3, rgb(150, 154, 158))
	-- A yard of concrete in front, for vans
	piece(f, Vector3.new(w, PAVEMENT_TOP, 1.6), 0, PAVEMENT_TOP / 2, -0.7, rgb(160, 160, 156), Enum.Material.Concrete)
end

-- Council tower blocks: concrete with a balcony on every floor
local function council(s: Spec)
	local f, w, d, r = s.frame, s.w, s.d, s.random
	local storeyH = 9.5
	local h = s.storeys * storeyH
	local wall = choose({ rgb(196, 190, 176), rgb(170, 168, 160), rgb(150, 110, 90), rgb(188, 180, 160) }, r)
	piece(f, Vector3.new(w, h, d), 0, h / 2, d / 2, wall, Enum.Material.Concrete)
	local grid = { x0 = -w / 2, x1 = w / 2, y0 = storeyH, y1 = h, bay = 9, window = 5.4, storey = storeyH, pane = 5, sill = 2.6 }
	windows(f, "front", 0, grid, wall, Enum.Material.Concrete, nil, nil, WHITE_FRAME)
	windows(f, "back", d, grid, wall, Enum.Material.Concrete, nil)
	local balcony = choose({ rgb(60, 90, 140), rgb(170, 60, 40), rgb(230, 230, 225), rgb(70, 120, 80) }, r)
	for k = 1, s.storeys - 1 do
		local panel = piece(f, Vector3.new(w - 6, 3.4, 0.4), 0, k * storeyH + 1.7, -3, balcony, Enum.Material.SmoothPlastic)
		panel.CastShadow = false
		piece(f, Vector3.new(w - 6, 0.5, 3), 0, k * storeyH + 0.25, -1.5, wall, Enum.Material.Concrete)
	end
	door(f, 0, rgb(40, 60, 90), 6)
	piece(f, Vector3.new(10, 8, 10), 0, h + 4, d / 2, wall, Enum.Material.Concrete)
	flatRoof(f, w, d, h, 1.2, wall, Enum.Material.Concrete, r)
	apron(f, w)
end

-- A corner pub: painted ground floor with big windows and the name in gold, brick above, a hanging sign
local function pub(s: Spec)
	local f, w, d, r = s.frame, s.w, s.d, s.random
	local groundH, storeyH = 12, 10.5
	local h = groundH + (s.storeys - 1) * storeyH
	local wall = choose(RED_BRICK, r)
	piece(f, Vector3.new(w, h, d), 0, h / 2, d / 2, wall, Enum.Material.Brick)
	local paint = choose(PUB_PAINT, r)
	local name = choose(PUB_NAMES, r)
	local function groundFloor(face: CFrame, length: number)
		piece(face, Vector3.new(length, groundH, 1.2), 0, groundH / 2, -0.5, paint, Enum.Material.Wood)
		local panes = math.max(1, math.round(length / 12))
		for i = 0, panes - 1 do
			local x = -length / 2 + (i + 0.5) * length / panes
			local glass = piece(face, Vector3.new(length / panes - 3, 6.5, 0.3), x, PAVEMENT_TOP + 4.6, -1.15, rgb(60, 45, 30), Enum.Material.Glass)
			glass.Reflectance = 0.25
		end
		local fascia = piece(face, Vector3.new(length - 1, 2.4, 0.6), 0, groundH - 1.6, -1.25, paint, Enum.Material.Wood)
		sign(fascia, name, rgb(214, 178, 90))
	end
	groundFloor(f, w)
	if s.flank ~= 0 then
		local side = f * CFrame.new(s.flank * w / 2, 0, d / 2) * CFrame.Angles(0, -s.flank * math.pi / 2, 0)
		groundFloor(side, d)
		local sideGrid = { x0 = -d / 2, x1 = d / 2, y0 = groundH, y1 = h, bay = 8, window = 4, storey = storeyH, pane = 6.4, sill = 2.4 }
		windows(f * CFrame.new(0, 0, d / 2), if s.flank > 0 then "right" else "left", s.flank * w / 2, sideGrid, wall, Enum.Material.Brick, nil, nil, WHITE_FRAME)
	end
	local grid = { x0 = -w / 2, x1 = w / 2, y0 = groundH, y1 = h, bay = 8, window = 4, storey = storeyH, pane = 6.4, sill = 2.4 }
	windows(f, "front", 0, grid, wall, Enum.Material.Brick, nil, nil, WHITE_FRAME)
	-- The hanging sign on its bracket, at the corner
	local cornerX = if s.flank ~= 0 then s.flank * (w / 2 - 1) else w / 2 - 2
	piece(f, Vector3.new(0.4, 0.4, 3.2), cornerX, groundH + 3, -1.6, rgb(20, 20, 20), Enum.Material.Metal)
	local board = piece(f, Vector3.new(0.4, 3.6, 2.8), cornerX, groundH + 0.8, -2.6, paint, Enum.Material.Wood)
	board.CanCollide = false
	cornice(f, w, h - 0.8, STONE_TRIM)
	if r:NextNumber() < 0.5 then
		pitchedRoof(f, w, d, h, math.min(d * 0.3, 9))
	else
		flatRoof(f, w, d, h, 2, wall, Enum.Material.Brick, r)
	end
	apron(f, w)
end

-- A corner shop with flats above
local function corner(s: Spec)
	shops(s)
end

-- Plain blocks for the edge of the map, seen from a distance
local function backdrop(s: Spec)
	local f, w, d, r = s.frame, s.w, s.d, s.random
	local storeyH = 10.5
	local h = s.storeys * storeyH
	local roll = r:NextNumber()
	local wall = if roll < 0.45 then choose(RED_BRICK, r) elseif roll < 0.7 then choose(STOCK_BRICK, r) else choose(CONCRETE, r)
	local material = if roll < 0.7 then Enum.Material.Brick else Enum.Material.Concrete
	piece(f, Vector3.new(w, h, d), 0, h / 2, d / 2, wall, material)
	local grid = { x0 = -w / 2, x1 = w / 2, y0 = 2, y1 = h, bay = 9, window = 4.6, storey = storeyH, pane = 6, sill = 2.4 }
	windows(f, "front", 0, grid, wall, material, nil)
	if roll < 0.75 then
		pitchedRoof(f, w, d, h, math.min(d * 0.3, 12))
	else
		flatRoof(f, w, d, h, 1.5, wall, material, r)
	end
end

local BUILDERS: { [string]: (Spec) -> () } = {
	victorian = victorian,
	georgian = georgian,
	shops = shops,
	mansion = mansion,
	stone = stone,
	office = office,
	concrete = concrete,
	warehouse = warehouse,
	shed = shed,
	council = council,
	pub = pub,
	corner = corner,
	backdrop = backdrop,
}

function CityBuildings.has(style: string): boolean
	return BUILDERS[style] ~= nil
end

-- Builds one building and returns its Model (see the top of this file)
function CityBuildings.build(style: string, frame: CFrame, width: number, depth: number, storeys: number, seed: number, flank: number, isBack: boolean): Model
	local model = Instance.new("Model")
	model.Name = style
	local parent = TownKit.getParent()
	TownKit.setParent(model)
	local builder = BUILDERS[style] or georgian
	builder({ frame = frame, w = width, d = depth, storeys = math.max(1, storeys), random = Random.new(seed), flank = flank, back = isBack })
	TownKit.setParent(parent :: Instance)
	-- Only the main body is solid. Everything else (window strips, bars, sills, roofs, chimneys, signs) is just
	-- for looks, so it's taken out of the physics engine: hundreds of thousands of physics parts used gigabytes
	-- of memory and made the game freeze. Thin details don't cast shadows either: far cheaper to draw.
	local body = model:FindFirstChildWhichIsA("BasePart")
	for _, part in model:GetChildren() do
		if part:IsA("BasePart") then
			part.CanTouch = false
			if part ~= body then
				part.CanCollide = false
				part.CanQuery = false
			end
			local size = part.Size
			if math.min(size.X, size.Y, size.Z) < 1.6 then
				part.CastShadow = false
			end
		end
	end
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	model.Parent = parent
	return model
end

return CityBuildings
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
	-- Thick enough that the far end of a street fades into grey, like BVS, so the city seems to go on forever
	atmosphere.Density = 0.36
	atmosphere.Offset = 0.2
	atmosphere.Color = Color3.fromRGB(202, 204, 208)
	atmosphere.Decay = Color3.fromRGB(112, 118, 130)
	atmosphere.Glare = 0.15
	atmosphere.Haze = 1.7

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
put(folder4, "ModuleScript", "LondonFill", [[
--!nocheck
-- Everything that fills London's blocks, as data. MADE BY tools/london_fill.py (run tools/london_layout.py):
-- don't edit this file by hand. LondonMap builds it. The rows themselves are in LondonFillData1, 2...
--   styles: names used by buildings (kit building names, or CityBuildings styles)
--   buildings: { kit (1) or parts (0), style index, front x, front z, turn (degrees), width, depth, storeys, seed, back (1/0), flank }
--     the front edge is centred on (x, z); turn 0 faces north (-z)
--     flank: on a corner, 1 if the building's right side faces a street too, -1 its left side, 0 neither
--   gardens: { kind (1 lawn, 2 yard, 3 car park), front x, front z, turn, width, depth }
--   walls: { kind (1 brick, 2 fence, 3 hedge, 4 railing), x0, z0, x1, z1 }
--   trees: { x, z, size, form (1 round, 2 tall, 3 wide, 4 bush) }

local fill = {
	styles = { "concrete", "corner", "council", "darwick", "detached_a", "detached_b", "detached_c", "detached_d", "duggen", "georgian", "gosford", "gosford_double", "mansion", "mitchell", "morton", "office", "pub", "semi_a", "semi_b", "semi_c", "shed", "shop_1", "shop_2", "shop_3", "shop_4", "shop_5", "shop_6", "shop_7", "shops", "stone", "terrace_a", "terrace_b", "victorian", "warehouse", "windsor" },
	buildings = {},
	gardens = {},
	walls = {},
	trees = {},
}
for i = 1, 4 do
	local part = require(script.Parent:FindFirstChild("LondonFillData" .. i))
	for kind, rows in part do
		for _, row in rows do
			table.insert(fill[kind], row)
		end
	end
end
return fill
]])
put(folder4, "ModuleScript", "LondonFillData1", [[
--!nocheck
-- Part 1 of the data in LondonFill. MADE BY tools/london_fill.py: don't edit by hand.
return {
	buildings = {
		{0,2,3353.8,324.5,-40.8,34.0,34,4,9381,0,-1},{0,2,3485.0,118.3,90.5,34.0,34,4,9610,0,-1},{0,17,3362.0,-598.3,60.9,34.0,34,3,1323,0,-1},{0,17,3294.2,-774.6,105.4,34.0,34,3,7368,0,-1},{0,17,2964.6,-1388.2,78.9,34.0,34,3,5149,0,-1},{0,17,2847.1,-1529.2,122.0,34.0,34,3,5697,0,-1},{0,2,2311.9,-2064.9,99.5,34.0,34,4,6167,0,-1},{0,2,2133.0,-2150.5,151.9,34.0,34,3,5578,0,-1},
		{0,17,1338.6,-2383.9,124.2,34.0,34,3,4713,0,-1},{0,17,1127.2,-2350.6,-167.6,34.0,34,3,406,0,-1},{0,2,339.8,-2262.2,133.0,34.0,34,4,5957,0,-1},{0,17,163.7,-2266.2,168.9,34.0,34,3,6534,0,-1},{0,2,-823.1,-2344.5,135.7,34.0,34,4,1908,0,-1},{0,17,-1013.7,-2321.5,-177.7,34.0,34,3,6524,0,-1},{0,2,-1798.0,-2182.5,149.0,34.0,34,4,6881,0,-1},{0,2,-1979.3,-2079.4,-149.0,34.0,34,4,8405,0,-1},
		{0,2,-2392.1,-1714.7,-179.6,34.0,34,3,9430,0,-1},{0,17,-2503.4,-1561.6,-132.0,34.0,34,3,801,0,-1},{0,2,-2809.8,-1052.9,-156.5,34.0,34,3,7036,0,-1},{0,17,-2851.5,-858.7,-104.4,34.0,34,3,3751,0,-1},{0,2,-2954.5,-246.7,-141.5,34.0,34,3,7485,0,-1},{0,2,-2909.3,-34.1,-72.4,34.0,34,4,9172,0,-1},{0,33,3231.7,1311.0,80.8,50.0,11.1,2,9800,0,0},{0,33,3247.1,1221.7,87.4,65.7,10.7,3,6397,0,0},
		{0,33,3255.8,1125.8,84.6,29.2,26.4,3,423,0,0},{0,33,3257.3,1097.5,89.6,27.4,30.7,2,8153,0,0},{0,33,3256.4,1073.3,95.3,21.0,28.9,2,7105,0,0},{0,33,3253.0,1050.4,101.1,25.4,32.3,3,560,0,0},{0,33,3246.4,1024.6,107.2,28.0,31.3,2,7403,0,0},{0,33,3236.9,999.1,114.1,26.5,30.9,2,2116,0,0},{0,33,3225.9,977.4,119.9,22.2,33.4,2,2628,0,0},{0,33,3215.0,960.1,124.7,18.6,31.2,2,6279,0,0},
		{0,33,3201.2,942.4,130.4,26.3,31.0,3,4714,0,0},{0,33,3184.4,924.4,135.9,23.1,28.7,3,1550,0,0},{0,33,3161.8,905.3,142.5,36.1,33.7,3,5414,0,0},{1,32,3106.6,866.5,145.8,98.8,28.0,0,2990,0,0},{1,19,3044.2,824.0,145.8,52.3,28.2,0,2569,0,0},{0,33,3011.7,801.4,141.1,12.1,31.7,3,9107,0,0},{1,31,2943.0,711.1,126.5,98.9,36.8,0,4321,0,0},{0,33,2904.4,659.1,126.5,30.7,28.4,3,3040,0,0},
		{0,33,2883.4,630.8,126.6,39.8,31.5,2,4769,0,0},{0,33,2859.7,600.4,129.5,37.3,28.1,3,6792,0,0},{0,33,2835.2,573.0,134.1,36.3,29.9,2,9195,0,0},{0,33,2764.9,469.2,8.8,38.4,30.0,2,4866,0,0},{0,33,2803.6,463.2,8.8,40.0,33.4,3,3235,0,0},{1,32,2872.2,452.5,8.8,98.8,28.0,0,1845,0,0},{0,33,2934.7,442.8,8.8,27.6,31.1,3,472,0,0},{0,33,2970.1,436.6,10.5,44.3,30.3,3,3598,0,0},
		{0,33,3008.4,428.7,13.4,34.0,28.2,3,4178,0,0},{0,33,3042.2,419.4,17.3,36.0,28.1,3,6847,0,0},{1,31,3106.0,397.4,19.7,98.9,36.8,0,9727,0,0},{1,31,3199.1,364.1,19.7,98.9,36.8,0,623,0,0},{0,33,3277.3,336.2,19.7,67.2,31.1,3,5583,0,0},{0,33,3379.5,336.9,-21.4,23.0,29.9,2,3979,0,0},{0,33,3512.6,162.4,129.4,9.5,32.1,2,6539,0,0},{1,31,3484.4,51.9,90.5,98.9,36.8,0,3810,0,0},
		{1,31,3483.6,-47.0,90.5,98.9,36.8,0,3293,0,0},{0,33,3482.9,-119.6,90.5,46.1,32.9,3,3079,0,0},{0,33,3483.6,-166.3,87.9,47.3,13.5,3,8573,0,0},{0,33,3484.0,-199.1,92.6,18.5,28.5,3,8958,0,0},{0,33,3481.1,-219.3,102.8,22.4,32.4,2,8740,0,0},{1,32,3462.4,-276.9,109.2,98.8,28.0,0,9542,0,0},{1,31,3429.6,-370.1,109.6,98.9,36.8,0,6444,0,0},{1,32,3396.4,-463.3,109.6,98.8,28.0,0,8464,0,0},
		{0,33,3372.5,-530.6,109.6,44.2,33.8,2,1402,0,0},{0,33,3334.8,-736.6,140.6,16.8,31.3,3,682,0,0},{0,33,3282.4,-817.6,105.4,55.1,29.1,3,4839,0,0},{1,31,3261.9,-891.9,105.4,98.9,36.8,0,6368,0,0},{0,33,3245.2,-952.3,105.9,26.4,31.6,3,6925,0,0},{0,33,3213.6,-1039.9,113.8,39.8,28.9,2,1912,0,0},{0,33,3192.6,-1081.9,118.7,54.3,28.0,3,1043,0,0},{0,33,3170.6,-1119.5,123.0,32.8,31.7,2,1742,0,0},
		{1,19,3145.8,-1154.0,127.5,52.3,28.2,0,1199,0,0},{1,32,3092.9,-1218.0,130.6,98.8,28.0,0,5699,0,0},{1,31,3028.6,-1293.1,130.6,98.9,36.8,0,9103,0,0},{0,33,2989.9,-1338.1,130.6,19.8,32.1,3,9590,0,0},{0,33,2963.6,-1413.8,95.6,17.4,33.9,3,5113,0,0},{0,33,2895.0,-1505.3,159.4,12.5,29.0,3,8295,0,0},{1,31,2811.9,-1585.6,122.0,98.9,36.8,0,8081,0,0},{1,31,2759.4,-1669.4,122.0,98.9,36.8,0,7586,0,0},
		{0,33,2722.0,-1728.7,123.0,41.3,32.7,3,9665,0,0},{0,33,2665.5,-1804.8,130.1,31.2,29.6,3,4320,0,0},{0,33,2642.6,-1829.6,135.2,36.3,33.8,2,4390,0,0},{0,33,2540.1,-1912.2,146.9,28.6,30.4,2,173,0,0},{1,32,2485.8,-1945.4,149.0,98.8,28.0,0,2140,0,0},{1,32,2401.1,-1996.3,149.0,98.8,28.0,0,6794,0,0},{0,33,2351.3,-2026.2,149.0,17.3,33.1,3,5551,0,0},{0,33,2186.4,-2153.7,-170.6,12.4,31.8,3,5352,0,0},
		{1,31,2074.4,-2181.8,151.9,98.9,36.8,0,7490,0,0},{1,32,1987.1,-2228.3,151.9,98.8,28.0,0,6053,0,0},{1,32,1900.0,-2274.8,151.9,98.8,28.0,0,8831,0,0},{0,33,1727.5,-2345.6,172.7,27.4,31.4,2,464,0,0},{1,31,1664.5,-2350.1,176.9,98.9,36.8,0,3036,0,0},{1,32,1565.8,-2355.9,176.3,98.8,28.0,0,3791,0,0},{1,12,1498.9,-2360.2,176.3,35.3,29.0,0,5592,0,0},{0,33,1450.4,-2363.3,176.3,47.1,30.9,3,4098,0,0},
		{0,33,1404.5,-2366.2,176.3,45.0,28.1,3,4160,0,0},{0,33,1323.2,-2398.5,138.8,8.4,30.2,3,4982,0,0},{1,31,1062.4,-2336.3,-167.6,98.9,36.8,0,6732,0,0},{0,33,985.8,-2319.4,-167.6,57.9,31.9,3,7907,0,0},{1,32,909.2,-2302.6,-167.6,98.8,28.0,0,8560,0,0},{1,31,812.6,-2281.9,-168.2,98.9,36.8,0,5565,0,0},{1,12,696.3,-2264.3,-176.2,35.3,29.0,0,8651,0,0},{1,31,621.2,-2260.8,-177.7,98.9,36.8,0,9984,0,0},
		{1,18,545.7,-2257.7,-177.7,52.3,28.2,0,3947,0,0},{1,32,463.3,-2254.4,-177.7,98.8,28.0,0,8417,0,0},{0,33,399.7,-2251.8,-177.7,28.6,32.7,3,2240,0,0},{0,33,322.1,-2276.3,144.4,11.4,30.0,3,8728,0,0},{0,33,215.6,-2285.5,-155.6,16.3,28.9,2,2359,0,0},{1,32,98.6,-2279.0,168.9,98.8,28.0,0,9388,0,0},{1,32,1.6,-2298.1,168.9,98.8,28.0,0,566,0,0},{1,31,-95.4,-2317.2,168.9,98.9,36.8,0,2933,0,0},
		{1,32,-192.4,-2336.3,168.9,98.8,28.0,0,5844,0,0},{0,33,-268.6,-2351.1,169.1,56.5,32.5,2,6782,0,0},{0,33,-360.9,-2362.8,178.3,30.0,32.1,3,2540,0,0},{0,33,-392.1,-2362.6,-177.7,32.4,31.0,3,124,0,0},{1,31,-457.6,-2358.3,-175.8,98.9,36.8,0,4215,0,0},{1,31,-556.3,-2351.2,-175.8,98.9,36.8,0,8246,0,0},{1,32,-654.9,-2344.0,-175.8,98.8,28.0,0,6928,0,0},{0,33,-721.5,-2339.2,-175.8,34.8,33.1,2,3681,0,0},
		{0,33,-757.9,-2336.5,-175.8,38.3,30.2,3,6934,0,0},{1,31,-1080.1,-2318.9,-177.7,98.9,36.8,0,3428,0,0},{1,19,-1155.6,-2315.8,-177.7,52.3,28.2,0,7217,0,0},{1,31,-1240.9,-2312.4,-177.7,98.9,36.8,0,3458,0,0},{0,33,-1305.8,-2309.6,-176.7,31.1,28.5,2,1887,0,0},{0,33,-1338.4,-2307.1,-174.6,34.3,33.7,3,500,0,0},{0,33,-1433.0,-2292.8,-168.8,26.4,31.1,3,5803,0,0},{0,33,-1475.1,-2281.5,-163.4,60.9,31.4,3,7472,0,0},
		{1,32,-1550.9,-2256.3,-160.5,98.8,28.0,0,791,0,0},{1,20,-1627.6,-2229.1,-160.4,64.1,41.3,0,5346,0,0},{1,18,-1691.0,-2206.6,-160.4,52.3,28.2,0,7677,0,0},{0,33,-1737.0,-2190.2,-160.4,30.6,31.2,2,4524,0,0},{0,33,-1953.3,-2129.3,-114.4,18.0,28.3,3,9247,0,0},{1,32,-2036.2,-2045.2,-149.0,98.8,28.0,0,9421,0,0},{1,19,-2101.0,-2006.3,-149.0,52.3,28.2,0,8861,0,0},{0,33,-2142.1,-1981.2,-147.7,31.9,28.6,2,2756,0,0},
		{0,33,-2169.0,-1962.5,-142.9,33.7,32.5,2,9863,0,0},{0,33,-2193.9,-1941.8,-137.4,31.2,30.0,2,5031,0,0},{1,32,-2272.8,-1848.4,-127.5,98.8,28.0,0,5122,0,0},{0,33,-2317.3,-1790.3,-127.5,47.5,31.6,3,3091,0,0},{0,33,-2343.1,-1756.6,-127.5,37.3,31.5,3,8683,0,0},{0,33,-2416.4,-1708.6,-163.1,16.0,30.3,2,8676,0,0},{1,31,-2547.8,-1512.2,-132.0,98.9,36.8,0,3950,0,0},{0,33,-2594.2,-1460.6,-132.0,39.8,32.6,2,5792,0,0},
		{1,32,-2640.6,-1409.1,-132.0,98.8,28.0,0,8690,0,0},{0,33,-2700.6,-1335.1,-121.0,21.0,32.8,3,6569,0,0},{0,33,-2710.2,-1317.2,-115.6,19.8,32.5,2,8598,0,0},{0,33,-2720.7,-1290.8,-109.5,37.2,33.6,2,3581,0,0},{1,32,-2741.8,-1226.1,-107.5,98.8,28.0,0,9214,0,0},{0,33,-2763.5,-1157.2,-107.5,45.7,32.0,3,7651,0,0},{0,33,-2777.2,-1113.8,-107.5,45.4,33.6,2,7889,0,0},{0,33,-2867.0,-908.5,-67.5,9.8,31.9,3,3353,0,0},
		{1,32,-2868.0,-794.4,-104.4,98.8,28.0,0,715,0,0},{1,31,-2892.6,-698.7,-104.4,98.9,36.8,0,8955,0,0},{0,33,-2910.4,-625.5,-102.5,51.7,29.4,2,8875,0,0},{0,33,-2925.9,-532.0,-95.9,45.4,31.7,2,3882,0,0},{1,31,-2930.9,-460.0,-93.1,98.9,36.8,0,5523,0,0},{1,32,-2936.0,-361.3,-92.9,98.8,28.0,0,2768,0,0},{0,33,-2939.0,-301.6,-92.9,20.8,28.4,2,9288,0,0},{0,33,-2895.1,10.8,-72.4,60.3,32.9,3,2441,0,0},
		{0,33,-2878.7,62.3,-72.4,47.8,28.7,2,6219,0,0},{0,33,-2862.6,110.4,-70.8,53.7,32.0,3,8394,0,0},{0,33,-2679.1,350.4,-33.5,32.6,31.8,2,7276,0,0},{0,33,-2637.7,373.8,-27.5,62.6,30.7,2,6312,0,0},{1,19,-2586.2,399.3,-25.0,52.3,28.2,0,7275,0,0},{0,33,-2537.7,421.9,-25.0,37.0,32.4,3,7693,0,0},{1,31,-2476.1,450.7,-25.0,98.9,36.8,0,2756,0,0},{0,33,-2415.4,479.0,-25.0,35.0,33.9,3,6609,0,0},
		{0,33,-2381.1,494.4,-23.5,40.3,32.8,2,6311,0,0},{0,33,-2261.5,533.9,-12.8,27.6,11.4,2,4921,0,0},{0,33,-2222.7,541.8,-10.7,51.5,11.0,3,8142,0,0},{0,17,-1908.0,896.1,-178.0,34.0,34,3,1550,0,-1},{0,17,-2546.0,871.3,111.3,34.0,34,3,9209,0,-1},{0,17,-2719.5,1029.0,-91.8,34.0,34,3,7000,0,-1},{0,2,-2415.0,1780.0,-94.4,34.0,34,3,9513,0,-1},{0,17,-2244.8,1896.9,-34.0,34.0,34,3,4049,0,-1},
		{0,17,-1554.5,2248.9,-70.7,34.0,34,3,6322,0,-1},{0,17,-1362.5,2295.1,-16.7,34.0,34,3,7350,0,-1},{0,17,-389.2,2493.1,-56.0,34.0,34,3,1521,0,-1},{0,17,-185.1,2479.1,3.5,34.0,34,3,1338,0,-1},{0,17,932.2,2353.2,-41.1,34.0,34,3,1637,0,-1},{0,2,1102.7,2338.4,-6.6,34.0,34,3,4825,0,-1},{0,2,2063.8,2426.1,-53.0,34.0,34,3,4356,0,-1},{0,2,2269.2,2400.0,8.0,34.0,34,3,3124,0,-1},
		{0,17,3008.5,2197.5,-26.1,34.0,34,3,3047,0,-1},{0,2,2939.0,2020.5,166.2,34.0,34,4,4843,0,-1},{1,19,-1951.1,897.6,-178.0,52.3,28.2,0,2113,0,0},{1,31,-2033.6,900.6,-178.0,98.9,36.8,0,514,0,0},{1,32,-2132.4,904.1,-178.0,98.8,28.0,0,6053,0,0},{0,33,-2213.3,906.9,-178.0,63.2,29.4,2,9083,0,0},{1,31,-2341.3,901.5,175.9,98.9,36.8,0,4394,0,0},{1,31,-2439.9,894.4,175.9,98.9,36.8,0,3691,0,0},
		{0,33,-2497.6,890.2,175.9,16.7,33.2,3,2472,0,0},{0,33,-2558.7,850.5,127.3,14.9,33.1,3,1012,0,0},{0,33,-2568.7,839.1,134.8,15.5,29.5,2,784,0,0},{1,31,-2721.6,1095.4,-91.8,98.9,36.8,0,2286,0,0},{1,32,-2724.7,1194.2,-91.8,98.8,28.0,0,9800,0,0},{1,19,-2727.1,1269.7,-91.8,52.3,28.2,0,3333,0,0},{0,33,-2728.3,1309.0,-91.8,11.3,32.8,2,807,0,0},{0,33,-2739.5,1337.3,-118.1,21.5,32.6,3,2658,0,0},
		{0,33,-2746.6,1352.8,-109.2,12.8,29.9,3,4819,0,0},{0,33,-2751.0,1367.9,-103.6,18.8,28.2,2,6751,0,0},{0,33,-2753.6,1384.7,-93.0,15.3,28.7,2,5279,0,0},{0,33,-2750.5,1418.4,-77.8,11.3,31.4,2,1777,0,0},{0,33,-2745.1,1434.0,-67.6,21.8,29.8,3,2764,0,0},{0,33,-2737.1,1450.3,-58.4,14.6,30.3,3,239,0,0},{0,33,-2728.9,1461.8,-50.3,13.9,28.9,2,4723,0,0},{1,32,-2688.7,1501.3,-43.8,98.8,28.0,0,8526,0,0},
		{1,19,-2634.1,1553.5,-43.5,52.3,28.2,0,2603,0,0},{1,32,-2574.1,1610.6,-43.5,98.8,28.0,0,6445,0,0},{1,31,-2502.4,1678.7,-43.5,98.9,36.8,0,6617,0,0},{0,33,-2452.5,1726.2,-43.5,39.0,29.1,2,5612,0,0},{0,33,-2412.4,1803.3,-78.7,13.1,29.1,2,9983,0,0},{1,31,-2189.8,1934.0,-34.0,98.9,36.8,0,3884,0,0},{1,31,-2107.8,1989.4,-34.0,98.9,36.8,0,1809,0,0},{0,33,-2052.2,2026.9,-34.0,35.2,28.8,3,6529,0,0},
		{0,33,-2020.8,2048.0,-33.9,40.5,32.4,3,538,0,0},{0,33,-1979.1,2074.5,-31.2,58.4,30.1,2,4315,0,0},{0,33,-1932.3,2100.4,-26.4,48.6,31.1,3,5871,0,0},{1,32,-1803.0,2151.7,-18.6,98.8,28.0,0,5055,0,0},{0,33,-1727.2,2177.1,-18.4,61.1,30.5,2,7429,0,0},{0,33,-1673.9,2194.9,-18.4,51.2,31.5,2,4421,0,0},{0,33,-1621.0,2212.5,-18.4,60.3,32.8,3,8645,0,0},{0,33,-1321.4,2307.5,-16.7,51.8,29.9,3,6425,0,0},
		{1,19,-1271.5,2322.4,-16.7,52.3,28.2,0,9608,0,0},{1,32,-1191.5,2346.5,-16.7,98.8,28.0,0,6856,0,0},{0,33,-1111.4,2370.5,-16.7,68.4,31.2,3,2072,0,0},{1,31,-1031.2,2394.5,-16.7,98.9,36.8,0,3911,0,0},{0,33,-952.3,2418.0,-16.3,65.8,29.2,2,9131,0,0},{1,32,-759.0,2452.4,-4.6,98.8,28.0,0,765,0,0},{1,31,-660.5,2460.0,-4.2,98.9,36.8,0,4073,0,0},{1,31,-561.8,2467.1,-4.2,98.9,36.8,0,245,0,0},
		{0,33,-494.9,2472.0,-4.2,35.3,29.7,3,2531,0,0},{0,33,-454.9,2474.9,-4.2,44.9,32.1,3,1536,0,0},{0,33,-373.5,2508.1,-41.2,9.4,32.0,2,3803,0,0},{1,32,-118.8,2475.0,3.5,98.8,28.0,0,4506,0,0},{0,33,-45.7,2470.5,3.5,47.6,28.8,2,7673,0,0},{1,31,27.4,2466.0,3.5,98.9,36.8,0,4939,0,0},{1,32,126.0,2459.9,3.5,98.8,28.0,0,3693,0,0},{1,31,224.7,2453.8,3.5,98.9,36.8,0,1160,0,0},
		{0,33,289.0,2449.9,3.5,30.0,29.4,2,6944,0,0},{0,33,324.6,2447.2,4.8,41.4,28.2,3,3694,0,0},{0,33,359.8,2443.7,7.1,29.4,33.9,3,8840,0,0},{1,31,423.1,2433.3,10.1,98.9,36.8,0,800,0,0},{0,33,493.3,2420.7,10.5,43.8,29.9,3,3210,0,0},{1,31,563.4,2407.7,10.5,98.9,36.8,0,3724,0,0},{1,31,660.7,2389.8,10.5,98.9,36.8,0,6358,0,0},{1,32,757.9,2371.8,10.5,98.8,28.0,0,547,0,0},
		{0,33,846.2,2355.5,10.5,80.9,29.6,2,3517,0,0},{0,33,955.0,2365.3,-24.4,17.6,28.1,2,823,0,0},{0,33,1055.2,2360.4,31.9,10.2,32.3,2,4539,0,0},{1,31,1168.8,2346.1,-6.6,98.9,36.8,0,803,0,0},{1,31,1267.0,2357.6,-6.6,98.9,36.8,0,4281,0,0},{1,32,1365.2,2369.0,-6.6,98.8,28.0,0,217,0,0},{1,32,1463.3,2380.5,-6.6,98.8,28.0,0,8891,0,0},{0,33,1538.6,2389.2,-6.6,52.9,31.2,3,4059,0,0},
		{0,33,1581.4,2393.7,-4.8,33.2,33.6,3,8001,0,0},{1,32,1647.3,2397.3,-2.6,98.8,28.0,0,4894,0,0},{1,32,1746.0,2401.4,-2.1,98.8,28.0,0,9364,0,0},{1,31,1844.8,2404.9,-2.1,98.9,36.8,0,222,0,0},{0,33,1910.9,2407.3,-2.1,33.4,33.7,2,72,0,0},{0,33,1941.9,2408.5,-2.1,28.6,32.6,3,617,0,0},{0,33,1971.6,2409.6,-2.1,31.0,30.3,3,1650,0,0},{0,33,2003.3,2410.7,-2.1,32.5,28.4,3,6797,0,0},
		{0,33,2081.1,2441.7,-37.5,12.7,28.6,2,657,0,0},{0,33,2229.2,2433.1,45.0,9.5,31.8,3,1849,0,0},{1,31,2335.0,2390.7,8.0,98.9,36.8,0,7991,0,0},{1,32,2432.9,2377.0,8.0,98.8,28.0,0,1466,0,0},{0,33,2495.7,2368.2,8.0,28.1,28.2,3,3295,0,0},{0,33,2544.1,2361.2,8.4,69.7,28.4,2,9059,0,0},{0,33,2603.6,2351.3,10.8,50.9,32.2,2,4103,0,0},{0,33,2642.0,2342.7,15.9,28.0,31.0,2,9990,0,0},
		{0,33,2730.1,2313.0,22.2,31.2,29.6,3,2493,0,0},{1,31,2789.4,2286.3,24.9,98.9,36.8,0,3875,0,0},{1,32,2878.9,2244.3,25.4,98.8,28.0,0,1753,0,0},{0,33,2943.0,2213.9,25.4,43.2,28.1,2,5895,0,0},{0,33,3033.7,2203.3,-9.4,17.7,29.9,3,6842,0,0},{0,33,2983.6,1996.7,-146.8,11.8,33.7,2,3664,0,0},{0,33,2896.7,2010.1,166.2,53.1,28.0,2,4209,0,0},{1,32,2822.9,1992.0,166.2,98.8,28.0,0,2380,0,0},
		{1,32,2727.0,1968.4,166.2,98.8,28.0,0,7480,0,0},{1,18,2653.6,1950.4,166.2,52.3,28.2,0,1122,0,0},{0,33,2604.8,1938.4,166.2,35.8,29.4,3,9386,0,0},{0,33,2550.9,1921.1,155.3,15.1,30.3,3,5272,0,0},{0,33,2516.9,1898.5,140.4,12.8,32.6,3,5667,0,0},{0,33,2494.7,1874.2,126.6,14.0,30.5,3,4703,0,0},{1,31,2449.3,1784.9,114.8,98.9,36.8,0,6151,0,0},{1,20,2414.9,1711.1,115.5,64.1,41.3,0,3241,0,0},
		{0,33,2383.3,1644.7,115.5,63.8,28.5,3,393,0,0},{0,33,2361.4,1598.7,115.5,38.0,29.6,2,4012,0,0},{1,31,2332.0,1536.9,115.5,98.9,36.8,0,3040,0,0},{1,31,2289.5,1447.6,115.5,98.9,36.8,0,2297,0,0},{1,32,2247.0,1358.4,115.5,98.8,28.0,0,4229,0,0},{1,18,2214.5,1290.1,115.5,52.3,28.2,0,2120,0,0},{0,33,2191.8,1243.0,116.2,33.8,29.4,2,725,0,0},{1,31,2158.9,1185.5,121.0,98.9,36.8,0,1659,0,0},
		{1,20,2116.8,1115.6,121.0,64.1,41.3,0,8346,0,0},{0,33,2080.3,1054.9,121.0,61.5,29.0,2,9790,0,0},{0,33,2057.1,1016.4,121.0,28.2,33.3,3,3977,0,0},{0,33,2043.9,996.8,128.3,19.3,33.0,3,4191,0,0},{0,33,2031.8,983.7,137.8,16.3,28.7,2,1036,0,0},{0,33,2019.1,973.3,143.6,16.5,29.3,3,8324,0,0},{0,33,2005.3,964.4,150.7,16.4,29.0,3,4631,0,0},{0,33,1989.5,957.2,159.8,18.5,31.5,2,7583,0,0},
		{1,32,1933.5,939.8,163.3,98.7,28.0,0,855,0,0},{0,33,1855.8,915.2,161.0,64.4,15.1,2,9021,0,0},{0,33,1793.9,893.9,161.0,66.6,32.4,3,5656,0,0},{0,33,1753.0,879.8,161.0,19.9,30.4,2,7086,0,0},{0,16,2904.8,847.2,-135.0,60.0,60,25,9812,0,-1},{0,16,1741.0,576.1,90.0,24.3,80.1,17,4722,0,0},{0,16,1952.1,547.7,4.4,94.8,56.0,34,9765,0,0},{0,16,2039.9,541.0,4.4,81.2,76.8,23,1538,0,0},
		{0,16,2115.8,535.1,4.4,71.0,56.1,34,5767,0,0},{0,16,2185.3,529.8,4.4,68.5,60.2,23,3078,0,0},{0,1,2266.4,523.5,4.4,94.2,50.4,5,4834,0,0},{0,16,2356.0,516.7,4.4,85.4,51.1,35,847,0,0},{0,16,2435.2,510.6,4.4,73.4,54.8,27,7237,0,0},{0,16,2516.5,504.3,4.4,89.8,58.2,27,7049,0,0},{0,16,2663.1,550.5,-26.7,89.5,66.0,16,272,0,0},{0,16,2743.8,600.0,-38.8,39.3,83.6,15,4489,0,0},
		{0,16,2793.4,649.5,-49.9,49.7,78.3,15,6558,0,0},{0,16,2876.2,758.8,-53.5,47.2,81.6,18,9903,0,0},{0,16,2862.1,891.1,-133.5,62.4,70.4,34,4200,0,0},{0,16,2834.4,922.0,-127.1,20.8,89.3,33,4037,0,0},{0,16,2817.7,946.4,-122.9,38.4,74.0,18,3016,0,0},{0,16,2799.9,977.4,-116.3,33.2,73.4,34,1773,0,0},{0,16,2787.9,1004.2,-111.4,25.5,82.9,23,5526,0,0},{0,16,2779.4,1028.9,-106.7,26.8,51.0,36,1870,0,0},
		{0,16,2772.5,1055.8,-102.2,28.8,75.9,36,3962,0,0},{0,16,2762.0,1175.4,-92.3,81.3,51.4,15,2227,0,0},{0,16,2772.9,1353.6,-82.1,85.1,47.4,30,2386,0,0},{0,16,2783.1,1427.2,-82.1,63.5,45.6,26,2918,0,0},{0,16,2819.1,1560.0,-62.2,23.0,20.8,31,8881,0,0},{0,2,-221.8,2336.0,133.5,34.0,34,4,3650,0,-1},{0,2,-190.1,2180.1,1.8,34.0,34,3,3480,0,-1},{0,29,232.4,2321.1,-176.5,39.5,34.8,2,8597,0,0},
		{0,33,194.6,2323.4,-176.5,36.3,29.2,3,9113,0,0},{0,33,145.1,2326.5,-176.5,63.0,29.5,3,485,0,0},{0,29,82.5,2330.3,-176.5,62.5,36.9,3,2471,0,0},{1,31,1.9,2335.3,-176.5,98.9,36.8,0,9128,0,0},{0,33,-79.6,2340.3,-176.5,64.4,29.1,3,1821,0,0},{0,29,-130.0,2343.4,-176.5,36.6,34.6,3,307,0,0},{0,33,-162.2,2345.4,-176.5,28.0,33.7,2,6677,0,0},{1,22,-222.6,2260.9,79.1,14.7,34.2,0,6069,0,0},
		{0,29,-217.4,2233.9,79.1,40.5,33.9,3,8045,0,0},{1,31,-123.7,2178.1,1.8,98.9,36.8,0,5263,0,0},{0,33,-44.1,2175.6,1.8,60.5,31.2,2,2406,0,0},{0,33,11.5,2173.9,1.8,50.6,29.9,3,640,0,0},{0,33,77.8,2175.6,-12.2,12.6,31.0,3,9804,0,0},{1,32,163.5,2202.1,-18.5,98.8,28.0,0,1561,0,0},{1,32,257.2,2233.5,-18.5,98.8,28.0,0,6535,0,0},{0,2,-139.2,1914.7,2.3,34.0,34,3,1474,0,-1},
		{0,17,363.3,2193.2,161.5,34.0,34,3,4629,0,-1},{1,25,-178.8,2033.3,79.1,14.7,34.2,0,578,0,0},{0,29,-174.6,2011.4,79.1,29.8,32.5,3,5529,0,0},{1,26,-167.9,1976.6,79.1,41.1,28.0,0,6750,0,0},{0,33,-95.8,1912.9,2.3,52.8,28.2,2,4786,0,0},{1,32,-20.1,1909.9,2.3,98.8,28.0,0,4135,0,0},{1,32,78.6,1905.9,2.3,98.8,28.0,0,1861,0,0},{0,33,144.5,1903.3,2.3,33.0,28.1,2,204,0,0},
		{0,33,166.7,1902.4,2.3,11.5,31.5,3,3870,0,0},{1,20,215.1,1910.4,-12.4,64.0,41.3,0,4333,0,0},{1,32,302.5,1931.3,-14.0,98.8,28.0,0,1984,0,0},{1,31,398.4,1955.1,-14.0,98.9,36.8,0,147,0,0},{1,31,461.9,2062.8,-117.7,98.9,36.8,0,4192,0,0},{0,33,430.0,2123.5,-117.7,38.2,29.0,3,1275,0,0},{0,33,411.6,2156.9,-120.0,38.0,12.2,2,7615,0,0},{1,32,300.3,2172.1,161.5,98.8,28.0,0,5143,0,0},
		{1,31,206.6,2140.7,161.5,98.9,36.8,0,7331,0,0},{0,33,137.7,2117.7,161.7,46.3,29.4,2,7956,0,0},{0,33,102.0,2107.2,166.8,28.1,30.2,2,9178,0,0},{1,31,6.5,2102.5,-178.7,98.9,36.8,0,4800,0,0},{1,31,-92.3,2105.1,-178.3,98.9,36.8,0,5968,0,0},{0,33,-157.9,2107.1,-178.3,32.2,29.4,3,3131,0,0},{0,17,-205.3,1490.4,-95.7,34.0,34,3,2561,0,-1},{0,17,-304.2,2109.9,-179.9,34.0,34,3,2828,0,-1},
		{0,2,-951.8,2018.7,79.5,34.0,34,4,5169,0,-1},{0,10,-883.1,1517.4,4.8,67.0,34.1,4,6748,0,0},{0,33,-833.0,1513.3,4.8,33.6,31.7,2,8306,0,0},{0,29,-797.0,1510.3,4.8,38.6,33.0,3,1366,0,0},{0,10,-752.1,1506.5,4.8,51.5,33.4,4,7909,0,0},{0,10,-695.4,1501.7,5.0,62.3,39.2,4,8324,0,0},{0,29,-630.8,1495.9,5.2,67.5,32.9,4,8683,0,0},{0,33,-582.9,1491.6,5.2,28.7,31.6,3,7027,0,0},
		{1,31,-519.3,1485.8,5.2,98.9,36.8,0,1333,0,0},{0,29,-444.4,1479.0,5.2,51.6,32.1,2,2810,0,0},{0,33,-399.5,1474.9,5.2,38.5,28.0,3,2831,0,0},{0,10,-366.0,1471.9,5.2,28.8,34.6,3,7677,0,0},{0,29,-333.9,1468.9,5.2,35.8,35.8,3,2218,0,0},{1,24,-308.8,1466.6,5.2,14.7,34.2,0,2670,0,0},{0,29,-282.7,1464.3,5.2,37.6,31.4,2,2537,0,0},{1,25,-207.7,1514.6,-95.7,14.7,34.2,0,6921,0,0},
		{1,23,-209.2,1529.3,-95.7,14.7,34.2,0,2861,0,0},{1,27,-210.9,1546.2,-95.7,19.4,36.9,0,9243,0,0},{1,25,-212.6,1563.2,-95.7,14.7,34.2,0,2809,0,0},{1,26,-215.4,1590.9,-95.7,41.1,28.0,0,6799,0,0},{1,26,-219.5,1631.8,-95.7,41.1,28.0,0,6972,0,0},{1,22,-222.2,1659.6,-95.7,14.7,34.2,0,1814,0,0},{0,29,-226.0,1696.9,-95.7,60.4,26.8,3,2383,0,0},{0,29,-230.7,1744.1,-95.7,34.3,22.4,4,8123,0,0},
		{0,29,-234.1,1778.1,-95.7,34.1,19.8,4,6459,0,0},{0,29,-238.6,1823.1,-95.7,56.3,15.7,3,60,0,0},{0,29,-243.6,1870.5,-96.3,39.1,12.4,2,4801,0,0},{0,29,-270.9,2023.4,-100.7,35.6,36.9,2,7776,0,0},{1,25,-275.5,2048.1,-100.7,14.7,34.2,0,7514,0,0},{0,29,-278.9,2065.9,-100.7,21.5,33.0,2,5881,0,0},{1,32,-370.6,2110.0,-179.9,98.8,28.0,0,710,0,0},{1,31,-469.5,2110.1,-179.9,98.9,36.8,0,7841,0,0},
		{0,33,-547.9,2110.2,-179.9,57.9,31.5,2,1715,0,0},{0,33,-598.8,2109.7,178.6,44.1,23.2,2,1879,0,0},{1,31,-726.9,2086.5,167.4,98.9,36.8,0,3031,0,0},{1,31,-823.4,2064.8,167.4,98.9,36.8,0,864,0,0},{0,33,-896.7,2048.4,167.4,51.3,32.7,2,7290,0,0},{0,33,-944.9,1981.5,79.5,41.7,33.2,3,9756,0,0},{0,33,-938.6,1947.6,79.5,27.1,32.4,3,7456,0,0},{1,32,-927.5,1827.8,87.9,98.8,28.0,0,5745,0,0},
		{1,32,-924.0,1729.1,87.9,98.8,28.0,0,6137,0,0},{1,32,-920.4,1630.3,87.9,98.8,28.0,0,6078,0,0},{0,2,37.3,1092.5,-96.9,23.8,34,3,8229,0,-1},{0,2,14.3,1187.1,-138.8,34.0,34,3,4310,0,-1},{0,17,-144.9,1309.1,171.0,34.0,34,3,7644,0,-1},{0,29,-224.4,1252.0,135.0,58.9,31.1,2,9428,0,0},{1,23,-250.4,1226.0,135.0,14.7,34.2,0,2425,0,0},{1,25,-260.8,1215.6,135.0,14.7,34.2,0,9952,0,0},
		{1,27,-272.9,1203.6,135.0,19.4,36.9,0,4163,0,0},{0,10,-295.8,1180.7,135.0,45.3,34.4,3,5903,0,0},{1,32,-268.2,1107.5,12.3,98.8,28.0,0,138,0,0},{0,33,-198.8,1092.5,12.1,43.4,33.9,3,678,0,0},{1,32,-99.5,1083.5,3.2,98.8,28.0,0,25,0,0},{0,10,-12.6,1210.7,-138.8,37.5,39.0,5,8768,0,0},{1,31,-63.9,1255.6,-138.8,98.9,36.8,0,5577,0,0},{0,29,20.1,774.3,-79.8,46.0,46,4,9874,0,-1},
		{0,1,25.2,1004.3,-176.9,46.0,46,9,6087,0,-1},{0,13,-392.1,1002.7,82.9,60.0,44.3,7,5359,0,0},{0,13,-341.4,772.0,-0.0,38.5,57.7,7,3343,0,0},{0,29,-296.7,772.0,-0.0,51.0,34.8,4,2572,0,0},{0,13,-245.4,772.0,-0.0,51.6,59.2,5,4194,0,0},{0,13,-199.2,772.0,0.1,40.9,43.2,7,1859,0,0},{0,16,-71.0,762.5,7.1,83.4,52.8,18,8689,0,0},{0,29,26.7,811.1,-79.8,28.7,34.0,2,4654,0,0},
		{0,16,33.8,850.4,-79.8,51.3,65.7,6,4110,0,0},{0,1,-41.2,1007.9,-176.9,86.9,50.0,6,5357,0,0},{0,13,-100.1,1011.1,-176.9,31.1,44.9,6,7075,0,0},{0,1,-235.2,1026.3,-167.6,54.1,47.8,10,497,0,0},{0,13,-291.5,1038.7,-167.6,61.1,55.2,5,1184,0,0},{0,16,375.5,601.9,-173.0,67.5,33.9,22,3125,0,0},{0,13,328.6,607.6,-173.0,27.0,40.8,6,8142,0,0},{0,16,275.2,614.2,-173.0,80.7,48.0,23,9662,0,0},
		{0,13,215.4,621.6,-173.0,39.8,55.6,6,2560,0,0},{0,1,172.7,626.9,-173.0,46.3,52.8,14,2136,0,0},{0,29,134.8,631.6,-173.0,30.1,32.4,2,9881,0,0},{0,16,79.5,638.4,-173.0,81.5,61.5,12,920,0,0},{0,1,-7.2,649.1,-173.0,93.1,49.7,6,6263,0,0},{0,1,-95.3,660.0,-173.0,84.6,53.9,13,7121,0,0},{0,13,-214.1,667.3,-179.8,59.6,58.3,6,8320,0,0},{0,16,-283.2,667.6,-179.8,78.6,77.0,7,9658,0,0},
		{0,16,-351.3,667.9,-179.8,57.5,72.0,18,1247,0,0},{0,29,-729.5,668.0,-180.0,59.0,17.6,2,6131,0,0},{0,10,-114.3,307.3,1.6,63.1,14.5,3,5700,0,0},{0,2,-235.6,-106.5,2.3,28.9,34,3,5192,0,-1},{0,2,-49.5,-97.0,-83.0,34.0,34,4,2724,0,-1},{0,2,-27.4,202.0,-179.5,23.8,34,3,8043,0,-1},{1,20,-217.3,178.2,100.6,64.1,41.3,0,3705,0,0},{1,19,-229.3,114.4,100.6,52.3,28.2,0,8738,0,0},
		{1,32,-240.7,31.6,96.0,98.7,28.0,0,4587,0,0},{0,33,-248.0,-44.7,94.3,54.6,15.1,2,4026,0,0},{1,23,-179.6,-108.8,2.3,14.7,34.2,0,4892,0,0},{1,24,-164.9,-109.4,2.3,14.7,34.2,0,6357,0,0},{0,29,-137.5,-110.5,2.3,40.1,31.4,2,6091,0,0},{0,29,-101.5,-111.9,2.3,32.0,30.5,4,1372,0,0},{1,20,-43.5,-48.3,-83.0,64.1,41.3,0,9562,0,0},{1,18,-35.3,18.1,-83.0,52.3,28.2,0,2742,0,0},
		{1,32,-24.4,100.4,-82.1,98.8,28.0,0,96,0,0},{0,29,-97.4,202.6,-179.5,48.4,37.5,4,3221,0,0},{0,13,-252.4,-219.9,87.1,37.4,44,6,3467,0,-1},{0,13,-163.9,-444.5,-0.5,44.0,44,7,561,0,-1},{1,25,-66.0,-205.4,-177.7,14.7,34.2,0,4343,0,0},{1,23,-80.7,-204.8,-177.7,14.7,34.2,0,8871,0,0},{0,29,-110.7,-203.6,-177.7,45.4,31.7,3,1582,0,0},{1,22,-140.8,-202.4,-177.7,14.7,34.2,0,371,0,0},
		{1,24,-155.4,-201.8,-177.7,14.7,34.2,0,2076,0,0},{1,24,-170.1,-201.2,-177.7,14.7,34.2,0,1321,0,0},{0,10,-247.2,-298.4,81.5,22.5,33.8,3,1684,0,0},{0,13,-233.1,-343.5,67.1,46.1,50.0,5,1891,0,0},{0,10,-111.3,-444.1,-0.5,61.1,34.9,4,6733,0,0},{0,10,-67.5,-443.7,-0.5,26.5,31.7,3,3330,0,0},{0,13,-59.2,-325.3,-98.1,20.2,58.4,5,465,0,0},{0,13,140.0,-213.6,-177.7,44.0,44,5,7593,0,-1},
		{0,13,12.6,-230.6,92.0,44.0,44,5,9455,0,-1},{0,13,78.8,-442.6,-0.4,44.0,44,7,4480,0,-1},{0,13,171.6,-354.8,-93.9,37.5,43.6,6,2279,0,0},{0,10,169.2,-320.8,-93.9,30.8,35.1,4,1263,0,0},{0,13,166.6,-281.9,-93.9,47.1,47.0,5,5313,0,0},{1,24,110.6,-212.5,-177.7,14.7,34.2,0,6872,0,0},{1,24,96.0,-211.9,-177.7,14.7,34.2,0,1062,0,0},{1,22,81.3,-211.3,-177.7,14.7,34.2,0,6909,0,0},
		{0,29,65.6,-210.7,-177.7,16.7,34.5,3,164,0,0},{0,13,11.3,-265.7,92.0,26.4,47.2,6,1841,0,0},{0,10,12.9,-318.3,81.7,14.8,30.7,5,5263,0,0},{0,13,116.7,-442.4,-0.4,31.8,57.3,7,2312,0,0},{0,10,155.0,-442.1,-0.4,45.0,11.7,4,7904,0,0},{0,13,133.2,-402.8,86.1,48,40.6,7,7944,1,0},{0,1,462.3,-776.7,-90.1,56.0,56,7,7691,0,-1},{0,16,447.2,-241.0,-173.2,64.1,66.9,22,9403,0,0},
		{0,16,379.4,-232.8,-173.2,72.4,61.6,16,5462,0,0},{0,16,252.4,-334.5,86.1,63.0,55.2,21,4434,0,0},{0,1,256.5,-394.2,86.1,56.6,61.7,5,5540,0,0},{0,16,275.9,-677.6,86.1,71.5,82.8,25,7490,0,0},{0,30,280.5,-744.6,86.1,62.9,56.5,7,9288,0,0},{0,16,389.5,-822.9,-14.0,38.2,74.6,11,2333,0,0},{0,30,462.2,-717.8,-90.1,61.8,66.6,5,4918,0,0},{0,1,461.9,-577.4,-90.1,84.8,19.5,7,9501,0,0},
		{0,16,468.2,-414.0,-86.4,63.5,30.4,16,7489,0,0},{0,30,471.8,-358.4,-86.4,47.9,47.3,7,467,0,0},{0,16,386.7,-378.7,-93.9,48,42,18,2915,1,0},{0,16,1004.8,-708.3,-104.0,56.0,56,21,5411,0,-1},{0,16,298.7,-961.1,80.5,60.4,76.8,16,4743,0,0},{0,16,440.0,-951.6,-25.9,87.7,37.5,24,9653,0,0},{0,16,509.4,-918.0,-25.9,66.4,31.6,21,558,0,0},{0,30,719.7,-828.4,-17.7,65.1,17.6,5,463,0,0},
		{0,16,781.3,-808.8,-17.7,64.2,39.6,21,1147,0,0},{0,16,854.1,-785.6,-17.7,88.4,51.9,25,9561,0,0},{0,16,927.2,-762.3,-17.7,65.1,87.3,17,2939,0,0},{0,30,990.0,-649.1,-104.0,66.1,54.8,8,9439,0,0},{0,30,905.4,-648.2,141.3,37.6,18.5,7,25,0,0},{0,16,399.9,-1441.3,19.7,56.0,56,15,765,0,-1},{0,16,467.2,-1484.3,3.1,56.0,56,25,3117,0,-1},{0,16,1258.8,-1361.6,-117.1,56.0,56,8,7250,0,-1},
		{0,30,1002.4,-813.9,162.4,47.6,56,8,3827,0,-1},{0,16,324.9,-1118.0,80.5,57.2,90.0,19,3754,0,0},{0,16,333.4,-1169.5,80.5,47.3,58.6,11,6798,0,0},{0,30,342.1,-1224.0,81.3,63.0,55.4,6,1895,0,0},{0,16,352.8,-1294.8,81.4,80.1,54.5,19,3995,0,0},{0,30,362.0,-1355.4,81.4,42.6,49.1,8,4049,0,0},{0,16,542.2,-1488.4,3.1,94.3,54.9,22,1989,0,0},{0,30,622.9,-1492.8,3.1,67.2,45.4,8,6471,0,0},
		{0,30,679.7,-1495.9,3.1,46.6,60.9,6,9260,0,0},{0,16,729.9,-1498.6,3.1,53.9,63.6,13,7464,0,0},{0,16,795.4,-1502.2,3.1,77.3,84.3,6,2408,0,0},{0,30,856.9,-1505.0,1.7,45.8,22.5,8,849,0,0},{0,16,933.2,-1497.2,-11.8,67.9,71.1,23,6820,0,0},{0,30,979.2,-1487.1,-13.7,26.3,17.9,5,8556,0,0},{0,16,1037.2,-1472.9,-13.7,93.2,54.0,19,3144,0,0},{0,16,1112.2,-1454.6,-13.7,61.1,56.8,25,5542,0,0},
		{0,30,1159.8,-1443.0,-13.7,37.0,55.6,5,5324,0,0},{0,30,1235.3,-1315.6,-117.1,47.2,52.9,6,5569,0,0},{0,16,1204.1,-1254.5,-117.1,90.0,67.6,15,6125,0,0},{0,16,1172.7,-1193.1,-117.1,48.0,89.8,12,5404,0,0},{0,16,1144.1,-1137.2,-117.1,77.5,79.7,26,6397,0,0},{0,16,1114.0,-1078.3,-117.1,54.9,52.3,26,851,0,0},{0,30,1093.6,-1036.6,-114.4,37.8,49.6,7,1807,0,0},{0,30,1079.5,-1000.3,-108.3,40.2,55.3,7,4304,0,0},
		{0,30,1067.8,-959.8,-104.3,44.2,69.0,5,3559,0,0},{0,30,1058.6,-923.3,-104.0,31.1,65.4,8,9772,0,0},{0,16,885.5,-851.1,162.4,87.1,83.7,18,4685,0,0},{0,1,810.4,-875.0,162.4,70.4,58.4,6,7372,0,0},{0,16,744.2,-896.1,162.4,68.5,78.2,24,5537,0,0},{0,30,689.5,-913.8,161.6,46.5,48.9,8,8142,0,0},{0,16,595.5,-956.0,154.1,55.5,61.9,18,8638,0,0},{0,16,543.5,-981.3,154.1,60.2,51.0,11,7097,0,0},
		{0,16,487.6,-1008.5,154.1,64.1,80.5,12,6240,0,0},{0,16,434.7,-1034.2,154.1,53.5,61.4,6,3861,0,0},{0,16,458.1,-1308.5,-17.6,48,42,14,8085,1,0},{0,16,471.4,-1350.4,-17.6,48,42,14,4785,1,0},{0,16,484.7,-1392.3,-17.6,48,42,12,1984,1,0},{0,16,465.9,-1167.5,-17.6,48,42,12,5426,1,0},{0,16,479.2,-1209.5,-17.6,48,42,8,6924,1,0},{0,16,492.4,-1251.4,-17.6,48,42,25,5433,1,0},
		{0,16,505.7,-1293.4,-17.6,48,42,10,7372,1,0},{0,16,519.0,-1335.3,-17.6,48,42,13,6350,1,0},{0,16,532.3,-1377.2,-17.6,48,42,26,9236,1,0},{0,16,513.5,-1152.4,-17.6,48,42,20,6668,1,0},{0,16,526.8,-1194.4,-17.6,48,42,12,9532,1,0},{0,16,540.1,-1236.3,-17.6,48,42,23,9164,1,0},{0,16,553.4,-1278.2,-17.6,48,42,9,5308,1,0},{0,16,566.7,-1320.2,-17.6,48,42,7,297,1,0},
		{0,16,580.0,-1362.1,-17.6,48,42,19,5824,1,0},{0,16,593.3,-1404.1,-17.6,48,42,10,6403,1,0},{0,16,561.2,-1137.3,-17.6,48,42,7,8983,1,0},{0,16,574.5,-1179.3,-17.6,48,42,6,168,1,0},{0,16,587.8,-1221.2,-17.6,48,42,11,4184,1,0},{0,16,601.1,-1263.1,-17.6,48,42,9,5439,1,0},{0,16,614.4,-1305.1,-17.6,48,42,9,1839,1,0},{0,16,627.7,-1347.0,-17.6,48,42,7,8676,1,0},
		{0,16,640.9,-1389.0,-17.6,48,42,24,4155,1,0},{0,16,608.9,-1122.2,-17.6,48,42,8,1213,1,0},{0,16,622.1,-1164.2,-17.6,48,42,7,8051,1,0},{0,16,635.4,-1206.1,-17.6,48,42,25,103,1,0},{0,16,648.7,-1248.0,-17.6,48,42,12,9660,1,0},{0,16,662.0,-1290.0,-17.6,48,42,24,8527,1,0},{0,16,675.3,-1331.9,-17.6,48,42,9,8355,1,0},{0,16,688.6,-1373.9,-17.6,48,42,25,839,1,0},
		{0,16,656.5,-1107.1,-17.6,48,42,7,3044,1,0},{0,16,669.8,-1149.0,-17.6,48,42,18,754,1,0},{0,16,749.6,-1400.7,-17.6,48,42,16,5183,1,0},{0,16,690.9,-1050.1,-17.6,48,42,22,8046,1,0},{0,16,704.2,-1092.0,-17.6,48,42,6,1923,1,0},{0,16,717.5,-1133.9,-17.6,48,42,16,8723,1,0},{0,16,797.2,-1385.6,-17.6,48,42,12,9917,1,0},{0,16,751.8,-1076.9,-17.6,48,42,18,5292,1,0},
		{0,16,765.1,-1118.8,-17.6,48,42,6,8487,1,0},{0,16,778.4,-1160.8,-17.6,48,42,14,4324,1,0},{0,16,799.5,-1061.8,-17.6,48,42,26,3486,1,0},{0,16,812.8,-1103.7,-17.6,48,42,7,6870,1,0},{0,16,826.1,-1145.7,-17.6,48,42,26,8649,1,0},{0,16,905.9,-1397.3,-17.6,48,42,6,814,1,0},{0,16,847.2,-1046.7,-17.6,48,42,6,1429,1,0},{0,16,860.5,-1088.6,-17.6,48,42,15,7353,1,0},
		{0,16,873.8,-1130.6,-17.6,48,42,17,7594,1,0},{0,16,887.1,-1172.5,-17.6,48,42,25,2040,1,0},{0,16,900.3,-1214.5,-17.6,48,42,20,7419,1,0},{0,16,913.6,-1256.4,-17.6,48,42,14,4114,1,0},{0,16,926.9,-1298.3,-17.6,48,42,12,9347,1,0},{0,16,940.2,-1340.3,-17.6,48,42,24,8018,1,0},{0,16,953.5,-1382.2,-17.6,48,42,25,2737,1,0},{0,16,894.8,-1031.6,-17.6,48,42,11,8814,1,0},
		{0,16,908.1,-1073.5,-17.6,48,42,13,5282,1,0},{0,16,921.4,-1115.5,-17.6,48,42,13,5635,1,0},{0,16,934.7,-1157.4,-17.6,48,42,7,9496,1,0},{0,16,948.0,-1199.3,-17.6,48,42,11,2684,1,0},{0,16,961.3,-1241.3,-17.6,48,42,12,4581,1,0},{0,16,974.6,-1283.2,-17.6,48,42,10,1695,1,0},{0,16,987.9,-1325.2,-17.6,48,42,25,758,1,0},{0,16,1001.2,-1367.1,-17.6,48,42,6,8963,1,0},
		{0,16,942.5,-1016.5,-17.6,48,42,15,1588,1,0},{0,16,955.8,-1058.4,-17.6,48,42,6,4579,1,0},{0,16,969.1,-1100.4,-17.6,48,42,8,5728,1,0},{0,16,982.4,-1142.3,-17.6,48,42,18,3720,1,0},{0,16,995.7,-1184.2,-17.6,48,42,8,8583,1,0},{0,16,1009.0,-1226.2,-17.6,48,42,20,265,1,0},{0,16,1022.3,-1268.1,-17.6,48,42,20,9070,1,0},{0,16,1035.6,-1310.1,-17.6,48,42,9,1317,1,0},
		{0,16,1048.8,-1352.0,-17.6,48,42,25,1932,1,0},{0,16,1062.1,-1394.0,-17.6,48,42,10,5225,1,0},{0,16,1030.0,-1127.2,-17.6,48,42,17,2853,1,0},{0,16,1096.5,-1336.9,-17.6,48,42,21,1952,1,0},{0,16,1109.8,-1378.9,-17.6,48,42,11,8073,1,0},{0,2,422.8,-1599.8,129.5,34.0,34,3,6110,0,-1},{0,2,431.5,-1733.9,10.6,34.0,34,3,387,0,-1},{0,17,719.4,-1770.9,-88.9,23.8,34,3,2011,0,-1},
		{0,10,682.6,-1600.2,-176.9,41.7,36.2,4,5515,0,0},{1,32,612.4,-1596.4,-176.9,98.8,28.0,0,5131,0,0},{0,29,530.7,-1591.9,-176.9,64.9,33.7,2,4078,0,0},{0,10,482.9,-1589.3,-176.9,30.7,33.9,4,491,0,0},{1,26,410.1,-1668.7,84.3,41.1,28.0,0,7079,0,0},{1,12,465.5,-1740.3,10.6,35.3,29.0,0,6721,0,0},{1,31,540.1,-1754.3,10.6,98.9,36.8,0,1710,0,0},{0,33,610.6,-1767.5,10.6,44.6,32.1,3,4941,0,0},
		{0,2,397.1,-1822.0,101.6,34.0,34,4,6167,0,-1},{0,17,340.5,-2098.0,40.3,34.0,34,3,2609,0,-1},{0,17,1186.0,-2215.2,-36.4,34.0,34,3,4419,0,-1},{0,17,1286.7,-2184.3,-55.5,34.0,34,3,4722,0,-1},{1,20,1285.9,-1971.6,-169.4,64.1,41.3,0,2264,0,0},{1,31,1199.0,-1955.3,-169.4,98.9,36.8,0,2988,0,0},{1,19,1124.7,-1941.3,-169.4,52.3,28.2,0,1327,0,0},{1,32,1042.1,-1925.8,-169.4,98.8,28.0,0,1086,0,0},
		{1,32,945.0,-1907.6,-169.4,98.8,28.0,0,3189,0,0},{1,31,847.8,-1889.4,-169.4,98.9,36.8,0,652,0,0},{1,31,750.6,-1871.1,-169.4,98.9,36.8,0,1388,0,0},{0,33,679.3,-1857.7,-169.4,46.3,32.4,2,7662,0,0},{1,32,607.9,-1844.3,-169.4,98.8,28.0,0,3642,0,0},{1,32,510.8,-1826.1,-169.4,98.8,28.0,0,7243,0,0},{0,33,448.1,-1814.3,-169.4,28.9,30.4,2,5048,0,0},{1,26,389.5,-1858.8,101.6,41.1,28.0,0,2498,0,0},
		{1,23,383.9,-1886.1,101.6,14.7,34.2,0,4344,0,0},{0,29,378.4,-1912.6,101.6,39.4,33.5,2,1953,0,0},{1,32,359.3,-1978.6,108.0,98.2,28.0,0,3791,0,0},{0,29,354.0,-2114.5,51.3,8.7,36.7,4,3679,0,0},{1,32,445.2,-2121.5,2.3,98.8,28.0,0,493,0,0},{0,10,519.5,-2124.5,2.3,50.0,36.0,3,3765,0,0},{0,29,558.9,-2126.1,2.3,28.8,31.4,2,627,0,0},{1,25,580.6,-2127.0,2.3,14.7,34.2,0,7117,0,0},
		{0,33,609.7,-2128.2,2.3,43.5,32.6,3,6364,0,0},{1,23,638.8,-2129.4,2.3,14.7,34.2,0,9581,0,0},{1,28,666.7,-2130.5,2.3,41.2,28.1,0,5957,0,0},{1,26,707.8,-2132.9,4.2,41.1,28.0,0,5346,0,0},{1,25,735.6,-2135.0,5.0,14.7,34.2,0,9021,0,0},{0,29,757.2,-2137.4,6.8,28.7,33.3,2,5901,0,0},{0,29,796.9,-2143.7,10.3,51.7,35.7,3,3379,0,0},{1,31,870.7,-2159.0,12.4,98.9,36.8,0,9924,0,0},
		{1,22,926.1,-2171.2,12.4,14.7,34.2,0,4153,0,0},{1,22,940.5,-2174.3,12.4,14.7,34.2,0,5258,0,0},{0,10,972.4,-2181.4,12.4,50.6,30.9,4,1063,0,0},{1,27,1006.6,-2188.9,12.4,19.4,36.9,0,4457,0,0},{1,26,1036.1,-2195.4,12.4,41.1,28.0,0,4888,0,0},{0,10,1069.8,-2202.8,12.4,27.7,33.7,3,9527,0,0},{0,29,1101.5,-2209.8,12.4,37.3,31.5,3,1857,0,0},{1,23,1126.9,-2215.3,12.4,14.7,34.2,0,1248,0,0},
		{0,29,1237.6,-2196.0,-5.8,11.5,34.1,4,931,0,0},{1,22,1300.5,-2164.2,-55.5,14.7,34.2,0,206,0,0},{1,31,1338.4,-2085.8,-68.5,98.8,36.8,0,7795,0,0},{1,20,-1548.8,2097.5,161.6,64.1,41.3,0,5898,0,0},{1,26,-1605.6,2078.5,161.6,41.1,28.0,0,5329,0,0},{0,29,-1644.6,2065.6,161.6,41.1,35.7,3,8661,0,0},{1,24,-1671.1,2056.7,161.6,14.7,34.2,0,7403,0,0},{0,29,-1689.9,2050.5,161.6,24.9,35.6,3,7081,0,0},
		{1,18,-1721.1,1959.9,102.6,52.3,28.2,0,4657,0,0},{0,10,-1732.4,1909.7,102.6,37.9,34.9,4,5130,0,0},{0,10,-1741.8,1875.3,108.4,33.4,35.8,4,6082,0,0},{1,15,-1751.5,1846.8,109.4,26.9,29.0,0,2191,0,0},{1,20,-1769.6,1795.4,109.4,64.1,41.3,0,3213,0,0},{0,10,-1787.9,1743.4,109.4,26.8,11.7,3,4785,0,0},{1,18,-1708.9,1702.5,19.8,52.3,28.2,0,3650,0,0},{1,19,-1653.5,1682.5,19.8,52.3,28.2,0,9114,0,0},
		{1,22,-1614.0,1668.3,19.8,14.7,34.2,0,6192,0,0},{0,29,-1590.5,1659.9,19.8,35.2,35.9,2,811,0,0},{1,18,-1538.8,1736.7,-67.0,52.3,28.2,0,4231,0,0},{1,4,-1517.8,1786.2,-67.0,35.5,29.3,0,456,0,0},{0,10,-1500.0,1833.4,-72.7,41.3,35.2,4,9587,0,0},{1,18,-1479.1,1913.0,-76.2,52.3,28.2,0,1442,0,0},{1,19,-1464.7,1972.0,-76.2,52.3,28.2,0,5496,0,0},{1,35,-1452.5,2021.9,-76.2,34.9,32.4,0,8498,0,0},
		{0,29,-1500.7,2097.1,-153.8,15.1,11.7,2,2609,0,0},{0,29,-1456.4,1500.9,-160.3,40.3,30.6,2,5734,0,0},{1,20,-1505.6,1518.6,-160.3,64.1,41.3,0,8021,0,0},{1,26,-1564.2,1539.6,-160.3,41.1,28.0,0,3742,0,0},{0,29,-1605.2,1554.2,-160.3,46.0,34.6,4,9616,0,0},{1,19,-1651.5,1570.8,-160.3,52.3,28.2,0,5160,0,0},{0,29,-1708.5,1591.2,-160.3,52.6,33.3,4,8450,0,0},{1,24,-1740.1,1602.6,-160.3,14.7,34.2,0,3369,0,0},
		{1,19,-1771.7,1613.9,-160.3,52.3,28.2,0,1524,0,0},{0,29,-1816.7,1628.7,-165.1,30.2,32.8,2,5524,0,0},{1,18,-1905.5,1647.5,-168.6,52.3,28.2,0,5004,0,0},{0,29,-1963.7,1659.3,-168.6,51.1,30.8,4,2584,0,0},{1,18,-2014.4,1669.5,-168.6,52.3,28.2,0,2995,0,0},{1,26,-2067.6,1680.2,-168.6,41.1,28.0,0,7338,0,0},{0,29,-2111.2,1689.0,-168.6,47.8,34.3,3,2192,0,0},{0,29,-2156.2,1698.1,-168.6,44.1,31.8,3,9526,0,0},
		{1,22,-2185.0,1703.9,-168.6,14.7,34.2,0,4425,0,0},{0,29,-2201.0,1707.1,-168.6,17.8,35.0,3,3181,0,0},{0,29,-2242.5,1680.7,149.8,15.4,32.3,3,7312,0,0},{0,29,-2288.7,1666.2,174.9,22.3,36.0,3,3689,0,0},{1,27,-2309.4,1666.0,-175.4,19.4,36.9,0,9093,0,0},{1,18,-2385.2,1608.0,136.5,52.3,28.2,0,6632,0,0},{1,20,-2433.7,1562.0,136.5,64.1,41.3,0,6697,0,0},{0,29,-2486.3,1512.0,136.5,63.6,32.2,4,3399,0,0},
		{1,23,-2514.7,1485.0,136.5,14.7,34.2,0,212,0,0},{1,25,-2525.3,1474.9,136.5,14.7,34.2,0,2681,0,0},{1,24,-2536.0,1464.8,136.5,14.7,34.2,0,934,0,0},{1,20,-2564.6,1437.6,136.5,64.1,41.3,0,491,0,0},{0,29,-2604.6,1399.6,136.5,34.3,16.3,2,9206,0,0},{1,18,-2458.7,1384.6,-3.1,52.3,28.2,0,1827,0,0},{1,19,-2398.4,1387.9,-3.1,52.3,28.2,0,8732,0,0},{1,19,-2339.8,1391.1,-3.1,52.3,28.2,0,5148,0,0},
		{1,18,-2279.8,1394.4,-3.1,52.3,28.2,0,9027,0,0},{1,11,-2235.7,1396.8,-3.1,17.8,29.0,0,9690,0,0},{1,15,-2206.3,1398.5,-3.1,26.9,29.0,0,5968,0,0},{1,19,-2154.1,1401.3,-3.1,52.3,28.2,0,9112,0,0},{1,12,-2104.1,1404.1,-3.1,35.3,29.0,0,779,0,0},{1,18,-2054.0,1402.8,4.2,52.3,28.2,0,6027,0,0},{1,18,-1992.5,1398.3,4.2,52.3,28.2,0,7243,0,0},{1,20,-1926.0,1393.4,4.2,64.1,41.3,0,3165,0,0},
		{1,12,-1868.5,1389.1,4.2,35.3,29.0,0,6577,0,0},{1,19,-1816.3,1385.3,4.2,52.3,28.2,0,557,0,0},{1,7,-1772.0,1382.0,4.2,24.2,27.9,0,7243,0,0},{1,19,-1725.4,1378.6,4.2,52.3,28.2,0,585,0,0},{1,7,-1680.1,1375.2,4.2,24.2,27.9,0,8617,0,0},{1,35,-1641.6,1372.4,4.2,34.9,32.4,0,3753,0,0},{1,18,-1589.3,1368.5,4.2,52.3,28.2,0,3113,0,0},{0,10,-1549.4,1365.6,4.2,12.7,39.0,4,1962,0,0},
		{1,23,-1515.6,1388.0,-39.8,14.7,34.2,0,6645,0,0},{1,25,-1504.3,1397.4,-39.8,14.7,34.2,0,9620,0,0},{1,23,-1493.0,1406.8,-39.8,14.7,34.2,0,7767,0,0},{0,29,-1475.5,1421.4,-39.8,30.8,30.7,4,7287,0,0},{0,29,-1442.2,1449.2,-39.8,56.0,15.8,3,8267,0,0},{0,17,-1478.3,1267.7,93.9,34.0,34,3,4358,0,-1},{0,17,-1466.8,1186.9,5.1,34.0,34,3,4773,0,-1},{0,2,-1041.5,1134.7,-80.8,28.9,34,4,9021,0,-1},
		{0,2,-1011.9,1423.8,-175.2,28.9,34,4,789,0,-1},{1,23,-1288.7,1441.7,140.2,14.7,34.2,0,3354,0,0},{1,26,-1310.2,1423.8,140.2,41.1,28.0,0,2054,0,0},{1,25,-1331.6,1406.0,140.2,14.7,34.2,0,216,0,0},{1,24,-1342.9,1396.6,140.2,14.7,34.2,0,3875,0,0},{0,33,-1364.1,1378.9,140.2,40.4,32.7,2,8804,0,0},{0,29,-1404.9,1344.9,140.2,65.9,37.6,4,9067,0,0},{0,10,-1440.6,1315.1,140.2,27.1,33.2,4,5489,0,0},
		{0,33,-1480.4,1236.5,93.9,28.5,32.7,3,1172,0,0},{1,31,-1400.6,1180.9,5.1,98.9,36.8,0,7070,0,0},{0,33,-1323.1,1174.0,5.1,56.8,28.1,3,2969,0,0},{0,33,-1277.1,1169.7,5.7,35.5,28.7,2,5009,0,0},{1,31,-1211.3,1156.7,13.1,98.9,36.8,0,7358,0,0},{0,33,-1134.6,1138.9,13.1,58.6,29.3,2,166,0,0},{1,32,-1026.6,1227.1,-80.8,98.8,28.0,0,7660,0,0},{1,12,-1015.8,1293.3,-80.8,35.3,29.0,0,3204,0,0},
		{0,33,-1008.3,1339.7,-80.8,44.3,33.9,3,7274,0,0},{1,32,-1140.1,1434.5,-175.2,98.8,28.0,0,4804,0,0},{0,29,-1204.1,1439.8,-175.2,29.5,35.9,3,3055,0,0},{0,33,-1239.8,1442.8,-175.2,42.2,20.6,3,4884,0,0},{0,1,-1005.7,818.5,12.4,46.0,46,6,5024,0,-1},{0,29,-802.4,794.1,-47.4,46.0,46,4,2164,0,-1},{0,1,-977.6,1083.3,100.9,69.6,60.4,13,7148,0,0},{0,13,-989.0,1024.5,101.0,50.1,49.9,5,4814,0,0},
		{0,29,-999.2,972.3,101.0,56.4,30.4,4,7361,0,0},{0,13,-1007.7,928.6,101.0,32.7,52.9,7,2582,0,0},{0,29,-1015.1,890.6,101.0,44.7,34.5,4,5706,0,0},{0,1,-957.4,807.9,12.4,52.9,61.1,10,1065,0,0},{0,13,-913.2,798.1,12.4,37.7,40.5,5,4697,0,0},{0,29,-878.8,790.6,12.4,32.6,32.9,2,8684,0,0},{0,1,-770.8,828.5,-47.4,47.4,52.9,12,4471,0,0},{0,29,-741.9,859.9,-47.4,38.0,33.7,3,6665,0,0},
		{0,13,-712.6,891.7,-47.4,48.5,46.7,7,7265,0,0},{0,16,-675.8,931.6,-47.4,60.1,89.9,24,2439,0,0},{0,1,-625.7,986.0,-47.4,87.8,45.8,9,8547,0,0},{0,1,-580.4,1035.2,-47.4,45.8,38.3,14,5904,0,0},{0,13,-782.4,1105.7,-158.1,46.5,52.5,6,8627,0,0},{0,1,-841.7,1130.3,-157.1,81.9,47.6,7,5003,0,0},{0,13,-908.3,1158.4,-157.1,62.7,42.5,5,7253,0,0},{0,29,-858.4,679.6,-167.6,35.6,13.5,2,7769,0,0},
		{0,29,-909.5,690.8,-167.6,69.0,17.2,2,8100,0,0},{0,29,-974.4,705.1,-167.6,63.9,17.6,3,1237,0,0},{0,29,-1038.8,719.3,-167.6,68.0,18.1,4,5776,0,0},{0,33,-1099.2,732.6,-167.6,55.7,14.8,2,5554,0,0},{0,10,-1154.4,744.7,-167.6,57.4,16.4,4,1895,0,0},{0,10,-1212.8,757.6,-167.6,62.1,14.3,3,5084,0,0},{0,10,-1270.7,770.3,-167.6,56.3,12.0,3,625,0,0},{0,13,-841.0,394.6,-90.0,29.8,24.0,7,3771,0,0},
		{0,17,-1797.5,584.2,47.3,28.9,34,3,7328,0,-1},{0,10,-1782.9,561.7,43.8,14.8,32.5,3,8058,0,0},{0,33,-1713.8,510.1,36.1,57.3,31.7,3,4342,0,0},{0,10,-1666.9,476.0,36.1,58.7,35.9,3,4277,0,0},{1,26,-1626.6,446.6,36.1,41.1,28.0,0,2867,0,0},{0,29,-1535.2,390.1,25.3,52.4,31.8,4,3140,0,0},{0,29,-1449.1,360.0,11.5,26.2,36.1,3,2781,0,0},{1,22,-1429.0,356.0,10.8,14.7,34.2,0,6870,0,0},
		{0,29,-1357.9,351.4,-0.7,51.3,31.7,4,6306,0,0},{0,29,-1311.1,352.9,-3.3,42.3,12.6,2,1802,0,0},{0,10,-866.0,274.1,176.7,42.5,50,4,7629,0,-1},{0,10,-860.2,-50.5,-57.6,50.0,50,3,9243,0,-1},{0,10,-841.0,41.2,-90.0,62.3,33.3,3,227,0,0},{0,30,-841.0,87.8,-90.0,31.0,68.9,5,9451,0,0},{0,13,-841.0,116.7,-90.0,26.7,41.8,7,9333,0,0},{0,13,-841.0,158.9,-90.0,57.6,53.9,5,4332,0,0},
		{0,30,-949.1,269.4,176.7,33.2,54.7,5,891,0,0},{0,10,-984.0,267.4,176.7,36.8,39.7,3,1221,0,0},{0,30,-1024.2,265.1,176.7,43.6,22.2,5,6484,0,0},{0,10,-1077.2,262.1,176.7,62.7,17.0,5,9818,0,0},{0,10,-1214.0,254.3,176.7,64.6,10.9,3,9156,0,0},{0,10,-1451.1,254.8,-169.9,42.8,11.3,4,593,0,0},{0,10,-1570.7,291.4,-156.0,31.6,33.7,3,3871,0,0},{0,13,-1602.0,306.7,-152.4,38.1,54.4,6,3787,0,0},
		{0,13,-1641.4,330.3,-146.7,53.9,48.8,5,3627,0,0},{0,30,-1675.8,353.8,-143.9,29.6,47.6,6,288,0,0},{0,30,-1700.6,371.8,-143.9,31.6,54.3,8,6433,0,0},{0,30,-1727.7,391.6,-143.9,35.5,47.1,5,5361,0,0},{0,30,-1769.5,422.0,-143.9,67.8,34.9,8,5397,0,0},{0,30,-1824.0,371.0,95.0,51.4,28.4,7,2352,0,0},{0,10,-1828.8,315.4,95.0,60.3,30.4,3,8180,0,0},{0,10,-1832.7,270.9,95.0,29.1,38.4,4,1299,0,0},
		{0,10,-1835.2,235.2,93.5,42.4,20.5,3,8630,0,0},{0,10,-1833.2,131.6,85.2,53.1,34.6,4,2735,0,0},{0,30,-1829.8,91.1,85.2,28.2,32.2,5,4014,0,0},{0,30,-1827.1,58.7,85.2,36.8,32.5,6,8548,0,0},{0,30,-1824.2,24.4,85.2,32.2,30.0,8,357,0,0},{0,30,-1820.4,-21.0,85.2,59.0,28.0,6,8230,0,0},{0,30,-1817.1,-60.8,85.2,20.9,21.6,7,9622,0,0},{0,30,-1783.9,-92.4,46.4,11.4,23.7,6,5186,0,0},
		{0,30,-1775.2,-102.5,51.8,15.2,43.9,5,1261,0,0},{0,30,-1672.4,-108.3,-3.4,61.2,30.2,5,1077,0,0},{0,30,-1617.3,-105.0,-3.4,49.1,29.7,5,5349,0,0},{0,30,-1564.5,-101.9,-3.4,56.7,30.1,7,9644,0,0},{0,30,-1513.6,-98.8,-3.4,45.3,28.1,7,5534,0,0},{0,10,-1467.1,-96.0,-3.4,47.8,23.8,5,8790,0,0},{0,30,-1417.8,-93.1,-3.4,51.0,19.5,8,3799,0,0},{0,10,-991.7,-75.9,-2.1,34.2,32.3,5,734,0,0},
		{0,30,-958.5,-74.7,-2.1,32.2,52.2,5,4998,0,0},{0,30,-933.0,-73.8,-2.1,18.9,48.4,5,5804,0,0},{0,13,-966.0,141.8,-0.0,48,42,7,7875,1,0},{0,13,-966.0,97.8,-0.0,48,42,7,6450,1,0},{0,13,-966.0,53.8,-0.0,48,42,7,8087,1,0},{0,13,-966.0,9.8,-0.0,48,42,6,4553,1,0},{0,13,-1741.7,253.8,-0.0,48,42,7,6745,1,0},{0,13,-1826.9,165.8,-0.0,18.5,42,7,3747,1,0},
		{0,13,-1118.6,-184.5,117.1,50.0,50,5,5903,0,-1},{0,10,-1155.3,-453.2,17.3,50.0,50,3,7561,0,-1},{0,13,-969.9,-484.7,-73.1,50.0,50,5,7264,0,-1},{0,13,-866.9,-158.7,-126.0,12.6,54.0,6,5948,0,0},{0,13,-947.9,-156.4,177.9,37.4,42.1,6,6171,0,0},{0,30,-1001.5,-158.4,177.9,69.9,57.8,8,4559,0,0},{0,30,-1046.9,-160.0,177.9,20.9,53.8,8,6501,0,0},{0,30,-1137.5,-221.3,117.1,32.7,57.4,6,1169,0,0},
		{0,10,-1155.7,-258.3,115.6,49.9,19.3,5,8969,0,0},{0,30,-1172.3,-298.4,102.6,14.8,67.2,6,8656,0,0},{0,13,-1177.6,-350.5,91.0,39.3,42.8,7,1193,0,0},{0,10,-1178.2,-382.9,90.9,25.6,37.9,5,2997,0,0},{0,30,-1103.7,-469.2,17.3,58.2,54.9,6,9962,0,0},{0,13,-1062.1,-482.2,17.3,29.1,46.6,6,8727,0,0},{0,30,-1036.6,-490.1,17.3,24.3,58.6,7,1047,0,0},{0,30,-954.2,-433.0,-73.1,57.9,42.9,7,4108,0,0},
		{0,10,-939.3,-384.0,-73.1,44.7,34.8,4,2178,0,0},{0,10,-928.8,-349.4,-73.1,27.5,32.4,4,7923,0,0},{0,13,-914.6,-307.2,-70.8,61.7,44.9,5,6324,0,0},{0,30,-895.8,-254.0,-70.1,51.3,61.7,8,1131,0,0},{0,13,-1056.7,-305.4,108.3,48,42,6,8024,1,0},{0,13,-1072.4,-352.9,108.3,48,42,6,8769,1,0},{0,10,-661.6,-630.3,-100.6,35.0,50,4,1567,0,-1},{0,30,-883.3,-657.6,1.7,44.9,63.7,6,271,0,0},
		{0,13,-830.6,-658.7,0.8,60.6,32.7,6,9102,0,0},{0,13,-677.9,-543.1,-100.6,22.2,42.5,6,8368,0,0},{0,13,-696.3,-488.8,-111.3,62.2,43.1,5,5907,0,0},{0,30,-713.5,-444.6,-111.3,32.7,51.6,6,7001,0,0},{0,10,-730.0,-402.4,-111.3,57.9,37.3,5,3799,0,0},{0,10,-752.3,-345.0,-111.3,65.1,37.2,3,2025,0,0},{0,10,-775.5,-285.7,-111.3,62.4,28.8,5,5284,0,0},{0,13,-837.7,-334.7,109.8,31.5,36.9,6,8214,0,0},
		{0,30,-869.8,-437.5,106.9,60.8,67.1,5,3685,0,0},{0,10,-883.6,-482.8,106.9,34.0,30.8,5,4241,0,0},{0,30,-893.4,-515.0,106.9,33.3,64.0,5,4371,0,0},{0,13,-903.7,-548.8,106.9,37.3,56.1,6,3681,0,0},{0,13,-911.8,-573.1,111.8,13.9,32.2,6,5822,0,0},{0,30,-933.0,-608.7,122.7,69.2,16.6,5,5690,0,0},{0,13,-743.8,-599.8,-69.0,48,42,6,8162,1,0},{0,13,-767.0,-537.4,-69.0,48,42,6,2024,1,0},
		{0,13,-665.5,-727.1,178.4,44.0,44,6,8585,0,-1},{0,29,-1021.3,-745.5,122.2,46.5,30.3,4,4931,0,0},{0,29,-1059.9,-825.2,110.5,55.7,30.0,3,8894,0,0},{0,13,-1074.2,-863.5,110.5,26.2,52.6,6,5674,0,0},{1,25,-1008.9,-896.9,-2.9,14.7,34.2,0,366,0,0},{1,22,-994.3,-896.2,-2.9,14.7,34.2,0,9031,0,0},{1,25,-979.6,-895.4,-2.9,14.7,34.2,0,4661,0,0},{1,23,-964.9,-894.7,-2.9,14.7,34.2,0,79,0,0},
		{0,29,-930.0,-892.9,-2.9,55.2,30.1,4,5947,0,0},{1,27,-892.7,-891.1,-2.9,19.4,36.9,0,3957,0,0},{1,24,-875.7,-890.6,-0.1,14.7,34.2,0,3643,0,0},{1,23,-861.0,-890.6,-0.0,14.7,34.2,0,2916,0,0},{0,29,-834.6,-890.7,0.3,38.1,36.5,3,5323,0,0},{1,25,-808.2,-891.2,2.9,14.7,34.2,0,9404,0,0},{1,24,-793.5,-891.9,2.9,14.7,34.2,0,1889,0,0},{1,25,-778.9,-892.7,2.9,14.7,34.2,0,808,0,0},
		{1,23,-764.2,-893.4,2.9,14.7,34.2,0,151,0,0},{1,25,-749.5,-894.2,2.9,14.7,34.2,0,2927,0,0},{0,29,-726.0,-895.4,2.9,32.3,35.4,2,8852,0,0},{1,22,-702.6,-896.6,2.9,14.7,34.2,0,9032,0,0},{0,29,-677.0,-897.9,2.9,36.6,36.9,3,235,0,0},{0,10,-625.6,-822.2,-100.6,65.3,31.8,3,8073,0,0},{1,22,-633.0,-782.9,-100.6,14.7,34.2,0,5857,0,0},{0,29,-710.6,-728.3,178.4,46.2,33.4,2,9820,0,0},
		{0,29,-751.4,-729.5,178.4,35.4,30.6,4,2665,0,0},{1,23,-776.5,-730.2,178.4,14.7,34.2,0,4631,0,0},{1,28,-804.4,-730.9,178.4,41.2,28.1,0,8582,0,0},{0,13,-839.0,-731.2,-178.5,27.9,57.1,6,928,0,0},{1,22,-860.2,-730.6,-178.2,14.7,34.2,0,7295,0,0},{0,13,-901.5,-729.2,-178.2,67.9,59.7,6,3519,0,0},{0,29,-951.8,-727.6,-178.2,32.6,32.6,2,9296,0,0},{0,10,-1040.6,-1470.3,2.3,44.0,44,3,4198,0,-1},
		{0,29,-638.3,-1464.4,-87.8,44.0,44,3,3090,0,-1},{0,13,-627.5,-992.6,-177.0,37.4,44,7,1646,0,-1},{0,13,-1101.7,-1021.1,84.3,54.8,16.8,7,4273,0,0},{1,28,-1096.9,-1068.9,84.3,41.2,28.1,0,9040,0,0},{1,28,-1092.8,-1109.8,84.3,41.2,28.1,0,3469,0,0},{0,29,-1089.1,-1146.6,84.3,32.8,33.2,2,8421,0,0},{0,29,-1085.2,-1185.8,84.3,45.9,36.0,2,5012,0,0},{0,29,-1080.4,-1236.7,84.9,56.4,37.4,4,9213,0,0},
		{1,22,-1077.4,-1272.1,85.7,14.7,34.2,0,3099,0,0},{1,26,-1075.3,-1300.0,85.7,41.1,28.0,0,2565,0,0},{0,10,-1072.0,-1344.0,85.7,47.3,36.2,4,7442,0,0},{1,26,-1068.7,-1388.1,85.7,41.1,28.0,0,9988,0,0},{0,13,-1066.5,-1417.1,85.7,17.0,53.8,5,1156,0,0},{0,29,-992.9,-1472.2,2.3,51.5,34.7,3,1285,0,0},{1,26,-946.6,-1474.1,2.3,41.1,28.0,0,9908,0,0},{0,29,-907.4,-1475.7,2.3,37.4,32.5,2,9170,0,0},
		{0,29,-861.3,-1477.5,2.3,54.9,30.1,2,5124,0,0},{0,29,-812.0,-1479.5,2.3,43.9,36.1,4,2475,0,0},{1,22,-782.7,-1480.7,2.3,14.7,34.2,0,8553,0,0},{0,29,-753.1,-1481.8,2.3,44.5,30.4,4,9167,0,0},{1,26,-710.3,-1483.5,2.3,41.1,28.0,0,78,0,0},{0,13,-636.7,-1420.4,-87.8,44.0,57.4,5,7965,0,0},{1,23,-635.6,-1391.1,-87.8,14.7,34.2,0,8688,0,0},{1,28,-634.5,-1363.2,-87.8,41.2,28.1,0,5444,0,0},
		{1,22,-633.4,-1335.3,-87.8,14.7,34.2,0,3940,0,0},{1,25,-632.9,-1320.6,-87.8,14.7,34.2,0,5767,0,0},{0,13,-632.1,-1300.0,-87.8,26.4,47.3,5,3370,0,0},{0,13,-630.9,-1268.8,-87.8,36.1,49.7,7,2036,0,0},{1,26,-628.7,-1230.3,-85.7,41.1,28.0,0,7442,0,0},{1,24,-626.4,-1202.5,-84.3,14.7,34.2,0,127,0,0},{0,29,-623.3,-1170.7,-84.3,49.2,31.3,3,8864,0,0},{0,10,-618.5,-1122.7,-84.3,47.3,39.1,3,7271,0,0},
		{0,29,-614.4,-1081.7,-84.3,35.3,32.8,2,1767,0,0},{0,29,-611.3,-1050.8,-84.3,26.8,12.0,4,6606,0,0},{1,23,-715.1,-988.0,-177.0,14.7,34.2,0,6083,0,0},{0,29,-745.7,-986.5,-177.0,46.5,33.8,3,8554,0,0},{1,24,-776.3,-984.9,-177.0,14.7,34.2,0,7758,0,0},{1,24,-791.0,-984.1,-177.0,14.7,34.2,0,2993,0,0},{0,29,-813.4,-983.2,-177.8,30.3,37.9,3,3412,0,0},{0,29,-846.0,-982.6,-180.0,34.9,16.3,2,2481,0,0},
		{1,27,-873.1,-982.6,179.5,19.4,36.9,0,2858,0,0},{0,29,-896.6,-983.4,177.1,27.6,11.7,4,9191,0,0},{1,22,-917.8,-984.4,177.1,14.7,34.2,0,5638,0,0},{1,28,-945.7,-985.8,177.1,41.2,28.1,0,3074,0,0},{1,26,-986.8,-987.9,177.1,41.1,28.0,0,9977,0,0},{1,23,-1014.7,-989.3,177.1,14.7,34.2,0,5093,0,0},{1,26,-1042.5,-990.7,177.1,41.1,28.0,0,3697,0,0},{0,13,-704.2,-1176.0,-177.7,48,42,7,32,1,0},
		{0,13,-700.7,-1088.1,-177.7,48,42,6,6840,1,0},{0,13,-698.9,-1044.1,-177.7,48,42,5,5931,1,0},{0,13,-761.2,-1349.9,-177.7,48,42,5,7946,1,0},{0,13,-759.4,-1305.9,-177.7,48,42,6,6186,1,0},{0,13,-757.7,-1261.9,-177.7,48,42,7,6131,1,0},{0,13,-755.9,-1218.0,-177.7,48,42,7,1764,1,0},{0,13,-754.1,-1174.0,-177.7,48,42,6,2993,1,0},{0,13,-752.4,-1130.0,-177.7,48,42,5,9543,1,0},
		{0,13,-750.6,-1086.1,-177.7,48,42,5,3938,1,0},{0,13,-748.9,-1042.1,-177.7,48,42,7,7564,1,0},{0,13,-811.1,-1347.9,-177.7,48,42,6,5098,1,0},{0,13,-809.4,-1303.9,-177.7,48,42,7,595,1,0},{0,13,-807.6,-1259.9,-177.7,48,42,7,8228,1,0},{0,13,-805.9,-1216.0,-177.7,48,42,6,2589,1,0},{0,13,-804.1,-1172.0,-177.7,48,42,7,2740,1,0},{0,13,-802.3,-1128.0,-177.7,48,42,5,2401,1,0},
		{0,13,-800.6,-1084.1,-177.7,48,42,6,2058,1,0},{0,13,-798.8,-1040.1,-177.7,48,42,7,9398,1,0},{0,13,-861.1,-1345.9,-177.7,48,42,5,5324,1,0},{0,13,-859.3,-1301.9,-177.7,48,42,7,4650,1,0},{0,13,-857.6,-1257.9,-177.7,48,42,5,4951,1,0},{0,13,-855.8,-1214.0,-177.7,48,42,5,2981,1,0},{0,13,-854.1,-1170.0,-177.7,48,42,6,7754,1,0},{0,13,-852.3,-1126.0,-177.7,48,42,6,1045,1,0},
		{0,13,-850.5,-1082.1,-177.7,48,42,6,1802,1,0},{0,13,-911.1,-1343.9,-177.7,48,42,5,5965,1,0},{0,13,-909.3,-1299.9,-177.7,48,42,5,9070,1,0},{0,13,-907.5,-1255.9,-177.7,48,42,7,720,1,0},{0,13,-905.8,-1212.0,-177.7,48,42,7,7547,1,0},{0,13,-904.0,-1168.0,-177.7,48,42,5,8311,1,0},{0,13,-902.3,-1124.0,-177.7,48,42,6,7321,1,0},{0,13,-900.5,-1080.1,-177.7,48,42,7,9376,1,0},
		{0,13,-961.0,-1341.9,-177.7,48,42,7,5086,1,0},{0,13,-959.3,-1297.9,-177.7,48,42,5,5660,1,0},{0,13,-957.5,-1253.9,-177.7,48,42,7,2768,1,0},{0,13,-955.7,-1210.0,-177.7,48,42,5,614,1,0},{0,13,-954.0,-1166.0,-177.7,48,42,7,2296,1,0},{0,13,-952.2,-1122.0,-177.7,48,42,7,4527,1,0},{0,13,-950.5,-1078.1,-177.7,48,42,6,7898,1,0},{0,13,-1002.2,-1120.0,-177.7,48,42,5,6200,1,0},
		{0,13,-1000.4,-1076.1,-177.7,48,42,7,8958,1,0},{0,17,-1821.2,-1612.3,102.3,34.0,34,3,2238,0,-1},{0,2,-1808.2,-1973.1,17.5,34.0,34,4,2931,0,-1},{0,17,-1723.2,-2055.0,19.6,34.0,34,3,3939,0,-1},{0,2,-980.3,-2177.5,-48.9,34.0,34,4,5578,0,-1},{0,17,-861.1,-2134.9,-54.9,34.0,34,3,2941,0,-1},{0,29,-730.9,-1586.8,-177.7,67.8,32.7,4,577,0,0},{0,33,-797.4,-1584.1,-177.7,65.3,28.0,2,8652,0,0},
		{1,26,-850.6,-1582.0,-177.7,41.1,28.0,0,9919,0,0},{1,28,-891.7,-1580.4,-177.7,41.2,28.1,0,8455,0,0},{1,31,-961.7,-1577.6,-177.7,98.9,36.8,0,2017,0,0},{1,31,-1060.5,-1573.9,-178.1,98.9,36.8,0,803,0,0},{0,29,-1158.5,-1573.6,178.5,43.0,33.1,4,9936,0,0},{1,28,-1829.2,-1649.0,102.3,41.2,28.1,0,9672,0,0},{1,27,-1835.7,-1678.6,102.3,19.4,36.9,0,315,0,0},{1,23,-1839.3,-1695.3,102.3,14.7,34.2,0,8300,0,0},
		{0,29,-1847.6,-1733.4,102.3,63.2,33.7,3,4543,0,0},{0,29,-1859.0,-1780.2,106.2,33.2,30.7,3,4256,0,0},{0,29,-1859.7,-1826.8,76.0,31.9,27.5,4,3370,0,0},{0,29,-1850.2,-1864.8,76.0,46.5,33.4,4,3312,0,0},{0,29,-1838.6,-1911.2,76.0,49.1,37.9,2,3890,0,0},{0,10,-1786.6,-1984.4,33.6,14.9,37.8,4,8725,0,0},{0,29,-1774.5,-1993.6,41.0,15.5,11.2,2,8325,0,0},{0,29,-1755.9,-2014.2,56.3,10.2,34.8,4,4546,0,0},
		{0,10,-1681.0,-2070.0,19.6,55.5,34.3,4,2459,0,0},{1,32,-1608.3,-2095.9,19.6,98.8,28.0,0,783,0,0},{0,33,-1542.2,-2119.4,19.6,41.4,32.0,2,8392,0,0},{0,29,-1491.7,-2137.2,19.4,65.8,35.7,3,2921,0,0},{1,22,-1397.2,-2165.5,10.9,14.7,34.2,0,4916,0,0},{0,29,-1377.1,-2169.4,10.9,26.3,32.2,4,9439,0,0},{1,27,-1322.5,-2176.1,5.2,19.4,36.9,0,7454,0,0},{0,29,-1279.1,-2178.6,2.6,67.7,13.3,2,5841,0,0},
		{1,31,-1195.9,-2182.1,2.3,98.9,36.8,0,37,0,0},{1,26,-1125.9,-2184.9,2.3,41.1,28.0,0,3458,0,0},{1,24,-1098.0,-2186.0,2.3,14.7,34.2,0,4163,0,0},{0,29,-1058.1,-2187.6,2.3,65.3,31.9,4,5578,0,0},{0,29,-958.9,-2161.9,-31.9,19.0,31.4,4,3245,0,0},{1,25,-929.9,-2149.2,-15.0,14.7,34.2,0,2566,0,0},{0,29,-916.4,-2146.4,-7.7,12.8,33.0,3,8025,0,0},{0,33,-836.7,-2099.4,-55.7,52.1,33.4,2,7316,0,0},
		{0,29,-811.9,-2061.7,-58.0,38.1,13.5,4,1644,0,0},{1,32,-775.7,-2003.7,-58.0,98.8,28.0,0,569,0,0},{0,29,-734.8,-1915.6,-73.4,65.1,36.2,4,8506,0,0},{0,29,-716.8,-1855.1,-73.4,61.1,36.5,3,8654,0,0},{0,29,-703.9,-1811.9,-73.4,29.2,35.8,3,4401,0,0},{1,26,-693.9,-1778.2,-73.4,41.1,28.0,0,2123,0,0},{0,29,-675.8,-1697.9,-79.5,57.6,33.0,4,6319,0,0},{1,26,-666.8,-1649.4,-79.5,41.1,28.0,0,4640,0,0},
		{1,24,-661.7,-1622.0,-79.5,14.7,34.2,0,601,0,0},{1,22,-659.1,-1607.5,-79.5,14.7,34.2,0,1269,0,0},{0,3,-927.9,-1880.0,86.6,40.7,31.0,15,769,0,0},{1,19,-2595.2,1274.9,88.2,52.3,28.2,0,7777,0,0},{1,28,-2593.5,1222.0,88.2,41.2,28.1,0,9887,0,0},{1,18,-2592.0,1175.2,88.2,52.3,28.2,0,51,0,0},{1,23,-2590.7,1131.9,88.2,14.7,34.2,0,4786,0,0},{0,29,-2589.7,1101.1,88.2,46.9,36.3,2,2299,0,0},
		{0,29,-2588.0,1046.9,88.2,61.5,35.9,2,7460,0,0},{0,29,-2566.4,997.9,47.6,23.1,16.8,3,348,0,0},{0,29,-2552.3,979.2,58.3,24.1,37.0,2,4152,0,0},{0,29,-2486.8,973.4,-4.3,56.1,16.0,2,207,0,0},{1,22,-2451.5,976.0,-4.3,14.7,34.2,0,3219,0,0},{1,18,-2418.1,978.5,-4.3,52.3,28.2,0,5479,0,0},{1,12,-2368.4,982.2,-4.3,35.3,29.0,0,4174,0,0},{0,29,-2316.0,986.2,-4.3,57.5,33.3,4,9694,0,0},
		{0,29,-2194.4,988.3,2.0,50.4,31.3,4,7795,0,0},{1,19,-2143.1,986.4,2.0,52.3,28.2,0,636,0,0},{1,22,-2101.6,985.0,2.0,14.7,34.2,0,3747,0,0},{1,19,-2068.1,983.8,2.0,52.3,28.2,0,998,0,0},{1,23,-2024.8,982.3,2.0,14.7,34.2,0,5118,0,0},{0,29,-1992.6,981.1,2.0,49.8,34.6,2,2727,0,0},{1,19,-1941.6,979.3,2.0,52.3,28.2,0,8376,0,0},{1,25,-1899.4,977.8,2.0,14.7,34.2,0,569,0,0},
		{0,29,-1887.5,977.4,2.0,9.2,30.3,3,3403,0,0},{1,20,-1822.9,1052.8,-51.6,64.1,41.3,0,7035,0,0},{1,27,-1791.3,1092.6,-51.6,19.4,36.9,0,1029,0,0},{1,24,-1780.7,1105.9,-51.6,14.7,34.2,0,4984,0,0},{0,29,-1765.2,1125.5,-51.6,35.3,31.4,3,4422,0,0},{0,29,-1735.8,1162.6,-51.6,59.3,32.5,4,2596,0,0},{1,24,-1712.8,1191.5,-51.6,14.7,34.2,0,6656,0,0},{1,26,-1695.4,1213.4,-51.6,41.1,28.0,0,1158,0,0},
		{1,26,-1669.6,1245.3,-50.5,41.1,28.0,0,2406,0,0},{0,29,-1647.8,1271.1,-48.7,26.4,21.6,2,2574,0,0},{0,10,-1693.9,1300.1,-175.8,42.4,16.7,3,8048,0,0},{1,20,-1747.0,1304.0,-175.8,64.1,41.3,0,4196,0,0},{1,18,-1813.4,1308.9,-175.8,52.3,28.2,0,9483,0,0},{1,7,-1861.4,1312.5,-175.8,24.2,27.9,0,6427,0,0},{1,11,-1892.4,1314.7,-175.8,17.8,29.0,0,5099,0,0},{1,6,-1935.9,1318.0,-175.8,51.4,31.0,0,2761,0,0},
		{1,20,-2001.3,1322.8,-175.8,64.1,41.3,0,3822,0,0},{1,19,-2067.4,1327.3,-176.7,52.3,28.2,0,8716,0,0},{1,18,-2125.8,1327.0,176.8,52.3,28.2,0,9447,0,0},{1,8,-2171.8,1324.4,176.8,26.9,27.9,0,7471,0,0},{1,4,-2214.4,1322.1,176.8,35.5,29.3,0,5751,0,0},{1,8,-2254.2,1319.9,176.8,26.9,27.9,0,1238,0,0},{1,11,-2288.4,1318.0,176.8,17.8,29.0,0,627,0,0},{1,14,-2325.2,1316.0,176.8,34.9,32.4,0,5450,0,0},
		{1,19,-2377.6,1313.1,176.8,52.3,28.2,0,9468,0,0},{1,18,-2436.8,1309.8,176.8,52.3,28.2,0,9810,0,0},{1,9,-2486.3,1307.0,176.8,28.8,32.0,0,7226,0,0},{1,12,-2528.3,1304.7,176.8,35.3,29.0,0,7552,0,0},{0,17,-1575.9,952.8,-84.6,28.9,34,3,7855,0,-1},{0,29,-1601.9,1163.7,128.7,65.7,28.3,3,9761,0,0},{1,32,-1653.2,1099.4,128.4,98.8,28.0,0,5569,0,0},{1,23,-1688.5,1054.9,128.4,14.7,34.2,0,792,0,0},
		{0,29,-1714.6,1021.9,128.4,69.6,34.2,4,7533,0,0},{0,33,-1663.3,952.3,10.8,52.8,33.4,2,5098,0,0},{1,19,-1569.1,1024.2,-84.6,52.3,28.2,0,3638,0,0},{0,33,-1564.4,1074.3,-84.6,34.0,31.6,2,701,0,0},{0,33,-1561.7,1105.6,-85.6,28.9,30.9,2,3830,0,0},{0,10,-1794.3,-428.2,23.7,50.0,50,4,2090,0,-1},{0,10,-1550.6,-508.5,-55.6,50.0,50,3,9990,0,-1},{0,10,-1509.3,-404.0,-150.0,42.5,50,4,7800,0,-1},
		{0,13,-1800.2,-240.7,148.4,9.1,47.8,6,4490,0,0},{0,13,-1810.1,-322.8,94.3,32.9,48.9,6,5366,0,0},{0,13,-1812.4,-353.7,94.3,29.3,44.7,7,8695,0,0},{0,30,-1744.5,-450.1,23.7,58.8,48.2,5,6978,0,0},{0,13,-1701.0,-469.3,23.7,36.2,53.6,7,473,0,0},{0,30,-1647.5,-492.8,23.7,80.7,45.0,5,6558,0,0},{0,30,-1595.6,-354.1,-150.0,57.1,66.2,8,2166,0,0},{0,13,-1644.8,-325.8,-150.0,56.4,52.8,6,4684,0,0},
		{0,10,-1680.9,-304.9,-150.0,27.0,39.5,4,8768,0,0},{0,13,-1714.2,-285.7,-150.0,49.9,43.7,6,9390,0,0},{0,13,-1571.4,-417.8,30.0,48,42,7,9033,1,0},{0,29,-1786.0,-884.4,35.8,44.0,44,3,5023,0,-1},{0,29,-1701.3,-892.7,-76.6,44.0,44,4,9742,0,-1},{0,13,-1676.8,-558.5,-156.3,64.0,47.7,7,4496,0,0},{1,24,-1712.8,-542.6,-156.3,14.7,34.2,0,7549,0,0},{1,25,-1726.2,-536.7,-156.3,14.7,34.2,0,4523,0,0},
		{1,28,-1751.8,-525.5,-156.3,41.2,28.1,0,5820,0,0},{1,28,-1789.5,-508.9,-156.3,41.2,28.1,0,736,0,0},{0,10,-1825.5,-551.0,91.9,28.9,31.3,3,3775,0,0},{0,29,-1821.3,-644.5,85.6,69.4,33.2,2,8999,0,0},{0,29,-1816.5,-707.1,85.6,56.1,37.8,4,1380,0,0},{0,13,-1812.6,-758.6,85.6,47.2,43.4,5,1787,0,0},{0,29,-1809.0,-804.9,85.6,45.7,31.1,4,8573,0,0},{0,29,-1759.3,-910.4,4.1,18.2,12.6,4,1004,0,0},
		{0,13,-1689.7,-844.0,-76.6,56.2,51.9,7,5720,0,0},{0,29,-1678.9,-798.7,-76.6,36.8,33.9,4,224,0,0},{0,10,-1669.2,-758.1,-76.6,46.8,33.5,4,767,0,0},{1,27,-1661.6,-725.9,-76.6,19.4,36.9,0,1930,0,0},{1,24,-1657.6,-709.3,-76.6,14.7,34.2,0,1539,0,0},{1,23,-1654.2,-695.0,-76.6,14.7,34.2,0,6273,0,0},{1,25,-1650.8,-680.7,-76.6,14.7,34.2,0,1490,0,0},{0,29,-1645.3,-661.9,-71.9,24.5,33.5,3,1958,0,0},
		{1,23,-1638.4,-643.6,-65.5,14.7,34.2,0,318,0,0},{1,24,-1631.9,-630.5,-61.4,14.7,34.2,0,4587,0,0},{0,13,-1791.6,-1042.9,86.1,44.0,44,5,8687,0,-1},{0,29,-1759.3,-1200.9,8.2,44.0,44,3,7810,0,-1},{0,29,-1477.5,-1018.9,177.5,44.0,44,4,496,0,-1},{0,29,-1778.3,-1005.7,127.7,10.8,16.4,2,5100,0,0},{1,27,-1789.4,-1074.5,86.1,19.4,36.9,0,6964,0,0},{0,13,-1787.8,-1098.9,86.1,29.5,55.1,5,6218,0,0},
		{0,29,-1785.4,-1133.8,86.1,40.3,33.7,3,3065,0,0},{0,13,-1712.0,-1207.8,8.2,51.5,43.8,5,795,0,0},{1,25,-1679.3,-1212.5,8.2,14.7,34.2,0,4550,0,0},{1,28,-1651.6,-1216.5,8.2,41.2,28.1,0,6140,0,0},{0,29,-1612.5,-1222.1,8.2,37.8,32.5,2,1426,0,0},{0,29,-1571.2,-1229.1,10.7,46.1,34.6,3,109,0,0},{0,29,-1524.2,-1238.6,12.0,49.6,34.0,2,8909,0,0},{0,29,-1469.8,-1250.1,12.0,61.7,32.8,3,1300,0,0},
		{1,24,-1432.4,-1258.1,12.0,14.7,34.2,0,5506,0,0},{1,23,-1418.0,-1261.1,12.0,14.7,34.2,0,8729,0,0},{0,10,-1394.2,-1212.3,-106.1,40.3,12.4,5,5580,0,0},{1,23,-1402.0,-1185.9,-107.7,14.7,34.2,0,572,0,0},{0,10,-1409.3,-1163.0,-107.7,33.6,33.9,5,1282,0,0},{0,13,-1419.2,-1131.8,-107.7,31.8,45.4,7,5150,0,0},{1,28,-1430.3,-1097.1,-107.7,41.2,28.1,0,8990,0,0},{0,13,-1439.3,-1068.7,-107.7,18.5,52.4,5,2148,0,0},
		{1,23,-1506.8,-1019.5,-178.1,14.7,34.2,0,3304,0,0},{1,25,-1521.5,-1019.1,-178.1,14.7,34.2,0,414,0,0},{1,28,-1549.4,-1017.5,-176.2,41.2,28.1,0,1034,0,0},{1,26,-1590.4,-1014.6,-175.9,41.1,28.0,0,921,0,0},{0,29,-1634.9,-1011.5,-175.9,48.0,35.6,3,6226,0,0},{1,25,-1666.1,-1009.2,-175.9,14.7,34.2,0,7417,0,0},{1,23,-1680.8,-1008.2,-175.9,14.7,34.2,0,786,0,0},{0,29,-1701.7,-1006.7,-175.9,27.2,33.5,4,4472,0,0},
		{0,13,-1654.2,-1138.9,2.9,48,42,7,5294,1,0},{0,13,-1604.3,-1141.5,2.9,48,42,5,2558,1,0},{0,13,-1554.3,-1144.1,2.9,48,42,5,2840,1,0},{0,29,-1775.8,-1431.9,41.7,44.0,44,2,6368,0,-1},{0,29,-1402.2,-1454.1,-84.6,44.0,44,4,7329,0,-1},{0,29,-1413.0,-1335.8,-168.0,44.0,44,4,8975,0,-1},{0,10,-1786.8,-1338.8,93.9,69.3,31.1,3,622,0,0},{1,28,-1673.4,-1462.1,4.6,41.2,28.1,0,6982,0,0},
		{0,13,-1620.1,-1466.5,4.6,65.8,46.2,7,7305,0,0},{0,10,-1566.7,-1470.8,4.6,41.4,38.5,5,440,0,0},{0,10,-1531.8,-1473.6,4.6,28.5,33.8,4,1666,0,0},{1,25,-1510.3,-1475.3,4.1,14.7,34.2,0,7445,0,0},{0,29,-1397.9,-1408.2,-84.6,48.2,34.0,4,3286,0,0},{0,10,-1448.4,-1328.3,-168.0,28.4,35.5,5,6518,0,0},{1,28,-1482.5,-1321.0,-168.0,41.2,28.1,0,112,0,0},{0,10,-1526.6,-1311.7,-168.0,49.0,30.4,3,603,0,0},
		{0,13,-1575.9,-1301.5,-168.7,51.8,49.5,6,2877,0,0},{0,13,-1681.1,-1284.9,-171.8,34.7,54.6,7,9755,0,0},{0,29,-1721.2,-1279.1,-171.8,46.3,33.4,4,8419,0,0},{0,13,-1686.8,-1410.9,5.4,48,42,6,7797,1,0},{0,2,-2636.5,-906.3,-1.2,34.0,34,3,1488,0,-1},{0,17,-2779.0,-214.4,114.8,34.0,34,3,8451,0,-1},{0,2,-2808.5,-267.7,87.1,34.0,34,4,7128,0,-1},{0,29,-2707.8,-848.4,27.1,26.2,35.6,3,6138,0,0},
		{0,29,-2689.6,-859.7,39.4,16.8,32.5,4,5912,0,0},{0,29,-2678.8,-869.4,45.4,12.2,35.7,4,2326,0,0},{1,31,-2570.1,-904.9,-1.2,98.9,36.8,0,178,0,0},{0,33,-2507.2,-903.5,-1.2,26.9,30.1,3,4644,0,0},{0,33,-2478.7,-902.9,-1.2,30.0,33.4,3,4016,0,0},{1,28,-2443.1,-902.1,-1.2,41.2,28.1,0,4930,0,0},{0,29,-2416.3,-901.5,-1.2,12.5,32.5,3,6543,0,0},{0,29,-1963.6,-198.8,-178.9,54.3,15.2,4,8167,0,0},
		{0,29,-2017.5,-197.7,-178.9,53.4,16.9,4,592,0,0},{0,29,-2058.9,-197.0,-178.9,29.5,17.5,3,1906,0,0},{0,33,-2105.3,-196.1,-178.9,63.4,15.5,3,9702,0,0},{0,33,-2160.4,-195.0,-178.9,46.8,16.3,3,7927,0,0},{0,29,-2205.7,-194.2,-178.9,43.7,21.0,2,4834,0,0},{0,29,-2243.3,-193.5,-178.9,31.5,20.3,4,4644,0,0},{0,29,-2287.2,-192.6,-178.9,56.2,20.9,4,2488,0,0},{0,33,-2344.7,-191.8,-179.4,58.8,20.2,2,7824,0,0},
		{0,10,-2387.2,-191.7,178.9,26.3,21.3,3,6710,0,0},{0,29,-2421.9,-192.4,178.9,43.1,19.0,3,8986,0,0},{1,24,-2450.8,-192.9,178.9,14.7,34.2,0,8975,0,0},{1,32,-2507.5,-194.0,178.9,98.8,28.0,0,3783,0,0},{1,32,-2606.3,-195.8,178.9,98.8,28.0,0,4173,0,0},{0,29,-2670.0,-197.0,178.9,28.5,31.1,3,4892,0,0},{0,33,-2711.0,-197.8,178.9,53.7,30.1,2,8283,0,0},{0,29,-2793.3,-235.1,130.6,16.5,11.2,2,3444,0,0},
		{0,29,-2806.3,-313.1,87.1,56.9,30.1,2,236,0,0},{1,31,-2802.4,-391.0,87.1,98.9,36.8,0,5628,0,0},{0,29,-2799.2,-455.3,87.1,30.0,30.2,2,8603,0,0},{1,28,-2796.9,-490.9,86.0,41.2,28.1,0,8982,0,0},{0,29,-2794.1,-525.5,84.3,28.3,19.5,4,1700,0,0},{0,10,-2778.1,-612.8,76.3,36.9,32.4,4,8759,0,0},{1,32,-2761.5,-678.6,75.6,98.8,28.0,0,6477,0,0},{0,33,-2745.8,-739.5,75.6,27.0,30.1,3,1104,0,0},
		{0,33,-2737.4,-772.3,75.6,40.6,29.9,3,9481,0,0},{0,3,-2688.6,-387.7,103.9,36.0,29.2,17,4700,0,0},{0,3,-2508.1,-383.7,122.3,41.2,28.1,17,3954,0,0},{0,17,-2269.8,-1530.4,-8.7,34.0,34,3,3552,0,-1},{0,2,-2147.3,-1494.4,-93.8,34.0,34,3,3085,0,-1},{0,2,-2181.4,-1238.7,172.8,28.9,34,3,8296,0,-1},{0,10,-2383.2,-1485.7,-1.0,21.5,32.3,5,9718,0,0},{1,24,-2365.1,-1486.5,7.5,14.7,34.2,0,4925,0,0},
		{0,33,-2225.8,-1523.7,-8.7,54.9,30.5,2,3272,0,0},{1,24,-2191.4,-1518.4,-8.7,14.7,34.2,0,4367,0,0},{1,32,-2151.7,-1428.2,-93.8,98.8,28.0,0,913,0,0},{1,31,-2158.3,-1329.6,-93.8,98.9,36.8,0,4083,0,0},{0,33,-2281.9,-1251.4,172.8,44.0,29.0,3,4094,0,0},{0,33,-2324.1,-1256.7,172.8,41.1,28.7,2,2912,0,0},{0,33,-2367.2,-1262.1,172.8,45.8,32.4,3,2474,0,0},{1,32,-2493.0,-1264.2,-179.0,98.8,28.0,0,2198,0,0},
		{0,33,-2555.8,-1305.4,48.1,47.7,15.7,2,9380,0,0},{0,10,-2528.6,-1335.7,48.1,33.6,34.4,3,8290,0,0},{0,10,-2501.8,-1365.6,48.1,46.8,33.3,5,3541,0,0},{0,10,-2471.1,-1399.9,48.1,45.2,36.9,5,4216,0,0},{1,28,-2442.2,-1432.0,48.1,41.2,28.1,0,9374,0,0},{0,2,-1894.7,-1393.1,-86.1,34.0,34,4,5162,0,-1},{0,17,-1910.6,-1018.0,-144.0,34.0,34,3,9582,0,-1},{0,2,-1949.1,-988.8,-178.7,28.9,34,3,3504,0,-1},
		{0,17,-2101.7,-1002.4,87.8,28.9,34,3,1666,0,-1},{0,2,-2058.4,-1493.0,-12.7,23.8,34,4,3684,0,-1},{1,25,-1942.6,-1460.8,-65.6,14.7,34.2,0,8255,0,0},{0,33,-1935.9,-1448.1,-58.4,14.2,31.0,3,5918,0,0},{0,29,-1927.5,-1436.3,-51.2,14.8,36.7,2,3874,0,0},{1,31,-1890.2,-1326.8,-86.1,98.9,36.8,0,1944,0,0},{0,29,-1885.8,-1263.8,-86.1,27.4,36.5,2,2276,0,0},{0,10,-1888.0,-1157.4,-93.9,63.6,39.3,3,7603,0,0},
		{1,23,-1890.7,-1118.3,-93.9,14.7,34.2,0,9252,0,0},{0,10,-1892.8,-1086.5,-93.9,49.2,39.2,5,943,0,0},{0,33,-2097.9,-1097.7,87.8,34.5,32.0,2,3018,0,0},{1,32,-2095.3,-1164.3,87.8,98.8,28.0,0,1863,0,0},{1,32,-2090.5,-1262.9,86.6,98.8,28.0,0,3823,0,0},{1,32,-2084.2,-1361.5,86.1,98.8,28.0,0,978,0,0},{1,25,-2009.9,-1482.0,-12.7,14.7,34.2,0,9336,0,0},{0,17,-1948.7,-1708.6,-77.7,34.0,34,3,8367,0,-1},
		{1,32,-2123.3,-1750.6,-16.4,98.8,28.0,0,291,0,0},{0,33,-1999.5,-1728.8,-4.4,26.7,29.9,3,1349,0,0},{1,26,-1940.7,-1671.9,-77.7,41.1,28.0,0,664,0,0},{1,22,-1934.7,-1644.6,-77.7,14.7,34.2,0,6112,0,0},{0,29,-1926.2,-1605.4,-77.7,65.5,12.0,2,3561,0,0},{0,29,-2012.8,-1589.4,167.5,58.3,36.7,4,2416,0,0},{1,24,-2048.4,-1597.3,167.5,14.7,34.2,0,3885,0,0},{1,24,-2062.8,-1600.5,167.5,14.7,34.2,0,8366,0,0},
		{0,29,-2090.4,-1606.4,168.1,41.8,32.2,3,1503,0,0},{0,10,-2129.2,-1613.6,171.1,37.2,35.7,4,8380,0,0},{1,22,-2154.9,-1617.7,171.1,14.7,34.2,0,5848,0,0},{0,29,-2180.3,-1621.6,171.1,36.6,33.4,4,4546,0,0},{0,29,-2222.0,-1628.2,171.1,47.8,37.6,3,3621,0,0},{0,2,-1985.9,-1800.0,175.4,28.9,34,3,1005,0,-1},{0,33,-1956.4,-1868.8,-104.0,75.1,31.9,2,6404,0,0},{0,33,-2051.2,-1806.4,171.4,33.0,33.4,2,1444,0,0},
		{0,29,-2072.1,-1869.1,32.5,39.1,22.7,2,2166,0,0},{0,33,-2041.2,-1888.3,31.0,33.7,19.4,2,2291,0,0},{0,33,-1999.9,-1913.1,31.0,62.5,10.3,3,343,0,0},{0,17,-2191.4,-983.5,-179.0,34.0,34,3,2920,0,-1},{0,17,-2658.8,-1004.1,114.7,34.0,34,3,7775,0,-1},{0,17,-2597.1,-1190.4,1.2,34.0,34,3,6562,0,-1},{1,32,-2169.3,-1114.9,-92.2,98.8,28.0,0,3418,0,0},{0,33,-2172.2,-1041.7,-92.2,47.8,28.3,3,4354,0,0},
		{1,25,-2215.8,-983.0,-179.0,14.7,34.2,0,1838,0,0},{1,22,-2230.5,-982.8,-179.0,14.7,34.2,0,6174,0,0},{1,32,-2287.2,-982.2,-179.5,98.8,28.0,0,2200,0,0},{0,10,-2350.4,-982.1,178.8,27.5,19.4,3,8480,0,0},{0,33,-2384.1,-982.8,178.8,39.9,29.4,3,8992,0,0},{1,25,-2411.4,-983.4,178.8,14.7,34.2,0,667,0,0},{0,29,-2439.4,-984.0,178.8,41.4,35.8,2,8227,0,0},{1,31,-2509.6,-985.6,178.8,98.9,36.8,0,6168,0,0},
		{0,10,-2574.4,-987.0,178.8,30.9,39.1,5,5093,0,0},{0,10,-2603.8,-987.6,178.8,27.9,30.9,3,9293,0,0},{0,29,-2652.9,-1068.6,72.3,44.4,37.1,3,7979,0,0},{0,29,-2641.3,-1104.8,72.3,31.5,34.7,2,7584,0,0},{0,29,-2630.5,-1138.7,72.3,39.8,36.8,3,407,0,0},{1,32,-2530.7,-1191.8,1.2,98.8,28.0,0,534,0,0},{0,33,-2446.4,-1193.5,1.1,69.7,31.2,3,678,0,0},{1,32,-2316.6,-1183.5,-7.3,98.8,28.0,0,3059,0,0},
		{0,33,-2234.1,-1172.9,-7.3,67.5,29.7,2,85,0,0},{0,2,-2195.7,-95.1,-89.6,34.0,34,3,5089,0,-1},{0,2,-2395.6,325.8,91.3,34.0,34,4,1916,0,-1},{1,32,-2345.6,-110.0,0.1,98.8,28.0,0,9623,0,0},{0,29,-2273.3,-110.5,1.1,45.7,36.5,2,1570,0,0},{1,23,-2243.2,-111.1,1.1,14.7,34.2,0,5318,0,0},{1,32,-2195.2,-28.7,-89.6,98.8,28.0,0,3284,0,0},{1,32,-2194.6,70.1,-89.6,98.8,28.0,0,479,0,0},
		{1,31,-2194.3,169.0,-90.0,98.9,36.8,0,5282,0,0},{1,32,-2194.6,267.8,-90.3,98.8,28.0,0,4941,0,0},{1,18,-2195.0,343.4,-90.3,52.3,28.2,0,2442,0,0},{0,29,-2259.3,397.8,165.3,48.0,32.8,4,6323,0,0},{1,28,-2326.1,374.4,156.4,41.2,28.1,0,1978,0,0},{0,29,-2354.7,361.7,155.0,21.4,23.0,4,510,0,0},{1,31,-2397.0,259.3,91.3,98.9,36.8,0,8068,0,0},{1,31,-2399.0,160.4,91.0,98.9,36.8,0,3755,0,0},
		{0,33,-2399.2,81.2,88.7,59.6,13.9,2,6607,0,0},{0,33,-2398.2,36.8,88.7,29.4,32.4,2,7502,0,0},{1,19,-2397.3,-4.1,88.7,52.3,28.2,0,5025,0,0},{0,33,-2396.1,-57.4,88.7,37.2,32.8,2,7951,0,0},{0,2,-1899.4,-61.1,-94.8,34.0,34,4,2509,0,-1},{0,2,-2123.4,409.2,89.7,34.0,34,4,7354,0,-1},{0,17,-2106.8,-113.9,1.1,34.0,34,3,1759,0,-1},{0,33,-1929.2,-108.7,-56.8,20.5,32.7,2,6767,0,0},
		{0,33,-1903.2,-14.8,-94.8,59.0,29.4,2,8195,0,0},{1,28,-1907.4,35.2,-94.8,41.2,28.1,0,6444,0,0},{1,32,-1913.2,104.9,-94.8,98.8,28.0,0,1679,0,0},{1,24,-1917.6,161.5,-92.4,14.7,34.2,0,8440,0,0},{0,29,-1916.8,241.4,-86.5,55.6,37.3,3,1862,0,0},{0,33,-1913.7,286.2,-85.0,34.2,31.1,3,6002,0,0},{0,29,-1910.8,319.6,-85.0,32.9,37.9,4,2202,0,0},{1,24,-1908.7,343.3,-85.0,14.7,34.2,0,8803,0,0},
		{1,28,-1906.3,371.2,-85.0,41.2,28.1,0,9864,0,0},{0,33,-1963.3,456.4,169.3,40.6,34.0,2,1199,0,0},{0,33,-1997.8,449.9,169.3,29.6,28.5,3,6228,0,0},{1,25,-2019.5,445.8,169.3,14.7,34.2,0,9348,0,0},{0,33,-2058.4,438.5,169.3,64.5,32.1,3,4459,0,0},{1,32,-2123.0,342.8,89.7,98.8,28.0,0,842,0,0},{1,32,-2122.5,244.0,89.7,98.8,28.0,0,326,0,0},{0,33,-2122.1,175.1,89.8,39.0,28.7,2,2382,0,0},
		{1,31,-2122.4,106.2,90.4,98.9,36.8,0,6417,0,0},{1,31,-2123.0,7.3,90.4,98.9,36.8,0,5075,0,0},{0,33,-2123.4,-60.8,90.4,37.3,28.4,2,8895,0,0},{0,10,-2063.8,-114.7,1.1,52.0,39.9,5,2511,0,0},{0,29,-2013.5,-115.7,1.1,48.5,36.6,4,8148,0,0},{0,2,-2467.3,-94.2,-91.3,34.0,34,3,3327,0,-1},{0,2,-2779.7,-104.6,58.2,28.9,34,3,5820,0,-1},{1,32,-2674.6,-115.1,-1.1,98.8,28.0,0,5023,0,0},
		{1,32,-2575.8,-113.3,-1.1,98.8,28.0,0,1823,0,0},{0,10,-2513.7,-112.1,-1.1,25.5,31.0,3,6228,0,0},{1,31,-2468.8,-27.8,-91.3,98.9,36.8,0,1902,0,0},{1,18,-2470.5,47.8,-91.3,52.3,28.2,0,9008,0,0},{0,33,-2471.5,97.1,-91.3,34.0,32.4,2,43,0,0},{1,31,-2471.0,163.5,-88.9,98.9,36.8,0,3278,0,0},{0,33,-2469.7,227.6,-88.8,29.2,29.8,2,9923,0,0},{0,33,-2468.9,265.7,-88.8,47.1,33.0,2,6007,0,0},
		{0,29,-2524.7,282.3,155.0,39.0,11.8,2,3997,0,0},{0,10,-2565.4,262.6,153.6,51.4,39.9,5,9252,0,0},{0,10,-2623.0,228.4,143.5,30.7,30.4,5,7165,0,0},{0,29,-2674.7,179.9,130.9,46.5,36.5,3,7590,0,0},{0,10,-2717.4,117.8,116.5,25.5,36.2,4,2576,0,0},{1,31,-2759.8,0.6,107.6,98.9,36.8,0,8747,0,0},{0,29,-2776.6,-52.2,107.6,11.8,37.5,4,2023,0,0},{1,23,-1848.3,1994.7,155.8,14.7,34.2,0,3684,0,0},
		{1,26,-1918.5,1956.9,148.3,41.1,28.0,0,5237,0,0},{0,29,-1959.8,1930.0,146.0,57.5,15.3,3,220,0,0},{1,19,-2005.3,1899.3,146.0,52.3,28.2,0,6262,0,0},{1,20,-2060.5,1862.0,146.0,64.1,41.3,0,2025,0,0},{0,29,-2077.6,1788.5,11.3,39.6,18.9,3,1263,0,0},{1,26,-2038.0,1780.6,11.3,41.1,28.0,0,6971,0,0},{1,27,-2008.3,1774.7,11.3,19.4,36.9,0,8869,0,0},{0,29,-1969.9,1767.0,11.3,59.0,36.7,2,4570,0,0},
		{0,29,-1919.0,1756.8,11.3,44.8,34.7,2,5389,0,0},{0,29,-1880.2,1749.1,11.3,34.3,31.0,2,3457,0,0},{1,9,-1844.6,1798.9,-70.5,28.8,32.0,0,7007,0,0},{1,19,-1827.0,1848.9,-70.5,52.3,28.2,0,329,0,0},{1,20,-1807.1,1912.0,-74.7,64.0,41.3,0,9449,0,0},{0,10,-1793.6,1965.2,-77.4,28.5,31.3,5,4202,0,0},{0,17,-1074.5,1051.1,-166.9,34.0,34,3,626,0,-1},{0,2,-1490.1,1099.6,95.3,34.0,34,4,6652,0,-1},
		{0,17,-1489.8,919.2,10.9,34.0,34,3,8925,0,-1},{0,33,-1094.0,862.3,-79.0,47.6,30.3,3,5055,0,0},{0,33,-1086.6,900.2,-79.0,29.8,30.3,2,7,0,0},{1,32,-1074.3,963.3,-79.0,98.8,28.0,0,4127,0,0},{1,31,-1139.2,1066.2,-166.9,98.9,36.8,0,8312,0,0},{0,33,-1214.1,1083.7,-166.9,54.8,28.9,2,240,0,0},{0,33,-1264.3,1094.2,-169.6,48.0,10.2,3,6721,0,0},{0,33,-1341.7,1103.4,-174.9,32.9,30.0,3,6916,0,0},
		{0,33,-1374.5,1106.3,-174.9,33.0,31.8,2,7836,0,0},{0,33,-1407.5,1109.3,-174.9,33.4,29.7,2,3592,0,0},{0,33,-1439.4,1112.2,-174.9,30.6,31.5,3,8262,0,0},{1,31,-1496.2,1033.5,95.3,98.9,36.8,0,5077,0,0},{0,33,-1502.1,970.2,95.3,28.1,32.9,2,7124,0,0},{0,29,-1448.2,911.2,10.9,50.6,36.1,4,4656,0,0},{0,33,-1407.0,903.3,10.9,33.2,31.2,3,1619,0,0},{0,29,-1369.1,896.0,10.9,44.0,36.1,3,6623,0,0},
		{0,33,-1329.7,888.5,10.9,36.2,29.4,3,4261,0,0},{0,33,-1280.5,878.5,11.7,64.2,28.3,2,4842,0,0},{0,10,-1231.3,868.1,12.4,36.4,30.6,4,8003,0,0},{0,29,-1179.6,856.8,12.4,69.4,31.5,4,1857,0,0},{0,13,-1611.7,-920.9,4.1,30.8,44,7,8284,0,-1},{0,29,-1455.4,-904.5,-77.7,44.0,44,4,8255,0,-1},{1,24,-1429.1,-458.4,124.4,14.7,34.2,0,7054,0,0},{0,29,-1451.3,-490.8,124.4,63.9,34.7,4,8503,0,0},
		{1,22,-1473.5,-523.3,124.4,14.7,34.2,0,1241,0,0},{0,10,-1487.1,-543.2,124.4,33.6,33.0,4,383,0,0},{0,29,-1505.7,-570.5,124.4,32.4,33.5,4,8741,0,0},{0,29,-1529.1,-604.7,124.4,50.5,37.1,3,1992,0,0},{0,10,-1554.7,-643.0,122.9,41.7,18.9,4,4405,0,0},{0,13,-1575.7,-680.6,108.4,13.8,47.8,5,924,0,0},{0,29,-1591.6,-740.1,103.2,51.2,36.4,2,8127,0,0},{0,10,-1602.6,-787.2,103.2,45.5,31.7,5,8564,0,0},
		{0,29,-1611.9,-826.9,103.2,36.2,36.0,3,5764,0,0},{1,26,-1528.1,-926.5,3.0,41.1,28.0,0,3705,0,0},{0,29,-1445.0,-856.4,-77.7,54.5,36.5,4,9992,0,0},{0,10,-1434.2,-806.8,-77.7,47.0,32.2,4,531,0,0},{0,13,-1424.5,-762.5,-77.7,43.7,44.3,7,9035,0,0},{0,29,-1400.8,-682.5,-64.2,20.5,35.8,4,4792,0,0},{0,13,-1357.0,-614.7,-54.7,30.9,43.6,5,3148,0,0},{0,29,-1336.1,-585.1,-54.7,41.5,30.3,4,108,0,0},
		{0,10,-1307.2,-544.4,-54.7,58.4,39.7,4,8759,0,0},{0,13,-1426.0,-627.5,113.4,48,42,5,6341,1,0},{0,13,-1545.7,-793.6,113.4,48,42,7,107,1,0},{0,10,-1169.8,-885.2,-69.8,44.0,44,4,1812,0,-1},{0,29,-1217.2,-541.7,125.3,44.0,44,2,7743,0,-1},{0,29,-1302.0,-914.7,-4.1,51.0,34.0,4,7121,0,0},{0,29,-1258.6,-911.6,-4.1,36.1,34.8,2,481,0,0},{0,29,-1230.9,-909.7,-4.1,19.3,33.9,2,4486,0,0},
		{0,29,-1156.0,-847.6,-69.8,36.1,35.4,3,7606,0,0},{1,26,-1142.6,-811.4,-69.8,41.1,28.0,0,8610,0,0},{1,28,-1073.1,-674.2,-57.0,41.2,28.1,0,6208,0,0},{1,24,-1057.9,-650.8,-57.0,14.7,34.2,0,4829,0,0},{0,29,-1044.4,-630.0,-57.0,34.9,34.8,2,1892,0,0},{1,25,-1030.9,-609.2,-57.0,14.7,34.2,0,6383,0,0},{0,13,-1090.4,-559.3,-162.7,65.0,39.7,5,1652,0,0},{1,28,-1141.1,-543.5,-162.7,41.2,28.1,0,2620,0,0},
		{1,22,-1234.1,-565.7,125.3,14.7,34.2,0,88,0,0},{1,26,-1250.2,-588.5,125.3,41.1,28.0,0,7337,0,0},{0,10,-1275.2,-623.7,125.3,45.2,31.3,5,7009,0,0},{1,28,-1300.1,-658.9,125.3,41.2,28.1,0,4148,0,0},{0,29,-1321.9,-691.1,122.7,36.5,11.6,2,1819,0,0},{1,28,-1344.1,-738.2,106.3,41.2,28.1,0,4754,0,0},{1,28,-1368.0,-841.4,102.3,41.2,28.1,0,6727,0,0},{0,13,-1179.1,-612.4,116.9,48,42,5,8342,1,0},
		{0,13,-1162.5,-676.9,116.9,48,42,7,2993,1,0},{0,13,-1201.7,-657.0,116.9,48,42,6,7692,1,0},{0,13,-1185.1,-721.5,116.9,48,42,7,7499,1,0},{0,13,-1224.3,-701.6,116.9,48,42,5,9902,1,0},{0,13,-1246.9,-746.2,116.9,48,42,6,2910,1,0},{0,13,-1286.2,-726.3,116.9,48,42,6,5128,1,0},{0,13,-1269.5,-790.8,116.9,48,42,5,8833,1,0},{0,10,-1309.8,-1473.5,-1.5,30.8,44,4,6336,0,-1},
		{0,13,-1146.5,-1447.2,-94.2,37.4,44,6,331,0,-1},{1,27,-1196.0,-999.4,175.9,19.4,36.9,0,3174,0,0},{1,23,-1213.0,-1000.6,175.9,14.7,34.2,0,7691,0,0},{0,29,-1255.2,-1003.6,175.9,69.8,36.7,2,1960,0,0},{0,29,-1315.7,-1008.0,175.9,51.5,36.3,3,1,0,0},{1,22,-1348.7,-1010.3,175.9,14.7,34.2,0,5590,0,0},{0,29,-1366.1,-1061.3,72.3,41.2,13.4,3,5742,0,0},{0,13,-1355.2,-1095.6,72.3,30.8,40.8,7,5480,0,0},
		{0,10,-1345.8,-1125.1,72.3,31.1,39.6,3,9437,0,0},{0,29,-1331.7,-1169.5,72.3,62.1,35.4,3,4784,0,0},{0,10,-1318.6,-1215.0,77.3,32.6,39.0,4,4863,0,0},{1,22,-1314.2,-1238.2,83.7,14.7,34.2,0,9654,0,0},{1,28,-1315.5,-1301.1,95.4,41.2,28.1,0,5496,0,0},{0,10,-1318.8,-1336.2,95.4,29.2,32.7,4,1149,0,0},{0,13,-1321.6,-1365.6,95.4,29.9,45.8,6,5374,0,0},{1,27,-1323.9,-1390.1,95.4,19.4,36.9,0,8828,0,0},
		{0,29,-1215.2,-1471.0,-1.5,52.6,10.8,4,5083,0,0},{0,13,-1153.9,-1347.0,-94.2,63.0,45.6,5,2711,0,0},{0,10,-1157.8,-1294.6,-94.2,42.0,39.6,4,9275,0,0},{0,29,-1160.8,-1256.9,-95.0,33.5,35.6,2,6609,0,0},{0,29,-1163.6,-1226.8,-95.7,27.0,35.4,3,4665,0,0},{1,22,-1165.7,-1206.1,-95.7,14.7,34.2,0,2792,0,0},{0,10,-1167.8,-1184.9,-95.7,27.8,35.5,3,9966,0,0},{0,13,-1171.0,-1153.0,-95.7,36.4,40.7,5,1270,0,0},
		{1,28,-1174.8,-1114.4,-95.7,41.2,28.1,0,2412,0,0},{0,13,-1178.2,-1080.3,-95.7,27.4,42.8,7,4230,0,0},{0,13,-1274.0,-1438.3,84.3,48,42,5,5469,1,0},{0,30,-1390.0,-196.0,112.3,50.0,50,7,8052,0,-1},{0,13,-1250.0,-371.0,-89.1,34.0,52.1,7,5585,0,0},{0,10,-1248.7,-331.1,-87.6,45.7,38.7,4,7061,0,0},{0,10,-1244.5,-292.1,-78.5,33.1,37.6,5,1951,0,0},{0,30,-1238.3,-267.2,-71.9,18.3,67.3,6,1991,0,0},
		{0,13,-1230.0,-246.6,-65.2,26.3,51.1,7,7843,0,0},{0,10,-1259.4,-168.0,177.7,64.6,31.9,4,9253,0,0},{0,10,-1311.1,-170.1,177.7,39.0,31.8,5,9630,0,0},{0,10,-1405.2,-234.9,109.9,33.4,14.9,4,4071,0,0},{0,30,-1414.3,-282.8,89.2,11.6,62.9,8,3181,0,0},{0,30,-1405.7,-348.9,80.1,45.7,55.0,8,9867,0,0},{0,13,-1351.6,-391.8,17.4,33.6,23.8,6,2444,0,0},{0,30,-1319.4,-401.9,17.4,33.9,17.5,7,2904,0,0},
		{0,30,-1541.7,-182.6,176.6,53.1,68.7,6,4244,0,0},{0,30,-1589.1,-185.4,176.6,41.9,47.4,8,2353,0,0},{0,10,-1640.0,-188.5,176.6,60.0,28.6,5,5196,0,0},{0,13,-1551.7,-284.8,30.0,40.1,22.3,7,8354,0,0},{0,10,-1520.6,-302.8,30.0,31.5,30.3,5,4516,0,0},{0,10,-1484.4,-253.4,-82.1,16.9,26.1,3,8647,0,0},{0,10,-1480.9,-235.0,-76.5,20.7,25.8,3,9668,0,0},{0,17,-951.8,2109.8,-12.6,28.9,34,3,716,0,-1},
		{0,2,-341.5,2313.0,-162.6,34.0,34,4,5976,0,-1},{0,17,-406.0,2346.1,175.8,34.0,34,3,3441,0,-1},{1,31,-989.7,2217.8,79.2,98.9,36.8,0,9420,0,0},{0,33,-977.6,2154.4,79.2,30.2,17.5,2,7105,0,0},{1,32,-837.8,2135.3,-12.6,98.8,28.0,0,6369,0,0},{1,18,-764.1,2151.7,-12.6,52.3,28.2,0,8029,0,0},{0,33,-715.5,2162.6,-12.6,33.3,29.0,2,8940,0,0},{0,33,-679.1,2170.7,-12.6,41.4,32.1,2,2164,0,0},
		{1,31,-536.2,2182.1,0.1,98.9,36.8,0,6373,0,0},{1,32,-437.3,2182.0,0.1,98.8,28.0,0,1855,0,0},{0,33,-371.5,2182.0,0.1,32.9,29.3,3,4727,0,0},{1,23,-315.2,2255.5,-100.9,14.7,34.2,0,2175,0,0},{0,29,-317.7,2268.6,-100.9,12.0,36.5,4,1204,0,0},{0,29,-366.4,2326.8,-144.6,23.2,18.8,4,4861,0,0},{1,32,-472.2,2341.3,175.8,98.8,28.0,0,8639,0,0},{1,24,-528.8,2337.2,175.8,14.7,34.2,0,5791,0,0},
		{0,29,-568.3,2334.3,175.8,64.4,37.9,3,3193,0,0},{0,33,-618.9,2330.6,175.8,36.9,31.7,3,8023,0,0},{1,32,-686.5,2325.7,175.8,98.8,28.0,0,8699,0,0},{0,29,-768.8,2319.3,175.1,66.2,32.4,3,5007,0,0},{0,33,-883.2,2300.6,165.2,30.7,32.0,3,9391,0,0},{0,33,-918.2,2290.6,163.3,42.0,18.2,3,3420,0,0},{0,17,-933.4,1247.2,22.9,34.0,34,3,5074,0,-1},{0,17,-470.2,1168.1,-82.8,34.0,34,3,539,0,-1},
		{0,17,-468.4,1376.7,-174.8,34.0,34,3,2548,0,-1},{1,31,-930.8,1367.6,99.1,98.9,36.8,0,5745,0,0},{0,33,-941.2,1303.1,99.1,31.7,32.0,3,5199,0,0},{1,31,-872.2,1221.3,22.9,98.9,36.8,0,7969,0,0},{1,18,-802.6,1191.9,22.9,52.3,28.2,0,2557,0,0},{0,33,-748.1,1169.7,21.0,45.7,29.5,2,8034,0,0},{1,12,-694.5,1156.2,5.4,35.3,29.0,0,3208,0,0},{0,33,-638.2,1152.9,2.4,65.6,28.7,2,8337,0,0},
		{1,31,-556.0,1149.4,2.4,98.9,36.8,0,6311,0,0},{0,33,-465.0,1209.1,-82.8,48.7,33.3,3,6347,0,0},{0,33,-460.0,1248.5,-82.8,30.6,31.4,3,1904,0,0},{0,33,-454.8,1318.5,-86.6,45.6,30.1,3,3645,0,0},{0,33,-502.0,1379.8,-174.8,33.4,29.4,3,6197,0,0},{0,33,-531.6,1382.5,-174.8,26.1,32.2,3,9463,0,0},{0,29,-575.6,1386.5,-174.8,62.3,31.9,3,4501,0,0},{1,32,-655.8,1393.8,-174.8,98.8,28.0,0,2111,0,0},
		{0,10,-723.4,1399.8,-175.2,37.0,36.0,5,2900,0,0},{0,10,-755.1,1402.4,-175.2,26.6,34.7,4,2449,0,0},{0,29,-788.6,1405.2,-175.2,40.6,34.6,2,7704,0,0},{0,29,-825.1,1408.2,-175.2,32.8,32.1,4,5164,0,0},{0,29,-864.0,1411.5,-175.2,45.3,33.6,4,5160,0,0},{0,2,-989.3,1543.2,-92.1,23.8,34,3,505,0,-1},{0,17,-1084.6,2240.7,163.3,23.8,34,3,604,0,-1},{0,2,-1347.3,2148.1,112.2,34.0,34,4,1370,0,-1},
		{0,17,-1376.4,2091.6,74.1,34.0,34,3,6954,0,-1},{1,31,-1216.3,1545.2,4.8,98.9,36.8,0,6038,0,0},{1,24,-1159.7,1540.5,4.8,14.7,34.2,0,4671,0,0},{1,28,-1131.9,1538.2,4.8,41.2,28.1,0,6513,0,0},{1,27,-1101.7,1535.7,4.8,19.4,36.9,0,8647,0,0},{0,29,-1068.9,1532.9,4.8,46.4,34.6,3,7147,0,0},{1,22,-1038.5,1530.4,4.8,14.7,34.2,0,1887,0,0},{1,32,-993.6,1663.7,-92.1,98.8,28.0,0,8651,0,0},
		{0,33,-996.5,1744.3,-92.1,62.6,29.3,2,8981,0,0},{1,32,-999.4,1825.0,-92.1,98.8,28.0,0,7134,0,0},{1,32,-1018.9,1984.9,-100.8,98.8,28.0,0,4092,0,0},{0,33,-1031.1,2049.5,-100.8,32.8,30.1,2,2758,0,0},{0,33,-1038.1,2086.4,-100.8,42.3,29.0,3,8965,0,0},{0,33,-1044.9,2121.9,-100.8,29.9,28.3,3,2486,0,0},{0,33,-1052.8,2163.5,-100.8,54.8,29.6,2,28,0,0},{1,32,-1178.3,2212.6,163.3,98.8,28.0,0,3840,0,0},
		{0,10,-1246.9,2192.0,163.3,44.4,39.5,4,6716,0,0},{0,33,-1288.2,2179.6,163.3,41.9,30.5,2,973,0,0},{1,23,-1369.7,2068.2,74.1,14.7,34.2,0,7104,0,0},{0,10,-1359.0,2030.8,74.1,63.2,39.8,3,2381,0,0},{1,32,-1336.8,1952.9,74.1,98.8,28.0,0,7492,0,0},{0,10,-1316.7,1880.2,75.6,51.9,35.3,3,2995,0,0},{0,33,-1307.2,1837.2,80.3,36.3,28.7,2,7147,0,0},{0,10,-1301.8,1802.6,81.9,33.9,39.6,5,543,0,0},
		{0,29,-1295.3,1757.1,81.9,58.0,30.0,4,676,0,0},{0,29,-1287.3,1701.2,81.9,55.1,32.2,4,1073,0,0},{0,29,-1281.4,1659.8,81.9,28.5,31.5,3,4703,0,0},{0,10,-1422.2,1843.3,104.1,57.9,16.3,4,7916,0,0},{1,5,-1448.8,1764.8,113.0,32.6,30.8,0,462,0,0},{1,19,-1468.7,1717.9,113.0,52.3,28.2,0,6846,0,0},{1,12,-1489.6,1668.3,113.0,35.3,29.0,0,3641,0,0},{0,10,-1502.6,1637.8,113.0,18.1,14.0,5,7098,0,0},
		{1,12,-1442.1,1606.4,19.8,35.3,29.0,0,4744,0,0},{1,19,-1391.7,1588.3,19.8,52.3,28.2,0,1243,0,0},{1,25,-1364.9,1662.3,-98.3,14.7,34.2,0,3014,0,0},{1,24,-1367.0,1676.9,-98.3,14.7,34.2,0,5955,0,0},{0,29,-1370.9,1703.7,-98.3,39.6,34.3,2,1330,0,0},{1,18,-1377.6,1749.2,-98.3,52.3,28.2,0,6767,0,0},{0,29,-1386.7,1811.9,-98.3,57.8,13.4,4,9891,0,0},{0,30,-702.6,-71.6,4.6,50.0,50,6,403,0,-1},
		{0,13,-589.6,-55.6,-83.8,50.0,50,5,4835,0,-1},{0,10,-574.4,251.6,-173.4,42.5,50,4,2265,0,-1},{0,10,-759.0,247.9,90.0,35.0,50,4,4093,0,-1},{0,13,-750.2,-44.6,37.3,22.2,27.6,6,482,0,0},{0,29,-659.9,-75.1,4.6,35.6,31.6,4,5152,0,0},{0,30,-583.2,3.6,-83.8,69.2,68.8,7,7992,0,0},{0,10,-577.1,59.0,-83.8,42.1,39.1,5,655,0,0},{0,30,-572.0,99.1,-81.7,38.8,45.7,7,1553,0,0},
		{0,10,-567.2,131.6,-81.4,26.8,30.1,3,4821,0,0},{0,30,-759.0,183.1,90.0,43.1,49.0,5,8154,0,0},{0,10,-759.0,135.5,90.0,52.1,37.3,5,7491,0,0},{0,30,-759.0,82.7,90.0,53.5,56.5,7,5090,0,0},{0,30,-759.0,20.9,90.0,69.9,50.0,7,7459,0,0},{0,13,-626.7,232.5,-83.4,48,42,6,6976,1,0},{0,13,-632.5,182.8,-83.4,48,42,7,7849,1,0},{0,13,-638.2,133.2,-83.4,48,42,6,3126,1,0},
		{0,17,-323.2,-84.9,-85.7,34.0,34,3,7343,0,-1},{0,2,-300.1,220.0,-173.4,28.9,34,3,3588,0,-1},{0,2,-480.5,223.7,98.6,34.0,34,4,2356,0,-1},{0,29,-490.7,-88.6,4.6,60.0,24.7,3,1974,0,0},{0,29,-435.3,-93.0,4.6,51.0,30.6,2,8504,0,0},{0,29,-384.1,-97.1,4.6,51.7,37.0,4,43,0,0},{1,32,-318.2,-18.7,-85.7,98.8,28.0,0,714,0,0},{0,33,-313.4,44.7,-85.7,28.5,30.0,2,5016,0,0},
		{1,32,-303.5,107.5,-79.7,98.8,28.0,0,8832,0,0},{0,29,-385.5,229.8,-173.4,40.6,30.3,3,2461,0,0},{0,29,-424.9,234.4,-173.4,38.7,33.7,3,7481,0,0},{1,19,-487.0,181.0,98.6,52.3,28.2,0,596,0,0},{1,31,-498.7,99.8,98.0,98.9,36.8,0,2043,0,0},{0,33,-508.9,20.9,96.2,60.3,16.0,3,1014,0,0},{0,33,-514.2,-28.0,96.2,38.1,32.9,3,39,0,0},{0,13,-413.7,-569.6,94.0,44.0,44,6,8089,0,-1},
		{0,13,-349.9,-898.7,-2.8,44.0,44,5,7508,0,-1},{0,10,-225.0,-870.8,-100.8,30.8,44,3,4774,0,-1},{0,29,-313.3,-534.9,172.6,59.8,37.3,3,8973,0,0},{0,13,-355.8,-540.4,172.6,25.8,47.5,5,7269,0,0},{0,10,-416.8,-613.8,94.0,44.6,36.6,5,9581,0,0},{0,13,-419.8,-656.2,94.0,40.5,44.8,6,4820,0,0},{0,10,-421.8,-700.4,91.4,48.0,11.9,4,9997,0,0},{0,10,-417.0,-750.8,76.1,30.1,34.7,5,386,0,0},
		{0,13,-388.8,-844.9,72.9,26.9,52.1,5,535,0,0},{0,13,-308.3,-896.7,-2.8,39.5,51.6,6,6129,0,0},{0,10,-238.5,-800.5,-100.8,31.0,37.7,3,6369,0,0},{0,13,-246.1,-759.9,-100.6,51.7,43.3,7,8472,0,0},{0,29,-252.6,-719.6,-96.4,30.0,35.6,2,7382,0,0},{0,10,-253.5,-689.5,-87.4,30.4,31.6,3,5186,0,0},{0,29,-251.9,-653.0,-87.3,42.7,35.3,2,5567,0,0},{0,10,-249.7,-607.4,-87.3,48.5,32.8,5,8508,0,0},
		{0,10,-535.3,-1491.9,3.6,44.0,44,3,1540,0,-1},{0,13,22.8,-1483.8,-103.1,30.8,44,5,6337,0,-1},{0,13,-525.6,-1018.1,95.7,58.1,45.3,7,7652,0,0},{0,10,-529.9,-1060.8,95.7,27.7,38.5,3,2099,0,0},{0,29,-533.7,-1098.6,95.7,48.3,33.5,3,9570,0,0},{0,10,-538.8,-1149.8,95.7,54.7,32.6,4,8470,0,0},{0,10,-544.4,-1205.6,95.7,57.4,31.5,5,9493,0,0},{0,13,-550.4,-1307.7,92.2,45.3,53.5,7,5363,0,0},
		{0,10,-552.0,-1350.1,92.2,39.7,31.5,5,1163,0,0},{0,13,-554.2,-1408.3,92.2,76.7,55.2,7,4113,0,0},{0,10,-478.8,-1495.5,3.6,69.2,30.1,4,8208,0,0},{0,13,-429.6,-1498.5,3.6,29.3,51.8,7,9257,0,0},{0,13,-388.5,-1501.1,3.6,53.0,47.1,5,9779,0,0},{0,10,-340.1,-1504.1,3.6,44.1,38.7,5,1519,0,0},{0,10,-291.0,-1507.2,3.6,54.2,32.4,3,8978,0,0},{0,10,-240.4,-1510.4,3.6,47.3,33.4,4,140,0,0},
		{0,13,-190.3,-1513.4,3.4,53.1,48.8,6,2340,0,0},{0,29,-138.6,-1515.3,0.9,50.5,11.1,4,8237,0,0},{0,13,7.2,-1416.8,-103.1,31.9,44.6,6,4870,0,0},{0,13,-1.4,-1379.7,-103.1,44.3,41.5,5,7825,0,0},{0,29,-13.3,-1328.6,-103.1,60.8,35.7,4,9707,0,0},{0,10,-24.3,-1278.8,-101.5,41.0,37.3,4,5144,0,0},{0,10,-29.3,-1246.9,-94.7,23.7,37.3,3,4960,0,0},{0,10,-30.0,-1226.6,-88.4,17.0,30.5,4,9523,0,0},
		{0,10,-16.9,-1132.8,-80.4,51.7,33.0,5,7416,0,0},{0,10,-8.9,-1085.2,-80.4,44.8,31.0,4,4891,0,0},{0,13,0.1,-1032.0,-80.4,63.0,48.3,6,3927,0,0},{0,10,-39.4,-962.6,175.9,27.9,28.8,5,9570,0,0},{0,29,-75.9,-965.2,175.9,45.3,36.8,3,3480,0,0},{0,10,-124.4,-968.7,175.9,52.0,39.0,4,1948,0,0},{0,10,-169.8,-971.7,176.4,38.9,36.1,5,4959,0,0},{0,10,-219.3,-974.4,177.2,60.3,38.9,5,7908,0,0},
		{0,10,-283.9,-977.6,177.2,68.9,36.2,3,2293,0,0},{0,13,-333.5,-980.0,177.2,30.4,50.6,6,6139,0,0},{0,10,-377.8,-982.2,177.2,58.4,35.6,5,4997,0,0},{0,13,-428.4,-984.6,177.2,42.9,46.2,7,2691,0,0},{0,13,-55.1,-1501.9,-1.6,48,42,7,1612,1,0},{0,13,-116.2,-1107.4,-1.6,48,42,7,8057,1,0},{0,13,-115.0,-1151.4,-1.6,48,42,5,265,1,0},{0,13,-113.7,-1195.4,-1.6,48,42,5,8740,1,0},
		{0,13,-112.5,-1239.4,-1.6,48,42,7,3075,1,0},{0,13,-110.0,-1327.3,-1.6,48,42,7,663,1,0},{0,13,-108.8,-1371.3,-1.6,48,42,5,9295,1,0},{0,13,-107.6,-1415.3,-1.6,48,42,7,7377,1,0},{0,13,-106.3,-1459.3,-1.6,48,42,5,1510,1,0},{0,13,-105.1,-1503.3,-1.6,48,42,7,7916,1,0},{0,13,-166.2,-1108.8,-1.6,48,42,5,5083,1,0},{0,13,-164.9,-1152.8,-1.6,48,42,5,5887,1,0},
		{0,13,-163.7,-1196.8,-1.6,48,42,7,9126,1,0},{0,13,-157.6,-1416.7,-1.6,48,42,6,1699,1,0},{0,13,-216.2,-1110.2,-1.6,48,42,7,2514,1,0},{0,13,-214.9,-1154.2,-1.6,48,42,7,4140,1,0},{0,13,-213.7,-1198.2,-1.6,48,42,7,3955,1,0},{0,13,-207.5,-1418.1,-1.6,48,42,6,7993,1,0},{0,13,-266.1,-1111.6,-1.6,48,42,7,4440,1,0},{0,13,-264.9,-1155.6,-1.6,48,42,7,9019,1,0},
		{0,13,-263.7,-1199.6,-1.6,48,42,5,3552,1,0},{0,13,-257.5,-1419.5,-1.6,48,42,6,8815,1,0},{0,13,-316.1,-1113.0,-1.6,48,42,5,8003,1,0},{0,13,-314.9,-1157.0,-1.6,48,42,7,1847,1,0},{0,13,-307.5,-1420.9,-1.6,48,42,6,9028,1,0},{0,13,-366.1,-1114.4,-1.6,48,42,5,759,1,0},{0,13,-364.9,-1158.4,-1.6,48,42,6,4025,1,0},{0,13,-363.6,-1202.4,-1.6,48,42,7,4886,1,0},
		{0,13,-357.5,-1422.3,-1.6,48,42,6,2293,1,0},{0,13,-416.1,-1115.8,-1.6,48,42,5,5662,1,0},{0,13,-414.8,-1159.8,-1.6,48,42,7,8370,1,0},{0,13,-413.6,-1203.8,-1.6,48,42,7,2408,1,0},{0,13,-412.4,-1247.8,-1.6,48,42,7,5743,1,0},{0,13,-411.2,-1291.7,-1.6,48,42,7,9115,1,0},{0,13,-409.9,-1335.7,-1.6,48,42,6,2896,1,0},{0,13,-408.7,-1379.7,-1.6,48,42,6,3133,1,0},
		{0,13,-407.5,-1423.7,-1.6,48,42,7,7571,1,0},{0,13,-462.4,-1249.2,-1.6,48,42,5,627,1,0},{0,17,162.6,-2118.2,-63.3,34.0,34,3,4816,0,-1},{0,2,252.7,-2049.2,-74.9,34.0,34,3,2021,0,-1},{0,17,297.8,-1616.7,-154.5,34.0,34,3,326,0,-1},{0,2,251.3,-1590.6,175.1,34.0,34,4,7362,0,-1},{0,33,-224.4,-1647.0,90.2,62.8,11.7,3,9787,0,0},{0,33,-224.5,-1709.4,90.2,62.1,31.7,2,1139,0,0},
		{1,32,-224.8,-1789.8,90.2,98.8,28.0,0,6797,0,0},{1,31,-224.9,-1888.7,90.0,98.9,36.8,0,9932,0,0},{1,31,-224.1,-1987.6,89.1,98.9,36.8,0,6751,0,0},{0,33,-222.8,-2071.1,89.1,68.3,28.9,2,9500,0,0},{0,33,-221.8,-2133.3,89.1,56.0,33.1,3,3856,0,0},{1,32,-128.2,-2189.1,-11.1,98.8,28.0,0,4667,0,0},{1,32,-31.3,-2170.0,-11.1,98.8,28.0,0,2156,0,0},{1,28,37.4,-2156.5,-11.1,41.2,28.1,0,670,0,0},
		{0,33,71.1,-2149.9,-11.1,27.4,28.0,3,3082,0,0},{0,29,103.0,-2143.6,-11.1,37.7,34.6,2,4627,0,0},{0,29,175.9,-2101.8,-48.7,8.3,37.9,2,6727,0,0},{1,24,196.1,-2084.7,-33.7,14.7,34.2,0,5151,0,0},{1,23,208.8,-2077.3,-26.4,14.7,34.2,0,6121,0,0},{1,31,270.0,-1985.1,-74.9,98.9,36.8,0,7627,0,0},{1,24,286.4,-1903.8,-78.3,14.7,34.2,0,9713,0,0},{1,25,289.4,-1889.4,-78.3,14.7,34.2,0,5082,0,0},
		{1,26,295.0,-1862.1,-78.3,41.1,28.0,0,1032,0,0},{1,25,300.7,-1834.8,-78.3,14.7,34.2,0,834,0,0},{1,25,303.7,-1820.4,-78.3,14.7,34.2,0,1341,0,0},{1,25,306.7,-1806.0,-78.3,14.7,34.2,0,322,0,0},{0,29,313.7,-1772.3,-78.3,54.2,35.8,2,6295,0,0},{0,29,320.6,-1739.2,-78.3,13.5,33.1,3,2380,0,0},{1,28,320.6,-1698.6,-95.7,41.2,28.1,0,1847,0,0},{0,29,317.6,-1668.0,-95.7,20.4,36.6,3,7878,0,0},
		{1,27,224.7,-1592.9,175.1,19.4,36.9,0,3630,0,0},{0,29,196.7,-1595.2,175.1,36.7,34.8,3,9361,0,0},{0,33,157.4,-1598.6,175.1,42.2,30.4,2,1838,0,0},{1,32,87.1,-1604.5,175.1,98.8,28.0,0,9494,0,0},{1,32,-11.3,-1612.9,175.1,98.8,28.0,0,5134,0,0},{0,29,-94.4,-1618.5,177.6,67.6,35.0,2,1508,0,0},{1,24,-135.5,-1619.7,-178.5,14.7,34.2,0,7232,0,0},{0,29,-163.4,-1618.8,-178.0,41.1,30.5,4,3966,0,0},
		{0,3,55.5,-1949.5,-60.3,40.9,29.1,17,2252,0,0},{0,3,40.6,-1772.4,-35.3,50.7,31.8,9,1486,0,0},{0,17,-313.2,-1610.0,-176.4,34.0,34,3,1217,0,-1},{0,2,-566.2,-1611.1,100.3,34.0,34,4,3639,0,-1},{1,31,-296.6,-1717.6,-89.8,98.9,36.8,0,3052,0,0},{0,33,-296.4,-1656.6,-89.8,23.1,32.5,2,7805,0,0},{1,27,-339.9,-1608.4,-176.4,19.4,36.9,0,9634,0,0},{0,33,-376.1,-1606.1,-176.4,53.2,30.9,2,5337,0,0},
		{0,33,-423.0,-1603.2,-176.4,40.8,29.5,2,9048,0,0},{1,28,-463.9,-1600.6,-176.4,41.2,28.1,0,4258,0,0},{0,33,-506.8,-1597.9,-176.4,44.8,29.3,3,6850,0,0},{1,22,-570.5,-1635.1,100.3,14.7,34.2,0,4970,0,0},{1,26,-575.5,-1662.5,100.3,41.1,28.0,0,6788,0,0},{1,28,-582.9,-1703.0,100.3,41.2,28.1,0,2749,0,0},{1,22,-587.9,-1730.5,100.3,14.7,34.2,0,5846,0,0},{1,23,-590.5,-1745.0,100.4,14.7,34.2,0,9939,0,0},
		{1,23,-593.5,-1759.4,102.8,14.7,34.2,0,3462,0,0},{0,33,-504.8,-1779.2,0.9,62.9,29.0,3,9048,0,0},{0,33,-408.0,-1792.8,16.9,58.3,29.9,3,5961,0,0},{0,33,-366.4,-1805.7,17.8,28.8,30.7,3,3538,0,0},{0,2,-313.3,-1898.5,-162.5,34.0,34,4,5721,0,-1},{0,17,-623.9,-1866.2,107.0,34.0,34,3,997,0,-1},{1,32,-293.2,-2172.0,-90.8,98.8,28.0,0,9614,0,0},{1,31,-294.6,-2073.2,-90.8,98.9,36.8,0,9130,0,0},
		{0,33,-295.7,-2001.2,-90.8,45.1,31.4,3,6196,0,0},{0,33,-296.3,-1958.1,-90.8,41.1,32.4,2,5368,0,0},{1,31,-376.7,-1878.4,-162.5,98.9,36.8,0,6619,0,0},{0,33,-437.8,-1859.1,-162.5,29.4,30.3,2,3737,0,0},{1,31,-512.7,-1851.9,-178.4,98.8,36.8,0,1629,0,0},{0,33,-573.5,-1850.4,-179.5,22.9,28.2,3,7939,0,0},{1,25,-631.0,-1889.5,107.0,14.7,34.2,0,3843,0,0},{0,29,-637.5,-1910.7,107.0,29.6,33.9,3,2967,0,0},
		{0,29,-650.3,-1952.6,107.0,58.0,35.5,3,1169,0,0},{1,31,-712.5,-2057.3,122.0,98.9,36.8,0,490,0,0},{0,33,-749.7,-2116.8,122.0,41.6,32.5,2,5649,0,0},{0,29,-771.1,-2149.3,125.0,36.3,35.1,3,3266,0,0},{0,10,-705.1,-2208.0,4.2,68.6,30.9,5,4912,0,0},{0,33,-644.7,-2212.4,4.2,52.6,32.2,2,4023,0,0},{0,29,-602.1,-2215.5,4.2,32.7,30.5,4,1471,0,0},{0,10,-553.7,-2219.0,4.2,64.5,32.0,3,8484,0,0},
		{0,29,-501.9,-2222.8,4.2,39.2,35.4,4,5994,0,0},{0,33,-464.6,-2225.5,4.2,35.6,31.3,3,485,0,0},{1,23,-439.5,-2227.3,4.2,14.7,34.2,0,5716,0,0},{1,28,-411.6,-2229.3,4.1,41.2,28.1,0,9082,0,0},{0,29,-585.2,-592.2,79.4,37.4,44,2,8620,0,-1},{0,13,-504.3,-906.2,-2.8,44.0,44,5,8685,0,-1},{0,29,-461.6,-853.2,-107.1,52.5,21.0,4,2941,0,0},{0,10,-474.3,-812.2,-107.1,33.2,34.6,4,8056,0,0},
		{0,13,-494.3,-727.4,-94.3,20.7,54.1,5,2054,0,0},{0,10,-494.2,-696.9,-87.6,40.3,37.1,4,2181,0,0},{0,13,-491.1,-643.8,-86.0,66.2,57.6,7,9822,0,0},{0,10,-567.1,-689.0,79.4,59.5,17.0,4,4769,0,0},{0,10,-541.7,-824.7,79.4,80.0,28.1,5,3607,0,0},{0,13,-347.7,-192.3,-175.4,44.0,44,6,6860,0,-1},{0,29,-587.6,-493.8,-7.4,35.7,33.1,4,6328,0,0},{0,13,-540.8,-487.7,-7.4,58.7,54.7,5,4760,0,0},
		{0,13,-494.1,-481.6,-7.4,35.5,58.7,5,4596,0,0},{0,10,-461.2,-477.4,-7.4,30.9,35.9,4,3553,0,0},{0,10,-430.4,-473.4,-7.4,31.2,39.4,3,1228,0,0},{0,10,-401.3,-469.6,-7.4,27.5,30.8,3,4143,0,0},{0,10,-361.6,-464.5,-7.4,52.5,32.6,5,9818,0,0},{0,13,-308.0,-457.5,-7.4,55.6,52.5,5,9502,0,0},{0,10,-315.6,-326.0,-102.3,20.2,34.1,5,6025,0,0},{0,10,-319.4,-302.1,-96.4,28.3,34.8,4,8706,0,0},
		{0,13,-322.2,-263.0,-92.9,50.1,51.5,5,5566,0,0},{0,29,-391.4,-188.8,-175.4,43.7,37.5,2,7406,0,0},{1,27,-422.8,-186.3,-175.4,19.4,36.9,0,9395,0,0},{1,23,-439.8,-185.0,-175.4,14.7,34.2,0,9439,0,0},{1,28,-467.7,-182.7,-175.4,41.2,28.1,0,9854,0,0},{1,22,-495.5,-180.5,-175.4,14.7,34.2,0,7495,0,0},{0,29,-523.7,-178.3,-175.4,41.8,37.6,3,875,0,0},{1,28,-565.0,-174.9,-175.4,41.2,28.1,0,6703,0,0},
		{1,27,-595.3,-172.5,-175.4,19.4,36.9,0,3932,0,0},{1,25,-612.2,-171.2,-175.4,14.7,34.2,0,7967,0,0},{0,29,-634.7,-169.4,-175.4,30.3,33.4,2,9319,0,0},{1,26,-670.2,-166.5,-175.4,41.1,28.0,0,7700,0,0},{0,13,-712.4,-221.7,68.7,50.3,28.4,6,3371,0,0},{0,10,-692.8,-272.0,68.7,57.7,31.6,4,655,0,0},{0,29,-671.3,-327.1,68.7,60.7,33.9,2,8952,0,0},{0,13,-648.8,-384.6,68.7,62.7,49.8,6,7271,0,0},
		{0,13,-629.7,-433.6,68.7,42.6,47.8,6,739,0,0},{0,13,-366.8,-367.4,172.6,48,42,6,1845,1,0},{0,13,-422.0,-330.2,172.6,48,42,7,7305,1,0},{0,13,-427.7,-286.5,172.6,48,42,6,4995,1,0},{0,13,-471.6,-336.6,172.6,48,42,5,5375,1,0},{0,13,-477.3,-293.0,172.6,48,42,5,2694,1,0},{0,13,-482.9,-249.3,172.6,48,42,6,9596,1,0},{0,13,-521.2,-343.0,172.6,48,42,5,3343,1,0},
		{0,13,-526.8,-299.4,172.6,48,42,6,6835,1,0},{0,13,-532.5,-255.8,172.6,48,42,7,7684,1,0},{0,13,-582.1,-262.2,172.6,48,42,5,2109,1,0},{0,16,-491.5,793.9,-72.4,46.0,46,26,7052,0,-1},{0,1,-522.3,944.7,132.6,60.8,54.4,9,2774,0,0},{0,1,-560.7,903.1,132.6,52.5,57.7,14,1034,0,0},{0,16,-602.1,858.1,132.6,69.9,53.7,21,1705,0,0},{0,29,-476.9,840.0,-72.4,50.6,32.8,4,6835,0,0},
		{0,29,-464.6,879.7,-73.4,32.5,22.3,2,9371,0,0},{0,17,-380.7,1351.7,93.2,28.9,34,3,4333,0,-1},{0,29,-331.0,1292.6,-45.0,37.6,37.3,3,9103,0,0},{0,29,-322.2,1363.4,-174.8,47.5,13.3,4,4827,0,0},{0,10,270.3,-1466.5,-60.1,44.0,44,3,3791,0,-1},{0,13,196.8,-945.1,175.7,44.0,44,7,766,0,-1},{0,13,82.8,-975.1,99.4,44.0,44,7,7612,0,-1},{0,13,128.3,-1496.7,-4.9,56.4,40.6,6,854,0,0},
		{0,10,171.5,-1493.0,-4.9,30.3,32.2,5,104,0,0},{0,13,201.0,-1490.5,-4.9,29.0,55.2,7,2470,0,0},{0,10,295.7,-1425.1,-98.6,36.5,17.9,5,8446,0,0},{0,13,290.6,-1391.8,-98.6,31.0,58.5,6,6433,0,0},{0,10,284.6,-1352.2,-98.6,49.1,34.4,3,4921,0,0},{0,13,276.3,-1297.2,-98.6,62.2,45.1,6,3853,0,0},{0,10,269.3,-1251.0,-98.6,31.3,31.9,4,476,0,0},{0,13,263.2,-1211.6,-98.9,48.4,55.0,7,2669,0,0},
		{0,13,254.2,-1156.2,-99.5,63.9,55.7,6,938,0,0},{0,13,243.4,-1091.6,-99.5,66.9,57.3,6,7813,0,0},{0,10,231.9,-1022.7,-99.5,72.7,37.5,5,9740,0,0},{0,10,152.6,-948.4,175.7,44.7,40.0,3,8568,0,0},{0,13,75.7,-1017.8,99.4,42.6,53.4,5,9395,0,0},{0,10,69.7,-1054.1,99.4,31.0,31.3,4,5545,0,0},{0,10,63.5,-1091.2,99.4,44.2,39.1,4,9396,0,0},{0,13,56.8,-1131.6,99.4,37.7,43.6,6,5381,0,0},
		{0,10,51.2,-1164.9,99.4,29.7,36.5,3,752,0,0},{0,10,45.4,-1200.0,99.4,41.4,33.2,5,4562,0,0},{0,29,43.9,-1248.7,84.0,28.0,35.4,2,3146,0,0},{0,13,63.0,-1339.0,76.9,63.5,57.0,5,4804,0,0},{0,29,77.8,-1402.4,76.9,66.6,32.5,4,8905,0,0},{0,13,116.8,-1248.1,81.4,48,42,5,8515,1,0},{0,13,139.2,-1396.4,81.4,48,42,7,5174,1,0},{0,10,-174.5,-542.6,92.8,44.0,44,5,1584,0,-1},
		{0,13,-126.3,-887.1,-4.3,44.0,44,7,7468,0,-1},{0,13,7.3,-855.2,-101.8,30.8,44,6,6749,0,-1},{0,13,-93.2,-519.9,179.5,72.5,46.0,7,2199,0,0},{0,10,-176.7,-585.8,92.8,42.6,37.1,4,3492,0,0},{0,13,-178.7,-627.2,92.8,40.4,49.1,6,3450,0,0},{0,13,-180.8,-669.4,92.8,44.1,49.6,5,4145,0,0},{0,10,-177.6,-733.6,80.2,35.5,35.6,3,2510,0,0},{0,10,-171.2,-769.2,79.2,36.9,30.6,3,7853,0,0},
		{0,13,-163.9,-807.0,79.2,40.2,40.2,6,390,0,0},{0,10,-158.3,-836.1,79.2,19.1,31.5,5,8541,0,0},{0,13,-84.8,-884.0,-4.3,39.2,54.1,6,699,0,0},{0,13,-12.8,-758.8,-101.7,57.7,45.9,7,8056,0,0},{0,13,-21.6,-678.1,-87.5,36.7,45.8,5,7047,0,0},{0,10,-18.8,-639.1,-84.4,41.7,37.9,4,4111,0,0},{0,13,-14.1,-591.1,-84.4,54.6,41.4,6,3486,0,0},{0,10,204.8,-840.2,-93.9,44.0,44,5,5140,0,-1},
		{0,13,160.7,-518.1,179.6,44.0,44,7,1690,0,-1},{0,10,63.3,-540.6,95.6,44.0,44,3,8717,0,-1},{0,10,123.3,-868.4,-4.3,78.5,36.5,3,8989,0,0},{0,10,201.7,-794.2,-93.9,48.3,35.4,3,8978,0,0},{0,13,197.7,-736.1,-93.9,68.0,50.7,6,4546,0,0},{0,13,193.8,-678.8,-93.9,46.9,45.0,6,7720,0,0},{0,13,190.0,-624.1,-93.9,62.7,59.6,6,8338,0,0},{0,10,186.8,-577.4,-93.9,31.1,37.9,3,3141,0,0},
		{0,13,124.1,-518.3,179.6,29.3,45.9,5,2280,0,0},{0,10,59.4,-579.4,95.6,33.9,35.0,4,8328,0,0},{0,13,54.6,-628.7,95.6,65.2,59.8,5,1911,0,0},{0,10,51.5,-711.4,78.6,14.1,32.6,4,9354,0,0},{0,10,57.4,-740.3,78.4,44.8,37.6,4,3922,0,0},{0,13,67.0,-787.0,78.4,50.5,54.7,6,3271,0,0},{0,2,920.4,2156.0,145.7,34.0,34,4,8667,0,-1},{0,17,585.9,1912.8,100.5,34.0,34,3,2752,0,-1},
		{0,2,647.9,1565.0,-7.6,34.0,34,3,3351,0,-1},{0,17,1491.7,1680.5,-39.5,34.0,34,3,5015,0,-1},{0,10,1095.4,2197.1,124.7,20.0,33.0,3,1100,0,0},{0,29,1085.0,2183.4,130.9,14.5,31.0,4,3577,0,0},{0,29,982.8,2146.9,-170.6,19.7,37.9,2,418,0,0},{0,29,969.0,2149.7,-163.2,8.4,33.3,2,8895,0,0},{0,33,877.9,2126.9,145.7,69.1,28.7,3,3190,0,0},{0,29,826.7,2091.9,145.7,54.7,34.0,2,3484,0,0},
		{1,32,763.4,2048.6,145.7,98.8,28.0,0,8414,0,0},{0,29,694.1,2001.3,145.7,69.0,32.8,2,8727,0,0},{0,33,654.2,1974.1,145.7,27.6,31.7,2,3531,0,0},{0,33,630.0,1957.5,145.7,31.2,28.5,3,2350,0,0},{1,31,573.8,1847.4,100.5,98.9,36.8,0,2666,0,0},{0,33,562.3,1784.2,100.0,29.7,33.7,3,6865,0,0},{0,33,559.2,1732.3,84.4,13.7,30.8,3,7567,0,0},{0,33,567.0,1699.6,71.0,12.6,28.6,3,6026,0,0},
		{0,33,605.1,1617.5,64.7,53.2,28.9,2,5708,0,0},{0,29,690.7,1570.7,-7.6,52.3,35.9,3,8407,0,0},{1,25,723.9,1575.2,-7.6,14.7,34.2,0,4419,0,0},{0,29,739.0,1577.2,-7.6,15.8,37.3,4,5167,0,0},{1,28,1006.8,1610.8,-7.1,41.2,28.1,0,1251,0,0},{0,33,1048.1,1615.9,-7.1,42.1,29.8,2,244,0,0},{1,32,1118.0,1624.7,-7.1,98.8,28.0,0,3811,0,0},{0,10,1187.2,1633.3,-7.1,40.6,38.3,4,989,0,0},
		{1,32,1256.3,1641.9,-7.1,98.8,28.0,0,6478,0,0},{1,23,1312.6,1649.0,-7.1,14.7,34.2,0,3372,0,0},{1,32,1369.0,1656.0,-7.1,98.8,28.0,0,2314,0,0},{0,29,1431.4,1663.8,-7.1,27.1,34.7,3,9507,0,0},{0,29,1523.6,1706.8,-39.5,48.7,37.2,4,2669,0,0},{1,31,1580.5,1753.8,-39.5,98.9,36.8,0,7408,0,0},{1,28,1634.5,1798.4,-39.5,41.2,28.1,0,1740,0,0},{1,22,1656.1,1816.2,-39.5,14.7,34.2,0,9683,0,0},
		{1,23,1959.6,2143.4,-58.0,14.7,34.2,0,4716,0,0},{1,31,1989.7,2191.6,-58.0,98.9,36.8,0,6292,0,0},{0,33,1953.5,2276.8,177.9,63.6,23.1,2,404,0,0},{1,32,1872.3,2273.9,177.9,98.8,28.0,0,9062,0,0},{0,29,1798.4,2271.2,177.9,49.3,11.2,4,5866,0,0},{0,33,1700.7,2267.6,177.9,33.2,32.5,2,1563,0,0},{0,10,1662.7,2266.2,177.9,43.0,37.2,5,2377,0,0},{0,29,1621.4,2264.2,176.4,39.7,22.9,3,3208,0,0},
		{0,29,1567.3,2259.4,174.0,69.0,11.2,4,8972,0,0},{1,31,1483.9,2250.0,173.3,98.9,36.8,0,2086,0,0},{0,29,1417.2,2242.2,173.3,35.3,36.0,4,4406,0,0},{0,10,1379.4,2237.8,173.3,41.0,32.4,3,7874,0,0},{1,31,1309.9,2229.7,173.3,98.9,36.8,0,6682,0,0},{0,29,1239.4,2221.5,173.3,43.0,35.2,3,8687,0,0},{0,33,1183.8,2215.0,173.3,69.0,29.7,2,5495,0,0},{0,3,1020.1,2018.3,-58.3,51.8,33.5,14,4132,0,0},
		{0,3,1345.1,2035.6,122.0,37.9,31.8,14,7106,0,0},{0,3,27.9,1313.5,41.2,51.1,36.4,12,1627,0,0},{0,3,117.7,1234.9,41.2,51.8,30.7,15,5004,0,0},{0,3,220.6,1144.8,41.2,95.0,36.9,15,7363,0,0},{0,3,317.7,1089.6,-11.4,59.7,39.8,12,9348,0,0},{0,3,412.9,1108.8,-11.4,48.4,34.6,11,3398,0,0},{0,1,501.1,1126.5,-11.4,46.6,59.6,6,3622,0,0},{0,33,585.9,1143.6,-11.4,29.0,29.3,3,9490,0,0},
		{0,3,634.0,1153.2,-11.4,69.2,37.3,16,5700,0,0},{0,3,750.7,1176.7,-11.4,57.8,31.4,14,2932,0,0},{0,3,848.4,1196.3,-11.4,58.0,32.8,9,7348,0,0},{0,1,983.8,1223.5,-11.4,94.3,46.8,5,5779,0,0},{0,1,1183.7,1257.3,-6.8,75.0,61.8,13,4072,0,0},{0,3,1306.3,1271.8,-6.8,51.1,38.5,12,3894,0,0},{0,3,1425.8,1286.0,-6.8,55.7,36.9,15,8036,0,0},{0,3,1532.7,1298.7,-6.8,84.6,32.0,8,5582,0,0},
		{0,33,1649.9,1312.6,-6.8,34.1,31.9,2,9758,0,0},{0,1,1711.9,1319.9,-6.8,90.8,59.0,11,4679,0,0},{0,1,1675.1,1440.8,-143.7,49.8,65.2,6,4116,0,0},{0,3,1583.8,1507.7,-143.7,49.8,38.6,12,887,0,0},{0,3,1511.3,1560.9,-143.7,23.4,37.2,8,4829,0,0},{0,1,1416.2,1557.1,172.9,82.6,53.9,9,6872,0,0},{0,3,1287.6,1541.0,172.9,66.6,30.8,12,5062,0,0},{0,3,1161.4,1525.3,172.9,51.5,33.1,16,1275,0,0},
		{0,3,1059.2,1512.5,172.9,54.4,34.0,16,282,0,0},{0,3,937.2,1497.2,172.9,76.0,37.0,15,4703,0,0},{0,3,800.8,1480.2,172.9,77.6,37.6,15,233,0,0},{0,3,653.2,1460.8,172.0,91.1,32.6,16,6104,0,0},{0,3,516.4,1441.5,172.0,84.7,39.6,15,3216,0,0},{0,1,398.3,1424.9,172.0,74.5,57.5,11,911,0,0},{0,3,284.4,1408.8,172.0,65.1,33.4,13,6436,0,0},{0,1,163.5,1391.7,172.0,57.3,40.9,8,8147,0,0},
		{0,3,616.9,1372.6,117.5,42.9,27.3,12,4155,0,0},{0,13,1024.8,799.7,-10.5,39.1,46,7,8567,0,-1},{0,13,1388.2,906.0,-88.9,46.0,46,7,3680,0,-1},{0,16,1298.1,1194.7,173.1,46.2,73.1,12,5923,0,0},{0,1,1237.6,1187.4,173.1,75.6,58.5,5,9127,0,0},{0,1,1171.1,1179.4,173.1,58.4,56.3,8,4912,0,0},{0,16,1044.1,1158.2,168.6,78.1,66.2,24,6930,0,0},{0,16,966.7,1142.6,168.6,79.7,71.8,13,929,0,0},
		{0,29,921.0,1068.9,59.3,45.4,15.4,4,5879,0,0},{0,1,976.1,963.8,72.8,21.8,69.5,11,5917,0,0},{0,1,1096.1,813.6,-11.7,60.6,44.4,13,3954,0,0},{0,29,1148.8,825.3,-13.6,47.4,18.1,3,8678,0,0},{0,13,1205.8,839.1,-13.6,69.9,56.5,5,257,0,0},{0,13,1265.8,853.6,-13.6,53.6,48.2,7,2761,0,0},{0,16,1317.5,866.0,-13.6,52.7,67.2,21,1037,0,0},{0,29,1389.2,959.8,-88.9,61.4,36.3,3,2118,0,0},
		{0,13,1384.9,1049.2,-106.9,14.0,49.7,6,6031,0,0},{0,13,1599.1,827.1,166.4,67.2,17.9,5,8258,0,0},{0,13,1542.6,813.5,166.4,49.3,21.7,7,9960,0,0},{0,13,1505.5,804.5,166.4,27.0,20.7,6,9185,0,0},{0,29,1467.3,795.3,166.4,51.6,25.1,3,6595,0,0},{0,1,1413.7,782.3,166.4,58.7,29.2,9,7455,0,0},{0,1,1340.2,764.6,166.4,92.5,31.2,8,7827,0,0},{0,29,1268.0,747.1,166.4,56.2,35.4,2,5827,0,0},
		{0,13,1213.1,733.8,166.4,56.7,33.1,6,5539,0,0},{0,16,1158.4,720.6,166.4,55.9,39.2,23,9466,0,0},{0,13,1099.0,707.7,168.8,65.6,34.1,7,6462,0,0},{0,1,1024.6,693.9,170.0,85.8,33.9,11,3444,0,0},{0,1,938.9,678.7,170.0,88.4,31.7,7,6768,0,0},{0,29,873.0,667.0,170.0,45.5,33.9,3,1835,0,0},{0,1,819.6,657.6,170.0,63.0,38.9,12,8826,0,0},{0,1,744.5,644.3,170.0,89.4,40.8,13,6061,0,0},
		{0,13,674.5,631.9,170.0,52.6,34.8,5,292,0,0},{0,29,617.2,621.8,170.0,63.8,35.5,4,2630,0,0},{0,13,558.9,611.5,170.0,54.6,42.3,5,3655,0,0},{0,13,511.5,603.1,170.0,41.7,40.8,5,3162,0,0},{0,30,1070.7,382.2,-6.5,68.9,21.0,5,3550,0,0},{0,30,1120.5,387.9,-6.5,31.4,26.2,5,9085,0,0},{0,30,1228.3,410.6,-13.3,61.1,23.8,7,9461,0,0},{0,30,1285.0,424.0,-13.3,55.6,26.3,6,5006,0,0},
		{0,16,1343.2,437.8,-13.3,64.0,30.1,11,8560,0,0},{0,16,1403.8,452.1,-13.3,60.4,27.5,26,4780,0,0},{0,16,1532.7,495.8,-20.6,91.5,27.6,11,1926,0,0},{0,16,1160.8,395.4,-12.4,48,13.2,21,9542,1,0},{0,1,1200.5,227.6,0.3,39.2,56,12,1690,0,-1},{0,1,1598.7,232.8,-80.2,56.0,56,11,8972,0,-1},{0,16,1306.4,227.0,0.3,76.3,71.2,17,8629,0,0},{0,16,1439.1,221.1,5.8,78.5,77.2,25,9900,0,0},
		{0,16,1508.2,214.0,5.8,60.4,63.7,23,6263,0,0},{0,16,1609.7,297.1,-80.2,74.4,51.4,12,1645,0,0},{0,16,1622.9,373.4,-80.2,80.5,52.0,20,468,0,0},{0,16,1406.8,368.1,166.6,80.5,53.8,24,9301,0,0},{0,30,1348.9,354.3,166.9,38.7,46.2,8,5741,0,0},{0,16,1291.0,340.8,166.9,80.2,28.9,12,3805,0,0},{0,16,1229.2,326.4,166.9,46.7,30.9,7,2372,0,0},{0,16,1196.4,318.7,166.9,20.7,28.8,26,9792,0,0},
		{0,16,1492.5,378.9,-176.9,48,42,15,7296,1,0},{0,16,1174.1,56.3,11.1,56.0,56,16,3146,0,-1},{0,16,1545.7,-30.8,-75.7,39.2,56,9,601,0,-1},{0,16,1553.8,136.9,-174.4,47.6,56,11,1682,0,-1},{0,30,1158.3,136.4,98.8,39.2,62.6,5,7140,0,0},{0,30,1223.7,46.6,11.1,45.1,45.8,7,4511,0,0},{0,16,1273.8,36.7,11.1,57.0,52.6,16,8484,0,0},{0,30,1404.9,0.4,23.3,61.6,47.2,5,6443,0,0},
		{0,16,1561.4,32.2,-76.5,50.9,64.4,25,6643,0,0},{0,16,1474.9,144.6,-174.4,64.9,83.0,20,4825,0,0},{0,16,1400.7,151.3,-175.3,84.0,33.2,10,6011,0,0},{0,16,1263.2,155.2,-179.7,51.6,60.9,19,2488,0,0},{0,16,1512.9,98.6,9.8,20.9,42,16,4641,1,0},{0,16,1357.7,66.4,9.8,48,42,21,143,1,0},{0,16,1350.3,23.0,9.8,48,42,26,7480,1,0},{0,1,1404.7,-381.5,-79.6,56.0,56,9,3456,0,-1},
		{0,16,1477.9,-296.2,-75.7,56.0,56,19,5514,0,-1},{0,1,1495.1,-117.4,-156.4,56.0,56,6,7287,0,-1},{0,16,1118.0,-117.8,100.0,54.5,72.7,23,4639,0,0},{0,30,1107.5,-174.9,100.8,61.7,57.7,6,525,0,0},{0,16,1094.6,-242.7,100.8,76.2,73.0,26,3292,0,0},{0,30,1082.4,-306.6,100.8,53.9,59.8,8,9483,0,0},{0,30,1070.8,-367.3,100.8,69.5,48.3,5,3053,0,0},{0,30,1061.7,-414.9,100.8,27.6,67.5,7,6693,0,0},
		{0,16,1154.0,-466.2,-4.6,67.4,24.6,6,453,0,0},{0,30,1205.1,-462.1,-4.6,35.0,59.4,5,5031,0,0},{0,16,1273.0,-448.8,-16.9,65.7,74.0,18,9514,0,0},{0,16,1325.3,-432.6,-17.6,43.9,39.3,23,1317,0,0},{0,16,1490.9,-245.5,-75.7,48.7,60.5,15,3442,0,0},{0,16,1501.9,-202.4,-75.7,40.2,56.7,9,5251,0,0},{0,30,1448.1,-96.9,-156.4,46.6,53.0,8,6662,0,0},{0,30,1414.5,-82.2,-156.4,26.7,58.7,5,2352,0,0},
		{0,30,1380.0,-67.1,-156.4,48.6,64.7,6,5035,0,0},{0,30,1304.4,-42.1,-169.0,33.6,58.9,7,6791,0,0},{0,30,1263.0,-34.1,-169.1,50.7,67.0,7,661,0,0},{0,16,1215.3,-24.9,-169.1,46.5,64.1,26,8188,0,0},{0,30,1179.6,-18.0,-169.1,26.4,46.4,8,3708,0,0},{0,1,1151.1,-12.5,-169.1,31.6,20.6,10,8625,0,0},{0,16,1229.9,-334.4,-79.6,48,42,12,4815,1,0},{0,16,1238.9,-285.3,-79.6,48,42,10,4613,1,0},
		{0,16,1282.2,-293.2,-79.6,48,42,11,9189,1,0},{0,16,1325.4,-301.1,-79.6,48,42,14,9426,1,0},{0,16,1368.7,-309.0,-79.6,48,42,24,1304,1,0},{0,16,1247.9,-236.1,-79.6,48,42,22,9090,1,0},{0,16,1291.2,-244.0,-79.6,48,42,25,823,1,0},{0,16,1334.5,-251.9,-79.6,48,42,9,3848,1,0},{0,16,1377.7,-259.9,-79.6,48,42,8,2086,1,0},{0,16,1256.9,-186.9,-79.6,48,42,15,485,1,0},
		{0,16,1300.2,-194.8,-79.6,48,42,23,2988,1,0},{0,16,1343.5,-202.8,-79.6,48,42,26,2006,1,0},{0,16,1386.7,-210.7,-79.6,48,42,22,1877,1,0},{0,16,1058.3,-584.0,76.0,39.2,56,18,573,0,-1},{0,1,1157.9,-867.4,-9.1,56.0,56,6,6227,0,-1},{0,16,1084.9,-690.5,76.0,62.0,51.9,19,1730,0,0},{0,30,1098.7,-746.0,76.0,52.4,69.2,8,92,0,0},{0,30,1108.4,-784.7,76.0,27.5,46.9,7,4923,0,0},
		{0,16,1114.2,-807.8,76.0,20.0,62.8,26,4113,0,0},{0,16,1238.7,-1089.4,3.8,56.0,56,9,430,0,-1},{0,30,1399.2,-1054.2,-75.4,56.0,56,6,2873,0,-1},{0,1,1173.4,-1012.1,64.2,56.2,48.2,8,9626,0,0},{0,16,1326.3,-1091.4,-6.9,21.1,84.2,12,5451,0,0},{0,30,1426.1,-936.6,-82.3,28.1,51.4,8,9306,0,0},{0,16,1301.1,-916.4,169.1,54.9,86.4,24,9167,0,0},{0,16,1243.4,-926.5,170.9,62.4,54.7,26,5309,0,0},
		{0,30,58.4,173.5,97.9,56.0,56,7,3699,0,-1},{0,16,48.6,-117.9,2.3,47.6,56,23,3936,0,-1},{0,16,487.1,-135.0,-85.4,47.6,56,18,1408,0,-1},{0,30,502.7,132.7,-132.8,56.0,56,7,9440,0,-1},{0,16,416.8,198.3,-179.5,50.9,78.8,18,8030,0,0},{0,1,356.7,198.8,-179.5,69.3,59.0,12,3189,0,0},{0,30,295.5,199.3,-179.5,53.0,48.0,6,3625,0,0},{0,30,242.5,199.7,-179.5,53.0,52.0,8,9944,0,0},
		{0,30,202.3,200.1,-179.5,27.4,63.2,5,6800,0,0},{0,16,153.4,200.5,-179.5,70.5,72.8,7,7550,0,0},{0,16,51.4,123.0,97.9,46.0,51.7,23,2789,0,0},{0,30,45.4,80.3,97.9,40.1,58.5,6,1352,0,0},{0,16,37.3,17.8,97.2,86.0,47.3,16,9503,0,0},{1,24,138.7,-121.6,2.3,14.7,34.2,0,9545,0,0},{0,29,161.3,-122.6,2.3,30.6,30.3,4,1990,0,0},{1,25,184.0,-123.5,2.3,14.7,34.2,0,9503,0,0},
		{0,29,198.7,-124.1,2.3,14.7,36.6,4,5643,0,0},{0,16,232.2,-130.1,12.2,53.6,85.2,25,5701,0,0},{0,1,364.3,-148.4,6.8,91.2,65.1,12,1228,0,0},{0,16,494.7,-47.6,-84.1,51.3,85.9,6,9757,0,0},{0,16,504.5,17.5,-79.7,80.5,66.1,26,573,0,0},{0,16,372.6,-18.6,-174.3,48,42,10,7023,1,0},{0,16,376.9,25.1,-174.3,48,42,7,4502,1,0},{0,16,381.2,68.9,-174.3,48,42,22,5202,1,0},
		{0,16,385.6,112.7,-174.3,48,42,23,7686,1,0},{0,16,322.8,-13.7,-174.3,48,42,7,3298,1,0},{0,16,327.1,30.1,-174.3,48,42,6,8189,1,0},{0,16,331.5,73.9,-174.3,48,42,9,3320,1,0},{0,16,335.8,117.7,-174.3,48,42,15,7224,1,0},{0,16,277.4,35.0,-174.3,48,42,12,1804,1,0},{0,16,281.7,78.8,-174.3,48,42,21,5824,1,0},{0,16,286.1,122.6,-174.3,48,42,9,302,1,0},
		{0,16,227.6,40.0,-174.3,48,42,20,8387,1,0},{0,16,232.0,83.8,-174.3,48,42,21,2950,1,0},{0,16,173.5,1.1,-174.3,48,42,17,5828,1,0},{0,16,177.9,44.9,-174.3,48,42,25,6593,1,0},{0,16,182.2,88.7,-174.3,48,42,19,4123,1,0},{0,16,123.8,6.1,-174.3,48,42,11,8950,1,0},{0,16,917.9,-497.6,-136.0,39.2,56,11,6728,0,-1},{0,30,653.6,-265.7,-173.2,56.0,56,5,9743,0,-1},
		{0,16,543.9,-358.1,93.6,86.2,82.2,9,7229,0,0},{0,16,538.2,-447.3,93.6,92.7,58.2,13,789,0,0},{0,30,533.9,-587.9,89.9,47.8,60.5,7,2330,0,0},{0,16,534.0,-649.4,89.9,75.1,56.8,24,8397,0,0},{0,16,534.1,-719.5,89.9,65.1,75.2,7,2586,0,0},{0,16,676.9,-724.3,-36.7,75.6,63.3,9,5348,0,0},{0,30,771.9,-649.9,-38.7,50.6,51.7,5,391,0,0},{0,30,817.4,-613.6,-38.7,65.8,63.3,8,1802,0,0},
		{0,30,865.2,-446.8,-136.0,30.6,53.8,8,7732,0,0},{0,16,829.1,-411.8,-136.0,69.9,79.9,11,7303,0,0},{0,30,787.8,-371.9,-136.0,45.0,67.2,7,3270,0,0},{0,16,746.7,-332.1,-136.0,69.5,75.4,18,8761,0,0},{0,16,591.3,-291.3,-86.4,48,42,11,5586,1,0},{0,16,621.4,-293.3,-86.4,48,28.2,7,3913,1,0},{0,16,658.3,-622.4,-86.4,48,42,18,2850,1,0},{0,16,702.3,-625.2,-86.4,48,42,22,9269,1,0},
		{0,16,661.5,-572.5,-86.4,48,42,12,7698,1,0},{0,16,705.4,-575.3,-86.4,48,42,7,2617,1,0},{0,16,664.7,-522.6,-86.4,48,42,15,4595,1,0},{0,16,708.6,-525.4,-86.4,48,42,6,128,1,0},{0,16,752.5,-528.2,-86.4,48,42,14,888,1,0},{0,16,667.9,-472.7,-86.4,48,42,9,1862,1,0},{0,16,711.8,-475.5,-86.4,48,42,21,6887,1,0},{0,17,343.1,1734.3,93.2,34.0,34,3,2930,0,-1},
		{0,17,386.3,1528.2,-8.0,34.0,34,3,3920,0,-1},{0,33,464.3,1844.3,145.7,47.1,23.6,3,3737,0,0},{0,29,424.5,1815.7,143.1,50.9,11.4,3,9981,0,0},{0,29,387.2,1786.6,140.7,43.6,36.4,2,2515,0,0},{0,33,340.6,1689.6,93.2,55.4,28.9,3,3084,0,0},{0,33,339.7,1627.1,84.7,12.5,28.1,3,4678,0,0},{1,32,452.0,1537.5,-8.0,98.8,28.0,0,8039,0,0},{1,32,521.3,1626.3,-115.2,98.8,28.0,0,6361,0,0},
		{0,33,497.7,1678.7,-108.4,16.1,28.2,2,8249,0,0},{0,33,492.5,1697.3,-103.6,22.5,31.7,3,4000,0,0},{0,1,501.5,706.9,-10.0,46.0,46,9,7624,0,-1},{0,1,670.1,760.1,-99.2,46.0,46,9,661,0,-1},{0,29,537.5,1056.3,168.6,38.7,37.1,2,9347,0,0},{0,1,496.1,1048.0,168.6,45.7,47.4,8,1138,0,0},{0,16,444.1,1037.5,168.6,60.4,53.0,7,5852,0,0},{0,1,385.6,1025.8,168.6,59.0,65.3,9,898,0,0},
		{0,16,384.4,888.6,63.0,76.4,75.6,19,10,0,0},{0,1,419.0,820.6,63.0,76.1,53.8,7,1515,0,0},{0,1,447.1,765.3,63.0,48.0,64.5,10,6982,0,0},{0,1,553.5,716.1,-10.0,59.5,56.1,14,8493,0,0},{0,16,605.6,725.3,-10.0,46.5,83.6,14,3964,0,0},{0,13,664.3,795.9,-99.2,26.5,47.3,7,8419,0,0},{0,13,657.6,837.4,-99.2,57.5,41.8,6,2889,0,0},{0,29,644.2,899.6,-111.4,13.2,34.6,3,9505,0,0},
		{0,29,605.2,973.6,-119.4,33.7,32.9,4,358,0,0},{0,17,-146.5,1826.0,84.3,23.8,34,3,4539,0,-1},{1,25,-77.6,1512.2,-39.3,14.7,34.2,0,4009,0,0},{0,33,-57.5,1528.7,-39.3,37.3,28.4,3,1136,0,0},{1,25,-37.4,1545.1,-39.3,14.7,34.2,0,6669,0,0},{1,31,6.6,1581.1,-39.3,98.9,36.8,0,126,0,0},{1,28,60.8,1625.5,-39.3,41.2,28.1,0,4567,0,0},{0,33,90.2,1649.5,-39.3,34.7,32.3,3,4256,0,0},
		{1,32,141.9,1691.8,-39.3,98.8,28.0,0,669,0,0},{0,10,199.3,1738.8,-39.3,49.6,36.4,5,8101,0,0},{0,33,234.0,1767.1,-39.3,40.0,30.3,2,3604,0,0},{0,29,264.7,1792.2,-39.3,39.3,33.3,3,1506,0,0},{0,33,296.0,1817.9,-39.3,41.6,28.4,3,7947,0,0},{0,29,322.9,1839.9,-39.3,27.9,16.3,2,2561,0,0},{0,33,171.6,1830.7,178.2,35.1,28.0,3,13,0,0},{1,31,104.6,1832.3,-177.6,98.9,36.8,0,5693,0,0},
		{1,31,5.8,1836.5,-177.6,98.9,36.8,0,9015,0,0},{1,23,-139.8,1758.8,84.3,14.7,34.2,0,1844,0,0},{0,29,-137.3,1734.5,84.3,34.2,33.1,3,3006,0,0},{0,29,-132.6,1687.5,84.3,60.2,36.9,2,4044,0,0},{1,22,-128.9,1650.2,84.3,14.7,34.2,0,3206,0,0},{0,29,-126.1,1622.1,84.3,41.7,35.6,3,9011,0,0},{0,29,-120.5,1567.2,84.3,68.8,12.3,4,5691,0,0},{0,29,113.8,739.4,7.1,52.8,13.3,4,744,0,0},
		{0,29,155.0,734.3,7.1,30.3,34.4,4,6836,0,0},{0,1,202.0,728.4,7.1,64.6,69.2,9,683,0,0},{0,13,254.5,721.8,7.1,41.2,59.6,5,6836,0,0},{0,13,305.2,715.5,7.1,61.0,31.2,5,7295,0,0},{0,1,307.6,810.3,-117.0,94.9,33.7,7,4225,0,0},{0,29,278.3,867.7,-117.0,34.1,34.6,4,4675,0,0},{0,29,257.7,908.3,-117.0,57.0,37.3,4,8397,0,0},{0,16,226.6,969.5,-117.0,80.3,81.5,10,7342,0,0},
		{0,13,205.3,1012.1,-114.6,15.0,40.4,7,8580,0,0},{0,13,180.4,1041.8,-138.8,36.4,31.3,7,5688,0,0},{0,16,117.6,1028.6,83.1,53.8,29.1,22,730,0,0},{0,13,122.2,986.5,84.6,30.9,21.3,7,9221,0,0},{0,29,109.4,861.1,100.4,40.6,36.6,3,7571,0,0},{0,29,99.9,809.7,100.4,64.0,31.8,4,9935,0,0},{1,32,188.3,1623.8,140.7,98.8,28.0,0,7633,0,0},{0,33,130.9,1576.9,140.7,49.4,28.8,2,7854,0,0},
		{0,10,89.7,1543.2,140.7,57.1,39.1,4,3701,0,0},{0,10,57.4,1481.8,-8.0,48.3,16.9,4,6034,0,0},{0,29,162.3,1496.6,-8.0,44.0,34.4,3,3879,0,0},{1,31,233.1,1506.6,-8.0,98.9,36.8,0,1575,0,0},{0,33,276.8,1578.1,-106.7,31.2,30.2,2,3992,0,0},{0,17,582.4,2024.3,-34.3,23.8,34,3,3643,0,-1},{0,33,410.5,2268.0,43.9,65.2,18.5,3,4453,0,0},{1,32,517.3,2111.1,62.1,98.8,28.0,0,3098,0,0},
		{1,32,679.4,2090.6,-34.3,98.8,28.0,0,207,0,0},{1,31,761.0,2146.4,-34.3,98.9,36.8,0,8285,0,0},{0,33,824.5,2189.7,-34.3,54.9,19.8,3,5570,0,0},{0,33,800.6,2229.7,-169.6,36.0,19.3,3,2713,0,0},{0,29,760.8,2237.0,-169.6,44.9,26.5,2,3755,0,0},{0,33,718.7,2244.8,-169.6,40.7,31.5,3,2100,0,0},{1,31,650.0,2257.4,-169.6,98.9,36.8,0,2356,0,0},{0,10,570.1,2272.1,-169.6,63.6,40.0,5,6280,0,0},
		{0,33,517.5,2281.8,-169.6,43.5,31.9,3,4393,0,0},{0,29,482.0,2288.3,-169.6,28.7,35.5,4,3202,0,0},{0,29,444.8,2295.2,-169.6,46.8,12.3,4,2154,0,0},{0,29,789.5,1107.0,168.6,46.0,46,3,9979,0,-1},{0,1,767.4,754.0,-10.0,46.0,46,6,6579,0,-1},{0,1,925.9,822.2,-97.7,79.3,49.1,7,3635,0,0},{0,13,918.3,879.2,-97.7,35.8,47.0,7,8175,0,0},{0,1,907.4,941.7,-103.4,11.4,48.7,9,478,0,0},
		{0,16,883.9,988.7,-119.2,71.5,40.0,21,5891,0,0},{0,16,726.1,1094.2,168.6,83.3,51.1,7,5305,0,0},{0,16,714.7,916.7,71.9,16.4,84.1,21,3978,0,0},{0,1,733.4,819.6,80.8,49.2,34.9,8,3771,0,0},{0,16,825.9,764.3,-10.0,72.8,61.8,11,7484,0,0},{0,30,573.5,-173.5,6.8,34.4,58.2,8,286,0,0},{0,30,612.0,-178.1,6.8,43.2,57.7,7,5957,0,0},{0,16,665.7,-184.6,6.8,64.9,68.7,8,3829,0,0},
		{0,30,705.0,-189.8,10.8,14.5,48.2,5,5470,0,0},{0,16,752.3,-188.4,-121.3,45.9,19.2,12,5474,0,0},{0,16,684.2,-76.3,-121.3,62.0,24.8,20,9439,0,0},{0,16,639.5,-16.8,-132.4,55.7,60.7,21,449,0,0},{0,16,763.8,-49.3,58.7,56.0,56,21,3303,0,-1},{0,16,1036.6,207.6,139.9,52.5,38.5,7,2247,0,0},{0,30,991.5,169.7,139.9,65.4,66.6,7,4339,0,0},{0,1,944.3,130.5,140.8,57.4,47.5,12,6744,0,0},
		{0,16,903.9,97.8,141.4,46.6,75.7,11,2260,0,0},{0,30,863.5,65.7,141.4,56.6,52.4,7,8978,0,0},{0,16,817.2,28.7,141.4,61.8,59.7,22,2783,0,0},{0,16,800.6,-109.9,58.7,85.8,54.0,8,216,0,0},{0,30,831.0,-159.9,58.7,31.1,57.5,8,1889,0,0},{0,16,921.4,-132.9,-51.4,46.2,28.4,14,6897,0,0},{0,16,954.3,-91.8,-51.4,59.3,77.7,22,4545,0,0},{0,16,987.0,-50.9,-51.4,45.2,68.8,21,14,0,0},
		{0,30,1022.5,-6.5,-51.4,68.5,56.2,5,9348,0,0},{0,30,1052.2,30.6,-51.4,26.5,53.6,6,1546,0,0},{0,30,917.9,-303.4,59.0,67.5,60.5,8,3328,0,0},{0,16,1009.3,-252.3,-79.2,73.1,22.7,25,3492,0,0},{0,16,976.0,-180.0,128.6,66.6,31.3,21,6763,0,0},{0,16,727.8,49.6,-38.6,56.0,56,19,4332,0,-1},{0,30,934.0,283.8,173.3,30.4,42.4,5,3259,0,0},{0,16,884.1,278.0,173.3,70.2,60.1,22,3106,0,0},
		{0,16,814.3,269.4,172.6,70.3,47.8,7,6046,0,0},{0,16,678.7,247.6,170.3,65.4,62.5,19,4998,0,0},{0,16,608.7,235.6,170.3,76.4,54.4,8,938,0,0},{0,30,613.7,132.6,47.5,51.8,48.0,8,6372,0,0},{0,30,640.5,103.4,47.5,27.3,60.7,8,3762,0,0},{0,16,658.9,83.4,47.5,27.1,56.1,23,3284,0,0},{0,16,778.7,90.2,-38.6,74.4,67.5,11,2539,0,0},{0,1,836.0,135.8,-38.6,72.0,44.8,13,4988,0,0},
		{0,1,884.8,174.8,-38.7,52.8,32.1,8,9817,0,0},{0,16,755.5,217.1,-9.7,48,42,20,9017,1,0},{0,17,2194.1,-1925.0,-7.6,34.0,34,3,2024,0,-1},{0,17,2261.3,-1926.2,-31.0,34.0,34,3,1073,0,-1},{0,2,2738.6,-1428.8,-109.1,34.0,34,4,6324,0,-1},{0,2,2757.7,-1307.1,-116.6,34.0,34,3,5619,0,-1},{0,2,2363.4,-570.2,-177.1,34.0,34,4,388,0,-1},{0,17,1565.0,-496.8,136.2,34.0,34,3,9112,0,-1},
		{0,17,1432.8,-1392.5,50.8,34.0,34,3,5635,0,-1},{1,31,1495.6,-1449.9,20.9,98.9,36.8,0,4679,0,0},{1,32,1587.9,-1485.2,20.9,98.8,28.0,0,4350,0,0},{0,29,1664.4,-1514.4,20.9,64.9,35.3,2,6332,0,0},{1,25,1701.6,-1528.6,20.9,14.7,34.2,0,6295,0,0},{0,29,1735.0,-1541.3,20.9,56.8,35.5,4,7114,0,0},{1,26,1780.7,-1558.8,20.9,41.1,28.0,0,7940,0,0},{0,33,1817.1,-1572.7,20.9,36.9,31.7,2,7546,0,0},
		{0,10,1848.6,-1585.3,23.0,30.9,34.3,5,3418,0,0},{0,29,1880.8,-1600.8,27.6,40.7,36.1,2,8039,0,0},{0,29,1916.6,-1622.7,35.1,43.4,30.0,2,816,0,0},{0,33,2012.8,-1718.9,51.7,39.5,33.8,2,5869,0,0},{0,10,2039.6,-1752.9,51.7,47.0,34.5,3,5338,0,0},{0,29,2072.2,-1794.3,51.7,58.4,31.0,3,2309,0,0},{0,33,2106.7,-1837.8,51.7,52.7,30.5,3,3315,0,0},{0,29,2139.6,-1879.6,51.7,53.6,37.3,3,9470,0,0},
		{0,29,2298.0,-1904.2,-31.0,51.6,31.6,3,1378,0,0},{0,29,2347.5,-1874.5,-31.0,63.9,30.6,4,993,0,0},{1,32,2417.3,-1832.7,-31.0,98.8,28.0,0,9350,0,0},{0,33,2535.1,-1749.2,-42.7,59.3,28.3,2,5273,0,0},{0,29,2587.4,-1691.6,-53.8,27.5,36.8,4,4679,0,0},{1,25,2628.9,-1629.3,-58.0,14.7,34.2,0,3162,0,0},{0,10,2650.6,-1594.5,-58.0,67.4,36.3,5,2908,0,0},{1,31,2694.7,-1523.9,-58.0,98.9,36.8,0,4803,0,0},
		{0,29,2723.5,-1477.8,-58.0,9.8,36.2,3,1960,0,0},{0,29,2735.4,-1406.0,-93.7,12.1,36.9,2,3287,0,0},{0,10,2736.7,-1265.1,-116.6,60.0,30.5,4,7042,0,0},{0,29,2709.0,-1209.7,-116.6,63.8,36.0,2,654,0,0},{0,10,2680.8,-1153.3,-116.6,62.3,38.4,5,6654,0,0},{0,10,2656.5,-1104.8,-116.6,46.3,38.3,3,7940,0,0},{0,10,2638.6,-1068.9,-116.6,33.8,37.0,4,8770,0,0},{1,27,2626.7,-1045.2,-116.6,19.4,36.9,0,2054,0,0},
		{0,29,2611.1,-1014.4,-117.1,49.6,35.8,4,3506,0,0},{0,29,2583.8,-961.7,-117.5,69.0,36.8,2,2975,0,0},{1,32,2545.1,-887.3,-117.5,98.8,28.0,0,4263,0,0},{0,33,2508.4,-816.8,-117.5,60.2,30.7,2,2319,0,0},{0,10,2482.0,-766.2,-117.5,53.8,33.5,4,2891,0,0},{0,33,2458.0,-720.1,-117.5,50.3,33.1,3,1963,0,0},{0,33,2430.4,-667.2,-117.5,69.1,30.6,2,226,0,0},{0,29,2405.3,-618.9,-117.5,39.8,35.5,4,1475,0,0},
		{1,22,2339.1,-569.0,-177.1,14.7,34.2,0,5827,0,0},{0,29,2304.5,-567.3,-177.1,54.6,31.6,2,6932,0,0},{0,29,2254.4,-564.8,-177.1,45.8,30.1,4,3674,0,0},{1,26,2211.0,-562.6,-177.1,41.1,28.0,0,7034,0,0},{1,31,2141.1,-559.1,-177.1,98.9,36.8,0,502,0,0},{1,32,2042.4,-553.7,-176.6,98.8,28.0,0,8562,0,0},{0,10,1962.0,-545.9,-171.0,62.8,36.0,3,910,0,0},{0,33,1915.8,-538.6,-171.0,30.8,32.9,3,8383,0,0},
		{1,32,1851.8,-528.4,-171.0,98.8,28.0,0,519,0,0},{0,29,1772.7,-515.9,-171.0,61.2,37.1,3,6618,0,0},{1,31,1693.7,-503.4,-171.0,98.9,36.8,0,2451,0,0},{0,29,1627.8,-493.0,-171.0,34.4,32.8,3,9585,0,0},{1,24,1546.7,-561.5,92.2,14.7,34.2,0,743,0,0},{0,10,1545.8,-586.4,92.2,35.0,39.5,4,9930,0,0},{0,10,1544.1,-630.4,92.2,53.1,35.7,5,347,0,0},{0,10,1542.4,-675.9,92.2,38.1,39.9,5,6347,0,0},
		{1,28,1540.9,-715.5,92.2,41.2,28.1,0,832,0,0},{0,29,1539.1,-764.0,92.2,55.7,31.5,2,2580,0,0},{1,31,1536.1,-841.2,92.2,98.9,36.8,0,679,0,0},{0,10,1533.3,-906.9,93.6,32.5,38.7,4,73,0,0},{0,29,1530.3,-939.6,96.6,33.2,32.2,4,8868,0,0},{1,26,1524.7,-976.2,100.5,41.1,28.0,0,134,0,0},{1,23,1519.4,-1003.6,102.4,14.7,34.2,0,9398,0,0},{1,26,1512.7,-1030.7,104.4,41.1,28.0,0,8329,0,0},
		{0,10,1499.0,-1083.6,104.6,68.2,38.0,4,8494,0,0},{1,24,1488.6,-1123.7,104.6,14.7,34.2,0,4644,0,0},{0,29,1479.4,-1159.0,104.6,58.2,33.1,2,989,0,0},{1,32,1459.6,-1235.0,104.6,98.8,28.0,0,1165,0,0},{1,24,1445.4,-1289.9,104.6,14.7,34.2,0,6236,0,0},{0,10,1437.1,-1321.7,104.6,51.1,35.6,3,751,0,0},{0,3,2213.9,-1509.4,-148.1,44.4,29.2,17,2637,0,0},{0,3,1982.9,-1316.2,165.2,44.4,31.7,11,9000,0,0},
		{0,3,2522.7,-1324.4,-122.4,47.6,26.5,18,9033,0,0},{0,3,1715.9,-1149.1,-100.7,47.5,31.6,10,982,0,0},{0,3,1900.2,-1141.5,-142.7,36.5,26.4,11,5558,0,0},{0,3,2070.6,-1161.2,55.5,43.9,32.5,17,4067,0,0},{0,3,2265.0,-1137.8,-154.8,47.8,31.4,11,4201,0,0},{0,3,1717.3,-960.9,-25.3,36.7,26.7,12,4268,0,0},{0,3,2162.2,-776.7,-70.0,42.0,33.8,16,644,0,0},{0,2,1070.0,-1853.7,10.6,34.0,34,4,2912,0,-1},
		{0,17,1380.7,-1895.0,-87.6,23.8,34,3,694,0,-1},{0,2,1311.8,-1543.5,-162.6,34.0,34,3,7720,0,-1},{0,17,1261.7,-1525.1,166.3,34.0,34,3,9682,0,-1},{1,32,1083.0,-1607.7,116.4,98.8,28.0,0,5891,0,0},{0,33,1057.9,-1658.8,115.0,15.0,20.4,2,3984,0,0},{0,33,1046.1,-1694.7,102.1,15.0,28.8,3,8545,0,0},{1,20,1045.5,-1760.3,85.3,64.1,41.3,0,1198,0,0},{0,33,1049.6,-1808.8,84.9,16.0,29.1,3,9495,0,0},
		{1,32,1135.3,-1866.0,10.6,98.8,28.0,0,8046,0,0},{1,31,1232.4,-1884.2,10.6,98.9,36.8,0,8400,0,0},{0,33,1295.2,-1896.0,10.6,29.0,29.2,2,2958,0,0},{0,33,1384.2,-1809.2,-87.6,43.0,30.4,2,1519,0,0},{1,27,1385.4,-1778.0,-88.4,19.4,36.9,0,9354,0,0},{1,23,1383.7,-1731.9,-96.6,14.7,34.2,0,6414,0,0},{0,10,1366.8,-1664.7,-108.4,27.0,39.0,5,2431,0,0},{1,26,1356.0,-1632.4,-108.4,41.1,28.0,0,83,0,0},
		{1,25,1347.2,-1605.9,-108.4,14.7,34.2,0,8102,0,0},{1,22,1342.5,-1592.0,-108.4,14.7,34.2,0,8065,0,0},{0,33,1214.3,-1536.7,166.3,63.8,33.5,3,7934,0,0},{1,27,1173.9,-1546.6,166.3,19.4,36.9,0,1195,0,0},{0,17,819.4,-1623.9,110.4,34.0,34,3,3190,0,-1},{1,31,839.5,-1810.5,10.6,98.9,36.8,0,6329,0,0},{0,33,912.7,-1824.2,10.6,50.1,29.0,3,8544,0,0},{0,33,972.5,-1753.8,-94.7,34.2,30.3,2,103,0,0},
		{0,33,974.5,-1685.9,-79.4,31.2,33.2,2,2953,0,0},{0,33,980.2,-1661.0,-73.8,19.9,28.4,2,6424,0,0},{0,29,872.2,-1609.3,-178.4,25.8,37.6,3,4381,0,0},{0,33,805.1,-1662.4,110.2,48.0,31.1,3,6746,0,0},{0,33,791.5,-1739.3,90.6,36.4,34.0,2,1546,0,0},{0,29,1402.2,-2234.1,-3.7,47.0,30.6,4,7603,0,0},{1,18,1451.8,-2230.9,-3.7,52.3,28.2,0,9109,0,0},{1,25,1492.5,-2228.3,-3.7,14.7,34.2,0,9588,0,0},
		{1,23,1507.2,-2227.4,-3.7,14.7,34.2,0,3991,0,0},{1,24,1521.9,-2226.4,-3.7,14.7,34.2,0,2382,0,0},{1,19,1555.3,-2224.3,-3.7,52.3,28.2,0,5412,0,0},{1,12,1608.2,-2220.9,-3.7,35.3,29.0,0,1696,0,0},{1,20,1634.9,-2136.6,-84.7,64.1,41.3,0,1457,0,0},{1,18,1641.0,-2070.4,-84.7,52.3,28.2,0,3468,0,0},{1,5,1645.6,-2020.4,-84.7,32.6,30.8,0,5254,0,0},{1,5,1649.5,-1978.1,-84.7,32.6,30.8,0,9383,0,0},
		{1,11,1652.8,-1942.6,-84.7,17.8,29.0,0,3706,0,0},{1,8,1657.0,-1909.8,-81.4,26.9,27.9,0,2195,0,0},{1,18,1664.3,-1861.6,-81.4,52.3,28.2,0,2243,0,0},{1,19,1673.4,-1801.8,-81.4,52.3,28.2,0,7799,0,0},{1,19,1682.1,-1744.1,-81.4,52.3,28.2,0,9864,0,0},{1,4,1689.7,-1694.0,-81.4,35.5,29.3,0,9372,0,0},{0,10,1695.9,-1653.1,-81.4,29.3,38.8,5,4084,0,0},{1,22,1629.1,-1612.2,-159.1,14.7,34.2,0,2409,0,0},
		{1,19,1597.8,-1600.3,-159.1,52.3,28.2,0,5843,0,0},{1,24,1559.3,-1585.6,-159.1,14.7,34.2,0,9860,0,0},{0,29,1526.5,-1573.0,-159.1,55.6,36.2,3,6348,0,0},{1,23,1493.6,-1560.5,-159.1,14.7,34.2,0,9125,0,0},{0,29,1457.4,-1607.9,71.6,59.5,21.1,2,3301,0,0},{1,25,1469.1,-1643.1,71.6,14.7,34.2,0,3594,0,0},{0,29,1487.4,-1725.9,83.9,33.7,31.3,2,7653,0,0},{1,22,1489.4,-1750.0,88.2,14.7,34.2,0,1563,0,0},
		{1,22,1489.6,-1764.7,89.9,14.7,34.2,0,7802,0,0},{0,29,1489.1,-1787.0,92.0,29.8,37.3,4,9162,0,0},{1,25,1488.3,-1809.2,92.4,14.7,34.2,0,4388,0,0},{1,28,1487.2,-1837.2,92.4,41.2,28.1,0,8660,0,0},{1,28,1485.4,-1878.3,92.4,41.2,28.1,0,7008,0,0},{1,20,1483.2,-1930.9,92.5,64.1,41.3,0,4157,0,0},{0,29,1477.7,-1979.6,112.5,13.4,31.8,3,5035,0,0},{0,29,1471.3,-1990.8,127.3,12.6,33.2,3,9357,0,0},
		{0,29,1462.5,-2000.0,140.4,13.1,36.7,2,4398,0,0},{1,24,1436.3,-2061.5,110.2,14.7,34.2,0,1172,0,0},{1,19,1424.7,-2092.9,110.2,52.3,28.2,0,5429,0,0},{1,26,1405.4,-2142.3,113.2,41.1,28.0,0,6947,0,0},{1,22,2087.3,-2018.8,-79.1,14.7,34.2,0,6370,0,0},{1,27,2092.2,-2001.1,-69.9,19.4,36.9,0,4338,0,0},{1,19,2047.2,-1930.4,-128.3,52.3,28.2,0,2158,0,0},{0,29,2014.6,-1889.1,-128.3,34.5,35.1,2,2127,0,0},
		{1,20,1984.0,-1850.4,-128.3,64.1,41.3,0,4156,0,0},{0,29,1937.0,-1790.7,-128.3,69.3,34.5,2,8472,0,0},{0,29,1873.0,-1719.3,-140.7,20.3,34.6,4,350,0,0},{0,29,1840.1,-1696.7,-150.0,20.3,37.0,2,28,0,0},{1,8,1758.5,-1720.3,98.6,26.9,27.9,0,1551,0,0},{1,11,1753.8,-1751.9,98.6,17.8,29.0,0,68,0,0},{1,15,1749.1,-1782.6,98.6,26.9,29.0,0,763,0,0},{1,19,1742.0,-1829.6,98.6,52.3,28.2,0,9772,0,0},
		{1,15,1734.6,-1878.2,98.6,26.9,29.0,0,4744,0,0},{1,7,1729.1,-1914.6,98.6,24.2,27.9,0,4132,0,0},{1,14,1723.9,-1955.5,95.4,34.9,32.4,0,1468,0,0},{1,19,1718.8,-2010.6,95.2,52.3,28.2,0,7279,0,0},{1,15,1714.6,-2056.5,95.2,26.9,29.0,0,2706,0,0},{1,6,1710.1,-2105.1,95.2,51.4,31.0,0,6051,0,0},{1,11,1706.0,-2149.8,95.2,17.8,29.0,0,1446,0,0},{1,12,1702.8,-2184.4,95.2,35.3,29.0,0,4123,0,0},
		{1,18,1777.1,-2190.6,-27.8,52.3,28.2,0,4465,0,0},{1,28,1826.9,-2164.2,-28.1,41.2,28.1,0,946,0,0},{0,29,1870.7,-2140.8,-28.1,58.2,35.3,4,5315,0,0},{1,19,1919.4,-2114.8,-28.1,52.3,28.2,0,8924,0,0},{0,29,1972.1,-2086.7,-28.1,48.3,37.6,2,7757,0,0},{1,18,2016.5,-2063.1,-28.1,52.3,28.2,0,529,0,0},{0,21,1900.9,1728.8,41.4,84.0,51.6,2,4330,0,0},{0,21,1965.7,1671.7,41.4,88.8,65.9,2,5352,0,0},
		{0,21,2016.1,1626.7,42.5,46.3,89.5,2,1593,0,0},{0,21,2061.6,1584.6,42.9,77.4,56.8,2,9799,0,0},{0,21,2118.6,1531.6,42.9,78.3,59.9,2,8972,0,0},{0,21,2166.2,1487.3,42.9,51.9,63.0,2,1166,0,0},{0,21,2271.4,1600.5,-64.5,58.6,89.8,2,3987,0,0},{0,34,2301.8,1664.4,-64.5,83.0,40.6,5,2141,0,0},{0,21,2335.0,1734.1,-64.5,71.2,84.9,2,6850,0,0},{0,21,2268.8,1835.0,-139.8,46.1,53.2,2,8655,0,0},
		{0,21,2229.8,1868.0,-139.8,56.2,53.3,2,8311,0,0},{0,21,2112.8,1972.9,-136.8,87.4,75.7,2,7313,0,0},{0,21,2144.7,1408.9,-137.1,67.2,89.1,2,3774,0,0},{0,34,2086.8,1462.8,-137.1,90.9,44.6,4,1566,0,0},{0,21,2022.0,1523.1,-137.1,86.0,79.1,2,691,0,0},{0,21,1956.3,1583.3,-137.9,92.4,35.3,2,8888,0,0},{0,21,1903.1,1631.0,-138.6,50.5,59.4,2,3229,0,0},{0,21,1854.9,1673.4,-138.6,77.8,71.9,2,5782,0,0},
		{0,21,1789.9,1730.7,-138.6,95.5,69.2,2,819,0,0},{0,34,1624.5,1655.3,140.5,60.0,52.0,4,7513,0,0},{0,34,1675.0,1542.5,36.3,62.8,44.2,5,9883,0,0},{0,21,1737.2,1496.9,36.3,91.5,65.9,2,166,0,0},{0,21,1862.8,1418.7,24.6,76.9,88.6,2,6178,0,0},{0,21,1940.6,1384.3,23.2,93.3,22.4,2,3684,0,0},{0,21,2022.7,1349.2,23.2,85.3,20.1,2,1887,0,0},{0,34,1973.4,1041.9,-40.8,11.3,20.3,5,3810,0,0},
		{0,21,2000.8,1081.6,-59.0,55.2,36.6,2,1507,0,0},{0,34,2037.7,1142.9,-59.0,87.9,50.4,6,7067,0,0},{0,21,2013.5,1263.9,-156.8,60.3,45.7,2,1503,0,0},{0,16,1739.3,436.8,99.8,46.0,46,14,2975,0,-1},{0,16,2148.3,270.5,-81.9,32.2,46,12,4281,0,-1},{0,34,2136.8,428.9,-175.6,51.1,49.0,4,9937,0,0},{0,1,2088.2,432.7,-175.6,46.5,47.6,8,9822,0,0},{0,34,2024.1,437.7,-175.6,82.1,54.7,5,8752,0,0},
		{0,34,1943.5,443.9,-175.6,79.6,60.3,4,694,0,0},{0,34,1867.1,449.9,-175.6,73.7,53.7,4,7211,0,0},{0,16,1809.7,454.3,-175.6,41.4,81.8,18,8888,0,0},{0,34,1727.6,368.7,99.8,92.2,45.3,4,731,0,0},{0,34,1714.1,290.0,99.8,67.6,56.9,4,9107,0,0},{0,34,1848.9,261.8,-15.0,60.8,56.3,5,3602,0,0},{0,16,1889.6,271.2,-7.7,22.9,88.7,13,504,0,0},{0,16,1910.9,273.1,-1.6,19.8,59.0,25,1007,0,0},
		{0,34,2008.9,264.1,6.9,56.5,58.9,5,8760,0,0},{0,34,2068.1,257.0,6.9,62.9,47.2,5,5318,0,0},{0,13,1958.0,288.3,4.4,48,42,5,435,1,0},{0,13,2144.5,318.0,4.4,15.2,42,6,7351,1,0},{0,34,1684.5,118.3,99.8,46.0,46,6,8979,0,-1},{0,16,2124.4,118.4,-81.0,46.0,46,20,7327,0,-1},{0,34,2089.5,181.9,-173.1,89.1,19.6,4,8925,0,0},{0,34,2010.7,191.4,-173.1,69.6,54.4,4,645,0,0},
		{0,34,1951.3,198.1,-174.2,50.0,25.6,6,9117,0,0},{0,34,1901.9,200.0,171.2,12.2,61.4,6,670,0,0},{0,16,1770.3,164.7,163.9,78.4,89.9,12,5191,0,0},{0,34,1674.4,62.6,100.7,67.3,54.7,5,6722,0,0},{0,34,1764.7,-6.6,-16.0,49.1,54.5,6,8353,0,0},{0,16,1820.6,9.4,-16.0,67.0,61.7,25,1765,0,0},{0,34,1888.8,29.0,-16.0,75.0,69.3,4,8150,0,0},{0,16,1957.8,48.9,-16.0,68.6,57.6,11,6546,0,0},
		{0,1,2021.5,67.2,-16.0,63.9,41.5,14,4723,0,0},{0,16,2064.4,79.5,-16.0,25.4,55.8,6,5633,0,0},{0,13,1840.8,167.7,164.0,48,42,7,9166,1,0},{0,13,1836.5,182.9,164.0,48,13.9,7,3772,1,0},{0,34,1854.9,-109.1,106.5,46.0,46,5,3747,0,-1},{0,34,1837.0,-421.2,8.9,46.0,46,6,1358,0,-1},{0,34,2100.3,-18.4,164.0,61.6,68.7,4,2109,0,0},{0,34,2039.5,-35.9,164.0,65.0,43.2,5,6144,0,0},
		{0,34,1978.6,-53.4,164.0,61.7,67.0,4,384,0,0},{0,34,1927.3,-68.1,164.0,45.0,55.5,6,2130,0,0},{0,16,1840.1,-159.0,106.5,58.2,80.1,22,6127,0,0},{0,34,1823.9,-213.7,106.5,55.9,51.1,4,8135,0,0},{0,34,1813.4,-293.7,90.7,83.2,38.7,6,2426,0,0},{0,34,1894.5,-430.2,8.9,70.6,68.9,5,7267,0,0},{0,34,1951.9,-439.1,8.9,45.6,52.8,5,4216,0,0},{0,34,2080.7,-451.5,3.0,74.7,58.4,6,9814,0,0},
		{0,34,2143.5,-454.7,3.0,51.0,59.4,6,9657,0,0},{0,34,2212.4,-458.3,3.0,86.9,62.0,5,8680,0,0},{0,34,2277.0,-376.8,-119.1,85.5,21.0,6,6637,0,0},{0,34,2244.8,-318.8,-118.9,47.1,64.1,4,489,0,0},{0,34,2190.9,-192.4,-108.6,81.2,49.7,4,8002,0,0},{0,34,2170.2,-130.6,-108.4,49.2,53.5,4,4290,0,0},{0,13,2158.5,-280.6,-177.1,48,42,7,6852,1,0},{0,13,2106.3,-322.1,-177.1,48,42,6,6413,1,0},
		{0,13,2108.5,-278.1,-177.1,48,42,5,448,1,0},{0,13,2056.4,-319.6,-177.1,48,42,5,3954,1,0},{0,13,2058.6,-275.6,-177.1,48,42,6,1462,1,0},{0,13,2060.8,-231.7,-177.1,48,42,6,6433,1,0},{0,13,2063.0,-187.8,-177.1,48,42,7,8424,1,0},{0,13,2065.2,-143.8,-177.1,48,42,7,5338,1,0},{0,13,2006.5,-317.1,-177.1,48,42,6,9286,1,0},{0,13,2008.7,-273.1,-177.1,48,42,5,343,1,0},
		{0,13,2010.9,-229.2,-177.1,48,42,6,1430,1,0},{0,13,2013.1,-185.3,-177.1,48,42,6,5218,1,0},{0,13,1958.7,-270.7,-177.1,48,42,6,3273,1,0},{0,13,1960.9,-226.7,-177.1,48,42,6,5582,1,0},{0,13,1908.8,-268.2,-177.1,48,42,5,1861,1,0},{0,13,2268.6,-418.3,-177.1,16.4,42,7,6080,1,0},{0,16,1292.0,-1246.5,62.9,92.1,29.8,19,4138,0,0},{0,30,1434.1,-787.3,-87.8,56.0,56,8,2708,0,-1},
		{0,16,1397.9,-495.7,162.3,56.0,56,16,9160,0,-1},{0,16,1242.5,-568.8,95.9,56.0,56,14,8755,0,-1},{0,30,1331.7,-836.9,-12.1,56.1,57.6,8,754,0,0},{0,1,1368.7,-829.0,-12.1,19.6,68.6,14,7815,0,0},{0,30,1435.8,-743.1,-87.8,32.4,57.4,8,7615,0,0},{0,30,1437.0,-710.9,-87.8,32.1,54.6,7,6523,0,0},{0,30,1438.4,-674.3,-87.8,41.2,58.1,6,2651,0,0},{0,30,1440.0,-630.4,-87.8,46.6,58.1,6,2770,0,0},
		{0,30,1356.1,-509.1,162.3,31.8,68.1,5,865,0,0},{0,16,1320.3,-520.6,162.3,43.5,77.4,8,3116,0,0},{0,30,1236.6,-628.0,95.6,63.0,54.5,5,678,0,0},{0,16,1236.1,-695.2,79.3,12.6,57.8,18,3951,0,0},{0,16,1308.1,-653.1,92.2,48,42,6,6530,1,0},{0,34,1615.3,-178.4,104.3,46.0,46,6,2390,0,-1},{0,16,1586.4,-366.8,50.7,46.0,46,24,2570,0,-1},{0,34,1668.0,-394.2,9.1,49.6,41.1,6,2353,0,0},
		{0,34,1740.4,-288.7,-90.2,48.2,44.3,5,3490,0,0},{0,16,1741.3,-253.6,-85.2,22.2,58.9,18,3753,0,0},{0,34,1683.0,-138.3,164.0,36.8,41.0,6,4428,0,0},{0,34,1601.2,-234.0,104.3,68.7,53.7,4,5889,0,0},{0,34,1587.9,-285.8,104.3,38.4,62.9,5,6976,0,0},{0,16,1883.4,1035.0,-95.0,46.0,46,6,1412,0,-1},{0,1,1796.8,1253.5,173.3,46.0,46,9,6595,0,-1},{0,1,1755.8,967.5,-19.0,82.2,51.4,11,9664,0,0},
		{0,1,1818.3,989.0,-19.0,50.0,42.4,12,8771,0,0},{0,1,1877.8,1091.6,-96.0,67.8,33.9,7,1831,0,0},{0,13,1860.1,1166.3,-112.9,56.5,41.4,7,3950,0,0},{0,16,1737.4,1246.5,173.3,73.6,53.8,9,1831,0,0},{0,13,1667.0,1238.2,173.3,68.2,47.5,7,9435,0,0},{0,13,1618.4,1232.5,173.3,29.5,54.4,6,3212,0,0},{0,29,1576.9,1227.6,173.3,54.2,31.5,4,5674,0,0},{0,16,1524.4,1221.4,173.3,51.4,70.5,12,1768,0,0},
		{0,13,1471.9,1215.2,173.3,54.4,52.8,5,206,0,0},{0,13,1427.8,1134.9,65.9,27.6,26.3,7,6935,0,0},{0,29,1442.3,1101.3,67.1,45.7,31.6,3,8400,0,0},{0,1,1453.4,1072.6,73.8,15.9,56.0,10,5008,0,0},{0,1,1457.5,1056.1,78.0,18.1,40.7,8,5201,0,0},{0,16,1460.7,1037.1,82.9,20.4,75.9,6,5991,0,0},{0,29,1461.9,1010.4,90.2,33.2,33.7,4,6976,0,0},{0,1,1461.3,965.1,91.0,57.3,48.0,9,8715,0,0},
		{0,13,1520.9,915.2,-13.6,48.3,23.1,6,3482,0,0},{0,16,1568.8,926.8,-13.6,50.4,81.2,24,1458,0,0},{0,16,1641.6,944.3,-13.6,99.3,66.3,6,721,0,0},{0,1,1696.5,956.4,-3.8,13.4,45.4,8,5932,0,0},{0,1,2849.9,-1285.6,-0.1,22.5,41.7,10,596,0,0},{0,3,2921.0,-1215.7,-49.4,60.4,33.7,9,742,0,0},{0,1,3003.0,-1119.9,-49.5,78.1,60.8,11,2958,0,0},{0,33,3074.8,-1022.3,-60.5,40.3,29.7,2,722,0,0},
		{0,3,3111.3,-937.3,-72.3,58.3,30.8,16,2067,0,0},{0,1,3143.0,-826.4,-74.6,53.5,40.6,14,5005,0,0},{0,3,3169.7,-729.4,-74.6,12.8,33.4,12,7090,0,0},{0,1,3152.8,-689.8,-110.3,23.5,56.5,14,3546,0,0},{0,3,3046.8,-656.4,-167.6,75.4,38.1,13,9517,0,0},{0,33,2951.6,-635.5,-167.6,30.8,32.4,2,4523,0,0},{0,3,2892.2,-622.9,-168.1,90.7,33.3,13,810,0,0},{0,3,2753.0,-603.6,-174.9,55.2,36.7,8,8184,0,0},
		{0,3,2642.5,-593.8,-174.9,72.4,36.5,10,7576,0,0},{0,1,2539.0,-584.6,-174.9,61.1,50.6,10,9124,0,0},{0,3,2523.2,-667.8,62.5,49.3,22.2,17,4479,0,0},{0,1,2568.4,-754.6,62.5,53.4,54.7,9,7648,0,0},{0,3,2625.8,-864.8,62.5,83.4,33.8,18,7248,0,0},{0,1,2678.3,-965.8,62.8,66.4,44.2,14,3393,0,0},{0,3,2723.9,-1056.3,63.4,48.9,34.4,16,7787,0,0},{0,3,2785.3,-1179.0,63.4,90.1,32.9,12,8155,0,0},
		{0,3,2986.7,-1020.1,-0.0,41.5,30.1,12,6497,0,0},{0,34,2232.1,398.6,95.1,46.0,46,6,1684,0,-1},{0,16,2282.3,255.9,-45.0,70.5,42.0,25,6193,0,0},{0,16,2330.4,303.9,-45.0,65.5,62.7,15,4235,0,0},{0,34,2385.3,358.9,-45.0,89.9,26.2,5,884,0,0},{0,34,2337.9,413.8,-175.7,51.0,40.8,4,9629,0,0},{0,16,2296.2,416.9,-175.7,32.6,36.1,11,1056,0,0},{0,1,2226.3,333.8,95.1,84.1,31.0,9,162,0,0},
		{0,34,2551.8,378.3,135.0,46.0,46,6,1030,0,-1},{0,16,2368.7,46.8,10.8,91.2,50.6,13,2889,0,0},{0,16,2454.0,30.5,10.8,82.6,65.7,6,5297,0,0},{0,16,2518.7,18.1,10.8,49.2,88.8,25,4989,0,0},{0,34,2587.5,4.9,10.8,90.7,63.7,4,9706,0,0},{0,34,2675.1,103.9,-96.3,51.6,66.5,6,1557,0,0},{0,34,2672.9,177.9,-83.6,24.0,54.8,5,3346,0,0},{0,16,2676.5,199.4,-76.9,19.8,53.8,11,6793,0,0},
		{0,16,2681.6,218.1,-72.3,19.0,73.6,25,1640,0,0},{0,34,2645.4,382.5,-171.2,64.4,66.1,5,1041,0,0},{0,34,2515.1,341.6,135.0,57.8,61.0,6,9202,0,0},{0,34,2467.1,293.6,135.0,78.0,50.8,4,6379,0,0},{0,34,2420.2,246.6,135.0,54.7,40.2,5,226,0,0},{0,34,2370.2,196.6,135.0,86.7,42.2,6,2144,0,0},{0,34,2319.5,146.0,135.0,56.6,38.6,4,1829,0,0},{0,34,2282.6,109.0,135.0,47.9,39.3,4,57,0,0},
		{0,13,2543.7,199.7,-169.2,48,42,6,9178,1,0},{0,13,2552.0,242.9,-169.2,48,42,7,7753,1,0},{0,13,2486.3,165.9,-169.2,48,42,6,5795,1,0},{0,17,3008.3,321.0,-162.9,23.8,34,3,3711,0,-1},{0,2,2820.9,338.9,117.3,34.0,34,4,5876,0,-1},{1,31,2811.1,-36.4,9.1,98.9,36.8,0,5013,0,0},{0,33,2874.6,-46.5,9.1,29.8,33.1,3,4444,0,0},{0,33,2902.4,-51.0,9.1,26.4,28.3,3,2215,0,0},
		{0,33,2954.4,-12.9,-93.6,41.6,29.2,2,568,0,0},{0,33,2951.5,33.3,-93.6,50.9,29.2,3,744,0,0},{0,33,2950.5,132.2,-81.7,17.5,28.1,2,4373,0,0},{0,33,2954.2,150.7,-76.3,20.3,33.0,3,8516,0,0},{0,33,2978.1,213.9,-65.5,36.1,33.6,3,2582,0,0},{0,29,2957.9,333.3,-169.2,36.0,32.0,3,4776,0,0},{0,29,2910.4,341.3,-171.2,60.3,15.9,2,6272,0,0},{0,29,2871.4,347.4,-171.2,18.6,36.9,4,1810,0,0},
		{0,33,2804.3,306.8,117.3,38.2,28.2,3,872,0,0},{1,31,2773.8,245.5,116.2,98.8,36.8,0,6280,0,0},{0,33,2745.4,170.7,97.7,34.0,29.1,2,5731,0,0},{0,33,2751.9,67.7,83.9,50.0,31.1,3,5614,0,0},{0,34,2652.1,-467.6,-72.8,46.0,46,4,7766,0,-1},{0,1,2672.3,-88.7,-169.2,46.0,46,9,7457,0,-1},{0,34,2453.5,-472.6,5.1,76.9,44.9,6,1477,0,0},{0,1,2529.3,-479.3,5.1,75.2,44.3,10,1906,0,0},
		{0,34,2583.1,-484.1,5.1,32.9,60.3,5,2793,0,0},{0,34,2669.9,-410.2,-72.8,74.3,48.2,6,7576,0,0},{0,34,2690.0,-343.2,-74.0,65.6,23.7,4,7174,0,0},{0,34,2700.9,-253.0,-91.8,59.2,57.1,4,5480,0,0},{0,34,2698.3,-181.2,-92.2,84.5,42.5,5,357,0,0},{0,34,2613.1,-77.4,-169.2,74.5,43.8,4,3969,0,0},{0,16,2548.8,-65.1,-169.2,56.5,62.0,19,6221,0,0},{0,34,2482.2,-52.3,-169.2,79.2,65.0,6,713,0,0},
		{0,1,2397.0,-36.0,-169.2,94.2,63.4,14,6310,0,0},{0,34,2317.6,-20.8,-169.2,67.5,52.0,4,5301,0,0},{0,34,2261.2,-10.0,-169.2,47.3,52.8,4,5351,0,0},{0,34,2237.8,-93.1,71.6,46.5,26.7,6,1721,0,0},{0,34,2258.0,-153.7,71.6,81.3,50.1,6,9288,0,0},{0,16,2314.6,-287.9,61.0,57.3,76.1,15,352,0,0},{0,34,2342.7,-338.7,60.9,58.7,62.5,5,3246,0,0},{0,16,2370.6,-388.8,60.9,55.9,71.2,8,9878,0,0},
		{0,13,2400.7,-182.6,10.8,48,42,5,8644,1,0},{0,13,2449.8,-192.0,10.8,48,42,7,5439,1,0},{0,13,2441.5,-235.2,10.8,48,42,6,1566,1,0},{0,13,2498.9,-201.4,10.8,48,42,5,6380,1,0},{0,13,2490.6,-244.6,10.8,48,42,5,6668,1,0},{0,13,2482.4,-287.8,10.8,48,42,5,1768,1,0},{0,13,2474.1,-331.1,10.8,48,42,6,6255,1,0},{0,13,2548.0,-210.8,10.8,48,42,7,898,1,0},
		{0,13,2539.7,-254.0,10.8,48,42,5,4001,1,0},{0,13,2531.5,-297.2,10.8,48,42,7,4140,1,0},{0,13,2523.2,-340.5,10.8,48,42,7,5661,1,0},{0,13,2514.9,-383.7,10.8,48,42,7,1646,1,0},{0,13,2597.1,-220.2,10.8,48,42,6,4458,1,0},{0,13,2588.9,-263.4,10.8,48,42,5,1787,1,0},{0,13,2580.6,-306.6,10.8,48,42,7,8487,1,0},{0,13,2572.3,-349.9,10.8,48,42,6,5293,1,0},
		{0,13,2564.0,-393.1,10.8,48,42,7,4506,1,0},{0,17,2921.6,-505.2,-70.9,34.0,34,3,5129,0,-1},{0,17,2945.8,-134.8,-171.1,34.0,34,3,9587,0,-1},{0,10,2762.2,-500.3,5.5,26.9,32.7,4,22,0,0},{0,29,2800.9,-504.1,5.5,50.9,36.7,4,8231,0,0},{1,22,2833.6,-507.2,5.5,14.7,34.2,0,2863,0,0},{0,33,2936.7,-461.8,-70.9,57.9,33.8,3,4343,0,0},{0,33,2953.3,-413.9,-70.9,43.5,34.0,3,6206,0,0},
		{0,33,2965.3,-377.7,-72.7,32.9,18.2,2,4573,0,0},{0,33,2974.8,-338.0,-87.1,12.1,31.1,2,6611,0,0},{1,32,2970.8,-247.6,-94.3,98.8,28.0,0,1894,0,0},{0,33,2966.1,-184.9,-94.3,27.0,28.1,2,2292,0,0},{1,32,2880.2,-124.6,-171.1,98.8,28.0,0,713,0,0},{0,33,2818.5,-114.9,-171.1,26.0,31.4,3,9945,0,0},{1,31,2771.0,-196.5,87.8,98.9,36.8,0,6521,0,0},{0,33,2771.6,-313.1,97.1,23.3,31.8,2,8784,0,0},
		{0,33,2754.8,-377.8,107.0,30.5,29.6,2,1433,0,0},{1,19,2742.7,-417.4,107.0,52.3,28.2,0,182,0,0},{0,2,3182.8,-565.0,-46.2,34.0,34,4,8418,0,-1},{0,17,3235.0,-523.2,-70.4,34.0,34,3,2755,0,-1},{1,25,3049.8,-550.6,12.4,14.7,34.2,0,4399,0,0},{0,10,3071.0,-555.3,12.4,28.6,35.8,3,3042,0,0},{1,27,3094.4,-560.4,12.4,19.4,36.9,0,8430,0,0},{0,33,3120.9,-566.2,12.4,34.7,31.5,3,2829,0,0},
		{0,33,3202.6,-550.6,-30.0,15.1,19.1,3,2900,0,0},{1,32,3257.3,-460.6,-70.4,98.8,28.0,0,8975,0,0},{1,31,3290.4,-367.5,-70.4,98.9,36.8,0,9957,0,0},{1,31,3323.5,-274.3,-70.4,98.9,36.8,0,4225,0,0},{0,33,3254.9,-182.9,-171.2,68.5,28.1,2,9195,0,0},{1,18,3195.3,-173.6,-171.2,52.3,28.2,0,1874,0,0},{1,20,3130.0,-163.5,-171.2,64.1,41.3,0,3359,0,0},{1,31,3042.9,-246.8,85.7,98.9,36.8,0,2153,0,0},
		{0,33,3045.0,-356.7,98.9,25.0,28.5,2,6089,0,0},{1,32,3009.1,-472.7,109.1,98.8,28.0,0,8627,0,0},{0,2,3289.9,221.2,-160.3,34.0,34,4,715,0,-1},{0,2,3085.6,276.2,114.5,34.0,34,3,2255,0,-1},{0,17,3047.0,-73.7,8.8,34.0,34,3,5361,0,-1},{0,17,3351.1,-103.9,-89.5,23.8,34,3,5944,0,-1},{0,29,3344.3,144.5,-138.0,24.0,32.9,3,8093,0,0},{0,29,3331.6,157.3,-128.1,12.2,30.7,2,1812,0,0},
		{0,29,3324.1,167.3,-125.6,12.7,33.9,2,8709,0,0},{0,29,3318.0,177.8,-114.4,11.6,36.1,4,2160,0,0},{1,32,3227.4,243.6,-160.3,98.8,28.0,0,3947,0,0},{0,33,3165.3,265.8,-160.3,33.1,33.0,3,3921,0,0},{0,10,3137.2,275.8,-160.3,26.5,34.0,5,1175,0,0},{0,33,3072.2,246.9,114.5,30.5,29.7,3,8633,0,0},{0,33,3058.4,216.6,114.5,36.0,30.4,3,2139,0,0},{0,33,3044.1,185.1,114.5,33.2,30.4,3,1965,0,0},
		{0,33,3033.4,161.1,113.1,19.2,24.4,3,5367,0,0},{0,33,3022.1,122.6,100.3,13.4,29.6,3,8091,0,0},{1,20,3022.8,45.9,86.4,64.1,41.3,0,5409,0,0},{0,33,3026.7,-15.6,86.4,43.2,28.7,3,7214,0,0},{1,31,3112.6,-83.9,8.8,98.9,36.8,0,305,0,0},{1,31,3210.4,-99.1,8.8,98.9,36.8,0,179,0,0},{0,33,3273.3,-108.8,8.8,28.4,32.3,2,7100,0,0},{0,33,3351.7,-33.4,-89.5,29.4,32.5,2,2375,0,0},
		{1,31,3352.2,30.7,-89.5,98.9,36.8,0,8461,0,0},{0,16,3134.2,1204.0,-180.0,60.0,60,16,9796,0,-1},{0,16,2844.1,1174.0,87.7,51.0,60,13,5015,0,-1},{0,1,3011.2,901.0,-34.5,63.6,54.0,12,7227,0,0},{0,16,3065.3,938.2,-34.5,67.8,59.7,32,2614,0,0},{0,16,3104.1,964.8,-34.5,26.2,71.6,16,2132,0,0},{0,16,3130.2,986.4,-45.6,18.2,49.8,33,6088,0,0},{0,16,3151.3,1013.0,-57.0,25.8,64.6,30,7281,0,0},
		{0,16,3165.3,1041.3,-68.4,14.5,55.1,20,1649,0,0},{0,16,3173.3,1073.4,-80.9,29.0,46.7,25,9904,0,0},{0,16,3080.3,1204.0,-180.0,47.9,61.3,26,2762,0,0},{0,16,3020.1,1204.0,-180.0,72.3,86.9,17,7336,0,0},{0,16,2850.3,1083.6,80.1,23.4,85.3,35,4739,0,0},{0,1,2861.6,1041.0,69.9,20.4,48.4,13,7121,0,0},{0,16,2882.5,997.2,59.4,26.8,65.4,29,5894,0,0},{0,16,2922.0,947.5,46.9,63.0,53.4,25,5028,0,0},
		{0,16,2877.7,1296.0,-0.0,42.0,60,7,8128,0,-1},{0,16,3146.3,1325.6,-99.2,42.0,60,15,2145,0,-1},{0,16,2938.4,1584.5,131.2,89.4,65.1,20,2331,0,0},{0,1,2884.7,1506.6,112.4,22.5,52.8,10,1968,0,0},{0,16,2867.8,1435.2,99.0,82.7,61.5,21,4540,0,0},{0,16,2992.3,1296.0,-0.0,94.0,58.6,17,6180,0,0},{0,1,3130.9,1421.1,-99.2,55.7,57.7,14,8801,0,0},{0,16,3114.9,1488.1,-111.5,25.6,56.8,17,3645,0,0},
		{0,16,3097.9,1520.8,-123.7,17.2,58.7,33,18,0,0},{0,16,3076.4,1547.1,-134.3,19.3,71.5,34,1114,0,0},{0,21,2425.4,1918.3,-54.9,28.1,71.0,2,8940,0,0},{0,21,2443.0,1940.4,-48.2,28.4,64.9,2,7467,0,0},{0,21,2463.1,1960.3,-41.1,28.3,62.7,2,925,0,0},{0,21,2484.7,1977.2,-34.8,26.7,75.1,2,6850,0,0},{0,34,2504.1,1989.4,-28.5,19.3,43.4,6,8786,0,0},{0,21,2526.1,1999.8,-23.3,29.4,64.0,2,2194,0,0},
		{0,21,2570.7,2013.9,-14.9,64.4,60.0,2,4004,0,0},{0,21,2645.0,2032.7,-13.8,88.8,72.8,2,1769,0,0},{0,21,2711.4,2049.0,-13.8,48.0,86.2,2,5099,0,0},{0,34,2757.9,2060.5,-13.8,47.8,64.5,5,1333,0,0},{0,34,2809.2,2073.1,-13.8,57.7,38.5,4,232,0,0},{0,21,2720.3,2173.0,-155.4,71.5,27.3,2,7498,0,0},{0,21,2588.6,2218.7,-167.4,72.2,84.1,2,1329,0,0},{0,21,2465.8,2239.1,-172.0,63.4,81.8,2,4350,0,0},
		{0,21,2395.4,2249.0,-172.0,78.9,68.7,2,4055,0,0},{0,21,2318.7,2259.7,-172.0,75.9,87.3,2,3252,0,0},{0,21,2257.6,2268.3,-172.0,47.5,55.0,2,2518,0,0},{0,34,2210.5,2252.9,149.4,12.2,20.3,5,9572,0,0},{0,34,2199.6,2246.8,151.9,12.8,56.1,4,9099,0,0},{0,21,2161.0,2236.2,176.7,13.8,67.6,2,7326,0,0},{0,21,2147.0,2235.6,178.9,14.4,77.1,2,2654,0,0},{0,21,2086.1,2149.7,122.0,78.8,40.7,2,1703,0,0},
		{0,21,2163.3,2024.0,43.3,84.0,81.5,2,2253,0,0},{0,34,2220.5,1971.5,41.7,71.4,18.4,4,6304,0,0},{0,21,2265.0,1932.7,40.2,46.6,59.7,2,4508,0,0},{0,21,2308.1,1896.2,40.2,66.3,55.0,2,7745,0,0},
	},
	gardens = {
		{2,3519.0,118.0,90.5,34.0,34.0},{2,3391.7,-581.8,60.9,34.0,10.2},{2,3327.0,-783.6,105.4,34.0,34.0},{2,2998.0,-1381.7,78.9,34.0,10.2},{2,2875.9,-1547.2,122.0,34.0,34.0},{2,2345.4,-2070.5,99.5,34.0,10.2},{2,2149.0,-2180.5,151.9,34.0,34.0},{2,1119.9,-2383.8,-167.6,34.0,34.0},
		{2,364.7,-2285.4,133.0,34.0,10.2},{2,170.2,-2299.6,168.9,34.0,34.0},{2,-799.4,-2368.8,135.7,34.0,34.0},{2,-1015.1,-2355.5,-177.7,34.0,34.0},{2,-1780.5,-2211.6,149.0,34.0,10.2},{2,-1996.8,-2108.5,-149.0,34.0,34.0},{2,-2528.7,-1584.4,-132.0,34.0,34.0},{2,-2823.4,-1084.1,-156.5,34.0,10.2},
		{2,-2884.4,-867.2,-104.4,34.0,34.0},{2,-2975.7,-273.3,-141.5,34.0,34.0},{2,-2941.7,-23.8,-72.4,34.0,34.0},{1,3285.2,1070.6,95.3,21.0,10.2},{1,3284.7,1044.2,101.1,25.4,17.0},{1,3276.3,1015.3,107.2,28.0,34.0},{1,3265.1,986.5,114.1,26.5,34.0},{1,3254.9,960.8,119.9,22.2,34.0},
		{1,3240.7,942.3,124.7,18.6,34.0},{1,3224.8,922.3,130.4,26.3,34.0},{1,3204.4,903.8,135.9,23.1,34.0},{1,3182.3,878.6,142.5,36.1,34.0},{1,3122.3,843.3,145.8,98.8,34.0},{1,3060.1,800.7,145.8,52.3,34.0},{1,3031.6,776.7,141.1,12.1,34.0},{1,2972.6,689.2,126.5,98.9,34.0},
		{1,2927.2,642.2,126.5,30.7,34.0},{1,2908.7,612.0,126.6,39.8,34.0},{1,2881.4,582.5,129.5,37.3,34.0},{1,2856.7,552.2,134.1,36.3,34.0},{1,2808.7,496.2,8.8,40.0,34.0},{1,2876.5,480.2,8.8,98.8,34.0},{1,2939.5,473.5,8.8,27.6,34.0},{1,2975.6,466.4,10.5,44.3,34.0},
		{1,3014.9,456.1,13.4,34.0,34.0},{1,3050.6,446.2,17.3,36.0,34.0},{1,3118.4,432.0,19.7,98.9,34.0},{1,3211.5,398.7,19.7,98.9,34.0},{1,3287.8,365.5,19.7,67.2,34.0},{1,3368.6,364.7,-21.4,23.0,34.0},{1,3521.2,51.6,90.5,98.9,34.0},{1,3520.4,-47.3,90.5,98.9,34.0},
		{1,3515.8,-119.9,90.5,46.1,34.0},{1,3512.5,-200.4,92.6,18.5,34.0},{1,3512.7,-226.5,102.8,22.4,34.0},{1,3488.8,-286.1,109.2,98.8,34.0},{1,3464.3,-382.4,109.6,98.9,34.0},{1,3422.8,-472.7,109.6,98.8,34.0},{1,3404.3,-541.9,109.6,44.2,34.0},{1,3354.7,-760.8,140.6,16.8,10.2},
		{1,3310.5,-825.3,105.4,55.1,34.0},{1,3297.4,-901.7,105.4,98.9,34.0},{1,3275.6,-961.0,105.9,26.4,34.0},{1,3240.0,-1051.6,113.8,39.8,34.0},{1,3217.2,-1095.3,118.7,54.3,34.0},{1,3197.2,-1136.8,123.0,32.8,34.0},{1,3168.2,-1171.2,127.5,52.3,34.0},{1,3114.2,-1236.2,130.6,98.8,34.0},
		{1,3056.5,-1317.0,130.6,98.9,34.0},{1,3014.3,-1359.0,130.6,19.8,34.0},{1,2997.3,-1417.1,95.6,17.4,34.0},{1,2905.2,-1532.4,159.4,12.5,10.2},{1,2843.1,-1605.1,122.0,98.9,34.0},{1,2790.6,-1688.9,122.0,98.9,34.0},{1,2749.4,-1746.5,123.0,41.3,34.0},{1,2688.1,-1823.9,130.1,31.2,34.0},
		{1,2666.4,-1853.6,135.2,36.3,34.0},{1,2556.7,-1937.7,146.9,28.6,34.0},{1,2500.2,-1969.4,149.0,98.8,34.0},{1,2415.5,-2020.3,149.0,98.8,34.0},{1,2368.3,-2054.6,149.0,17.3,34.0},{1,2091.7,-2214.3,151.9,98.9,34.0},{1,2000.3,-2253.0,151.9,98.8,34.0},{1,1913.2,-2299.5,151.9,98.8,34.0},
		{1,1731.5,-2376.7,172.7,27.4,34.0},{1,1666.5,-2386.8,176.9,98.9,34.0},{1,1567.6,-2383.8,176.3,98.8,25.5},{1,1500.8,-2389.1,176.3,35.3,34.0},{1,1452.4,-2394.1,176.3,47.1,34.0},{1,1406.3,-2394.2,176.3,45.0,34.0},{1,1343.1,-2421.2,138.8,8.4,34.0},{1,1054.5,-2372.2,-167.6,98.9,34.0},
		{1,978.9,-2350.6,-167.6,57.9,34.0},{1,903.2,-2329.9,-167.6,98.8,34.0},{1,805.1,-2317.9,-168.2,98.9,10.2},{1,694.4,-2293.2,-176.2,35.3,34.0},{1,619.7,-2297.6,-177.7,98.9,34.0},{1,544.6,-2285.9,-177.7,52.3,34.0},{1,462.2,-2282.4,-177.7,98.8,34.0},{1,398.4,-2284.5,-177.7,28.6,34.0},
		{1,339.6,-2300.7,144.4,11.4,34.0},{1,203.7,-2311.8,-155.6,16.3,10.2},{1,104.0,-2306.5,168.9,98.8,34.0},{1,7.0,-2325.6,168.9,98.8,34.0},{1,-88.3,-2353.3,168.9,98.9,34.0},{1,-187.0,-2363.8,168.9,98.8,34.0},{1,-262.5,-2383.0,169.1,56.5,34.0},{1,-359.9,-2394.9,178.3,30.0,34.0},
		{1,-393.3,-2393.6,-177.7,32.4,34.0},{1,-460.3,-2395.0,-175.8,98.9,34.0},{1,-559.0,-2387.9,-175.8,98.9,34.0},{1,-657.0,-2371.9,-175.8,98.8,34.0},{1,-723.9,-2372.2,-175.8,34.8,34.0},{1,-1081.6,-2355.7,-177.7,98.9,34.0},{1,-1156.7,-2344.0,-177.7,52.3,34.0},{1,-1242.4,-2349.2,-177.7,98.9,34.0},
		{1,-1307.4,-2338.1,-176.7,31.1,34.0},{1,-1341.6,-2340.7,-174.6,34.3,34.0},{1,-1439.0,-2323.3,-168.8,26.4,34.0},{1,-1484.1,-2311.6,-163.4,60.9,34.0},{1,-1560.2,-2282.7,-160.5,98.8,34.0},{1,-1641.5,-2268.0,-160.4,64.1,34.0},{1,-1700.5,-2233.2,-160.4,52.3,34.0},{1,-1747.5,-2219.6,-160.4,30.6,34.0},
		{1,-1979.1,-2141.0,-114.4,18.0,10.2},{1,-2050.6,-2069.2,-149.0,98.8,34.0},{1,-2115.5,-2030.5,-149.0,52.3,34.0},{1,-2157.4,-2005.4,-147.7,31.9,34.0},{1,-2188.6,-1988.4,-142.9,33.7,34.0},{1,-2214.2,-1963.9,-137.4,31.2,34.0},{1,-2295.0,-1865.4,-127.5,98.8,34.0},{1,-2342.4,-1809.5,-127.5,47.5,34.0},
		{1,-2368.1,-1775.8,-127.5,37.3,34.0},{1,-2425.2,-1737.6,-163.1,16.0,34.0},{1,-2575.1,-1536.8,-132.0,98.9,34.0},{1,-2618.4,-1482.4,-132.0,39.8,34.0},{1,-2661.4,-1427.8,-132.0,98.8,34.0},{1,-2728.7,-1352.0,-121.0,21.0,34.0},{1,-2739.5,-1331.2,-115.6,19.8,34.0},{1,-2752.4,-1302.0,-109.5,37.2,34.0},
		{1,-2768.5,-1234.5,-107.5,98.8,34.0},{1,-2794.0,-1166.8,-107.5,45.7,34.0},{1,-2809.2,-1123.9,-107.5,45.4,34.0},{1,-2895.1,-801.4,-104.4,98.8,34.0},{1,-2928.2,-707.9,-104.4,98.9,34.0},{1,-2939.1,-631.9,-102.5,51.7,34.0},{1,-2957.4,-535.3,-95.9,45.4,34.0},{1,-2967.6,-462.0,-93.1,98.9,34.0},
		{1,-2964.0,-362.7,-92.9,98.8,34.0},{1,-2926.5,20.7,-72.4,60.3,34.0},{1,-2906.1,71.0,-72.4,47.8,34.0},{1,-2892.8,120.9,-70.8,53.7,34.0},{1,-2696.7,376.9,-33.5,32.6,34.0},{1,-2651.9,401.0,-27.5,62.6,34.0},{1,-2598.1,424.9,-25.0,52.3,34.0},{1,-2551.4,451.3,-25.0,37.0,34.0},
		{1,-2491.7,484.1,-25.0,98.9,17.0},{1,-2429.7,509.7,-25.0,35.0,10.2},{2,-2753.5,1027.9,-91.8,34.0,34.0},{2,-2448.9,1777.4,-94.4,34.0,10.2},{2,-2263.8,1925.1,-34.0,34.0,34.0},{2,-1372.3,2327.7,-16.7,34.0,34.0},{2,-417.4,2512.1,-56.0,34.0,10.2},{2,-183.0,2513.0,3.5,34.0,34.0},
		{2,909.8,2378.8,-41.1,34.0,10.2},{2,1098.8,2372.2,-6.6,34.0,34.0},{2,2036.6,2446.6,-53.0,34.0,34.0},{2,2273.9,2433.7,8.0,34.0,34.0},{2,2993.5,2228.0,-26.1,34.0,10.2},{2,2947.1,1987.5,166.2,34.0,10.2},{1,-1952.1,869.4,-178.0,52.3,17.0},{1,-2034.9,863.8,-178.0,98.9,17.0},
		{1,-2133.4,876.1,-178.0,98.8,34.0},{1,-2214.3,877.5,-178.0,63.2,34.0},{1,-2338.7,864.8,175.9,98.9,34.0},{1,-2437.3,857.7,175.9,98.9,34.0},{1,-2495.2,857.1,175.9,16.7,34.0},{1,-2532.4,830.4,127.3,14.9,34.0},{1,-2547.8,818.3,134.8,15.5,34.0},{1,-2758.4,1094.2,-91.8,98.9,34.0},
		{1,-2752.7,1193.3,-91.8,98.8,34.0},{1,-2755.3,1268.8,-91.8,52.3,34.0},{1,-2768.3,1321.9,-118.1,21.5,34.0},{1,-2774.8,1343.0,-109.2,12.8,34.0},{1,-2778.4,1361.3,-103.6,18.8,34.0},{1,-2782.3,1383.2,-93.0,15.3,34.0},{1,-2781.2,1425.0,-77.8,11.3,17.0},{1,-2772.7,1445.4,-67.6,21.8,17.0},
		{1,-2762.9,1466.2,-58.4,14.6,17.0},{1,-2751.1,1480.3,-50.3,13.9,17.0},{1,-2708.1,1521.5,-43.8,98.8,17.0},{1,-2653.5,1574.0,-43.5,52.3,34.0},{1,-2593.4,1630.9,-43.5,98.8,34.0},{1,-2527.7,1705.4,-43.5,98.9,34.0},{1,-2472.5,1747.3,-43.5,39.0,34.0},{1,-2440.9,1809.0,-78.7,13.1,34.0},
		{1,-2210.4,1964.5,-34.0,98.9,34.0},{1,-2128.4,2019.9,-34.0,98.9,34.0},{1,-2068.3,2050.8,-34.0,35.2,34.0},{1,-2038.9,2074.9,-33.9,40.5,34.0},{1,-1994.7,2100.2,-31.2,58.4,34.0},{1,-1946.1,2128.3,-26.4,48.6,34.0},{1,-1811.9,2178.2,-18.6,98.8,34.0},{1,-1736.8,2206.0,-18.4,61.1,34.0},
		{1,-1683.8,2224.8,-18.4,51.2,34.0},{1,-1631.4,2243.6,-18.4,60.3,34.0},{1,-1330.0,2336.1,-16.7,51.8,34.0},{1,-1279.6,2349.4,-16.7,52.3,34.0},{1,-1199.5,2373.3,-16.7,98.8,34.0},{1,-1120.4,2400.4,-16.7,68.4,34.0},{1,-1041.8,2429.7,-16.7,98.9,34.0},{1,-960.5,2446.0,-16.3,65.8,34.0},
		{1,-761.2,2480.3,-4.6,98.8,34.0},{1,-663.2,2496.7,-4.2,98.9,34.0},{1,-564.5,2503.8,-4.2,98.9,34.0},{1,-497.1,2501.6,-4.2,35.3,34.0},{1,-457.3,2506.9,-4.2,44.9,34.0},{1,-394.6,2532.2,-41.2,9.4,34.0},{1,-117.1,2502.9,3.5,98.8,34.0},{1,-43.9,2499.2,3.5,47.6,34.0},
		{1,29.6,2502.7,3.5,98.9,34.0},{1,127.7,2487.8,3.5,98.8,34.0},{1,226.9,2490.5,3.5,98.9,34.0},{1,290.8,2479.2,3.5,30.0,34.0},{1,327.0,2475.3,4.8,41.4,34.0},{1,364.0,2477.3,7.1,29.4,34.0},{1,429.6,2469.5,10.1,98.9,34.0},{1,498.7,2450.1,10.5,43.8,34.0},
		{1,570.1,2443.9,10.5,98.9,34.0},{1,667.4,2426.0,10.5,98.9,34.0},{1,763.0,2399.3,10.5,98.8,34.0},{1,851.6,2384.6,10.5,80.9,34.0},{1,943.4,2390.9,-24.4,17.6,34.0},{1,1164.6,2382.7,-6.6,98.9,34.0},{1,1262.8,2394.2,-6.6,98.9,34.0},{1,1362.0,2396.8,-6.6,98.8,34.0},
		{1,1460.1,2408.3,-6.6,98.8,34.0},{1,1535.0,2420.2,-6.6,52.9,34.0},{1,1578.6,2427.2,-4.8,33.2,34.0},{1,1646.0,2425.3,-2.6,98.8,34.0},{1,1745.0,2429.4,-2.1,98.8,34.0},{1,1843.5,2441.7,-2.1,98.9,34.0},{1,1909.7,2441.0,-2.1,33.4,34.0},{1,1940.7,2441.1,-2.1,28.6,34.0},
		{1,1970.5,2439.9,-2.1,31.0,34.0},{1,2063.7,2464.4,-37.5,12.7,34.0},{1,2340.1,2427.1,8.0,98.9,34.0},{1,2436.8,2404.7,8.0,98.8,34.0},{1,2499.6,2396.1,8.0,28.1,34.0},{1,2548.2,2389.3,8.4,69.7,34.0},{1,2609.6,2382.9,10.8,50.9,34.0},{1,2650.5,2372.5,15.9,28.0,34.0},
		{1,2741.3,2340.4,22.2,31.2,34.0},{1,2804.9,2319.7,24.9,98.9,34.0},{1,2890.9,2269.6,25.4,98.8,34.0},{1,2955.1,2239.3,25.4,43.2,34.0},{1,3028.8,2232.8,-9.4,17.7,34.0},{1,2965.1,1968.5,-146.8,11.8,25.5},{1,2903.4,1982.9,166.2,53.1,34.0},{1,2829.6,1964.8,166.2,98.8,34.0},
		{1,2733.7,1941.2,166.2,98.8,34.0},{1,2660.3,1923.0,166.2,52.3,34.0},{1,2611.8,1909.8,166.2,35.8,34.0},{1,2563.6,1893.6,155.3,15.1,34.0},{1,2537.7,1873.4,140.4,12.8,34.0},{1,2519.2,1856.0,126.6,14.0,34.0},{1,2482.7,1769.5,114.8,98.9,34.0},{1,2452.2,1693.3,115.5,64.1,34.0},
		{1,2409.0,1632.4,115.5,63.8,34.0},{1,2388.1,1586.0,115.5,38.0,34.0},{1,2365.2,1521.1,115.5,98.9,34.0},{1,2322.7,1431.8,115.5,98.9,34.0},{1,2272.3,1346.3,115.5,98.8,34.0},{1,2240.0,1278.0,115.5,52.3,34.0},{1,2218.2,1230.0,116.2,33.8,34.0},{1,2190.4,1166.5,121.0,98.9,34.0},
		{1,2152.2,1094.3,121.0,64.1,34.0},{1,2105.2,1040.0,121.0,61.5,34.0},{1,2085.6,999.2,121.0,28.2,34.0},{1,2069.8,976.3,128.3,19.3,34.0},{1,2051.1,962.4,137.8,16.3,34.0},{1,2036.5,949.7,143.6,16.5,34.0},{1,2019.5,939.1,150.7,16.4,34.0},{1,2000.4,927.6,159.8,18.5,34.0},
		{1,1941.5,913.0,163.3,98.7,34.0},{2,1821.1,576.1,90.0,24.3,14.0},{2,2120.1,591.0,4.4,71.0,14.0},{2,2189.9,589.8,4.4,68.5,14.0},{2,2270.3,573.8,4.4,94.2,14.0},{2,2359.9,567.6,4.4,85.4,14.0},{2,2439.4,565.2,4.4,73.4,14.0},{2,2521.0,562.3,4.4,89.8,14.0},
		{2,2633.4,609.5,-26.7,89.5,14.0},{2,2691.4,665.2,-38.8,39.3,14.0},{2,2733.5,699.9,-49.9,49.7,14.0},{2,2810.6,807.3,-53.5,47.2,14.0},{2,2763.2,868.1,-127.1,20.8,14.0},{2,2755.6,906.2,-122.9,38.4,14.0},{2,2734.1,944.9,-116.3,33.2,14.0},{2,2710.7,974.0,-111.4,25.5,14.0},
		{2,2730.6,1014.2,-106.7,26.8,14.0},{2,2698.3,1039.8,-102.2,28.8,14.0},{2,2710.6,1173.3,-92.3,81.3,7.0},{2,2725.9,1360.1,-82.1,85.1,7.0},{2,2259.7,613.0,-43.0,48,42},{2,2326.3,614.9,-43.0,48,42},{2,2362.9,649.0,-43.0,48,42},{3,2392.9,616.8,-43.0,48,42},
		{2,2399.4,683.1,-43.0,48,42},{3,2429.4,650.9,-43.0,48,42},{2,2459.5,618.7,-43.0,48,42},{2,2436.0,717.2,-43.0,48,42},{3,2466.0,685.0,-43.0,48,42},{2,2496.0,652.8,-43.0,48,42},{3,2526.0,620.6,-43.0,48,42},{2,2472.6,751.3,-43.0,48,42},
		{2,2502.6,719.1,-43.0,48,42},
	},
	walls = {
	},
	trees = {
	},
}
]])
put(folder4, "ModuleScript", "LondonFillData2", [[
--!nocheck
-- Part 2 of the data in LondonFill. MADE BY tools/london_fill.py: don't edit by hand.
return {
	buildings = {
	},
	gardens = {
		{2,2532.6,686.9,-43.0,48,42},{3,2562.6,654.7,-43.0,48,42},{3,2592.6,622.5,-43.0,48,42},{3,2509.2,785.3,-43.0,48,42},{3,2539.2,753.2,-43.0,48,42},{3,2569.2,721.0,-43.0,48,42},{2,2599.2,688.8,-43.0,48,42},{3,2629.2,656.6,-43.0,48,42},
		{2,2545.7,819.4,-43.0,48,42},{2,2575.7,787.3,-43.0,48,42},{3,2605.7,755.1,-43.0,48,42},{3,2635.7,722.9,-43.0,48,42},{3,2665.7,690.7,-43.0,48,42},{3,2582.3,853.5,-43.0,48,42},{3,2612.3,821.4,-43.0,48,42},{2,2642.3,789.2,-43.0,48,42},
		{2,2672.3,757.0,-43.0,48,42},{2,2702.3,724.8,-43.0,48,42},{2,2618.9,887.6,-43.0,48,42},{3,2648.9,855.5,-43.0,48,42},{2,2678.9,823.3,-43.0,48,42},{2,2708.9,791.1,-43.0,48,42},{2,2738.9,758.9,-43.0,48,42},{3,2655.4,921.7,-43.0,48,42},
		{3,2685.5,889.5,-43.0,48,42},{3,2715.5,857.4,-43.0,48,42},{3,2745.5,825.2,-43.0,48,42},{2,2775.5,793.0,-43.0,48,42},{2,-197.1,2312.6,133.5,34.0,10.2},{2,230.3,2286.4,-176.5,39.5,25.5},{1,192.8,2294.3,-176.5,36.3,34.0},{1,143.3,2297.1,-176.5,63.0,34.0},
		{2,80.2,2293.5,-176.5,62.5,34.0},{1,-0.3,2298.6,-176.5,98.9,34.0},{1,-81.4,2311.3,-176.5,64.4,34.0},{2,-132.1,2308.9,-176.5,36.6,34.0},{1,-164.3,2311.8,-176.5,28.0,34.0},{1,-189.0,2267.4,79.1,14.7,17.0},{2,-184.1,2240.3,79.1,40.5,34.0},{1,-43.1,2206.8,1.8,60.5,34.0},
		{1,12.4,2203.8,1.8,50.6,34.0},{1,71.2,2205.9,-12.2,12.6,34.0},{1,154.6,2228.7,-18.5,98.8,17.0},{2,374.1,2161.0,161.5,34.0,34.0},{1,-145.2,2039.8,79.1,14.7,34.0},{2,-142.7,2017.5,79.1,29.8,34.0},{1,-140.4,1981.9,79.1,41.1,34.0},{1,-94.7,1941.1,2.3,52.8,17.0},
		{1,-19.0,1937.9,2.3,98.8,34.0},{1,79.7,1933.9,2.3,98.8,34.0},{1,145.6,1931.4,2.3,33.0,34.0},{1,168.0,1933.9,2.3,11.5,34.0},{1,295.7,1958.5,-14.0,98.8,34.0},{1,389.5,1990.8,-14.0,98.9,34.0},{1,404.3,2110.0,-117.7,38.2,34.0},{1,309.2,2145.5,161.5,98.8,34.0},
		{1,218.3,2105.8,161.5,98.9,34.0},{1,146.9,2089.8,161.7,46.3,34.0},{1,108.9,2077.8,166.8,28.1,34.0},{1,5.7,2065.7,-178.7,98.9,34.0},{1,-93.4,2068.3,-178.3,98.9,10.2},{1,-158.8,2077.7,-178.3,32.2,25.5},{2,-239.1,1487.0,-95.7,34.0,17.0},{1,-880.2,1551.4,4.8,67.0,25.5},
		{1,-830.3,1544.9,4.8,33.6,34.0},{2,-794.2,1543.2,4.8,38.6,34.0},{1,-749.3,1539.8,4.8,51.5,34.0},{1,-692.0,1540.8,5.0,62.3,34.0},{2,-627.8,1528.7,5.2,67.5,34.0},{1,-580.0,1523.1,5.2,28.7,34.0},{1,-516.0,1522.4,5.2,98.9,34.0},{2,-441.5,1511.0,5.2,51.6,34.0},
		{1,-397.0,1502.8,5.2,38.5,34.0},{1,-362.9,1506.4,5.2,28.8,34.0},{2,-330.7,1504.6,5.2,35.8,34.0},{1,-305.7,1500.7,5.2,14.7,34.0},{2,-279.9,1495.6,5.2,37.6,34.0},{1,-241.7,1511.2,-95.7,14.7,17.0},{1,-243.2,1525.9,-95.7,14.7,10.2},{1,-247.6,1542.5,-95.7,19.4,34.0},
		{1,-246.6,1559.8,-95.7,14.7,34.0},{1,-243.3,1588.1,-95.7,41.1,34.0},{1,-247.4,1629.0,-95.7,41.1,10.2},{2,-307.2,2016.5,-100.7,35.6,34.0},{1,-309.1,2041.8,-100.7,14.7,34.0},{2,-311.3,2059.8,-100.7,21.5,34.0},{1,-370.6,2082.0,-179.9,98.8,10.2},{1,-469.6,2073.3,-179.9,98.9,34.0},
		{1,-548.0,2078.7,-179.9,57.9,34.0},{1,-718.9,2050.6,167.4,98.9,34.0},{1,-815.4,2028.9,167.4,98.9,34.0},{1,-889.6,2016.5,167.4,51.3,34.0},{1,-906.7,1953.5,79.5,27.1,34.0},{1,-899.5,1828.8,87.9,98.8,34.0},{1,-896.0,1730.1,87.9,98.8,34.0},{1,-892.4,1631.3,87.9,98.8,34.0},
		{2,-8.1,1161.5,-138.8,34.0,34.0},{2,-139.6,1275.5,171.0,34.0,10.2},{2,-202.4,1230.0,135.0,58.9,34.0},{1,-226.2,1201.8,135.0,14.7,34.0},{1,-236.6,1191.4,135.0,14.7,34.0},{1,-246.8,1177.5,135.0,19.4,34.0},{1,-191.7,1125.6,12.1,43.4,34.0},{1,-97.9,1111.5,3.2,98.8,34.0},
		{1,-38.3,1181.4,-138.8,37.5,34.0},{1,-88.1,1227.9,-138.8,98.9,34.0},{2,22.7,958.4,-176.9,46.0,20.0},{2,-348.1,1008.2,82.9,60.0,10.0},{2,-341.4,829.7,-0.0,38.5,20.0},{2,-296.7,806.8,-0.0,51.0,20.0},{2,-245.4,831.2,-0.0,51.6,20.0},{2,-199.1,815.2,0.1,40.9,20.0},
		{2,-64.5,814.9,7.1,83.4,20.0},{2,-6.8,817.1,-79.8,28.7,15.0},{2,-30.9,862.0,-79.8,51.3,20.0},{2,-43.9,958.0,-176.9,86.9,20.0},{2,-102.5,966.3,-176.9,31.1,20.0},{2,-245.5,979.6,-167.6,54.1,20.0},{2,-303.4,984.8,-167.6,61.1,10.0},{3,-337.6,896.5,-175.4,48,42},
		{2,-334.1,940.4,-175.4,48,42},{2,-284.2,936.4,-175.4,48,42},{3,-234.4,932.3,-175.4,48,42},{2,-188.1,884.5,-175.4,48,42},{2,-184.6,928.3,-175.4,48,42},{3,-181.0,972.2,-175.4,48,42},{3,-141.8,836.6,-175.4,48,42},{2,-138.3,880.4,-175.4,48,42},
		{3,-134.7,924.3,-175.4,48,42},{2,-84.9,920.3,-175.4,48,42},{2,371.4,568.3,-173.0,67.5,6.0},{2,323.6,567.1,-173.0,27.0,6.0},{2,166.3,574.5,-173.0,46.3,10.0},{2,130.9,599.4,-173.0,30.1,20.0},{2,72.0,577.4,-173.0,81.5,6.0},{2,-13.3,599.8,-173.0,93.1,20.0},
		{2,-101.9,606.5,-173.0,84.6,20.0},{2,-214.3,609.0,-179.8,59.6,20.0},{2,-283.5,590.6,-179.8,78.6,10.0},{2,-351.6,595.9,-179.8,57.5,6.0},{2,-27.7,168.0,-179.5,23.8,10.2},{1,-176.7,170.6,100.6,64.1,34.0},{1,-201.6,109.2,100.6,52.3,34.0},{1,-212.9,28.7,96.0,98.7,34.0},
		{1,-178.2,-74.6,2.3,14.7,34.0},{1,-163.5,-75.2,2.3,14.7,34.0},{2,-136.2,-79.1,2.3,40.1,34.0},{1,-84.5,-43.3,-83.0,64.1,25.5},{1,-63.3,21.5,-83.0,52.3,34.0},{1,-52.1,104.2,-82.1,98.8,34.0},{2,-164.3,-400.5,-0.5,44.0,22.0},{2,-67.4,-239.6,-177.7,14.7,22.0},
		{2,-82.1,-239.0,-177.7,14.7,22.0},{2,-112.0,-235.3,-177.7,45.4,22.0},{2,-142.2,-236.6,-177.7,14.7,22.0},{2,-156.8,-236.0,-177.7,14.7,22.0},{2,-171.5,-235.4,-177.7,14.7,22.0},{2,-213.8,-293.4,81.5,22.5,22.0},{2,-111.6,-409.2,-0.5,61.1,22.0},{2,-67.8,-412.0,-0.5,26.5,22.0},
		{2,-117.0,-333.5,-98.1,20.2,22.0},{2,78.5,-398.6,-0.4,44.0,22.0},{2,128.1,-357.8,-93.9,37.5,22.0},{2,134.2,-323.2,-93.9,30.8,22.0},{2,119.7,-285.1,-93.9,47.1,22.0},{2,109.2,-246.7,-177.7,14.7,11.0},{2,94.6,-246.1,-177.7,14.7,16.5},{2,79.9,-245.5,-177.7,14.7,22.0},
		{2,64.2,-245.2,-177.7,16.7,6.6},{2,58.5,-267.3,92.0,26.4,11.0},{2,43.3,-313.9,81.7,14.8,22.0},{2,116.3,-385.1,-0.4,31.8,6.6},{2,439.3,-307.4,-173.2,64.1,14.0},{2,372.1,-294.0,-173.2,72.4,14.0},{2,307.5,-330.7,86.1,63.0,14.0},{2,318.1,-390.0,86.1,56.6,14.0},
		{2,358.5,-672.0,86.1,71.5,14.0},{2,336.9,-740.8,86.1,62.9,14.0},{2,371.5,-750.5,-14.0,38.2,7.0},{2,424.6,-355.4,-86.4,47.9,14.0},{2,374.4,-948.4,80.5,60.4,10.5},{2,838.3,-736.2,-17.7,88.4,10.5},{2,418.8,-1388.6,19.7,56.0,7.0},{2,470.2,-1428.4,3.1,56.0,14.0},
		{2,1208.9,-1387.1,-117.1,56.0,14.0},{2,1019.3,-867.3,162.4,47.6,14.0},{2,413.7,-1103.1,80.5,57.2,14.0},{2,391.2,-1159.8,80.5,47.3,14.0},{2,396.9,-1215.6,81.3,63.0,14.0},{2,406.7,-1286.7,81.4,80.1,14.0},{2,410.5,-1348.1,81.4,42.6,14.0},{2,545.2,-1433.6,3.1,94.3,14.0},
		{2,625.4,-1447.5,3.1,67.2,14.0},{2,683.0,-1435.1,3.1,46.6,14.0},{2,733.3,-1435.1,3.1,53.9,14.0},{2,800.0,-1418.0,3.1,77.3,14.0},{2,918.7,-1427.6,-11.8,67.9,14.0},{2,1024.4,-1420.4,-13.7,93.2,14.0},{2,1098.7,-1399.4,-13.7,61.1,14.0},{2,1146.6,-1389.0,-13.7,37.0,14.0},
		{2,1188.2,-1339.7,-117.1,47.2,14.0},{2,1143.9,-1285.3,-117.1,90.0,14.0},{2,1092.8,-1234.0,-117.1,48.0,14.0},{2,1073.2,-1173.5,-117.1,77.5,14.0},{2,1067.4,-1102.1,-117.1,54.9,14.0},{2,1048.4,-1057.1,-114.4,37.8,14.0},{2,1027.0,-1017.7,-108.3,40.2,14.0},{2,1000.9,-976.8,-104.3,44.2,14.0},
		{2,995.1,-939.1,-104.0,31.1,14.0},{2,910.8,-930.9,162.4,87.1,14.0},{2,828.1,-930.7,162.4,70.4,14.0},{2,767.8,-970.6,162.4,68.5,14.0},{2,622.5,-1011.7,154.1,55.5,14.0},{2,565.8,-1027.2,154.1,60.2,14.0},{2,522.8,-1080.9,154.1,64.1,14.0},{2,461.5,-1089.4,154.1,53.5,14.0},
		{1,680.6,-1636.3,-176.9,41.7,34.0},{1,610.9,-1624.4,-176.9,98.8,34.0},{2,528.9,-1625.6,-176.9,64.9,34.0},{1,481.1,-1623.2,-176.9,30.7,34.0},{1,438.0,-1665.9,84.3,41.1,25.5},{1,470.8,-1711.8,10.6,35.3,17.0},{1,546.9,-1718.1,10.6,98.9,34.0},{1,616.5,-1735.9,10.6,44.6,34.0},
		{2,362.5,-2072.1,40.3,34.0,34.0},{2,1165.8,-2187.8,-36.4,34.0,34.0},{2,1258.7,-2165.0,-55.5,34.0,10.2},{1,1278.3,-2012.2,-169.4,64.1,34.0},{1,1192.2,-1991.5,-169.4,98.9,34.0},{1,1119.5,-1969.0,-169.4,52.3,34.0},{1,1036.9,-1953.3,-169.4,98.8,34.0},{1,939.8,-1935.1,-169.4,98.8,34.0},
		{1,841.0,-1925.6,-169.4,98.9,34.0},{1,743.8,-1907.3,-169.4,98.9,34.0},{1,673.3,-1889.5,-169.4,46.3,34.0},{1,602.7,-1871.8,-169.4,98.8,34.0},{1,505.6,-1853.6,-169.4,98.8,34.0},{1,442.5,-1844.2,-169.4,28.9,34.0},{1,417.4,-1893.0,101.6,14.7,34.0},{2,411.2,-1919.3,101.6,39.4,34.0},
		{1,385.9,-1987.3,108.0,98.2,34.0},{2,382.6,-2091.6,51.3,8.7,34.0},{1,520.9,-2088.5,2.3,50.0,34.0},{2,560.2,-2094.7,2.3,28.8,34.0},{1,582.0,-2092.8,2.3,14.7,34.0},{1,611.0,-2095.6,2.3,43.5,34.0},{1,640.2,-2095.2,2.3,14.7,34.0},{1,667.8,-2102.4,2.3,41.2,34.0},
		{1,709.9,-2105.0,4.2,41.1,34.0},{1,738.6,-2100.9,5.0,14.7,34.0},{2,761.1,-2104.3,6.8,28.7,34.0},{2,803.3,-2108.6,10.3,51.7,34.0},{1,878.6,-2123.1,12.4,98.9,34.0},{1,933.4,-2137.8,12.4,14.7,34.0},{1,947.8,-2140.9,12.4,14.7,34.0},{1,979.0,-2151.2,12.4,50.6,34.0},
		{1,1014.5,-2152.9,12.4,19.4,34.0},{1,1042.1,-2168.1,12.4,41.1,34.0},{1,1077.0,-2169.9,12.4,27.7,34.0},{2,1108.3,-2179.0,12.4,37.3,34.0},{2,1234.2,-2162.1,-5.8,11.5,34.0},{1,1272.3,-2144.8,-55.5,14.7,34.0},{1,-1535.8,2058.3,161.6,64.1,50.0},{1,-1596.8,2051.9,161.6,41.1,50.0},
		{2,-1633.3,2031.7,161.6,41.1,50.0},{1,-1660.3,2024.2,161.6,14.7,50.0},{2,-1678.7,2016.7,161.6,24.9,50.0},{1,-1698.3,1902.1,102.6,37.9,50.0},{1,-1707.8,1864.0,108.4,33.4,50.0},{1,-1724.1,1837.2,109.4,26.9,50.0},{1,-1730.6,1781.7,109.4,64.1,50.0},{1,-1643.9,1709.0,19.8,52.3,50.0},
		{1,-1602.4,1700.5,19.8,14.7,50.0},{2,-1578.3,1693.7,19.8,35.2,25.0},{1,-1544.8,1797.6,-67.0,35.5,50.0},{1,-1533.6,1843.9,-72.7,41.3,50.0},{1,-1506.5,1919.7,-76.2,52.3,50.0},{1,-1492.1,1978.7,-76.2,52.3,25.0},{1,-1519.5,1479.7,-160.3,64.1,25.0},{1,-1573.6,1513.2,-160.3,41.1,50.0},
		{2,-1616.9,1521.6,-160.3,46.0,50.0},{1,-1661.0,1544.3,-160.3,52.3,50.0},{2,-1719.7,1559.8,-160.3,52.6,50.0},{1,-1751.6,1570.4,-160.3,14.7,50.0},{1,-1781.2,1587.4,-160.3,52.3,50.0},{2,-1825.1,1597.0,-165.1,30.2,50.0},{1,-1911.1,1619.9,-168.6,52.3,50.0},{2,-1969.8,1629.1,-168.6,51.1,50.0},
		{1,-2020.0,1641.9,-168.6,52.3,50.0},{1,-2073.1,1652.8,-168.6,41.1,50.0},{2,-2118.0,1655.4,-168.6,47.8,50.0},{2,-2162.5,1666.9,-168.6,44.1,50.0},{1,-2191.8,1670.4,-168.6,14.7,50.0},{2,-2207.9,1672.8,-168.6,17.8,15.0},{2,-2226.3,1652.8,149.8,15.4,25.0},{2,-2285.5,1630.3,174.9,22.3,50.0},
		{1,-2312.4,1629.2,-175.4,19.4,50.0},{1,-2365.8,1587.5,136.5,52.3,25.0},{1,-2405.3,1532.0,136.5,64.1,50.0},{2,-2464.1,1488.6,136.5,63.6,50.0},{1,-2491.2,1460.2,136.5,14.7,50.0},{1,-2501.8,1450.1,136.5,14.7,37.5},{1,-2512.5,1440.0,136.5,14.7,37.5},{1,-2399.9,1416.1,-3.1,52.3,37.5},
		{1,-2341.3,1419.3,-3.1,52.3,50.0},{1,-2281.3,1422.6,-3.1,52.3,50.0},{1,-2237.3,1425.8,-3.1,17.8,50.0},{1,-2207.9,1427.5,-3.1,26.9,50.0},{1,-2155.6,1429.5,-3.1,52.3,50.0},{1,-2105.7,1433.1,-3.1,35.3,50.0},{1,-2051.9,1430.9,4.2,52.3,50.0},{1,-1990.4,1426.4,4.2,52.3,50.0},
		{1,-1923.0,1434.6,4.2,64.1,50.0},{1,-1866.4,1418.0,4.2,35.3,50.0},{1,-1814.2,1413.4,4.2,52.3,50.0},{1,-1770.0,1409.8,4.2,24.2,50.0},{1,-1723.3,1406.7,4.2,52.3,50.0},{1,-1678.1,1403.0,4.2,24.2,50.0},{1,-1639.2,1404.7,4.2,34.9,50.0},{1,-1587.2,1396.6,4.2,52.3,50.0},
		{1,-1537.5,1414.3,-39.8,14.7,25.0},{1,-1526.2,1423.7,-39.8,14.7,37.5},{1,-1514.9,1433.1,-39.8,14.7,15.0},{2,-1444.4,1265.4,93.9,34.0,34.0},{2,-1075.1,1140.1,-80.8,28.9,10.2},{2,-1014.7,1389.9,-175.2,28.9,10.2},{1,-1266.8,1415.4,140.2,14.7,34.0},{1,-1292.3,1402.3,140.2,41.1,34.0},
		{1,-1309.7,1379.7,140.2,14.7,34.0},{1,-1321.0,1370.3,140.2,14.7,34.0},{1,-1343.2,1353.8,140.2,40.4,34.0},{2,-1380.8,1316.0,140.2,65.9,34.0},{1,-1397.3,1217.6,5.1,98.9,25.5},{1,-1320.6,1202.0,5.1,56.8,34.0},{1,-1274.2,1198.3,5.7,35.5,34.0},{1,-1203.0,1192.5,13.1,98.9,34.0},
		{1,-1128.0,1167.4,13.1,58.6,34.0},{1,-1054.2,1231.6,-80.8,98.8,25.5},{1,-1044.4,1297.9,-80.8,35.3,34.0},{1,-1041.8,1345.1,-80.8,44.3,34.0},{1,-1142.4,1406.6,-175.2,98.8,34.0},{2,-1207.1,1404.0,-175.2,29.5,34.0},{2,-836.3,825.2,-47.4,46.0,6.0},{2,-918.3,1071.9,100.9,69.6,10.0},
		{2,-940.0,1015.0,101.0,50.1,20.0},{2,-969.4,966.5,101.0,56.4,20.0},{2,-955.8,918.5,101.0,32.7,20.0},{2,-981.2,884.0,101.0,44.7,10.0},{2,-944.3,867.6,12.4,52.9,20.0},{2,-904.5,837.7,12.4,37.7,20.0},{2,-871.7,822.7,12.4,32.6,20.0},{2,-809.7,864.3,-47.4,47.4,20.0},
		{2,-766.7,882.7,-47.4,38.0,20.0},{2,-747.0,923.3,-47.4,48.5,20.0},{2,-742.0,992.5,-47.4,60.1,20.0},{2,-659.4,1017.0,-47.4,87.8,20.0},{2,-802.0,1057.0,-158.1,46.5,20.0},{2,-860.2,1086.5,-157.1,81.9,20.0},{2,-861.9,1010.4,13.9,48,42},{2,-872.5,967.7,13.9,48,42},
		{3,-883.1,925.0,13.9,48,42},{3,-893.7,882.3,13.9,48,42},{3,-823.9,955.7,13.9,48,42},{2,-834.5,913.0,13.9,48,42},{1,-1760.4,585.2,43.8,14.8,34.0},{1,-1695.1,535.7,36.1,57.3,34.0},{1,-1645.7,505.0,36.1,58.7,34.0},{1,-1610.1,469.2,36.1,41.1,34.0},
		{2,-1521.6,418.8,25.3,52.4,34.0},{2,-1441.9,395.4,11.5,26.2,34.0},{1,-1422.6,389.6,10.8,14.7,17.0},{2,-1358.3,383.1,-0.7,51.3,34.0},{2,-863.1,224.2,176.7,42.5,20.0},{2,-902.4,-23.7,-57.6,50.0,10.0},{2,-874.3,41.2,-90.0,62.3,20.0},{2,-909.9,87.8,-90.0,31.0,20.0},
		{2,-882.8,116.7,-90.0,26.7,20.0},{2,-894.9,158.9,-90.0,57.6,20.0},{2,-946.0,214.8,176.7,33.2,20.0},{2,-981.7,227.8,176.7,36.8,20.0},{2,-1584.4,260.6,-156.0,31.6,15.0},{2,-1627.2,258.5,-152.4,38.1,10.0},{2,-1668.2,289.5,-146.7,53.9,20.0},{2,-1703.8,315.3,-143.9,29.6,20.0},
		{2,-1732.6,327.9,-143.9,31.6,20.0},{2,-1755.5,353.5,-143.9,35.5,20.0},{2,-1798.5,312.8,95.0,60.3,20.0},{2,-1794.4,267.6,95.0,29.1,20.0},{2,-1798.7,134.5,85.2,53.1,6.0},{2,-1797.7,93.8,85.2,28.2,6.0},{2,-1674.2,-78.2,-3.4,61.2,6.0},{2,-992.9,-43.6,-2.1,34.2,20.0},
		{2,-960.4,-22.5,-2.1,32.2,20.0},{2,-934.8,-25.4,-2.1,18.9,20.0},{2,-1074.1,-207.3,117.1,50.0,6.0},{2,-910.6,-190.4,-126.0,12.6,15.0},{2,-946.4,-198.5,177.9,37.4,10.0},{2,-999.4,-216.2,177.9,69.9,20.0},{2,-1044.9,-213.8,177.9,20.9,20.0},{2,-1086.4,-247.4,117.1,32.7,20.0},
		{2,-1106.7,-313.1,102.6,14.8,20.0},{2,-1134.8,-351.2,91.0,39.3,20.0},{2,-1140.3,-383.5,90.9,25.6,20.0},{2,-1087.4,-416.8,17.3,58.2,20.0},{2,-1048.2,-437.7,17.3,29.1,20.0},{2,-1019.2,-434.2,17.3,24.3,20.0},{2,-995.2,-420.5,-73.1,57.9,6.0},{2,-972.6,-373.9,-73.1,44.7,20.0},
		{2,-959.8,-340.0,-73.1,27.5,20.0},{2,-957.0,-292.4,-70.8,61.7,20.0},{2,-719.7,-550.9,-100.6,22.2,20.0},{2,-736.5,-504.5,-111.3,62.2,20.0},{2,-761.6,-463.3,-111.3,32.7,20.0},{2,-764.8,-415.9,-111.3,57.9,20.0},{2,-805.6,-457.0,106.9,60.8,15.0},{2,-854.1,-491.8,106.9,34.0,20.0},
		{2,-832.2,-533.6,106.9,33.3,20.0},{2,-850.0,-565.1,106.9,37.3,20.0},{2,-881.9,-585.1,111.8,13.9,6.0},{2,-664.3,-771.1,178.4,44.0,6.0},{2,-995.7,-761.6,122.2,46.5,15.0},{2,-1031.8,-835.7,110.5,55.7,20.0},{2,-1010.6,-862.7,-2.9,14.7,6.0},{2,-996.0,-862.0,-2.9,14.7,20.0},
		{2,-981.3,-861.2,-2.9,14.7,20.0},{2,-966.6,-860.5,-2.9,14.7,20.0},{2,-931.5,-862.8,-2.9,55.2,20.0},{2,-894.6,-854.2,-2.9,19.4,20.0},{2,-875.8,-856.4,-0.1,14.7,20.0},{2,-861.0,-856.4,-0.0,14.7,20.0},{2,-834.4,-854.2,0.3,38.1,20.0},{2,-806.5,-857.0,2.9,14.7,20.0},
		{2,-791.8,-857.7,2.9,14.7,20.0},{2,-777.2,-858.5,2.9,14.7,20.0},{2,-762.5,-859.2,2.9,14.7,20.0},{2,-747.8,-860.0,2.9,14.7,20.0},{2,-724.2,-860.0,2.9,32.3,20.0},{2,-700.9,-862.4,2.9,14.7,20.0},{2,-675.1,-861.0,2.9,36.6,20.0},{2,-666.6,-789.2,-100.6,14.7,20.0},
		{2,-709.7,-761.7,178.4,46.2,20.0},{2,-750.5,-760.1,178.4,35.4,20.0},{2,-775.5,-764.4,178.4,14.7,20.0},{2,-803.6,-759.0,178.4,41.2,20.0},{2,-840.5,-788.3,-178.5,27.9,20.0},{2,-861.3,-764.8,-178.2,14.7,20.0},{2,-903.4,-788.9,-178.2,67.9,20.0},{2,-952.8,-760.2,-178.2,32.6,20.0},
		{2,-682.3,-1462.7,-87.8,44.0,6.0},{2,-1068.9,-1066.1,84.3,41.2,20.0},{2,-1064.8,-1107.0,84.3,41.2,20.0},{2,-1056.1,-1143.3,84.3,32.8,20.0},{2,-1049.4,-1182.2,84.3,45.9,20.0},{2,-1043.1,-1233.4,84.9,56.4,20.0},{2,-1043.3,-1269.5,85.7,14.7,20.0},{2,-1047.4,-1297.9,85.7,41.1,20.0},
		{2,-1035.9,-1341.3,85.7,47.3,20.0},{2,-1040.8,-1386.0,85.7,41.1,20.0},{2,-1012.9,-1413.1,85.7,17.0,20.0},{2,-991.5,-1437.5,2.3,51.5,15.0},{2,-945.5,-1446.1,2.3,41.1,20.0},{2,-906.1,-1443.2,2.3,37.4,20.0},{2,-860.1,-1447.4,2.3,54.9,20.0},{2,-810.6,-1443.4,2.3,43.9,20.0},
		{2,-781.3,-1446.5,2.3,14.7,20.0},{2,-751.9,-1451.4,2.3,44.5,20.0},{2,-709.2,-1455.5,2.3,41.1,15.0},{2,-694.1,-1418.2,-87.8,44.0,20.0},{2,-669.8,-1389.8,-87.8,14.7,20.0},{2,-662.6,-1362.1,-87.8,41.2,20.0},{2,-667.6,-1334.0,-87.8,14.7,20.0},{2,-667.1,-1319.3,-87.8,14.7,20.0},
		{2,-679.4,-1298.2,-87.8,26.4,20.0},{2,-680.6,-1266.9,-87.8,36.1,20.0},{2,-656.6,-1228.2,-85.7,41.1,20.0},{2,-660.4,-1199.1,-84.3,14.7,20.0},{2,-654.4,-1167.6,-84.3,49.2,20.0},{2,-657.4,-1118.8,-84.3,47.3,20.0},{2,-647.0,-1078.4,-84.3,35.3,20.0},{2,-716.9,-1022.2,-177.0,14.7,20.0},
		{2,-747.5,-1020.3,-177.0,46.5,20.0},{2,-778.1,-1019.1,-177.0,14.7,20.0},{2,-792.8,-1018.3,-177.0,14.7,20.0},{2,-872.8,-1019.5,179.5,19.4,20.0},{2,-916.1,-1018.6,177.1,14.7,20.0},{2,-944.3,-1013.9,177.1,41.2,20.0},{2,-985.4,-1015.9,177.1,41.1,20.0},{2,-1013.0,-1023.5,177.1,14.7,20.0},
		{2,-1041.1,-1018.7,177.1,41.1,20.0},{2,-1788.0,-1619.5,102.3,34.0,25.5},{2,-1711.8,-2023.0,19.6,34.0,25.5},{2,-1005.9,-2155.1,-48.9,34.0,10.2},{2,-888.9,-2115.3,-54.9,34.0,17.0},{2,-732.2,-1619.5,-177.7,67.8,34.0},{1,-798.5,-1612.1,-177.7,65.3,34.0},{1,-851.7,-1610.0,-177.7,41.1,34.0},
		{1,-892.8,-1608.5,-177.7,41.2,34.0},{1,-963.2,-1614.4,-177.7,98.9,34.0},{1,-1061.7,-1610.7,-178.1,98.9,34.0},{2,-1157.6,-1606.7,178.5,43.0,34.0},{1,-1801.7,-1655.0,102.3,41.2,34.0},{1,-1799.6,-1686.5,102.3,19.4,34.0},{1,-1805.9,-1702.6,102.3,14.7,34.0},{2,-1814.7,-1740.6,102.3,63.2,34.0},
		{2,-1829.5,-1788.8,106.2,33.2,34.0},{2,-1817.8,-1856.7,76.0,46.5,34.0},{2,-1801.8,-1902.0,76.0,49.1,34.0},{1,-1669.5,-2037.7,19.6,55.5,34.0},{1,-1598.9,-2069.5,19.6,98.8,34.0},{1,-1531.5,-2089.3,19.6,41.4,34.0},{2,-1479.8,-2103.5,19.4,65.8,34.0},{1,-1390.7,-2131.9,10.9,14.7,34.0},
		{2,-1371.0,-2137.8,10.9,26.3,34.0},{1,-1319.2,-2139.4,5.2,19.4,34.0},{1,-1194.4,-2145.3,2.3,98.9,34.0},{1,-1124.8,-2156.9,2.3,41.1,34.0},{1,-1096.6,-2151.8,2.3,14.7,34.0},{2,-1056.8,-2155.7,2.3,65.3,34.0},{2,-975.5,-2135.2,-31.9,19.0,34.0},{1,-938.8,-2116.2,-15.0,14.7,34.0},
		{2,-920.8,-2113.7,-7.7,12.8,34.0},{1,-864.3,-2080.6,-55.7,52.1,10.2},{1,-799.4,-1988.9,-58.0,98.8,34.0},{2,-769.5,-1905.3,-73.4,65.1,34.0},{2,-751.8,-1844.7,-73.4,61.1,34.0},{2,-738.2,-1801.7,-73.4,29.2,34.0},{1,-720.7,-1770.2,-73.4,41.1,34.0},{2,-708.2,-1691.9,-79.5,57.6,34.0},
		{1,-2567.0,1275.8,88.2,52.3,15.0},{1,-2565.4,1222.9,88.2,41.2,50.0},{1,-2563.8,1176.1,88.2,52.3,50.0},{1,-2556.5,1133.0,88.2,14.7,50.0},{2,-2553.4,1102.2,88.2,46.9,50.0},{2,-2552.1,1048.0,88.2,61.5,50.0},{2,-2520.8,998.6,58.3,24.1,15.0},{1,-2454.1,1010.1,-4.3,14.7,50.0},
		{1,-2420.2,1006.6,-4.3,52.3,50.0},{1,-2370.6,1011.1,-4.3,35.3,50.0},{2,-2318.5,1019.4,-4.3,57.5,50.0},{2,-2193.3,1019.6,2.0,50.4,50.0},{1,-2142.1,1014.6,2.0,52.3,50.0},{1,-2100.4,1019.2,2.0,14.7,50.0},{1,-2067.1,1012.0,2.0,52.3,50.0},{1,-2023.6,1016.5,2.0,14.7,50.0},
		{2,-1991.4,1015.7,2.0,49.8,50.0},{1,-1940.6,1007.5,2.0,52.3,50.0},{1,-1898.2,1012.0,2.0,14.7,50.0},{2,-1886.4,1007.7,2.0,9.2,50.0},{1,-1855.3,1078.5,-51.6,64.1,50.0},{1,-1820.2,1115.5,-51.6,19.4,50.0},{1,-1807.5,1127.1,-51.6,14.7,50.0},{2,-1789.8,1145.0,-51.6,35.3,50.0},
		{2,-1761.3,1182.8,-51.6,59.3,50.0},{1,-1739.6,1212.7,-51.6,14.7,50.0},{1,-1717.3,1230.8,-51.6,41.1,15.0},{1,-1815.5,1280.8,-175.8,52.3,50.0},{1,-1863.4,1284.7,-175.8,24.2,50.0},{1,-1894.5,1285.8,-175.8,17.8,50.0},{1,-1938.2,1287.1,-175.8,51.4,50.0},{1,-2004.3,1281.6,-175.8,64.1,50.0},
		{1,-2069.0,1299.1,-176.7,52.3,50.0},{1,-2124.2,1298.8,176.8,52.3,25.0},{1,-2170.2,1296.5,176.8,26.9,50.0},{1,-2212.8,1292.8,176.8,35.5,50.0},{1,-2252.6,1292.0,176.8,26.9,50.0},{1,-2286.8,1289.0,176.8,17.8,50.0},{1,-2323.4,1283.7,176.8,34.9,50.0},{1,-2376.0,1284.9,176.8,52.3,50.0},
		{1,-2435.2,1281.6,176.8,52.3,50.0},{1,-2484.5,1275.0,176.8,28.8,50.0},{1,-2526.7,1275.7,176.8,35.3,25.0},{1,-1631.3,1082.0,128.4,98.8,10.2},{1,-1661.7,1033.7,128.4,14.7,34.0},{2,-1687.8,1000.7,128.4,69.6,10.2},{1,-1597.2,1026.9,-84.6,52.3,25.5},{1,-1595.9,1077.3,-84.6,34.0,10.2},
		{2,-1534.3,-447.3,-150.0,42.5,6.0},{2,-1775.2,-281.4,148.4,9.1,20.0},{2,-1767.8,-357.1,94.3,29.3,20.0},{2,-1725.1,-406.0,23.7,58.8,20.0},{2,-1679.5,-420.2,23.7,36.2,20.0},{2,-1629.4,-451.6,23.7,80.7,20.0},{2,-1628.7,-411.4,-150.0,57.1,10.0},{2,-1671.2,-371.5,-150.0,56.4,20.0},
		{2,-1700.7,-339.1,-150.0,27.0,20.0},{2,-1736.0,-323.5,-150.0,49.9,6.0},{2,-1696.0,-602.2,-156.3,64.0,20.0},{2,-1726.5,-573.9,-156.3,14.7,20.0},{2,-1739.9,-568.0,-156.3,14.7,20.0},{2,-1763.1,-551.2,-156.3,41.2,20.0},{2,-1788.2,-642.0,85.6,69.4,20.0},{2,-1778.8,-704.2,85.6,56.1,20.0},
		{2,-1769.3,-755.3,85.6,47.2,20.0},{2,-1778.0,-802.5,85.6,45.7,20.0},{2,-1711.9,-790.8,-76.6,36.8,20.0},{2,-1701.8,-750.3,-76.6,46.8,20.0},{2,-1697.5,-717.3,-76.6,19.4,20.0},{2,-1690.9,-701.4,-76.6,14.7,20.0},{2,-1687.5,-687.1,-76.6,14.7,20.0},{2,-1684.1,-672.8,-76.6,14.7,20.0},
		{2,-1677.1,-651.5,-71.9,24.5,20.0},{2,-1747.7,-1039.9,86.1,44.0,20.0},{2,-1752.6,-1072.0,86.1,19.4,20.0},{2,-1732.8,-1095.2,86.1,29.5,20.0},{2,-1751.8,-1131.5,86.1,40.3,20.0},{2,-1705.8,-1164.4,8.2,51.5,20.0},{2,-1674.4,-1178.6,8.2,14.7,20.0},{2,-1647.6,-1188.7,8.2,41.2,20.0},
		{2,-1607.9,-1189.9,8.2,37.8,20.0},{2,-1564.8,-1195.1,10.7,46.1,20.0},{2,-1517.1,-1205.3,12.0,49.6,20.0},{2,-1463.0,-1218.0,12.0,61.7,20.0},{2,-1425.3,-1224.6,12.0,14.7,20.0},{2,-1441.6,-1173.3,-107.7,33.6,20.0},{2,-1462.5,-1145.6,-107.7,31.8,20.0},{2,-1457.1,-1105.6,-107.7,41.2,20.0},
		{2,-1489.2,-1084.6,-107.7,18.5,20.0},{2,-1507.9,-1053.7,-178.1,14.7,20.0},{2,-1522.6,-1053.3,-178.1,14.7,20.0},{2,-1551.3,-1045.5,-176.2,41.2,20.0},{2,-1592.4,-1042.5,-175.9,41.1,20.0},{2,-1637.4,-1047.0,-175.9,48.0,20.0},{2,-1668.5,-1043.3,-175.9,14.7,20.0},{2,-1683.2,-1042.3,-175.9,14.7,20.0},
		{2,-1704.1,-1040.1,-175.9,27.2,20.0},{2,-1746.5,-1399.0,41.7,44.0,20.0},{2,-1446.0,-1450.0,-84.6,44.0,20.0},{2,-1671.1,-1434.1,4.6,41.2,20.0},{2,-1616.4,-1420.4,4.6,65.8,20.0},{2,-1563.6,-1432.4,4.6,41.4,20.0},{2,-1529.1,-1439.9,4.6,28.5,20.0},{2,-1507.9,-1441.2,4.1,14.7,20.0},
		{2,-1431.7,-1405.0,-84.6,48.2,20.0},{2,-1455.8,-1363.0,-168.0,28.4,10.0},{2,-1488.3,-1348.5,-168.0,41.2,20.0},{2,-1532.9,-1341.4,-168.0,49.0,15.0},{2,-1585.6,-1350.0,-168.7,51.8,20.0},{2,-1688.9,-1338.9,-171.8,34.7,20.0},{2,-1726.0,-1312.2,-171.8,46.3,20.0},{2,-2637.2,-872.3,-1.2,34.0,17.0},
		{2,-2774.5,-266.0,87.1,34.0,34.0},{2,-2691.6,-816.7,27.1,26.2,34.0},{2,-2669.0,-834.6,39.4,16.8,34.0},{2,-2653.4,-844.3,45.4,12.2,34.0},{1,-2570.9,-868.1,-1.2,98.9,34.0},{1,-2507.8,-873.4,-1.2,26.9,34.0},{1,-2479.4,-869.5,-1.2,30.0,34.0},{1,-2443.7,-874.0,-1.2,41.2,34.0},
		{2,-2417.0,-869.0,-1.2,12.5,34.0},{1,-2450.1,-227.1,178.9,14.7,34.0},{1,-2507.0,-222.0,178.9,98.8,34.0},{1,-2605.8,-223.8,178.9,98.8,34.0},{2,-2669.4,-228.1,178.9,28.5,34.0},{1,-2710.4,-227.9,178.9,53.7,34.0},{2,-2776.2,-311.6,87.1,56.9,34.0},{1,-2765.6,-389.1,87.1,98.9,34.0},
		{2,-2769.0,-453.8,87.1,30.0,34.0},{1,-2746.6,-605.1,76.3,36.9,34.0},{1,-2734.4,-671.6,75.6,98.8,17.0},{1,-2716.6,-732.0,75.6,27.0,34.0},{1,-2708.4,-764.9,75.6,40.6,34.0},{2,-2274.9,-1496.8,-8.7,34.0,34.0},{1,-2383.8,-1453.4,-1.0,21.5,34.0},{1,-2360.6,-1452.6,7.5,14.7,34.0},
		{1,-2230.4,-1493.6,-8.7,54.9,34.0},{1,-2196.6,-1484.6,-8.7,14.7,34.0},{1,-2179.6,-1430.1,-93.8,98.8,10.2},{1,-2195.0,-1332.0,-93.8,98.9,34.0},{1,-2278.3,-1280.2,172.8,44.0,34.0},{1,-2320.5,-1285.2,172.8,41.1,34.0},{1,-2363.1,-1294.2,172.8,45.8,34.0},{1,-2503.0,-1312.7,48.1,33.6,10.2},
		{1,-2477.0,-1343.4,48.1,46.8,34.0},{1,-2443.6,-1375.3,48.1,45.2,34.0},{1,-2421.3,-1413.2,48.1,41.2,34.0},{2,-1928.6,-1390.8,-86.1,34.0,34.0},{2,-1930.6,-1045.5,-144.0,34.0,10.2},{2,-2067.7,-1001.1,87.8,28.9,17.0},{1,-1973.7,-1446.7,-65.6,14.7,34.0},{1,-1962.3,-1431.9,-58.4,14.2,34.0},
		{1,-1926.9,-1324.3,-86.1,98.9,34.0},{2,-1922.2,-1261.3,-86.1,27.4,34.0},{1,-1927.2,-1160.1,-93.9,63.6,34.0},{1,-1924.8,-1120.6,-93.9,14.7,34.0},{1,-1931.9,-1089.2,-93.9,49.2,34.0},{1,-2065.9,-1096.5,87.8,34.5,34.0},{1,-2067.3,-1163.2,87.8,98.8,34.0},{1,-2056.3,-1359.6,86.1,98.8,34.0},
		{1,-2017.4,-1448.6,-12.7,14.7,34.0},{1,-2131.2,-1723.7,-16.4,98.8,34.0},{1,-2001.8,-1699.0,-4.4,26.7,34.0},{1,-1968.1,-1665.9,-77.7,41.1,17.0},{1,-1968.1,-1637.3,-77.7,14.7,25.5},{1,-2041.0,-1630.7,167.5,14.7,34.0},{1,-2055.4,-1633.9,167.5,14.7,34.0},{2,-2083.8,-1637.9,168.1,41.8,34.0},
		{1,-2123.7,-1648.9,171.1,37.2,34.0},{1,-2149.6,-1651.5,171.1,14.7,34.0},{2,-2175.1,-1654.6,171.1,36.6,34.0},{1,-2200.5,-1042.8,-92.2,47.8,34.0},{1,-2287.4,-1010.2,-179.5,98.8,34.0},{1,-2383.5,-1012.2,178.8,39.9,34.0},{1,-2410.7,-1017.6,178.8,14.7,34.0},{2,-2438.7,-1019.8,178.8,41.4,34.0},
		{1,-2508.8,-1022.4,178.8,98.9,34.0},{1,-2573.6,-1026.1,178.8,30.9,34.0},{1,-2603.2,-1018.5,178.8,27.9,34.0},{2,-2608.2,-1094.3,72.3,31.5,34.0},{2,-2595.4,-1127.5,72.3,39.8,34.0},{1,-2530.1,-1163.8,1.2,98.8,17.0},{1,-2445.8,-1162.3,1.1,69.7,34.0},{1,-2320.2,-1155.7,-7.3,98.8,34.0},
		{1,-2237.9,-1143.4,-7.3,67.5,34.0},{2,-2272.6,-74.0,1.1,45.7,34.0},{1,-2242.5,-76.9,1.1,14.7,34.0},{1,-2223.2,-28.5,-89.6,98.8,10.2},{1,-2222.6,70.3,-89.6,98.8,34.0},{1,-2231.1,169.0,-90.0,98.9,34.0},{1,-2222.6,267.7,-90.3,98.8,34.0},{1,-2223.2,343.3,-90.3,52.3,17.0},
		{1,-2314.9,348.7,156.4,41.2,34.0},{1,-2360.2,258.5,91.3,98.9,34.0},{1,-2362.2,159.8,91.0,98.9,34.0},{1,-2365.8,37.5,88.7,29.4,34.0},{1,-2369.1,-3.5,88.7,52.3,34.0},{1,-2363.3,-56.7,88.7,37.2,34.0},{2,-1933.3,-63.9,-94.8,34.0,34.0},{1,-1932.5,-17.3,-94.8,59.0,34.0},
		{1,-1935.4,32.8,-94.8,41.2,34.0},{1,-1941.1,102.6,-94.8,98.8,34.0},{1,-1951.8,160.1,-92.4,14.7,34.0},{2,-1954.0,243.7,-86.5,55.6,34.0},{1,-1944.7,288.9,-85.0,34.2,34.0},{2,-1948.6,322.9,-85.0,32.9,34.0},{1,-1942.8,346.3,-85.0,14.7,34.0},{1,-1934.3,373.6,-85.0,41.2,34.0},
		{1,-1957.0,423.0,169.3,40.6,17.0},{1,-1992.5,421.9,169.3,29.6,34.0},{1,-2013.2,412.2,169.3,14.7,34.0},{1,-2052.4,407.0,169.3,64.5,34.0},{1,-2095.0,342.9,89.7,98.8,10.2},{1,-2094.5,244.1,89.7,98.8,34.0},{1,-2093.4,175.2,89.8,39.0,34.0},{1,-2085.6,105.9,90.4,98.9,34.0},
		{1,-2086.2,7.0,90.4,98.9,34.0},{1,-2063.0,-74.8,1.1,52.0,25.5},{2,-2012.8,-79.1,1.1,48.5,34.0},{2,-2750.8,-86.7,58.2,28.9,10.2},{1,-2675.1,-87.1,-1.1,98.8,34.0},{1,-2576.3,-85.3,-1.1,98.8,34.0},{1,-2505.6,-28.6,-91.3,98.9,17.0},{1,-2498.7,47.2,-91.3,52.3,34.0},
		{1,-2503.9,96.4,-91.3,34.0,34.0},{1,-2507.8,164.2,-88.9,98.9,34.0},{1,-2499.5,228.2,-88.8,29.2,25.5},{1,-2604.9,204.0,143.5,30.7,34.0},{2,-2647.1,156.0,130.9,46.5,34.0},{1,-2685.0,101.6,116.5,25.5,34.0},{1,-2724.7,-10.5,107.6,98.9,10.2},{2,-2740.9,-63.5,107.6,11.8,10.2},
		{1,-1903.8,1933.1,148.3,41.1,50.0},{1,-1989.5,1875.9,146.0,52.3,50.0},{1,-2001.1,1810.9,11.3,19.4,15.0},{2,-1912.2,1790.8,11.3,44.8,50.0},{1,-1853.6,1858.3,-70.5,52.3,25.0},{1,-1116.3,906.0,-79.0,29.8,34.0},{1,-1101.8,968.6,-79.0,98.8,34.0},{1,-1220.7,1055.6,-166.9,54.8,34.0},
		{1,-1344.4,1073.5,-174.9,32.9,34.0},{1,-1377.3,1074.6,-174.9,33.0,34.0},{1,-1410.1,1079.7,-174.9,33.4,34.0},{1,-1459.6,1030.1,95.3,98.9,25.5},{1,-1469.3,967.2,95.3,28.1,34.0},{1,-1401.1,933.9,10.9,33.2,34.0},{2,-1362.3,931.4,10.9,44.0,34.0},{1,-1324.1,917.4,10.9,36.2,34.0},
		{1,-1274.8,906.2,11.7,64.2,34.0},{1,-1224.7,898.0,12.4,36.4,34.0},{2,-1172.8,887.6,12.4,69.4,10.2},{2,-1400.9,-477.7,124.4,14.7,20.0},{2,-1422.7,-510.4,124.4,63.9,20.0},{2,-1445.3,-542.6,124.4,14.7,20.0},{2,-1459.9,-561.8,124.4,33.6,20.0},{2,-1478.1,-589.4,124.4,32.4,20.0},
		{2,-1498.5,-625.7,124.4,50.5,20.0},{2,-1530.3,-695.7,108.4,13.8,20.0},{2,-1556.2,-748.4,103.2,51.2,20.0},{2,-1571.7,-794.4,103.2,45.5,20.0},{2,-1576.9,-835.1,103.2,36.2,20.0},{2,-1526.6,-898.5,3.0,41.1,20.0},{2,-1480.7,-848.6,-77.7,54.5,20.0},{2,-1465.7,-799.9,-77.7,47.0,20.0},
		{2,-1467.8,-753.1,-77.7,43.7,20.0},{2,-1433.0,-666.9,-64.2,20.5,20.0},{2,-1392.6,-589.5,-54.7,30.9,20.0},{2,-1360.8,-567.6,-54.7,41.5,20.0},{2,-1339.6,-521.5,-54.7,58.4,20.0},{2,-1304.4,-880.8,-4.1,51.0,20.0},{2,-1261.1,-876.9,-4.1,36.1,20.0},{2,-1233.3,-875.9,-4.1,19.3,20.0},
		{2,-1189.2,-835.4,-69.8,36.1,20.0},{2,-1168.9,-801.7,-69.8,41.1,20.0},{2,-1096.7,-658.9,-57.0,41.2,20.0},{2,-1086.6,-632.2,-57.0,14.7,20.0},{2,-1149.5,-570.3,-162.7,41.2,20.0},{2,-1206.2,-585.5,125.3,14.7,20.0},{2,-1227.3,-604.7,125.3,41.1,20.0},{2,-1249.7,-641.8,125.3,45.2,20.0},
		{2,-1277.2,-675.1,125.3,41.2,20.0},{2,-1317.1,-746.1,106.3,41.2,20.0},{2,-1340.5,-847.4,102.3,41.2,10.0},{2,-1311.0,-1429.5,-1.5,30.8,15.0},{2,-1193.4,-1036.2,175.9,19.4,20.0},{2,-1210.6,-1034.7,175.9,14.7,20.0},{2,-1252.6,-1040.2,175.9,69.8,20.0},{2,-1313.1,-1044.2,175.9,51.5,20.0},
		{2,-1346.3,-1044.4,175.9,14.7,15.0},{2,-1316.3,-1083.2,72.3,30.8,15.0},{2,-1308.1,-1113.1,72.3,31.1,20.0},{2,-1298.0,-1158.7,72.3,62.1,20.0},{2,-1280.6,-1206.4,77.3,32.6,20.0},{2,-1280.2,-1234.4,83.7,14.7,20.0},{2,-1287.5,-1303.7,95.4,41.2,20.0},{2,-1286.2,-1339.3,95.4,29.2,20.0},
		{2,-1276.0,-1369.9,95.4,29.9,20.0},{2,-1287.2,-1393.6,95.4,19.4,20.0},{2,-1199.4,-1350.3,-94.2,63.0,20.0},{2,-1197.3,-1297.5,-94.2,42.0,20.0},{2,-1196.3,-1260.0,-95.0,33.5,10.0},{2,-1198.8,-1230.3,-95.7,27.0,20.0},{2,-1199.7,-1209.5,-95.7,14.7,20.0},{2,-1203.1,-1188.4,-95.7,27.8,20.0},
		{2,-1211.5,-1157.0,-95.7,36.4,20.0},{2,-1202.8,-1117.2,-95.7,41.2,20.0},{2,-1220.8,-1084.6,-95.7,27.4,20.0},{2,-1302.1,-370.2,-89.1,34.0,6.0},{2,-1287.4,-329.5,-87.6,45.7,20.0},{2,-1281.3,-284.6,-78.5,33.1,20.0},{2,-1302.3,-246.3,-71.9,18.3,20.0},{2,-1276.4,-225.2,-65.2,26.3,20.0},
		{2,-1309.8,-201.9,177.7,39.0,6.0},{2,-1351.4,-281.9,89.2,11.6,20.0},{2,-1351.5,-339.4,80.1,45.7,20.0},{2,-1586.3,-232.7,176.6,41.9,20.0},{2,-1505.4,-276.6,30.0,31.5,10.0},{2,-403.5,2312.2,175.8,34.0,34.0},{1,-953.6,2224.7,79.2,98.9,25.5},{1,-843.9,2162.6,-12.6,98.8,34.0},
		{1,-770.3,2179.2,-12.6,52.3,34.0},{1,-721.8,2190.9,-12.6,33.3,34.0},{1,-686.1,2202.0,-12.6,41.4,34.0},{1,-536.1,2218.9,0.1,98.9,34.0},{1,-437.3,2210.0,0.1,98.8,34.0},{1,-371.4,2211.3,0.1,32.9,34.0},{2,-353.5,2261.7,-100.9,12.0,34.0},{1,-470.1,2313.4,175.8,98.8,34.0},
		{1,-526.3,2303.1,175.8,14.7,34.0},{2,-565.5,2296.5,175.8,64.4,34.0},{1,-616.6,2299.0,175.8,36.9,34.0},{1,-684.4,2297.8,175.8,98.8,34.0},{2,-766.0,2287.0,175.1,66.2,17.0},{1,-875.0,2269.7,165.2,30.7,34.0},{1,-909.6,1298.0,99.1,31.7,34.0},{1,-791.6,1217.9,22.9,52.3,34.0},
		{1,-737.5,1197.2,21.0,45.7,34.0},{1,-691.8,1185.1,5.4,35.3,25.5},{1,-637.0,1181.6,2.4,65.6,34.0},{1,-554.5,1186.2,2.4,98.9,34.0},{1,-491.2,1252.4,-82.8,30.6,34.0},{1,-484.8,1320.3,-86.6,45.6,34.0},{1,-534.5,1350.4,-174.8,26.1,34.0},{2,-578.5,1354.7,-174.8,62.3,34.0},
		{1,-658.3,1365.9,-174.8,98.8,34.0},{1,-726.4,1363.9,-175.2,37.0,34.0},{1,-758.0,1367.8,-175.2,26.6,34.0},{2,-791.5,1370.7,-175.2,40.6,34.0},{2,-827.8,1376.2,-175.2,32.8,34.0},{2,-866.8,1378.0,-175.2,45.3,34.0},{2,-1074.8,2208.1,163.3,23.8,17.0},{2,-1315.8,2135.3,112.2,34.0,10.2},
		{2,-1343.7,2100.9,74.1,34.0,17.0},{1,-1213.2,1581.9,4.8,98.9,34.0},{1,-1156.8,1574.6,4.8,14.7,34.0},{1,-1129.5,1566.2,4.8,41.2,34.0},{1,-1098.6,1572.5,4.8,19.4,34.0},{2,-1066.0,1567.4,4.8,46.4,34.0},{1,-1035.6,1564.5,4.8,14.7,34.0},{1,-1021.6,1662.7,-92.1,98.8,34.0},
		{1,-1025.8,1743.2,-92.1,62.6,34.0},{1,-1027.4,1824.0,-92.1,98.8,34.0},{1,-1046.4,1979.7,-100.8,98.8,34.0},{1,-1060.7,2043.9,-100.8,32.8,34.0},{1,-1066.6,2081.0,-100.8,42.3,34.0},{1,-1072.7,2116.6,-100.8,29.9,34.0},{1,-1081.9,2158.0,-100.8,54.8,34.0},{1,-1170.3,2185.8,163.3,98.8,17.0},
		{1,-1235.5,2154.2,163.3,44.4,34.0},{1,-1279.4,2150.4,163.3,41.9,34.0},{1,-1336.8,2077.6,74.1,14.7,34.0},{1,-1320.7,2041.7,74.1,63.2,34.0},{1,-1309.9,1960.6,74.1,98.8,34.0},{1,-1282.5,1889.0,75.6,51.9,34.0},{1,-1278.9,1842.0,80.3,36.3,34.0},{1,-1262.6,1808.2,81.9,33.9,34.0},
		{2,-1265.6,1761.3,81.9,58.0,34.0},{2,-1255.4,1705.7,81.9,55.1,34.0},{2,-1250.2,1664.2,81.9,28.5,34.0},{1,-1442.7,1706.9,113.0,52.3,25.0},{1,-1462.9,1657.0,113.0,35.3,15.0},{1,-1432.3,1633.7,19.8,35.3,37.5},{2,-698.6,-21.8,4.6,50.0,6.0},{2,-580.1,201.9,-173.4,42.5,20.0},
		{2,-709.0,247.9,90.0,35.0,20.0},{2,-657.4,-43.6,4.6,35.6,20.0},{2,-651.6,11.0,-83.8,69.2,15.0},{2,-616.0,63.2,-83.8,42.1,20.0},{2,-617.2,105.7,-81.7,38.8,20.0},{2,-597.0,136.1,-81.4,26.8,20.0},{2,-710.0,183.1,90.0,43.1,20.0},{2,-721.7,135.5,90.0,52.1,20.0},
		{2,-702.5,82.7,90.0,53.5,20.0},{2,-709.0,20.9,90.0,69.9,20.0},{2,-304.0,186.2,-173.4,28.9,10.2},{2,-432.8,-62.5,4.6,51.0,34.0},{2,-381.1,-60.2,4.6,51.7,34.0},{1,-343.3,46.9,-85.7,28.5,34.0},{1,-331.0,112.5,-79.7,98.8,34.0},{2,-389.0,199.7,-173.4,40.6,34.0},
		{2,-428.8,200.9,-173.4,38.7,34.0},{1,-462.3,94.7,98.0,98.9,34.0},{1,-481.5,-31.6,96.2,38.1,25.5},{2,-268.2,-879.0,-100.8,30.8,6.6},{2,-308.5,-571.9,172.6,59.8,11.0},{2,-349.7,-587.5,172.6,25.8,22.0},{2,-380.3,-616.4,94.0,44.6,16.5},{2,-375.1,-659.3,94.0,40.5,22.0},
		{2,-383.3,-742.5,76.1,30.1,22.0},{2,-339.0,-829.6,72.9,26.9,22.0},{2,-275.5,-807.6,-100.8,31.0,22.0},{2,-288.7,-767.9,-100.6,51.7,22.0},{2,-288.0,-723.6,-96.4,30.0,22.0},{2,-285.1,-688.1,-87.4,30.4,22.0},{2,-287.2,-651.3,-87.3,42.7,22.0},{2,-282.5,-605.9,-87.3,48.5,11.0},
		{2,-20.1,-1493.8,-103.1,30.8,6.6},{2,-480.5,-1022.6,95.7,58.1,22.0},{2,-491.6,-1064.6,95.7,27.7,22.0},{2,-500.4,-1101.9,95.7,48.3,22.0},{2,-506.4,-1153.0,95.7,54.7,22.0},{2,-513.1,-1208.7,95.7,57.4,22.0},{2,-496.9,-1309.8,92.2,45.3,22.0},{2,-520.5,-1351.3,92.2,39.7,22.0},
		{2,-499.0,-1410.4,92.2,76.7,22.0},{2,-476.9,-1465.5,3.6,69.2,11.0},{2,-426.3,-1446.8,3.6,29.3,22.0},{2,-385.5,-1454.1,3.6,53.0,22.0},{2,-337.7,-1465.5,3.6,44.1,22.0},{2,-289.0,-1474.9,3.6,54.2,22.0},{2,-238.3,-1477.1,3.6,47.3,22.0},{2,-187.4,-1464.7,3.4,53.1,22.0},
		{2,-36.2,-1426.9,-103.1,31.9,22.0},{2,-41.8,-1389.1,-103.1,44.3,22.0},{2,-48.1,-1336.7,-103.1,60.8,22.0},{2,-60.9,-1286.2,-101.5,41.0,22.0},{2,-66.5,-1250.0,-94.7,23.7,22.0},{2,-60.5,-1225.7,-88.4,17.0,22.0},{2,-49.4,-1127.3,-80.4,51.7,22.0},{2,-39.5,-1080.0,-80.4,44.8,22.0},
		{2,-47.5,-1023.9,-80.4,63.0,6.6},{2,-121.6,-1007.6,175.9,52.0,22.0},{2,-167.5,-1007.7,176.4,38.9,22.0},{2,-217.4,-1013.3,177.2,60.3,22.0},{2,-282.1,-1013.8,177.2,68.9,22.0},{2,-331.0,-1030.5,177.2,30.4,22.0},{2,-376.1,-1017.8,177.2,58.4,22.0},{2,-426.1,-1030.7,177.2,42.9,22.0},
		{2,219.9,-2040.3,-74.9,34.0,10.2},{1,-192.8,-1709.5,90.2,62.1,34.0},{1,-196.8,-1789.9,90.2,98.8,34.0},{1,-188.1,-1888.7,90.0,98.9,34.0},{1,-193.9,-2070.6,89.1,68.3,34.0},{1,-188.7,-2132.8,89.1,56.0,34.0},{1,-36.7,-2142.5,-11.1,98.8,34.0},{1,32.0,-2128.9,-11.1,41.2,34.0},
		{1,65.7,-2122.4,-11.1,27.4,34.0},{2,96.3,-2109.6,-11.1,37.7,34.0},{2,147.4,-2076.8,-48.7,8.3,34.0},{1,177.1,-2056.2,-33.7,14.7,34.0},{1,193.6,-2046.7,-26.4,14.7,34.0},{1,234.5,-1975.5,-74.9,98.9,34.0},{1,252.9,-1896.9,-78.3,14.7,34.0},{1,255.9,-1882.5,-78.3,14.7,34.0},
		{1,267.6,-1856.4,-78.3,41.1,34.0},{1,267.2,-1827.9,-78.3,14.7,34.0},{1,270.2,-1813.5,-78.3,14.7,34.0},{1,273.2,-1799.1,-78.3,14.7,34.0},{2,278.6,-1765.0,-78.3,54.2,34.0},{2,288.2,-1732.5,-78.3,13.5,34.0},{1,292.6,-1701.4,-95.7,41.2,17.0},{2,281.2,-1671.6,-95.7,20.4,34.0},
		{1,227.9,-1629.7,175.1,19.4,34.0},{2,199.7,-1629.9,175.1,36.7,34.0},{1,160.0,-1628.9,175.1,42.2,34.0},{1,89.5,-1632.4,175.1,98.8,34.0},{1,-8.9,-1640.8,175.1,98.8,34.0},{2,-92.9,-1653.5,177.6,67.6,34.0},{1,-136.4,-1653.9,-178.5,14.7,34.0},{2,-164.5,-1649.3,-178.0,41.1,25.5},
		{1,-333.4,-1717.5,-89.8,98.9,34.0},{1,-342.2,-1645.2,-176.4,19.4,17.0},{1,-378.0,-1636.9,-176.4,53.2,25.5},{1,-424.9,-1632.6,-176.4,40.8,34.0},{1,-465.7,-1628.6,-176.4,41.2,34.0},{1,-508.6,-1627.1,-176.4,44.8,34.0},{1,-548.0,-1667.5,100.3,41.1,10.2},{1,-555.3,-1708.0,100.3,41.2,34.0},
		{1,-554.3,-1736.6,100.3,14.7,34.0},{1,-556.9,-1751.2,100.4,14.7,17.0},{1,-560.1,-1767.0,102.8,14.7,17.0},{1,-399.3,-1764.2,16.9,58.3,10.2},{1,-321.2,-2172.4,-90.8,98.8,34.0},{1,-331.4,-2073.7,-90.8,98.9,34.0},{1,-327.1,-2001.6,-90.8,45.1,34.0},{1,-328.7,-1958.6,-90.8,41.1,34.0},
		{1,-387.8,-1913.5,-162.5,98.9,10.2},{1,-446.9,-1888.0,-162.5,29.4,34.0},{1,-598.3,-1899.5,107.0,14.7,34.0},{2,-605.1,-1920.6,107.0,29.6,34.0},{2,-616.4,-1963.0,107.0,58.0,34.0},{1,-681.3,-2076.8,122.0,98.9,34.0},{1,-722.1,-2134.0,122.0,41.6,34.0},{1,-642.3,-2180.3,4.2,52.6,34.0},
		{2,-599.9,-2185.1,4.2,32.7,34.0},{1,-551.4,-2187.1,4.2,64.5,34.0},{2,-499.3,-2187.5,4.2,39.2,34.0},{1,-462.3,-2194.3,4.2,35.6,34.0},{1,-437.0,-2193.2,4.2,14.7,34.0},{1,-409.6,-2201.3,4.1,41.2,34.0},{2,-542.0,-584.1,79.4,37.4,22.0},{2,-548.2,-731.5,-94.3,20.7,6.6},
		{2,-531.3,-695.3,-87.6,40.3,11.0},{2,-591.9,-461.0,-7.4,35.7,11.0},{2,-547.8,-433.5,-7.4,58.7,22.0},{2,-501.7,-423.4,-7.4,35.5,22.0},{2,-465.8,-441.8,-7.4,30.9,22.0},{2,-435.5,-434.3,-7.4,31.2,22.0},{2,-405.3,-439.1,-7.4,27.5,22.0},{2,-365.8,-432.2,-7.4,52.5,22.0},
		{2,-348.9,-333.3,-102.3,20.2,22.0},{2,-354.0,-306.0,-96.4,28.3,22.0},{2,-373.6,-265.6,-92.9,50.1,22.0},{2,-394.4,-226.2,-175.4,43.7,11.0},{2,-425.8,-223.1,-175.4,19.4,22.0},{2,-442.5,-219.1,-175.4,14.7,22.0},{2,-470.0,-210.7,-175.4,41.2,22.0},{2,-498.2,-214.6,-175.4,14.7,22.0},
		{2,-526.7,-215.8,-175.4,41.8,22.0},{2,-567.3,-202.9,-175.4,41.2,22.0},{2,-598.3,-209.3,-175.4,19.4,22.0},{2,-614.9,-205.3,-175.4,14.7,22.0},{2,-637.4,-202.7,-175.4,30.3,22.0},{2,-663.4,-260.5,68.7,57.7,22.0},{2,-639.7,-314.8,68.7,60.7,22.0},{2,-602.4,-366.5,68.7,62.7,22.0},
		{2,-535.3,807.8,-72.4,46.0,20.0},{2,-518.2,864.0,132.6,52.5,6.0},{2,-486.0,886.1,-73.4,32.5,6.0},{2,232.2,-1444.6,-60.1,44.0,6.6},{2,124.8,-1456.2,-4.9,56.4,22.0},{2,168.7,-1460.9,-4.9,30.3,22.0},{2,196.3,-1435.5,-4.9,29.0,22.0},{2,232.8,-1400.5,-98.6,31.0,22.0},
		{2,250.6,-1357.3,-98.6,49.1,22.0},{2,231.7,-1303.9,-98.6,62.2,22.0},{2,237.8,-1255.8,-98.6,31.3,22.0},{2,208.9,-1220.1,-98.9,48.4,22.0},{2,186.9,-1101.1,-99.5,66.9,22.0},{2,194.9,-1028.9,-99.5,72.7,22.0},{2,155.6,-988.3,175.7,44.7,6.6},{2,128.4,-1026.5,99.4,42.6,22.0},
		{2,100.6,-1059.2,99.4,31.0,22.0},{2,102.1,-1097.6,99.4,44.2,22.0},{2,99.8,-1138.7,99.4,37.7,22.0},{2,87.2,-1170.9,99.4,29.7,22.0},{2,78.2,-1205.4,99.4,41.4,22.0},{2,79.1,-1245.0,84.0,28.0,22.0},{2,118.5,-1326.1,76.9,63.5,22.0},{2,109.5,-1395.0,76.9,66.6,22.0},
		{2,-35.8,-864.2,-101.8,30.8,11.0},{2,-92.8,-565.9,179.5,72.5,22.0},{2,-139.6,-587.6,92.8,42.6,6.6},{2,-129.7,-629.6,92.8,40.4,22.0},{2,-131.3,-671.8,92.8,44.1,22.0},{2,-142.5,-727.5,80.2,35.5,22.0},{2,-124.4,-799.5,79.2,40.2,22.0},{2,-127.4,-830.2,79.2,19.1,16.5},
		{2,-88.9,-830.1,-4.3,39.2,11.0},{2,-57.7,-768.1,-101.7,57.7,22.0},{2,-67.4,-676.1,-87.5,36.7,22.0},{2,-56.5,-635.4,-84.4,41.7,22.0},{2,120.6,-832.0,-4.3,78.5,22.0},{2,166.4,-796.6,-93.9,48.3,6.6},{2,147.1,-739.5,-93.9,68.0,22.0},{2,148.9,-681.9,-93.9,46.9,22.0},
		{2,130.5,-628.2,-93.9,62.7,11.0},{2,149.0,-580.0,-93.9,31.1,22.0},{2,94.2,-582.8,95.6,33.9,22.0},{2,83.5,-705.0,78.6,14.1,22.0},{2,94.2,-732.7,78.4,44.8,22.0},{2,120.6,-776.0,78.4,50.5,6.6},{2,619.3,1906.6,100.5,34.0,34.0},{2,1470.1,1706.7,-39.5,34.0,34.0},
		{1,1122.5,2178.3,124.7,20.0,34.0},{2,1108.4,2163.1,130.9,14.5,34.0},{2,976.6,2109.5,-170.6,19.7,34.0},{2,959.4,2117.8,-163.2,8.4,34.0},{1,894.1,2103.2,145.7,69.1,34.0},{2,845.9,2063.8,145.7,54.7,34.0},{1,779.2,2025.5,145.7,98.8,34.0},{2,712.6,1974.2,145.7,69.0,34.0},
		{1,672.1,1947.9,145.7,27.6,34.0},{1,610.0,1840.7,100.5,98.9,34.0},{1,595.5,1778.3,100.0,29.7,25.5},{1,589.9,1735.3,84.4,13.7,34.0},{1,594.0,1708.9,71.0,12.6,34.0},{1,631.2,1629.9,64.7,53.2,34.0},{2,686.0,1606.3,-7.6,52.3,10.2},{1,719.4,1609.1,-7.6,14.7,34.0},
		{2,734.1,1614.2,-7.6,15.8,34.0},{1,1003.3,1638.7,-7.1,41.2,34.0},{1,1044.4,1645.5,-7.1,42.1,34.0},{1,1114.5,1652.5,-7.1,98.8,34.0},{1,1182.5,1671.3,-7.1,40.6,34.0},{1,1252.8,1669.7,-7.1,98.8,34.0},{1,1308.4,1682.9,-7.1,14.7,34.0},{1,1365.5,1683.8,-7.1,98.8,34.0},
		{2,1427.1,1698.2,-7.1,27.1,17.0},{2,1499.9,1735.5,-39.5,48.7,34.0},{1,1557.1,1782.2,-39.5,98.9,34.0},{1,1616.6,1820.1,-39.5,41.2,34.0},{1,1634.3,1842.6,-39.5,14.7,34.0},{1,1930.6,2161.5,-58.0,14.7,34.0},{1,1873.3,2245.9,177.9,98.8,34.0},{1,1701.9,2235.1,177.9,33.2,10.2},
		{1,1664.1,2229.0,177.9,43.0,34.0},{1,1488.2,2213.5,173.3,98.9,34.0},{2,1421.4,2206.4,173.3,35.3,34.0},{1,1383.2,2205.6,173.3,41.0,34.0},{1,1314.2,2193.2,173.3,98.9,34.0},{2,1243.5,2186.5,173.3,43.0,34.0},{1,1187.3,2185.5,173.3,69.0,10.2},{2,1016.4,844.9,-10.5,39.1,20.0},
		{2,1306.9,1122.1,173.1,46.2,20.0},{2,1244.6,1129.3,173.1,75.6,20.0},{2,1177.9,1123.5,173.1,58.4,20.0},{2,1057.2,1093.3,168.6,78.1,20.0},{2,1042.5,984.4,72.8,21.8,20.0},{2,1087.1,857.1,-11.7,60.6,20.0},{2,1192.5,894.0,-13.6,69.9,20.0},{2,1254.5,900.4,-13.6,53.6,20.0},
		{2,1301.7,931.3,-13.6,52.7,20.0},{2,1352.9,960.5,-88.9,61.4,20.0},{2,1337.3,1034.8,-106.9,14.0,20.0},{2,1302.5,1080.0,168.2,48,42},{3,1262.6,1026.7,168.2,48,42},{2,1253.6,1069.8,168.2,48,42},{2,1222.7,973.4,168.2,48,42},{2,1213.7,1016.5,168.2,48,42},
		{3,1204.7,1059.5,168.2,48,42},{3,1173.7,963.2,168.2,48,42},{2,1164.7,1006.2,168.2,48,42},{2,1155.7,1049.3,168.2,48,42},{3,1146.7,1092.4,168.2,48,42},{2,1124.8,952.9,168.2,48,42},{2,1115.8,996.0,168.2,48,42},{3,1106.8,1039.1,168.2,48,42},
		{3,1075.8,942.7,168.2,48,42},{3,1026.9,932.5,168.2,48,42},{3,999.9,1061.7,168.2,48,42},{2,1030.5,660.5,170.0,85.8,6.0},{2,944.4,647.5,170.0,88.4,6.0},{2,878.9,633.6,170.0,45.5,6.0},{2,680.5,597.6,170.0,52.6,6.0},{2,623.4,586.8,170.0,63.8,6.0},
		{2,1397.5,478.9,-13.3,60.4,7.0},{2,1306.8,298.2,0.3,76.3,7.0},{2,1446.9,297.9,5.8,78.5,10.5},{2,1514.6,277.4,5.8,60.4,14.0},{2,1559.1,305.8,-80.2,74.4,7.0},{2,1571.7,382.3,-80.2,80.5,7.0},{2,1236.2,296.3,166.9,46.7,7.0},{2,1548.3,81.2,-174.4,47.6,10.5},
		{2,1220.2,126.8,98.8,39.2,14.0},{2,1423.6,43.8,23.3,61.6,14.0},{2,1466.8,62.0,-174.4,64.9,10.5},{2,1349.6,-371.4,-79.6,56.0,7.0},{2,1423.6,-282.4,-75.7,56.0,14.0},{2,1189.6,-130.4,100.0,54.5,14.0},{2,1164.2,-185.7,100.8,61.7,14.0},{2,1166.3,-256.4,100.8,76.2,14.0},
		{2,1141.1,-317.8,100.8,53.9,14.0},{2,1118.2,-376.4,100.8,69.5,14.0},{2,1128.0,-427.5,100.8,27.6,10.5},{2,1200.3,-402.9,-4.6,35.0,14.0},{2,1251.5,-378.0,-16.9,65.7,14.0},{2,1313.4,-395.1,-17.6,43.9,7.0},{2,1432.3,-230.6,-75.7,48.7,14.0},{2,1447.0,-188.4,-75.7,40.2,14.0},
		{2,1426.9,-145.5,-156.4,46.6,10.5},{2,1391.0,-136.0,-156.4,26.7,14.0},{2,1354.1,-126.4,-156.4,48.6,14.0},{2,1293.2,-99.9,-169.0,33.6,14.0},{2,1250.3,-99.9,-169.1,50.7,14.0},{2,1203.2,-87.8,-169.1,46.5,14.0},{2,1170.8,-63.6,-169.1,26.4,14.0},{2,1135.3,-677.9,76.0,62.0,14.0},
		{2,1153.9,-773.4,76.0,27.5,14.0},{2,1175.1,-792.6,76.0,20.0,14.0},{2,1242.4,-1033.5,3.8,56.0,7.0},{2,1216.8,-991.1,64.2,56.2,7.0},{2,1375.2,-929.7,-82.3,28.1,14.0},{2,431.3,-130.5,-85.4,47.6,14.0},{2,461.6,94.7,-132.8,56.0,14.0},{2,356.2,139.8,-179.5,69.3,14.0},
		{2,295.1,151.3,-179.5,53.0,14.0},{2,242.0,147.7,-179.5,53.0,14.0},{2,201.7,136.9,-179.5,27.4,14.0},{2,152.8,127.7,-179.5,70.5,14.0},{2,102.6,115.9,97.9,46.0,10.5},{2,103.3,72.3,97.9,40.1,14.0},{2,140.1,-87.4,2.3,14.7,14.0},{2,162.5,-92.3,2.3,30.6,14.0},
		{2,185.4,-89.3,2.3,14.7,14.0},{2,200.2,-87.5,2.3,14.7,14.0},{2,250.2,-46.8,12.2,53.6,14.0},{2,372.0,-83.8,6.8,91.2,14.0},{2,409.3,-38.8,-84.1,51.3,14.0},{2,439.5,29.3,-79.7,80.5,14.0},{2,879.0,-537.9,-136.0,39.2,14.0},{2,625.9,-363.3,93.6,86.2,14.0},
		{2,596.3,-451.0,93.6,92.7,14.0},{2,594.4,-587.8,89.9,47.8,14.0},{2,590.8,-649.3,89.9,75.1,14.0},{2,739.6,-609.6,-38.7,50.6,14.0},{2,777.8,-564.2,-38.7,65.8,14.0},{2,827.8,-485.5,-136.0,30.6,14.0},{2,773.6,-469.3,-136.0,69.9,14.0},{2,741.1,-420.2,-136.0,45.0,14.0},
		{2,694.3,-386.3,-136.0,69.5,14.0},{2,377.0,1732.4,93.2,34.0,10.2},{2,381.6,1561.9,-8.0,34.0,34.0},{2,410.3,1758.4,140.7,43.6,34.0},{1,369.5,1688.0,93.2,55.4,34.0},{1,367.7,1629.7,84.7,12.5,34.0},{1,448.1,1565.2,-8.0,98.8,34.0},{1,470.9,1669.8,-108.4,16.1,34.0},
		{1,461.7,1689.8,-103.6,22.5,34.0},{2,544.8,1019.9,168.6,38.7,20.0},{2,505.5,1001.5,168.6,45.7,20.0},{2,454.6,985.5,168.6,60.4,20.0},{2,398.5,961.8,168.6,59.0,10.0},{2,451.8,922.9,63.0,76.4,15.0},{2,466.9,845.0,63.0,76.1,20.0},{2,504.6,794.6,63.0,48.0,20.0},
		{2,543.8,771.3,-10.0,59.5,6.0},{2,591.1,807.6,-10.0,46.5,20.0},{2,612.0,887.0,-111.4,13.2,20.0},{2,576.5,957.4,-119.4,33.7,20.0},{3,574.8,865.1,-117.0,48,42},{3,552.1,909.6,-117.0,48,42},{2,529.4,954.2,-117.0,48,42},{1,-75.5,1550.7,-39.3,37.3,25.5},
		{1,-59.1,1571.6,-39.3,14.7,34.0},{1,-16.7,1609.6,-39.3,98.9,34.0},{1,43.0,1647.2,-39.3,41.2,34.0},{1,69.7,1674.5,-39.3,34.7,34.0},{1,124.2,1713.5,-39.3,98.8,34.0},{1,176.2,1767.0,-39.3,49.6,25.5},{1,214.8,1790.5,-39.3,40.0,25.5},{2,243.6,1818.0,-39.3,39.3,17.0},
		{1,103.1,1795.5,-177.6,98.9,10.2},{1,4.3,1799.7,-177.6,98.9,34.0},{1,-105.8,1762.2,84.3,14.7,34.0},{2,-104.4,1737.8,84.3,34.2,34.0},{2,-95.9,1691.2,84.3,60.2,34.0},{1,-94.9,1653.6,84.3,14.7,34.0},{2,-90.7,1625.6,84.3,41.7,10.2},{2,159.3,768.4,7.1,30.3,20.0},
		{2,210.6,797.1,7.1,64.6,20.0},{2,261.9,780.9,7.1,41.2,6.0},{2,247.5,852.0,-117.0,34.1,20.0},{2,224.5,891.4,-117.0,57.0,20.0},{2,154.0,932.5,-117.0,80.3,10.0},{2,168.6,995.3,-114.6,15.0,20.0},{2,145.4,854.5,100.4,40.6,20.0},{2,131.2,804.0,100.4,64.0,15.0},
		{1,206.0,1602.1,140.7,98.8,34.0},{1,149.1,1554.6,140.7,49.4,10.2},{1,247.9,1569.4,-106.7,31.2,10.2},{2,563.2,2052.4,-34.3,23.8,17.0},{1,542.0,2124.2,62.1,98.8,34.0},{1,663.6,2113.7,-34.3,98.8,34.0},{1,713.0,2213.8,-169.6,40.7,34.0},{1,643.4,2221.2,-169.6,98.9,34.0},
		{1,562.9,2232.8,-169.6,63.6,34.0},{1,511.7,2250.4,-169.6,43.5,34.0},{2,475.6,2253.4,-169.6,28.7,34.0},{2,798.6,1061.9,168.6,46.0,20.0},{2,877.2,815.6,-97.7,79.3,20.0},{2,871.7,872.9,-97.7,35.8,20.0},{2,860.0,930.4,-103.4,11.4,20.0},{2,736.2,1044.1,168.6,83.3,20.0},
		{2,794.6,942.8,71.9,16.4,20.0},{2,815.2,825.2,-10.0,72.8,20.0},{2,837.1,882.4,-109.3,48,42},{2,580.4,-115.7,6.8,34.4,14.0},{2,618.8,-120.8,6.8,43.2,14.0},{2,594.7,-57.7,-132.4,55.7,14.0},{2,1034.4,118.8,139.9,65.4,14.0},{2,974.3,93.7,140.8,57.4,14.0},
		{2,951.1,38.6,141.4,46.6,14.0},{2,896.2,24.7,141.4,56.6,14.0},{2,854.4,-18.0,141.4,61.8,14.0},{2,846.7,-81.8,58.7,85.8,7.0},{2,899.2,-115.2,-51.4,46.2,7.0},{2,893.6,-43.3,-51.4,59.3,14.0},{2,933.2,-8.0,-51.4,45.2,7.0},{2,978.6,28.6,-51.4,68.5,7.0},
		{2,1010.3,64.0,-51.4,26.5,14.0},{2,938.9,241.7,173.3,30.4,10.5},{2,689.2,186.0,170.3,65.4,14.0},{2,685.3,144.4,47.5,27.3,14.0},{2,736.6,143.0,-38.6,74.4,14.0},{2,808.1,170.8,-38.6,72.0,14.0},{2,2243.8,-1897.1,-31.0,34.0,34.0},{2,2706.5,-1439.9,-109.1,34.0,10.2},
		{2,2727.3,-1322.3,-116.6,34.0,34.0},{1,1508.7,-1415.5,20.9,98.9,10.2},{1,1597.9,-1459.0,20.9,98.8,34.0},{2,1677.0,-1481.4,20.9,64.9,34.0},{1,1713.8,-1496.7,20.9,14.7,34.0},{2,1747.7,-1508.1,20.9,56.8,34.0},{1,1790.7,-1532.6,20.9,41.1,34.0},{1,1828.4,-1543.1,20.9,36.9,34.0},
		{1,1862.0,-1553.7,23.0,30.9,34.0},{2,1897.5,-1568.8,27.6,40.7,34.0},{2,1933.9,-1598.2,35.1,43.4,34.0},{1,2039.3,-1698.0,51.7,39.5,34.0},{1,2066.7,-1731.5,51.7,47.0,34.0},{2,2096.5,-1775.1,51.7,58.4,34.0},{1,2130.6,-1818.9,51.7,52.7,34.0},{2,2168.9,-1856.5,51.7,53.6,34.0},
		{2,2281.7,-1877.1,-31.0,51.6,34.0},{2,2331.7,-1848.3,-31.0,63.9,34.0},{1,2402.9,-1808.7,-31.0,98.8,34.0},{1,2515.9,-1728.4,-42.7,59.3,34.0},{2,2557.7,-1669.9,-53.8,27.5,34.0},{1,2599.9,-1611.2,-58.0,14.7,34.0},{1,2619.8,-1575.3,-58.0,67.4,34.0},{1,2663.5,-1504.4,-58.0,98.9,34.0},
		{2,2692.8,-1458.6,-58.0,9.8,34.0},{2,2698.6,-1408.4,-93.7,12.1,34.0},{1,2709.4,-1278.8,-116.6,60.0,34.0},{2,2676.8,-1225.8,-116.6,63.8,34.0},{1,2646.5,-1170.5,-116.6,62.3,34.0},{1,2622.3,-1121.9,-116.6,46.3,34.0},{1,2605.5,-1085.5,-116.6,33.8,34.0},{1,2593.7,-1061.7,-116.6,19.4,34.0},
		{2,2579.2,-1030.7,-117.1,49.6,34.0},{2,2551.2,-978.7,-117.5,69.0,34.0},{1,2520.3,-900.2,-117.5,98.8,34.0},{1,2481.2,-831.0,-117.5,60.2,34.0},{1,2452.3,-781.7,-117.5,53.8,34.0},{1,2428.6,-735.4,-117.5,50.3,34.0},{1,2403.3,-681.3,-117.5,69.1,34.0},{2,2373.8,-635.3,-117.5,39.8,34.0},
		{1,2337.4,-603.2,-177.1,14.7,25.5},{2,2302.9,-598.9,-177.1,54.6,34.0},{2,2252.9,-594.9,-177.1,45.8,34.0},{1,2209.6,-590.6,-177.1,41.1,34.0},{1,2139.2,-595.9,-177.1,98.9,34.0},{1,2040.7,-581.7,-176.6,98.8,34.0},{1,1956.4,-581.5,-171.0,62.8,34.0},{1,1910.7,-571.1,-171.0,30.8,34.0},
		{1,1847.4,-556.1,-171.0,98.8,34.0},{2,1766.9,-552.5,-171.0,61.2,34.0},{1,1687.9,-539.7,-171.0,98.9,34.0},{2,1622.7,-525.4,-171.0,34.4,34.0},{1,1580.9,-562.8,92.2,14.7,17.0},{1,1585.3,-587.9,92.2,35.0,34.0},{1,1579.8,-631.8,92.2,53.1,34.0},{1,1582.3,-677.4,92.2,38.1,34.0},
		{1,1569.0,-716.6,92.2,41.2,34.0},{2,1570.6,-765.2,92.2,55.7,34.0},{1,1572.9,-842.6,92.2,98.9,34.0},{1,1571.9,-909.3,93.6,32.5,34.0},{2,1562.3,-943.3,96.6,33.2,34.0},{1,1552.2,-981.3,100.5,41.1,34.0},{1,1552.8,-1010.9,102.4,14.7,34.0},{1,1539.8,-1037.7,104.4,41.1,34.0},
		{1,1535.8,-1093.2,104.6,68.2,34.0},{1,1521.7,-1132.3,104.6,14.7,34.0},{2,1511.4,-1167.3,104.6,58.2,34.0},{1,1486.7,-1242.1,104.6,98.8,34.0},{1,1478.5,-1298.5,104.6,14.7,34.0},{1,1471.6,-1330.7,104.6,51.1,34.0},{2,1301.6,-1575.9,-162.6,34.0,10.2},{1,1108.1,-1620.1,116.4,98.8,34.0},
		{1,1074.3,-1700.7,102.1,15.0,34.0},{1,1086.7,-1756.9,85.3,64.1,34.0},{1,1078.6,-1806.2,84.9,16.0,34.0},{1,1140.5,-1838.5,10.6,98.8,17.0},{1,1239.2,-1848.0,10.6,98.9,34.0},{1,1300.6,-1867.3,10.6,29.0,34.0},{1,1353.8,-1807.9,-87.6,43.0,34.0},{1,1349.7,-1735.8,-96.6,14.7,34.0},
		{1,1329.8,-1677.0,-108.4,27.0,34.0},{1,1329.4,-1641.2,-108.4,41.1,34.0},{1,1314.7,-1616.7,-108.4,14.7,34.0},{1,1310.0,-1602.8,-108.4,14.7,34.0},{1,1222.2,-1569.2,166.3,63.8,34.0},{1,1182.6,-1582.5,166.3,19.4,34.0},{1,918.0,-1795.7,10.6,50.1,25.5},{1,941.9,-1679.8,-79.4,31.2,34.0},
		{1,952.9,-1653.1,-73.8,19.9,34.0},{2,871.2,-1646.9,-178.4,25.8,34.0},{1,834.3,-1673.1,110.2,48.0,17.0},{1,825.5,-1739.7,90.6,36.4,34.0},{1,1450.0,-2202.8,-3.7,52.3,25.0},{1,1490.3,-2194.2,-3.7,14.7,50.0},{1,1505.0,-2193.3,-3.7,14.7,50.0},{1,1519.7,-2192.3,-3.7,14.7,50.0},
		{1,1553.5,-2196.2,-3.7,52.3,50.0},{1,1606.3,-2192.0,-3.7,35.3,15.0},{1,1612.9,-2067.8,-84.7,52.3,50.0},{1,1614.9,-2017.6,-84.7,32.6,50.0},{1,1618.8,-1975.3,-84.7,32.6,50.0},{1,1623.9,-1939.9,-84.7,17.8,50.0},{1,1629.4,-1905.6,-81.4,26.9,50.0},{1,1636.4,-1857.4,-81.4,52.3,50.0},
		{1,1645.5,-1797.6,-81.4,52.3,50.0},{1,1654.2,-1739.9,-81.4,52.3,50.0},{1,1660.7,-1689.6,-81.4,35.5,50.0},{1,1657.5,-1647.3,-81.4,29.3,25.0},{1,1616.9,-1644.1,-159.1,14.7,15.0},{1,1587.7,-1626.6,-159.1,52.3,50.0},{1,1547.1,-1617.5,-159.1,14.7,50.0},{2,1513.6,-1606.8,-159.1,55.6,15.0},
		{2,1518.5,-1722.6,83.9,33.7,50.0},{1,1523.6,-1748.9,88.2,14.7,50.0},{1,1523.8,-1764.6,89.9,14.7,50.0},{2,1526.4,-1788.3,92.0,29.8,50.0},{1,1522.5,-1810.6,92.4,14.7,50.0},{1,1515.3,-1838.4,92.4,41.2,50.0},{1,1513.5,-1879.5,92.4,41.2,50.0},{1,1524.5,-1932.7,92.5,64.1,37.5},
		{2,1507.1,-1991.8,112.5,13.4,50.0},{2,1497.7,-2010.9,127.3,12.6,50.0},{2,1485.9,-2028.3,140.4,13.1,50.0},{1,1468.4,-2073.3,110.2,14.7,50.0},{1,1451.2,-2102.6,110.2,52.3,50.0},{1,1431.1,-2153.3,113.2,41.1,15.0},{1,2053.7,-2012.3,-79.1,14.7,50.0},{1,2057.5,-1988.4,-69.9,19.4,50.0},
		{2,1987.1,-1910.9,-128.3,34.5,50.0},{1,1951.6,-1876.0,-128.3,64.1,50.0},{2,1909.9,-1812.1,-128.3,69.3,50.0},{2,1851.1,-1746.1,-140.7,20.3,50.0},{2,1821.6,-1728.7,-150.0,20.3,50.0},{1,1786.1,-1724.5,98.6,26.9,15.0},{1,1777.8,-1786.9,98.6,26.9,25.0},{1,1769.9,-1833.8,98.6,52.3,50.0},
		{1,1763.3,-1882.5,98.6,26.9,50.0},{1,1756.7,-1918.8,98.6,24.2,50.0},{1,1756.2,-1958.5,95.4,34.9,50.0},{1,1746.9,-2013.2,95.2,52.3,50.0},{1,1743.5,-2059.1,95.2,26.9,50.0},{1,1741.0,-2107.9,95.2,51.4,50.0},{1,1734.9,-2152.4,95.2,17.8,25.0},{1,1813.7,-2139.4,-28.1,41.2,15.0},
		{2,1854.1,-2109.7,-28.1,58.2,50.0},{1,1906.1,-2089.9,-28.1,52.3,50.0},{2,1954.4,-2053.5,-28.1,48.3,50.0},{1,2003.2,-2038.2,-28.1,52.3,15.0},{2,1935.0,1767.5,41.4,84.0,30.0},{2,2009.3,1721.1,41.4,88.8,30.0},{2,2076.6,1692.7,42.5,46.3,30.0},{2,2100.3,1626.2,42.9,77.4,30.0},
		{2,2159.4,1575.5,42.9,78.3,30.0},{2,2209.1,1533.5,42.9,51.9,9.0},{2,2190.3,1639.2,-64.5,58.6,30.0},{2,2265.2,1681.9,-64.5,83.0,30.0},{2,2234.5,1794.4,-139.8,46.1,30.0},{2,2195.4,1827.3,-139.8,56.2,30.0},{2,2061.0,1917.7,-136.8,87.4,30.0},{2,1966.2,1873.4,41.6,48,42},
		{2,1936.9,1840.5,41.6,48,42},{2,2003.5,1840.2,41.6,48,42},{2,1974.3,1807.3,41.6,48,42},{2,2040.9,1807.0,41.6,48,42},{2,2011.7,1774.1,41.6,48,42},{3,2136.8,1839.5,41.6,48,42},{2,2107.5,1806.6,41.6,48,42},{2,2078.3,1773.7,41.6,48,42},
		{2,2049.1,1740.9,41.6,48,42},{3,2144.9,1773.4,41.6,48,42},{3,2115.7,1740.5,41.6,48,42},{2,2182.3,1740.2,41.6,48,42},{3,2153.1,1707.3,41.6,48,42},{3,2123.8,1674.4,41.6,48,42},{2,2056.4,1430.1,-137.1,90.9,30.0},{2,1968.2,1465.2,-137.1,86.0,9.0},
		{2,1863.8,1586.4,-138.6,50.5,30.0},{2,1807.4,1619.5,-138.6,77.8,30.0},{2,1744.1,1678.8,-138.6,95.5,30.0},{2,1657.6,1615.2,140.5,60.0,22.5},{2,1701.2,1578.1,36.3,62.8,15.0},{2,1776.2,1550.0,36.3,91.5,30.0},{2,1994.5,1168.9,-59.0,87.9,30.0},{2,2133.0,380.0,-175.6,51.1,16.5},
		{2,2084.5,385.2,-175.6,46.5,22.0},{2,2019.9,383.2,-175.6,82.1,22.0},{2,1938.9,383.8,-175.6,79.6,22.0},{2,1863.0,396.4,-175.6,73.7,22.0},{2,1803.4,372.7,-175.6,41.4,22.0},{2,1770.2,280.3,99.8,67.6,22.0},{2,1834.3,316.2,-15.0,60.8,22.0},{2,1877.7,359.1,-7.7,22.9,11.0},
		{2,1909.3,332.1,-1.6,19.8,22.0},{2,2016.0,322.6,6.9,56.5,22.0},{2,2073.8,303.9,6.9,62.9,22.0},{2,1948.7,172.6,-174.2,50.0,6.6},{2,1911.3,139.3,171.2,12.2,22.0},{2,1795.2,78.3,163.9,78.4,11.0},{2,1869.7,95.6,-16.0,75.0,22.0},{2,1941.9,104.3,-16.0,68.6,16.5},
		{2,2010.1,107.1,-16.0,63.9,16.5},{2,1899.0,-122.2,106.5,46.0,6.6},{2,1844.1,-375.8,8.9,46.0,22.0},{2,2119.2,-84.4,164.0,61.6,22.0},{2,2051.4,-77.4,164.0,65.0,22.0},{2,1997.1,-117.8,164.0,61.7,22.0},{2,1942.6,-121.5,164.0,45.0,22.0},{2,1916.9,-181.7,106.5,58.2,22.0},
		{2,1872.9,-228.2,106.5,55.9,22.0},{2,1852.1,-294.2,90.7,83.2,6.6},{2,1905.2,-362.1,8.9,70.6,22.0},{2,1960.1,-386.9,8.9,45.6,22.0},{2,2083.8,-393.2,3.0,74.7,22.0},{2,2146.6,-395.4,3.0,51.0,22.0},{2,2215.6,-396.4,3.0,86.9,11.0},{2,2188.7,-349.8,-118.9,47.1,22.0},
		{2,2143.8,-208.3,-108.6,81.2,22.0},{2,2119.4,-147.5,-108.4,49.2,22.0},{2,1414.9,-549.0,162.3,56.0,7.0},{2,1319.6,-780.6,-12.1,56.1,14.0},{2,1354.3,-761.9,-12.1,19.6,14.0},{2,1378.4,-740.9,-87.8,32.4,14.0},{2,1382.4,-708.8,-87.8,32.1,14.0},{2,1380.3,-672.1,-87.8,41.2,14.0},
		{2,1381.9,-628.2,-87.8,46.6,14.0},{2,1376.8,-574.0,162.3,31.8,14.0},{2,1343.8,-594.3,162.3,43.5,14.0},{2,1290.8,-633.3,95.6,63.0,14.0},{2,1292.9,-684.5,79.3,12.6,14.0},{2,1659.9,-189.8,104.3,46.0,6.6},{2,1622.0,-337.7,50.7,46.0,11.0},{2,1674.5,-353.6,9.1,49.6,22.0},
		{2,1696.1,-288.9,-90.2,48.2,22.0},{2,1682.6,-248.7,-85.2,22.2,22.0},{2,1694.3,-177.7,164.0,36.8,22.0},{2,1648.9,-301.3,104.3,38.4,16.5},{2,1802.2,1207.8,173.3,46.0,20.0},{2,1739.1,1016.1,-19.0,82.2,20.0},{2,1804.5,1029.1,-19.0,50.0,20.0},{2,1822.0,1150.2,-112.9,56.5,20.0},
		{2,1743.7,1193.1,173.3,73.6,20.0},{2,1672.5,1191.0,173.3,68.2,20.0},{2,1624.7,1178.5,173.3,29.5,20.0},{2,1580.6,1196.3,173.3,54.2,20.0},{2,1532.6,1151.4,173.3,51.4,20.0},{2,1478.1,1162.8,173.3,54.4,15.0},{2,1471.4,1113.6,67.1,45.7,20.0},{2,1507.2,1088.2,73.8,15.9,20.0},
		{2,1497.3,1064.6,78.0,18.1,20.0},{2,1536.0,1046.5,82.9,20.4,20.0},{2,1495.6,1010.3,90.2,33.2,20.0},{2,1549.7,1005.7,-13.6,50.4,20.0},{2,1626.0,1008.7,-13.6,99.3,20.0},{3,1748.2,1119.9,168.2,48,42},{3,1739.3,1163.0,168.2,48,42},{2,1699.3,1109.7,168.2,48,42},
		{3,1690.3,1152.7,168.2,48,42},{3,1650.4,1099.4,168.2,48,42},{2,1641.4,1142.5,168.2,48,42},{2,1601.4,1089.2,168.2,48,42},{3,1592.4,1132.3,168.2,48,42},{2,2286.1,348.2,-45.0,65.5,6.6},{2,2584.3,345.8,135.0,46.0,11.0},{2,2466.3,95.0,10.8,82.6,22.0},
		{2,2535.3,105.3,10.8,49.2,22.0},{2,2609.0,96.6,-96.3,51.6,16.5},{2,2618.4,184.0,-83.6,24.0,22.0},{2,2624.1,211.6,-76.9,19.8,22.0},{2,2611.5,240.5,-72.3,19.0,22.0},{2,2635.3,317.2,-171.2,64.4,22.0},{2,2558.2,298.5,135.0,57.8,22.0},{2,2503.0,257.7,135.0,78.0,22.0},
		{2,2448.6,218.2,135.0,54.7,22.0},{2,2400.0,166.8,135.0,86.7,22.0},{2,2310.4,81.2,135.0,47.9,6.6},{2,2998.3,288.5,-162.9,23.8,10.2},{1,2816.9,-0.1,9.1,98.9,34.0},{1,2879.8,-13.8,9.1,29.8,34.0},{1,2906.9,-23.1,9.1,26.4,25.5},{1,2922.4,31.5,-93.6,50.9,17.0},
		{1,2922.7,136.3,-81.7,17.5,34.0},{1,2922.1,158.5,-76.3,20.3,34.0},{1,2947.5,227.8,-65.5,36.1,34.0},{2,2951.9,301.9,-169.2,36.0,34.0},{2,2865.8,310.9,-171.2,18.6,34.0},{1,2806.8,229.3,116.2,98.8,34.0},{1,2774.2,166.8,97.7,34.0,17.0},{1,2782.8,71.0,83.9,50.0,34.0},
		{2,2457.5,-427.9,5.1,76.9,22.0},{2,2533.2,-435.2,5.1,75.2,22.0},{2,2588.5,-424.0,5.1,32.9,22.0},{2,2623.9,-395.9,-72.8,74.3,6.6},{2,2643.8,-254.8,-91.8,59.2,22.0},{2,2655.8,-182.8,-92.2,84.5,22.0},{2,2604.9,-120.4,-169.2,74.5,11.0},{2,2537.2,-126.0,-169.2,56.5,22.0},
		{2,2470.0,-116.1,-169.2,79.2,22.0},{2,2385.1,-98.3,-169.2,94.2,22.0},{2,2307.9,-71.9,-169.2,67.5,22.0},{2,2305.5,-137.9,71.6,81.3,16.5},{2,2381.2,-251.0,61.0,57.3,22.0},{2,2397.3,-308.3,60.9,58.7,22.0},{2,2432.8,-354.2,60.9,55.9,22.0},{2,2889.5,-494.1,-70.9,34.0,34.0},
		{1,2765.3,-467.8,5.5,26.9,17.0},{2,2804.4,-467.6,5.5,50.9,34.0},{1,2836.9,-473.2,5.5,14.7,34.0},{1,2904.8,-450.7,-70.9,57.9,34.0},{1,2921.2,-402.8,-70.9,43.5,34.0},{1,2943.7,-336.4,-87.1,12.1,34.0},{1,2942.9,-249.7,-94.3,98.8,34.0},{1,2938.1,-187.0,-94.3,27.0,34.0},
		{1,2875.9,-152.3,-171.1,98.8,10.2},{1,2803.2,-317.0,97.1,23.3,34.0},{1,2783.1,-386.5,107.0,30.5,34.0},{2,3203.0,-511.8,-70.4,34.0,34.0},{1,3057.1,-517.2,12.4,14.7,34.0},{1,3078.7,-520.3,12.4,28.6,34.0},{1,3102.3,-524.4,12.4,19.4,34.0},{1,3127.7,-535.4,12.4,34.7,34.0},
		{1,3230.9,-451.2,-70.4,98.8,34.0},{1,3255.7,-355.2,-70.4,98.9,34.0},{1,3288.8,-262.0,-70.4,98.9,17.0},{1,3250.6,-210.7,-171.2,68.5,17.0},{1,3191.0,-201.5,-171.2,52.3,34.0},{1,3123.7,-204.3,-171.2,64.1,34.0},{1,3073.2,-361.1,98.9,25.0,34.0},{1,3035.6,-481.9,109.1,98.8,17.0},
		{2,3278.4,189.2,-160.3,34.0,10.2},{2,3322.3,120.1,-138.0,24.0,34.0},{2,3307.4,138.4,-128.1,12.2,34.0},{2,3296.5,147.6,-125.6,12.7,34.0},{2,3285.1,162.9,-114.4,11.6,34.0},{1,3218.0,217.2,-160.3,98.8,34.0},{1,3154.2,234.7,-160.3,33.1,34.0},{1,3125.7,243.8,-160.3,26.5,34.0},
		{1,3086.1,204.0,114.5,36.0,34.0},{1,3071.8,172.5,114.5,33.2,34.0},{1,3051.2,117.3,100.3,13.4,34.0},{1,3064.0,48.5,86.4,64.1,34.0},{1,3055.3,-13.8,86.4,43.2,34.0},{1,3216.0,-62.7,8.8,98.9,34.0},{1,3278.2,-76.9,8.8,28.4,34.0},{1,3319.2,-33.1,-89.5,29.4,17.0},
		{1,3315.4,31.0,-89.5,98.9,34.0},{2,3134.2,1144.0,-180.0,60.0,14.0},{2,2904.1,1176.4,87.7,51.0,14.0},{2,3031.5,987.4,-34.5,67.8,14.0},{2,3063.5,1023.8,-34.5,26.2,14.0},{2,3094.6,1021.2,-45.6,18.2,14.0},{2,3097.1,1048.2,-57.0,25.8,14.0},{2,3127.2,1080.8,-80.9,29.0,7.0},
		{2,3080.3,1142.7,-180.0,47.9,14.0},{2,3020.1,1117.1,-180.0,72.3,14.0},{2,2934.3,1098.3,80.1,23.4,14.0},{2,2907.1,1057.6,69.9,20.4,14.0},{2,2938.8,1030.5,59.4,26.8,14.0},{2,2961.0,984.0,46.9,63.0,14.0},{3,3017.9,1029.0,-0.0,48,42},{2,2877.7,1356.0,-0.0,42.0,10.5},
		{2,2987.4,1541.6,131.2,89.4,14.0},{2,2933.5,1486.5,112.4,22.5,14.0},{2,2928.5,1425.6,99.0,82.7,14.0},{2,2992.3,1354.6,-0.0,94.0,14.0},{2,3073.9,1411.9,-99.2,55.7,14.0},{2,3062.1,1467.3,-111.5,25.6,14.0},{2,3049.1,1488.2,-123.7,17.2,14.0},{2,3025.2,1497.2,-134.3,19.3,14.0},
		{2,3011.7,1421.0,90.0,48,42},{3,2967.7,1421.0,90.0,48,42},{2,2367.3,1959.1,-54.9,28.1,30.0},{2,2394.6,1983.7,-48.2,28.4,30.0},{2,2421.9,2007.5,-41.1,28.3,30.0},{2,2441.8,2038.9,-34.8,26.7,30.0},{2,2483.4,2027.5,-28.5,19.3,30.0},{2,2500.8,2058.6,-23.3,29.4,30.0},
		{2,2555.3,2071.9,-14.9,64.4,30.0},{2,2627.6,2103.4,-13.8,88.8,30.0},{2,2690.8,2132.7,-13.8,48.0,9.0},{2,2742.5,2123.1,-13.8,47.8,9.0},{2,2454.4,2158.1,-172.0,63.4,30.0},{2,2385.8,2181.0,-172.0,78.9,30.0},{2,2306.6,2173.2,-172.0,75.9,30.0},{2,2226.0,2197.3,151.9,12.8,30.0},
		{2,2164.9,2168.7,176.7,13.8,30.0},{2,2148.5,2158.5,178.9,14.4,30.0},{2,2219.2,2083.3,43.3,84.0,30.0},{2,2303.5,1978.3,40.2,46.6,30.0},{2,2343.6,1938.2,40.2,66.3,15.0},{2,2294.6,2086.4,8.0,48,42},{2,2344.1,2079.5,8.0,48,42},{3,2338.0,2035.9,8.0,48,42},
		{3,2393.6,2072.5,8.0,48,42},
	},
	walls = {
		{1,3000.1,1694.2,3043.5,1669.0},{1,3043.5,1669.0,3081.2,1647.1},{1,3081.2,1647.1,3118.0,1620.6},{1,3118.0,1620.6,3138.1,1601.6},{1,3138.1,1601.6,3154.3,1582.9},{1,3154.3,1582.9,3171.7,1558.1},{1,3171.7,1558.1,3179.8,1543.7},{1,3179.8,1543.7,3193.2,1514.5},
		{1,3193.2,1514.5,3199.9,1494.0},{1,3199.9,1494.0,3210.1,1445.0},{1,3210.1,1445.0,3219.5,1386.7},{1,3219.5,1386.7,3227.7,1335.7},{1,3235.7,1286.3,3245.6,1254.5},{1,3248.6,1188.8,3254.5,1140.3},{1,3022.5,809.3,3016.4,805.2},{1,3007.0,797.6,2972.4,750.9},
		{1,2822.6,560.0,2791.4,532.8},{1,2791.4,532.8,2762.7,511.9},{1,2762.7,511.9,2704.7,478.6},{1,2704.7,478.6,2745.9,472.1},{1,3241.6,-965.0,3221.7,-1021.7},{1,3129.9,-1174.7,3125.0,-1180.5},{1,2710.7,-1746.0,2675.5,-1792.9},{1,2629.7,-1842.4,2597.0,-1871.2},
		{1,2597.0,-1871.2,2552.1,-1904.4},{1,1856.4,-2298.1,1794.6,-2329.2},{1,1794.6,-2329.2,1741.0,-2343.9},{1,1481.3,-2361.3,1473.9,-2361.8},{1,764.2,-2271.8,713.9,-2265.5},{1,678.7,-2263.1,670.6,-2262.8},{1,519.5,-2256.6,512.7,-2256.4},{1,-296.3,-2356.5,-345.9,-2362.3},
		{1,-1181.7,-2314.8,-1191.5,-2314.4},{1,-1355.5,-2305.5,-1420.0,-2295.4},{1,-1657.8,-2218.3,-1666.3,-2215.3},{1,-1715.6,-2197.8,-1722.6,-2195.3},{1,-2123.4,-1992.9,-2128.6,-1989.7},{1,-2205.4,-1931.3,-2242.7,-1887.6},{1,-2673.6,-1372.4,-2695.2,-1344.1},{1,-2916.0,-600.3,-2923.6,-554.6},
		{1,-2853.8,135.7,-2830.4,186.5},{1,-2830.4,186.5,-2811.5,218.0},{1,-2811.5,218.0,-2783.2,256.9},{1,-2783.2,256.9,-2758.9,284.3},{1,-2758.9,284.3,-2718.4,321.6},{1,-2718.4,321.6,-2692.7,341.4},{1,-2562.5,410.3,-2554.5,414.1},{1,-2362.6,502.4,-2316.0,519.5},
		{1,-2316.0,519.5,-2275.0,530.9},{1,-2197.4,546.5,-2139.9,557.4},{1,-2139.9,557.4,-2104.6,564.1},{1,-2104.6,564.1,-2043.1,575.7},{1,-2043.1,575.7,-2002.4,583.4},{1,-2002.4,583.4,-1960.1,591.4},{1,-1960.1,591.4,-1904.0,602.0},{1,-1977.2,898.6,-1984.2,898.8},
		{1,-2244.9,908.0,-2292.0,905.1},{1,-2727.9,1295.9,-2728.2,1303.4},{1,-2728.5,1314.7,-2734.4,1327.8},{1,-2754.0,1392.3,-2751.6,1412.9},{1,-2615.2,1571.5,-2609.9,1576.6},{1,-1910.6,2111.2,-1849.8,2136.0},{1,-1246.5,2330.0,-1238.8,2332.3},{1,-920.7,2427.2,-868.1,2439.6},
		{1,-868.1,2439.6,-808.2,2448.5},{1,2655.5,2338.9,2715.7,2318.9},{1,3013.0,1981.1,2988.6,1993.4},{1,2628.2,1944.2,2622.2,1942.7},{1,2587.4,1934.2,2557.7,1924.3},{1,2544.0,1918.0,2521.8,1902.6},{1,2511.9,1894.4,2498.8,1879.8},{1,2490.5,1868.6,2470.0,1829.8},
		{1,2401.1,1682.2,2397.0,1673.5},{1,2203.3,1266.5,2199.3,1258.2},{1,2100.3,1088.2,2096.1,1081.2},{1,1741.0,873.0,1741.0,842.2},{1,1741.0,564.0,1819.7,557.9},{1,1819.7,557.9,1904.8,551.4},{1,2561.3,500.9,2623.1,530.4},{1,2703.1,570.6,2728.5,587.6},
		{1,2759.1,612.3,2777.3,630.6},{1,2809.4,668.5,2862.2,739.8},{1,2769.4,1069.9,2763.6,1134.8},{1,2760.3,1216.0,2754.6,1251.6},{1,2754.6,1251.6,2767.1,1311.4},{1,2787.4,1458.7,2798.1,1507.3},{1,2798.1,1507.3,2813.8,1549.8},{1,2824.5,1570.2,2845.5,1603.4},
		{1,2845.5,1603.4,2902.9,1668.6},{1,-234.9,2325.2,-224.0,2268.2},{1,36.8,2173.2,71.7,2174.2},{1,83.9,2176.9,116.7,2186.4},{1,304.0,2249.2,320.5,2254.8},{1,320.5,2254.8,284.3,2289.2},{1,284.3,2289.2,252.1,2319.9},{1,-193.2,2108.2,-180.2,2040.5},
		{1,-164.0,1956.4,-162.6,1948.7},{1,172.4,1902.2,183.9,1903.5},{1,246.4,1917.3,254.6,1919.3},{1,446.4,1967.1,504.5,1981.6},{1,504.5,1981.6,484.8,2019.0},{1,88.3,2104.0,55.9,2101.3},{1,-174.0,2107.6,-193.2,2108.2},{1,-264.0,1462.6,-219.6,1458.5},
		{1,-245.7,1889.9,-251.5,1921.0},{1,-251.5,1921.0,-256.7,1948.0},{1,-256.7,1948.0,-267.6,2005.9},{1,-620.9,2109.1,-678.6,2097.3},{1,-936.1,1934.3,-929.3,1877.2},{1,-918.6,1581.0,-916.4,1520.2},{1,-166.0,1310.5,-203.6,1272.8},{1,-311.8,1164.7,-351.0,1125.5},
		{1,-351.0,1125.5,-316.5,1118.0},{1,-177.5,1087.9,-148.9,1086.3},{1,-50.2,1080.7,5.4,1077.6},{1,36.4,1099.3,31.2,1142.2},{1,-399.5,1062.4,-395.8,1032.5},{1,-388.4,972.9,-385.1,929.7},{1,-385.1,929.7,-387.8,893.2},{1,-387.8,893.2,-399.7,847.1},
		{1,-399.7,847.1,-422.9,772.0},{1,-422.9,772.0,-360.7,772.0},{1,-178.7,771.9,-112.4,767.7},{1,38.4,875.7,51.9,957.3},{1,-115.6,1012.0,-208.8,1020.4},{1,-321.3,1045.2,-399.5,1062.4},{1,-137.3,665.1,-184.3,667.2},{1,409.0,556.3,409.0,597.7},
		{1,-759.0,668.0,-759.0,647.7},{4,-759.0,396.6,-759.0,377.6},{4,-759.0,377.6,-708.9,371.8},{4,-708.9,371.8,-648.0,364.8},{4,-648.0,364.8,-592.9,358.4},{4,-592.9,358.4,-550.4,353.5},{4,-550.4,353.5,-505.3,348.3},{4,-505.3,348.3,-451.8,342.2},
		{4,-451.8,342.2,-390.3,335.1},{4,-390.3,335.1,-356.6,331.2},{4,-356.6,331.2,-289.3,323.4},{4,-289.3,323.4,-258.5,319.9},{4,-258.5,319.9,-193.6,312.4},{4,-193.6,312.4,-145.8,308.2},{4,-82.7,306.4,-47.9,306.2},{4,-47.9,306.2,13.7,305.6},
		{4,13.7,305.6,72.0,305.2},{4,72.0,305.2,100.4,304.9},{4,100.4,304.9,168.9,304.3},{4,168.9,304.3,223.9,303.9},{4,223.9,303.9,271.3,303.5},{4,271.3,303.5,304.2,303.2},{4,304.2,303.2,360.1,302.8},{4,360.1,302.8,409.0,302.3},
		{1,-223.2,146.7,-224.5,140.1},{1,-234.1,88.7,-235.6,80.7},{1,-223.7,-107.0,-186.9,-108.5},{1,-39.6,-16.5,-38.5,-7.8},{1,-32.2,44.1,-31.2,51.5},{1,-17.7,149.3,-15.1,168.2},{1,-34.2,202.0,-73.2,202.4},{1,-121.6,202.8,-173.2,205.8},
		{1,-173.2,205.8,-211.5,209.7},{4,-177.5,-200.9,-209.5,-199.7},{4,-251.6,-235.2,-248.8,-287.2},{4,-245.5,-309.5,-242.1,-322.3},{4,-224.1,-364.8,-204.9,-405.0},{4,-54.2,-443.6,-20.2,-443.4},{4,-20.2,-443.4,-37.0,-399.9},{4,-37.0,-399.9,-57.8,-335.3},
		{4,-60.6,-315.3,-60.4,-256.7},{4,-60.4,-256.7,-58.6,-205.7},{4,177.5,-442.0,172.8,-373.5},{4,10.9,-278.9,11.8,-310.9},{4,14.0,-325.6,40.9,-401.8},{4,343.4,-228.5,244.3,-216.6},{4,244.3,-216.6,250.2,-303.1},{4,282.6,-776.0,287.6,-848.3},
		{4,287.6,-848.3,370.9,-827.5},{4,462.1,-686.8,462.0,-619.8},{4,461.9,-535.0,466.2,-445.7},{4,473.3,-334.5,479.0,-244.8},{4,303.7,-990.9,307.8,-1015.7},{4,307.8,-1015.7,352.0,-994.3},{4,352.0,-994.3,400.6,-970.8},{4,539.3,-903.5,578.6,-884.5},
		{4,578.6,-884.5,635.0,-857.1},{4,635.0,-857.1,688.7,-838.3},{4,982.0,-617.0,975.7,-591.9},{4,975.7,-591.9,920.1,-636.4},{4,890.7,-659.9,822.2,-714.8},{4,822.2,-714.8,774.5,-752.9},{4,774.5,-752.9,721.2,-795.2},{4,721.2,-795.2,654.3,-835.4},
		{4,654.3,-835.4,601.4,-854.2},{4,601.4,-854.2,536.4,-870.6},{4,536.4,-870.6,449.9,-892.3},{4,449.9,-892.3,367.6,-912.8},{4,367.6,-912.8,293.7,-931.3},{4,879.8,-1505.7,899.9,-1504.1},{4,1177.8,-1438.6,1253.6,-1420.0},{4,1253.6,-1420.0,1259.4,-1405.3},
		{4,1054.8,-908.2,1042.7,-859.8},{4,983.7,-819.9,926.9,-837.9},{4,667.4,-921.1,620.5,-943.9},{4,410.6,-1045.9,320.2,-1089.8},{1,749.8,-1603.9,703.4,-1601.4},{1,421.4,-1601.4,404.7,-1614.8},{1,404.7,-1614.8,408.1,-1648.3},{1,412.1,-1689.2,412.9,-1696.8},
		{1,482.9,-1743.5,491.5,-1745.1},{1,632.5,-1771.6,685.6,-1781.6},{1,719.5,-1764.1,720.0,-1737.7},{1,720.0,-1737.7,721.0,-1699.4},{1,721.0,-1699.4,734.7,-1645.7},{1,734.7,-1645.7,749.8,-1603.9},{1,1375.8,-1988.5,1317.4,-1977.5},{1,1254.4,-1965.7,1247.6,-1964.4},
		{1,1099.0,-1936.5,1090.6,-1934.9},{1,344.1,-2025.3,336.3,-2054.1},{1,356.7,-2117.9,395.9,-2119.5},{1,1134.0,-2216.9,1139.1,-2218.0},{1,1206.0,-2203.8,1231.9,-2196.6},{1,1304.6,-2158.1,1320.3,-2131.8},{1,1356.5,-2039.8,1375.8,-1988.5},{3,-1579.2,2087.4,-1586.1,2085.0},
		{3,-1701.7,2046.5,-1715.4,1985.4},{3,-1726.8,1934.4,-1728.2,1928.1},{3,-1756.0,1834.1,-1758.9,1825.6},{3,-1780.2,1765.1,-1783.4,1756.1},{3,-1792.3,1730.8,-1733.5,1711.3},{3,-1684.3,1693.6,-1678.1,1691.4},{3,-1628.9,1673.7,-1620.9,1670.8},{3,-1574.0,1653.9,-1549.0,1712.7},
		{3,-1528.6,1760.8,-1524.7,1769.9},{3,-1510.9,1802.5,-1506.1,1813.7},{3,-1493.8,1853.1,-1485.4,1887.6},{3,-1472.9,1938.4,-1470.9,1946.6},{3,-1458.5,1997.4,-1456.6,2004.9},{3,-1447.5,2042.1,-1459.9,2085.5},{3,-1459.9,2085.5,-1494.0,2093.7},{3,-1507.5,2100.4,-1518.4,2107.6},
		{3,-1403.0,1481.8,-1437.4,1494.1},{3,-1535.8,1529.4,-1544.9,1532.6},{3,-1676.1,1579.6,-1683.7,1582.4},{3,-1796.3,1622.7,-1802.1,1624.8},{3,-1831.3,1632.5,-1879.9,1642.3},{3,-1931.1,1652.7,-1938.6,1654.2},{3,-2040.0,1674.7,-2047.5,1676.2},{3,-2209.7,1708.9,-2235.9,1684.6},
		{3,-2322.8,1667.3,-2366.2,1626.0},{3,-2404.2,1590.0,-2410.4,1584.0},{3,-2456.9,1539.9,-2463.2,1533.9},{3,-2587.8,1415.6,-2592.2,1411.4},{3,-2617.1,1387.8,-2610.5,1376.3},{3,-2610.5,1376.3,-2554.2,1379.4},{3,-2554.2,1379.4,-2484.8,1383.2},{3,-2432.5,1386.1,-2424.5,1386.5},
		{3,-2372.3,1389.4,-2365.9,1389.7},{3,-2313.7,1392.6,-2305.9,1393.0},{3,-2253.7,1395.9,-2244.6,1396.4},{3,-2226.8,1397.3,-2219.7,1397.7},{3,-2192.9,1399.2,-2180.2,1399.9},{3,-2128.0,1402.8,-2121.7,1403.1},{3,-2086.5,1405.0,-2080.1,1404.8},{3,-2028.0,1400.9,-2018.6,1400.2},
		{3,-1966.4,1396.4,-1958.0,1395.7},{3,-1894.1,1391.0,-1886.1,1390.4},{3,-1850.9,1387.8,-1842.4,1387.2},{3,-1790.2,1383.3,-1784.0,1382.9},{3,-1759.9,1381.1,-1751.5,1380.5},{3,-1699.4,1376.6,-1692.2,1376.1},{3,-1668.1,1374.3,-1659.0,1373.6},{3,-1624.2,1371.1,-1615.4,1370.4},
		{3,-1563.2,1366.6,-1555.8,1366.0},{3,-1543.1,1365.1,-1521.3,1383.3},{3,-1420.7,1467.1,-1403.0,1481.8},{1,-1106.0,1132.3,-1077.3,1125.6},{1,-1039.6,1146.5,-1034.4,1178.3},{1,-1013.0,1310.7,-1011.9,1317.8},{1,-1004.8,1361.6,-1000.4,1388.8},{1,-1023.8,1424.8,-1090.9,1430.4},
		{1,-1260.8,1444.6,-1283.1,1446.4},{1,-960.8,1180.6,-971.0,1117.5},{1,-564.9,1052.0,-542.1,1076.8},{1,-542.1,1076.8,-604.6,1079.7},{1,-604.6,1079.7,-688.8,1083.6},{1,-688.8,1083.6,-722.8,1086.5},{1,-722.8,1086.5,-760.8,1097.0},{1,-937.2,1170.7,-960.8,1180.6},
		{1,-841.0,660.5,-841.0,675.8},{1,-1298.2,776.4,-1334.1,783.4},{1,-1334.1,783.4,-1387.9,793.7},{1,-1387.9,793.7,-1424.6,800.8},{1,-1424.6,800.8,-1458.2,807.2},{1,-1458.2,807.2,-1487.3,812.8},{1,-1487.3,812.8,-1510.6,817.3},{4,-870.0,378.1,-841.0,379.7},
		{1,-1795.1,581.7,-1788.3,566.8},{1,-1777.6,556.6,-1737.0,527.0},{1,-1610.0,434.5,-1558.9,401.3},{1,-1511.5,378.9,-1461.9,362.6},{1,-1421.8,354.7,-1383.5,351.0},{4,-841.0,-37.9,-841.0,10.0},{4,-841.0,187.7,-841.0,225.6},{4,-883.4,273.1,-932.5,270.3},
		{4,-1108.5,260.3,-1150.6,257.9},{4,-1150.6,257.9,-1181.7,256.1},{4,-1246.3,252.4,-1302.8,249.2},{4,-1302.8,249.2,-1362.9,247.1},{4,-1362.9,247.1,-1430.1,251.0},{4,-1472.2,258.6,-1515.3,269.9},{4,-1515.3,269.9,-1556.2,284.9},{4,-1796.9,442.0,-1816.6,456.3},
		{4,-1816.6,456.3,-1821.7,396.6},{4,-1836.5,214.0,-1835.4,158.1},{4,-1816.3,-71.2,-1801.9,-78.2},{4,-1801.9,-78.2,-1787.8,-88.3},{4,-1770.5,-108.5,-1767.0,-113.9},{4,-1767.0,-113.9,-1702.9,-110.1},{4,-1392.4,-91.6,-1359.3,-89.6},{4,-1359.3,-89.6,-1310.6,-87.5},
		{4,-1310.6,-87.5,-1247.4,-85.2},{4,-1247.4,-85.2,-1215.9,-84.1},{4,-1215.9,-84.1,-1150.5,-81.7},{4,-1150.5,-81.7,-1106.7,-80.1},{4,-1106.7,-80.1,-1066.1,-78.6},{4,-1066.1,-78.6,-1036.6,-77.6},{4,-1036.6,-77.6,-1008.8,-76.6},{4,-870.6,-153.6,-929.2,-155.7},
		{4,-1166.5,-280.7,-1170.7,-291.2},{4,-1173.9,-305.6,-1177.3,-330.8},{4,-887.0,-229.8,-863.2,-163.8},{4,-963.0,-655.2,-905.8,-656.9},{4,-800.2,-659.1,-754.0,-657.7},{4,-754.0,-657.7,-706.9,-656.3},{4,-663.4,-620.4,-675.9,-554.0},{4,-680.0,-532.2,-685.0,-517.7},
		{4,-786.8,-256.6,-798.6,-226.2},{4,-798.6,-226.2,-816.5,-275.6},{4,-816.5,-275.6,-832.4,-319.9},{4,-843.1,-349.5,-861.0,-408.4},{4,-951.7,-637.9,-963.0,-655.2},{4,-1033.7,-765.1,-1050.1,-799.1},{4,-1078.8,-875.8,-1088.2,-900.9},{4,-1088.2,-900.9,-1055.6,-899.2},
		{4,-1055.6,-899.2,-1016.3,-897.3},{4,-658.7,-898.8,-610.8,-901.3},{4,-610.8,-901.3,-619.6,-854.3},{4,-634.3,-775.7,-635.5,-769.7},{4,-968.1,-727.1,-1008.9,-725.8},{4,-689.8,-1484.4,-683.1,-1484.6},{4,-642.9,-991.8,-707.8,-988.4},{4,-1063.0,-991.7,-1104.4,-993.8},
		{1,-655.8,-1589.8,-697.0,-1588.2},{1,-1109.9,-1572.3,-1137.0,-1573.0},{1,-1753.4,-1560.0,-1768.0,-1558.8},{1,-1768.0,-1558.8,-1787.8,-1579.5},{1,-1863.6,-1796.1,-1863.6,-1811.3},{1,-1460.7,-2148.1,-1404.4,-2164.1},{1,-1364.1,-2171.9,-1332.2,-2175.3},{1,-910.1,-2145.6,-904.6,-2145.2},
		{1,-749.5,-1961.8,-745.0,-1951.6},{1,-745.0,-1951.6,-744.1,-1946.8},{1,-688.0,-1758.5,-681.0,-1726.3},{1,-657.7,-1600.3,-655.8,-1589.8},{3,-2594.4,1248.7,-2594.2,1242.6},{3,-2591.2,1149.1,-2590.9,1139.3},{3,-2587.0,1016.2,-2574.2,1006.5},{3,-2546.0,968.9,-2514.8,971.3},
		{3,-2392.0,980.5,-2386.0,980.9},{3,-2350.8,983.6,-2344.6,984.0},{3,-2287.3,988.3,-2219.6,989.2},{3,-2116.9,985.5,-2108.9,985.2},{3,-2041.9,982.9,-2032.2,982.5},{3,-1915.4,978.4,-1906.8,978.1},{3,-1882.8,977.3,-1842.8,1027.7},{3,-1802.9,1077.9,-1797.4,1085.0},
		{3,-1639.1,1281.1,-1624.8,1295.0},{3,-1624.8,1295.0,-1672.8,1298.5},{3,-1778.9,1306.4,-1787.3,1307.0},{3,-1839.4,1310.8,-1849.4,1311.6},{3,-1873.5,1313.4,-1883.5,1314.1},{3,-1901.3,1315.4,-1910.3,1316.1},{3,-1961.5,1319.9,-1969.3,1320.4},{3,-2033.3,1325.2,-2041.3,1325.8},
		{3,-2093.5,1328.8,-2099.7,1328.4},{3,-2152.0,1325.5,-2158.4,1325.2},{3,-2185.3,1323.7,-2196.7,1323.1},{3,-2232.2,1321.1,-2240.7,1320.6},{3,-2267.6,1319.1,-2279.5,1318.5},{3,-2297.3,1317.5,-2307.8,1316.9},{3,-2342.7,1315.0,-2351.5,1314.5},{3,-2403.7,1311.6,-2410.7,1311.2},
		{3,-2462.9,1308.3,-2472.0,1307.8},{3,-2500.7,1306.3,-2510.7,1305.7},{3,-2546.0,1303.8,-2552.0,1303.4},{3,-2552.0,1303.4,-2596.0,1301.0},{1,-1553.8,1219.0,-1581.3,1189.3},{1,-1736.3,994.7,-1755.9,970.0},{1,-1755.9,970.0,-1689.3,957.3},{1,-1637.4,947.4,-1610.9,942.3},
		{1,-1574.8,964.7,-1571.6,998.1},{1,-1566.7,1050.2,-1566.0,1057.4},{1,-1560.5,1120.0,-1557.2,1169.6},{1,-1557.2,1169.6,-1553.8,1219.0},{4,-1804.1,-243.1,-1808.8,-306.4},{4,-1536.5,-487.9,-1515.9,-457.7},{4,-1524.5,-395.2,-1570.9,-368.4},{4,-1735.8,-273.2,-1796.3,-238.3},
		{4,-1606.0,-589.6,-1647.5,-571.4},{4,-1808.4,-500.6,-1822.9,-494.2},{4,-1822.9,-494.2,-1825.1,-536.6},{4,-1826.0,-565.4,-1824.0,-610.0},{4,-1790.0,-881.6,-1781.4,-890.3},{4,-1781.4,-890.3,-1768.4,-909.7},{4,-1628.4,-624.0,-1606.0,-589.6},{4,-1410.8,-1262.7,-1385.0,-1268.2},
		{4,-1385.0,-1268.2,-1385.4,-1247.0},{4,-1385.4,-1247.0,-1388.6,-1231.6},{4,-1715.2,-1005.7,-1775.0,-1001.5},{4,-1782.0,-1270.4,-1784.4,-1304.3},{4,-1759.5,-1455.2,-1693.9,-1460.5},{4,-1503.0,-1475.8,-1448.3,-1476.7},{4,-1601.3,-1296.5,-1663.9,-1287.4},{4,-1744.1,-1275.8,-1782.0,-1270.4},
		{1,-2674.5,-873.8,-2671.2,-877.8},{1,-1927.4,-215.0,-1936.4,-199.3},{1,-2792.7,-539.6,-2782.4,-594.9},{1,-2732.4,-791.9,-2719.4,-842.5},{1,-2357.8,-1487.4,-2350.2,-1488.9},{1,-2336.0,-1493.8,-2310.2,-1508.6},{1,-2184.2,-1517.3,-2179.8,-1516.6},{1,-2161.6,-1280.2,-2162.3,-1270.5},
		{1,-2193.2,-1240.2,-2260.0,-1248.6},{1,-2389.9,-1265.0,-2443.6,-1265.1},{1,-2542.4,-1263.4,-2590.3,-1262.6},{1,-2590.3,-1262.6,-2571.7,-1287.7},{1,-2428.5,-1447.4,-2393.9,-1485.9},{1,-1884.9,-1250.2,-1885.9,-1189.1},{1,-1961.0,-988.5,-2014.9,-987.3},{1,-2014.9,-987.3,-2068.3,-986.2},
		{1,-2101.2,-1014.3,-2098.6,-1080.5},{1,-2080.9,-1410.8,-2077.3,-1462.8},{1,-2051.8,-1491.5,-2017.1,-1483.7},{1,-2002.8,-1480.4,-1945.6,-1467.5},{1,-2075.9,-1736.6,-2012.8,-1729.8},{1,-1923.2,-1569.5,-1984.4,-1583.1},{1,-2245.6,-1631.9,-2269.5,-1635.6},{1,-2269.5,-1635.6,-2240.9,-1672.9},
		{1,-2240.9,-1672.9,-2200.4,-1725.8},{1,-2200.4,-1725.8,-2170.7,-1764.5},{1,-1935.7,-1951.6,-1947.3,-1905.3},{1,-1997.7,-1801.0,-2034.9,-1804.0},{1,-2067.6,-1808.9,-2096.6,-1817.3},{1,-2096.6,-1817.3,-2123.4,-1825.4},{1,-2123.4,-1825.4,-2088.6,-1858.6},{1,-1973.1,-1929.2,-1935.7,-1951.6},
		{1,-2668.5,-1019.6,-2659.6,-1047.5},{1,-2411.6,-1194.1,-2365.6,-1189.8},{1,-2200.6,-1168.6,-2167.4,-1164.3},{1,-2235.8,-111.3,-2229.8,-111.4},{1,-2195.2,369.5,-2195.2,378.4},{1,-2195.2,378.4,-2195.4,412.6},{1,-2195.4,412.6,-2236.1,403.9},{1,-2282.5,391.7,-2307.2,382.6},
		{1,-2396.7,-30.2,-2396.5,-38.8},{1,-2395.7,-75.9,-2395.0,-109.8},{1,-1917.9,168.8,-1918.5,213.6},{1,-1904.5,391.7,-1897.8,468.8},{1,-1897.8,468.8,-1943.4,460.2},{1,-1989.3,-116.2,-1934.8,-117.3},{1,-2773.4,-117.0,-2724.0,-116.0},{1,-2471.0,74.0,-2471.2,80.1},
		{1,-2468.4,289.2,-2468.0,308.8},{1,-2468.0,308.8,-2507.0,290.6},{1,-2588.4,251.2,-2610.7,237.5},{1,-2635.3,219.3,-2659.5,197.5},{1,-2689.9,162.3,-2711.7,129.3},{1,-2723.1,106.4,-2744.9,47.7},{3,-1781.3,2020.0,-1841.6,1997.7},{3,-1855.0,1991.7,-1901.0,1967.7},
		{3,-2026.9,1884.7,-2034.0,1879.9},{3,-2087.1,1844.1,-2092.5,1840.4},{3,-2092.5,1840.4,-2148.4,1802.7},{3,-2148.4,1802.7,-2097.0,1792.4},{3,-1863.4,1745.7,-1849.4,1785.3},{3,-1839.8,1812.4,-1835.7,1824.3},{3,-1818.2,1873.6,-1815.6,1881.1},{3,-1798.7,1942.8,-1796.7,1951.3},
		{3,-1790.5,1979.1,-1781.3,2020.0},{1,-1288.0,1098.6,-1325.3,1101.9},{1,-1145.8,849.3,-1098.5,838.9},{4,-1566.0,-660.5,-1573.5,-674.0},{4,-1577.9,-687.1,-1585.7,-715.2},{4,-1616.1,-844.5,-1623.6,-876.5},{4,-1602.9,-921.5,-1548.6,-925.4},{4,-1419.9,-741.1,-1405.2,-691.7},
		{4,-1396.3,-673.2,-1366.0,-627.3},{4,-1290.4,-520.5,-1276.8,-501.3},{4,-1276.8,-501.3,-1312.8,-490.1},{4,-1312.8,-490.1,-1373.8,-471.1},{4,-1373.8,-471.1,-1401.8,-461.7},{4,-1401.8,-461.7,-1425.0,-452.3},{4,-1385.3,-920.7,-1327.4,-916.6},{4,-1135.5,-792.1,-1115.3,-743.9},
		{4,-1115.3,-743.9,-1084.4,-691.5},{4,-1026.9,-603.1,-1013.9,-583.1},{4,-1013.9,-583.1,-1059.4,-568.9},{4,-1331.7,-706.4,-1338.4,-718.5},{4,-1349.9,-758.0,-1363.7,-821.3},{4,-1372.4,-861.6,-1385.3,-920.7},{4,-1356.1,-1010.8,-1381.6,-1012.7},{4,-1381.6,-1012.7,-1372.3,-1041.7},
		{4,-1313.4,-1245.5,-1313.6,-1280.6},{4,-1324.8,-1399.8,-1327.6,-1430.3},{4,-1301.0,-1473.3,-1241.5,-1471.7},{4,-1147.6,-1431.9,-1151.6,-1378.4},{4,-1179.6,-1066.6,-1186.3,-998.7},{4,-1250.8,-423.5,-1250.3,-388.0},{4,-1224.4,-234.6,-1189.7,-165.2},{4,-1189.7,-165.2,-1227.1,-166.7},
		{4,-1410.9,-250.6,-1414.4,-277.1},{4,-1414.2,-288.6,-1409.6,-326.4},{4,-1401.7,-371.5,-1367.6,-386.8},{4,-1303.2,-407.0,-1250.8,-423.5},{4,-1460.7,-177.7,-1515.2,-181.0},{4,-1670.0,-190.3,-1711.2,-192.7},{4,-1711.2,-192.7,-1662.4,-220.9},{4,-1662.4,-220.9,-1611.9,-250.1},
		{4,-1611.9,-250.1,-1569.1,-274.8},{4,-1507.0,-310.6,-1483.0,-324.5},{4,-1483.0,-324.5,-1486.4,-291.5},{4,-1486.4,-291.5,-1485.6,-261.8},{4,-1478.4,-225.0,-1460.7,-177.7},{1,-940.2,2112.4,-886.0,2124.5},{1,-738.6,2157.4,-731.7,2158.9},{1,-658.9,2175.2,-630.3,2180.5},
		{1,-630.3,2180.5,-585.6,2182.2},{1,-355.1,2181.9,-301.1,2181.9},{1,-301.1,2181.9,-313.8,2248.3},{1,-801.8,2316.5,-868.4,2304.5},{1,-938.3,2284.6,-999.0,2266.4},{1,-778.5,1181.7,-769.4,1177.9},{1,-726.8,1161.5,-712.0,1157.9},{1,-676.9,1154.5,-670.9,1154.3},
		{1,-506.6,1147.3,-477.4,1146.1},{1,-458.1,1263.6,-456.2,1295.7},{1,-886.6,1413.4,-923.0,1416.4},{1,-1031.2,1529.8,-1022.6,1529.1},{1,-989.5,1550.0,-991.8,1614.3},{1,-1001.1,1874.3,-1009.6,1936.4},{1,-1057.9,2190.4,-1062.0,2212.2},{1,-1091.2,2238.7,-1131.0,2226.8},
		{1,-1346.9,2149.1,-1357.4,2132.2},{1,-1279.4,1645.7,-1270.4,1582.4},{1,-1270.4,1582.4,-1265.6,1549.3},{3,-1407.4,1901.8,-1415.1,1871.3},{3,-1429.3,1815.2,-1442.4,1779.8},{3,-1455.1,1749.8,-1458.4,1741.9},{3,-1478.9,1693.8,-1482.8,1684.6},{3,-1496.5,1652.1,-1499.0,1646.2},
		{3,-1506.1,1629.5,-1458.7,1612.4},{3,-1425.5,1600.4,-1416.3,1597.1},{3,-1367.1,1579.4,-1357.7,1576.1},{3,-1357.7,1576.1,-1352.0,1574.0},{3,-1352.0,1574.0,-1357.4,1610.9},{3,-1357.4,1610.9,-1363.8,1655.1},{3,-1381.4,1775.1,-1382.6,1783.3},{3,-1390.9,1840.5,-1398.9,1870.4},
		{3,-1398.9,1870.4,-1407.4,1901.8},{4,-565.2,144.9,-557.0,199.3},{4,-591.7,253.6,-638.0,259.0},{4,-638.0,259.0,-709.3,267.2},{4,-759.0,237.9,-759.0,204.6},{4,-759.0,-14.0,-759.0,-37.9},{1,-294.7,156.1,-289.4,184.6},{1,-311.9,221.3,-365.4,227.5},
		{1,-490.9,155.2,-491.8,148.8},{1,-516.3,-46.9,-520.6,-86.2},{4,-245.8,-526.1,-283.6,-531.0},{4,-422.4,-724.4,-420.6,-736.2},{4,-413.4,-765.4,-392.8,-832.0},{4,-288.6,-895.7,-264.8,-894.6},{4,-226.7,-862.2,-235.5,-815.8},{4,-248.5,-583.2,-245.8,-526.1},
		{4,-547.2,-1234.2,-549.5,-1285.1},{4,-113.3,-1515.7,-81.6,-1514.2},{4,-81.6,-1514.2,-16.1,-1509.0},{4,20.8,-1475.2,10.8,-1432.3},{4,-29.8,-1218.1,-21.3,-1158.2},{4,5.3,-1000.9,12.4,-958.9},{4,12.4,-958.9,-25.5,-961.6},{4,-449.8,-985.7,-487.3,-987.5},
		{4,-487.3,-987.5,-522.7,-989.2},{1,-221.4,-2161.2,-220.7,-2207.3},{1,-220.7,-2207.3,-176.7,-2198.6},{1,282.9,-1937.3,284.9,-1911.0},{1,322.0,-1732.5,322.7,-1719.1},{1,-183.9,-1618.1,-224.3,-1615.6},{1,-296.9,-1828.0,-296.7,-1767.0},{1,-595.1,-1766.5,-597.7,-1778.2},
		{1,-597.7,-1778.2,-536.3,-1778.7},{1,-473.4,-1779.7,-435.9,-1784.4},{1,-352.7,-1810.1,-296.9,-1828.0},{1,-451.8,-1854.7,-463.3,-1853.3},{1,-658.7,-1980.3,-686.2,-2015.3},{1,-781.6,-2164.2,-804.2,-2196.4},{1,-801.3,-2201.0,-739.3,-2205.5},{1,-391.1,-2230.8,-353.6,-2230.7},
		{1,-353.6,-2230.7,-292.5,-2221.4},{4,-446.1,-903.4,-453.9,-878.2},{4,-479.2,-796.3,-493.5,-737.7},{4,-488.8,-610.8,-485.0,-557.1},{4,-485.0,-557.1,-545.7,-565.0},{4,-582.4,-607.4,-572.6,-659.7},{4,-561.7,-718.2,-549.1,-785.4},{4,-482.3,-905.2,-446.1,-903.4},
		{4,-280.4,-454.0,-262.3,-451.6},{4,-262.3,-451.6,-285.0,-404.2},{4,-285.0,-404.2,-298.7,-375.6},{4,-298.7,-375.6,-313.5,-335.8},{4,-690.7,-164.9,-734.8,-161.4},{4,-735.6,-162.3,-721.5,-198.3},{4,-622.0,-453.5,-611.9,-479.2},{4,-611.9,-479.2,-605.3,-496.1},
		{1,-465.1,1006.8,-501.7,967.1},{1,-625.8,832.4,-681.4,772.0},{1,-681.4,772.0,-619.4,772.0},{1,-619.4,772.0,-544.4,772.0},{1,-460.0,895.2,-456.7,918.8},{1,-456.7,918.8,-457.3,940.0},{1,-457.3,940.0,-465.1,1006.8},{1,-389.2,1234.4,-344.3,1279.3},
		{1,-317.7,1305.9,-265.3,1358.3},{1,-265.3,1358.3,-298.6,1361.3},{1,-381.4,1339.8,-385.0,1273.9},{1,-385.0,1273.9,-389.2,1234.4},{4,274.1,-1463.4,298.4,-1443.2},{4,42.0,-1220.4,42.5,-1234.8},{4,45.4,-1262.6,55.9,-1308.1},{4,85.3,-1434.9,100.2,-1499.1},
		{4,-7.0,-519.3,-56.9,-519.7},{4,-181.9,-691.5,-180.7,-716.1},{4,-65.3,-882.5,-32.1,-880.0},{4,5.5,-846.6,-7.0,-787.1},{4,-18.7,-730.5,-22.4,-696.5},{4,-11.4,-564.0,-7.0,-519.3},{4,51.4,-661.2,50.1,-704.5},{4,72.0,-811.7,79.0,-846.1},
		{4,79.0,-846.1,84.2,-871.3},{1,1080.2,2178.0,1075.8,2173.5},{1,559.7,1769.6,558.5,1739.1},{1,559.9,1725.5,564.9,1705.6},{1,569.0,1693.7,593.7,1641.6},{1,984.9,1608.0,938.5,1602.2},{1,938.5,1602.2,880.7,1595.0},{1,880.7,1595.0,837.0,1589.5},
		{1,837.0,1589.5,863.6,1592.9},{1,863.6,1592.9,916.9,1599.5},{1,916.9,1599.5,986.3,1608.2},{1,1661.7,1820.8,1719.3,1868.3},{1,1935.3,2104.5,1955.7,2137.2},{1,2015.9,2233.5,2045.0,2280.1},{1,2045.0,2280.1,1985.3,2278.0},{1,1773.7,2270.3,1717.3,2268.2},
		{1,1149.5,2211.0,1101.1,2205.3},{1,-30.3,1364.4,8.6,1330.3},{1,1077.3,1242.3,1146.5,1252.8},{1,1797.1,1330.0,1845.7,1335.8},{1,1845.7,1335.8,1762.7,1377.8},{1,1762.7,1377.8,1695.1,1426.1},{1,1501.8,1567.8,1457.1,1562.2},{1,79.1,1379.8,30.8,1373.0},
		{1,30.8,1373.0,-30.3,1364.4},{1,1142.1,1175.9,1082.4,1165.9},{1,927.6,1134.8,886.8,1126.6},{1,886.8,1126.6,909.5,1088.5},{1,932.6,1049.4,972.9,974.2},{1,979.4,953.4,988.0,900.2},{1,988.0,900.2,996.0,841.1},{1,1040.6,802.7,1066.5,807.5},
		{1,1389.8,990.5,1386.9,1042.5},{1,1382.8,1055.9,1361.9,1106.0},{1,1361.9,1106.0,1321.0,1197.5},{1,491.0,599.4,491.0,556.2},{1,1659.0,822.7,1659.0,841.6},{1,1659.0,841.6,1631.8,835.0},{4,1658.7,546.7,1659.0,564.4},{4,491.0,308.0,491.0,298.6},
		{4,491.0,298.6,557.9,310.0},{4,557.9,310.0,625.4,321.4},{4,625.4,321.4,690.5,332.4},{4,690.5,332.4,778.8,347.4},{4,778.8,347.4,867.3,358.9},{4,867.3,358.9,922.9,365.3},{4,922.9,365.3,970.3,370.7},{4,970.3,370.7,1036.5,378.3},
		{4,1136.0,389.7,1198.5,403.6},{4,1433.2,459.0,1489.8,479.7},{4,1575.5,511.9,1655.6,542.0},{4,1186.3,316.4,1181.1,283.1},{4,1211.7,227.5,1268.2,227.2},{4,1344.5,226.8,1400.1,225.1},{4,1629.7,413.0,1635.5,446.6},{4,1635.5,446.6,1582.1,426.4},
		{4,1582.1,426.4,1519.2,402.5},{4,1519.2,402.5,1446.0,377.4},{4,1301.7,31.3,1376.6,12.6},{4,1433.2,-11.8,1487.5,-35.5},{4,1548.5,-20.0,1555.5,7.4},{4,1567.4,56.9,1571.5,79.1},{4,1534.3,138.8,1507.1,141.5},{4,1358.8,154.7,1289.0,155.1},
		{4,1237.3,155.4,1161.3,155.8},{4,1135.6,-9.5,1122.7,-91.0},{4,1059.2,-428.5,1050.4,-474.6},{4,1050.4,-474.6,1120.4,-469.0},{4,1222.5,-460.7,1241.6,-458.4},{4,1357.7,-57.4,1320.9,-45.2},{4,1172.4,-546.7,1107.3,-552.2},{4,1061.0,-594.9,1077.4,-660.4},
		{4,1185.5,-862.9,1230.0,-855.7},{4,1230.0,-855.7,1191.6,-780.5},{4,1191.6,-780.5,1171.8,-735.7},{4,1171.8,-735.7,1165.2,-710.9},{4,1165.2,-710.9,1162.6,-693.4},{4,1162.6,-693.4,1161.2,-672.9},{4,1161.2,-672.9,1166.2,-607.1},{4,1166.2,-607.1,1172.4,-546.7},
		{4,1147.7,-941.9,1161.2,-986.8},{4,1266.6,-1091.2,1315.9,-1092.7},{4,1406.2,-1027.1,1424.2,-950.5},{4,1428.0,-922.7,1430.2,-889.5},{4,1430.2,-889.5,1398.6,-896.2},{4,1398.6,-896.2,1328.0,-911.2},{4,1212.6,-931.5,1147.7,-941.9},{4,31.9,-24.9,27.5,-61.2},
		{4,68.2,-118.7,131.3,-121.3},{4,258.4,-135.7,319.0,-143.0},{4,409.6,-153.9,429.3,-156.2},{4,488.7,-115.4,492.0,-73.1},{4,483.7,153.3,442.2,198.1},{4,550.6,-253.4,546.7,-315.0},{4,535.3,-493.6,533.8,-564.1},{4,534.2,-752.0,534.2,-786.7},
		{4,534.2,-786.7,603.1,-767.7},{4,603.1,-767.7,646.6,-746.9},{4,707.2,-701.7,752.2,-665.7},{4,843.1,-593.0,894.3,-552.1},{4,909.8,-489.8,876.3,-457.4},{4,625.8,-262.4,550.6,-253.4},{1,505.2,1872.2,483.7,1857.5},{1,339.0,1662.0,339.2,1633.3},
		{1,340.3,1620.9,358.7,1558.1},{1,500.9,1544.4,556.3,1552.2},{1,556.3,1552.2,542.4,1581.6},{1,489.9,1708.2,486.8,1737.9},{1,486.8,1737.9,486.8,1765.8},{1,486.8,1765.8,498.3,1833.1},{1,498.3,1833.1,505.2,1872.2},{1,356.7,1020.0,321.2,1012.8},
		{1,321.2,1012.8,335.6,984.6},{1,335.6,984.6,367.1,922.7},{1,653.0,865.8,646.6,893.5},{1,641.8,905.8,613.5,958.9},{1,596.9,988.3,570.3,1035.6},{1,570.3,1035.6,556.5,1060.1},{1,-112.2,1483.9,-83.3,1507.6},{1,333.7,1848.7,357.3,1868.1},
		{1,362.5,1872.0,328.6,1863.6},{1,328.6,1863.6,298.5,1856.0},{1,298.5,1856.0,246.1,1843.0},{1,246.1,1843.0,189.1,1831.3},{1,-43.6,1838.5,-114.2,1841.5},{1,-145.8,1819.3,-140.5,1766.1},{1,-117.1,1533.0,-112.2,1483.9},{1,335.5,711.7,359.2,708.8},
		{1,359.2,708.8,329.1,768.0},{1,202.1,1018.9,194.1,1029.8},{1,166.7,1053.8,108.3,1104.9},{1,108.3,1104.9,114.3,1055.3},{1,123.7,971.2,123.8,952.7},{1,123.8,952.7,113.0,881.1},{1,94.1,778.2,87.6,742.7},{1,268.4,1689.4,226.5,1655.1},
		{1,67.6,1525.1,5.8,1474.5},{1,5.8,1474.5,33.5,1478.4},{1,81.3,1485.2,140.5,1493.5},{1,282.0,1513.5,297.0,1515.6},{1,297.0,1515.6,281.3,1563.1},{1,272.3,1593.0,268.0,1621.5},{1,268.0,1621.5,268.4,1689.4},{1,367.5,2309.4,387.0,2290.6},
		{1,434.0,2245.4,464.2,2210.1},{1,464.2,2210.1,494.2,2154.8},{1,540.5,2067.5,552.5,2044.8},{1,588.0,2028.1,638.6,2062.7},{1,847.1,2205.2,865.5,2217.7},{1,865.5,2217.7,818.3,2226.4},{1,421.8,2299.4,367.5,2309.4},{1,915.9,897.0,908.8,936.1},
		{1,906.1,947.2,901.4,957.5},{1,866.4,1019.9,835.5,1072.0},{1,685.3,1086.0,630.7,1075.1},{1,630.7,1075.1,669.0,1007.1},{1,669.0,1007.1,712.2,924.5},{1,717.3,908.9,729.5,843.9},{1,861.7,770.7,931.2,783.0},{4,712.1,-191.2,722.7,-196.7},
		{4,722.7,-196.7,734.0,-205.8},{4,734.0,-205.8,804.3,-273.8},{4,804.3,-273.8,764.3,-208.0},{4,740.4,-168.8,700.3,-102.8},{4,668.1,-49.8,658.3,-37.4},{4,620.8,3.8,582.8,45.4},{4,582.8,45.4,570.8,-23.3},{4,570.8,-23.3,561.4,-109.7},
		{4,561.4,-109.7,556.4,-171.5},{4,1093.8,255.7,1056.7,224.5},{4,839.1,-173.2,860.8,-208.8},{4,860.8,-208.8,907.0,-151.0},{4,1060.4,41.0,1068.4,91.8},{4,1068.4,91.8,1081.3,175.3},{4,1081.3,175.3,1093.8,255.7},{4,935.2,-332.4,970.5,-391.1},
		{4,970.5,-391.1,979.8,-406.7},{4,979.8,-406.7,990.7,-349.6},{4,990.7,-349.6,1002.4,-288.2},{4,1016.1,-216.4,1030.5,-140.9},{4,1030.5,-140.9,1037.7,-102.7},{4,1037.7,-102.7,996.8,-154.0},{4,955.2,-206.0,925.2,-243.5},{4,925.2,-243.5,900.5,-274.5},
		{4,1028.6,294.9,949.1,285.6},{4,779.4,264.9,710.9,253.1},{4,571.1,229.2,531.5,222.4},{4,531.5,222.4,577.6,172.1},{4,577.6,172.1,596.2,151.7},{4,905.4,191.3,976.6,251.2},{4,976.6,251.2,1028.6,294.9},{1,1934.4,-1635.2,1965.7,-1663.4},
		{1,1965.7,-1663.4,2000.5,-1703.4},{1,2459.6,-1807.3,2513.3,-1769.3},{1,2556.9,-1729.1,2579.3,-1702.7},{1,2595.6,-1680.5,2625.0,-1635.5},{1,2737.2,-1377.6,2746.3,-1350.4},{1,1548.7,-508.4,1547.0,-554.2},{1,1441.3,-1407.2,1449.4,-1432.3},{1,1054.7,-1665.6,1047.7,-1687.3},
		{1,1044.5,-1702.0,1042.8,-1728.3},{1,1048.1,-1792.2,1048.9,-1800.8},{1,1309.5,-1898.7,1346.5,-1905.7},{1,1380.9,-1888.2,1383.3,-1830.6},{1,1385.7,-1768.3,1384.6,-1739.2},{1,1382.9,-1724.6,1371.0,-1677.6},{1,1340.2,-1585.0,1338.8,-1580.8},{1,1164.4,-1548.9,1104.9,-1563.4},
		{1,937.3,-1828.8,979.8,-1836.8},{1,979.8,-1836.8,973.9,-1770.9},{1,971.1,-1736.8,971.7,-1701.2},{1,983.0,-1651.5,1001.8,-1610.4},{1,1001.8,-1610.4,1013.5,-1585.8},{1,1013.5,-1585.8,946.1,-1601.7},{1,946.1,-1601.7,885.1,-1609.7},{1,796.8,-1684.9,791.7,-1721.1},
		{1,791.3,-1757.4,790.9,-1801.3},{3,1349.6,-2237.5,1378.8,-2235.6},{3,1477.9,-2229.3,1485.2,-2228.8},{3,1581.4,-2222.6,1590.6,-2222.0},{3,1627.3,-2219.7,1632.0,-2168.5},{3,1637.9,-2104.7,1638.6,-2096.4},{3,1643.4,-2044.4,1644.1,-2036.7},{3,1647.1,-2004.2,1648.0,-1994.3},
		{3,1651.0,-1961.9,1652.0,-1951.4},{3,1653.6,-1933.7,1655.0,-1923.1},{3,1659.1,-1896.5,1660.4,-1887.5},{3,1668.3,-1835.8,1669.5,-1827.7},{3,1677.3,-1776.0,1678.2,-1770.0},{3,1686.0,-1718.3,1687.1,-1711.6},{3,1692.4,-1676.5,1693.7,-1667.6},{3,1698.1,-1638.6,1636.0,-1614.9},
		{3,1573.4,-1591.0,1566.2,-1588.2},{3,1486.8,-1557.9,1434.1,-1537.8},{3,1434.1,-1537.8,1448.0,-1579.7},{3,1471.4,-1650.1,1485.6,-1709.2},{3,1481.8,-1962.9,1480.5,-1971.5},{3,1457.4,-2004.1,1438.9,-2054.6},{3,1415.7,-2117.4,1413.5,-2123.4},{3,1397.3,-2161.1,1363.7,-2216.3},
		{3,1363.7,-2216.3,1349.6,-2237.5},{3,2095.7,-1991.8,2063.4,-1950.9},{3,2031.0,-1909.9,2025.3,-1902.6},{3,1964.2,-1825.2,1958.4,-1817.9},{3,1915.5,-1763.6,1880.8,-1725.7},{3,1865.1,-1712.9,1848.9,-1701.8},{3,1831.3,-1691.6,1787.6,-1673.1},{3,1787.6,-1673.1,1766.9,-1664.9},
		{3,1766.9,-1664.9,1760.6,-1707.0},{3,1756.5,-1733.6,1755.1,-1743.1},{3,1752.4,-1760.7,1751.1,-1769.3},{3,1747.1,-1795.8,1745.9,-1803.8},{3,1738.1,-1855.5,1736.6,-1864.9},{3,1732.6,-1891.5,1730.9,-1902.6},{3,1727.3,-1926.6,1725.6,-1938.1},{3,1722.3,-1972.8,1721.2,-1984.6},
		{3,1716.4,-2036.6,1715.8,-2043.1},{3,1713.4,-2069.9,1712.5,-2079.5},{3,1707.8,-2130.7,1706.8,-2141.0},{3,1705.2,-2158.7,1704.5,-2166.8},{3,1701.2,-2201.9,1700.5,-2209.7},{3,1700.5,-2209.7,1699.9,-2216.0},{3,1699.9,-2216.0,1718.3,-2213.8},{3,1718.3,-2213.8,1732.5,-2210.6},
		{3,1732.5,-2210.6,1753.9,-2202.8},{3,1800.2,-2178.4,1808.7,-2173.9},{3,1942.5,-2102.5,1950.8,-2098.1},{3,2039.6,-2050.8,2047.4,-2046.6},{3,2047.4,-2046.6,2085.9,-2026.1},{2,2026.3,2054.0,1993.0,2000.7},{2,1993.0,2000.7,1943.3,1931.6},{2,1943.3,1931.6,1904.0,1888.5},
		{2,1904.0,1888.5,1845.4,1837.5},{2,1845.4,1837.5,1810.4,1808.6},{2,1810.4,1808.6,1869.4,1756.6},{2,2185.2,1469.6,2201.8,1454.2},{2,2201.8,1454.2,2224.3,1501.5},{2,2224.3,1501.5,2258.8,1574.1},{2,2350.3,1766.2,2286.5,1820.1},{2,2208.3,1886.1,2144.7,1943.0},
		{2,2081.0,2002.8,2026.3,2054.0},{2,1754.1,1762.2,1706.5,1723.0},{2,1706.5,1723.0,1647.7,1674.4},{2,1601.4,1636.2,1575.9,1615.2},{2,1575.9,1615.2,1649.7,1561.0},{2,1774.1,1469.8,1827.8,1434.7},{2,2061.9,1332.4,2129.9,1303.2},{2,2129.9,1303.2,2169.3,1386.0},
		{2,1894.8,1265.1,1926.3,1196.7},{2,1926.3,1196.7,1941.0,1158.2},{2,1941.0,1158.2,1947.0,1127.1},{2,1947.0,1127.1,1955.9,1031.8},{2,1955.9,1031.8,1969.1,1038.2},{2,1977.7,1045.6,1986.6,1057.9},{2,2060.4,1180.5,2090.7,1230.8},{2,2090.7,1230.8,2041.2,1252.0},
		{2,1985.8,1275.8,1925.3,1268.7},{2,1925.3,1268.7,1894.8,1265.1},{2,1708.3,256.7,1702.0,219.9},{2,1702.0,219.9,1762.6,237.4},{2,1762.6,237.4,1819.5,253.9},{2,1920.8,273.3,1980.8,267.5},{2,2149.2,279.6,2155.6,352.2},{2,2155.6,352.2,2162.3,426.9},
		{2,1926.4,200.6,1907.9,201.0},{2,1895.8,199.1,1807.9,175.6},{2,1668.1,29.6,1650.9,-39.4},{2,1650.9,-39.4,1741.1,-13.4},{2,2128.1,141.1,2133.7,176.6},{2,1815.9,-240.5,1813.9,-252.1},{2,1812.9,-335.3,1813.5,-371.6},{2,1974.4,-442.7,2043.4,-449.5},
		{2,2255.7,-460.6,2325.5,-464.2},{2,2325.5,-464.2,2297.7,-414.2},{2,2233.5,-298.2,2203.8,-230.9},{2,2162.4,-107.3,2129.9,-9.9},{4,1249.1,-1162.4,1271.1,-1205.5},{4,1313.0,-1287.5,1329.9,-1320.6},{4,1329.9,-1320.6,1343.4,-1268.7},{4,1343.4,-1268.7,1355.7,-1221.4},
		{4,1355.7,-1221.4,1372.3,-1157.4},{4,1372.3,-1157.4,1309.0,-1165.3},{4,1309.0,-1165.3,1249.1,-1162.4},{4,1440.9,-607.1,1444.8,-504.5},{4,1233.5,-659.3,1234.9,-689.1},{4,1237.3,-701.4,1245.7,-727.4},{4,1245.7,-727.4,1287.1,-809.2},{4,1287.1,-809.2,1304.3,-842.8},
		{2,1593.7,-382.3,1643.5,-390.3},{2,1692.4,-398.1,1742.0,-406.1},{2,1742.0,-406.1,1740.5,-312.8},{2,1742.2,-242.5,1766.9,-151.0},{2,1766.9,-151.0,1779.1,-110.7},{2,1779.1,-110.7,1700.7,-133.3},{1,1874.3,1125.3,1871.1,1140.2},{1,1849.1,1192.3,1838.9,1214.4},
		{1,1444.9,1212.1,1395.9,1206.3},{1,1395.9,1206.3,1422.2,1147.5},{1,1460.8,936.5,1460.2,900.5},{1,1460.2,900.5,1497.4,909.5},{1,1703.2,956.9,1716.9,954.2},{1,2861.1,-1285.6,2901.4,-1238.7},{1,3084.8,-1004.7,3102.5,-965.1},{1,3171.4,-723.2,3156.9,-700.9},
		{1,3148.7,-678.8,3083.6,-664.5},{1,2477.0,-579.0,2511.8,-646.0},{1,2831.1,-1270.4,2838.7,-1285.6},{2,2207.3,180.8,2257.4,230.9},{2,2417.1,390.6,2433.1,406.6},{2,2433.1,406.6,2363.4,411.9},{2,2222.6,291.9,2216.8,242.9},{2,2216.8,242.9,2207.3,180.8},
		{2,2244.2,70.7,2323.9,55.4},{2,2632.0,-3.6,2688.2,-14.4},{2,2688.2,-14.4,2678.0,78.3},{2,2672.3,129.6,2671.5,165.9},{2,2684.5,227.2,2725.7,310.5},{2,2725.7,310.5,2753.7,365.7},{2,2753.7,365.7,2677.2,377.6},{2,2265.6,92.1,2244.2,70.7},
		{1,2915.4,-53.0,2957.3,-59.8},{1,2957.3,-59.8,2955.7,-33.7},{1,2949.9,58.7,2949.2,123.5},{1,2956.6,160.6,2970.6,197.5},{1,2985.6,230.4,3010.5,285.1},{1,3001.8,323.0,2975.6,329.9},{1,2752.0,201.1,2747.7,187.6},{1,2743.1,153.8,2749.3,92.6},
		{1,2754.6,42.9,2762.3,-28.5},{2,2699.0,-311.7,2701.9,-282.6},{2,2237.9,-5.5,2206.6,0.5},{2,2206.6,0.5,2230.4,-71.1},{2,2270.8,-192.3,2300.7,-262.9},{2,2384.1,-413.2,2415.2,-469.1},{1,2718.7,-496.1,2748.8,-499.0},{1,2840.9,-507.9,2882.7,-514.7},
		{1,2970.2,-362.0,2974.5,-344.0},{1,2975.1,-332.0,2974.5,-296.9},{1,2805.6,-112.9,2767.5,-106.9},{1,2767.5,-106.9,2769.1,-147.1},{1,2772.9,-245.9,2773.0,-301.5},{1,2770.1,-324.7,2759.2,-363.3},{1,2735.1,-442.4,2732.3,-451.4},{1,2732.3,-451.4,2718.7,-496.1},
		{1,2986.9,-536.8,3042.6,-549.0},{1,3340.1,-227.7,3350.7,-197.8},{1,3350.7,-197.8,3288.8,-188.1},{1,3169.4,-169.6,3161.7,-168.4},{1,3098.3,-158.6,3090.8,-157.4},{1,3090.8,-157.4,3035.6,-148.8},{1,3035.6,-148.8,3039.2,-197.5},{1,3046.6,-296.1,3046.9,-344.3},
		{1,3043.0,-369.0,3025.3,-426.0},{1,2992.9,-519.4,2986.9,-536.8},{1,3029.6,152.3,3023.3,129.2},{1,3020.9,116.0,3020.8,77.8},{1,3024.9,13.9,3025.3,6.0},{1,3287.3,-111.0,3317.3,-115.7},{1,3351.1,-97.1,3351.6,-48.1},{1,3352.7,80.2,3353.2,136.5},
		{1,3114.9,972.3,3123.8,979.9},{1,3136.5,992.9,3144.2,1002.2},{1,3158.3,1023.8,3162.6,1034.6},{1,3167.9,1048.1,3171.0,1059.1},{1,3175.6,1087.8,3171.4,1144.4},{1,2984.0,1204.0,2902.9,1204.0},{1,2844.9,1153.0,2848.3,1095.1},{1,2852.3,1072.1,2858.1,1050.6},
		{1,2865.1,1031.5,2875.7,1008.7},{1,2889.3,985.7,2900.4,970.6},{1,2943.5,924.5,2985.0,883.0},{1,2909.0,1550.9,2889.0,1517.0},{1,2880.4,1496.2,2874.3,1476.0},{1,2861.3,1394.3,2855.9,1355.4},{1,2889.7,1296.0,2945.3,1296.0},{1,3039.3,1296.0,3091.1,1296.0},
		{1,3144.4,1337.5,3135.3,1393.7},{1,3126.4,1448.6,3119.6,1476.2},{1,3110.2,1500.0,3102.7,1513.6},{1,3093.2,1527.9,3083.2,1540.2},{1,3069.7,1554.0,3055.6,1565.7},{1,3055.6,1565.7,2997.1,1601.2},{1,2997.1,1601.2,2967.9,1618.1},{2,2381.7,1833.9,2417.3,1906.8},
		{2,2837.2,2080.0,2890.0,2092.9},{2,2890.0,2092.9,2835.4,2118.9},{2,2835.4,2118.9,2752.8,2158.1},{2,2687.8,2187.8,2623.8,2210.8},{2,2553.4,2226.6,2497.2,2234.7},{2,2234.0,2271.6,2215.8,2256.0},{2,2194.0,2243.8,2167.9,2236.6},{2,2139.8,2235.5,2107.0,2183.1},
		{2,2065.2,2116.3,2132.7,2052.8},{2,2333.4,1874.8,2381.7,1833.9},
	},
	trees = {
		{3280.2,979.7,0.8,1},{3240.5,909.0,0.75,1},{3133.0,827.6,0.78,1},{3071.6,783.6,0.95,1},{3042.2,763.7,0.72,1},{2993.2,673.9,0.9,1},{2880.2,504.3,0.94,1},{2941.9,489.4,0.63,1},
		{2979.2,485.7,0.98,1},{3363.5,377.7,0.79,1},{3540.8,-47.5,0.78,1},{3526.7,-201.0,0.67,1},{3508.7,-293.0,0.7,1},{3489.3,-391.3,0.6,1},{3443.4,-480.0,0.72,1},{3326.5,-829.8,0.97,1},
		{3322.0,-908.4,0.63,1},{3257.8,-1059.4,0.85,1},{3218.0,-1150.3,0.81,1},{3130.2,-1250.0,0.7,1},{2707.0,-1839.8,0.72,1},{2677.1,-1864.3,0.84,1},{2565.6,-1951.3,0.84,1},{2100.3,-2230.3,0.86,1},
		{1355.4,-2435.3,0.61,1},{693.1,-2312.4,0.62,1},{618.8,-2320.8,0.82,1},{461.2,-2306.4,0.77,1},{107.1,-2322.6,0.62,1},{9.7,-2339.6,0.75,1},{-560.1,-2403.2,0.95,1},{-658.6,-2394.9,0.63,1},
		{-725.7,-2396.5,1.0,1},{-1243.2,-2368.7,0.93,1},{-1752.3,-2233.1,0.72,1},{-2232.3,-1983.6,0.77,1},{-2378.9,-1784.1,0.91,1},{-2429.7,-1752.3,0.68,1},{-2742.2,-1360.1,0.92,1},{-2762.6,-1342.3,0.68,1},
		{-2915.9,-806.7,0.64,1},{-2955.8,-635.6,0.72,1},{-2980.6,-363.6,0.82,1},{-2908.2,126.3,0.7,1},{-2706.0,391.1,0.86,1},{-2604.9,439.4,0.74,1},{-2560.8,471.5,0.65,1},{-2494.3,-1762.4,1.57,2},
		{3379.4,726.8,1.4,1},{3273.8,428.5,1.43,2},{1245.4,-2459.4,1.69,2},{-1463.0,-2382.1,1.56,2},{-1762.6,-2296.4,1.71,2},{-2164.4,-2078.1,1.45,1},{3687.3,161.8,1.93,2},{2547.0,-1996.0,1.23,1},
		{2133.3,-2253.7,1.67,2},{-2589.3,-1789.2,1.38,1},{1195.5,-2435.0,2.0,2},{220.9,-2354.8,1.48,2},{3130.0,-1439.5,1.22,1},{3723.6,322.4,1.52,2},{-630.6,-2449.8,1.13,1},{-3066.8,436.8,1.37,2},
		{433.4,-2335.3,1.46,1},{3304.7,-1063.1,1.76,2},{-2728.2,-1409.3,1.19,1},{3471.3,667.3,1.97,2},{3084.9,-1441.3,1.22,1},{-3036.8,294.8,1.36,2},{-3025.5,-624.3,1.49,2},{3161.1,-1332.2,1.92,2},
		{3562.4,-127.9,1.34,1},{-2486.5,-1803.8,1.8,2},{3596.0,535.8,1.15,1},{-1700.0,-2355.7,1.36,1},{-2037.7,-2190.8,1.63,2},{-44.4,-2388.8,1.07,1},{3344.7,860.8,1.35,1},{-3061.0,304.4,1.87,2},
		{3397.9,-842.7,1.39,1},{3376.2,616.9,1.14,1},{3497.0,-429.5,1.27,2},{794.8,-2352.1,1.89,2},{3119.1,-1333.5,1.43,1},{-2520.2,-1634.8,1.86,2},{-2384.1,-1888.4,2.0,2},{3173.9,577.5,1.28,1},
		{2018.4,-2348.1,1.47,2},{3552.5,339.0,2.0,2},{-857.0,-2388.2,1.47,1},{3327.1,824.2,1.42,2},{3164.4,787.6,1.54,1},{-1104.1,-2413.2,1.51,1},{3167.9,-1344.5,1.48,1},{3501.2,367.2,1.2,1},
		{2282.2,-2180.8,1.3,2},{832.5,-2414.4,1.95,2},{3137.7,742.9,1.44,2},{661.4,-2388.7,1.26,1},{-2871.2,252.1,1.03,1},{-2926.7,214.9,1.23,1},{3405.3,-886.6,1.95,2},{3565.0,251.5,1.62,2},
		{-3067.7,168.0,1.28,1},{2010.1,-2322.2,1.58,2},{795.5,-2366.4,1.15,1},{-2555.2,-1818.4,1.35,1},{-2833.7,249.2,1.47,2},{2968.4,547.2,1.78,2},{-2012.0,-2180.2,1.88,2},{-761.9,-2482.4,1.85,2},
		{684.3,-2384.9,1.43,1},{-2523.9,-1694.9,1.35,1},{-993.2,-2442.4,1.59,1},{729.6,-2427.2,1.43,1},{2733.2,-1783.6,1.18,1},{3149.8,-1361.9,1.25,2},{3252.4,622.3,1.46,2},{1420.0,-2475.0,1.99,2},
		{2812.6,-1775.9,1.1,1},{-2129.2,-2093.5,1.08,1},{3309.3,602.0,1.31,1},{3680.6,487.0,1.6,2},{3611.5,21.2,1.42,1},{3607.2,320.8,1.72,2},{3233.8,867.9,1.98,2},{3257.4,507.7,1.77,2},
		{3570.6,-139.4,1.97,2},{283.1,-2315.9,1.81,2},{2076.9,-2337.7,1.6,2},{-98.2,-2421.2,1.44,1},{-3027.9,-327.2,1.65,2},{-962.9,-2452.9,1.38,2},{3420.5,-711.6,1.27,2},{-781.2,-2470.5,1.36,1},
		{-1157.6,-2423.8,1.02,1},{3452.1,582.7,1.65,2},{2286.0,-2137.3,1.08,1},{-2927.6,441.9,1.36,1},{2420.6,-2095.5,1.43,2},{-2633.1,-1639.3,1.76,2},{2905.2,-1651.5,1.49,1},{1783.7,-2395.7,1.8,2},
		{3237.5,-1153.1,1.72,2},{2224.0,-2282.5,1.16,1},{3438.3,499.3,1.87,2},{3638.0,-80.6,1.79,2},{-2876.8,430.0,1.71,2},{-2240.1,-2046.0,1.55,1},{-2529.8,-1622.5,1.31,2},{303.2,-2299.1,1.29,1},
		{-1419.2,-2344.1,1.28,2},{347.6,-2344.6,1.97,2},{2429.7,-2071.7,1.16,1},{3581.4,407.3,1.56,2},{3120.4,701.2,1.32,1},{-3006.3,-817.5,1.08,1},{3309.9,474.1,1.64,2},{3278.9,-1107.9,1.11,1},
		{2258.9,-2262.3,1.5,2},{3478.1,-535.7,1.36,1},{-2193.3,-2058.7,1.3,2},{3096.3,-1518.9,1.57,1},{-3029.0,418.0,1.26,2},{3592.1,297.6,1.29,2},{-2138.4,-2076.6,1.62,2},{-2650.6,475.7,1.31,1},
		{-2720.0,-1512.0,1.83,2},{3355.3,750.9,1.58,1},{2610.8,-1902.0,1.65,2},{3404.5,-809.3,1.44,2},{-2131.3,-2147.6,1.98,2},{3644.6,351.8,1.4,2},{2318.9,-2120.4,1.5,1},{3220.8,505.1,1.48,2},
		{3381.0,441.1,1.71,2},{3525.3,-590.8,1.82,2},{-3023.3,-179.5,2.0,2},{-1886.5,-2301.8,1.84,2},{-2977.3,251.2,1.96,2},{1359.4,-2455.7,1.05,1},{-964.1,-2404.5,1.46,1},{-2340.8,-1887.3,1.67,2},
		{3265.1,575.3,1.97,2},{388.5,-2384.0,1.62,2},{-514.2,-2443.0,1.08,1},{3579.8,42.8,1.9,2},{-2840.9,-1234.2,1.96,2},{2868.7,-1649.4,1.05,1},{3252.3,473.9,1.27,1},{3099.6,484.1,1.73,2},
		{1787.0,-2342.3,1.29,1},{-2470.5,-1807.3,1.43,2},{-2860.7,462.1,1.01,1},{3382.2,395.5,1.78,2},{2573.9,-1896.3,1.59,1},{-2852.7,321.4,1.2,1},{-3043.7,-156.8,1.42,1},{2389.4,-2101.0,1.27,2},
		{2430.1,-2172.9,1.5,2},{1299.2,-2445.5,1.4,2},{-2680.8,-1488.9,1.74,2},{3742.6,315.2,1.32,2},{-2685.5,480.8,1.05,1},{3156.4,-1382.6,1.36,2},{3425.3,595.7,1.7,2},{2379.6,-2113.1,1.04,1},
		{-1909.4,-2195.8,1.11,1},{-2711.2,-1374.1,1.63,2},{3647.0,-50.9,1.59,1},{3409.2,759.7,1.62,2},{3725.7,402.7,1.13,1},{-325.6,-2393.6,1.37,2},{-1727.2,-2348.0,1.35,1},{-2082.5,-2129.9,1.48,2},
		{3683.5,90.6,1.05,1},{678.1,-2440.2,1.29,2},{3629.1,268.5,1.14,1},{1392.3,-2441.2,1.04,1},{2105.3,-2268.3,1.64,2},{842.1,-2427.6,1.65,2},{3382.3,707.5,1.64,2},{3254.9,653.0,1.13,1},
		{-2527.3,-1737.4,1.36,1},{588.8,-2372.4,1.98,2},{-693.5,-2417.1,1.39,2},{-2996.4,-727.7,1.62,2},{3357.2,535.6,1.9,2},{-2628.6,-1581.3,1.3,2},{-2534.1,-1655.3,1.33,1},{91.3,-2406.3,1.15,1},
		{-298.4,-2414.7,1.88,2},{-2938.1,323.1,1.9,2},{3319.4,-1051.0,1.64,2},{3155.1,570.1,1.54,2},{1272.2,-2477.4,1.59,1},{3044.1,-1572.1,1.3,1},{2983.1,629.0,1.82,2},{-2486.2,-1739.6,1.17,1},
		{3123.7,-1312.7,1.65,2},{2868.5,-1761.7,1.53,1},{-3041.6,195.7,1.33,1},{1829.0,-2377.0,1.41,1},{-3028.8,306.6,1.95,2},{977.9,-2399.6,1.04,1},{3169.6,606.4,1.35,1},{2699.9,-1778.5,1.51,2},
		{982.6,-2427.5,1.01,1},{3317.2,672.9,1.55,2},{2312.4,-2226.6,1.17,1},{-2592.3,482.1,1.27,1},{-3108.2,261.9,1.55,2},{2580.7,-1922.5,1.41,1},{1221.7,-2506.3,1.4,2},{194.4,-2382.8,1.74,2},
		{-1418.7,-2370.8,1.04,1},{-2109.1,-2114.1,1.43,2},{2986.8,-1462.8,1.58,1},{-728.1,-2471.2,1.8,2},{3394.1,486.1,1.93,2},{-2889.9,354.9,1.54,2},{3207.2,-1204.8,1.61,2},{2072.9,-2297.3,1.2,1},
		{3319.7,639.9,1.53,2},{-3044.7,-446.4,1.86,2},{3419.9,-658.0,1.28,2},{2632.7,-1866.3,1.02,1},{3328.8,553.3,1.4,1},{-3013.3,-590.1,1.42,1},{-2856.8,239.6,1.59,2},{-3050.1,176.7,1.4,2},
		{-3079.2,34.9,1.8,2},{3567.3,581.4,1.3,2},{3439.2,-580.6,1.4,2},{3406.5,554.4,1.66,2},{3316.6,984.2,1.13,1},{3706.9,223.9,1.25,1},{3390.0,685.4,1.98,2},{-2768.9,-1426.7,1.75,2},
		{3703.4,328.6,1.42,2},{3485.2,464.1,1.23,1},{3108.9,657.9,1.99,2},{-3095.9,328.6,1.44,1},{3513.9,573.3,1.45,1},{-2407.8,-1881.8,1.57,2},{1135.8,-2507.8,1.75,2},{3598.8,510.5,1.48,2},
		{-2538.3,491.1,1.32,1},{3125.6,541.9,1.27,2},{3128.7,-1401.7,1.45,1},{-1815.3,-2239.4,1.51,1},{-991.6,-2410.9,1.35,1},{-3014.9,402.6,1.26,1},{-2983.1,31.1,1.92,2},{1238.3,-2435.8,1.6,2},
		{-2999.6,295.6,1.37,1},{3649.7,325.9,1.28,1},{-560.7,-2460.5,1.81,2},{3132.6,509.4,1.33,1},{-2796.9,412.8,1.26,2},{-535.1,-2433.2,1.32,1},{519.5,-2334.7,1.24,1},{-2051.5,-2162.1,1.0,1},
		{-2696.1,-1554.1,1.09,1},{3521.7,624.3,1.39,2},{2209.2,-2210.0,1.5,1},{-2475.5,-1863.2,1.27,1},{-592.3,-2452.9,1.42,1},{-2969.1,274.4,1.58,2},{-2277.1,-1926.8,1.39,1},{3364.8,439.0,1.45,1},
		{3550.2,-316.6,1.5,2},{1142.2,-2409.0,1.27,1},{-846.8,-2422.4,1.97,2},{-664.6,-2441.0,1.59,1},{3244.0,-1182.9,1.79,2},{3410.1,352.2,1.48,1},{42.4,-2378.7,1.25,1},{3002.6,527.7,1.18,1},
		{-2268.6,-2036.6,1.18,1},{165.3,-2344.1,1.71,2},{418.9,-2392.3,1.7,2},{-2572.2,-1626.6,1.87,2},{-2805.9,247.6,1.72,2},{770.9,-2439.2,1.92,2},{1841.6,-2358.9,1.07,1},{-2448.6,-1858.7,1.96,2},
		{-2406.6,-1800.3,1.96,2},{3012.4,-1525.7,1.48,1},{3702.7,502.8,1.57,2},{3420.0,469.4,1.98,2},{3666.8,391.8,1.16,1},{-2551.4,-1684.7,1.71,2},{372.7,-2341.0,1.41,2},{3062.4,-1564.8,1.27,2},
		{2295.6,-2262.4,1.43,2},{-1488.4,-2386.5,1.02,1},{3383.8,555.9,1.26,2},{590.4,-2406.0,1.26,1},{3481.4,390.9,1.56,1},{304.3,-2355.4,1.39,1},{3315.1,504.4,1.39,1},{-2920.6,-933.2,1.66,2},
		{-2892.7,-996.0,1.27,1},{916.4,-2412.1,1.22,1},{-3083.2,-36.3,1.89,2},{3323.7,491.5,1.44,1},{-2966.8,-724.7,1.05,1},{3210.6,714.8,1.53,1},{-944.0,-2482.7,1.68,2},{287.0,-2392.5,1.29,1},
		{283.9,-2346.3,1.99,2},{-2749.2,-1423.2,1.5,2},{3148.4,506.7,1.69,2},{1283.0,-2515.6,1.93,2},{-2712.6,-1581.9,1.1,1},{3616.4,541.6,1.47,2},{3426.2,524.5,1.21,1},{-1388.6,-2372.3,1.99,2},
		{-3063.0,-123.6,1.6,2},{3687.4,139.8,1.14,1},{-2939.0,-901.3,1.49,2},{-2822.9,332.6,1.69,2},{-1196.3,-2416.0,1.83,2},{-2975.8,-568.8,1.77,2},{-2457.8,-1748.2,1.91,2},{-2113.0,-2083.8,1.77,2},
		{3003.0,740.4,1.97,2},{-2959.8,-839.5,1.87,2},{-1089.3,-2447.3,1.25,2},{-2304.5,-1955.8,1.26,1},{-2779.9,-1351.9,1.83,2},{3486.7,479.6,1.59,1},{3352.3,579.0,1.25,2},{3277.1,-995.9,1.63,2},
		{-2112.1,-2146.2,1.54,2},{3609.4,343.5,1.31,1},{1117.2,-2468.2,1.13,1},{3469.7,-570.6,1.52,2},{3030.4,731.6,1.5,2},{2193.6,-2301.9,1.67,2},{-1268.7,-2411.1,1.38,2},{387.9,-2337.2,1.35,2},
		{-1174.5,-2422.9,1.1,1},{-2742.2,336.3,1.24,1},{3561.5,194.9,1.5,1},{-1823.6,-2254.0,1.86,2},{-2235.5,-2025.6,1.42,1},{629.6,-2426.9,1.14,1},{-2477.8,-1785.4,1.37,2},{3616.0,81.8,1.31,2},
		{3364.3,-899.8,1.11,1},{-2775.0,322.3,1.45,1},{-1054.5,-2436.2,1.4,2},{3108.8,503.0,1.45,1},{3325.2,402.5,1.49,2},{-2967.0,-54.5,1.33,2},{-1187.4,-2439.0,1.51,1},{343.1,-2378.4,1.53,2},
		{170.9,-2361.7,1.31,1},{-2798.9,451.9,1.28,2},{1217.9,-2486.1,1.5,2},{746.5,-2377.2,1.12,1},{-2634.8,-1667.8,1.27,1},{3592.8,250.9,1.54,1},{3563.5,533.1,1.73,2},{564.3,-2353.3,1.56,2},
		{-2051.1,-2196.3,1.38,1},{-2865.9,-1172.5,1.6,2},{-3026.2,-672.0,1.55,1},{900.9,-2418.2,1.48,2},{1343.1,-2482.2,1.67,2},{-2996.1,-689.8,1.98,2},{910.0,-2450.5,1.35,2},{3612.9,-196.5,1.32,1},
		{3516.5,-175.7,1.73,2},{3434.4,-754.7,1.28,2},{3458.3,376.7,1.35,1},{-2504.8,-1783.7,1.34,2},{-2702.1,-1594.8,1.29,2},{812.3,-2381.1,1.58,1},{-2979.4,331.0,1.54,1},{2951.8,535.2,1.2,1},
		{3389.9,761.7,1.39,2},{3300.9,630.2,1.3,2},{3515.4,-499.8,1.35,1},{3296.5,865.8,1.6,2},{3658.9,-32.4,1.43,1},{2989.8,-1514.8,1.8,2},{-2900.3,392.0,1.53,2},{3142.2,542.4,1.29,2},
		{3121.8,763.2,1.53,2},{-1852.6,-2255.6,1.81,2},{3268.9,447.2,1.4,2},{-1780.4,-2288.9,1.37,1},{1921.7,-2350.8,1.85,2},{-3038.0,73.3,1.08,1},{3458.8,-536.9,1.35,1},{-2561.1,-1654.8,1.41,1},
		{3647.3,395.2,1.35,1},{3704.7,487.0,1.12,1},{3365.9,-921.0,1.57,1},{-2971.8,-875.6,1.32,1},{3381.5,-819.6,1.05,1},{2415.1,-2140.7,1.55,2},{1607.0,-2448.6,1.78,2},{-2324.6,-1925.2,1.42,1},
		{1937.4,-2335.7,1.84,2},{2242.4,-2247.3,1.57,1},{-2848.0,307.0,1.4,1},{3368.1,-848.4,1.13,1},{-1908.2,-2214.3,1.38,2},{3142.6,638.2,1.07,1},{-2945.5,-957.6,1.15,1},{-2959.9,-858.8,1.4,2},
		{-3065.7,127.4,1.0,1},{2325.2,-2167.5,1.79,2},{2345.2,-2195.5,1.34,2},{708.2,-2370.4,1.84,2},{-3078.2,-94.9,1.28,1},{2723.3,-1896.4,1.39,2},{-2257.1,-1921.0,1.6,2},{-2824.1,-1252.0,1.57,1},
		{-2546.4,-1787.2,1.1,1},{-2604.6,-1622.3,1.18,1},{-2037.5,-2160.2,1.42,2},{967.7,-2480.1,1.7,2},{-1947.0,-2289.9,1.01,1},{3153.5,672.8,1.6,2},{2484.0,-2051.0,1.47,2},{-2997.3,145.7,1.52,1},
		{-152.4,-2411.8,1.51,1},{-3090.4,149.7,1.35,1},{3253.6,560.7,1.41,2},{3032.4,-1537.4,1.38,2},{-1508.9,-2354.6,1.58,1},{-2393.7,-1834.6,1.33,2},{3734.6,362.2,1.63,2},{3229.5,561.2,1.35,2},
		{2251.1,-2190.6,1.63,2},{3170.8,733.2,1.24,1},{-3001.5,32.4,1.26,1},{2544.5,-2065.4,1.33,2},{832.2,-2465.0,1.38,1},{3453.5,-706.6,1.59,1},{-1820.7,-2210.6,1.62,2},{3725.0,425.9,1.29,1},
		{-2206.4,-2066.8,1.38,2},{-3008.6,-303.5,1.69,2},{3098.3,615.0,1.36,2},{3113.4,601.1,1.53,2},{3682.9,457.0,1.88,2},{-2745.4,416.8,1.56,1},{2879.5,-1627.7,1.77,2},{-1118.6,-2444.6,1.79,2},
		{3664.8,230.5,1.6,2},{-2878.3,-989.8,1.73,2},{-3033.6,447.0,1.79,2},{3566.4,66.5,1.27,1},{-2091.7,-2162.4,1.5,2},{-2612.0,-1725.5,1.72,2},{2365.0,-2154.6,1.45,2},{3614.1,422.5,1.43,2},
		{2619.9,-1887.2,1.65,2},{3349.4,845.7,1.92,2},{-1408.2,-2387.6,1.55,2},{2982.9,597.5,1.91,2},{825.4,-2375.5,1.55,2},{-3048.6,245.8,1.57,2},{3016.4,772.8,1.4,1},{557.0,-2413.4,1.8,2},
		{3343.8,598.8,1.73,2},{1136.5,-2447.1,1.84,2},{34.7,-2392.2,1.45,2},{3440.8,-719.9,1.14,1},{-1840.5,-2316.4,1.01,1},{3365.9,454.4,1.28,2},{3252.9,811.6,1.13,1},{2311.4,-2199.5,1.46,1},
		{-2894.1,-1120.5,1.25,1},{964.9,-2414.6,1.56,1},{2478.0,-2074.5,1.76,2},{-1638.4,-2351.8,1.1,1},{-3056.8,278.0,1.96,2},{-2832.8,210.3,1.31,2},{-1831.2,-2269.8,1.29,1},{3245.7,528.8,1.49,1},
		{507.6,-2349.8,1.77,2},{511.9,-2367.5,1.97,2},{3062.2,748.7,1.86,2},{526.8,-2426.2,1.34,1},{3045.7,720.5,1.77,2},{-2909.5,271.1,1.4,2},{-2516.8,-1794.9,1.47,1},{3331.8,955.3,1.47,1},
		{-710.6,-2465.7,1.47,2},{-2980.8,-641.8,1.9,2},{-2672.9,464.8,1.86,2},{3582.9,326.3,1.09,1},{3005.4,-1618.7,1.52,1},{-1927.3,-2272.5,1.01,1},{3213.3,464.6,1.53,1},{-1976.5,-2225.6,1.4,2},
		{3353.4,645.4,1.82,2},{2268.0,-2157.6,1.75,2},{2992.6,-1555.8,1.5,1},{-2727.3,436.0,1.06,1},{-3031.5,-141.4,1.8,2},{3594.2,-191.2,1.2,1},{-2507.0,-1729.2,1.26,2},{3638.5,453.9,1.33,1},
		{3372.3,-788.9,1.33,2},{3402.0,528.3,1.38,1},{818.1,-2431.1,1.38,2},{2567.2,-2033.3,1.6,2},{-1032.7,-2404.6,2.0,2},{3503.4,-640.0,1.44,1},{3573.7,206.3,1.54,1},{-3021.5,336.7,1.42,2},
		{2210.2,-2303.2,1.55,1},{946.7,-2409.3,1.33,2},{3189.4,603.1,1.95,2},{2605.7,-1953.6,1.94,2},{2429.7,-2150.5,1.66,2},{3563.7,549.3,1.34,2},{-2611.0,-1675.3,1.21,1},{3283.6,655.9,1.72,2},
		{-2927.2,-1030.3,1.47,2},{-2430.2,-1920.2,1.23,1},{3178.8,-1239.6,1.86,2},{-1844.6,-2283.6,1.43,1},{-912.6,-2444.5,1.84,2},{1341.5,-2511.0,1.35,2},{-2345.3,-1989.6,1.06,1},{-2921.6,406.7,1.3,2},
		{3520.1,-157.4,1.5,1},{2792.7,-1768.0,1.6,2},{2435.7,-2085.2,1.54,2},{3577.1,111.0,1.43,1},{3416.5,744.2,1.25,1},{-1984.9,-2169.8,1.88,2},{3531.7,-572.5,1.66,2},{-2959.3,-889.2,1.93,2},
		{3593.8,281.7,1.07,1},{-926.5,-2479.5,1.93,2},{3672.4,365.3,1.36,1},{-3007.6,-652.6,1.37,1},{2838.2,-1780.8,1.11,1},{-2020.6,-2145.4,1.71,2},{-3074.9,241.3,1.59,1},{-3019.5,435.8,1.48,2},
		{3516.3,366.0,1.33,2},{3161.0,557.3,1.69,2},{-3015.5,-200.7,1.09,1},{1665.3,-2436.3,1.54,2},{2811.5,-1795.2,1.54,1},{-5.3,-2377.1,1.78,2},{3595.7,-218.8,1.21,1},{3690.2,441.6,1.59,2},
		{252.6,-2386.9,1.36,2},{803.3,-2471.6,1.83,2},{-1475.3,-2373.4,1.49,1},{-3084.5,-19.3,1.14,1},{-1560.2,-2326.9,1.5,1},{-2477.9,-1683.7,1.02,1},{-2834.1,-1214.6,1.67,2},{3382.3,859.6,1.76,2},
		{3095.5,690.8,1.48,2},{-1589.0,-2374.2,1.63,2},{3050.2,591.5,1.78,2},{-3013.6,-718.2,1.9,2},{3371.9,-731.2,1.29,2},{1876.8,-2361.9,1.47,1},{-2563.7,-1790.0,1.32,2},{837.9,-2343.7,1.9,2},
		{3333.3,-949.6,1.71,2},{3400.9,-758.3,1.23,1},{3101.4,755.2,1.22,1},{3301.4,461.7,1.26,1},{-1699.0,-2302.3,1.6,1},{-186.7,-2423.4,1.39,2},{3500.7,526.4,1.3,1},{2996.4,585.8,1.65,2},
		{3308.4,856.2,1.6,2},{3268.9,-1132.8,1.45,1},{1216.5,-2470.6,1.46,2},{3081.2,-1455.4,1.32,1},{3347.0,-889.7,1.37,1},{-2980.2,-838.7,1.76,2},{3678.1,177.6,1.17,1},{-2686.6,-1525.5,1.99,2},
		{3074.7,-1537.1,1.76,2},{-2824.7,-1278.1,1.94,2},{-1218.1,-2396.1,1.26,1},{-930.8,-2456.5,1.37,2},{1614.7,-2433.8,1.41,1},{-1840.8,-2215.6,1.0,1},{-2492.6,-1670.0,1.53,2},{330.2,-2360.2,1.12,1},
		{2311.2,-2156.2,1.38,1},{336.8,-2393.5,1.32,1},{-3060.9,330.9,1.6,1},{-2950.9,107.0,1.39,2},{-2474.2,-1759.1,1.98,2},{2790.7,-1808.1,1.84,2},{-2653.8,-1553.1,1.35,2},{-2834.7,298.7,1.95,2},
		{-1817.3,-2276.4,1.33,2},{3634.8,170.1,1.11,1},{604.9,-2404.0,1.55,1},{872.9,-2436.4,1.51,1},{3457.3,-634.3,1.79,2},{-2521.8,-1766.0,1.43,1},{-2502.6,-1606.0,1.51,1},{3402.5,808.8,1.32,1},
		{3530.4,343.7,1.96,2},{3537.8,-332.7,1.23,1},{616.1,-2444.5,1.63,2},{3083.4,608.6,1.52,2},{3006.1,660.1,1.29,2},{-3029.8,214.9,1.61,2},{-2441.7,-1893.0,1.73,2},{-2173.0,-2052.4,1.55,2},
		{3435.6,701.4,1.39,1},{3191.2,703.1,1.02,1},{-2253.6,-1946.9,1.15,1},{2720.3,-1857.1,1.72,2},{3639.8,439.5,1.86,2},{1378.0,-2483.1,1.49,2},{3187.1,-1251.8,1.1,1},{-3000.5,-776.6,1.05,1},
		{2975.7,-1607.1,1.3,1},{-2978.0,300.3,1.87,2},{3518.5,410.8,1.35,1},{-3060.0,-163.0,1.34,1},{2210.3,-2235.7,1.36,1},{3347.3,-942.3,1.53,1},{3162.3,535.0,1.32,2},{3422.5,-612.9,1.03,1},
		{1416.7,-2461.0,1.65,2},{3385.5,-939.1,1.19,1},{2975.8,-1493.2,1.44,1},{-2673.9,-1599.4,1.77,2},{-3041.9,-257.5,1.54,2},{-2954.4,201.2,1.3,2},{3561.7,436.3,1.51,2},{2206.6,-2161.0,1.12,1},
		{2307.8,-2134.8,1.39,2},{-3058.3,-374.0,1.48,2},{-3051.1,136.8,1.12,1},{3669.6,-12.6,1.5,1},{2993.1,-1498.5,1.26,2},{3627.2,210.9,1.3,2},{3226.3,-1194.6,1.46,1},{-3089.2,67.2,1.3,2},
		{-1533.6,-2365.8,1.21,1},{-1750.6,-2333.7,1.6,2},{162.9,-2378.5,1.94,2},{-1493.5,-2358.1,1.11,1},{-3063.2,345.6,1.4,2},{3332.0,791.7,1.15,1},{3587.3,438.3,1.42,1},{2978.6,572.0,1.38,1},
		{3616.5,225.2,1.34,2},{-2472.2,-1738.7,1.39,2},{1261.2,-2514.0,1.75,2},{3598.9,475.0,1.45,2},{-2940.9,-930.9,1.4,2},{3061.6,-1505.9,1.41,1},{2969.4,616.3,1.4,2},{3580.3,-85.2,1.55,2},
		{-3023.2,-430.0,1.58,2},{3346.9,-853.5,1.96,2},{3489.6,542.9,1.17,1},{-2629.4,455.5,1.38,1},{3502.5,500.6,1.59,2},{-805.5,-2445.6,1.19,1},{1837.7,-2317.6,1.47,2},{3508.6,-574.8,1.06,1},
		{3506.8,401.8,1.98,2},{3075.1,707.7,1.37,2},{-2881.6,-931.0,1.77,2},{3583.1,-376.9,1.28,2},{-2743.0,-1490.2,1.9,2},{2456.9,-2108.6,1.45,1},{3327.2,920.4,1.15,1},{-2074.0,-2174.9,1.84,2},
		{-2012.5,-2208.6,1.37,2},{2994.7,613.9,1.28,1},{3439.4,-651.6,1.67,2},{-2892.1,437.1,1.4,2},{-2600.5,-1689.9,1.31,2},{3070.9,679.1,1.21,1},{3594.2,149.6,1.48,2},{3412.4,660.1,1.15,1},
		{-2979.8,-857.2,1.57,2},{-3013.6,-163.9,1.24,1},{-2978.6,-753.7,1.26,2},{2371.7,-2138.4,1.31,2},{-1941.9,-2163.9,1.94,2},{2406.9,-2215.9,1.53,2},{644.0,-2423.8,1.95,2},{-1881.4,-2206.5,1.3,2},
		{372.6,-2304.0,1.08,1},{3034.2,599.3,1.91,2},{3439.1,-675.3,1.48,1},{2956.5,-1497.2,1.09,1},{3657.8,500.9,1.57,2},{-2710.5,478.6,1.28,1},{1560.7,-2426.1,1.29,2},{3599.4,45.7,1.19,1},
		{3056.2,701.4,1.87,2},{-3109.3,196.9,1.05,1},{1103.0,-2424.2,1.78,2},{-2932.0,-942.0,1.4,1},{2793.8,-1831.9,1.83,2},{604.6,-2383.0,1.56,2},{-2827.7,375.9,1.86,2},{510.5,-2413.6,1.01,1},
		{-1283.9,-2392.7,1.54,1},{-922.8,-2407.6,1.69,2},{3094.5,-1347.5,1.79,2},{2637.2,-1910.9,1.98,2},{3024.8,505.3,1.87,2},{-857.6,-2485.6,1.44,1},{-2706.0,430.3,1.76,2},{3491.5,-583.4,1.39,2},
		{2442.4,-2120.1,1.05,1},{3534.3,-368.4,1.4,2},{-2179.3,-2072.7,1.28,1},{-2944.5,130.7,1.27,2},{3350.5,509.6,1.05,1},{3022.4,-1554.3,1.37,1},{-2970.3,-592.3,1.43,1},{770.2,-2400.3,1.29,2},
		{-793.6,-2456.2,1.32,2},{-2912.2,-976.5,1.45,1},{3520.3,-353.4,1.72,2},{2419.5,-2205.6,1.1,1},{2922.3,-1711.5,1.2,1},{3287.4,599.3,1.02,1},{-2757.1,-1391.0,1.24,1},{3540.5,-445.3,1.34,2},
		{-2732.9,452.1,1.87,2},{-2920.9,310.7,1.35,1},{3494.0,-504.4,1.11,1},{-1641.3,-2324.3,1.39,2},{3570.0,305.5,1.52,1},{-3085.3,439.1,1.07,1},{2900.8,-1604.7,1.55,2},{-3026.6,-706.9,1.98,2},
		{-2878.5,-1083.8,1.44,2},{3625.7,-89.0,1.7,2},{2363.1,-2211.6,1.33,1},{805.4,-2450.2,1.68,2},{3430.7,654.0,1.2,1},{-2397.9,-1936.8,1.28,1},{2916.5,-1693.6,1.52,1},{2775.9,-1784.3,1.4,2},
		{-3075.3,79.3,1.06,1},{3072.8,-1397.2,1.26,2},{1778.5,-2376.9,1.34,1},{1159.1,-2460.8,1.65,2},{-1042.5,-2466.8,1.56,2},{3473.2,-665.6,1.54,1},{-975.2,-2460.0,1.5,1},{3300.9,922.8,1.55,2},
		{3539.5,184.5,1.78,2},{-1077.5,-2406.6,1.15,1},{3481.9,-450.9,1.2,1},{3280.1,734.7,1.86,2},{-1994.9,-2191.9,1.52,1},{3563.7,-184.6,1.56,1},{3599.8,-167.0,1.45,2},{3321.8,845.4,1.12,1},
		{-2945.7,348.6,1.59,1},{3321.2,420.1,1.36,1},{-3004.5,-57.4,1.38,2},{-2939.7,-53.6,1.01,1},{-1952.6,-2265.1,1.08,1},{545.3,-2327.6,1.19,1},{3467.7,-504.3,1.48,2},{-3010.5,-622.3,1.56,2},
		{-2526.4,-1811.1,1.86,2},{820.6,-2453.5,1.9,2},{-2992.8,46.9,1.88,2},{3304.1,704.2,1.5,1},{-1719.2,-2294.8,1.72,2},{-3041.9,-219.2,1.16,1},{-2734.8,-1458.5,1.56,1},{3485.2,519.3,1.64,2},
		{-2762.7,391.3,1.88,2},{-2910.1,250.4,1.11,1},{-3018.1,-804.1,1.18,1},{3247.5,783.8,1.19,1},{3744.7,449.7,1.83,2},{-2369.5,-1893.4,1.04,1},{-308.3,-2364.9,1.33,1},{-2896.8,334.9,1.59,2},
		{3645.7,75.9,1.5,1},{-1050.1,-2450.5,1.82,2},{-2866.8,-1100.8,1.64,2},{3034.4,-1454.8,1.67,2},{3444.3,728.9,1.29,2},{984.3,-2490.9,1.69,2},{-2882.0,339.1,1.68,2},{2981.5,-1449.4,1.08,1},
		{2277.0,-2253.3,1.3,2},{3680.0,193.7,1.63,2},{3387.6,-677.2,1.55,1},{-2911.9,-949.0,1.48,2},{3456.9,456.7,1.81,2},{3094.2,724.3,1.13,1},{3296.8,555.5,1.29,2},{867.1,-2378.9,1.34,2},
		{3401.4,-633.5,1.14,1},{3528.3,594.3,1.41,2},{3068.8,-1466.9,1.58,2},{3411.7,-848.3,1.12,1},{3516.0,-375.6,1.32,1},{-2844.1,421.9,1.12,1},{3225.3,581.8,1.25,1},{-1122.3,-2408.4,1.42,2},
		{-3055.4,69.2,1.4,2},{-1695.4,-2279.7,1.5,2},{-2889.5,-1063.0,1.58,1},{2965.1,-1477.9,1.57,1},{-2856.1,-1022.1,1.03,1},{3481.7,-624.1,1.59,1},{2536.6,-2092.2,1.55,1},{-2985.2,271.0,1.63,2},
		{-3028.7,-467.5,1.91,2},{-385.6,-2435.7,1.96,2},{2749.6,-1875.8,1.35,2},{3589.5,-244.0,1.34,2},{-2972.9,145.3,1.55,1},{3452.6,-742.4,1.15,1},{2562.8,-2049.0,1.02,1},{3606.3,367.1,1.94,2},
		{3039.4,497.3,1.9,2},{-3004.4,-114.2,1.61,2},{-2793.1,381.8,1.32,1},{3290.1,515.1,1.97,2},{2938.5,569.7,1.4,2},{744.4,-2282.2,1.99,2},{-2719.4,-1563.1,1.75,2},{-2505.7,507.0,1.37,2},
		{3669.5,12.9,1.3,2},{370.0,-2373.5,1.57,1},{3546.7,-302.7,1.62,2},{-3028.8,-654.3,1.5,2},{3237.5,-1020.1,1.46,1},{580.4,-2433.7,1.28,1},{2485.7,-2127.2,1.85,2},{3081.2,649.3,1.3,1},
		{3492.8,-600.6,1.26,2},{-169.2,-2404.1,1.5,2},{-2270.4,-2013.5,1.9,2},{3617.5,6.4,1.48,1},{3506.0,555.0,1.57,1},{1819.0,-2335.2,1.35,2},{3679.1,402.6,1.63,2},{-2123.1,-2129.4,1.26,1},
		{661.0,-2358.7,1.35,2},{3206.5,575.3,1.48,1},{1198.6,-2497.1,1.75,2},{-2459.0,-1847.5,1.71,2},{453.9,-2325.6,1.25,1},{-686.1,-2462.2,1.58,1},{3100.9,708.2,1.1,1},{1329.1,-2447.3,1.25,2},
		{-2951.2,238.9,1.4,2},{-1421.8,-2392.9,1.42,1},{1378.5,-2466.3,1.46,1},{-2582.2,-1641.3,1.5,2},{408.1,-2411.9,1.29,1},{-3044.0,-78.6,1.48,2},{3014.6,-1442.6,1.58,1},{3188.1,789.1,1.41,2},
		{2903.1,-1705.4,1.36,1},{3113.5,620.1,1.6,2},{3315.4,-997.3,1.22,1},{1537.7,-2453.5,1.02,1},{-1869.1,-2241.2,1.49,2},{228.0,-2336.6,1.9,2},{2883.3,-1688.8,1.16,1},{284.2,-2372.9,1.05,1},
		{-2656.6,-1690.1,1.94,2},{-1175.4,-2384.3,1.53,2},{-296.3,-2430.8,1.22,1},{3300.0,749.7,1.32,2},{-2755.6,312.4,1.34,1},{3307.5,662.7,1.47,1},{-3082.3,97.6,1.94,2},{2508.6,-2099.9,1.19,1},
		{-3047.2,121.4,1.0,1},{-3083.4,415.9,1.73,2},{-3036.1,357.5,1.29,1},{-2490.1,-1714.0,1.48,1},{3406.1,-674.0,1.59,2},{-3001.4,383.1,1.69,2},{3332.6,-1022.2,1.25,1},{2148.3,-2289.6,1.36,1},
		{-2600.0,-1775.6,1.46,1},{-2602.8,-1571.9,1.29,1},{3568.9,11.7,1.5,1},{3266.2,750.8,1.59,2},{130.7,-2360.1,1.33,1},{3224.1,453.5,1.4,2},{-2345.1,-1966.9,1.28,2},{1139.3,-2465.2,1.87,2},
		{3059.6,519.5,1.49,1},{-1332.9,-2383.7,1.86,2},{-2937.0,-829.7,1.59,1},{889.3,-2386.2,1.83,2},{3199.2,-1322.2,1.29,1},{-2935.7,180.6,1.33,2},{1168.3,-2520.2,1.59,2},{-1786.7,-2247.9,1.73,2},
		{-3026.6,237.6,1.38,1},{-2282.6,-1980.6,1.54,1},{3247.5,747.9,1.65,2},{-1917.3,-2242.2,1.02,1},{-2316.5,-2011.4,1.46,1},{3092.4,582.0,1.49,1},{-2580.6,-1762.5,1.47,2},{-2851.7,-1165.3,1.41,1},
		{3359.5,-859.6,2.0,2},{-2912.7,-1048.4,1.26,2},{465.3,-2374.1,1.84,2},{3422.5,-781.8,1.07,1},{-2796.5,-1345.0,1.56,2},{3050.0,651.9,1.21,1},{3434.2,584.9,1.29,1},{-1860.7,-2282.1,1.21,1},
		{3575.0,426.5,1.08,1},{3656.9,172.4,1.95,2},{3696.6,248.4,1.02,1},{3650.5,154.2,1.09,1},{-2870.1,278.0,1.31,2},{2891.7,-1742.1,1.72,2},{3480.9,-692.7,1.56,2},{-2415.8,-1830.0,1.15,1},
		{-3023.2,67.7,1.26,2},{2072.8,-2275.7,1.19,1},{3478.4,557.4,1.56,1},{3476.5,424.6,1.96,2},{-2954.5,398.8,1.3,2},{3297.9,722.5,1.43,2},{3626.2,384.6,1.92,2},{-2142.0,-2130.0,1.31,1},
		{2731.9,-1844.9,1.44,1},{3136.4,-1353.9,1.5,2},{3752.4,386.9,1.83,2},{3358.4,484.9,1.29,2},{3674.4,323.1,1.03,1},{3461.0,-654.6,1.69,2},{1074.6,-2490.9,1.78,2},{1164.8,-2499.1,1.6,1},
		{-2957.4,-929.0,1.59,2},{-2829.3,226.5,1.79,2},{-2399.3,-1851.8,1.25,1},{3679.9,421.7,1.54,2},{-3061.5,-257.3,1.39,1},{3647.2,473.5,1.51,1},{-3024.7,-54.7,1.42,2},{-2239.8,-1952.9,1.35,1},
		{1964.0,-2333.2,1.85,2},{3467.4,642.0,1.23,1},{3576.7,151.6,1.31,1},{-2442.0,-1811.8,1.9,2},{2986.1,506.5,1.1,1},{3607.8,306.5,1.49,2},{-2675.1,-1582.1,1.39,1},{3361.5,867.3,1.27,1},
		{851.9,-2390.0,1.37,2},{-3080.8,382.8,1.31,1},{-3072.1,211.5,1.33,1},{-1374.8,-2363.0,1.46,2},{-3001.0,3.7,1.36,2},{2673.0,-1930.9,1.1,1},{-2914.5,-999.5,1.74,2},{3716.8,466.6,1.65,2},
		{2943.5,552.9,1.6,2},{3137.4,-1426.2,1.87,2},{1082.5,-2435.7,1.25,1},{77.4,-2370.8,1.34,1},{-992.1,-2372.2,1.55,2},{3115.3,561.9,1.83,2},{3266.7,890.9,1.82,2},{-1549.4,-2345.8,1.48,2},
		{-3023.7,276.2,1.49,2},{2675.8,-1958.7,1.41,2},{-2625.7,-1708.6,1.67,2},{143.4,-2389.0,1.08,1},{2964.4,-1647.1,1.03,1},{2730.3,-1867.4,1.28,2},{2260.3,-2237.0,1.8,2},{3454.5,-757.8,1.32,1},
		{-2989.1,-655.7,1.44,2},{-2934.2,256.4,1.86,2},{-2797.4,-1285.3,1.93,2},{-311.7,-2403.3,1.76,2},{3051.1,-1590.5,1.96,2},{-3051.5,361.2,1.26,1},{3544.7,386.1,1.6,1},{2225.8,-2159.5,1.34,1},
		{-2859.4,-1130.1,1.49,1},{3441.6,625.6,1.44,2},{3633.0,480.2,1.35,1},{751.5,-2418.1,1.2,1},{3734.2,272.5,1.29,1},{2926.1,-1608.6,1.19,1},{-2634.1,-1554.0,1.65,2},{1798.5,-2362.0,1.49,1},
		{1243.1,-2479.1,1.71,2},{3401.6,570.7,1.96,2},{-1605.1,-2338.1,1.07,1},{60.2,-2401.1,1.49,1},{3675.0,282.4,1.7,2},{3504.4,-691.9,1.36,2},{-3093.0,17.7,1.52,2},{1226.1,-2520.3,1.34,2},
		{3497.4,-663.3,1.08,1},{-1151.3,-2401.4,1.41,1},{3014.5,-1403.4,1.26,2},{-1756.5,-2311.5,1.49,2},{-2894.7,375.3,1.73,2},{-2874.3,-1114.0,2.0,2},{-1969.8,-2165.8,1.33,2},{-3031.5,-291.8,1.37,1},
		{-3021.9,-564.1,1.84,2},{90.0,-2356.9,1.33,2},{3342.1,-977.7,1.85,2},{3065.7,656.7,1.49,2},{-2945.5,412.1,1.52,2},{-832.0,-2385.1,1.51,1},{2489.9,-2112.1,1.46,2},{-2838.1,-1271.9,1.34,1},
		{2269.3,-2198.2,1.46,1},{3695.0,104.6,1.57,1},{-3053.7,395.9,1.4,1},{1201.0,-2449.0,1.34,2},{287.5,-2299.6,1.45,1},{2255.3,-2215.0,1.83,2},{3696.4,475.3,1.99,2},{1316.1,-2509.2,1.42,2},
		{-2811.7,375.8,1.51,1},{-2695.2,463.7,1.03,1},{3643.4,250.3,1.45,2},{3587.5,-288.9,1.52,2},{-2361.9,-1964.8,1.44,1},{3264.9,-1024.3,1.94,2},{-911.0,-2467.6,1.11,1},{-2969.6,64.8,1.68,2},
		{758.7,-2447.9,1.46,2},{-2703.1,-1524.7,1.26,2},{1148.3,-2493.7,1.05,1},{3241.6,485.1,1.62,2},{1267.7,-2454.1,1.51,1},{-2315.9,-1977.1,1.0,1},{2156.9,-2240.3,1.72,2},{-2991.1,341.8,1.46,1},
		{3479.3,-489.0,1.43,1},{2740.2,-1810.6,1.75,2},{3364.5,725.7,1.32,1},{3521.5,-611.8,1.05,1},{2619.9,-2002.0,1.26,1},{-2475.6,-1703.8,1.79,2},{645.8,-2347.5,1.28,1},{2334.7,-2133.7,1.38,2},
		{3474.4,-467.1,1.06,1},{3595.1,9.9,1.73,2},{3273.9,592.6,1.62,2},{-9.2,-2417.1,1.16,1},{452.9,-2392.0,2.0,2},{-3014.7,-830.1,1.51,1},{3070.1,-1488.7,1.61,2},{3183.3,524.3,1.01,1},
		{3057.6,-1440.7,1.47,1},{3268.4,-1178.2,1.91,2},{-1738.6,-2315.4,1.27,1},{2963.8,-1679.2,1.57,1},{3663.9,349.7,1.2,1},{-710.7,-2416.3,1.78,2},{3267.8,726.7,1.17,1},{-811.9,-2480.8,1.22,1},
		{-2777.9,276.0,1.77,2},{-1944.9,-2236.7,1.94,2},{1120.5,-2486.8,1.48,2},{-821.2,-2439.2,1.88,2},{-697.4,-2433.5,1.13,1},{3088.2,-1407.6,1.48,1},{-3096.5,132.3,1.73,2},{-3067.2,-194.0,1.21,1},
		{3521.7,485.2,1.47,2},{-2247.6,-1993.6,1.54,1},{-1816.5,-2306.0,1.12,1},{2177.6,-2295.4,1.59,2},{3239.0,734.7,1.03,1},{-3026.6,-606.7,1.7,2},{1066.2,-2430.3,1.53,2},{3602.3,-67.1,1.46,2},
		{3117.7,-1358.8,1.22,1},{-3006.8,-851.4,1.4,2},{3646.1,127.2,1.94,2},{-2854.0,-1109.0,1.82,2},{3348.4,665.0,1.04,1},{3494.5,332.0,1.81,2},{3115.3,788.5,1.97,2},{-2201.3,-2035.5,1.07,1},
		{-2987.3,-805.2,1.48,1},{3179.7,-1300.8,1.27,1},{-2898.6,457.3,1.77,2},{610.9,-2426.0,1.32,2},{3240.6,673.5,1.89,2},{-2955.5,223.7,1.27,1},{-2801.5,285.9,1.65,2},{2620.5,-1959.6,1.91,2},
		{232.7,-2382.6,1.49,2},{519.0,-2397.2,1.01,1},{3096.7,550.7,1.41,1},{663.2,-2374.2,1.33,2},{-3050.3,-311.7,1.77,2},{-2814.4,392.0,1.07,1},{-923.9,-2385.0,1.29,2},{3213.9,-1243.6,1.6,2},
		{3273.7,696.2,1.44,1},{-2781.1,-1399.1,1.29,1},{1561.2,-2443.1,1.87,2},{106.6,-2405.4,1.82,2},{3345.1,-994.4,1.87,2},{-2462.3,-1691.9,1.25,1},{-2996.8,441.0,1.74,2},{3249.9,-1133.2,1.58,1},
		{3619.7,473.5,1.3,1},{3152.3,620.8,1.49,1},{3258.2,-1107.0,1.62,2},{3412.6,780.0,1.47,2},{-3023.7,-496.6,1.81,2},{3355.5,786.0,1.3,1},{3594.3,132.8,1.27,1},{3504.2,-397.8,1.7,2},
		{-2577.4,486.8,1.56,1},{-2948.9,270.2,1.96,2},{3014.9,564.1,1.35,2},{755.8,-2404.6,1.66,2},{3570.1,-41.3,1.26,2},{3720.5,286.2,1.69,2},{-2448.7,-1718.4,1.71,2},{1470.8,-2477.3,1.31,2},
		{2288.0,-2278.2,1.49,2},{3471.5,-720.3,1.22,1},{2318.8,-2259.5,1.51,1},{3393.4,822.8,1.47,2},{-1808.6,-2330.2,1.75,2},{-630.9,-2425.9,1.31,1},{3692.9,221.5,1.48,2},{3568.7,-334.8,1.47,2},
		{-2673.9,-1567.9,1.28,1},{3288.2,883.7,1.16,1},{-2627.8,-1750.1,1.6,2},{-3001.3,-526.9,1.41,4},{-2995.9,-550.3,0.91,4},{-2993.3,-557.0,1.24,4},{-2996.4,-567.6,0.88,4},{-2974.7,-569.0,1.21,4},
		{-2964.8,-564.2,1.11,4},{-2951.5,-561.6,1.23,4},{-2945.4,-560.7,0.96,4},{-2929.5,-559.6,0.92,4},{-2926.7,-573.8,0.97,4},{-2925.7,-576.0,1.13,4},{-2925.3,-587.8,0.95,4},{-2921.1,-593.4,1.49,4},
		{-2930.0,-594.4,0.92,4},{-2934.3,-597.7,1.43,4},{-2950.8,-603.3,1.18,4},{-2957.9,-604.6,0.99,4},{-2966.6,-604.9,1.16,4},{-2981.0,-610.7,1.25,4},{-2985.4,-619.8,1.11,4},{-2978.2,-642.3,1.35,4},
		{-2976.7,-648.5,1.05,4},{-2977.6,-660.6,1.44,4},{-2976.2,-682.3,1.43,4},{-2973.7,-694.3,1.14,4},{-2968.3,-707.0,0.94,4},{-2968.0,-712.0,1.38,4},{-2968.9,-721.4,1.01,4},{-2961.2,-738.6,1.45,4},
		{-2955.1,-757.8,0.99,4},{-2952.2,-766.4,1.1,4},{-2944.9,-773.0,0.83,4},{-2945.0,-779.1,1.05,4},{-2933.6,-806.5,1.24,4},{-2934.7,-809.2,1.35,4},{-2931.9,-829.7,1.06,4},{-2924.9,-840.8,1.21,4},
		{-2925.7,-859.1,0.8,4},{-2923.2,-882.1,1.43,4},{-2907.5,-901.7,1.06,4},{-2885.7,-911.4,1.11,4},{-2879.4,-915.7,0.93,4},{-2878.2,-923.1,1.23,4},{-2877.0,-960.5,0.93,4},{-2876.0,-969.2,0.95,4},
		{-2875.3,-980.8,1.12,4},{-2871.2,-1002.4,1.27,4},{-2867.1,-1008.1,1.36,4},{-2850.4,-1028.1,1.17,4},{-2841.8,-1037.5,0.84,4},{-2835.7,-1044.0,0.87,4},{-2837.5,-1049.0,1.49,4},{-2842.1,-1065.9,0.97,4},
		{-2846.5,-1073.6,1.37,4},{-2848.9,-1085.7,1.27,4},{-2832.3,-1099.1,1.21,4},{-2843.1,-1104.4,0.88,4},{-2853.6,-1126.1,1.15,4},{-2848.7,-1132.2,1.41,4},{-2845.6,-1144.1,0.97,4},{-2845.9,-1151.1,0.81,4},
		{-2837.5,-1157.0,1.39,4},{-2836.3,-1166.0,1.23,4},{-2832.6,-1178.8,0.82,4},{-2827.7,-1187.9,1.49,4},{-2816.5,-1210.2,1.35,4},{-2814.8,-1228.4,1.42,4},{-2811.0,-1233.4,1.5,4},{-2808.0,-1244.5,0.87,4},
		{-2803.9,-1254.1,1.39,4},{-2798.8,-1265.6,1.1,4},{-2793.9,-1288.9,1.15,4},{-2800.0,-1293.5,1.06,4},{-2792.1,-1303.4,1.43,4},{-2786.4,-1324.6,1.47,4},{-2786.0,-1327.5,1.48,4},{-2782.7,-1342.0,0.89,4},
		{-2773.9,-1351.5,1.3,4},{-2768.9,-1360.7,1.0,4},{-2766.9,-1366.9,1.3,4},{-2752.7,-1387.5,1.13,4},{-2729.1,-1376.2,1.32,4},{-2694.0,-1352.2,1.02,4},{-2687.0,-1368.6,0.95,4},{-2694.3,-1382.0,0.8,4},
		{-2696.0,-1388.6,1.38,4},{-2728.5,-1412.0,1.06,4},{-2718.9,-1423.4,1.4,4},{-2710.3,-1433.8,1.27,4},{-2699.8,-1450.5,1.01,4},{-2688.6,-1456.3,1.4,4},{-2662.3,-1489.0,1.41,4},{-2653.2,-1504.8,1.43,4},
		{-2641.1,-1524.0,1.37,4},{-2632.6,-1538.8,1.0,4},{-2621.9,-1551.4,1.31,4},{-2615.1,-1556.5,1.07,4},{-2604.8,-1563.7,1.49,4},{-2600.8,-1567.2,1.01,4},{-2589.4,-1579.3,0.96,4},{-2585.5,-1585.3,1.29,4},
		{-2578.9,-1595.4,1.1,4},{-2558.5,-1609.5,1.17,4},{-2553.1,-1619.4,0.97,4},{-2536.1,-1625.1,1.39,4},{-2530.3,-1613.0,1.23,4},{-2518.0,-1605.9,0.93,4},{-2512.1,-1597.4,0.93,4},{-2492.5,-1635.2,0.94,4},
		{-2488.2,-1642.8,1.42,4},{-2488.2,-1650.3,1.49,4},{-2479.2,-1668.0,0.94,4},{-2470.0,-1676.5,1.43,4},{-2468.2,-1685.8,1.35,4},{-2440.5,-1699.8,1.4,4},{-2434.2,-1705.7,1.38,4},{-2430.3,-1716.0,1.21,4},
		{-2438.4,-1721.7,1.4,4},{-2439.7,-1735.8,0.89,4},{-2441.9,-1752.1,1.28,4},{-2449.9,-1768.0,1.3,4},{-2418.8,-1764.5,0.99,4},{-2407.1,-1755.0,1.1,4},{-2399.5,-1753.9,1.42,4},{-2388.9,-1754.5,1.41,4},
		{-2387.9,-1758.1,1.26,4},{-2392.2,-1765.9,0.86,4},{-2402.1,-1773.0,1.06,4},{-2412.8,-1784.3,1.1,4},{-2398.3,-1796.9,1.26,4},{-2392.5,-1805.7,1.36,4},{-2382.4,-1825.4,1.27,4},{-2374.5,-1835.0,1.24,4},
		{-2372.3,-1838.7,0.83,4},{-2361.9,-1846.3,1.31,4},{-2350.4,-1860.7,1.06,4},{-2345.2,-1865.4,1.07,4},{-2332.9,-1879.1,1.27,4},{-2325.1,-1899.1,1.28,4},{-2315.9,-1906.1,1.17,4},{-2309.3,-1911.3,0.89,4},
		{-2302.9,-1923.6,1.14,4},{-2272.3,-1920.0,1.0,4},{-2250.8,-1903.3,1.0,4},{-2236.2,-1904.3,0.91,4},{-2231.1,-1912.9,0.98,4},{-2214.9,-1927.0,1.07,4},{-2218.1,-1937.0,1.32,4},{-2223.6,-1945.7,0.88,4},
		{-2234.0,-1951.1,0.89,4},{-2238.1,-1961.7,0.98,4},{-2256.3,-1980.1,1.07,4},{-2249.7,-1985.7,1.17,4},{-2238.2,-1995.3,1.28,4},{-2234.6,-2004.0,1.38,4},{-2225.9,-2012.4,1.23,4},{-2215.7,-2017.5,1.34,4},
		{-2202.7,-2032.2,0.84,4},{-2164.4,-2045.3,1.49,4},{-2137.0,-2061.7,0.95,4},{-2130.6,-2071.0,1.23,4},{-2125.0,-2075.9,1.2,4},{-2110.4,-2079.3,1.36,4},{-2098.7,-2091.1,0.87,4},{-2076.7,-2101.3,1.13,4},
		{-2045.6,-2117.8,1.14,4},{-2035.3,-2130.0,1.27,4},{-2020.6,-2143.7,1.4,4},{-2004.3,-2155.0,1.08,4},{-1985.8,-2157.5,1.4,4},{-1982.5,-2160.7,1.27,4},{-1976.3,-2158.4,1.15,4},{-1961.2,-2149.9,1.1,4},
		{-1959.2,-2148.3,1.0,4},{-1945.7,-2150.9,1.07,4},{-1939.9,-2158.7,0.82,4},{-1911.0,-2181.9,1.29,4},{-1878.7,-2196.5,1.02,4},{-1873.0,-2199.2,0.82,4},{-1839.5,-2202.3,1.32,4},{-1826.5,-2197.3,1.06,4},
		{-1805.0,-2222.7,1.48,4},{-1794.3,-2229.9,0.96,4},{-1789.8,-2235.4,1.24,4},{-1773.2,-2229.4,1.08,4},{-1781.6,-2246.0,1.5,4},{-1763.9,-2259.3,1.23,4},{-1748.3,-2263.4,1.22,4},{-1732.7,-2263.1,1.1,4},
		{-1723.7,-2267.7,1.28,4},{-1713.1,-2270.7,0.81,4},{-1696.7,-2278.3,0.93,4},{-1689.0,-2281.5,0.9,4},{-1691.1,-2290.3,1.13,4},{-1676.7,-2298.5,1.18,4},{-1667.8,-2301.3,1.25,4},{-1655.8,-2305.0,1.5,4},
		{-1641.7,-2312.1,1.22,4},{-1626.8,-2314.0,1.03,4},{-1618.9,-2314.7,1.13,4},{-1611.5,-2306.4,1.03,4},{-1594.9,-2314.7,1.49,4},{-1582.8,-2316.2,1.46,4},{-1568.4,-2326.8,1.04,4},{-1537.3,-2335.2,0.89,4},
		{-1528.9,-2336.7,0.96,4},{-1505.4,-2350.0,1.03,4},{-1484.3,-2351.1,0.93,4},{-1476.6,-2354.0,1.3,4},{-1470.2,-2361.0,1.06,4},{-1461.6,-2360.5,1.06,4},{-1430.0,-2363.7,1.27,4},{-1424.5,-2360.3,0.99,4},
		{-1423.2,-2354.6,0.82,4},{-1420.1,-2339.3,1.3,4},{-1415.4,-2311.1,1.01,4},{-1413.9,-2305.4,1.39,4},{-1411.9,-2304.5,1.07,4},{-1381.3,-2305.0,1.22,4},{-1365.3,-2315.4,1.25,4},{-1363.9,-2318.8,1.01,4},
		{-1364.4,-2329.3,0.87,4},{-1364.0,-2343.9,0.95,4},{-1369.7,-2356.1,0.96,4},{-1370.2,-2366.8,0.99,4},{-1334.3,-2383.4,1.09,4},{-1302.1,-2381.7,1.01,4},{-1296.5,-2389.0,0.93,4},{-1286.4,-2390.8,1.35,4},
		{-1272.2,-2386.7,1.24,4},{-1257.1,-2390.0,1.33,4},{-1249.0,-2387.3,1.19,4},{-1235.0,-2387.2,1.18,4},{-1224.3,-2390.0,1.18,4},{-1210.6,-2390.7,1.4,4},{-1199.3,-2389.3,1.11,4},{-1191.7,-2393.9,1.36,4},
		{-1178.2,-2386.1,1.04,4},{-1167.9,-2383.9,1.0,4},{-1149.3,-2387.2,1.23,4},{-1122.0,-2394.6,0.92,4},{-1097.8,-2394.7,0.93,4},{-1086.7,-2398.5,1.23,4},{-1073.0,-2396.2,0.81,4},{-1065.1,-2398.8,0.96,4},
		{-1054.1,-2395.4,1.29,4},{-1040.9,-2396.2,1.04,4},{-1033.6,-2395.1,1.05,4},{-1020.7,-2397.5,1.28,4},{-1015.3,-2398.7,0.89,4},{-994.4,-2396.9,0.96,4},{-990.2,-2363.3,0.85,4},{-972.3,-2354.4,0.86,4},
		{-953.5,-2368.3,1.33,4},{-943.4,-2372.7,0.98,4},{-927.3,-2374.2,1.27,4},{-906.0,-2382.5,1.47,4},{-901.3,-2381.1,1.06,4},{-878.5,-2376.0,1.01,4},{-869.6,-2377.3,1.07,4},{-854.9,-2371.0,0.82,4},
		{-841.1,-2363.7,1.28,4},{-825.7,-2372.5,1.36,4},{-803.7,-2396.6,1.2,4},{-797.1,-2403.2,1.05,4},{-749.5,-2372.9,0.96,4},{-748.0,-2396.1,1.37,4},{-744.3,-2412.0,0.98,4},{-726.6,-2415.5,1.21,4},
		{-717.3,-2412.4,0.8,4},{-708.3,-2415.5,1.29,4},{-700.9,-2407.1,1.24,4},{-691.5,-2411.1,1.2,4},{-685.5,-2409.2,1.13,4},{-673.1,-2414.2,0.88,4},{-659.2,-2409.9,1.06,4},{-641.9,-2415.1,1.5,4},
		{-626.7,-2414.6,1.48,4},{-618.7,-2417.6,1.21,4},{-610.7,-2424.9,1.08,4},{-599.8,-2425.0,1.37,4},{-592.2,-2428.4,1.23,4},{-579.6,-2424.4,1.29,4},{-565.7,-2426.0,1.24,4},{-558.4,-2430.2,1.13,4},
		{-549.0,-2432.0,1.25,4},{-527.3,-2430.1,0.93,4},{-514.1,-2430.0,1.33,4},{-493.8,-2430.9,1.06,4},{-484.2,-2435.5,0.88,4},{-474.2,-2433.3,0.89,4},{-468.7,-2432.6,1.47,4},{-458.5,-2436.4,1.26,4},
		{-433.9,-2435.3,1.37,4},{-425.1,-2439.0,1.18,4},{-414.8,-2437.5,1.06,4},{-397.7,-2435.8,1.47,4},{-376.0,-2435.9,1.34,4},{-366.7,-2438.0,1.47,4},{-350.0,-2434.5,1.42,4},{-339.5,-2431.7,1.45,4},
		{-340.4,-2388.1,1.19,4},{-331.2,-2367.3,0.93,4},{-305.6,-2363.0,1.06,4},{-299.8,-2368.6,1.15,4},{-296.5,-2379.1,1.31,4},{-298.6,-2390.5,1.18,4},{-280.5,-2425.8,1.41,4},{-263.3,-2423.3,1.05,4},
		{-244.7,-2419.4,0.85,4},{-235.8,-2419.0,1.06,4},{-227.8,-2415.2,0.81,4},{-214.0,-2412.8,1.5,4},{-179.8,-2403.3,0.91,4},{-170.4,-2402.9,1.43,4},{-162.1,-2400.0,1.28,4},{-125.5,-2404.3,0.83,4},
		{-117.3,-2399.3,1.27,4},{-108.2,-2400.7,1.19,4},{-100.2,-2398.4,0.82,4},{-78.0,-2393.6,1.13,4},{-68.4,-2388.8,0.9,4},{-58.9,-2391.3,1.34,4},{-49.0,-2386.0,1.35,4},{-40.9,-2386.2,1.49,4},
		{-31.0,-2384.4,0.94,4},{-28.2,-2374.0,1.07,4},{-8.9,-2368.8,1.32,4},{31.5,-2361.2,1.01,4},{64.2,-2355.2,1.41,4},{77.2,-2353.7,1.13,4},{88.2,-2350.9,1.04,4},{98.5,-2349.2,1.18,4},
		{113.2,-2344.7,1.49,4},{120.7,-2345.8,1.22,4},{132.5,-2340.9,0.86,4},{156.6,-2343.1,0.95,4},{168.6,-2342.6,1.23,4},{175.6,-2337.9,0.97,4},{192.0,-2338.2,1.16,4},{202.9,-2330.0,1.28,4},
		{214.8,-2326.9,1.39,4},{220.1,-2311.2,1.38,4},{230.7,-2296.3,0.96,4},{244.8,-2300.0,1.0,4},{250.5,-2302.6,0.89,4},{265.6,-2301.7,1.28,4},{273.8,-2298.9,1.05,4},{300.8,-2290.7,1.22,4},
		{309.4,-2288.0,1.38,4},{319.6,-2292.8,1.45,4},{326.0,-2305.5,1.06,4},{333.4,-2310.9,1.17,4},{346.2,-2326.4,1.11,4},{363.1,-2334.8,0.84,4},{369.4,-2324.6,0.93,4},{369.4,-2301.2,0.88,4},
		{376.7,-2296.2,0.94,4},{378.6,-2312.0,0.92,4},{374.1,-2321.3,1.39,4},{397.3,-2324.7,1.22,4},{413.8,-2323.6,1.27,4},{422.3,-2318.9,1.04,4},{430.3,-2322.3,1.24,4},{441.7,-2319.3,1.49,4},
		{469.4,-2322.3,1.34,4},{483.6,-2325.2,1.34,4},{503.3,-2326.1,1.22,4},{522.7,-2322.8,0.92,4},{531.2,-2326.6,1.12,4},{549.2,-2326.0,1.14,4},{563.6,-2330.2,1.48,4},{587.4,-2334.5,1.29,4},
		{599.8,-2334.7,0.82,4},{617.0,-2338.6,1.43,4},{624.9,-2336.3,1.13,4},{650.9,-2339.5,1.41,4},{700.5,-2335.2,1.07,4},{715.5,-2316.3,1.15,4},{715.9,-2309.8,1.02,4},{720.6,-2290.6,1.25,4},
		{717.5,-2283.7,0.9,4},{719.7,-2275.8,1.11,4},{756.6,-2275.8,1.39,4},{755.0,-2282.8,0.87,4},{751.5,-2296.7,1.23,4},{751.6,-2306.4,1.29,4},{746.1,-2313.6,0.8,4},{751.5,-2325.6,1.05,4},
		{764.4,-2328.9,0.97,4},{807.4,-2333.3,1.03,4},{812.3,-2337.9,1.29,4},{820.6,-2338.8,0.85,4},{832.4,-2341.6,1.38,4},{841.4,-2350.4,1.07,4},{846.2,-2360.2,1.32,4},{851.3,-2361.3,1.47,4},
		{858.3,-2364.9,0.91,4},{873.8,-2367.7,0.9,4},{894.4,-2369.6,1.14,4},{914.5,-2371.5,1.17,4},{927.8,-2373.6,1.18,4},{937.9,-2381.2,0.94,4},{943.2,-2386.0,0.83,4},{951.9,-2384.0,1.34,4},
		{969.1,-2388.0,1.0,4},{982.7,-2390.1,1.25,4},{987.9,-2391.4,1.32,4},{998.4,-2401.7,0.99,4},{1008.2,-2403.0,1.23,4},{1036.7,-2409.0,1.37,4},{1047.1,-2412.2,1.17,4},{1054.5,-2411.1,0.85,4},
		{1074.1,-2420.3,1.4,4},{1095.9,-2424.6,1.5,4},{1103.7,-2422.4,1.45,4},{1133.3,-2426.6,1.01,4},{1136.9,-2414.1,1.19,4},{1142.3,-2395.2,0.99,4},{1143.4,-2385.0,0.8,4},{1150.7,-2377.9,1.41,4},
		{1156.6,-2378.7,0.9,4},{1158.0,-2389.5,1.24,4},{1191.9,-2412.3,1.39,4},{1207.5,-2421.6,1.07,4},{1215.8,-2421.8,0.95,4},{1232.4,-2429.7,1.42,4},{1242.9,-2428.3,1.15,4},{1247.7,-2429.9,1.09,4},
		{1257.5,-2429.7,1.02,4},{1279.1,-2424.7,0.87,4},{1293.0,-2419.8,0.85,4},{1301.3,-2419.3,0.92,4},{1312.5,-2413.7,1.29,4},{1319.0,-2410.8,1.15,4},{1357.3,-2452.1,0.86,4},{1367.7,-2454.9,1.28,4},
		{1377.6,-2444.7,1.37,4},{1365.0,-2431.6,0.9,4},{1364.7,-2412.8,1.05,4},{1376.9,-2404.8,0.83,4},{1375.3,-2404.0,1.46,4},{1376.5,-2410.3,1.34,4},{1378.6,-2422.2,1.32,4},{1389.1,-2433.9,0.81,4},
		{1422.8,-2431.6,1.32,4},{1441.3,-2433.7,0.89,4},{1448.7,-2433.1,0.82,4},{1464.5,-2436.4,1.2,4},{1497.1,-2432.9,1.3,4},{1509.0,-2430.0,0.95,4},{1519.2,-2425.8,0.81,4},{1524.6,-2427.3,0.86,4},
		{1532.8,-2415.5,1.03,4},{1546.2,-2415.9,0.85,4},{1568.8,-2417.4,1.42,4},{1580.6,-2415.6,1.39,4},{1608.4,-2412.3,0.96,4},{1612.4,-2425.4,1.14,4},{1634.6,-2428.7,0.89,4},{1645.8,-2430.2,0.84,4},
		{1657.7,-2430.4,1.2,4},{1700.2,-2424.7,1.21,4},{1713.5,-2422.9,1.36,4},{1663.5,-2436.0,1.37,4},{1652.3,-2440.0,1.21,4},{1637.3,-2444.2,1.41,4},{1617.1,-2450.9,0.95,4},{1607.3,-2447.7,1.25,4},
		{1601.3,-2453.9,1.22,4},{1593.8,-2454.2,1.41,4},{1583.9,-2456.4,1.37,4},{1554.9,-2464.0,1.25,4},{1516.2,-2474.4,1.49,4},{1510.2,-2475.0,1.05,4},{1499.6,-2473.3,1.12,4},{1495.2,-2475.0,1.16,4},
		{1483.9,-2478.6,1.08,4},{1475.9,-2480.7,1.23,4},{1451.9,-2486.3,1.42,4},{1438.0,-2491.4,0.96,4},{1435.5,-2491.8,1.42,4},{1422.0,-2496.5,1.23,4},{1415.2,-2493.7,1.42,4},{1411.5,-2498.9,0.85,4},
		{1357.7,-2511.3,1.25,4},{1352.2,-2509.6,0.98,4},{1340.2,-2513.3,1.49,4},{1330.7,-2518.3,1.19,4},{1304.8,-2520.0,0.9,4},{1295.1,-2523.3,1.06,4},{1275.2,-2528.3,1.38,4},{1237.4,-2529.1,0.85,4},
		{1229.2,-2529.7,0.98,4},{1204.5,-2525.7,1.42,4},{1187.2,-2523.9,1.42,4},{1156.5,-2522.0,1.5,4},{1137.6,-2520.9,1.25,4},{1125.1,-2515.0,0.85,4},{1113.3,-2513.0,1.24,4},{1099.5,-2514.2,1.27,4},
		{1093.1,-2510.9,1.17,4},{1071.1,-2510.0,1.0,4},{1060.9,-2511.5,0.9,4},{1044.3,-2503.7,1.26,4},{1032.7,-2505.9,1.38,4},{1012.5,-2503.4,1.13,4},{991.5,-2498.7,1.05,4},{971.8,-2497.8,0.99,4},
		{942.7,-2489.9,1.14,4},{931.1,-2488.1,1.38,4},{921.3,-2491.1,1.11,4},{914.1,-2490.1,1.09,4},{874.7,-2480.9,0.86,4},{827.9,-2478.5,1.13,4},{806.5,-2471.9,1.1,4},{798.9,-2469.1,1.37,4},
		{770.5,-2468.8,1.0,4},{760.2,-2464.2,0.93,4},{749.6,-2467.0,0.97,4},{739.3,-2466.8,1.41,4},{719.4,-2461.1,1.25,4},{710.9,-2461.9,0.97,4},{696.1,-2456.7,1.45,4},{684.1,-2457.7,0.93,4},
		{672.8,-2454.4,1.45,4},{664.8,-2454.7,1.5,4},{652.9,-2449.0,1.41,4},{623.2,-2446.6,1.26,4},{617.0,-2447.1,0.95,4},{605.5,-2447.3,0.96,4},{596.0,-2445.6,1.3,4},{578.9,-2441.8,0.96,4},
		{539.7,-2434.1,0.85,4},{532.1,-2433.7,0.87,4},{524.1,-2436.1,1.2,4},{515.8,-2434.7,1.49,4},{483.9,-2426.8,1.46,4},{477.4,-2429.6,1.23,4},{469.0,-2423.8,1.38,4},{445.5,-2422.0,1.08,4},
		{440.2,-2422.8,1.44,4},{430.6,-2417.2,1.09,4},{416.8,-2417.3,1.32,4},{382.8,-2416.3,1.47,4},{361.9,-2408.1,1.29,4},{354.8,-2408.9,1.07,4},{348.9,-2408.8,1.39,4},{337.0,-2408.8,1.05,4},
		{327.2,-2406.7,1.32,4},{321.1,-2403.9,1.41,4},{312.3,-2403.7,0.87,4},{302.0,-2402.5,1.07,4},{294.1,-2399.8,0.86,4},{279.1,-2399.8,0.9,4},{260.9,-2399.7,1.2,4},{234.1,-2395.0,1.23,4},
		{219.5,-2396.6,1.32,4},{196.0,-2401.8,1.15,4},{189.2,-2403.3,1.23,4},{174.6,-2402.3,1.35,4},{153.9,-2401.1,1.18,4},{91.3,-2407.2,1.1,4},{78.4,-2407.7,1.08,4},{60.9,-2413.2,1.19,4},
		{12.0,-2418.3,0.85,4},{2.6,-2417.7,1.22,4},{-10.4,-2417.2,0.9,4},{-45.2,-2420.9,0.85,4},{-66.6,-2419.9,1.12,4},{-110.7,-2423.7,1.09,4},{-130.2,-2431.0,1.07,4},{-142.2,-2426.2,1.17,4},
		{-155.0,-2428.7,1.11,4},{-176.3,-2433.3,0.97,4},{-185.7,-2429.9,1.19,4},{-229.4,-2436.9,0.99,4},{-241.9,-2437.0,1.44,4},{-270.4,-2441.8,1.28,4},{-280.4,-2439.1,1.15,4},{-320.4,-2445.9,1.44,4},
		{-331.7,-2442.8,1.1,4},{-340.6,-2445.9,1.23,4},{-357.9,-2446.8,1.06,4},{-368.7,-2449.5,1.1,4},{-383.5,-2451.5,1.47,4},{-394.2,-2448.8,1.26,4},{-416.3,-2452.8,1.12,4},{-428.4,-2452.6,1.13,4},
		{-448.6,-2455.8,1.5,4},{-466.4,-2459.5,1.03,4},{-505.7,-2461.6,1.39,4},{-513.0,-2461.7,0.96,4},{-523.6,-2462.1,1.24,4},{-536.1,-2464.8,0.95,4},{-574.3,-2465.1,0.86,4},{-601.7,-2472.1,1.08,4},
		{-627.3,-2473.5,1.22,4},{-634.8,-2470.0,0.94,4},{-644.6,-2470.2,1.18,4},{-654.7,-2476.5,0.87,4},{-675.5,-2476.6,1.09,4},{-685.0,-2477.2,1.25,4},{-693.1,-2478.0,1.0,4},{-704.5,-2476.1,1.15,4},
		{-729.2,-2477.3,1.48,4},{-736.7,-2477.8,0.94,4},{-742.3,-2480.1,1.5,4},{-748.3,-2480.1,0.93,4},{-771.6,-2483.6,1.07,4},{-784.4,-2487.6,1.31,4},{-824.5,-2486.0,1.12,4},{-831.3,-2488.3,1.02,4},
		{-871.3,-2494.3,1.08,4},{-880.9,-2493.9,1.44,4},{-925.8,-2492.7,1.15,4},{-960.1,-2486.1,0.82,4},{-967.7,-2481.8,1.27,4},{-990.3,-2482.1,1.01,4},{-1013.5,-2476.1,1.03,4},{-1060.6,-2465.7,0.96,4},
		{-1077.3,-2462.3,1.16,4},{-1110.9,-2461.0,1.45,4},{-1119.9,-2457.8,0.93,4},{-1127.4,-2458.0,1.45,4},{-1150.2,-2451.0,1.04,4},{-1176.0,-2445.7,1.45,4},{-1189.3,-2444.6,0.96,4},{-1199.9,-2441.6,1.38,4},
		{-1212.5,-2444.2,1.44,4},{-1253.0,-2432.4,0.83,4},{-1273.0,-2428.6,1.01,4},{-1281.4,-2429.4,1.1,4},{-1297.8,-2428.2,1.11,4},{-1320.4,-2421.5,1.32,4},{-1338.4,-2419.6,0.91,4},{-1360.8,-2417.0,0.84,4},
		{-1379.8,-2415.3,1.07,4},{-1391.5,-2411.7,1.4,4},{-1400.4,-2406.6,0.86,4},{-1404.9,-2407.3,1.27,4},{-1416.4,-2409.0,1.43,4},{-1424.5,-2406.2,1.34,4},{-1438.9,-2405.5,1.07,4},{-1445.5,-2403.0,1.26,4},
		{-1457.8,-2397.7,1.37,4},{-1483.0,-2395.1,1.22,4},{-1512.0,-2390.8,0.81,4},{-1564.4,-2384.3,1.4,4},{-1575.7,-2381.2,0.91,4},{-1602.0,-2375.9,1.45,4},{-1613.1,-2374.0,0.99,4},{-1647.7,-2368.3,1.12,4},
		{-1696.1,-2356.3,1.21,4},{-1722.7,-2353.7,1.1,4},{-1742.1,-2348.3,0.82,4},{-1753.2,-2348.6,0.82,4},{-1772.6,-2347.8,1.3,4},{-1786.6,-2344.7,1.43,4},{-1791.1,-2339.1,0.97,4},{-1829.3,-2337.4,0.92,4},
		{-1889.0,-2325.6,1.26,4},{-1907.6,-2318.2,1.24,4},{-1924.4,-2317.2,0.82,4},{-1934.5,-2314.0,1.09,4},{-1945.7,-2306.1,1.33,4},{-1963.9,-2300.1,1.38,4},{-1969.3,-2291.7,1.41,4},{-1986.6,-2284.3,0.84,4},
		{-1995.0,-2278.9,1.13,4},{-2014.8,-2260.0,1.03,4},{-2024.9,-2253.2,0.95,4},{-2033.4,-2241.9,1.45,4},{-2041.6,-2235.5,1.12,4},{-2083.4,-2205.5,0.9,4},{-2089.5,-2203.2,1.48,4},{-2097.1,-2195.5,1.19,4},
		{-2129.1,-2166.7,0.88,4},{-2146.9,-2152.7,0.87,4},{-2153.8,-2148.1,1.13,4},{-2169.4,-2132.7,1.3,4},{-2183.5,-2124.0,1.22,4},{-2195.2,-2117.9,1.37,4},{-2199.6,-2108.5,1.35,4},{-2207.7,-2102.0,1.13,4},
		{-2213.8,-2096.3,1.13,4},{-2236.0,-2080.8,1.35,4},{-2245.7,-2073.8,1.03,4},{-2267.1,-2058.2,1.45,4},{-2274.1,-2050.9,1.0,4},{-2278.5,-2043.1,1.22,4},{-2288.4,-2037.0,1.39,4},{-2303.2,-2027.0,1.2,4},
		{-2327.2,-2006.0,0.85,4},{-2339.1,-1994.1,1.43,4},{-2349.6,-1988.5,1.1,4},{-2354.2,-1981.4,1.32,4},{-2363.9,-1980.7,1.06,4},{-2375.4,-1967.5,0.94,4},{-2383.1,-1959.9,1.37,4},{-2395.4,-1952.4,1.35,4},
		{-2403.1,-1945.1,1.41,4},{-2411.7,-1937.2,1.05,4},{-2424.0,-1926.8,1.36,4},{-2429.1,-1924.7,1.26,4},{-2435.1,-1916.5,0.86,4},{-2460.1,-1900.5,1.2,4},{-2463.4,-1895.9,0.88,4},{-2484.9,-1880.2,1.43,4},
		{-2511.1,-1859.2,1.5,4},{-2536.2,-1839.0,0.91,4},{-2544.3,-1831.6,0.86,4},{-2553.8,-1819.8,1.23,4},{-2571.5,-1805.7,1.0,4},{-2577.9,-1801.0,1.37,4},{-2593.5,-1791.0,1.03,4},{-2601.7,-1778.9,1.37,4},
		{-2612.0,-1775.6,0.98,4},{-2620.9,-1762.2,1.38,4},{-2632.6,-1749.3,1.43,4},{-2642.3,-1737.9,1.34,4},{-2644.1,-1730.7,0.89,4},{-2649.2,-1725.8,1.1,4},{-2659.2,-1714.1,1.26,4},{-2661.6,-1710.8,1.39,4},
		{-2661.6,-1702.8,1.11,4},{-2671.5,-1688.4,1.14,4},{-2671.6,-1679.6,1.45,4},{-2689.2,-1638.5,1.08,4},{-2696.0,-1631.8,1.2,4},{-2697.5,-1619.1,0.93,4},{-2703.5,-1612.6,1.31,4},{-2704.8,-1604.7,0.9,4},
		{-2709.2,-1596.7,1.21,4},{-2718.2,-1576.1,1.15,4},{-2718.6,-1568.2,1.23,4},{-2732.8,-1538.8,1.32,4},{-2740.5,-1513.8,1.22,4},{-2744.4,-1501.8,1.17,4},{-2750.7,-1492.4,0.95,4},{-2752.6,-1482.1,1.49,4},
		{-2759.9,-1473.6,1.24,4},{-2767.2,-1452.8,0.91,4},{-2775.4,-1430.3,0.92,4},{-2778.9,-1419.0,1.41,4},{-2806.0,-1356.9,1.49,4},{-2826.5,-1311.2,1.27,4},{-2830.1,-1304.1,1.25,4},{-2838.9,-1280.8,1.34,4},
		{-2847.6,-1253.0,1.33,4},{-2852.7,-1246.8,0.92,4},{-2860.8,-1218.7,1.45,4},{-2871.2,-1203.6,1.25,4},{-2881.2,-1176.2,1.41,4},{-2883.4,-1165.2,1.15,4},{-2892.9,-1150.9,0.92,4},{-2902.0,-1121.1,1.41,4},
		{-2907.3,-1108.6,0.84,4},{-2912.9,-1096.2,0.82,4},{-2919.7,-1088.9,1.19,4},{-2937.8,-1042.2,1.33,4},{-2942.7,-1021.7,0.98,4},{-2947.5,-1010.3,1.17,4},{-2949.7,-1003.6,1.46,4},{-2959.0,-990.2,0.92,4},
		{-2961.1,-981.9,1.07,4},{-2964.2,-978.0,1.22,4},{-2967.3,-969.7,1.34,4},{-2978.2,-940.1,1.2,4},{-2985.1,-917.1,1.16,4},{-2997.4,-897.9,1.36,4},{-2998.1,-891.6,1.12,4},{-3000.2,-882.3,1.34,4},
		{-3005.7,-864.0,1.28,4},{-3011.2,-857.7,1.45,4},{-3015.1,-818.6,1.37,4},{-3020.5,-810.0,1.45,4},{-3022.9,-787.1,1.38,4},{-3022.4,-780.4,1.13,4},{-3022.3,-736.9,1.43,4},{-3026.8,-728.9,0.98,4},
		{-3028.4,-709.3,1.28,4},{-3026.8,-701.8,1.11,4},{-3027.5,-693.2,0.88,4},{-3030.7,-653.6,1.36,4},{-3031.6,-643.4,1.05,4},{-3036.8,-634.0,1.25,4},{-3038.3,-622.3,0.96,4},{-3034.4,-610.3,1.5,4},
		{-3041.2,-589.2,1.25,4},{-3038.2,-586.4,0.97,4},{-3041.4,-555.5,0.95,4},{-3041.0,-543.0,0.86,4},{-3045.9,-521.4,1.14,4},{-3047.0,-478.5,1.37,4},{-3052.1,-459.0,1.35,4},{-3054.4,-422.6,0.88,4},
		{-3056.9,-414.3,0.82,4},{-3054.0,-406.2,1.45,4},{-3053.6,-397.1,1.05,4},{-3060.0,-372.8,1.29,4},{-3060.2,-362.6,1.48,4},{-3063.5,-326.9,1.27,4},{-3060.5,-317.7,1.13,4},{-3065.1,-308.1,1.21,4},
		{-3065.2,-293.2,1.36,4},{-3067.4,-272.1,1.05,4},{-3067.3,-242.7,0.99,4},{-3069.6,-228.5,1.4,4},{-3070.1,-223.8,1.21,4},{-3074.8,-215.1,0.88,4},{-3073.1,-202.7,0.99,4},{-3075.4,-198.9,0.88,4},
		{-3075.6,-187.5,1.01,4},{-3081.3,-147.6,0.93,4},{-3083.6,-123.2,1.45,4},{-3082.6,-114.4,1.25,4},{-3085.0,-89.0,1.47,4},{-3086.6,-61.1,1.25,4},{-3088.5,-55.7,1.12,4},{-3091.3,-30.9,1.12,4},
		{-3088.4,-13.9,0.97,4},{-3094.7,3.8,1.02,4},{-3094.8,38.5,0.87,4},{-3095.7,48.3,1.09,4},{-3098.3,77.2,0.83,4},{-3102.6,115.2,1.39,4},{-3103.0,126.1,1.16,4},{-3104.0,133.6,1.1,4},
		{-3105.0,158.1,1.43,4},{-3108.1,170.1,1.07,4},{-3107.2,181.9,1.22,4},{-3107.6,198.6,0.99,4},{-3108.3,208.4,1.24,4},{-3111.8,219.3,1.17,4},{-3113.8,251.0,1.21,4},{-3113.4,272.7,1.18,4},
		{-3107.2,282.4,0.81,4},{-3105.8,293.9,1.32,4},{-3107.5,311.4,1.13,4},{-3101.3,324.0,1.15,4},{-3099.8,332.1,1.21,4},{-3098.1,354.6,0.95,4},{-3094.6,364.5,1.02,4},{-3097.8,375.6,1.41,4},
		{-3095.5,383.5,1.24,4},{-3089.4,398.1,1.26,4},{-3089.9,409.6,1.06,4},{-3088.7,418.9,1.34,4},{-3090.5,424.4,1.02,4},{-3088.6,436.4,1.26,4},{-3082.1,440.7,1.17,4},{-3036.2,450.3,1.26,4},
		{-3031.2,453.8,1.21,4},{-3015.2,449.3,1.23,4},{-2999.3,451.5,0.87,4},{-2994.1,454.6,1.42,4},{-2979.4,456.4,1.42,4},{-2971.7,458.5,0.95,4},{-2959.4,459.4,1.44,4},{-2935.6,461.0,1.15,4},
		{-2914.1,460.7,0.87,4},{-2896.2,464.0,1.28,4},{-2870.6,462.8,1.08,4},{-2863.5,467.3,0.86,4},{-2855.7,465.4,1.17,4},{-2813.1,468.9,1.22,4},{-2799.5,468.9,1.32,4},{-2787.9,474.9,1.1,4},
		{-2765.7,472.7,0.87,4},{-2758.8,476.7,0.94,4},{-2744.7,476.3,0.86,4},{-2730.0,476.9,0.93,4},{-2720.0,480.1,1.04,4},{-2658.5,488.8,1.24,4},{-2647.5,488.4,0.96,4},{-2627.5,493.0,1.24,4},
		{-2619.9,492.5,1.1,4},{-2601.7,494.2,1.37,4},{-2582.1,498.3,1.34,4},{-2556.9,498.4,1.29,4},{-2547.3,500.6,1.31,4},{-2526.9,502.9,1.38,4},{-2520.2,504.9,1.47,4},{-2502.6,504.3,1.04,4},
		{-2514.4,497.0,1.28,4},{-2523.0,493.0,1.18,4},{-2553.3,496.6,1.35,4},{-2561.7,488.8,1.05,4},{-2580.0,479.8,1.42,4},{-2584.9,479.3,1.38,4},{-2602.8,468.5,1.16,4},{-2613.6,460.2,1.43,4},
		{-2626.7,457.5,0.88,4},{-2647.5,448.9,1.34,4},{-2654.3,445.6,0.82,4},{-2662.8,439.9,1.33,4},{-2669.8,438.6,1.18,4},{-2690.7,424.9,1.17,4},{-2705.8,420.6,0.84,4},{-2708.3,417.7,1.39,4},
		{-2719.8,412.7,0.9,4},{-2725.9,405.4,1.19,4},{-2734.1,395.6,1.47,4},{-2728.1,384.4,1.3,4},{-2717.6,366.7,1.32,4},{-2715.7,362.3,0.89,4},{-2733.7,314.3,1.29,4},{-2747.1,305.3,0.98,4},
		{-2754.8,296.4,0.8,4},{-2770.5,280.1,0.8,4},{-2780.5,265.3,1.29,4},{-2800.2,242.1,1.43,4},{-2812.6,224.5,1.27,4},{-2821.1,212.5,1.25,4},{-2828.5,196.2,0.91,4},{-2835.3,188.9,1.17,4},
		{-2846.1,167.1,1.05,4},{-2850.7,156.1,1.43,4},{-2877.2,148.6,1.25,4},{-2887.4,152.8,0.87,4},{-2921.3,160.9,1.31,4},{-2923.7,155.0,1.07,4},{-2928.0,146.8,1.46,4},{-2933.6,135.2,1.03,4},
		{-2934.4,124.3,0.92,4},{-2935.9,110.3,1.12,4},{-2937.8,102.1,1.42,4},{-2940.9,93.3,1.15,4},{-2947.2,84.4,1.05,4},{-2952.1,67.0,1.03,4},{-2959.0,56.4,1.31,4},{-2963.1,46.2,1.1,4},
		{-2964.4,32.8,1.31,4},{-2966.1,22.9,0.96,4},{-2969.4,10.2,1.36,4},{-2974.4,3.7,0.84,4},{-2981.3,-17.2,0.89,4},{-2983.5,-33.9,0.92,4},{-2972.7,-38.6,0.82,4},{-2947.7,-44.4,1.3,4},
		{-2941.9,-58.7,1.48,4},{-2947.9,-64.3,0.82,4},{-2963.0,-72.7,1.2,4},{-2974.6,-84.5,1.22,4},{-2976.3,-93.9,1.35,4},{-2986.5,-97.1,1.18,4},{-2994.9,-129.4,1.37,4},{-2997.5,-132.0,1.02,4},
		{-2996.2,-144.4,1.17,4},{-2998.5,-169.8,1.13,4},{-2994.0,-190.4,1.17,4},{-2993.4,-199.3,1.15,4},{-2991.5,-208.3,1.47,4},{-2977.0,-242.5,1.16,4},{-2983.6,-244.5,0.96,4},{-2994.0,-258.6,1.04,4},
		{-2999.7,-266.7,1.37,4},{-3017.0,-294.1,1.44,4},{-3002.8,-298.8,0.83,4},{-3008.9,-327.9,1.36,4},{-3008.0,-336.9,1.28,4},{-3008.1,-347.9,1.17,4},{-3005.1,-369.0,1.44,4},{-3000.6,-379.7,0.97,4},
		{-3004.5,-390.5,1.31,4},{-3000.7,-410.2,1.4,4},{-3009.1,-409.9,0.89,4},{-3009.1,-433.4,1.4,4},{-3005.5,-475.7,0.83,4},{-3004.2,-491.7,1.29,4},{-3008.7,-502.4,1.42,4},{-3006.3,-509.3,1.33,4},
		{-2371.3,-1731.5,0.93,4},{-2364.7,-1736.2,1.03,4},{-2370.5,-1745.4,1.49,4},{1722.9,-2420.9,1.11,4},{1752.0,-2414.3,1.16,4},{1757.9,-2413.0,1.11,4},{1756.8,-2400.2,1.42,4},{1754.6,-2380.0,0.97,4},
		{1753.2,-2374.2,0.86,4},{1748.7,-2361.1,1.02,4},{1751.7,-2358.2,1.18,4},{1747.8,-2350.9,1.3,4},{1755.5,-2343.9,1.35,4},{1764.9,-2341.9,0.85,4},{1775.1,-2340.0,1.21,4},{1797.6,-2333.3,1.43,4},
		{1810.8,-2326.2,1.39,4},{1821.8,-2319.0,1.21,4},{1828.7,-2318.3,0.91,4},{1845.3,-2308.7,0.87,4},{1852.4,-2308.4,0.88,4},{1865.5,-2326.3,0.98,4},{1868.8,-2334.1,1.37,4},{1875.2,-2340.2,1.04,4},
		{1879.7,-2354.6,0.97,4},{1898.0,-2351.5,1.45,4},{1909.6,-2349.5,1.37,4},{1924.0,-2338.4,1.21,4},{1933.1,-2332.6,1.21,4},{1949.3,-2327.4,1.44,4},{1956.2,-2323.4,1.5,4},{1963.7,-2318.8,1.48,4},
		{1989.5,-2303.9,0.92,4},{2026.5,-2281.5,1.15,4},{2037.4,-2277.5,1.09,4},{2055.7,-2270.2,1.35,4},{2061.4,-2272.2,1.16,4},{2095.0,-2259.8,1.1,4},{2133.9,-2236.5,0.86,4},{2146.2,-2231.6,0.88,4},
	},
}
]])
put(folder4, "ModuleScript", "LondonFillData3", [[
--!nocheck
-- Part 3 of the data in LondonFill. MADE BY tools/london_fill.py: don't edit by hand.
return {
	buildings = {
	},
	gardens = {
	},
	walls = {
	},
	trees = {
		{2151.0,-2228.4,1.47,4},{2159.0,-2223.1,1.14,4},{2173.8,-2213.8,0.89,4},{2187.0,-2208.3,1.3,4},{2188.2,-2190.8,1.31,4},{2196.3,-2185.7,0.95,4},{2200.7,-2162.7,1.29,4},{2212.9,-2159.7,1.37,4},
		{2221.3,-2156.2,1.19,4},{2230.7,-2153.1,1.1,4},{2238.1,-2155.2,0.82,4},{2250.3,-2150.9,1.45,4},{2257.9,-2144.6,1.44,4},{2303.2,-2105.5,1.34,4},{2306.8,-2094.7,1.17,4},{2313.2,-2088.0,1.43,4},
		{2334.6,-2092.3,1.06,4},{2343.9,-2097.0,1.18,4},{2360.3,-2085.1,1.21,4},{2359.9,-2072.6,1.42,4},{2363.7,-2081.0,1.01,4},{2368.7,-2089.6,0.84,4},{2388.0,-2091.7,0.95,4},{2394.6,-2081.5,1.17,4},
		{2403.5,-2075.9,0.96,4},{2423.6,-2064.2,1.22,4},{2430.6,-2055.6,0.87,4},{2436.8,-2052.5,1.02,4},{2446.4,-2048.2,0.97,4},{2455.5,-2043.7,1.32,4},{2466.7,-2035.9,0.86,4},{2494.2,-2019.1,1.45,4},
		{2502.2,-2012.4,1.31,4},{2511.8,-2006.6,1.48,4},{2526.9,-2002.5,0.85,4},{2546.2,-1989.4,1.39,4},{2555.7,-1983.6,1.16,4},{2589.7,-1963.0,0.98,4},{2595.2,-1955.7,0.98,4},{2582.6,-1943.3,1.16,4},
		{2581.9,-1934.8,0.9,4},{2570.1,-1921.2,1.25,4},{2563.3,-1909.8,1.05,4},{2559.2,-1903.7,0.86,4},{2575.8,-1891.2,1.47,4},{2597.4,-1876.4,0.9,4},{2630.7,-1850.8,1.41,4},{2637.6,-1861.6,0.96,4},
		{2642.9,-1862.3,1.47,4},{2653.2,-1877.4,1.02,4},{2660.9,-1882.6,0.9,4},{2670.8,-1894.6,1.08,4},{2681.4,-1898.1,0.9,4},{2696.0,-1879.9,0.98,4},{2708.2,-1872.7,1.1,4},{2711.5,-1861.5,1.04,4},
		{2726.8,-1837.2,1.42,4},{2714.0,-1812.4,1.43,4},{2700.2,-1804.1,1.44,4},{2693.4,-1797.8,1.1,4},{2686.1,-1791.3,1.09,4},{2695.5,-1774.1,1.1,4},{2705.6,-1764.4,1.2,4},{2716.8,-1753.6,0.99,4},
		{2727.0,-1759.6,0.94,4},{2733.5,-1770.4,0.88,4},{2740.9,-1769.9,1.45,4},{2755.9,-1783.2,0.87,4},{2782.4,-1773.1,1.15,4},{2786.2,-1766.8,1.26,4},{2791.8,-1762.2,1.26,4},{2795.8,-1756.9,1.32,4},
		{2808.4,-1743.1,1.27,4},{2810.4,-1736.2,1.03,4},{2818.4,-1722.0,1.38,4},{2819.5,-1712.5,1.08,4},{2826.1,-1710.4,1.43,4},{2830.7,-1702.5,1.22,4},{2844.1,-1680.2,1.14,4},{2848.1,-1670.4,1.47,4},
		{2856.1,-1666.9,1.43,4},{2867.9,-1640.3,1.19,4},{2879.1,-1628.2,1.47,4},{2890.1,-1600.6,1.45,4},{2909.2,-1565.9,1.32,4},{2919.4,-1546.0,1.29,4},{2922.1,-1532.8,1.38,4},{2914.8,-1530.1,1.43,4},
		{2910.3,-1508.4,1.5,4},{2921.3,-1498.9,1.36,4},{2929.0,-1492.7,1.01,4},{2934.0,-1481.2,1.26,4},{2956.2,-1458.1,1.37,4},{2957.3,-1448.1,1.45,4},{2963.7,-1436.8,0.97,4},{2974.0,-1430.5,1.49,4},
		{2992.4,-1434.1,1.43,4},{3026.4,-1437.9,0.91,4},{3039.3,-1425.1,1.1,4},{3036.7,-1409.6,0.93,4},{3027.0,-1404.9,1.43,4},{3016.7,-1397.4,1.09,4},{3019.4,-1393.4,1.19,4},{3016.6,-1379.4,1.32,4},
		{3023.0,-1384.5,1.22,4},{3034.4,-1391.6,1.46,4},{3043.8,-1388.6,1.49,4},{3052.4,-1384.4,0.86,4},{3063.6,-1376.1,1.24,4},{3070.3,-1364.4,1.24,4},{3098.2,-1330.4,1.0,4},{3103.4,-1321.8,0.96,4},
		{3111.7,-1313.0,1.06,4},{3115.3,-1304.8,1.48,4},{3121.1,-1299.7,1.47,4},{3114.8,-1297.3,1.3,4},{3144.3,-1259.3,0.96,4},{3155.1,-1252.2,1.2,4},{3162.8,-1246.1,1.19,4},{3167.9,-1238.5,1.19,4},
		{3171.0,-1233.7,1.23,4},{3183.7,-1220.1,1.1,4},{3187.9,-1211.5,1.34,4},{3198.1,-1194.5,1.33,4},{3207.4,-1190.4,1.08,4},{3219.7,-1177.4,1.1,4},{3233.1,-1153.6,1.21,4},{3239.7,-1143.1,0.82,4},
		{3247.1,-1125.7,1.28,4},{3255.7,-1113.0,1.43,4},{3259.6,-1100.9,1.02,4},{3274.1,-1070.1,1.45,4},{3286.3,-1050.4,0.97,4},{3282.5,-1041.1,1.25,4},{3271.8,-1037.4,0.82,4},{3262.7,-1031.5,1.29,4},
		{3254.0,-1027.9,1.4,4},{3248.0,-1025.2,1.45,4},{3240.6,-1019.4,1.27,4},{3235.4,-1000.0,0.98,4},{3246.6,-972.0,1.13,4},{3253.4,-973.8,1.33,4},{3263.6,-978.1,1.15,4},{3277.5,-984.2,1.29,4},
		{3292.1,-986.7,1.37,4},{3311.4,-983.4,1.02,4},{3315.9,-966.6,1.31,4},{3325.3,-956.8,0.95,4},{3333.4,-931.3,0.85,4},{3334.1,-926.0,1.26,4},{3342.1,-886.5,0.99,4},{3344.6,-875.3,0.95,4},
		{3346.2,-865.2,0.89,4},{3351.4,-859.8,1.44,4},{3347.1,-855.6,0.91,4},{3345.0,-840.7,1.4,4},{3350.8,-830.8,1.16,4},{3353.0,-824.0,0.91,4},{3362.6,-807.1,1.5,4},{3368.5,-795.3,1.35,4},
		{3369.1,-788.3,1.25,4},{3367.0,-782.6,1.42,4},{3365.9,-750.5,1.26,4},{3362.6,-745.2,1.47,4},{3349.9,-732.6,0.92,4},{3356.1,-724.0,0.91,4},{3370.2,-704.7,0.83,4},{3379.0,-668.4,0.88,4},
		{3378.8,-634.0,0.89,4},{3378.3,-619.1,1.05,4},{3380.8,-612.3,0.97,4},{3400.3,-605.9,0.82,4},{3413.9,-589.5,0.89,4},{3407.6,-581.8,1.09,4},{3425.2,-582.5,1.19,4},{3434.5,-575.3,1.42,4},
		{3450.4,-518.1,1.32,4},{3454.7,-507.6,1.13,4},{3458.3,-499.6,1.18,4},{3457.9,-489.3,0.86,4},{3472.7,-456.9,1.33,4},{3481.1,-444.8,0.82,4},{3489.9,-436.3,1.31,4},{3491.8,-418.4,1.43,4},
		{3499.2,-409.6,1.34,4},{3502.4,-399.0,0.82,4},{3501.4,-392.7,1.09,4},{3504.9,-385.3,0.85,4},{3511.4,-368.1,1.02,4},{3516.9,-361.1,1.46,4},{3513.1,-334.2,1.14,4},{3516.7,-326.5,0.93,4},
		{3520.4,-319.2,1.01,4},{3526.7,-300.4,1.47,4},{3526.3,-295.9,1.34,4},{3531.6,-279.7,1.07,4},{3538.1,-262.0,0.98,4},{3541.9,-257.8,1.2,4},{3549.3,-247.7,0.88,4},{3556.5,-221.2,1.47,4},
		{3551.9,-213.9,0.87,4},{3550.8,-193.7,0.94,4},{3545.7,-183.4,0.93,4},{3535.6,-188.2,1.05,4},{3505.7,-186.9,1.17,4},{3505.8,-181.4,0.84,4},{3505.7,-170.2,1.46,4},{3518.1,-147.0,1.12,4},
		{3523.3,-152.0,1.11,4},{3541.8,-151.1,1.33,4},{3554.6,-146.8,1.12,4},{3557.7,-140.2,0.83,4},{3555.6,-109.5,1.15,4},{3557.7,-104.1,1.33,4},{3559.0,-83.5,1.46,4},{3560.7,-73.1,1.2,4},
		{3562.2,-51.5,1.12,4},{3559.4,-44.6,1.15,4},{3559.5,-32.8,1.04,4},{3560.2,-24.0,1.05,4},{3559.1,1.3,1.15,4},{3560.8,11.4,1.17,4},{3562.9,17.5,1.08,4},{3562.3,30.1,1.0,4},
		{3564.4,46.3,1.0,4},{3562.9,64.6,1.03,4},{3558.9,72.7,0.82,4},{3560.8,102.1,0.86,4},{3559.0,111.4,1.46,4},{3553.4,143.5,0.9,4},{3544.9,148.8,1.2,4},{3538.3,159.2,1.31,4},
		{3531.4,164.1,0.84,4},{3520.2,169.4,1.27,4},{3529.0,176.1,1.11,4},{3529.2,186.3,1.29,4},{3533.1,192.1,1.22,4},{3538.4,204.7,1.35,4},{3539.6,213.3,1.31,4},{3541.3,243.3,0.82,4},
		{3539.2,256.8,0.82,4},{3529.7,274.6,1.28,4},{3527.3,283.2,1.2,4},{3502.9,311.7,0.95,4},{3492.1,322.3,1.26,4},{3480.1,335.4,0.96,4},{3463.5,339.1,1.03,4},{3451.7,347.1,1.24,4},
		{3442.6,345.2,0.85,4},{3432.0,350.5,1.35,4},{3404.1,349.5,1.16,4},{3395.8,350.0,1.27,4},{3389.9,367.4,0.95,4},{3385.9,374.3,1.47,4},{3383.6,382.2,1.4,4},{3376.5,390.9,1.11,4},
		{3366.9,406.0,1.41,4},{3357.9,401.5,1.07,4},{3345.1,370.1,0.82,4},{3344.3,367.2,1.44,4},{3331.1,357.8,1.39,4},{3326.1,358.7,0.88,4},{3329.7,367.6,1.43,4},{3336.5,385.6,1.16,4},
		{3333.3,389.7,1.46,4},{3301.7,402.5,1.36,4},{3290.9,404.6,0.88,4},{3278.7,411.8,1.0,4},{3261.4,424.2,1.1,4},{3209.7,444.9,1.39,4},{3197.7,446.4,1.15,4},{3190.0,448.4,1.43,4},
		{3135.4,465.5,1.3,4},{3122.5,474.0,0.93,4},{3110.3,479.5,1.03,4},{3076.6,486.3,0.96,4},{3066.4,482.7,1.5,4},{3060.9,487.3,1.07,4},{3054.4,487.8,0.99,4},{3044.2,492.9,1.45,4},
		{3037.8,493.8,1.49,4},{3014.4,499.1,1.45,4},{3007.3,500.8,0.93,4},{2997.2,502.3,1.03,4},{2987.4,505.1,1.44,4},{2977.4,504.9,1.31,4},{2956.0,509.5,1.43,4},{2950.2,513.7,0.95,4},
		{2938.2,513.5,1.36,4},{2931.0,516.8,0.91,4},{2904.4,516.2,1.33,4},{2895.9,521.0,1.05,4},{2910.3,555.6,0.8,4},{2930.9,571.3,0.9,4},{2940.8,585.1,0.95,4},{2946.8,589.1,1.07,4},
		{2951.4,604.1,0.93,4},{2961.6,620.0,1.48,4},{2968.6,625.4,1.21,4},{2978.6,627.3,1.48,4},{2984.9,640.0,1.09,4},{2995.6,651.1,1.09,4},{3011.2,668.2,0.84,4},{3018.1,679.9,1.02,4},
		{3021.8,685.2,1.27,4},{3038.3,704.6,1.12,4},{3034.8,713.9,0.86,4},{3023.6,719.4,0.99,4},{3016.3,724.8,0.98,4},{3006.7,735.0,1.16,4},{2986.5,748.6,1.14,4},{3003.1,788.6,0.84,4},
		{3011.0,779.7,1.46,4},{3022.6,771.6,0.98,4},{3027.8,763.1,1.21,4},{3033.2,753.7,1.22,4},{3046.2,742.1,1.44,4},{3058.9,746.4,1.39,4},{3096.4,774.7,0.97,4},{3128.5,798.4,0.88,4},
		{3139.4,808.1,1.02,4},{3149.4,811.3,1.17,4},{3164.1,821.4,1.42,4},{3191.4,832.9,1.1,4},{3197.4,844.0,1.43,4},{3217.5,856.4,0.96,4},{3229.3,871.9,1.32,4},{3258.6,895.1,1.11,4},
		{3261.9,905.2,1.27,4},{3264.4,909.4,1.45,4},{3287.0,937.9,1.2,4},{3293.2,953.6,1.14,4},{3297.5,968.3,1.04,4},{3306.6,974.9,1.1,4},{3314.2,1002.5,0.93,4},{3324.9,998.1,0.98,4},
		{3328.1,993.2,0.9,4},{3328.6,981.6,0.84,4},{3339.2,959.4,0.82,4},{3345.2,945.4,1.48,4},{3352.5,924.8,1.49,4},{3358.2,920.4,1.41,4},{3363.4,907.6,1.06,4},{3365.5,900.0,1.02,4},
		{3370.9,882.9,1.03,4},{3375.5,871.8,0.83,4},{3383.6,866.8,1.45,4},{3386.8,853.1,1.36,4},{3388.3,843.8,1.29,4},{3394.9,833.3,1.1,4},{3398.9,822.1,1.33,4},{3405.3,810.1,1.09,4},
		{3406.6,806.8,0.95,4},{3411.4,793.4,0.98,4},{3414.7,787.4,1.15,4},{3427.9,764.2,1.2,4},{3435.3,745.7,0.87,4},{3440.2,738.9,1.34,4},{3444.4,729.6,0.92,4},{3449.9,715.7,1.42,4},
		{3458.4,706.1,1.44,4},{3461.9,701.6,1.4,4},{3486.0,668.6,1.17,4},{3493.3,660.0,1.48,4},{3501.0,649.1,0.87,4},{3511.5,643.9,0.89,4},{3530.9,616.0,1.09,4},{3542.8,608.3,0.82,4},
		{3551.0,599.8,1.44,4},{3557.8,599.1,1.03,4},{3571.5,581.4,1.12,4},{3579.1,576.4,1.2,4},{3589.1,565.2,0.97,4},{3602.0,557.4,1.11,4},{3611.4,553.5,1.43,4},{3645.5,534.3,1.3,4},
		{3657.0,523.3,1.49,4},{3662.2,522.0,1.16,4},{3671.5,516.1,1.33,4},{3707.0,500.7,1.18,4},{3728.3,494.7,1.03,4},{3750.7,486.2,1.38,4},{3750.1,479.9,0.98,4},{3750.5,470.2,1.46,4},
		{3753.9,426.8,0.82,4},{3750.8,408.7,0.93,4},{3754.3,399.3,1.23,4},{3755.5,393.2,0.97,4},{3753.3,384.4,1.13,4},{3752.7,366.9,0.92,4},{3750.6,356.8,1.15,4},{3753.8,344.4,1.21,4},
		{3743.1,310.5,1.09,4},{3746.0,299.5,1.12,4},{3741.0,279.2,0.82,4},{3733.0,266.4,1.29,4},{3734.6,258.9,0.92,4},{3730.1,242.8,1.17,4},{3726.9,231.7,1.42,4},{3725.5,216.0,1.11,4},
		{3721.6,207.8,0.82,4},{3717.6,194.2,1.0,4},{3706.6,140.3,1.0,4},{3700.2,108.8,0.8,4},{3695.4,95.5,1.3,4},{3688.9,78.8,1.37,4},{3686.8,64.0,0.93,4},{3686.2,52.8,1.13,4},
		{3684.9,42.2,1.16,4},{3675.0,13.7,1.22,4},{3672.2,-16.3,1.47,4},{3662.2,-39.7,1.01,4},{3661.7,-57.4,0.97,4},{3655.0,-70.6,1.06,4},{3655.7,-79.9,1.06,4},{3652.6,-95.7,0.86,4},
		{3646.7,-105.4,0.83,4},{3644.8,-117.2,1.04,4},{3643.3,-129.4,1.34,4},{3638.5,-150.4,1.16,4},{3636.4,-172.1,1.02,4},{3631.1,-175.4,1.42,4},{3628.6,-198.0,1.11,4},{3623.7,-209.6,1.41,4},
		{3624.7,-218.0,0.9,4},{3612.7,-249.0,1.02,4},{3613.6,-261.9,1.22,4},{3607.9,-291.9,0.86,4},{3601.1,-312.0,0.82,4},{3599.7,-318.6,1.09,4},{3595.6,-328.4,1.29,4},{3596.9,-337.6,1.24,4},
		{3594.1,-348.6,0.96,4},{3587.6,-360.6,0.83,4},{3585.1,-379.7,1.39,4},{3576.7,-415.4,1.05,4},{3571.2,-430.0,1.22,4},{3574.7,-434.4,1.01,4},{3571.5,-444.7,1.34,4},{3569.4,-452.5,1.09,4},
		{3568.5,-459.9,1.23,4},{3557.5,-491.0,1.45,4},{3552.5,-521.4,1.44,4},{3546.9,-531.1,1.02,4},{3546.6,-544.1,1.27,4},{3545.0,-552.5,1.01,4},{3543.0,-562.7,1.08,4},{3538.9,-572.1,0.97,4},
		{3537.7,-587.1,1.03,4},{3530.3,-609.3,1.48,4},{3521.9,-649.8,1.41,4},{3503.1,-699.8,0.93,4},{3499.2,-714.4,1.46,4},{3487.9,-729.3,1.09,4},{3484.9,-735.9,1.09,4},{3482.8,-743.4,1.22,4},
		{3477.5,-753.3,0.94,4},{3472.6,-758.2,1.29,4},{3472.3,-769.5,1.25,4},{3469.1,-776.7,1.4,4},{3450.0,-809.2,1.33,4},{3444.5,-823.2,0.89,4},{3436.7,-831.6,0.95,4},{3434.3,-841.9,1.14,4},
		{3424.0,-859.6,0.9,4},{3423.9,-872.7,0.85,4},{3416.1,-877.7,0.96,4},{3416.2,-888.1,1.36,4},{3408.4,-895.3,0.95,4},{3402.4,-913.2,0.96,4},{3396.0,-918.5,1.14,4},{3389.5,-932.3,1.3,4},
		{3384.7,-941.2,1.04,4},{3371.8,-975.2,1.49,4},{3364.3,-990.6,1.37,4},{3347.1,-1020.6,1.0,4},{3345.7,-1030.6,1.46,4},{3340.1,-1040.8,0.89,4},{3327.5,-1059.3,1.08,4},{3320.0,-1076.3,1.1,4},
		{3316.0,-1082.7,0.92,4},{3312.6,-1092.1,1.37,4},{3307.4,-1103.6,1.05,4},{3305.2,-1112.8,1.42,4},{3303.7,-1114.8,1.21,4},{3296.6,-1123.5,1.15,4},{3291.3,-1137.9,1.26,4},{3288.5,-1149.7,1.22,4},
		{3281.5,-1157.5,0.82,4},{3263.1,-1189.5,0.86,4},{3252.3,-1220.0,1.4,4},{3245.9,-1226.2,0.81,4},{3241.8,-1239.1,0.93,4},{3223.5,-1272.8,1.05,4},{3211.9,-1291.1,1.28,4},{3209.2,-1310.6,1.4,4},
		{3200.8,-1317.9,1.17,4},{3199.1,-1326.5,1.42,4},{3194.2,-1334.1,1.37,4},{3176.7,-1370.2,1.25,4},{3175.2,-1379.5,1.46,4},{3165.3,-1389.4,1.23,4},{3163.1,-1395.3,1.06,4},{3155.9,-1418.1,1.48,4},
		{3148.1,-1432.7,1.27,4},{3145.7,-1441.5,1.47,4},{3136.8,-1446.0,0.9,4},{3127.4,-1479.1,1.2,4},{3118.9,-1485.0,1.3,4},{3105.0,-1515.3,0.98,4},{3101.4,-1526.1,1.0,4},{3082.4,-1558.4,0.95,4},
		{3071.7,-1574.6,1.07,4},{3061.4,-1587.4,0.88,4},{3049.8,-1598.7,0.83,4},{3036.8,-1611.7,1.12,4},{3014.4,-1633.0,0.85,4},{3009.4,-1638.5,1.18,4},{3001.2,-1648.2,1.26,4},{2993.2,-1654.6,1.34,4},
		{2987.2,-1660.1,1.13,4},{2947.1,-1699.2,1.39,4},{2933.1,-1716.8,1.28,4},{2927.4,-1724.6,0.83,4},{2913.0,-1731.2,0.81,4},{2909.9,-1739.9,1.11,4},{2893.5,-1748.8,1.33,4},{2888.9,-1761.0,1.06,4},
		{2875.7,-1767.7,1.03,4},{2870.1,-1775.0,1.09,4},{2864.0,-1779.7,1.11,4},{2859.2,-1784.1,1.16,4},{2849.3,-1793.8,0.88,4},{2817.6,-1825.1,0.95,4},{2811.7,-1830.7,1.26,4},{2794.2,-1845.2,1.49,4},
		{2785.2,-1853.1,1.14,4},{2771.2,-1867.8,1.24,4},{2762.9,-1879.3,1.33,4},{2745.4,-1890.2,1.19,4},{2742.0,-1898.2,1.03,4},{2732.4,-1904.4,1.41,4},{2727.1,-1912.9,1.39,4},{2695.8,-1945.0,1.35,4},
		{2679.0,-1958.7,0.97,4},{2671.4,-1964.6,1.12,4},{2661.1,-1971.1,1.03,4},{2660.7,-1979.2,1.18,4},{2649.2,-1984.2,1.33,4},{2630.4,-2002.3,0.98,4},{2627.0,-2009.0,0.99,4},{2608.4,-2022.3,0.85,4},
		{2605.2,-2028.5,1.36,4},{2576.7,-2055.2,1.19,4},{2573.6,-2063.0,1.25,4},{2565.1,-2070.3,1.09,4},{2541.3,-2086.0,1.28,4},{2534.9,-2096.8,0.92,4},{2526.1,-2103.2,1.0,4},{2517.2,-2110.9,1.48,4},
		{2508.0,-2119.3,1.17,4},{2495.2,-2134.9,1.24,4},{2475.7,-2149.9,0.89,4},{2452.3,-2176.5,0.83,4},{2442.3,-2179.5,1.43,4},{2437.7,-2191.0,1.0,4},{2423.4,-2202.6,1.14,4},{2410.5,-2215.4,1.06,4},
		{2402.6,-2221.1,1.09,4},{2393.6,-2231.7,0.81,4},{2372.2,-2247.9,0.95,4},{2370.4,-2252.5,1.3,4},{2358.9,-2261.1,1.36,4},{2313.4,-2278.4,1.03,4},{2308.8,-2279.3,0.94,4},{2297.9,-2288.2,1.49,4},
		{2288.2,-2287.3,0.82,4},{2273.2,-2290.1,1.41,4},{2268.6,-2295.4,1.22,4},{2239.9,-2298.3,0.98,4},{2219.0,-2305.9,0.9,4},{2171.5,-2317.5,1.3,4},{2145.6,-2323.5,1.19,4},{2125.6,-2326.5,0.9,4},
		{2117.1,-2333.3,1.48,4},{2101.0,-2333.6,0.86,4},{2093.5,-2335.9,1.11,4},{2084.0,-2335.4,1.03,4},{2074.0,-2338.5,1.15,4},{2048.0,-2344.7,0.92,4},{2041.9,-2348.0,1.15,4},{2024.9,-2351.4,1.23,4},
		{2010.1,-2355.3,1.1,4},{2004.9,-2356.7,1.17,4},{1983.0,-2361.7,1.42,4},{1973.0,-2366.2,1.02,4},{1952.2,-2371.0,1.2,4},{1940.2,-2374.0,0.88,4},{1932.9,-2376.0,0.95,4},{1923.6,-2377.0,1.0,4},
		{1895.0,-2383.2,1.07,4},{1886.4,-2386.5,1.24,4},{1871.1,-2391.0,1.18,4},{1861.3,-2387.8,1.18,4},{1853.2,-2394.8,1.29,4},{1833.6,-2397.6,1.28,4},{1771.9,-2410.6,1.45,4},{1763.6,-2411.2,1.04,4},
		{1754.1,-2413.9,1.16,4},{1743.3,-2416.8,0.86,4},{1729.0,-2418.5,1.24,4},{3510.8,139.7,1.46,4},{3502.3,144.9,1.06,4},{3508.9,147.4,1.12,4},{3313.1,1027.0,1.15,4},{3303.6,1033.8,1.44,4},
		{3306.6,1033.9,1.36,4},{3259.4,1146.9,1.34,4},{3254.8,1156.9,1.24,4},{3257.0,1180.8,1.49,4},{3263.8,1197.6,1.31,4},{3265.8,1188.4,1.39,4},{3270.0,1178.6,0.86,4},{3274.2,1166.4,0.82,4},
		{3248.6,1269.9,1.36,4},{3241.0,1279.4,0.92,4},{3251.7,1270.4,0.97,4},{2168.7,-2169.3,0.88,4},{2167.4,-2160.2,1.48,4},{2163.3,-2156.0,1.25,4},{2166.9,-2154.9,1.31,4},{2170.8,-2161.3,0.98,4},
		{1368.9,-2374.3,1.08,4},{1377.8,-2376.2,1.47,4},{-2873.2,-890.9,1.46,4},{-2858.2,-885.2,1.23,4},{-2871.5,-894.8,1.42,4},{-2285.2,539.9,1.47,2},{-2344.7,527.1,1.96,2},{-2330.2,530.2,1.49,1},
		{-2285.9,542.6,1.38,4},{-2300.7,531.4,1.27,4},{-2328.9,522.5,1.06,4},{-2354.9,530.0,1.06,4},{-2345.8,530.2,0.88,4},{-2332.1,536.0,1.13,4},{-2309.9,538.6,1.21,4},{-2286.5,542.1,1.01,4},
		{-2182.4,555.3,1.45,2},{-2194.7,557.3,1.32,4},{-2184.3,558.2,1.49,4},{-2169.8,557.9,0.96,4},{-2158.1,556.6,0.94,4},{-2159.9,561.4,0.94,4},{-2950.3,-281.7,1.2,1},{-2956.7,-286.0,1.45,4},
		{-2951.8,-275.0,1.32,4},{-2947.5,-280.5,0.92,4},{-2792.5,-1084.9,1.99,2},{-2799.9,-1091.6,0.8,4},{-2795.3,-1081.3,0.88,4},{-2792.3,-1089.2,1.21,4},{-1966.1,-2117.2,1.41,1},{-1971.1,-2108.9,0.88,4},
		{-1965.0,-2104.0,1.28,4},{-1966.5,-2118.5,1.34,4},{-1764.8,-2189.4,1.71,2},{-1767.4,-2188.6,1.1,4},{-1759.5,-2195.5,1.03,4},{-790.1,-2343.4,1.24,1},{-795.4,-2342.3,0.93,4},{197.0,-2287.9,1.38,1},
		{374.4,-2257.7,2.0,2},{379.8,-2263.7,1.23,4},{377.8,-2261.0,1.22,4},{2340.1,-2040.2,1.65,2},{2344.0,-2044.8,1.25,4},{2337.4,-2047.9,0.99,4},{2885.5,-1517.3,1.84,2},{2875.0,-1517.9,0.97,4},
		{2887.0,-1515.0,1.09,4},{2888.3,-1528.8,0.88,4},{2979.6,-1359.5,1.12,1},{2985.1,-1355.2,1.43,4},{2989.9,-1360.6,1.1,4},{2975.8,-1361.3,1.36,4},{3319.3,-756.3,1.86,2},{3322.5,-749.5,0.88,4},
		{3326.9,-756.1,0.85,4},{3367.3,-567.3,1.11,1},{3367.7,-566.3,1.31,4},{3364.5,-567.4,1.03,4},{2774.9,505.9,1.85,2},{2815.9,546.4,1.8,2},{2718.3,481.0,1.02,4},{2731.5,483.9,1.28,4},
		{2743.3,494.7,1.22,4},{2733.6,480.7,1.33,4},{2723.5,479.9,0.88,4},{2788.4,522.1,1.44,4},{2780.5,508.2,1.16,4},{2776.0,504.6,0.89,4},{2767.8,508.0,1.08,4},{2821.2,548.0,1.01,4},
		{2825.9,545.7,0.94,4},{2833.8,536.9,1.43,4},{2844.8,532.2,1.47,4},{2837.5,533.0,1.03,4},{2819.6,534.4,1.47,4},{2808.8,537.7,1.29,4},{3057.1,1667.5,0.89,4},{3066.1,1661.7,1.38,4},
		{3044.4,1674.4,0.86,4},{3224.4,1373.0,0.82,4},{3229.9,1358.6,1.16,4},{3233.4,1343.4,1.14,4},{3227.4,1355.4,0.9,4},{-1952.3,862.1,0.78,1},{-2133.9,860.1,0.61,1},{-2215.0,858.1,0.7,1},
		{-2435.8,837.3,0.94,1},{-2493.8,836.5,0.91,1},{-2529.0,799.7,0.8,1},{-2779.3,1448.1,0.95,1},{-2488.0,1763.6,0.73,1},{-2463.2,1813.5,0.63,1},{-2222.5,1982.5,0.89,1},{-1956.4,2149.0,0.85,1},
		{-1743.8,2226.9,1.0,1},{-762.6,2497.7,0.94,1},{-498.5,2520.8,0.69,1},{-458.8,2528.1,0.9,1},{-42.4,2525.0,0.76,1},{128.6,2502.5,0.9,1},{227.9,2505.7,0.61,1},{329.1,2500.6,0.76,1},
		{433.5,2491.9,0.73,1},{503.4,2475.1,0.92,1},{1457.6,2430.1,0.84,1},{1576.7,2449.8,0.97,1},{1969.6,2463.3,0.94,1},{2613.7,2404.1,0.66,1},{2654.5,2386.5,0.76,1},{3024.9,2256.7,0.73,1},
		{2955.7,1954.0,0.9,1},{2907.4,1966.4,0.88,1},{2834.8,1943.4,0.72,1},{2571.0,1877.5,0.83,1},{2404.5,1578.1,0.93,1},{2380.2,1513.9,0.61,1},{2336.4,1425.2,0.99,1},{2116.8,1032.9,0.7,1},
		{2032.4,916.0,0.88,1},{-2825.4,1270.3,1.07,1},{-2915.9,1193.5,1.55,1},{-2935.5,767.2,1.47,2},{-2721.5,813.0,1.84,2},{-2886.2,1175.7,1.44,1},{-2815.1,1333.5,1.34,1},{-2772.0,885.3,1.62,2},
		{-2976.7,859.4,1.74,2},{-2831.0,1094.2,1.81,2},{-2954.5,943.5,1.33,2},{-2829.6,1022.6,1.94,2},{-2884.4,1106.6,1.7,2},{-2834.3,863.0,1.54,2},{-2886.7,1235.9,1.05,1},{-2946.1,725.3,1.89,2},
		{-2858.2,1087.9,1.53,1},{-2885.2,1055.5,1.47,2},{-2828.8,1300.2,1.64,2},{-2997.2,785.7,1.59,2},{-2987.8,920.1,1.5,2},{-2182.1,824.8,1.09,1},{-2846.1,924.6,1.9,2},{-2813.7,802.3,1.65,2},
		{-2819.1,1204.3,1.45,2},{-2976.5,939.2,1.06,1},{-2820.9,1009.6,1.58,1},{-2493.0,812.0,1.9,2},{-2568.7,816.0,1.96,2},{-2954.1,1070.4,1.68,2},{-2270.2,836.4,1.35,1},{-2886.7,831.6,1.37,1},
		{-2951.0,871.0,1.75,2},{-2990.7,809.6,1.27,2},{-2375.8,795.2,1.86,2},{-2932.7,721.1,1.44,1},{-2986.7,771.0,1.3,1},{-2870.7,1165.7,1.51,2},{-2974.1,996.3,1.43,2},{-2901.1,1100.2,1.36,1},
		{-2757.9,754.4,1.55,2},{-2996.6,756.0,1.39,1},{-2838.0,775.3,1.77,2},{-2890.8,1040.8,1.05,1},{-2794.1,790.5,1.97,2},{-2798.1,1056.0,1.7,2},{-2875.5,823.0,1.58,2},{-2740.1,740.0,1.5,1},
		{-2858.7,1112.7,1.26,1},{-2866.6,879.6,1.79,2},{-2924.9,991.1,1.96,2},{-2947.9,1142.0,1.38,1},{-2619.3,760.3,1.23,1},{-2874.2,1266.2,1.27,1},{-2846.1,1231.5,1.03,1},{-2897.0,1008.7,1.37,2},
		{-2909.0,776.6,1.58,2},{-2863.5,795.6,1.42,2},{-2898.0,897.6,1.81,2},{-2871.6,761.5,1.71,2},{-2752.1,847.7,1.12,1},{-2906.9,994.3,1.06,1},{-2847.9,983.3,1.44,1},{-2855.0,1006.9,1.08,1},
		{-2590.4,778.5,1.32,1},{-2957.4,852.2,1.83,2},{-2161.7,828.6,1.62,2},{-2993.5,842.4,1.34,1},{-2781.2,1397.5,1.02,1},{-2808.8,1081.6,1.6,2},{-2934.8,1094.3,1.15,1},{-2828.5,944.9,1.63,2},
		{-3011.0,916.6,1.04,1},{-2740.6,824.4,1.67,2},{-2830.3,1056.5,1.85,2},{-2963.5,1130.5,1.75,2},{-2866.2,975.1,1.42,1},{-2778.2,942.8,1.84,2},{-2933.2,1180.0,1.83,2},{-2726.6,755.1,1.84,2},
		{-2795.3,921.4,1.43,1},{-2396.1,790.3,1.83,2},{-2968.6,1104.3,1.39,2},{-3020.4,747.6,1.29,2},{-2654.0,776.5,1.41,2},{-2810.6,1036.0,1.28,2},{-2763.7,836.8,1.34,2},{-2866.8,741.8,1.54,2},
		{-2941.5,1036.8,1.58,1},{-2877.9,1283.0,1.43,1},{-2952.4,1022.9,1.29,2},{-2283.5,823.5,1.54,1},{-2918.2,1078.3,1.46,2},{-2702.3,752.4,1.27,1},{-2944.7,739.6,1.07,1},{-2894.3,1270.5,1.46,1},
		{-2448.5,810.7,1.49,2},{-2866.2,1150.9,1.38,2},{-2844.0,1034.3,1.36,1},{-2942.6,1193.9,1.83,2},{-2934.6,1009.3,1.69,2},{-2860.2,1261.3,1.91,2},{-2513.9,777.0,1.75,2},{-2983.5,1042.5,1.06,1},
		{-2722.2,769.1,1.39,2},{-2976.8,890.6,1.46,2},{-2953.0,904.7,1.58,1},{-2957.8,1094.0,1.67,2},{-2846.1,897.6,1.4,1},{-2956.7,1040.8,1.46,2},{-2542.0,788.3,1.0,1},{-2765.7,864.7,1.31,2},
		{-2818.2,1170.5,1.01,1},{-2877.0,1091.5,1.75,2},{-2898.0,1153.5,1.08,1},{-2591.5,757.9,1.46,2},{-2907.9,939.5,1.25,1},{-2845.0,1165.3,1.71,2},{-2221.6,811.1,1.9,2},{-2926.0,930.0,1.69,2},
		{-2087.5,830.7,1.54,2},{-2834.2,969.4,1.36,1},{-2812.7,1134.1,1.52,1},{-2912.9,1173.1,1.9,2},{-2899.2,1084.8,1.44,2},{-2898.4,1192.6,1.58,2},{-2947.2,1105.8,1.29,1},{-2812.4,971.3,1.47,2},
		{-2946.7,992.6,1.37,2},{-2871.5,1207.8,1.54,1},{-2472.5,779.9,1.33,2},{-2998.5,889.7,1.37,1},{-2967.0,837.2,1.32,1},{-2928.8,784.7,1.33,1},{-2953.2,809.1,1.16,1},{-2843.1,1205.9,1.15,1},
		{-2935.1,945.9,1.96,2},{-2808.7,887.8,1.07,1},{-2934.1,1164.7,1.73,2},{-2940.7,887.8,1.96,2},{-2963.6,772.4,1.05,1},{-2793.4,1163.1,1.73,2},{-2745.0,993.3,1.31,1},{-2796.5,865.8,1.53,2},
		{-2771.0,760.3,1.6,2},{-2985.5,1026.9,1.1,1},{-2829.7,983.8,1.29,2},{-2705.1,793.5,1.72,2},{-2809.2,1307.7,1.29,2},{-2938.7,805.0,1.63,2},{-2845.2,1068.4,1.02,1},{-2977.0,907.7,1.17,1},
		{-2461.5,795.7,1.34,2},{-2854.2,828.8,1.84,2},{-2814.4,933.5,1.03,1},{-2863.0,926.9,1.92,2},{-2862.8,1224.6,1.69,2},{-2882.2,1021.2,1.09,1},{-2903.4,1253.4,1.5,1},{-2923.9,1103.7,1.63,2},
		{-2818.6,870.3,1.58,2},{-2240.3,824.4,1.36,2},{-2356.4,797.8,1.55,1},{-2968.3,739.3,1.29,1},{-2815.4,1395.8,1.05,1},{-2890.0,987.5,1.97,2},{-2951.8,929.6,1.01,1},{-2930.5,876.4,1.68,2},
		{-2719.4,791.2,1.04,1},{-2849.4,945.2,1.29,1},{-3001.0,935.1,1.06,1},{-2969.9,957.6,1.82,2},{-2872.5,855.3,1.48,2},{-2938.8,1128.1,1.71,2},{-2793.8,774.1,1.26,2},{-2857.1,778.1,1.91,2},
		{-2884.3,754.4,1.34,2},{-2980.1,973.3,1.81,2},{-2265.9,894.8,1.52,2},{-2844.2,1294.6,1.5,2},{-2981.0,717.9,1.37,1},{-2955.8,1159.5,1.56,1},{-2280.3,876.1,1.05,1},{-2319.8,797.0,1.73,2},
		{-2806.6,950.1,1.08,1},{-2988.4,1061.3,1.59,2},{-2992.9,993.0,1.57,1},{-2829.5,741.4,1.53,2},{-2751.9,777.6,1.25,1},{-2962.1,753.8,1.32,1},{-2357.3,819.5,1.79,2},{-2966.7,1056.0,1.66,2},
		{-2876.3,868.8,1.7,2},{-3013.2,795.5,1.96,2},{-2661.5,751.4,1.36,1},{-2848.5,1271.5,1.36,1},{-2879.6,796.1,1.79,2},{-2818.2,760.5,1.92,2},{-2831.6,1237.2,1.97,2},{-2814.4,1156.1,1.8,2},
		{-2883.8,960.5,1.89,2},{-2852.3,1343.0,1.36,2},{-2811.1,1225.3,1.39,2},{-2868.6,1057.7,1.42,2},{-2994.0,1015.3,1.62,2},{-2828.5,845.1,1.5,1},{-2971.6,1015.0,1.67,2},{-2828.3,886.8,1.52,2},
		{-2813.9,907.6,1.49,2},{-2311.1,823.6,1.2,1},{-2908.1,917.5,1.13,1},{-2811.6,1185.3,1.43,2},{-2849.1,1138.5,1.07,1},{-2894.4,810.6,1.74,2},{-2673.0,783.7,1.59,1},{-2808.0,844.5,1.27,1},
		{-2813.6,1278.5,1.92,2},{-2920.7,1208.6,1.94,2},{-2799.9,1402.9,1.42,2},{-2571.3,774.3,2.0,2},{-3036.2,736.2,1.26,1},{-3023.1,821.3,1.45,2},{-3002.1,951.4,1.58,2},{-2831.6,917.9,1.06,1},
		{-2902.1,723.3,1.07,1},{-2471.9,805.1,1.38,2},{-2903.8,970.7,1.16,1},{-2861.6,1324.0,1.9,2},{-2828.0,809.0,1.13,1},{-2751.8,804.3,1.09,1},{-2793.0,906.1,1.49,2},{-2928.8,741.9,1.31,1},
		{-2826.2,1142.0,1.93,2},{-2843.1,1250.9,1.6,2},{-2817.6,1066.9,1.79,2},{-2975.5,802.4,1.4,2},{-2776.1,999.2,1.59,2},{-2791.9,833.4,1.63,2},{-2830.3,1042.3,1.38,1},{-3008.6,828.8,1.39,1},
		{-2919.1,955.8,1.29,2},{-2851.2,737.8,1.53,1},{-2919.1,1023.6,1.3,1},{-2992.9,865.5,1.57,1},{-2998.8,974.0,1.72,2},{-2674.4,800.9,1.34,2},{-2797.5,1009.5,1.68,2},{-3024.4,716.7,1.01,1},
		{-2830.2,1314.1,1.54,1},{-2926.6,905.2,1.41,2},{-2852.1,809.7,1.09,1},{-2480.3,791.9,1.13,1},{-3032.8,764.2,1.25,2},{-2860.3,1187.9,1.35,2},{-2937.4,826.6,1.36,1},{-2263.4,812.4,1.87,2},
		{-2817.9,1104.2,1.76,2},{-2794.6,811.5,1.83,2},{-2209.0,823.1,1.23,1},{-2909.3,1136.1,1.37,2},{-2779.2,972.6,1.88,2},{-2624.2,787.8,1.38,2},{-2970.2,1080.8,1.29,1},{-2876.4,1069.9,1.6,2},
		{-2785.4,846.9,1.45,1},{-2904.3,828.9,1.64,2},{-2677.1,768.3,2.0,2},{-2565.9,760.5,1.46,1},{-2881.8,1190.9,1.29,1},{-2818.2,1367.4,1.54,2},{-2891.5,1212.8,1.59,1},{-2885.7,1127.7,1.43,2},
		{-2881.7,914.1,1.74,2},{-2874.8,1250.5,1.42,1},{-2193.7,835.8,1.62,2},{-2293.9,812.5,1.74,2},{-2863.8,909.9,1.94,2},{-2337.6,799.6,1.94,2},{-2766.3,954.9,1.49,2},{-2856.3,844.6,1.9,2},
		{-2965.1,723.4,1.87,2},{-2689.2,745.1,1.79,2},{-2831.1,1339.2,1.53,1},{-2609.7,789.4,1.4,1},{-2949.2,786.5,1.38,1},{-2977.0,1117.1,0.94,4},{-2975.5,1125.0,1.03,4},{-2976.2,1135.5,1.17,4},
		{-2972.0,1148.0,0.89,4},{-2962.5,1158.9,1.14,4},{-2954.2,1179.5,1.34,4},{-2945.8,1196.6,1.16,4},{-2938.0,1206.7,0.9,4},{-2926.3,1234.0,1.0,4},{-2910.9,1254.2,1.43,4},{-2899.7,1263.7,1.17,4},
		{-2898.2,1271.4,1.03,4},{-2878.1,1299.1,0.95,4},{-2872.5,1310.3,1.04,4},{-2869.9,1322.1,1.05,4},{-2863.1,1329.3,0.83,4},{-2860.7,1337.5,1.08,4},{-2847.7,1354.0,1.1,4},{-2840.7,1361.9,0.89,4},
		{-2820.9,1394.0,0.88,4},{-2808.2,1412.0,1.06,4},{-2801.4,1421.4,0.91,4},{-2788.5,1412.3,1.37,4},{-2758.6,1406.5,1.38,4},{-2759.9,1398.4,1.37,4},{-2781.0,1398.6,0.82,4},{-2793.0,1398.8,0.89,4},
		{-2819.1,1353.0,1.09,4},{-2814.6,1330.1,1.07,4},{-2810.2,1309.7,1.06,4},{-2801.2,1301.2,1.25,4},{-2800.1,1295.8,1.33,4},{-2795.0,1286.1,1.47,4},{-2794.4,1264.5,0.82,4},{-2792.9,1253.3,0.91,4},
		{-2794.4,1236.0,1.41,4},{-2791.9,1225.2,1.39,4},{-2796.1,1212.8,1.18,4},{-2793.1,1182.4,1.07,4},{-2793.1,1162.3,0.96,4},{-2792.4,1153.3,0.85,4},{-2797.2,1146.6,1.15,4},{-2802.3,1124.6,0.93,4},
		{-2799.7,1104.4,1.13,4},{-2800.4,1081.9,0.88,4},{-2798.2,1074.2,1.0,4},{-2795.9,1066.2,1.15,4},{-2798.6,1060.9,1.33,4},{-2799.3,1046.0,0.89,4},{-2792.9,1038.0,1.33,4},{-2784.9,1001.0,1.16,4},
		{-2756.9,1005.5,1.39,4},{-2740.9,1002.6,1.22,4},{-2746.7,995.7,1.09,4},{-2768.3,949.4,1.26,4},{-2766.6,939.2,1.03,4},{-2770.0,929.1,0.88,4},{-2771.2,914.8,1.32,4},{-2763.4,889.9,1.05,4},
		{-2767.0,880.4,0.93,4},{-2759.5,874.8,0.95,4},{-2751.5,854.6,1.35,4},{-2744.9,845.4,1.19,4},{-2736.1,840.9,1.45,4},{-2732.7,831.8,1.04,4},{-2726.3,826.2,1.01,4},{-2719.9,817.9,1.05,4},
		{-2706.4,815.4,0.8,4},{-2693.8,811.2,1.18,4},{-2687.2,804.9,1.18,4},{-2685.3,806.1,1.35,4},{-2669.8,799.2,0.81,4},{-2663.5,800.5,0.8,4},{-2650.4,798.9,1.26,4},{-2608.1,808.8,1.09,4},
		{-2601.7,810.5,0.92,4},{-2587.9,817.3,1.23,4},{-2578.3,821.7,0.81,4},{-2568.1,821.8,1.31,4},{-2554.7,805.9,1.01,4},{-2539.5,790.5,1.47,4},{-2530.4,785.7,1.03,4},{-2525.4,785.0,1.43,4},
		{-2512.6,795.2,0.85,4},{-2505.1,800.3,1.17,4},{-2494.0,812.9,0.85,4},{-2487.6,811.8,0.97,4},{-2477.3,813.6,0.86,4},{-2458.4,812.8,0.85,4},{-2442.1,816.6,1.12,4},{-2425.9,818.3,1.38,4},
		{-2407.3,822.0,1.36,4},{-2400.9,819.4,1.0,4},{-2384.6,819.7,1.0,4},{-2374.2,819.3,0.89,4},{-2351.6,821.6,1.0,4},{-2338.1,822.7,1.44,4},{-2333.0,823.5,1.08,4},{-2316.7,828.1,1.39,4},
		{-2306.3,827.3,1.21,4},{-2292.5,829.7,1.36,4},{-2278.6,839.2,1.23,4},{-2283.1,866.0,1.24,4},{-2285.7,870.1,1.34,4},{-2285.0,883.3,1.42,4},{-2286.8,894.7,0.96,4},{-2284.9,899.3,1.01,4},
		{-2270.4,899.5,1.02,4},{-2252.7,888.9,1.23,4},{-2255.0,875.9,1.23,4},{-2251.8,861.1,1.44,4},{-2255.9,853.9,0.94,4},{-2236.3,836.6,1.25,4},{-2206.9,836.0,1.42,4},{-2201.8,839.2,1.12,4},
		{-2181.1,835.4,1.06,4},{-2168.8,839.2,1.03,4},{-2153.2,835.5,1.48,4},{-2129.0,838.4,1.08,4},{-2120.0,836.8,0.97,4},{-2109.9,834.8,1.14,4},{-2099.0,834.9,1.08,4},{-2085.1,832.2,1.32,4},
		{-2053.8,841.3,1.11,4},{-2043.7,839.8,1.15,4},{-2035.7,838.6,0.96,4},{-2068.9,831.2,0.85,4},{-2091.1,832.1,1.15,4},{-2099.0,825.8,1.2,4},{-2110.3,826.7,1.32,4},{-2119.6,824.0,0.83,4},
		{-2131.8,822.6,1.47,4},{-2144.8,821.4,1.0,4},{-2152.5,819.0,1.27,4},{-2158.7,820.4,1.3,4},{-2179.7,815.1,0.81,4},{-2202.8,813.1,1.15,4},{-2215.8,814.3,1.07,4},{-2229.4,806.8,0.98,4},
		{-2255.0,804.0,1.14,4},{-2266.0,802.3,1.02,4},{-2278.6,800.5,0.81,4},{-2305.6,801.3,1.14,4},{-2310.7,796.5,0.81,4},{-2334.6,794.4,1.01,4},{-2353.1,793.3,1.31,4},{-2365.4,787.4,1.15,4},
		{-2371.3,787.5,1.36,4},{-2389.9,787.3,1.27,4},{-2423.8,779.7,0.96,4},{-2433.2,778.6,0.9,4},{-2444.9,780.3,1.06,4},{-2451.2,779.3,0.94,4},{-2467.6,773.0,1.36,4},{-2472.2,774.6,1.39,4},
		{-2494.7,771.6,1.35,4},{-2516.8,769.9,1.33,4},{-2532.1,762.7,0.93,4},{-2563.0,758.2,1.01,4},{-2581.5,755.7,1.31,4},{-2591.6,758.2,0.87,4},{-2599.8,752.8,0.89,4},{-2608.8,753.4,1.5,4},
		{-2659.1,747.7,0.96,4},{-2671.8,743.5,1.48,4},{-2677.8,745.0,1.44,4},{-2691.7,740.0,1.48,4},{-2730.3,738.5,1.26,4},{-2740.6,733.3,1.26,4},{-2747.5,737.9,1.23,4},{-2796.8,733.4,1.48,4},
		{-2811.4,729.3,1.35,4},{-2822.3,729.5,0.99,4},{-2828.0,725.9,0.98,4},{-2838.6,724.5,1.43,4},{-2862.7,725.8,0.99,4},{-2872.1,724.6,1.16,4},{-2882.4,724.3,1.38,4},{-2900.4,718.8,0.8,4},
		{-2908.7,721.5,1.13,4},{-2921.8,719.7,0.92,4},{-2944.2,715.2,1.24,4},{-2956.3,717.4,0.93,4},{-2962.3,717.0,0.95,4},{-2974.3,717.1,1.43,4},{-2986.9,714.5,1.3,4},{-2997.5,713.3,1.1,4},
		{-3032.4,710.2,1.26,4},{-3041.2,710.7,1.07,4},{-3040.6,727.0,1.17,4},{-3036.6,738.1,1.48,4},{-3034.5,783.5,1.19,4},{-3028.4,794.1,1.49,4},{-3023.7,830.6,1.15,4},{-3023.5,837.7,1.11,4},
		{-3021.6,855.6,1.45,4},{-3019.3,872.7,1.08,4},{-3014.0,895.8,1.09,4},{-3014.7,901.9,0.81,4},{-3010.8,924.0,1.33,4},{-3004.8,958.5,1.43,4},{-3001.4,967.1,1.06,4},{-3002.3,979.0,1.31,4},
		{-2999.0,992.1,1.26,4},{-2995.3,1006.7,1.3,4},{-2990.4,1039.2,0.83,4},{-2992.0,1043.6,1.4,4},{-2991.4,1055.9,1.06,4},{-2982.8,1081.7,1.0,4},{-2986.7,1087.6,1.17,4},{-2983.2,1099.4,0.95,4},
		{-1919.1,855.6,1.31,4},{-2506.2,831.0,1.34,4},{-2515.0,833.5,1.44,4},{-2509.6,852.4,0.85,4},{-2508.3,839.7,1.25,4},{-2509.1,828.8,0.93,4},{3258.4,2244.0,1.72,2},{-102.5,2664.0,1.69,2},
		{1905.9,2549.4,1.54,1},{2186.9,2485.0,1.42,2},{3261.9,1924.1,1.26,1},{-994.9,2509.5,1.98,2},{3358.8,1923.5,1.25,1},{1820.3,2530.3,1.44,1},{-1632.1,2377.4,1.43,2},{-2110.9,2120.1,1.86,2},
		{256.8,2533.8,1.24,1},{2316.8,2551.7,1.53,1},{-1254.8,2490.0,1.64,2},{-1507.9,2391.0,1.48,1},{-140.6,2636.3,1.32,1},{3157.7,2273.9,1.72,2},{3567.8,1532.2,1.21,1},{771.2,2462.6,1.55,2},
		{-1560.7,2400.3,1.31,2},{3220.5,2084.0,1.42,1},{3004.4,2303.5,1.4,2},{3554.4,1505.4,1.08,1},{-1272.6,2396.9,1.39,2},{-10.1,2616.6,1.47,2},{2138.4,2469.7,1.3,2},{3593.9,1518.5,1.48,2},
		{178.8,2554.3,1.29,2},{3300.2,2133.1,1.83,2},{420.3,2580.2,1.56,1},{2699.0,2432.9,1.27,1},{2969.3,2368.8,1.39,2},{1006.2,2386.2,1.52,2},{3454.2,1872.6,1.88,2},{2256.4,2580.9,1.49,1},
		{3709.3,866.2,1.69,2},{1425.4,2492.4,1.44,1},{-329.8,2646.9,1.67,2},{163.5,2591.5,1.28,2},{3657.6,1255.6,1.39,1},{-23.4,2608.4,1.36,2},{3583.6,1168.1,1.26,2},{1406.0,2446.2,1.12,1},
		{-903.8,2486.5,1.48,1},{3556.4,1335.3,1.25,2},{1151.0,2499.0,1.68,2},{3489.3,1682.0,1.48,1},{2972.8,2339.6,1.86,2},{-222.6,2592.4,1.32,1},{707.8,2530.6,1.52,2},{-726.3,2573.6,1.5,1},
		{3662.4,896.5,1.46,1},{3226.0,1892.3,1.81,2},{1002.6,2437.4,1.85,2},{607.2,2509.0,1.42,1},{-1366.1,2467.6,1.35,1},{-501.2,2561.9,1.93,2},{1520.6,2511.9,1.36,2},{-778.2,2590.6,1.48,1},
		{1319.1,2437.5,1.17,1},{-1406.8,2461.4,1.58,1},{766.2,2478.7,1.9,2},{3161.9,2160.6,1.41,1},{3152.5,1943.2,1.23,1},{3337.0,2173.7,1.63,2},{1189.4,2441.1,1.01,1},{-67.8,2619.7,1.54,2},
		{-2574.8,1787.2,1.71,2},{2984.1,1949.7,1.46,2},{-335.4,2550.1,1.93,2},{310.4,2548.0,1.37,2},{3486.4,1716.1,1.45,1},{2562.0,2434.2,1.23,1},{2665.9,2419.0,1.07,1},{3357.4,2110.4,1.69,2},
		{3212.5,1939.7,1.11,1},{3262.1,1842.9,1.57,2},{388.7,2527.6,1.58,2},{-248.3,2570.1,1.83,2},{-510.2,2601.2,1.57,1},{2850.8,2358.7,1.27,2},{3654.1,1065.7,1.32,2},{3588.9,1609.0,1.61,2},
		{3155.6,2203.0,1.9,2},{-1537.1,2344.3,1.19,1},{-1814.7,2227.4,1.26,1},{3060.4,2214.0,1.38,2},{1241.5,2477.3,1.79,2},{2510.9,2514.3,1.6,2},{1972.5,2554.2,1.84,2},{2076.2,2550.3,1.5,1},
		{3250.0,2014.1,1.77,2},{3410.3,1740.5,1.07,1},{617.9,2484.2,1.45,2},{3621.5,997.8,1.8,2},{-2512.0,1806.5,1.66,2},{2426.8,2501.4,1.45,2},{3594.6,1218.1,1.83,2},{-1043.0,2495.6,1.73,2},
		{3282.9,1949.6,1.55,1},{3479.9,1800.2,1.66,2},{916.6,2446.2,1.83,2},{1263.9,2462.4,2.0,2},{3596.7,1345.6,1.13,1},{2335.5,2557.0,1.69,2},{3314.3,1967.2,1.96,2},{3702.6,1215.1,1.69,2},
		{360.6,2566.4,1.85,2},{3260.7,2060.1,1.4,2},{-1407.3,2348.5,1.88,2},{-668.5,2596.9,1.94,2},{-1629.4,2328.6,1.27,2},{1615.3,2538.2,1.25,1},{3676.4,1288.5,1.45,1},{3489.2,1394.4,1.44,2},
		{2950.2,2326.9,1.54,2},{3258.2,2258.6,1.54,1},{1203.5,2454.5,1.48,2},{2285.0,2535.0,1.71,2},{3609.5,1561.6,1.86,2},{-1734.5,2309.7,1.28,1},{2502.8,2465.0,1.43,2},{226.6,2572.7,1.02,1},
		{3490.5,1774.8,1.3,2},{906.8,2508.7,1.49,1},{984.7,2407.3,1.1,1},{2202.2,2547.0,1.9,2},{-2479.5,1881.3,1.46,1},{3440.3,1804.2,1.69,2},{820.0,2514.4,1.22,1},{2554.0,2488.2,1.17,1},
		{901.6,2434.4,1.23,1},{532.4,2550.9,1.22,1},{2514.6,2478.4,1.26,1},{-1904.9,2152.2,1.81,2},{2130.1,2529.7,1.6,2},{2361.0,2555.8,1.27,2},{3596.0,1189.2,1.38,2},{-1431.7,2407.3,1.96,2},
		{3213.5,2204.4,1.08,1},{3148.1,2190.8,1.96,2},{-73.9,2596.0,1.44,2},{-164.3,2584.9,1.29,2},{-843.0,2522.0,1.61,2},{-1303.7,2430.7,1.34,2},{3294.9,2237.9,1.11,1},{-847.2,2460.0,1.48,2},
		{-1416.8,2316.5,1.5,1},{1862.2,2498.6,1.37,2},{-2319.3,1945.7,1.44,2},{3647.6,1217.4,1.99,2},{-320.3,2554.7,1.4,2},{3502.7,1612.7,1.91,2},{3347.4,2134.2,1.04,1},{3392.5,1986.4,1.52,1},
		{489.6,2573.0,1.89,2},{3116.7,2309.1,1.35,2},{-2305.2,1910.9,1.87,2},{-1442.1,2423.3,1.94,2},{3699.5,1297.3,1.81,2},{-273.5,2652.6,1.34,2},{3613.9,1024.3,1.34,2},{3670.4,1375.8,1.57,2},
		{844.7,2433.1,1.48,1},{959.3,2410.2,1.89,2},{-724.0,2553.6,1.32,1},{2143.7,2585.6,1.14,1},{-1743.1,2273.4,1.08,1},{3581.1,1075.1,1.28,1},{950.5,2438.1,1.47,2},{3324.8,1877.2,1.41,1},
		{3300.1,2158.7,1.14,1},{-418.9,2634.3,1.13,1},{562.5,2530.5,1.68,2},{3390.9,1919.1,1.8,2},{621.8,2534.4,1.75,2},{3082.8,1969.9,1.51,2},{3193.4,2275.8,1.25,2},{-326.7,2633.0,1.35,1},
		{3615.8,1375.3,1.04,1},{-784.5,2573.5,1.51,1},{-1209.0,2421.2,1.39,1},{0.0,2591.1,1.44,1},{-2059.2,2129.4,1.35,1},{-922.6,2547.1,1.56,2},{-201.7,2642.2,1.95,2},{94.4,2537.4,1.9,2},
		{2815.2,2425.1,1.18,1},{3632.8,1465.0,1.5,2},{2482.1,2518.9,1.21,1},{-2373.9,1901.2,1.89,2},{-1130.0,2508.0,1.35,2},{951.5,2492.2,1.62,2},{2875.3,2373.7,1.85,2},{1251.7,2493.2,1.28,2},
		{2932.2,2379.9,1.6,2},{3393.4,2055.9,1.44,1},{-1070.3,2481.0,1.43,2},{3661.8,1288.5,1.55,1},{3609.5,1135.7,1.18,1},{3455.0,1949.9,1.51,1},{3246.2,1955.7,1.59,1},{3533.0,1288.6,1.3,1},
		{3623.0,1238.6,1.94,2},{-364.4,2675.7,1.54,2},{3362.5,2158.4,1.64,2},{-545.8,2597.3,1.8,2},{3151.2,2245.2,1.53,2},{3660.7,982.0,1.55,1},{3549.0,1158.1,2.0,2},{716.1,2467.9,1.01,1},
		{1829.8,2554.3,1.58,2},{2251.5,2486.0,1.54,1},{3203.1,2078.8,1.81,2},{127.4,2613.6,1.71,2},{3493.5,1832.1,1.49,2},{48.9,2601.3,1.35,1},{-201.2,2667.4,1.59,2},{-248.5,2630.7,1.17,1},
		{-742.8,2548.6,1.69,2},{-2211.1,2063.9,1.53,2},{1111.7,2424.5,1.24,1},{1288.1,2449.3,1.88,2},{-2331.8,1997.4,1.03,1},{2524.1,2453.7,1.98,2},{2098.7,2468.5,1.5,2},{-495.0,2595.9,1.15,1},
		{3512.2,1370.2,1.57,1},{-2242.5,2012.5,1.58,1},{-1189.0,2429.9,1.56,2},{3441.0,1729.3,1.02,1},{3690.4,985.7,1.8,2},{-352.8,2595.1,1.5,2},{3345.9,1782.8,1.33,1},{687.8,2517.4,1.67,2},
		{3487.8,1853.5,1.56,2},{-1590.6,2330.9,1.52,1},{883.6,2447.8,1.4,1},{241.4,2554.4,1.6,2},{-207.3,2540.1,1.67,2},{226.2,2594.0,1.93,2},{-1881.6,2155.2,1.66,2},{-2263.8,2070.6,1.28,2},
		{882.5,2423.4,1.82,2},{302.3,2530.7,1.31,1},{-464.2,2660.4,1.86,2},{-495.1,2634.3,1.27,1},{-1504.7,2425.3,1.01,1},{1218.0,2512.1,1.91,2},{1569.9,2494.4,1.67,2},{863.3,2470.2,1.18,1},
		{3346.6,2078.4,1.52,1},{3703.4,956.4,1.04,1},{3684.6,1055.7,1.01,1},{3335.4,1837.5,1.15,1},{3294.7,2252.0,1.9,2},{3369.7,1783.3,1.56,2},{3342.5,2193.4,1.67,2},{1767.0,2536.8,1.26,1},
		{2946.2,2307.4,1.96,2},{1863.2,2483.5,1.02,1},{2186.6,2554.8,1.46,2},{2473.7,2462.5,1.39,1},{-2474.1,1897.0,1.4,1},{1045.8,2462.6,1.35,2},{3228.5,2155.1,1.42,1},{3045.8,2246.2,1.47,1},
		{474.0,2510.4,1.8,2},{1109.7,2460.4,1.4,1},{-465.0,2549.5,1.06,1},{520.8,2530.7,1.42,2},{3476.8,1483.8,1.96,2},{278.3,2585.1,1.42,1},{3608.1,1392.3,1.93,2},{-1611.7,2304.2,1.14,1},
		{-1866.0,2223.4,1.4,1},{2584.2,2471.2,1.42,2},{-1519.8,2369.5,1.37,2},{3340.2,1996.6,1.05,1},{-2329.7,1920.2,1.42,1},{3075.3,2298.7,1.51,2},{3327.6,2150.0,1.15,1},{2288.8,2494.2,1.94,2},
		{-48.5,2642.0,1.44,1},{1393.2,2485.7,1.62,2},{1920.2,2524.6,1.41,2},{3011.3,1970.6,1.3,2},{-2362.5,1909.9,1.68,2},{121.3,2550.0,1.91,2},{-2281.3,2060.3,1.93,2},{-2456.3,1888.4,1.74,2},
		{1171.5,2458.2,1.51,2},{-1263.4,2426.4,1.78,2},{-1326.1,2410.9,1.17,1},{2325.7,2501.1,1.21,1},{3254.7,2223.5,1.88,2},{-1547.2,2296.7,1.46,1},{-679.9,2549.8,1.14,1},{-2309.6,2014.6,1.23,1},
		{3520.0,1621.8,1.52,1},{3295.0,1889.7,1.99,2},{3435.0,1677.8,1.28,2},{1057.6,2484.7,1.89,2},{-2098.8,2147.9,1.15,1},{3635.5,1146.0,1.43,1},{2955.3,2343.3,1.4,1},{3292.9,2188.9,1.03,1},
		{1888.2,2498.5,1.54,1},{3662.3,1430.5,1.4,1},{3517.7,1284.8,1.93,2},{3580.1,1445.6,1.52,1},{-1546.4,2323.0,1.55,1},{-2241.0,2026.9,1.62,2},{-1659.3,2279.5,2.0,2},{2399.7,2547.9,1.58,2},
		{95.3,2579.1,1.15,1},{1662.1,2519.4,1.41,2},{-1026.9,2516.4,1.31,1},{3377.5,1962.3,1.97,2},{3538.5,1401.5,1.13,1},{1642.9,2492.3,1.34,1},{-395.9,2648.5,1.29,1},{20.9,2569.2,1.33,1},
		{3289.7,1977.6,1.32,1},{3461.0,1786.8,1.57,1},{3277.5,2030.7,1.05,1},{-1856.6,2258.9,1.19,1},{3304.1,1807.5,1.59,1},{-1000.1,2531.3,1.47,1},{-2275.4,2023.6,1.08,1},{3170.0,2018.3,1.52,1},
		{-1650.7,2295.1,1.51,1},{2152.6,2506.9,1.28,2},{3509.1,1317.5,1.63,2},{3337.7,1810.3,1.28,2},{-1344.7,2451.6,1.51,1},{3525.5,1463.4,1.46,1},{2893.0,2356.9,1.55,2},{-1082.2,2522.9,1.34,1},
		{2110.5,2515.8,1.48,1},{3188.5,2312.0,1.13,1},{1769.4,2483.3,1.06,1},{3662.7,871.4,1.91,2},{-836.0,2481.0,1.89,2},{-2388.5,1980.3,1.01,1},{1637.1,2470.5,1.41,1},{-2703.0,1578.2,1.07,1},
		{-348.7,2682.5,1.53,1},{3639.3,1336.5,1.54,1},{2342.1,2509.3,1.75,2},{1738.9,2514.6,1.28,2},{1706.2,2477.6,1.33,2},{3503.3,1395.1,1.44,1},{2175.5,2542.1,1.43,2},{-159.9,2568.0,1.17,1},
		{3682.3,1365.2,1.56,1},{-1911.8,2231.6,1.3,2},{2086.7,2497.8,1.36,1},{-119.9,2595.5,1.39,1},{3636.8,1389.1,1.79,2},{3642.6,1410.8,1.53,1},{-1930.2,2210.2,1.56,1},{3700.4,1006.8,1.36,2},
		{3616.7,1073.5,1.34,2},{-963.8,2516.0,1.25,1},{1083.7,2452.1,1.57,1},{-289.2,2624.9,1.68,2},{2496.0,2479.5,1.41,1},{3365.4,1906.7,1.53,2},{2046.7,2564.1,1.13,1},{3170.5,2284.2,1.69,2},
		{3559.5,1181.9,1.59,1},{3203.3,2149.6,1.42,2},{-2587.4,1726.1,1.31,1},{2008.2,2559.1,1.39,1},{-122.1,2637.7,1.26,1},{1093.9,2422.7,1.49,1},{2836.0,2367.8,1.27,2},{-437.4,2665.8,1.37,2},
		{108.8,2599.9,1.11,1},{-2522.2,1867.3,1.33,2},{3571.9,1388.0,1.78,2},{3339.0,2212.4,1.36,1},{3361.9,2043.6,1.62,2},{3668.7,1004.8,1.57,2},{3503.3,1792.8,1.77,2},{3310.0,2234.3,1.38,1},
		{-737.8,2533.0,1.22,1},{-803.8,2551.2,1.1,1},{1094.5,2477.2,1.56,2},{-479.8,2596.5,1.27,2},{2141.7,2519.2,1.71,2},{1782.0,2530.1,1.66,2},{-13.4,2553.3,1.51,2},{1534.1,2475.9,1.35,1},
		{51.9,2561.1,1.56,2},{-2220.0,2048.3,1.65,2},{1775.4,2503.9,1.15,1},{3634.4,1304.8,1.83,2},{2151.5,2547.6,1.53,1},{-562.9,2594.5,1.86,2},{-611.2,2603.6,1.49,1},{759.0,2507.0,1.76,2},
		{3615.7,1266.3,1.33,1},{405.1,2551.3,1.65,2},{937.1,2445.5,1.69,2},{-2446.0,1954.4,1.22,1},{3382.6,1841.8,1.86,2},{-402.1,2582.1,1.98,2},{-2494.1,1900.5,1.0,1},{-483.8,2546.0,1.34,2},
		{3599.6,1439.8,1.94,2},{-349.8,2627.3,1.36,1},{758.1,2522.6,1.38,2},{3403.6,1844.3,1.12,1},{3379.9,1819.3,1.36,1},{3533.7,1309.1,1.8,2},{-2348.6,1960.8,1.18,1},{3414.0,1760.3,1.94,2},
		{1424.0,2473.5,1.29,2},{3685.9,1343.7,1.5,2},{-1604.2,2338.1,1.46,2},{1314.4,2486.9,1.46,1},{-33.2,2543.6,1.33,2},{2719.9,2356.0,1.88,2},{-1437.8,2327.2,1.94,2},{3111.9,2276.2,1.53,1},
		{2232.4,2491.9,1.11,1},{3298.8,2011.4,1.52,2},{3357.3,1874.2,1.87,2},{1606.6,2481.2,1.7,2},{2514.3,2443.4,1.19,1},{-2491.7,1822.6,1.04,1},{3422.7,1916.2,1.33,2},{3689.4,1227.5,1.53,1},
		{-2529.1,1837.2,1.49,2},{974.8,2442.0,1.26,2},{3545.3,1652.7,1.64,2},{2082.5,2581.0,1.6,2},{-2413.6,1821.0,1.11,1},{3497.7,1445.9,1.14,1},{-1150.0,2467.0,1.49,2},{3688.3,1329.3,1.16,1},
		{-2547.6,1749.5,1.07,1},{-1290.5,2469.2,1.48,1},{1068.2,2400.4,1.22,1},{1923.9,2542.1,1.3,2},{3572.2,1489.3,1.74,2},{1046.4,2436.9,1.44,2},{-901.0,2551.1,1.82,2},{-460.0,2628.4,1.83,2},
		{2213.0,2453.1,1.02,1},{-2332.3,1955.2,1.07,1},{-2501.7,1835.1,1.9,2},{3403.8,1966.5,1.89,2},{3448.6,1759.5,1.14,1},{192.0,2615.3,1.42,2},{3701.6,1158.8,1.56,2},{3216.2,2271.4,1.9,2},
		{3164.4,2042.9,1.45,1},{-1245.9,2431.6,1.76,2},{3489.3,1539.2,1.29,2},{1370.9,2453.6,1.41,1},{2618.3,2461.6,1.63,2},{1975.4,2518.0,1.57,2},{-1673.3,2297.9,1.4,2},{-812.3,2525.3,1.71,2},
		{3293.9,2100.2,1.02,1},{-1956.9,2223.0,1.9,2},{1465.0,2451.9,1.41,1},{-2191.7,2036.4,1.36,2},{3544.0,1432.6,1.09,1},{3442.5,1848.0,1.02,1},{3581.4,1473.1,1.66,2},{3376.6,1934.0,1.72,2},
		{170.2,2573.9,1.92,2},{-1988.1,2182.7,1.27,2},{3255.6,2107.9,1.35,1},{-1217.1,2445.7,1.27,1},{3116.4,2335.5,1.59,2},{3555.3,1489.5,1.16,1},{-2366.6,1944.2,1.88,2},{69.5,2593.3,1.93,2},
		{809.0,2444.7,1.78,2},{3680.5,1069.9,1.57,1},{-1597.6,2308.7,1.02,1},{462.9,2573.2,1.56,1},{3181.8,1965.1,1.45,2},{-819.2,2548.6,1.41,1},{3274.3,2190.2,1.05,1},{-287.9,2606.7,1.39,1},
		{1572.2,2523.8,1.48,1},{-1975.8,2190.6,1.26,1},{3625.2,1407.7,1.51,1},{-2505.3,1853.6,1.66,2},{3668.4,940.1,1.44,2},{2226.5,2556.4,1.08,1},{1407.6,2513.7,1.41,1},{-48.6,2543.5,1.5,1},
		{-1947.4,2203.3,1.0,1},{2194.6,2508.4,1.61,2},{3169.5,1939.8,1.43,2},{3513.5,1650.2,1.45,2},{2715.4,2442.0,1.16,1},{3417.3,2044.3,1.98,2},{3277.8,2069.8,1.06,1},{3522.2,1765.2,1.53,2},
		{3350.1,2178.7,1.52,1},{-1450.7,2439.1,1.35,1},{3027.0,1965.3,1.81,2},{3629.3,1159.7,1.05,1},{-2267.9,2000.8,1.38,1},{-1081.1,2491.4,1.99,2},{3709.8,840.0,1.38,1},{3702.0,893.2,1.59,1},
		{2704.2,2358.8,1.46,2},{-251.4,2672.4,1.52,2},{646.6,2526.0,1.4,2},{1355.5,2474.7,1.49,1},{3648.0,949.6,1.4,1},{3545.4,1595.4,1.68,2},{1877.0,2521.2,1.88,2},{3538.6,1560.8,1.08,1},
		{2417.4,2525.4,1.68,2},{3590.7,1305.3,1.17,1},{1338.8,2468.2,1.25,2},{3703.6,1266.1,1.37,1},{2870.3,2409.0,1.42,1},{-1824.3,2241.9,1.6,2},{-178.5,2667.1,1.52,1},{3050.4,2275.9,1.32,2},
		{3346.1,1950.7,1.74,2},{-2144.0,2129.2,1.26,1},{-2483.8,1841.1,1.46,2},{3324.8,2035.8,1.05,1},{3219.2,2291.5,1.27,1},{-131.1,2649.4,1.97,2},{-1263.6,2454.5,1.6,2},{3416.2,1704.3,1.81,2},
		{3144.7,2287.5,1.04,1},{-250.6,2608.4,1.33,2},{65.5,2549.6,1.65,2},{-1385.5,2420.9,1.75,2},{-2431.9,1912.0,1.76,2},{-713.7,2589.0,1.52,2},{1196.7,2506.6,1.06,1},{2221.3,2577.0,1.91,2},
		{-230.4,2532.5,1.56,1},{586.5,2547.1,1.78,2},{-1026.9,2500.5,1.35,1},{3267.6,2271.4,1.8,2},{3299.7,1997.3,1.37,1},{453.0,2544.0,1.12,1},{1150.0,2441.3,1.6,2},{2933.7,2348.7,1.64,2},
		{3718.9,1000.2,1.26,2},{-2536.4,1818.0,1.38,2},{1814.2,2544.4,1.75,2},{-2528.8,1854.9,1.12,1},{-1661.0,2335.1,1.56,1},{546.2,2502.1,1.09,1},{1660.5,2497.3,1.31,2},{1671.4,2548.2,1.56,1},
		{3699.1,856.1,1.82,2},{2355.6,2476.4,1.94,2},{3462.4,1841.1,1.92,2},{3611.4,1121.5,1.33,1},{638.8,2487.4,1.4,1},{1817.6,2516.4,1.2,1},{561.1,2496.8,1.73,2},{-2123.2,2100.8,1.41,2},
		{3109.6,2246.6,1.07,1},{3579.0,1147.5,1.8,2},{1136.7,2457.3,1.8,2},{3702.1,1110.3,1.73,2},{3434.6,1630.9,1.75,2},{2008.8,2527.0,1.79,2},{222.9,2532.3,1.14,1},{2084.4,2516.5,1.62,2},
		{-2399.9,1943.2,1.9,2},{3232.3,2249.5,1.69,2},{3402.3,2008.0,1.32,1},{3388.7,1903.4,1.25,1},{-971.4,2531.5,1.66,2},{3235.1,2075.8,1.37,2},{2370.2,2528.0,1.83,2},{1031.7,2441.6,1.59,2},
		{-1415.5,2431.4,1.36,2},{1476.3,2516.4,1.14,1},{-1042.9,2479.2,1.4,1},{-1874.2,2171.6,1.93,2},{3104.4,1932.5,1.23,1},{3594.6,1367.3,1.7,2},{-2344.5,1909.9,1.74,2},{-1314.6,2393.1,1.0,1},
		{1206.9,2431.5,1.55,2},{1614.5,2501.6,1.17,1},{-498.9,2545.8,1.25,2},{2132.0,2488.1,1.25,1},{-2559.5,1802.9,1.54,1},{-139.7,2596.7,1.95,2},{-601.1,2631.3,1.16,1},{729.1,2456.0,1.92,2},
		{-860.6,2572.4,1.47,1},{3407.0,1886.4,1.12,1},{-916.4,2516.5,1.47,2},{1488.1,2489.7,1.02,1},{774.1,2519.7,1.38,2},{-1144.7,2503.5,1.37,2},{3598.7,1044.0,1.68,2},{3471.3,1764.2,1.39,2},
		{-1553.6,2309.9,1.53,2},{3426.6,1663.0,1.58,1},{-2427.8,1984.1,1.47,1},{3681.0,1255.7,1.99,2},{-2315.5,1982.9,1.52,2},{-2181.8,2058.3,1.85,2},{3592.1,1094.6,1.5,1},{3527.3,1515.3,1.58,2},
		{3195.6,2210.0,1.58,1},{-900.8,2529.3,1.86,2},{-590.0,2602.8,1.41,1},{3560.6,1425.7,1.25,1},{3054.6,2293.3,1.39,1},{3684.2,1272.3,1.55,1},{-1650.5,2354.9,1.12,1},{2992.4,2323.7,1.53,1},
		{2305.8,2509.0,1.28,2},{3039.5,2322.1,1.35,2},{3159.3,2005.0,1.56,1},{1386.2,2457.8,1.85,2},{-2155.2,2071.8,1.26,1},{-41.3,2569.6,1.44,2},{1125.9,2420.8,1.66,2},{1406.9,2465.7,1.24,1},
		{-1173.1,2425.1,1.87,2},{-1421.8,2460.2,1.4,1},{-1443.0,2347.5,1.62,2},{-2393.5,1963.1,1.38,1},{3306.7,2050.3,1.86,2},{-615.7,2620.6,1.38,1},{-1969.4,2205.0,1.21,1},{3661.6,1407.5,1.04,1},
		{-911.4,2467.4,1.94,2},{3613.9,1292.2,1.08,1},{-1484.3,2382.1,1.5,1},{-1680.7,2275.5,1.06,1},{-114.7,2570.5,1.17,1},{3481.7,1732.3,1.18,1},{-1665.4,2354.9,1.66,2},{2596.2,2444.5,1.21,1},
		{-1567.3,2294.9,1.03,1},{3679.3,896.3,1.82,2},{-2381.1,2018.8,1.7,2},{3575.7,1344.0,1.29,1},{-928.3,2486.5,1.76,2},{-1585.4,2296.9,1.27,1},{-245.0,2555.5,1.82,2},{75.6,2569.8,1.42,1},
		{-761.5,2587.7,1.65,2},{1448.3,2450.8,1.44,2},{-2022.4,2170.2,1.4,1},{3177.0,2130.8,1.45,1},{-452.6,2609.7,1.46,1},{3371.4,2016.5,1.26,2},{51.2,2617.0,1.43,2},{3549.5,1626.5,1.46,2},
		{2864.5,2340.3,1.17,1},{3466.0,1508.8,1.49,1},{1644.2,2532.3,1.95,2},{-49.8,2587.1,1.91,2},{3242.1,1882.6,1.33,2},{3200.2,1973.3,1.41,2},{3183.0,2105.8,1.4,1},{-1964.4,2168.5,1.23,1},
		{3713.5,1148.0,1.96,2},{3561.8,1596.4,1.57,2},{1708.2,2494.6,1.94,2},{3022.0,2306.4,1.89,2},{3304.5,2079.1,1.96,2},{2344.4,2490.6,1.27,1},{3440.8,1973.9,1.37,2},{2398.0,2462.1,1.85,2},
		{2985.2,2296.3,1.37,2},{935.3,2462.0,1.57,1},{1941.9,2538.9,1.54,1},{2451.7,2466.2,1.32,2},{-2341.8,1935.6,1.71,2},{1426.8,2453.1,1.92,2},{-99.2,2557.0,1.15,1},{295.3,2583.0,1.52,2},
		{3422.8,2015.2,1.7,2},{2689.3,2373.3,1.35,2},{3648.9,1051.2,1.66,2},{2902.8,2388.0,1.37,1},{150.6,2607.4,1.42,2},{-89.0,2606.2,1.37,2},{2687.4,2396.7,1.37,2},{-1797.0,2294.7,1.72,2},
		{-644.8,2605.9,1.42,2},{212.2,2594.0,1.35,2},{1586.2,2536.2,1.9,2},{986.2,2379.6,1.63,2},{3473.6,1553.8,1.31,1},{3086.4,1934.9,1.58,2},{-1568.2,2368.4,1.76,2},{-139.1,2662.8,1.9,2},
		{796.2,2458.2,1.21,1},{3629.5,1424.9,1.33,2},{-539.8,2548.0,1.44,2},{3580.1,1505.3,1.67,2},{-2637.0,1681.1,1.25,2},{-2109.6,2091.7,1.23,1},{3484.7,1426.8,1.55,2},{-1279.6,2437.0,1.32,2},
		{2331.6,2529.7,1.92,2},{-1423.8,2359.7,1.67,2},{2307.3,2476.6,1.56,2},{3579.7,1629.4,1.93,2},{3314.0,2025.6,1.53,2},{730.0,2535.9,1.38,2},{-1366.1,2380.9,1.52,2},{-1273.2,2416.3,1.69,2},
		{-1570.9,2281.2,1.64,2},{331.8,2547.6,1.7,2},{-347.6,2613.3,1.88,2},{-1815.4,2266.8,1.29,2},{-702.9,2568.2,1.78,2},{-1842.2,2267.3,1.48,1},{-2603.2,1735.8,1.22,1},{1870.4,2545.8,1.48,2},
		{-355.0,2544.8,1.63,2},{3102.7,2300.0,1.45,1},{3218.3,1957.7,1.01,1},{742.1,2525.7,1.68,2},{3462.8,1682.8,1.97,2},{-1471.2,2345.7,1.61,2},{2124.7,2567.6,1.3,2},{439.3,2576.3,1.18,1},
		{3718.1,928.9,1.01,1},{-741.3,2574.1,1.34,2},{2395.9,2522.3,1.42,1},{-1122.3,2443.4,1.47,2},{-2520.1,1781.1,1.59,2},{1396.3,2503.2,1.82,2},{965.1,2486.8,1.98,2},{-586.8,2635.1,1.38,1},
		{3152.5,1981.0,1.34,2},{3140.0,2236.6,1.86,2},{-1493.2,2393.7,1.01,1},{1600.6,2513.1,1.65,2},{-2044.0,2141.9,1.17,1},{3534.1,1246.3,1.31,2},{-17.2,2589.5,1.95,2},{3318.1,2139.6,1.76,2},
		{3292.2,1852.4,1.08,1},{3640.2,973.3,1.3,1},{-868.1,2475.1,1.57,2},{-1713.4,2292.9,1.83,2},{3607.4,1089.7,1.05,1},{3468.9,1725.9,1.52,2},{-2349.6,2011.8,1.95,2},{1655.0,2469.6,1.37,2},
		{1896.7,2511.2,1.34,1},{2445.2,2445.1,1.84,2},{-355.7,2530.8,1.34,2},{-2407.4,1874.1,1.4,1},{-2559.8,1781.7,1.9,2},{-522.8,2567.1,1.48,1},{3503.6,1685.3,1.53,1},{3291.9,2048.5,1.62,2},
		{3408.4,1926.8,1.07,1},{1466.6,2499.1,1.57,1},{3642.4,1265.6,1.56,2},{-2290.3,2022.0,1.31,2},{2380.0,2467.5,1.56,2},{746.6,2455.1,1.72,2},{583.7,2500.2,1.86,2},{-2395.9,1892.5,1.93,2},
		{3482.4,1637.4,1.35,1},{-2417.5,1932.3,1.56,2},{-1585.1,2358.9,1.85,2},{3272.8,2222.7,1.98,2},{2544.3,2462.8,1.31,2},{-1735.5,2332.0,1.97,2},{3508.4,1579.1,1.24,1},{3247.9,2034.7,1.37,1},
		{2886.4,2391.2,1.94,2},{3025.3,2320.9,1.71,2},{3048.2,2225.1,1.85,2},{-1537.1,2373.5,1.5,2},{-2462.4,1922.7,1.51,1},{-874.9,2499.6,1.46,1},{-1993.5,2151.1,1.53,2},{-1231.3,2462.0,1.32,2},
		{1075.6,2425.5,1.61,2},{3139.3,1937.6,1.27,1},{3490.6,1565.1,1.92,2},{2429.8,2467.6,1.35,1},{77.9,2634.4,1.48,1},{398.1,2585.0,1.38,2},{791.9,2481.0,1.57,1},{297.1,2562.0,1.02,1},
		{3602.1,1014.2,1.53,2},{2151.1,2478.6,1.37,1},{-299.3,2688.3,1.55,1},{-522.9,2609.2,1.43,1},{-162.3,2618.9,1.02,1},{3631.0,1028.2,1.36,2},{-1672.3,2314.4,1.48,2},{-1869.3,2252.1,1.8,2},
		{3206.6,2112.1,1.26,2},{3577.1,1132.8,1.28,1},{-1618.8,2340.2,1.67,2},{3684.5,1037.9,1.74,2},{2253.2,2537.0,1.43,1},{-2278.1,1980.8,1.66,2},{1752.1,2551.8,1.89,2},{-566.8,2573.9,1.87,2},
		{3172.5,2224.0,1.59,2},{3560.7,1672.4,1.99,2},{-697.3,2544.5,1.37,1},{3705.2,921.4,1.51,2},{3438.5,1706.8,1.94,2},{1523.3,2534.7,1.67,2},{1334.4,2508.4,1.59,1},{-1494.3,2332.8,1.61,2},
		{3575.3,1213.9,1.9,2},{3377.2,2074.7,1.59,1},{3166.3,1965.2,1.42,2},{3427.4,1847.8,1.44,1},{-2622.3,1707.4,1.22,1},{2971.4,2292.6,1.68,2},{3376.6,2109.0,1.91,2},{-1186.4,2481.9,1.78,2},
		{1298.5,2470.2,1.6,2},{133.8,2536.7,1.68,2},{-1300.8,2482.6,1.58,1},{-292.4,2571.3,1.34,2},{-2535.3,1770.8,1.35,2},{570.5,2510.8,1.25,1},{-1601.4,2272.5,1.17,1},{2784.7,2405.9,1.21,1},
		{3442.3,1891.0,1.35,1},{-769.7,2527.4,1.32,1},{1290.7,2512.7,1.49,1},{3506.9,1701.9,1.81,2},{-970.4,2490.9,1.8,2},{-1361.1,2454.0,1.12,1},{-2506.7,1772.0,1.96,2},{3276.6,1860.4,1.88,2},
		{2994.8,2351.1,1.05,1},{855.0,2494.8,1.73,2},{-77.5,2553.0,1.26,1},{1267.6,2495.2,1.67,2},{1796.9,2480.6,1.46,2},{3392.8,2086.5,1.38,1},{3665.2,1319.3,1.35,2},{2232.0,2474.9,1.34,2},
		{-2222.1,2031.2,1.23,1},{2065.5,2564.0,1.92,2},{-1461.8,2423.9,1.15,1},{1019.6,2481.0,1.97,2},{696.7,2506.6,1.26,2},{-328.8,2590.2,1.63,2},{3717.1,1229.7,1.42,2},{-602.1,2614.4,1.63,2},
		{-2406.0,1857.2,1.73,2},{-64.2,2571.8,1.58,1},{3680.9,845.3,1.73,2},{3538.2,1710.5,1.31,1},{2203.0,2581.9,1.33,1},{-1560.4,2415.4,1.71,2},{1510.1,2470.4,1.65,2},{-820.9,2491.2,1.47,1},
		{3192.6,2017.2,1.36,1},{1240.7,2452.7,1.81,2},{-1536.0,2403.6,1.55,2},{-1501.6,2309.1,1.22,1},{3443.3,1777.2,1.54,2},{1308.3,2504.2,1.62,2},{3463.7,1930.2,1.44,1},{-1370.0,2416.0,1.85,2},
		{-396.5,2616.7,1.05,1},{2606.0,2469.8,1.39,1},{-574.0,2555.7,1.76,2},{-427.2,2533.3,1.26,1},{3724.3,857.9,1.32,1},{-471.4,2611.2,1.4,2},{-2300.8,1937.9,1.35,1},{-511.6,2584.4,1.35,1},
		{1799.8,2516.0,1.95,2},{-2028.0,2144.7,1.48,2},{-420.7,2591.6,1.25,1},{2281.3,2571.8,1.14,1},{1976.3,2533.9,1.51,1},{1940.0,2501.6,1.41,2},{2474.5,2442.0,1.45,2},{1239.7,2513.4,1.27,2},
		{3209.0,2187.7,1.92,2},{830.3,2467.8,1.58,2},{974.6,2471.8,1.48,2},{-420.3,2614.1,1.53,2},{3358.5,1938.1,1.83,2},{1024.6,2415.7,1.48,1},{3500.6,1424.7,1.32,2},{3624.0,1128.2,1.07,1},
		{3271.3,1997.0,1.4,2},{-320.1,2608.4,1.35,1},{2730.7,2442.0,1.96,2},{1065.8,2462.2,1.21,1},{3128.3,2196.4,1.4,2},{261.9,2602.1,1.36,1},{-1982.3,2213.8,1.79,2},{3676.0,1303.7,1.46,1},
		{3401.2,2025.9,1.46,1},{1348.9,2447.1,1.3,1},{3562.4,1234.2,1.02,1},{2071.2,2536.5,1.06,1},{2804.8,2414.3,1.31,1},{1813.1,2486.1,1.19,1},{-2404.3,2009.6,1.16,1},{1847.2,2534.0,1.01,1},
		{-1771.6,2312.4,1.31,1},{3234.2,1962.9,1.32,2},{-1775.4,2256.7,1.67,2},{1542.8,2504.5,1.34,2},{-264.5,2536.6,1.5,1},{3632.0,1209.5,1.19,1},{-1423.6,2387.2,1.29,2},{859.7,2455.3,1.39,2},
		{-2572.8,1757.0,1.41,1},{-1564.3,2350.2,1.64,2},{3274.5,2147.2,1.59,1},{3654.0,1136.8,1.45,2},{3492.8,1756.9,1.96,2},{-1698.2,2333.6,1.54,2},{3587.0,1400.9,1.82,2},{3453.9,1814.8,1.77,2},
		{3051.7,1961.4,1.66,2},{3052.0,2352.4,1.3,2},{1049.9,2417.3,1.1,1},{-2356.3,2034.6,1.34,2},{3559.2,1274.3,1.52,2},{877.5,2471.4,1.35,1},{-1521.0,2335.4,1.35,1},{1849.2,2549.0,1.24,1},
		{3582.9,1264.2,1.04,1},{3255.7,1987.0,1.96,2},{-868.6,2456.3,1.59,2},{-2094.5,2108.8,1.42,1},{403.1,2519.8,1.27,2},{-1406.2,2325.6,1.92,2},{-1194.4,2497.9,1.48,1},{2673.4,2464.1,1.11,1},
		{-1456.1,2322.5,1.76,2},{-41.8,2619.7,1.07,1},{3439.4,1958.1,1.33,1},{3565.2,1256.4,1.96,2},{-430.3,2561.5,1.42,1},{254.5,2579.7,1.08,1},{-1879.2,2233.5,1.31,1},{19.6,2585.7,1.45,1},
		{-911.5,2561.2,1.33,1},{1073.7,2498.1,1.73,2},{3366.7,1996.7,1.77,2},{-144.9,2552.9,1.26,1},{2916.2,2338.7,1.94,2},{2715.4,2425.4,1.49,2},{1957.0,2561.2,1.77,2},{-894.4,2461.2,1.09,1},
		{663.5,2475.2,1.66,2},{1008.3,2489.7,1.17,1},{-2225.5,2087.9,1.53,1},{-374.3,2661.1,1.48,2},{-244.5,2530.0,1.39,1},{-2465.5,1844.6,1.69,2},{3611.0,1450.6,1.55,1},{3245.4,2281.5,1.48,1},
		{3655.0,1185.5,1.15,1},{-1495.9,2439.8,1.15,1},{-160.6,2671.5,1.0,1},{-2298.8,1969.4,1.15,1},{3343.4,1974.5,1.55,2},{-2141.3,2065.0,1.88,2},{3576.1,1100.5,1.66,2},{1687.5,2509.3,1.27,2},
		{3505.3,1458.2,1.0,1},{3539.3,1195.6,1.72,2},{-2394.2,1917.2,1.35,2},{-210.4,2622.3,1.54,2},{3030.5,2283.3,1.37,1},{2432.0,2524.6,1.28,1},{3553.3,1447.2,1.34,2},{3718.7,1087.1,1.95,2},
		{-1299.8,2395.5,1.14,1},{-1188.0,2453.9,1.51,1},{415.8,2542.2,1.45,1},{3218.7,2255.7,1.04,1},{-2409.3,1955.5,1.42,1},{-731.9,2588.3,1.28,1},{3356.3,1816.1,1.46,1},{2593.9,2491.8,1.7,2},
		{1716.2,2535.7,1.05,1},{155.2,2530.6,1.04,1},{-853.2,2476.4,1.18,1},{3543.6,1212.8,1.56,2},{-1879.9,2188.8,1.51,1},{2223.8,2524.7,1.3,1},{2166.6,2529.4,1.25,2},{2228.6,2452.5,1.54,2},
		{186.9,2535.6,1.35,1},{3196.9,1949.6,1.96,2},{3500.6,1628.3,1.21,1},{2753.9,2437.5,1.66,2},{3527.8,1350.8,1.7,2},{3378.3,2125.2,1.95,2},{3619.0,1224.0,1.59,1},{-177.5,2560.3,1.67,2},
		{3228.9,1936.7,1.35,1},{3009.6,2357.2,1.4,1},{197.9,2590.9,1.59,2},{1226.3,2431.4,1.96,2},{-2741.9,1521.9,0.89,4},{-2712.8,1576.2,1.33,4},{-2707.3,1577.4,1.14,4},{-2702.5,1589.7,0.96,4},
		{-2694.0,1600.1,1.09,4},{-2679.9,1622.3,0.92,4},{-2672.9,1631.4,1.11,4},{-2672.0,1638.0,1.01,4},{-2654.0,1663.2,1.29,4},{-2651.6,1670.0,1.31,4},{-2645.6,1680.6,1.35,4},{-2632.9,1691.3,1.44,4},
		{-2623.2,1714.1,1.1,4},{-2611.1,1725.8,1.41,4},{-2592.0,1757.4,0.85,4},{-2581.8,1776.4,1.36,4},{-2576.5,1786.2,1.05,4},{-2558.6,1815.9,1.01,4},{-2557.8,1823.2,0.96,4},{-2547.2,1830.5,1.28,4},
		{-2546.5,1837.2,1.14,4},{-2529.0,1858.0,1.22,4},{-2525.7,1867.7,1.35,4},{-2521.7,1877.8,1.22,4},{-2516.3,1887.7,0.89,4},{-2510.5,1896.2,1.25,4},{-2497.0,1920.9,1.41,4},{-2489.0,1926.6,1.36,4},
		{-2479.2,1941.7,1.4,4},{-2472.7,1953.4,1.29,4},{-2467.3,1962.1,0.86,4},{-2457.8,1966.2,1.44,4},{-2423.4,2000.8,1.09,4},{-2416.7,2003.0,0.91,4},{-2400.0,2015.9,1.42,4},{-2391.5,2019.5,1.29,4},
		{-2384.2,2022.0,1.42,4},{-2331.7,2049.7,1.0,4},{-2325.9,2054.4,0.87,4},{-2318.2,2056.1,0.84,4},{-2309.7,2059.7,1.4,4},{-2266.6,2080.5,1.04,4},{-2253.0,2086.8,1.49,4},{-2241.4,2093.5,1.48,4},
		{-2228.7,2098.4,1.08,4},{-2190.9,2119.8,1.42,4},{-2180.5,2121.4,1.03,4},{-2168.6,2127.1,1.33,4},{-2164.1,2133.3,1.24,4},{-2144.5,2141.3,0.94,4},{-2140.7,2139.4,0.85,4},{-2131.6,2144.2,0.94,4},
		{-2104.6,2155.6,1.34,4},{-2080.6,2173.8,0.82,4},{-2066.5,2172.6,1.09,4},{-2054.9,2178.4,1.16,4},{-2048.8,2188.7,1.26,4},{-2038.3,2189.2,1.16,4},{-2027.1,2197.7,1.2,4},{-2020.1,2198.5,0.91,4},
		{-2006.5,2203.4,1.27,4},{-1990.5,2213.3,1.09,4},{-1970.3,2223.1,1.23,4},{-1960.1,2226.1,1.16,4},{-1931.3,2240.3,1.25,4},{-1927.1,2244.0,1.19,4},{-1915.0,2245.1,1.08,4},{-1906.9,2253.9,1.13,4},
		{-1902.1,2252.5,1.09,4},{-1885.1,2264.1,1.23,4},{-1865.2,2273.2,0.87,4},{-1862.3,2272.7,1.07,4},{-1842.7,2282.1,1.2,4},{-1822.3,2290.3,1.38,4},{-1801.2,2300.0,1.33,4},{-1777.4,2310.3,1.1,4},
		{-1770.8,2317.8,0.87,4},{-1761.1,2316.9,1.25,4},{-1751.0,2324.5,1.14,4},{-1729.8,2336.3,1.49,4},{-1713.2,2343.7,1.15,4},{-1700.8,2351.7,1.06,4},{-1692.9,2353.4,1.3,4},{-1683.4,2358.9,1.38,4},
		{-1677.2,2360.8,1.44,4},{-1657.3,2369.3,1.42,4},{-1643.3,2376.4,0.9,4},{-1631.0,2383.3,1.28,4},{-1625.0,2383.7,1.24,4},{-1614.2,2392.5,0.91,4},{-1603.6,2397.4,1.27,4},{-1596.2,2396.6,1.46,4},
		{-1590.1,2403.8,1.21,4},{-1579.8,2408.0,1.48,4},{-1565.5,2414.9,1.04,4},{-1538.7,2429.5,0.92,4},{-1511.8,2440.0,0.81,4},{-1476.1,2446.4,0.93,4},{-1458.1,2451.8,1.48,4},{-1445.6,2454.0,1.15,4},
		{-1431.7,2458.9,1.01,4},{-1416.7,2458.8,0.95,4},{-1404.8,2464.4,0.91,4},{-1394.1,2465.0,1.33,4},{-1381.9,2468.4,1.17,4},{-1376.9,2468.9,1.45,4},{-1370.9,2473.5,1.26,4},{-1354.6,2472.8,1.19,4},
		{-1342.4,2475.2,0.95,4},{-1332.4,2481.0,1.22,4},{-1285.1,2489.6,1.44,4},{-1277.9,2490.0,0.94,4},{-1259.3,2497.8,0.84,4},{-1251.9,2494.9,1.25,4},{-1234.7,2502.0,1.19,4},{-1203.4,2507.7,1.23,4},
		{-1191.4,2506.0,1.39,4},{-1163.1,2518.3,1.2,4},{-1138.6,2518.8,1.26,4},{-1132.8,2524.6,0.85,4},{-1123.0,2521.9,0.85,4},{-1114.3,2527.8,0.96,4},{-1107.1,2527.0,1.12,4},{-1099.8,2531.0,1.19,4},
		{-1092.0,2529.3,0.81,4},{-1081.3,2530.5,1.48,4},{-1052.6,2536.7,0.82,4},{-1041.0,2540.7,1.33,4},{-1033.1,2544.9,0.83,4},{-1015.0,2544.9,1.29,4},{-1005.3,2550.4,0.91,4},{-991.4,2553.8,0.89,4},
		{-977.6,2554.0,1.28,4},{-964.2,2555.1,1.31,4},{-941.7,2563.9,1.47,4},{-930.8,2563.5,0.89,4},{-917.4,2568.4,0.91,4},{-907.4,2570.0,0.8,4},{-896.4,2572.0,1.01,4},{-888.4,2574.0,1.41,4},
		{-877.8,2573.0,1.03,4},{-864.1,2578.2,1.32,4},{-852.3,2578.5,1.34,4},{-839.9,2580.8,1.48,4},{-806.0,2592.7,0.92,4},{-794.4,2592.9,1.25,4},{-783.5,2592.0,1.41,4},{-774.1,2596.6,1.36,4},
		{-766.9,2597.5,1.03,4},{-757.8,2599.2,1.07,4},{-749.5,2601.7,0.95,4},{-742.5,2601.6,0.92,4},{-735.0,2606.1,1.15,4},{-705.8,2611.1,1.46,4},{-696.8,2612.2,0.92,4},{-642.7,2621.9,1.22,4},
		{-617.9,2625.8,0.92,4},{-597.8,2632.3,1.3,4},{-587.2,2635.1,0.96,4},{-577.0,2636.1,0.96,4},{-567.2,2637.3,1.26,4},{-520.0,2651.9,1.26,4},{-507.9,2651.5,1.24,4},{-494.1,2652.5,0.94,4},
		{-475.7,2656.3,1.39,4},{-469.1,2662.1,1.23,4},{-420.7,2671.0,1.08,4},{-412.6,2674.5,0.94,4},{-381.7,2677.8,1.08,4},{-372.4,2677.6,1.07,4},{-359.1,2683.6,0.92,4},{-347.2,2683.6,0.87,4},
		{-304.0,2690.1,1.42,4},{-292.6,2690.3,0.84,4},{-283.0,2693.4,1.28,4},{-271.8,2689.6,1.38,4},{-256.4,2690.6,0.89,4},{-249.7,2687.1,1.33,4},{-239.2,2687.3,1.08,4},{-226.7,2684.4,1.24,4},
		{-197.6,2682.2,0.97,4},{-178.2,2678.3,0.96,4},{-166.5,2671.8,1.45,4},{-141.4,2668.7,0.82,4},{-88.4,2664.7,0.99,4},{-83.4,2661.4,0.83,4},{-63.7,2657.3,1.28,4},{-42.9,2658.4,1.44,4},
		{-22.3,2649.0,1.17,4},{-0.4,2646.3,1.08,4},{9.2,2647.5,1.39,4},{18.0,2646.1,1.35,4},{71.6,2637.1,1.4,4},{133.8,2625.6,1.48,4},{141.0,2627.8,0.85,4},{156.2,2622.6,1.29,4},
		{183.6,2618.6,1.39,4},{188.8,2617.0,1.37,4},{231.7,2613.6,0.8,4},{238.3,2612.1,1.38,4},{268.5,2609.0,1.36,4},{287.4,2605.0,1.3,4},{308.8,2601.1,0.88,4},{312.8,2602.2,0.93,4},
		{335.2,2599.9,1.12,4},{341.3,2593.6,1.02,4},{353.2,2595.3,1.29,4},{364.8,2591.6,1.42,4},{372.5,2594.0,0.92,4},{394.4,2588.5,0.85,4},{410.2,2585.2,0.97,4},{420.2,2584.2,1.28,4},
		{427.3,2584.6,1.09,4},{433.5,2581.3,1.19,4},{453.4,2581.4,0.82,4},{469.8,2576.7,1.34,4},{480.0,2577.7,1.07,4},{488.0,2571.8,1.22,4},{493.1,2574.5,1.46,4},{521.2,2566.9,1.16,4},
		{556.8,2566.0,0.99,4},{564.0,2560.5,0.83,4},{592.0,2558.0,0.81,4},{604.0,2553.5,1.36,4},{619.1,2556.1,1.24,4},{629.0,2550.3,1.42,4},{642.2,2549.1,0.93,4},{654.4,2549.3,1.43,4},
		{672.3,2545.3,1.08,4},{702.5,2542.6,1.33,4},{736.8,2536.6,1.44,4},{755.1,2533.9,1.18,4},{760.4,2532.3,0.8,4},{800.8,2525.4,1.2,4},{811.3,2521.8,1.21,4},{827.2,2519.8,1.12,4},
		{858.9,2515.7,1.35,4},{869.3,2518.2,0.94,4},{886.0,2513.9,1.02,4},{896.2,2509.6,0.85,4},{920.9,2509.2,1.23,4},{933.4,2502.0,1.12,4},{963.4,2502.3,1.1,4},{974.1,2497.8,0.92,4},
		{981.2,2500.1,1.04,4},{993.4,2499.5,1.33,4},{995.9,2498.6,1.29,4},{1013.5,2498.8,1.07,4},{1018.6,2498.3,1.46,4},{1042.5,2501.3,1.0,4},{1073.9,2498.3,0.81,4},{1084.9,2504.1,1.32,4},
		{1098.6,2502.1,0.9,4},{1112.2,2504.3,0.98,4},{1132.9,2505.6,1.31,4},{1145.9,2504.6,0.89,4},{1153.9,2506.7,1.45,4},{1185.6,2511.6,1.46,4},{1198.7,2511.6,1.26,4},{1217.8,2511.5,1.22,4},
		{1231.0,2511.3,0.91,4},{1236.7,2513.0,1.35,4},{1249.9,2514.0,0.98,4},{1256.8,2518.1,0.96,4},{1265.6,2516.9,1.4,4},{1274.7,2519.0,1.03,4},{1295.0,2516.9,1.46,4},{1297.6,2521.3,0.93,4},
		{1312.7,2520.7,1.06,4},{1322.0,2521.6,1.31,4},{1345.1,2523.0,0.86,4},{1359.5,2523.3,0.9,4},{1379.7,2524.6,0.93,4},{1390.3,2523.6,1.39,4},{1410.9,2527.7,1.14,4},{1450.9,2531.9,0.96,4},
		{1462.6,2533.3,1.38,4},{1479.8,2534.9,1.36,4},{1486.4,2535.1,0.88,4},{1517.2,2533.9,1.12,4},{1526.1,2538.2,1.46,4},{1539.6,2536.4,0.99,4},{1555.8,2538.5,0.82,4},{1582.4,2543.1,1.19,4},
		{1591.3,2544.3,1.44,4},{1612.5,2545.6,1.42,4},{1619.9,2546.8,1.23,4},{1654.3,2549.2,0.95,4},{1678.2,2549.3,0.81,4},{1700.5,2548.4,0.99,4},{1716.9,2551.7,1.05,4},{1740.7,2555.1,0.9,4},
		{1751.9,2553.7,0.88,4},{1769.3,2554.9,1.07,4},{1793.4,2558.9,1.36,4},{1810.3,2559.9,1.36,4},{1824.9,2559.4,1.02,4},{1834.8,2562.3,1.21,4},{1860.7,2563.7,0.95,4},{1869.1,2563.9,1.3,4},
		{1879.6,2565.5,0.82,4},{1887.3,2568.2,0.81,4},{1897.6,2569.1,0.96,4},{1917.6,2565.9,1.45,4},{1926.7,2569.7,1.25,4},{1936.6,2571.4,1.37,4},{1976.5,2572.5,1.23,4},{2007.6,2578.6,0.91,4},
		{2027.2,2576.6,1.2,4},{2039.9,2575.9,1.46,4},{2044.6,2576.6,1.36,4},{2069.5,2580.1,1.06,4},{2079.8,2578.9,1.26,4},{2092.7,2580.0,1.25,4},{2110.1,2584.6,1.0,4},{2116.8,2582.0,1.15,4},
		{2139.0,2585.3,1.46,4},{2155.7,2585.0,0.87,4},{2170.9,2587.4,1.19,4},{2179.1,2590.4,1.03,4},{2198.1,2588.5,1.05,4},{2212.9,2589.0,0.95,4},{2227.5,2592.0,1.31,4},{2245.6,2591.1,1.09,4},
		{2255.1,2591.9,1.19,4},{2263.6,2585.2,1.45,4},{2292.0,2581.2,1.21,4},{2301.5,2578.8,0.97,4},{2311.7,2574.0,1.43,4},{2346.1,2568.7,1.46,4},{2351.2,2562.1,1.39,4},{2360.8,2561.4,0.81,4},
		{2373.0,2558.0,0.86,4},{2382.1,2553.6,1.4,4},{2402.2,2547.7,1.16,4},{2416.1,2543.7,1.03,4},{2427.9,2539.8,1.03,4},{2450.1,2536.2,0.99,4},{2476.0,2528.8,1.43,4},{2485.5,2528.6,1.47,4},
		{2489.6,2526.1,1.24,4},{2525.0,2515.1,0.97,4},{2532.9,2513.6,0.83,4},{2547.4,2504.1,1.24,4},{2602.6,2489.3,1.03,4},{2634.3,2481.8,0.87,4},{2642.8,2479.0,1.14,4},{2652.0,2477.3,0.88,4},
		{2674.3,2466.2,1.08,4},{2694.8,2464.3,1.3,4},{2707.7,2460.0,1.05,4},{2732.0,2453.1,1.2,4},{2753.6,2445.9,1.48,4},{2774.8,2438.2,1.21,4},{2793.4,2436.4,1.48,4},{2801.0,2434.0,1.23,4},
		{2806.6,2427.5,1.49,4},{2819.9,2426.9,1.33,4},{2835.1,2419.1,1.21,4},{2842.9,2421.0,1.11,4},{2857.3,2414.3,0.87,4},{2865.5,2410.4,1.11,4},{2893.0,2403.4,0.84,4},{2903.8,2398.9,1.42,4},
		{2924.3,2392.4,1.08,4},{2930.8,2392.9,0.83,4},{2941.2,2389.6,0.97,4},{2954.1,2387.8,0.93,4},{2987.9,2379.5,1.06,4},{2996.6,2371.9,0.97,4},{3003.7,2371.8,1.0,4},{3012.8,2369.6,1.18,4},
		{3019.5,2367.0,1.07,4},{3051.2,2358.1,1.46,4},{3062.6,2351.5,1.01,4},{3077.7,2346.6,1.36,4},{3086.5,2345.4,1.15,4},{3098.8,2346.8,1.31,4},{3105.8,2339.2,1.43,4},{3110.5,2340.9,0.88,4},
		{3119.6,2333.9,1.36,4},{3139.9,2330.9,0.8,4},{3147.1,2330.4,0.93,4},{3169.3,2322.8,1.02,4},{3178.7,2317.3,1.31,4},{3187.6,2316.7,1.27,4},{3197.3,2313.3,1.36,4},{3206.6,2308.1,1.31,4},
		{3226.8,2302.5,1.5,4},{3232.8,2302.2,1.1,4},{3247.5,2294.4,0.96,4},{3257.8,2291.3,1.21,4},{3262.6,2283.3,1.34,4},{3297.7,2264.8,0.85,4},{3305.5,2257.4,1.4,4},{3309.7,2251.5,1.14,4},
		{3342.2,2211.2,0.9,4},{3349.1,2203.1,1.29,4},{3357.8,2194.4,0.93,4},{3364.5,2182.7,1.22,4},{3376.9,2147.1,1.28,4},{3380.9,2139.8,0.87,4},{3386.4,2128.5,0.96,4},{3398.7,2093.5,0.88,4},
		{3405.4,2080.1,0.98,4},{3408.9,2063.2,1.1,4},{3418.9,2045.3,1.44,4},{3422.5,2041.1,1.44,4},{3425.4,2033.9,0.88,4},{3428.3,2022.3,0.85,4},{3429.5,2014.5,1.06,4},{3433.3,2003.3,1.05,4},
		{3436.8,1995.2,1.11,4},{3443.1,1988.0,1.37,4},{3449.0,1965.1,0.84,4},{3458.2,1947.1,1.24,4},{3459.6,1939.4,1.36,4},{3463.4,1931.1,1.31,4},{3466.8,1928.1,1.29,4},{3469.1,1910.5,1.11,4},
		{3477.0,1900.5,1.04,4},{3483.7,1880.3,0.83,4},{3488.0,1866.9,1.11,4},{3498.4,1848.8,1.33,4},{3498.3,1840.1,1.42,4},{3505.1,1827.7,1.06,4},{3504.8,1821.8,0.89,4},{3510.1,1813.2,1.39,4},
		{3522.4,1787.0,0.9,4},{3527.8,1777.6,1.06,4},{3529.8,1760.7,1.09,4},{3535.2,1754.7,0.84,4},{3538.0,1739.4,1.33,4},{3543.7,1728.4,0.94,4},{3545.8,1720.8,1.43,4},{3546.9,1715.8,0.84,4},
		{3550.9,1705.0,0.89,4},{3562.1,1689.6,1.02,4},{3566.0,1681.6,1.27,4},{3575.3,1653.6,1.09,4},{3572.9,1649.0,1.01,4},{3580.4,1634.9,1.49,4},{3587.4,1623.2,0.8,4},{3593.2,1600.1,1.21,4},
		{3602.7,1585.6,0.89,4},{3613.2,1547.6,0.92,4},{3622.4,1536.5,1.39,4},{3628.9,1519.0,0.88,4},{3641.1,1480.0,0.86,4},{3650.2,1460.0,1.43,4},{3676.3,1389.8,0.99,4},{3682.1,1381.6,1.24,4},
		{3683.0,1371.0,1.37,4},{3691.8,1359.9,1.17,4},{3692.5,1352.9,0.9,4},{3699.7,1334.9,0.85,4},{3708.8,1305.1,1.48,4},{3711.8,1287.8,1.06,4},{3711.7,1280.2,1.41,4},{3716.3,1270.0,1.39,4},
		{3716.7,1249.4,1.09,4},{3718.6,1226.6,1.04,4},{3722.2,1163.1,0.86,4},{3722.5,1147.9,1.08,4},{3720.7,1140.4,1.26,4},{3720.6,1120.0,1.27,4},{3721.4,1084.3,0.94,4},{3722.0,1071.9,0.83,4},
		{3726.4,1059.4,0.93,4},{3727.0,1033.9,0.91,4},{3727.3,1018.3,1.32,4},{3728.2,1005.2,1.01,4},{3729.3,993.6,1.27,4},{3729.4,978.4,1.26,4},{3728.3,967.6,1.13,4},{3728.2,956.9,1.13,4},
		{3728.3,943.2,1.25,4},{3732.5,929.4,0.81,4},{3733.7,921.3,1.27,4},{3731.1,892.4,0.89,4},{3734.4,877.6,0.81,4},{3734.5,856.5,1.19,4},{3734.1,850.6,0.92,4},{3733.0,844.3,1.17,4},
		{3736.5,829.7,1.45,4},{3736.5,806.9,1.03,4},{3735.6,789.4,1.47,4},{3707.3,803.5,0.96,4},{3703.5,813.6,0.8,4},{3696.8,815.0,1.14,4},{3693.8,824.6,1.45,4},{3677.5,839.3,1.16,4},
		{3673.4,849.2,1.06,4},{3668.6,859.0,1.31,4},{3665.8,865.3,1.2,4},{3655.0,883.5,1.37,4},{3648.6,896.0,1.06,4},{3646.5,908.5,1.45,4},{3640.9,913.1,1.23,4},{3632.9,930.4,1.2,4},
		{3625.1,948.5,1.36,4},{3624.2,955.7,1.41,4},{3616.1,972.3,1.11,4},{3615.1,981.7,1.28,4},{3607.4,993.2,0.99,4},{3601.3,1002.4,1.11,4},{3598.3,1015.2,0.82,4},{3589.0,1028.9,0.96,4},
		{3588.9,1040.8,0.85,4},{3580.9,1056.3,1.38,4},{3569.9,1086.3,1.34,4},{3558.7,1103.8,0.92,4},{3557.3,1110.8,1.26,4},{3547.2,1134.9,1.31,4},{3542.6,1153.6,1.3,4},{3540.3,1165.2,1.04,4},
		{3537.1,1172.1,1.13,4},{3534.7,1178.7,1.01,4},{3534.1,1191.3,1.19,4},{3528.7,1199.8,1.47,4},{3522.3,1242.6,0.94,4},{3520.2,1249.9,0.83,4},{3518.0,1255.1,0.95,4},{3514.7,1265.2,1.47,4},
		{3511.7,1274.8,0.99,4},{3508.6,1284.8,1.19,4},{3509.8,1297.0,1.41,4},{3504.3,1302.4,1.12,4},{3502.9,1315.4,1.28,4},{3504.8,1321.6,1.03,4},{3497.9,1334.3,1.25,4},{3496.8,1342.1,1.05,4},
		{3488.8,1382.1,0.8,4},{3485.9,1391.6,1.44,4},{3487.1,1400.2,1.42,4},{3476.9,1439.3,1.39,4},{3470.9,1452.7,1.16,4},{3469.8,1472.3,1.49,4},{3464.6,1485.5,0.82,4},{3465.3,1495.1,0.91,4},
		{3462.6,1499.9,1.34,4},{3459.6,1512.2,1.15,4},{3458.6,1525.2,1.47,4},{3455.1,1536.8,0.92,4},{3444.9,1581.0,1.14,4},{3437.7,1584.9,0.88,4},{3437.4,1597.7,0.84,4},{3425.5,1626.1,0.92,4},
		{3412.6,1654.5,1.06,4},{3401.0,1669.8,1.37,4},{3399.4,1675.3,1.47,4},{3396.1,1682.0,0.81,4},{3392.2,1692.5,1.09,4},{3387.0,1699.1,1.08,4},{3372.4,1715.4,1.35,4},{3361.9,1735.5,0.83,4},
		{3354.0,1745.0,1.5,4},{3351.7,1749.9,0.93,4},{3338.9,1769.0,1.34,4},{3328.7,1773.8,1.16,4},{3324.9,1780.0,1.04,4},{3316.3,1789.1,0.95,4},{3304.6,1798.9,1.37,4},{3294.3,1812.4,0.96,4},
		{3289.2,1816.2,1.2,4},{3280.9,1820.9,1.11,4},{3267.1,1837.3,1.13,4},{3255.9,1843.1,0.97,4},{3239.5,1853.9,1.1,4},{3233.8,1863.1,0.84,4},{3214.9,1873.5,1.14,4},{3191.5,1889.9,1.32,4},
		{3186.9,1894.3,1.27,4},{3171.9,1897.9,0.85,4},{3141.6,1915.7,0.82,4},{3133.7,1920.4,0.87,4},{3127.9,1923.6,0.84,4},{3086.1,1933.2,1.19,4},{3077.1,1934.8,1.16,4},{3069.2,1936.6,1.14,4},
		{3018.1,1944.6,1.4,4},{3004.2,1948.2,1.11,4},{2971.4,1945.6,1.15,4},{2976.4,1962.8,1.47,4},{2982.1,1968.0,1.4,4},{2987.4,1981.0,1.35,4},{2992.1,1982.0,1.44,4},{3004.9,1976.8,1.43,4},
		{3009.2,1976.6,1.45,4},{3020.9,1972.4,1.38,4},{3031.6,1970.9,1.0,4},{3045.4,1967.6,1.02,4},{3051.9,1969.2,1.3,4},{3084.5,1972.0,0.92,4},{3092.1,1976.2,1.16,4},{3101.8,1979.5,1.24,4},
		{3110.2,1988.4,1.48,4},{3132.5,2003.0,1.19,4},{3142.2,2011.4,0.93,4},{3143.7,2017.3,1.44,4},{3158.5,2037.7,1.11,4},{3157.3,2044.6,1.11,4},{3164.3,2049.1,1.19,4},{3171.4,2082.5,1.03,4},
		{3171.8,2090.5,1.47,4},{3168.2,2101.9,1.45,4},{3169.9,2105.9,1.01,4},{3165.8,2117.1,1.14,4},{3161.2,2142.1,1.43,4},{3129.4,2178.8,1.19,4},{3122.1,2184.0,0.95,4},{3106.1,2197.0,1.03,4},
		{3096.2,2197.4,1.43,4},{3082.4,2207.0,1.06,4},{3057.5,2207.9,0.84,4},{3052.4,2212.6,1.15,4},{3041.5,2234.9,0.86,4},{3043.6,2249.3,1.37,4},{3037.2,2272.5,1.06,4},{3033.7,2275.5,1.03,4},
		{3022.1,2274.5,1.2,4},{3009.1,2265.0,1.26,4},{3002.5,2248.7,1.44,4},{2995.8,2258.1,1.47,4},{2983.3,2271.0,1.12,4},{2975.9,2271.5,0.96,4},{2955.5,2280.2,0.89,4},{2930.4,2295.1,1.49,4},
		{2914.4,2302.2,1.4,4},{2909.9,2308.2,0.89,4},{2898.7,2307.3,0.87,4},{2888.0,2314.4,1.16,4},{2882.6,2318.9,1.13,4},{2869.9,2325.9,0.99,4},{2867.8,2328.4,1.24,4},{2841.3,2348.9,0.84,4},
		{2819.7,2358.7,1.05,4},{2818.8,2357.9,1.42,4},{2790.9,2372.0,0.87,4},{2769.4,2374.5,0.81,4},{2758.7,2380.3,1.33,4},{2742.6,2384.6,0.9,4},{2724.4,2355.1,1.13,4},{2718.2,2337.8,1.1,4},
		{2696.5,2329.5,0.96,4},{2690.0,2333.1,0.9,4},{2679.8,2339.9,1.14,4},{2672.0,2338.6,1.42,4},{2673.3,2368.6,1.31,4},{2673.4,2375.5,1.17,4},{2680.0,2398.1,1.09,4},{2675.4,2406.8,0.88,4},
		{2668.9,2410.2,0.97,4},{2648.3,2416.6,1.26,4},{2625.8,2423.8,1.3,4},{2562.0,2426.0,1.33,4},{2540.0,2428.3,0.96,4},{2535.6,2429.8,1.0,4},{2500.2,2436.7,1.06,4},{2480.1,2440.5,0.98,4},
		{2452.0,2443.5,1.28,4},{2436.4,2445.7,0.89,4},{2427.6,2446.8,0.94,4},{2402.1,2450.4,1.34,4},{2394.2,2457.9,0.92,4},{2369.6,2463.4,1.27,4},{2358.5,2464.5,1.47,4},{2353.9,2466.7,1.04,4},
		{2344.9,2470.2,0.85,4},{2309.6,2473.9,1.28,4},{2284.4,2475.4,0.89,4},{2255.1,2467.7,0.9,4},{2251.5,2464.2,0.96,4},{2244.6,2463.8,1.08,4},{2227.9,2447.5,1.48,4},{2214.7,2449.8,1.17,4},
		{2203.0,2457.4,1.18,4},{2193.6,2462.3,1.01,4},{2175.4,2468.1,1.12,4},{2138.1,2469.6,1.11,4},{2120.2,2467.5,0.8,4},{2114.0,2460.8,1.12,4},{2103.3,2457.7,1.22,4},{2082.8,2457.0,1.48,4},
		{2056.0,2500.2,0.98,4},{2046.2,2503.9,1.29,4},{2033.5,2484.9,1.09,4},{2033.9,2476.8,1.0,4},{2041.1,2470.3,0.91,4},{2033.1,2475.4,1.07,4},{2027.3,2485.6,1.4,4},{2012.2,2484.5,0.84,4},
		{2000.2,2466.3,1.13,4},{1996.1,2456.7,0.82,4},{1989.8,2452.0,0.86,4},{1989.3,2470.2,1.04,4},{1986.3,2477.9,1.17,4},{1976.8,2482.9,1.22,4},{1967.2,2482.6,1.47,4},{1948.8,2483.2,1.09,4},
		{1917.8,2483.3,1.01,4},{1909.0,2481.9,1.18,4},{1896.3,2479.0,0.81,4},{1810.6,2479.0,1.14,4},{1802.0,2482.5,0.96,4},{1791.4,2483.3,1.3,4},{1787.8,2472.9,1.46,4},{1745.7,2470.8,0.81,4},
		{1700.3,2471.1,0.85,4},{1690.3,2469.2,1.41,4},{1682.5,2464.8,1.14,4},{1658.6,2466.8,1.2,4},{1639.8,2465.0,1.4,4},{1630.6,2467.0,0.88,4},{1605.8,2464.1,0.99,4},{1598.0,2465.1,0.88,4},
		{1586.8,2470.0,1.38,4},{1576.7,2470.2,0.87,4},{1562.4,2467.6,1.42,4},{1553.3,2462.5,1.0,4},{1540.6,2464.6,1.46,4},{1532.6,2458.4,1.31,4},{1525.2,2459.8,1.03,4},{1509.4,2460.2,1.32,4},
		{1496.3,2452.6,0.9,4},{1467.9,2450.4,1.18,4},{1460.7,2449.7,1.4,4},{1450.0,2445.9,1.32,4},{1435.3,2447.9,1.42,4},{1424.3,2446.9,1.0,4},{1410.9,2442.1,1.33,4},{1405.6,2444.2,1.13,4},
		{1396.6,2442.3,1.02,4},{1388.8,2438.4,1.17,4},{1378.9,2438.1,0.87,4},{1357.4,2437.8,1.25,4},{1350.5,2437.7,1.16,4},{1325.7,2434.6,1.41,4},{1318.9,2430.6,1.44,4},{1314.1,2436.4,0.81,4},
		{1305.7,2439.8,0.96,4},{1289.6,2439.9,1.3,4},{1260.5,2434.9,0.89,4},{1247.8,2431.2,0.86,4},{1210.2,2429.7,1.23,4},{1198.4,2426.9,0.85,4},{1187.8,2427.9,0.85,4},{1179.3,2425.7,0.81,4},
		{1159.2,2424.3,0.89,4},{1143.9,2421.5,1.22,4},{1129.6,2417.6,1.42,4},{1118.1,2419.1,1.27,4},{1103.8,2415.7,0.9,4},{1096.1,2409.9,1.19,4},{1086.0,2410.0,1.27,4},{1068.9,2401.8,1.38,4},
		{1043.5,2369.7,1.0,4},{1034.3,2372.2,0.83,4},{1029.9,2379.3,1.33,4},{1001.2,2382.1,1.33,4},{982.8,2375.9,1.31,4},{964.2,2382.3,1.35,4},{962.6,2387.9,1.07,4},{959.3,2398.4,0.96,4},
		{951.1,2407.9,0.84,4},{936.6,2434.7,1.2,4},{920.0,2424.7,0.92,4},{912.8,2421.1,1.13,4},{918.1,2406.3,0.82,4},{922.1,2402.7,1.01,4},{912.7,2400.6,1.13,4},{903.5,2392.2,1.25,4},
		{902.4,2401.5,0.95,4},{901.5,2410.6,1.42,4},{881.1,2421.1,1.15,4},{872.1,2420.5,1.38,4},{844.1,2426.7,1.46,4},{814.2,2430.1,0.8,4},{807.7,2430.3,1.27,4},{789.4,2433.7,0.93,4},
		{764.5,2439.7,1.2,4},{745.4,2441.3,1.12,4},{717.5,2460.3,1.36,4},{713.0,2460.9,0.9,4},{707.5,2461.6,0.95,4},{699.3,2462.0,1.4,4},{677.7,2466.7,0.94,4},{666.2,2467.5,0.83,4},
		{656.6,2469.4,1.06,4},{646.6,2470.3,1.37,4},{631.7,2473.2,1.2,4},{617.1,2478.1,1.01,4},{592.3,2480.2,0.84,4},{585.8,2485.5,1.2,4},{565.4,2483.9,1.31,4},{556.2,2486.4,0.92,4},
		{545.5,2491.5,1.06,4},{517.6,2487.0,1.48,4},{491.8,2494.2,1.24,4},{480.2,2498.9,0.86,4},{477.6,2503.7,1.46,4},{465.9,2507.4,0.93,4},{454.2,2506.3,1.07,4},{433.6,2510.8,1.18,4},
		{423.1,2510.7,0.92,4},{413.6,2510.1,0.86,4},{407.1,2517.3,0.99,4},{381.8,2517.6,1.02,4},{369.3,2515.5,1.25,4},{350.0,2512.4,1.03,4},{284.2,2526.8,1.07,4},{275.0,2528.4,0.99,4},
		{263.2,2531.1,1.47,4},{249.7,2529.7,1.34,4},{244.6,2529.9,0.93,4},{233.5,2528.3,0.89,4},{224.0,2531.0,1.02,4},{209.1,2530.2,1.46,4},{197.1,2536.1,1.01,4},{153.9,2524.1,1.08,4},
		{148.0,2527.3,1.43,4},{134.3,2530.6,1.44,4},{106.2,2526.8,1.16,4},{85.6,2533.6,1.38,4},{76.8,2541.5,1.48,4},{52.2,2544.1,1.34,4},{32.4,2543.0,1.43,4},{15.5,2543.4,1.14,4},
		{7.0,2547.0,1.36,4},{-11.4,2548.8,1.12,4},{-21.2,2547.1,1.11,4},{-28.8,2538.7,1.23,4},{-48.6,2538.8,1.32,4},{-54.8,2540.5,1.1,4},{-65.7,2540.5,1.27,4},{-75.5,2539.9,1.3,4},
		{-87.1,2541.3,0.82,4},{-107.1,2542.9,1.12,4},{-119.4,2540.8,1.04,4},{-137.2,2546.4,0.96,4},{-168.6,2550.5,1.34,4},{-192.9,2555.5,0.88,4},{-196.4,2554.3,1.37,4},{-208.7,2514.2,0.82,4},
		{-206.5,2499.8,1.26,4},{-212.1,2502.9,1.06,4},{-228.0,2514.1,1.13,4},{-253.3,2533.2,1.21,4},{-262.6,2534.5,1.17,4},{-287.7,2540.0,1.32,4},{-295.3,2541.0,1.23,4},{-309.4,2541.6,1.27,4},
		{-316.0,2536.7,1.16,4},{-335.7,2534.0,0.99,4},{-344.8,2531.5,1.21,4},{-376.3,2529.0,1.33,4},{-393.4,2547.3,1.45,4},{-399.4,2552.9,0.94,4},{-406.2,2561.6,1.0,4},{-428.4,2559.8,0.97,4},
		{-419.8,2535.0,1.21,4},{-429.9,2524.9,1.28,4},{-427.7,2541.6,1.46,4},{-435.2,2548.4,0.88,4},{-442.3,2549.1,1.36,4},{-460.4,2545.1,0.96,4},{-470.0,2548.6,1.39,4},{-480.5,2544.1,1.12,4},
		{-503.5,2539.8,1.24,4},{-514.0,2543.5,1.11,4},{-520.4,2548.9,1.31,4},{-546.5,2547.1,0.95,4},{-559.1,2542.1,1.42,4},{-568.9,2545.8,1.32,4},{-575.3,2542.4,0.83,4},{-586.0,2543.5,0.8,4},
		{-593.9,2542.9,0.83,4},{-607.4,2541.1,1.14,4},{-652.7,2536.5,0.99,4},{-663.0,2535.5,1.49,4},{-673.9,2538.3,1.08,4},{-711.2,2536.5,1.33,4},{-718.3,2531.6,0.82,4},{-731.4,2522.8,1.49,4},
		{-741.1,2522.3,0.95,4},{-764.7,2519.4,1.38,4},{-777.0,2520.1,0.83,4},{-783.9,2518.2,1.08,4},{-791.3,2519.5,1.32,4},{-802.2,2520.1,0.98,4},{-817.1,2514.7,0.96,4},{-817.6,2506.5,1.21,4},
		{-816.6,2483.8,1.41,4},{-816.4,2473.9,1.09,4},{-818.7,2449.4,0.94,4},{-832.4,2452.9,1.32,4},{-840.8,2449.7,1.41,4},{-849.5,2444.8,1.47,4},{-866.8,2447.8,1.11,4},{-893.2,2441.4,1.0,4},
		{-909.2,2433.2,1.0,4},{-925.5,2460.9,1.24,4},{-927.5,2482.7,1.08,4},{-940.6,2495.4,1.26,4},{-946.2,2490.5,1.02,4},{-958.0,2488.8,1.07,4},{-970.0,2487.5,1.3,4},{-995.4,2476.4,1.36,4},
		{-999.1,2484.4,0.82,4},{-1009.7,2481.5,1.26,4},{-1019.7,2480.8,1.34,4},{-1023.6,2479.2,1.15,4},{-1035.4,2474.1,1.16,4},{-1045.4,2471.0,1.48,4},{-1058.1,2465.7,0.89,4},{-1070.9,2464.1,1.44,4},
		{-1080.0,2460.1,1.4,4},{-1091.7,2454.1,1.41,4},{-1105.8,2452.5,1.38,4},{-1109.3,2446.9,1.12,4},{-1120.3,2441.8,1.46,4},{-1153.7,2431.6,0.93,4},{-1160.8,2428.1,1.24,4},{-1166.1,2426.8,1.29,4},
		{-1204.4,2417.2,1.34,4},{-1207.7,2411.6,1.32,4},{-1232.8,2404.5,1.36,4},{-1237.9,2401.7,0.88,4},{-1249.7,2397.9,1.18,4},{-1284.7,2390.1,1.38,4},{-1294.9,2390.4,0.86,4},{-1303.5,2382.6,1.36,4},
		{-1308.6,2381.3,1.36,4},{-1318.2,2380.3,1.31,4},{-1330.0,2378.1,1.03,4},{-1336.9,2379.7,1.0,4},{-1391.3,2365.8,1.19,4},{-1401.3,2364.1,1.5,4},{-1404.8,2354.5,1.13,4},{-1399.4,2336.2,1.2,4},
		{-1391.4,2313.5,0.8,4},{-1406.8,2314.7,1.28,4},{-1414.8,2312.5,1.21,4},{-1426.6,2318.4,0.86,4},{-1447.2,2321.6,1.42,4},{-1460.0,2320.9,1.23,4},{-1466.4,2320.2,1.07,4},{-1487.7,2312.3,1.4,4},
		{-1497.4,2311.9,1.08,4},{-1505.9,2303.2,1.42,4},{-1516.9,2297.6,1.3,4},{-1526.2,2292.3,0.9,4},{-1533.1,2285.7,1.43,4},{-1541.6,2280.0,1.05,4},{-1551.0,2272.5,1.42,4},{-1580.0,2283.4,1.45,4},
		{-1587.2,2269.4,1.46,4},{-1598.2,2257.1,0.95,4},{-1602.4,2275.4,1.16,4},{-1618.7,2290.5,0.99,4},{-1624.9,2285.3,1.0,4},{-1641.1,2283.8,1.48,4},{-1662.7,2275.0,1.15,4},{-1672.5,2271.8,1.27,4},
		{-1677.9,2267.3,0.85,4},{-1692.1,2267.6,1.31,4},{-1711.4,2255.5,1.31,4},{-1727.4,2253.2,1.28,4},{-1738.2,2251.6,1.18,4},{-1747.8,2247.6,1.04,4},{-1758.0,2244.5,1.41,4},{-1767.2,2237.6,1.33,4},
		{-1779.9,2233.4,1.45,4},{-1785.7,2227.6,0.94,4},{-1792.1,2228.2,0.9,4},{-1800.5,2223.3,1.11,4},{-1807.7,2219.2,1.06,4},{-1816.6,2217.1,1.48,4},{-1823.1,2216.4,1.14,4},{-1855.0,2206.2,0.84,4},
		{-1876.9,2191.1,0.86,4},{-1872.9,2185.3,1.42,4},{-1861.6,2144.8,0.96,4},{-1867.6,2136.2,1.42,4},{-1880.2,2129.8,0.81,4},{-1889.4,2128.0,1.45,4},{-1896.2,2126.0,1.47,4},{-1901.7,2118.9,1.25,4},
		{-1911.8,2133.6,0.86,4},{-1916.6,2144.7,1.4,4},{-1927.3,2154.4,0.88,4},{-1929.8,2168.9,1.2,4},{-1937.8,2177.0,1.26,4},{-1997.9,2144.2,1.22,4},{-2004.4,2144.4,1.32,4},{-2010.3,2134.2,1.34,4},
		{-2023.1,2130.8,0.83,4},{-2030.1,2130.4,0.82,4},{-2037.1,2120.7,1.21,4},{-2046.2,2116.7,1.02,4},{-2053.9,2113.9,0.94,4},{-2082.5,2091.3,1.13,4},{-2088.4,2087.0,0.94,4},{-2094.2,2079.5,1.42,4},
		{-2102.4,2077.8,1.33,4},{-2118.7,2072.7,1.41,4},{-2135.9,2063.2,1.18,4},{-2140.8,2058.9,1.21,4},{-2193.4,2026.4,1.18,4},{-2204.2,2021.0,1.46,4},{-2216.9,2009.0,1.44,4},{-2245.5,1986.9,0.97,4},
		{-2254.8,1983.7,0.84,4},{-2286.4,1959.2,1.36,4},{-2300.2,1935.7,1.28,4},{-2285.5,1917.0,0.92,4},{-2276.6,1904.2,0.98,4},{-2274.3,1899.8,0.92,4},{-2294.5,1901.6,1.23,4},{-2313.3,1898.4,1.37,4},
		{-2338.6,1892.5,1.42,4},{-2372.6,1875.4,1.45,4},{-2380.3,1866.8,1.32,4},{-2387.8,1861.7,1.14,4},{-2400.3,1846.1,1.08,4},{-2406.5,1838.1,0.87,4},{-2419.7,1821.1,1.0,4},{-2441.2,1823.2,1.01,4},
		{-2454.3,1826.2,1.24,4},{-2461.9,1824.8,1.33,4},{-2472.2,1828.1,0.91,4},{-2465.0,1799.2,1.26,4},{-2477.4,1793.7,0.91,4},{-2487.6,1785.8,1.34,4},{-2499.0,1778.6,0.8,4},{-2510.0,1769.4,0.81,4},
		{-2512.6,1772.9,1.45,4},{-2523.5,1764.2,1.02,4},{-2532.9,1757.2,0.87,4},{-2536.6,1753.3,0.91,4},{-2548.3,1743.9,0.99,4},{-2554.7,1736.6,1.28,4},{-2560.8,1730.4,1.38,4},{-2594.1,1693.2,1.11,4},
		{-2611.2,1668.8,1.24,4},{-2618.9,1663.8,0.81,4},{-2639.2,1644.5,1.22,4},{-2649.7,1633.7,1.26,4},{-2672.0,1607.6,1.23,4},{-2684.9,1600.7,1.32,4},{-2690.1,1591.6,1.36,4},{-2696.5,1584.4,1.09,4},
		{-2700.3,1575.8,1.07,4},{-2711.7,1550.8,1.13,4},{-2732.5,1526.4,1.33,4},{-2741.2,1523.6,1.28,4},{2253.1,2437.9,0.92,4},{2249.3,2416.6,0.94,4},{2243.0,2422.2,1.19,4},{2244.2,2432.5,0.86,4},
		{1076.8,2373.5,1.09,4},{1074.2,2358.0,1.09,4},{1072.3,2354.1,0.87,4},{1072.3,2370.7,0.94,4},{-1580.9,2231.4,1.49,4},{-1591.3,2237.2,0.91,4},{2235.3,1132.8,1.95,2},{2267.7,1177.4,1.86,2},
		{2424.4,1512.1,1.58,2},{2328.6,1056.4,1.08,1},{2497.6,1644.4,1.59,2},{2534.4,1901.4,1.48,1},{2409.9,1461.0,1.08,1},{2516.3,1720.0,1.19,1},{2357.7,1407.3,1.06,1},{2291.1,1203.7,1.52,1},
		{2544.5,1803.5,1.53,1},{2393.2,1205.3,1.13,1},{2546.8,1893.6,1.64,2},{2207.1,985.4,1.82,2},{2376.6,1244.3,1.27,2},{2922.5,1944.1,1.76,2},{2595.0,1796.8,1.49,1},{2482.7,1554.6,1.59,2},
		{2171.3,927.3,1.13,1},{2622.8,1830.5,1.47,2},{2546.3,1762.6,1.22,1},{2438.5,1222.1,1.17,1},{2435.5,1452.9,1.83,2},{2270.1,1214.7,1.54,2},{2745.8,1879.5,1.8,2},{2140.3,949.7,1.84,2},
		{2401.0,1483.7,1.51,2},{2567.9,1770.0,1.38,1},{2132.0,971.9,1.53,2},{2196.6,1069.7,1.23,1},{2459.8,1392.9,1.49,1},{2180.4,961.4,1.48,1},{2293.6,1257.0,1.1,1},{2382.6,1221.2,1.55,2},
		{2161.6,906.7,1.13,1},{2299.2,1280.4,1.08,1},{2367.5,1194.1,1.6,2},{2417.1,1322.5,1.45,2},{2178.2,993.1,1.55,2},{2439.7,1258.3,1.27,1},{2287.7,990.3,1.44,2},{2437.4,1556.2,1.38,2},
		{2213.2,1077.9,1.45,2},{2423.5,1477.6,1.35,2},{2488.9,1533.5,1.57,1},{2543.1,1692.0,1.32,1},{2326.2,1313.6,1.64,2},{2433.5,1198.6,1.89,2},{2380.5,1304.0,1.2,1},{2209.5,1036.0,1.18,1},
		{2345.2,1224.3,1.66,2},{2198.3,944.6,1.23,1},{2458.6,1484.0,1.68,2},{2327.2,1177.6,1.71,2},{2030.3,887.3,1.25,1},{2390.1,1455.8,1.06,1},{2450.3,1605.1,1.47,2},{2232.9,1087.4,1.91,2},
		{2403.1,1445.8,1.38,1},{2219.8,1096.5,1.45,1},{2284.6,1052.8,1.99,2},{2365.1,1311.7,1.22,1},{2263.3,1101.0,1.67,2},{2012.5,880.6,1.45,2},{2624.0,1784.3,1.43,2},{2348.6,1250.1,1.51,1},
		{2566.2,1711.6,1.03,1},{2599.8,1857.9,1.11,1},{2246.1,1071.0,1.64,2},{2731.7,1885.6,1.88,2},{2263.9,987.7,1.44,1},{2323.1,1355.3,1.47,1},{2277.9,1105.5,1.34,2},{2447.3,1536.6,1.59,2},
		{2365.0,1354.5,1.4,1},{2577.5,1787.4,1.1,1},{2130.9,933.8,1.53,1},{2450.2,1588.1,1.25,2},{2448.7,1242.0,1.24,1},{1860.5,877.2,1.07,1},{2602.3,1836.2,1.51,1},{2470.5,1438.8,1.97,2},
		{2516.6,1600.7,1.34,1},{2093.6,918.0,1.57,1},{1882.4,864.8,1.91,2},{2606.3,1786.6,1.27,2},{2255.4,1138.5,1.12,1},{2513.7,1661.4,1.55,1},{2374.4,1131.2,1.15,1},{2322.5,1110.3,1.28,2},
		{2621.3,1802.0,1.67,2},{2353.7,1208.6,1.13,1},{2574.3,1842.1,1.35,2},{2428.9,1404.0,1.44,2},{2586.8,1718.7,1.42,2},{2564.6,1805.4,1.49,2},{2175.8,1039.6,1.56,1},{2450.3,1623.5,1.36,1},
		{2279.1,1067.9,1.33,2},{2494.1,1584.0,1.43,1},{2283.3,1021.4,1.46,2},{2223.1,1062.1,1.58,1},{2391.1,1416.5,1.37,2},{2223.8,994.5,1.29,2},{2309.6,1146.1,1.48,1},{2235.0,955.8,1.05,1},
		{2109.6,950.2,1.71,2},{2358.2,1160.2,1.91,2},{2468.5,1538.2,1.19,1},{2584.0,1760.3,1.51,2},{2219.0,975.1,1.21,1},{2272.0,1156.0,1.8,2},{2411.1,1429.0,1.32,2},{2516.1,1742.1,1.44,1},
		{2560.1,1750.2,1.53,1},{2393.1,1239.3,1.44,1},{2380.0,1111.1,1.49,1},{2332.1,1298.8,1.02,1},{2444.1,1397.7,1.37,2},{2346.0,1329.2,1.09,1},{2175.8,913.0,1.33,1},{2423.3,1374.2,1.44,2},
		{2484.0,1836.7,1.71,2},{2417.8,1202.7,1.81,2},{2375.4,1330.4,1.54,1},{2426.3,1353.4,1.67,2},{2592.2,1740.3,1.05,1},{2270.9,1005.7,1.88,2},{2263.7,1230.5,1.36,2},{2417.7,1170.6,1.8,2},
		{2123.0,911.8,1.22,1},{2474.9,1609.2,1.42,1},{2418.9,1340.7,1.03,1},{2448.9,1294.8,1.2,1},{2645.9,1785.3,1.48,2},{2571.0,1824.3,2.0,2},{2239.6,1042.9,1.89,2},{2083.9,898.7,1.45,2},
		{2672.5,1876.2,1.18,1},{2390.1,1373.1,1.25,1},{2388.0,1285.2,1.37,2},{2464.7,1419.3,1.19,1},{2660.1,1820.5,1.5,1},{2487.0,1655.8,1.26,2},{2328.2,1338.4,1.09,1},{2288.7,1229.4,1.17,1},
		{2539.0,1779.8,1.27,1},{2152.5,1008.1,1.25,1},{2327.4,1221.8,1.69,2},{2293.3,1041.0,1.09,1},{2394.5,1357.1,1.83,2},{2473.3,1490.5,1.26,2},{2447.0,1373.0,1.82,2},{2367.4,1292.7,1.39,1},
		{2377.6,1179.1,1.79,2},{2351.1,1082.9,1.31,2},{2261.7,1080.8,1.2,1},{2436.3,1417.2,1.05,1},{2312.7,1253.0,1.34,2},{2325.8,1095.6,1.74,2},{2248.4,1010.2,1.44,1},{2430.2,1310.7,1.73,2},
		{2450.6,1550.9,1.94,2},{2511.3,1682.0,1.2,1},{2172.6,978.6,1.47,1},{2464.9,1555.8,1.26,2},{2287.0,1171.7,1.16,1},{2516.2,1624.7,1.66,2},{2313.6,1192.7,1.39,2},{2404.5,1342.6,1.62,2},
		{2400.2,1317.1,1.35,2},{2383.1,1401.6,1.83,2},{2172.4,948.7,1.6,1},{2281.6,1140.3,1.03,1},{2435.7,1330.7,1.5,2},{2509.8,1883.4,1.55,2},{2101.6,903.6,1.74,2},{2246.5,981.7,1.81,2},
		{2530.4,1816.9,1.48,2},{2420.3,1222.5,1.43,1},{2378.2,1086.2,1.89,2},{2157.3,957.6,1.42,2},{2191.4,1035.3,1.84,2},{2340.3,1170.9,1.3,2},{2050.2,901.5,1.8,2},{2155.3,925.0,1.29,2},
		{2270.0,1117.9,1.43,1},{2229.3,1025.4,1.41,2},{2365.1,1254.2,1.22,1},{2500.7,1839.2,1.75,2},{2405.4,1263.5,1.2,1},{2563.7,1685.9,1.71,2},{2401.6,1502.2,1.46,1},{2158.6,979.9,1.79,2},
		{2299.9,1135.7,1.63,2},{2399.2,1402.5,1.31,2},{2304.6,1320.1,1.9,2},{2318.3,1285.5,1.46,2},{2433.0,1294.2,1.56,2},{2281.9,1091.3,1.03,1},{2530.0,1711.2,1.57,1},{2714.3,1864.3,1.58,2},
		{2352.9,1186.9,1.59,1},{2314.8,1085.3,1.7,2},{2542.3,1723.4,1.54,1},{2432.8,1526.2,1.41,2},{2551.0,1707.6,1.96,2},{2226.2,936.0,1.32,2},{2344.6,1310.7,1.58,1},{2066.8,921.0,1.55,2},
		{2149.4,991.4,1.51,2},{2186.4,926.4,1.21,1},{2208.2,1005.2,1.44,2},{1747.5,847.7,1.05,4},{1808.7,858.9,1.0,4},{1821.1,858.2,1.11,4},{1829.3,861.9,1.17,4},{1835.1,868.5,1.42,4},
		{1840.1,882.9,1.1,4},{1855.5,895.2,1.4,4},{1863.6,898.2,1.28,4},{1875.8,900.5,1.17,4},{1888.1,897.4,1.22,4},{1890.8,865.8,1.1,4},{1880.2,865.2,1.17,4},{1854.5,860.2,1.4,4},
		{1846.6,857.4,1.37,4},{1831.1,859.3,1.36,4},{1807.1,858.1,0.84,4},{1802.9,856.0,1.36,4},{1931.8,865.0,1.03,4},{1943.1,872.2,1.44,4},{1953.2,876.6,1.37,4},{1964.7,876.4,1.17,4},
		{1973.5,880.3,0.85,4},{1979.3,883.2,1.33,4},{2002.0,885.3,0.84,4},{2021.1,892.8,1.32,4},{2028.7,895.8,1.47,4},{2032.6,899.2,0.92,4},{2046.1,907.0,0.95,4},{2067.3,922.2,1.17,4},
		{2074.7,928.5,1.09,4},{2083.8,937.9,0.93,4},{2083.5,939.4,1.39,4},{2097.5,941.0,1.03,4},{2103.0,954.2,0.93,4},{2117.4,972.9,1.12,4},{2123.0,977.7,0.86,4},{2129.2,1005.0,1.46,4},
		{2142.9,1025.5,0.83,4},{2147.4,1029.5,1.13,4},{2168.1,1042.3,1.3,4},{2174.4,1050.6,1.09,4},{2180.9,1067.9,1.38,4},{2189.2,1075.3,1.38,4},{2203.9,1112.0,0.85,4},{2219.0,1135.9,1.16,4},
		{2223.9,1141.4,0.86,4},{2231.6,1155.7,0.93,4},{2238.2,1167.4,1.37,4},{2262.5,1228.7,1.34,4},{2261.7,1232.8,1.26,4},{2282.5,1267.2,1.48,4},{2288.0,1287.8,1.12,4},{2291.5,1296.5,1.49,4},
		{2295.0,1302.9,1.46,4},{2297.9,1312.0,1.1,4},{2308.3,1321.7,1.08,4},{2316.9,1339.2,0.82,4},{2320.4,1354.9,0.83,4},{2323.1,1362.4,1.11,4},{2333.7,1363.3,1.45,4},{2344.3,1388.6,1.28,4},
		{2366.0,1426.2,1.03,4},{2372.7,1434.9,1.14,4},{2375.4,1443.9,1.33,4},{2378.4,1455.7,0.99,4},{2385.5,1471.8,0.91,4},{2392.5,1481.7,1.35,4},{2395.2,1490.1,1.06,4},{2406.4,1511.0,1.15,4},
		{2409.3,1520.2,1.5,4},{2413.8,1527.9,1.41,4},{2423.5,1542.8,1.15,4},{2423.6,1556.6,1.12,4},{2420.7,1568.1,1.46,4},{2433.7,1586.1,1.1,4},{2436.2,1591.4,0.92,4},{2440.7,1599.4,1.14,4},
		{2450.8,1623.0,1.34,4},{2455.4,1632.5,1.12,4},{2457.6,1642.4,0.83,4},{2470.1,1642.3,0.96,4},{2476.8,1653.5,1.23,4},{2489.0,1679.7,0.99,4},{2499.3,1698.0,1.38,4},{2508.9,1727.8,1.48,4},
		{2513.8,1738.3,0.92,4},{2519.6,1748.2,0.81,4},{2520.8,1758.3,1.36,4},{2528.4,1779.4,1.25,4},{2539.8,1802.3,1.09,4},{2530.6,1809.9,0.89,4},{2516.0,1814.1,1.29,4},{2510.6,1819.2,0.91,4},
		{2501.9,1820.3,1.38,4},{2497.1,1823.6,1.32,4},{2487.0,1830.6,1.24,4},{2480.3,1833.8,0.93,4},{2480.9,1843.4,1.29,4},{2488.5,1856.9,1.49,4},{2518.9,1838.5,0.92,4},{2525.7,1833.6,1.36,4},
		{2543.4,1826.3,0.83,4},{2548.6,1833.0,1.22,4},{2563.0,1838.5,0.8,4},{2569.5,1844.7,1.14,4},{2585.1,1857.9,1.18,4},{2590.4,1863.0,1.2,4},{2585.2,1871.0,1.26,4},{2583.5,1886.7,0.86,4},
		{2576.8,1895.4,1.07,4},{2577.0,1902.5,1.48,4},{2567.2,1917.7,1.01,4},{2583.7,1916.9,0.92,4},{2590.5,1899.2,0.83,4},{2591.7,1891.8,1.28,4},{2594.1,1878.7,0.89,4},{2608.4,1867.3,0.96,4},
		{2625.3,1869.7,1.22,4},{2645.8,1877.3,1.01,4},{2650.7,1882.2,0.98,4},{2662.9,1884.1,1.39,4},{2685.9,1887.3,0.87,4},{2689.7,1890.3,1.31,4},{2728.6,1899.4,0.98,4},{2749.4,1901.2,1.44,4},
		{2767.9,1908.7,0.9,4},{2778.1,1910.5,0.9,4},{2800.6,1915.6,1.1,4},{2827.4,1924.1,1.08,4},{2835.0,1928.0,1.13,4},{2857.9,1929.4,1.38,4},{2876.3,1934.0,1.19,4},{2888.9,1938.8,1.38,4},
		{2909.0,1940.6,1.04,4},{2919.8,1944.7,1.14,4},{2927.8,1945.2,1.17,4},{2928.4,1944.8,1.46,4},{2912.9,1942.7,1.12,4},{2905.3,1938.8,0.9,4},{2894.3,1936.1,1.05,4},{2881.3,1938.0,0.86,4},
		{2870.0,1929.5,1.36,4},{2816.9,1914.2,1.12,4},{2807.8,1907.6,1.2,4},{2792.7,1898.8,1.24,4},{2771.1,1883.8,1.08,4},{2746.2,1866.6,1.47,4},{2736.8,1858.9,0.89,4},{2730.8,1853.9,0.9,4},
		{2693.6,1822.9,0.82,4},{2689.9,1818.0,1.33,4},{2678.7,1809.7,0.93,4},{2670.9,1801.0,1.08,4},{2662.5,1795.5,0.81,4},{2659.5,1789.6,0.85,4},{2651.8,1781.7,0.96,4},{2591.7,1722.1,1.49,4},
		{2587.5,1710.2,1.25,4},{2565.6,1687.7,1.24,4},{2558.6,1680.5,0.94,4},{2540.5,1645.7,1.05,4},{2527.7,1620.2,0.97,4},{2508.1,1578.0,1.47,4},{2497.6,1553.4,1.24,4},{2494.2,1538.3,0.9,4},
		{2495.5,1532.5,1.2,4},{2482.8,1497.9,1.32,4},{2478.9,1476.3,1.28,4},{2475.2,1465.4,1.47,4},{2472.0,1445.7,1.02,4},{2469.8,1409.5,1.19,4},{2458.3,1330.9,1.43,4},{2457.2,1324.1,1.43,4},
		{2457.2,1311.1,0.86,4},{2457.0,1284.7,0.85,4},{2450.4,1275.8,1.37,4},{2449.7,1264.3,1.44,4},{2446.8,1240.4,0.91,4},{2445.9,1227.5,1.32,4},{2445.1,1207.0,1.31,4},{2441.0,1197.9,1.13,4},
		{2437.0,1188.5,0.95,4},{2434.0,1172.4,1.13,4},{2422.1,1148.2,1.42,4},{2416.1,1137.6,1.31,4},{2402.6,1118.4,0.98,4},{2401.6,1111.1,0.82,4},{2389.2,1092.7,1.29,4},{2363.8,1069.2,0.96,4},
		{2358.2,1057.9,0.83,4},{2332.4,1034.0,1.07,4},{2321.4,1025.2,1.08,4},{2308.8,1011.7,0.89,4},{2300.0,1005.2,1.09,4},{2294.7,1000.4,1.25,4},{2291.2,992.3,0.99,4},{2269.5,970.9,1.5,4},
		{2227.7,932.3,1.2,4},{2217.2,927.2,1.33,4},{2210.3,923.5,0.83,4},{2202.5,921.6,1.5,4},{2193.0,917.1,1.09,4},{2180.2,909.7,1.25,4},{2160.9,900.4,1.1,4},{2145.4,894.3,1.4,4},
		{2124.0,889.0,1.01,4},{2105.7,887.1,1.03,4},{2067.0,879.5,1.09,4},{2052.4,878.8,1.27,4},{2036.8,875.9,0.89,4},{2026.2,879.7,1.19,4},{1983.6,873.6,1.2,4},{1961.9,871.1,1.07,4},
		{1943.2,869.3,1.37,4},{2526.4,1865.8,1.16,4},{2513.7,1875.9,1.04,4},{2504.4,1884.9,1.37,4},{2512.0,1883.3,1.36,4},{2545.7,1884.2,1.36,4},{2536.5,1894.5,1.23,4},{2529.7,1902.3,1.42,4},
		{2534.2,1910.1,1.23,4},{2543.9,1905.6,1.39,4},{2544.7,1897.3,1.11,4},{2550.1,1890.0,1.45,4},{2556.8,1871.2,1.44,4},{2976.8,2204.3,1.76,2},{2970.6,2208.9,1.33,4},{2971.6,2213.7,1.19,4},
		{2980.5,2207.2,1.18,4},{2031.5,2418.1,1.56,2},{2024.9,2417.4,0.84,4},{2025.2,2423.7,0.85,4},{898.2,2353.6,1.36,1},{897.0,2357.6,1.14,4},{897.2,2359.8,1.46,4},{-425.5,2488.0,1.43,1},
		{-428.0,2481.4,1.02,4},{-423.7,2491.2,1.05,4},{-415.2,2486.8,1.46,4},{-2438.9,1751.1,1.49,1},{-2445.8,1752.5,1.13,4},{-2436.6,1756.7,1.11,4},{-2437.2,1749.6,1.08,4},{-1.2,2284.2,0.81,1},
		{-165.8,2286.0,0.64,1},{150.6,2240.7,0.86,1},{278.0,2280.9,1.01,1},{-30.6,2250.2,1.27,3},{-51.7,2250.5,0.83,4},{54.2,2248.7,0.95,3},{-129.0,2042.9,0.7,1},{-125.6,1984.8,0.86,1},
		{80.6,1955.5,0.89,1},{289.8,1982.2,0.75,1},{383.8,2013.8,0.82,1},{226.4,2081.4,0.75,1},{71.5,2058.3,0.8,3},{89.5,2047.5,0.82,3},{72.2,2040.2,1.1,4},{94.4,2034.9,1.16,4},
		{102.2,2025.4,0.82,4},{72.6,2033.3,1.29,4},{110.2,2014.4,1.15,1},{92.6,2003.5,1.01,1},{110.9,1984.8,1.1,4},{139.5,2030.8,1.09,4},{5.3,2002.0,1.26,1},{-4.1,1989.3,1.17,1},
		{21.5,1995.2,1.13,3},{17.6,2012.8,0.95,1},{-30.3,2007.0,1.0,4},{198.0,1970.1,1.06,1},{209.5,1978.4,0.88,3},{232.3,2015.3,0.93,1},{230.3,1994.8,0.85,3},{211.1,2006.7,1.11,1},
		{189.0,1991.4,1.24,4},{202.6,2025.8,0.8,1},{201.5,2013.0,0.92,1},{222.3,2050.5,1.08,3},{183.9,2021.3,1.06,3},{215.9,1985.4,1.22,4},{219.0,2013.9,0.83,4},{-36.8,1983.1,1.15,1},
		{-38.2,1998.3,1.15,3},{-60.6,2032.9,0.83,1},{-14.9,1997.0,0.95,1},{-56.1,2000.6,0.86,3},{-44.0,2012.4,0.91,3},{68.9,1986.5,1.3,3},{58.1,1988.6,1.3,1},{67.4,2002.8,0.87,1},
		{87.8,1982.5,0.83,1},{102.6,1989.4,0.92,4},{69.7,1991.9,1.24,4},{31.6,1994.2,0.88,4},{243.1,2046.5,1.17,1},{251.6,1996.3,1.1,1},{275.3,1996.7,0.81,1},{254.2,2014.9,0.92,3},
		{257.4,1999.4,1.15,4},{284.5,2034.0,0.85,4},{296.7,2004.6,0.81,4},{280.7,2072.5,1.38,1},{352.4,2047.7,1.23,3},{349.3,2064.9,1.26,3},{-360.8,1529.0,0.6,1},{-810.9,2009.0,0.93,1},
		{-886.4,2002.5,0.99,1},{-886.2,1957.3,0.71,1},{-879.3,1829.6,0.9,1},{-867.8,1632.2,0.82,1},{-565.8,1580.5,1.14,3},{-584.1,1578.9,1.22,1},{-554.0,1586.1,0.94,4},{-583.0,1591.0,0.87,4},
		{-444.1,1580.9,1.11,1},{-441.6,1565.0,0.83,3},{-452.8,1554.1,1.01,1},{-868.4,1933.9,1.11,3},{-857.0,1936.9,1.15,1},{-854.9,1921.9,0.97,1},{-895.8,1908.4,1.06,4},{-801.4,1931.1,1.23,1},
		{-781.4,1943.7,1.04,1},{-787.8,1927.0,1.31,3},{-764.0,1939.4,0.88,1},{-767.7,1935.3,0.76,4},{-802.1,1908.2,0.84,4},{-842.5,1618.1,1.25,1},{-823.5,1595.6,1.1,3},{-843.8,1629.9,1.13,4},
		{-854.4,1808.5,1.24,3},{-836.6,1826.2,1.1,3},{-824.5,1784.1,1.3,4},{-842.0,1792.0,1.05,4},{-707.9,1592.2,0.9,1},{-679.2,1592.8,1.35,3},{-613.9,1574.1,1.26,1},{-618.0,1594.0,0.83,1},
		{-625.6,1575.3,1.0,1},{-566.5,1567.4,0.76,4},{-844.4,1862.5,1.29,3},{-829.7,1873.9,0.85,1},{-854.4,1868.7,0.81,1},{-823.7,1858.0,1.01,3},{-853.2,1891.5,1.14,1},{-820.3,1910.2,0.95,3},
		{-838.8,1916.9,0.77,4},{-808.9,1894.5,1.2,1},{-817.0,1885.5,0.82,1},{-825.4,1893.0,1.12,4},{-825.3,1907.3,1.24,4},{-757.8,1983.4,1.12,3},{-756.9,1995.1,1.26,3},{-593.4,1601.3,0.85,1},
		{-594.0,1613.3,1.32,3},{-615.0,1598.8,0.76,4},{-538.5,1587.0,1.1,1},{-529.5,1596.2,1.26,3},{-528.8,1579.4,1.09,3},{-512.5,1613.6,1.25,1},{-834.8,1887.0,1.28,1},{-848.3,1910.2,0.82,3},
		{-839.6,1898.1,1.17,4},{-842.4,1892.4,1.0,4},{-607.4,2043.8,1.13,3},{-571.6,2023.1,0.98,1},{-588.5,1995.8,0.82,1},{-595.1,2022.2,1.07,1},{-601.1,2063.8,1.18,1},{-725.8,1616.8,0.84,3},
		{-711.8,1609.4,1.19,1},{-728.5,1596.1,1.07,1},{-780.9,1605.3,1.21,4},{-756.7,1854.3,0.96,1},{-729.7,1845.1,0.96,1},{-757.8,1828.9,1.07,1},{-736.3,1830.5,0.9,1},{-729.3,1881.5,0.94,1},
		{-742.2,1869.0,0.89,4},{-745.2,1849.3,0.82,4},{-547.3,1601.2,1.32,3},{-560.0,1600.3,0.9,3},{-763.5,1651.1,0.85,3},{-793.4,1613.6,1.01,1},{-799.0,1645.0,0.82,1},{-776.9,1622.4,1.25,1},
		{-796.3,1622.1,0.89,4},{-616.8,2018.0,1.16,1},{-588.0,2056.4,0.91,1},{-588.9,2015.8,0.76,4},{-610.1,2025.5,1.18,4},{-621.8,2059.3,0.85,4},{-774.5,1729.9,1.22,1},{-785.8,1701.7,0.84,3},
		{-786.7,1690.1,1.14,3},{-764.1,1710.9,1.13,3},{-763.6,1716.1,0.72,4},{-772.6,1706.8,0.98,4},{-779.2,1699.4,0.83,4},{-747.9,1695.5,0.95,4},{-701.4,1967.2,1.1,1},{-700.4,1987.6,1.27,1},
		{-713.0,1979.1,0.88,1},{-724.8,1980.8,1.27,3},{-681.7,1978.2,1.04,4},{-686.3,1995.8,1.14,4},{-676.4,1975.4,1.22,4},{-456.7,1992.2,1.09,3},{-450.7,2003.6,1.02,3},{-462.3,2003.3,1.04,3},
		{-487.4,2007.7,1.03,4},{-444.1,1989.5,0.87,4},{-661.4,2062.1,1.39,3},{-773.9,1783.0,1.2,3},{-797.2,1763.3,1.14,1},{-305.3,1577.7,0.92,3},{-787.8,1800.1,1.06,1},{-732.2,1659.4,0.96,1},
		{-523.1,2022.0,1.15,3},{-522.1,1975.0,0.93,3},{-395.8,1588.2,1.36,1},{-358.7,2003.4,1.32,3},{-849.2,1776.1,1.3,1},{-797.7,1588.0,0.95,3},{-213.5,1189.1,0.66,1},{-160.7,1168.3,1.13,1},
		{-158.5,1189.5,1.32,1},{-186.7,1169.2,1.25,3},{-156.8,1140.4,0.84,4},{-178.4,1284.0,1.27,1},{-27.8,1098.4,1.09,3},{-41.0,1104.7,0.81,3},{-321.1,1132.5,0.89,3},{-184.2,106.0,0.97,1},
		{-187.8,26.0,0.73,1},{-177.4,-54.8,0.99,1},{-101.9,92.8,1.15,3},{-116.3,86.2,0.98,1},{-130.3,80.5,1.14,1},{-103.4,105.7,1.11,3},{-109.0,101.4,1.01,4},{-109.0,132.0,0.83,1},
		{-121.6,150.3,1.13,3},{-126.2,144.5,0.85,4},{-141.4,123.7,0.88,3},{-139.1,115.6,1.06,4},{679.3,-1660.8,0.61,1},{609.9,-1643.1,0.83,1},{480.1,-1641.1,0.78,1},{455.1,-1664.2,0.65,1},
		{689.6,-1744.3,1.05,3},{663.8,-1756.7,1.05,1},{686.2,-1712.6,1.15,1},{693.0,-1692.3,1.24,4},{668.8,-1731.5,1.19,4},{687.3,-1726.9,1.01,4},{657.7,-1699.5,0.77,4},{697.7,-1707.4,1.06,4},
		{739.8,-1609.6,1.23,3},{1274.1,-2034.7,0.63,1},{936.7,-1951.8,0.64,1},{739.9,-1928.1,1.0,1},{670.8,-1903.3,0.7,1},{439.2,-1862.1,0.9,1},{521.9,-2065.3,0.73,1},{668.8,-2077.8,0.91,1},
		{952.2,-2121.1,0.67,1},{982.9,-2133.5,0.91,1},{1027.0,-2053.4,1.3,1},{1009.3,-2063.3,0.83,1},{1023.2,-2106.1,1.16,1},{1009.9,-2080.9,0.96,3},{1044.6,-2076.4,1.16,3},{992.3,-2069.7,1.13,4},
		{603.7,-1947.9,0.84,1},{633.3,-1963.8,0.89,1},{621.6,-1946.8,0.88,1},{632.8,-1983.2,0.87,3},{642.3,-1972.2,0.98,1},{637.8,-1945.7,1.14,3},{624.6,-1977.1,1.17,4},{1087.7,-2123.5,1.25,1},
		{1080.3,-2090.8,1.28,3},{1054.7,-2118.7,0.92,3},{1084.1,-2100.0,0.98,4},{1082.1,-2113.7,0.87,4},{1061.5,-2087.2,0.88,4},{1100.2,-2127.6,1.02,4},{1060.1,-2006.8,1.2,1},{1066.4,-2016.0,1.02,1},
		{1083.5,-2031.2,1.22,1},{1073.2,-2004.3,1.27,1},{1096.3,-2010.5,0.7,4},{682.6,-2028.6,1.14,1},{656.6,-2025.6,1.22,1},{666.3,-2032.1,0.88,1},{655.5,-2040.6,1.09,1},{679.3,-2011.6,0.95,4},
		{661.2,-2023.4,1.04,4},{708.2,-2009.2,0.72,4},{688.0,-2002.2,1.1,4},{492.3,-2042.6,0.86,3},{472.7,-2057.6,1.08,1},{489.6,-2054.2,1.17,3},{474.6,-2020.7,1.09,1},{460.4,-2053.2,0.94,3},
		{469.3,-2033.1,0.76,4},{688.7,-1957.1,1.04,1},{732.6,-1958.3,1.2,1},{727.1,-1969.1,1.27,3},{723.4,-1947.5,1.04,3},{727.0,-1984.0,0.98,4},{1215.8,-2147.6,0.98,1},{1219.7,-2171.0,0.88,1},
		{1196.1,-2174.0,0.95,1},{1209.0,-2157.2,1.34,1},{1135.2,-2047.8,0.87,1},{1130.7,-2059.1,1.2,3},{1150.6,-2051.5,1.25,1},{1131.1,-2033.6,0.92,3},{994.9,-2095.4,1.2,1},{1016.8,-2048.6,1.06,1},
		{1031.6,-2081.8,0.74,4},{1034.4,-2070.8,0.8,4},{987.2,-2080.7,0.77,4},{679.2,-1994.2,1.15,3},{646.6,-1996.4,1.0,1},{659.1,-1993.1,0.86,1},{646.0,-2007.4,1.19,1},{644.1,-2023.5,0.96,4},
		{672.9,-1962.0,0.89,4},{672.1,-2044.7,1.1,4},{830.9,-2008.3,0.87,3},{830.6,-1992.4,0.85,1},{851.4,-1970.2,1.12,1},{821.7,-2015.3,0.86,4},{1095.0,-2047.7,1.07,3},{1111.6,-2036.2,1.08,1},
		{588.7,-1992.7,0.88,1},{598.6,-1999.7,0.97,1},{597.5,-2018.6,1.28,3},{595.5,-2010.3,0.96,4},{586.4,-2017.9,1.1,4},{536.6,-1987.0,0.96,3},{556.9,-1988.0,1.18,1},{554.5,-2009.0,1.15,1},
		{524.3,-2010.2,0.71,4},{571.9,-1951.4,0.76,4},{550.4,-1988.6,0.87,4},{882.3,-2048.1,0.82,3},{935.4,-2037.9,1.15,1},{951.5,-2045.8,0.98,1},{915.1,-2054.0,1.24,3},{928.3,-2025.8,1.03,1},
		{930.1,-2059.6,1.2,1},{934.6,-2016.9,1.03,4},{923.4,-1978.2,0.89,1},{881.1,-1986.3,1.06,3},{925.0,-1994.8,1.35,3},{909.2,-2008.8,0.96,3},{921.1,-1987.1,1.08,4},{508.2,-1972.5,1.31,1},
		{472.9,-1973.3,0.97,1},{485.5,-1968.1,0.9,1},{493.5,-1984.8,1.08,3},{503.9,-1961.0,0.81,1},{514.7,-1961.9,1.02,4},{1283.2,-2127.9,1.17,3},{1277.1,-2100.8,0.96,3},{1277.4,-2125.7,1.13,4},
		{591.5,-1965.9,1.13,3},{601.1,-1985.9,1.17,1},{612.2,-1930.7,1.14,3},{625.2,-1929.7,0.83,4},{591.0,-1939.3,1.17,4},{700.4,-1984.8,0.91,1},{719.2,-2000.9,1.06,3},{721.0,-2022.3,1.29,3},
		{747.0,-2021.6,1.04,1},{706.1,-1997.7,1.16,3},{741.6,-2000.5,0.94,4},{758.0,-2044.6,1.06,1},{453.4,-1967.3,1.24,3},{539.9,-1913.5,1.35,1},{785.9,-2032.5,1.06,1},{1283.5,-2079.7,1.4,1},
		{1176.4,-2113.7,1.38,1},{1036.1,-2023.5,0.95,1},{447.1,-2007.2,1.07,3},{1220.4,-2120.5,1.03,1},{518.9,-1901.7,0.98,1},{-1701.1,1829.1,0.7,1},{-1634.0,1736.7,0.88,1},{-1595.2,1720.6,0.91,1},
		{-1624.5,1815.0,1.24,1},{-1598.5,1818.7,0.86,3},{-1611.4,1837.8,0.84,4},{-1619.9,1861.2,0.8,1},{-1597.0,1875.7,0.97,1},{-1616.1,1880.4,1.29,3},{-1590.8,1898.1,1.1,3},{-1548.0,1981.0,1.16,1},
		{-1538.3,1996.0,1.16,3},{-1540.8,1967.5,1.12,3},{-1567.0,1987.1,1.19,4},{-1531.9,1984.4,1.21,4},{-1582.1,1986.5,1.06,3},{-1584.4,1953.6,1.24,4},{-1623.9,1957.1,1.17,4},{-1570.7,1958.9,1.23,4},
		{-1748.2,1737.2,1.06,3},{-1674.4,1746.0,1.17,1},{-1917.8,1586.4,0.94,1},{-2353.6,1574.7,0.99,1},{-2384.8,1510.5,0.69,1},{-2484.6,1432.0,0.95,1},{-2494.7,1421.2,0.67,1},{-2239.2,1460.6,0.65,1},
		{-2107.4,1464.8,0.88,1},{-1987.5,1465.8,0.76,1},{-1920.2,1471.9,0.72,1},{-1863.5,1457.6,0.74,1},{-1812.2,1440.5,0.62,1},{-1767.9,1438.2,0.95,1},{-1637.3,1431.0,0.9,1},{-1585.0,1426.8,0.9,1},
		{-1961.7,1509.5,0.97,1},{-1973.8,1495.1,1.25,3},{-1972.0,1484.0,0.95,4},{-2338.2,1500.3,1.19,1},{-2305.6,1486.2,1.03,3},{-2310.3,1499.7,1.06,3},{-2323.1,1495.9,1.03,1},{-2333.3,1485.5,0.82,4},
		{-2259.5,1606.0,1.22,1},{-2246.0,1584.9,0.95,1},{-2227.2,1598.7,0.8,3},{-2264.4,1572.9,1.14,1},{-2240.6,1605.0,1.08,1},{-2203.5,1595.7,1.07,4},{-2255.6,1619.7,1.06,1},{-2251.0,1630.6,1.11,1},
		{-2188.1,1520.3,1.16,1},{-2187.2,1505.0,0.87,1},{-2206.2,1518.9,1.06,1},{-2201.0,1507.7,1.11,1},{-2192.8,1536.5,1.3,1},{-2193.5,1515.7,1.1,4},{-2192.0,1503.5,0.84,4},{-2177.1,1580.8,1.17,3},
		{-2214.2,1568.1,1.06,1},{-2220.2,1555.9,0.95,1},{-2232.9,1564.7,1.02,1},{-2224.9,1584.1,1.29,4},{-2197.5,1569.5,1.3,4},{-2236.0,1597.4,1.16,4},{-2252.2,1519.8,1.03,1},{-2228.9,1514.7,0.88,1},
		{-2224.4,1492.9,1.22,1},{-2216.9,1582.2,0.83,4},{-1835.3,1474.9,1.3,3},{-1806.7,1492.0,0.91,3},{-1768.2,1498.9,1.11,1},{-1803.7,1513.4,1.09,1},{-1805.1,1479.1,0.89,1},{-1824.8,1480.8,1.26,3},
		{-1863.0,1495.4,1.03,4},{-1881.6,1551.9,0.93,3},{-1884.4,1518.2,0.98,1},{-1861.9,1545.8,1.16,1},{-1892.9,1533.4,1.14,1},{-1904.1,1532.1,1.3,3},{-1886.3,1561.4,1.27,4},{-1908.6,1544.0,0.78,4},
		{-1889.1,1554.0,0.84,4},{-1927.3,1561.1,1.24,3},{-1914.8,1560.6,1.14,3},{-1938.9,1546.4,1.16,1},{-1939.5,1560.0,0.95,4},{-1930.8,1554.0,0.73,4},{-1943.8,1540.0,1.06,4},{-2085.6,1525.9,1.2,1},
		{-2103.0,1535.2,1.14,1},{-2085.1,1539.7,1.04,1},{-2059.9,1529.1,1.19,1},{-2054.3,1522.4,0.77,4},{-2073.9,1552.4,0.74,4},{-2068.0,1542.2,1.01,4},{-2110.3,1554.5,1.29,4},{-1920.2,1522.6,0.88,1},
		{-1893.1,1505.6,1.19,1},{-1880.3,1537.2,1.25,4},{-1924.5,1519.9,1.26,4},{-1915.1,1517.8,0.91,4},{-1826.1,1510.5,0.99,3},{-1838.8,1525.0,0.95,1},{-1852.5,1516.5,1.11,1},{-1793.3,1519.8,0.86,3},
		{-1865.0,1560.3,1.26,4},{-1841.8,1520.3,0.74,4},{-1857.6,1482.7,0.92,1},{-1871.7,1496.1,0.92,4},{-1823.6,1496.1,1.24,4},{-2265.9,1650.8,1.2,1},{-2030.1,1582.3,1.25,1},{-1993.6,1522.5,1.1,1},
		{-2271.5,1520.9,0.99,1},{-2293.6,1521.6,1.15,1},{-1294.3,1361.2,0.78,1},{-1304.7,1350.7,0.6,1},{-1395.5,1237.9,0.91,1},{-1216.3,1339.5,1.23,1},{-1232.2,1331.1,0.96,1},{-1235.8,1359.1,1.04,3},
		{-1289.0,1315.1,0.77,4},{-1105.9,1226.4,0.99,1},{-1121.4,1250.8,1.06,1},{-1131.3,1301.7,0.98,3},{-1132.4,1263.8,0.91,1},{-1116.4,1288.0,1.15,3},{-1142.8,1256.4,0.88,3},{-1121.6,1218.2,1.18,4},
		{-1116.2,1236.9,1.0,4},{-1126.5,1263.3,1.02,4},{-1401.5,1276.2,0.99,1},{-1402.2,1270.5,0.78,4},{-1091.0,1348.9,1.2,3},{-1087.4,1315.6,1.04,1},{-1199.0,1319.1,1.05,1},{-1219.0,1304.8,1.14,4},
		{-1252.0,1323.6,0.81,4},{-1233.2,1306.3,1.02,4},{-1199.1,1299.4,1.06,3},{-1209.3,1282.6,1.15,1},{-1120.0,1348.5,0.99,3},{-1303.6,1278.7,1.32,1},{-1255.5,1276.6,1.29,3},{-1161.8,1261.3,1.39,3},
		{-1454.6,1294.7,0.89,4},{-1738.8,552.9,0.86,1},{-1740.8,572.0,1.09,1},{-1330.7,456.0,1.06,1},{-1316.4,434.1,0.81,3},{-1298.2,436.6,0.81,1},{-1323.6,444.3,0.84,1},{-1312.6,440.2,1.0,4},
		{-1314.5,468.5,1.19,4},{-1278.0,462.6,0.96,1},{-1231.0,449.2,1.22,1},{-1254.8,463.1,1.3,1},{-1249.7,474.0,1.33,1},{-1268.1,447.8,0.71,4},{-1244.6,450.0,1.17,4},{-1151.2,433.3,1.04,1},
		{-1175.7,453.6,0.85,1},{-1153.7,451.2,0.91,4},{-1237.6,439.5,0.99,3},{-1272.0,485.4,1.0,3},{-1292.1,482.7,0.84,4},{-1364.0,488.1,1.33,3},{-1359.6,499.8,0.95,1},{-1354.3,480.4,1.27,3},
		{-1371.3,503.3,1.11,3},{-1367.0,477.7,0.76,4},{-1279.2,448.5,1.32,1},{-1295.4,455.0,0.87,1},{-1291.9,470.1,0.97,4},{-1308.1,461.4,1.26,4},{-1183.7,463.6,0.9,1},{-1195.3,436.5,1.34,1},
		{-1144.0,450.3,0.79,4},{-1159.1,460.3,1.01,4},{-1491.9,463.6,1.08,3},{-1469.6,485.0,0.94,1},{-1485.0,489.3,1.06,3},{-1484.0,473.5,0.98,1},{-1474.0,468.6,1.26,4},{-1566.3,560.3,1.1,1},
		{-1600.3,562.7,0.99,3},{-1592.4,538.8,1.1,3},{-1582.7,567.2,1.12,4},{-1592.0,565.4,1.23,4},{-1549.3,540.3,1.03,4},{-1594.3,553.7,1.26,4},{-1447.8,510.1,1.26,3},{-1202.5,455.9,1.15,1},
		{-893.5,-1625.9,0.89,1},{-964.0,-1636.1,0.66,1},{-1783.0,-1659.1,0.88,1},{-1590.5,-2045.8,0.99,1},{-1193.4,-2118.6,0.81,1},{-1123.7,-2130.9,0.9,1},{-1096.1,-2137.5,0.99,1},{-817.9,-1977.3,0.85,1},
		{-1075.4,-1742.0,0.87,1},{-1102.9,-1741.9,1.01,3},{-1083.4,-1795.2,1.03,1},{-1094.8,-1756.6,1.23,1},{-1089.4,-1766.6,0.88,3},{-1070.7,-1769.6,0.76,4},{-1125.7,-1690.5,0.91,3},{-1119.0,-1704.3,1.26,1},
		{-1110.1,-1672.7,1.31,1},{-1121.1,-1676.2,0.84,3},{-1161.9,-1724.2,1.09,4},{-1118.8,-1697.3,1.02,4},{-1109.8,-1653.4,0.81,4},{-1416.5,-2040.7,1.02,3},{-1406.7,-2050.2,1.11,3},{-1417.8,-2064.4,1.07,1},
		{-1412.5,-2080.1,1.23,3},{-1373.7,-2078.6,1.0,1},{-1425.6,-2069.1,0.92,4},{-1369.9,-2015.2,0.98,4},{-975.6,-1976.0,0.85,1},{-956.8,-1975.6,1.21,1},{-954.6,-1943.9,0.89,3},{-946.6,-2000.2,1.1,1},
		{-1001.4,-1934.4,0.79,4},{-1114.2,-2014.3,1.01,3},{-1125.5,-2016.3,0.85,1},{-1135.8,-2037.5,0.8,3},{-1137.3,-2023.5,1.1,1},{-1160.8,-2003.2,1.3,1},{-1138.2,-2033.1,1.1,4},{-1024.9,-1866.7,0.83,3},
		{-1002.7,-1867.7,1.29,3},{-1028.3,-1884.5,1.13,3},{-1048.5,-1902.5,0.88,4},{-1079.8,-1836.8,1.3,1},{-1118.5,-1832.8,1.16,3},{-1088.8,-1806.1,1.22,1},{-1103.7,-1827.1,0.94,4},{-1097.7,-1808.6,0.86,4},
		{-1070.2,-1989.7,1.31,3},{-1067.1,-1978.3,0.88,1},{-1088.5,-1989.9,1.02,1},{-1065.2,-2000.2,1.02,4},{-1081.7,-1997.8,0.89,4},{-1061.1,-1996.2,1.05,4},{-1023.5,-1781.8,1.29,1},{-1024.1,-1734.1,0.92,3},
		{-999.5,-1778.7,1.29,1},{-1041.6,-1752.8,0.81,4},{-1024.8,-1758.1,0.97,4},{-1027.2,-1749.1,0.96,4},{-1011.1,-1811.9,0.94,4},{-1170.0,-1965.8,1.18,1},{-1159.4,-1954.5,1.26,1},{-1163.8,-1977.0,1.26,3},
		{-1153.4,-1969.0,0.96,1},{-1163.1,-1961.2,0.84,4},{-1158.6,-1947.1,0.83,4},{-989.0,-1957.1,1.34,1},{-942.5,-1970.6,0.97,1},{-940.9,-1956.9,1.09,1},{-927.1,-1967.5,1.27,3},{-924.1,-1952.7,1.26,4},
		{-966.9,-1939.9,1.01,4},{-1157.3,-1748.1,1.14,1},{-1170.1,-1755.0,0.96,1},{-1168.3,-1746.1,0.92,4},{-1078.1,-2022.9,0.93,3},{-1078.7,-2045.5,0.95,3},{-1069.6,-2016.2,0.94,4},{-1140.8,-1708.5,0.91,1},
		{-1137.9,-1726.9,1.0,3},{-1135.5,-1714.1,0.85,4},{-1126.5,-1701.1,1.04,4},{-1150.8,-1711.4,0.79,4},{-1109.2,-1700.6,1.11,4},{-1425.5,-2096.9,0.82,3},{-1409.9,-2096.3,1.13,3},{-971.4,-2091.5,1.06,1},
		{-992.3,-2072.4,1.34,3},{-1017.8,-2061.1,1.28,1},{-980.6,-2080.9,0.92,3},{-943.6,-2057.4,1.01,3},{-977.4,-2068.4,0.98,4},{-968.7,-2096.2,0.72,4},{-925.4,-1792.7,0.9,3},{-947.9,-1814.4,1.07,1},
		{-948.6,-1831.4,1.15,1},{-962.7,-1819.1,0.8,3},{-930.1,-1832.2,1.08,1},{-911.3,-1812.2,1.01,3},{-912.2,-1788.1,0.89,1},{-930.2,-1800.2,0.89,4},{-956.3,-1956.0,1.06,3},{-988.5,-2009.3,1.18,3},
		{-967.4,-1961.7,0.99,1},{-965.9,-2045.9,0.87,3},{-974.3,-2000.8,0.97,1},{-995.3,-1939.4,1.16,4},{-975.4,-1956.4,0.94,4},{-912.0,-1996.8,1.02,1},{-942.2,-1983.7,1.26,3},{-924.1,-1992.2,1.15,1},
		{-948.0,-2014.9,1.11,1},{-951.2,-1958.8,1.03,4},{-963.0,-2005.5,0.87,4},{-929.3,-1972.5,1.28,4},{-930.8,-1814.6,1.18,1},{-868.7,-1691.0,0.85,1},{-838.2,-1700.4,0.95,1},{-849.4,-1685.1,0.98,1},
		{-824.8,-1708.8,0.89,3},{-860.6,-1707.4,0.81,3},{-832.6,-1681.7,1.1,1},{-889.0,-1679.5,0.83,4},{-872.8,-1684.7,0.77,4},{-866.3,-1725.9,1.17,4},{-869.9,-1700.0,1.25,4},{-991.0,-2050.8,1.11,1},
		{-1004.2,-2039.8,1.31,3},{-993.6,-2024.9,1.02,3},{-986.5,-2080.5,1.01,4},{-989.5,-2021.3,0.82,4},{-1024.4,-2011.1,1.12,3},{-1044.8,-2038.0,1.09,3},{-1033.5,-2029.8,1.08,1},{-1058.0,-2045.4,0.71,4},
		{-1026.1,-2018.7,0.99,4},{-1011.2,-2025.5,0.86,4},{-984.0,-2036.7,1.35,1},{-1021.4,-2036.5,0.95,1},{-1001.0,-2045.3,1.04,4},{-1245.6,-2058.2,0.82,1},{-1258.5,-2052.7,0.96,1},{-1250.2,-2071.8,1.1,1},
		{-1229.6,-2037.1,1.05,1},{-1209.0,-2040.8,0.85,3},{-1234.6,-2055.2,1.28,3},{-1192.9,-2079.2,1.13,4},{-1236.3,-2086.1,0.85,4},{-1290.1,-2052.4,0.76,4},{-1107.6,-1763.3,1.15,1},{-1123.0,-1756.2,1.06,3},
		{-1102.5,-1730.0,1.08,3},{-1084.7,-1750.1,1.26,1},{-1088.2,-1738.2,0.99,3},{-1082.7,-1726.8,1.16,4},{-1136.9,-2063.4,1.2,1},{-1129.1,-2085.4,1.28,3},{-1114.9,-2066.9,1.17,4},{-1116.6,-2060.8,0.71,4},
		{-1133.8,-2082.5,1.1,4},{-1130.2,-2063.5,0.97,4},{-963.4,-1915.5,1.2,3},{-1015.3,-1935.5,1.34,1},{-1053.2,-1917.6,1.22,3},{-1038.8,-1937.9,1.25,3},{-1021.2,-1905.1,1.12,3},{-1034.4,-1926.0,1.13,4},
		{-1025.2,-1938.9,1.15,4},{-1006.9,-1942.5,0.93,4},{-863.0,-1778.6,1.01,3},{-888.7,-1761.3,1.12,3},{-875.1,-1749.3,0.94,1},{-860.6,-1745.1,0.97,3},{-876.8,-1770.6,0.83,1},{-892.8,-1731.7,1.19,3},
		{-851.9,-1763.8,0.99,3},{-873.5,-1805.4,0.83,4},{-1078.7,-1923.7,1.3,3},{-1079.4,-1937.9,0.91,1},{-1074.8,-1905.3,1.33,1},{-1092.7,-1931.1,1.16,3},{-1059.8,-1901.0,1.26,1},{-1097.1,-1907.0,1.21,4},
		{-1067.4,-1868.7,0.81,4},{-1080.4,-1897.4,1.29,4},{-1044.5,-1933.9,0.87,4},{-1022.3,-1799.0,0.9,3},{-1000.8,-1792.5,1.26,1},{-976.0,-1818.1,1.17,4},{-1009.4,-1764.6,1.0,4},{-1014.1,-1775.1,0.82,4},
		{-1012.2,-1859.2,1.35,1},{-1040.7,-1814.6,1.17,1},{-1048.2,-1825.9,0.78,4},{-1035.9,-1784.9,1.09,4},{-1053.7,-1796.1,1.25,4},{-1123.7,-2035.9,0.81,1},{-1119.3,-2054.9,0.83,4},{-1121.3,-2072.3,1.1,4},
		{-1113.7,-2072.6,1.23,4},{-1139.4,-2070.9,0.77,4},{-1333.4,-2027.3,1.19,1},{-1363.0,-2039.7,1.03,3},{-1344.5,-2033.2,1.29,1},{-1341.5,-2045.3,0.91,1},{-1360.4,-2021.7,1.14,3},{-1323.8,-2015.0,1.22,1},
		{-1350.7,-2004.7,1.28,4},{-1337.3,-2023.8,0.71,4},{-1308.7,-2033.4,1.06,4},{-1120.0,-1884.8,1.22,1},{-1141.1,-1876.9,1.31,3},{-1132.3,-1893.3,1.15,1},{-1082.0,-1906.0,0.92,4},{-1111.4,-1817.4,1.05,3},
		{-1094.6,-1786.9,0.87,4},{-1061.8,-1807.4,0.91,4},{-1064.3,-1800.3,0.8,4},{-832.0,-1816.0,0.89,3},{-849.9,-1777.0,1.18,3},{-909.4,-2024.1,0.92,1},{-920.5,-2020.1,1.31,3},{-926.2,-2011.6,1.17,4},
		{-916.4,-2035.2,0.88,4},{-938.4,-2020.0,1.24,4},{-893.8,-1993.7,1.0,4},{-789.7,-1698.7,1.19,3},{-845.5,-1728.2,0.88,3},{-813.4,-1695.7,0.81,1},{-801.6,-1699.7,1.3,3},{-808.2,-1739.2,0.77,4},
		{-778.2,-1712.1,1.24,3},{-873.1,-1823.4,0.95,3},{-1319.9,-2091.7,1.23,3},{-1104.6,-1970.7,1.27,3},{-1023.1,-1980.4,1.37,3},{-1068.1,-1674.3,0.93,3},{-1261.5,-2150.4,1.28,3},{-1459.0,-2058.1,0.96,3},
		{-1146.5,-1688.8,0.98,1},{-1080.1,-1689.5,1.21,1},{-859.9,-1658.7,0.95,3},{-1163.2,-2040.9,0.95,1},{-1406.0,-2132.4,1.24,1},{-1071.5,-2071.2,1.07,1},{-1776.3,-1580.2,1.06,1},{-2555.2,1276.2,0.94,1},
		{-2525.5,1177.3,0.81,1},{-2456.2,1038.4,0.91,1},{-2421.8,1027.3,0.94,1},{-2141.2,1041.1,0.62,1},{-2022.8,1039.0,0.97,1},{-1897.1,1044.0,0.67,1},{-1881.6,1099.4,0.91,1},{-1850.8,1139.8,0.73,1},
		{-1764.7,1232.7,0.83,1},{-1866.2,1247.8,0.95,1},{-2007.1,1244.0,0.65,1},{-2123.5,1285.8,0.65,1},{-2483.0,1248.0,0.85,1},{-2525.6,1255.8,0.7,1},{-1904.7,1114.3,1.08,1},{-1909.4,1129.4,0.93,3},
		{-1931.0,1103.1,1.2,1},{-1921.2,1132.5,1.27,1},{-2243.3,1005.1,1.02,1},{-2228.9,1018.5,1.15,1},{-2254.8,1018.7,1.13,1},{-2257.2,1031.5,1.14,4},{-2450.4,1084.7,1.04,3},{-2481.7,1107.5,0.97,1},
		{-2493.2,1090.0,1.27,3},{-2456.3,1110.4,0.85,1},{-2491.7,1119.4,1.07,1},{-2462.5,1123.1,0.88,4},{-1933.5,1218.3,1.25,3},{-1956.3,1208.3,1.23,3},{-1947.5,1215.6,0.92,3},{-1956.2,1202.5,0.79,4},
		{-1940.2,1210.5,1.06,4},{-1946.6,1209.6,1.08,4},{-1959.5,1220.3,0.84,4},{-2022.6,1119.7,1.05,1},{-2018.5,1105.5,1.14,1},{-2035.8,1101.5,0.88,3},{-2022.1,1110.1,1.28,4},{-2011.8,1102.6,0.99,4},
		{-2028.8,1100.3,1.0,4},{-1872.2,1209.7,0.91,1},{-1869.2,1193.3,1.24,4},{-2146.3,1149.8,1.22,1},{-2200.0,1166.1,1.24,1},{-2179.4,1156.8,0.86,3},{-2183.2,1139.4,1.19,3},{-2184.6,1168.8,1.11,1},
		{-2170.0,1118.6,1.16,1},{-2162.2,1143.4,1.23,4},{-2139.4,1130.6,1.2,4},{-2190.2,1138.5,0.99,4},{-2175.0,1175.0,1.07,1},{-2159.5,1161.0,1.27,1},{-2183.4,1145.3,1.27,4},{-1916.5,1109.5,1.06,1},
		{-1918.5,1125.4,1.04,4},{-2103.6,1079.9,1.08,1},{-2118.5,1082.3,1.24,3},{-2103.9,1095.4,1.31,1},{-2123.7,1092.2,1.02,4},{-2032.9,1200.6,0.96,3},{-2036.1,1178.4,1.25,1},{-2067.0,1191.5,1.28,3},
		{-2045.6,1216.2,1.15,1},{-2023.8,1214.1,1.0,4},{-2033.6,1192.5,0.8,4},{-2063.5,1097.6,0.92,1},{-2043.6,1126.0,1.15,3},{-2059.1,1086.1,1.25,3},{-2054.8,1122.3,0.8,1},{-2087.2,1101.9,1.21,3},
		{-2069.2,1110.6,1.18,3},{-2405.7,1191.3,1.04,1},{-2432.9,1219.8,1.23,1},{-2445.5,1190.0,0.8,4},{-2202.3,1146.4,1.15,3},{-2200.6,1187.3,1.16,3},{-2183.2,1190.7,1.19,1},{-2165.9,1185.2,1.01,4},
		{-2203.6,1155.8,0.74,4},{-2359.9,1080.7,1.14,3},{-2376.5,1069.5,1.02,4},{-2419.5,1161.1,1.06,3},{-2405.9,1146.5,1.03,3},{-2403.2,1130.8,1.2,1},{-2413.5,1166.8,0.73,4},{-2174.8,1095.9,0.98,1},
		{-2146.9,1103.0,0.95,3},{-2206.2,1106.0,1.33,1},{-2165.8,1105.5,0.87,1},{-2180.7,1115.7,1.04,4},{-2165.5,1131.9,0.97,4},{-2175.4,1080.5,0.88,4},{-2157.5,1090.6,0.7,4},{-2276.2,1144.0,0.95,3},
		{-2291.7,1136.6,1.25,1},{-2298.5,1147.4,1.25,3},{-2275.0,1165.5,1.1,1},{-2270.2,1161.0,0.87,4},{-2276.5,1134.1,1.12,4},{-2332.9,1113.3,1.21,3},{-2343.7,1101.8,0.95,1},{-2346.1,1086.3,0.95,1},
		{-2338.4,1090.4,0.81,4},{-2309.0,1095.0,1.29,4},{-2307.5,1107.3,1.02,3},{-2296.7,1087.7,1.02,3},{-2296.0,1101.6,0.82,4},{-2130.8,1197.5,1.06,1},{-2146.0,1192.4,0.86,3},{-2126.8,1176.1,1.25,1},
		{-2123.0,1214.4,1.25,1},{-2138.6,1180.7,1.08,3},{-2131.2,1157.8,1.22,1},{-2116.6,1186.6,0.97,3},{-2140.8,1213.2,1.29,4},{-2125.2,1198.3,1.03,4},{-2199.9,1119.0,1.28,4},{-1982.4,1183.4,1.3,3},
		{-1998.6,1146.2,0.82,1},{-2003.9,1133.6,1.19,4},{-1984.1,1209.2,1.32,3},{-2223.3,1102.5,0.9,1},{-2208.8,1229.3,1.1,3},{-2185.7,1224.7,1.32,1},{-1827.5,1214.8,1.12,1},{-2269.7,1190.4,1.12,1},
		{-2095.7,1128.2,1.13,1},{-2386.9,1226.0,1.1,1},{-2236.3,1179.5,1.02,1},{-2479.5,1011.7,0.96,1},{-1871.7,1040.1,0.91,4},{-1615.8,1028.6,0.73,1},{-1563.6,1185.8,1.15,1},{-1611.8,979.5,1.11,3},
		{-1591.9,981.0,0.83,1},{-1734.4,972.4,1.01,1},{-2444.2,-849.4,0.87,1},{-2449.7,-248.3,0.65,1},{-2710.1,-243.5,0.78,1},{-2721.3,-599.0,0.96,1},{-2714.6,-797.6,1.15,1},{-2716.2,-809.8,1.05,3},
		{-2506.2,-563.5,0.85,3},{-2452.2,-526.3,1.1,3},{-2484.7,-552.2,0.82,3},{-2505.4,-544.6,1.25,1},{-2481.1,-519.6,0.76,4},{-2499.3,-565.0,1.03,4},{-2644.1,-442.3,1.24,3},{-2652.9,-432.1,1.22,3},
		{-2616.6,-425.5,1.34,1},{-2629.7,-457.1,1.14,3},{-2625.8,-421.3,1.29,4},{-2617.8,-445.4,0.71,4},{-2635.3,-418.9,1.18,4},{-2429.4,-405.8,1.24,1},{-2435.9,-444.6,0.87,3},{-2421.8,-461.0,1.32,1},
		{-2453.3,-411.2,1.18,1},{-2417.0,-415.3,1.04,3},{-2426.3,-453.3,0.97,4},{-2449.4,-442.7,0.83,4},{-2589.1,-426.8,1.21,1},{-2585.1,-415.2,1.19,1},{-2557.3,-402.5,0.92,4},{-2571.8,-448.3,1.21,4},
		{-2591.3,-413.7,1.21,4},{-2731.9,-495.8,1.18,3},{-2733.1,-480.4,0.83,1},{-2720.1,-504.9,0.91,3},{-2718.6,-476.2,1.28,4},{-2705.6,-441.6,1.04,4},{-2684.9,-486.4,0.92,4},{-2740.7,-497.8,1.09,4},
		{-2432.5,-374.1,0.92,1},{-2418.3,-366.0,0.92,1},{-2447.9,-380.2,0.91,1},{-2416.1,-340.1,1.16,4},{-2443.7,-368.7,0.86,4},{-2509.9,-504.2,1.1,3},{-2533.2,-504.5,0.84,1},{-2531.8,-498.8,0.92,4},
		{-2449.9,-286.0,0.96,3},{-2443.3,-332.3,1.06,1},{-2425.3,-307.4,1.23,3},{-2449.7,-312.8,1.22,4},{-2436.6,-301.1,1.2,4},{-2577.2,-365.1,1.18,3},{-2608.1,-383.0,1.26,3},{-2555.9,-377.6,0.85,3},
		{-2593.7,-399.6,0.81,1},{-2575.5,-339.6,0.72,4},{-2619.9,-456.6,1.21,4},{-2633.2,-434.5,0.95,4},{-2645.6,-566.2,0.88,1},{-2652.8,-610.8,1.2,1},{-2609.3,-600.7,1.08,1},{-2620.2,-593.2,1.28,1},
		{-2616.8,-598.5,1.01,4},{-2639.4,-573.8,0.93,4},{-2642.1,-596.4,1.02,4},{-2606.4,-698.7,1.04,3},{-2623.0,-677.7,0.97,1},{-2640.1,-682.8,1.19,3},{-2597.0,-698.6,1.12,4},{-2604.5,-688.1,1.23,4},
		{-2724.8,-533.9,0.89,3},{-2716.2,-521.2,1.28,1},{-2734.8,-524.7,1.07,1},{-2709.3,-537.5,0.83,1},{-2752.7,-524.9,1.09,1},{-2726.7,-524.0,0.91,4},{-2719.0,-542.9,1.29,4},{-2509.6,-458.7,0.87,1},
		{-2487.3,-457.2,1.18,3},{-2501.5,-439.1,1.27,1},{-2493.9,-453.7,0.84,4},{-2479.2,-456.0,0.8,4},{-2443.9,-756.6,0.85,3},{-2453.2,-731.6,1.22,1},{-2438.9,-726.9,1.13,1},{-2441.4,-741.1,1.19,4},
		{-2446.4,-586.3,0.9,1},{-2445.0,-567.1,1.1,3},{-2423.6,-575.6,0.88,1},{-2419.2,-567.7,1.09,4},{-2496.3,-474.9,0.83,1},{-2459.1,-450.1,0.91,1},{-2454.7,-473.6,0.8,4},{-2534.7,-465.4,1.04,4},
		{-2627.4,-704.6,1.17,1},{-2610.2,-673.6,1.07,1},{-2622.7,-653.9,1.22,3},{-2605.2,-660.5,1.14,1},{-2638.2,-670.5,1.0,3},{-2629.7,-686.8,1.19,4},{-2627.0,-682.4,1.0,4},{-2604.4,-668.9,0.85,4},
		{-2673.5,-486.9,0.87,1},{-2691.9,-471.1,0.96,3},{-2679.4,-456.6,0.98,4},{-2687.6,-458.5,1.07,4},{-2679.8,-498.8,1.1,4},{-2461.2,-747.0,0.99,1},{-2434.4,-763.0,1.07,1},{-2461.4,-775.8,0.89,1},
		{-2445.8,-765.6,1.0,4},{-2473.1,-773.8,1.03,4},{-2450.0,-771.4,1.2,4},{-2443.3,-521.1,0.78,4},{-2482.1,-529.9,0.93,4},{-2443.9,-574.9,1.01,4},{-2665.2,-590.4,1.25,1},{-2683.5,-592.2,0.96,3},
		{-2668.3,-577.2,0.81,3},{-2679.4,-578.1,1.24,1},{-2665.3,-623.6,0.88,4},{-2661.6,-594.0,0.81,4},{-2463.3,-704.0,0.93,1},{-2470.1,-688.0,0.9,3},{-2481.1,-724.8,1.16,3},{-2485.4,-694.1,0.82,1},
		{-2449.5,-654.8,0.72,4},{-2494.4,-704.9,0.94,4},{-2677.6,-625.2,1.29,3},{-2690.4,-629.6,0.86,1},{-2676.6,-613.2,0.92,1},{-2687.5,-606.1,0.9,3},{-2701.7,-629.2,1.12,4},{-2675.8,-603.8,1.25,4},
		{-2686.7,-597.8,1.1,4},{-2545.0,-470.3,1.32,1},{-2532.0,-478.8,1.13,3},{-2552.2,-454.1,1.14,3},{-2541.4,-483.0,0.78,4},{-2539.8,-494.6,1.05,4},{-2606.1,-624.3,1.14,3},{-2589.7,-617.0,1.08,1},
		{-2579.2,-630.0,1.03,4},{-2612.2,-621.1,0.86,4},{-2584.4,-631.2,0.92,4},{-2517.5,-802.2,0.88,1},{-2503.6,-778.4,1.26,3},{-2498.1,-793.9,0.98,1},{-2488.5,-804.8,1.01,1},{-2509.5,-779.0,1.08,4},
		{-2646.6,-276.7,0.94,1},{-2625.6,-276.5,1.22,1},{-2645.7,-296.4,0.88,1},{-2631.1,-292.6,1.33,3},{-2659.2,-287.5,1.29,1},{-2648.1,-288.4,0.9,4},{-2686.8,-554.0,0.8,3},{-2744.6,-515.6,0.89,1},
		{-2746.8,-548.3,0.74,4},{-2700.9,-493.1,1.06,4},{-2509.2,-533.9,0.92,1},{-2518.2,-548.0,0.81,3},{-2533.6,-567.4,0.86,4},{-2514.9,-574.7,0.73,4},{-2606.5,-774.8,1.04,1},{-2452.0,-808.6,1.06,1},
		{-2490.7,-603.8,1.16,1},{-2519.2,-821.1,1.2,3},{-2633.9,-527.4,0.93,3},{-2459.4,-271.5,1.28,3},{-2619.9,-313.9,1.21,3},{-2516.6,-699.1,1.21,1},{-2421.4,-268.3,1.01,1},{-2656.1,-793.3,1.29,1},
		{-2706.6,-303.2,1.38,1},{-2591.9,-331.0,1.21,1},{-2567.2,-676.5,1.13,1},{-2703.5,-678.0,0.91,1},{-2384.2,-1429.6,0.84,1},{-2357.9,-1431.6,0.84,1},{-2232.9,-1477.1,0.87,1},{-2276.3,-1295.9,0.67,1},
		{-2361.2,-1309.8,0.94,1},{-2427.1,-1360.4,0.8,1},{-2403.7,-1397.5,0.65,1},{-2572.2,-1272.1,0.87,3},{-2362.0,-1373.2,1.32,3},{-2404.7,-1336.0,1.28,3},{-2383.3,-1381.0,1.28,1},{-2357.4,-1359.7,1.23,1},
		{-2321.5,-1355.8,1.2,4},{-2425.0,-1322.0,0.74,4},{-2371.1,-1356.8,1.26,4},{-2285.3,-1336.9,0.99,1},{-2301.3,-1333.6,0.81,1},{-2286.7,-1439.8,1.26,1},{-2300.2,-1415.5,1.25,1},{-2302.7,-1445.3,1.23,1},
		{-2274.6,-1398.5,1.31,1},{-2275.3,-1435.2,1.3,3},{-2255.8,-1392.7,0.95,4},{-2263.6,-1384.1,0.71,4},{-2267.8,-1406.0,1.19,4},{-2219.0,-1408.5,1.0,1},{-2255.5,-1441.7,0.86,3},{-2232.5,-1443.2,1.18,1},
		{-2232.9,-1402.0,1.22,1},{-2243.8,-1421.6,0.94,3},{-2242.6,-1416.5,1.27,4},{-2325.6,-1372.5,0.97,1},{-2319.5,-1338.4,1.27,1},{-2288.9,-1360.8,1.24,1},{-2309.6,-1350.2,1.28,3},{-2327.9,-1344.9,0.73,4},
		{-2274.1,-1353.3,1.3,1},{-2408.9,-1457.2,1.03,3},{-1942.9,-1323.2,0.89,1},{-2041.1,-1162.2,0.66,1},{-2041.7,-1059.5,1.0,3},{-2088.5,-1035.3,1.1,3},{-2035.5,-1028.6,1.25,4},{-2056.4,-1036.7,1.25,4},
		{-2040.4,-1427.8,1.21,1},{-2043.6,-1447.6,0.87,1},{-2051.3,-1421.6,0.83,1},{-2071.8,-1436.2,1.35,1},{-2041.4,-1439.7,0.97,4},{-1973.3,-1121.6,1.08,3},{-1987.7,-1172.3,1.34,1},{-1995.2,-1111.0,1.15,3},
		{-1992.6,-1126.2,1.29,3},{-1973.2,-1144.7,0.88,1},{-1969.5,-1155.0,0.85,4},{-1970.0,-1188.7,1.19,1},{-1998.7,-1185.5,1.24,1},{-1979.7,-1196.6,1.2,3},{-1975.8,-1218.1,1.2,3},{-1986.7,-1187.8,0.91,4},
		{-1988.1,-1057.8,1.28,1},{-1961.1,-1052.0,0.89,1},{-1981.3,-1024.5,1.21,1},{-2002.9,-1070.4,1.34,1},{-2025.9,-1067.1,1.25,4},{-2014.2,-1102.9,0.9,4},{-2070.5,-1041.7,1.14,3},{-2057.4,-1049.4,0.92,1},
		{-2028.5,-1030.0,0.88,4},{-2050.3,-1045.7,1.16,4},{-2079.3,-1028.8,1.23,4},{-1997.9,-1351.2,1.07,3},{-1980.3,-1305.0,0.97,3},{-2017.0,-1296.9,1.33,3},{-1978.1,-1663.7,0.66,1},{-2121.1,-1665.6,0.97,1},
		{-2147.4,-1665.4,0.72,1},{-1966.5,-1592.9,1.24,3},{-1953.6,-1591.5,0.85,4},{-2032.9,-1681.8,0.94,3},{-2024.8,-1690.6,1.25,3},{-2029.0,-1677.7,1.12,4},{-2030.7,-1712.7,0.71,4},{-2099.5,-1829.9,1.24,1},
		{-1947.9,-1933.1,1.11,1},{-1952.4,-1928.0,0.76,4},{-2287.6,-1032.6,0.75,1},{-2410.2,-1042.0,0.88,1},{-2323.2,-1132.0,0.75,1},{-2344.6,-1072.0,1.25,1},{-2373.9,-1058.3,1.28,3},{-2365.6,-1077.7,0.87,1},
		{-2328.1,-1092.3,0.98,3},{-2359.6,-1064.1,1.14,1},{-2362.4,-1112.5,1.04,4},{-2391.3,-1187.0,1.02,4},{-2422.8,-1119.0,1.21,1},{-2430.0,-1107.6,0.89,1},{-2448.9,-1114.7,1.27,3},{-2412.1,-1096.1,1.33,3},
		{-2416.3,-1108.9,0.87,1},{-2408.7,-1108.0,1.01,4},{-2421.4,-1108.4,1.1,4},{-2381.0,-1095.0,1.14,1},{-2382.5,-1077.0,0.81,4},{-2385.3,-1136.7,1.12,1},{-2238.5,-1076.1,1.12,3},{-2242.1,-55.1,0.92,1},
		{-2346.1,-2.9,0.71,1},{-2317.4,-57.1,1.23,1},{-2311.3,-71.7,1.11,1},{-2310.0,-46.3,0.84,1},{-2325.0,67.4,0.89,1},{-2298.9,55.6,0.88,4},{-2313.8,36.7,1.23,1},{-2318.0,22.1,1.23,3},
		{-2321.0,10.3,1.01,1},{-2278.7,35.9,0.81,3},{-2259.4,13.9,1.04,1},{-2283.9,-28.1,1.03,3},{-2266.8,-15.7,1.24,1},{-2248.3,-10.2,1.13,1},{-2294.8,-17.1,0.75,4},{-2249.3,-19.7,1.21,4},
		{-2249.8,-3.4,1.05,4},{-2312.5,-4.0,1.26,1},{-2350.0,321.4,0.93,1},{-2293.5,109.0,1.17,1},{-2216.6,392.2,1.18,3},{-2208.0,401.0,0.97,3},{-1956.3,31.1,0.97,1},{-1976.3,159.0,0.61,1},
		{-1964.2,290.6,0.65,1},{-2008.7,388.5,0.61,1},{-2047.5,380.8,0.96,1},{-1930.2,194.9,1.14,3},{-1946.5,192.3,1.19,1},{-1960.1,205.4,1.23,3},{-1960.1,188.3,0.92,4},{-1968.5,175.7,1.27,4},
		{-2016.2,110.4,0.97,3},{-2020.9,127.6,0.82,1},{-2027.7,113.9,0.86,4},{-2038.3,131.0,0.74,4},{-2062.1,337.8,1.22,3},{-2061.5,361.9,0.94,1},{-2073.8,346.6,1.09,3},{-2037.5,282.4,0.88,3},
		{-2045.6,302.4,1.3,1},{-2060.9,308.1,1.02,4},{-2004.6,336.7,0.88,1},{-1991.3,354.6,1.14,1},{-1991.3,343.3,0.94,3},{-2030.6,-24.9,1.23,1},{-1976.2,-48.7,1.33,1},{-1997.4,302.5,1.14,3},
		{-2675.4,-70.9,0.68,1},{-2513.2,46.8,0.79,1},{-2524.5,164.5,0.97,1},{-2518.5,228.6,0.83,1},{-2590.1,183.9,0.76,1},{-2614.4,84.0,0.95,1},{-2611.6,111.8,1.26,1},{-2568.6,112.5,0.7,4},
		{-2647.8,21.2,1.0,1},{-2661.5,0.9,1.26,3},{-2650.8,35.7,0.91,1},{-2634.9,23.2,0.83,1},{-2669.0,12.5,1.31,3},{-2672.1,29.8,1.09,1},{-2655.5,38.4,0.86,4},{-2659.8,17.4,0.97,4},
		{-2553.0,203.5,0.99,1},{-2538.5,222.7,0.74,4},{-2671.5,-18.9,1.23,1},{-2658.0,-10.0,1.23,3},{-2686.6,-10.4,1.17,1},{-2666.3,-27.2,0.92,4},{-2603.5,85.9,1.04,1},{-2545.8,43.7,1.28,3},
		{-2609.7,64.4,1.27,1},{-2546.4,62.8,1.23,1},{-2587.3,56.7,0.97,1},{-2592.1,72.7,1.14,3},{-2591.3,60.9,1.25,4},{-2590.7,109.7,1.24,4},{-2598.1,72.9,1.16,4},{-2638.7,-22.5,1.25,1},
		{-2696.7,131.4,1.21,1},{-1885.5,1903.5,0.84,1},{-1937.7,1861.1,0.94,3},{-1852.0,1937.4,1.0,3},{-2027.7,1823.1,1.08,1},{-1807.2,1992.5,0.83,4},{-1441.8,1028.5,0.81,1},{-1271.7,921.1,0.78,1},
		{-1221.7,912.0,0.83,1},{-1340.0,1021.8,1.03,1},{-1364.1,1006.8,0.83,1},{-1342.5,995.6,1.24,1},{-1348.5,984.8,0.98,1},{-1329.2,1025.9,0.98,4},{-1249.4,986.1,1.16,3},{-1259.7,965.0,1.29,1},
		{-1279.2,988.7,0.96,3},{-1290.6,959.1,1.35,1},{-1277.8,958.4,1.33,3},{-1263.5,996.6,0.84,3},{-1272.2,972.2,1.22,3},{-1277.8,1000.4,0.91,4},{-1260.6,951.3,0.97,4},{-1294.8,967.0,0.77,4},
		{-1296.6,1013.7,1.33,3},{-1298.5,1025.9,0.82,1},{-1291.6,998.5,1.0,4},{-1296.6,991.4,1.01,4},{-1267.3,1022.1,1.09,4},{-1242.8,957.4,1.1,4},{-1234.9,978.2,1.15,4},{-1183.2,935.7,1.02,3},
		{-1194.9,964.4,1.32,3},{-933.7,2228.5,0.69,1},{-773.4,2193.3,0.64,1},{-725.8,2208.8,0.69,1},{-536.1,2238.0,0.92,1},{-371.4,2236.2,1.0,1},{-468.6,2292.7,0.62,1},{-524.4,2276.7,0.82,1},
		{-683.1,2279.4,0.93,1},{-603.5,2235.3,0.99,3},{-614.6,2252.7,0.96,1},{-618.0,2226.3,1.31,1},{-605.6,2196.8,0.99,4},{-914.8,2205.3,0.95,1},{-910.9,2220.8,1.18,1},{-903.1,2231.5,1.16,1},
		{-902.4,2207.1,1.15,3},{-906.7,2193.9,1.28,4},{-904.5,2218.2,0.86,4},{-845.7,2251.1,1.06,1},{-837.8,2219.9,0.97,3},{-818.5,2253.3,1.29,1},{-829.7,2258.7,0.72,4},{-839.1,2235.3,0.92,4},
		{-808.1,2280.5,1.06,1},{-819.3,2266.9,0.85,1},{-839.0,2301.0,1.28,4},{-814.6,2272.0,0.92,4},{-638.5,2196.4,1.12,3},{-619.0,2193.8,1.07,1},{-626.1,2230.5,1.13,4},{-736.6,2238.6,1.23,1},
		{-434.4,2261.5,1.12,3},{-459.1,2270.1,0.93,1},{-785.8,1231.8,0.9,1},{-690.1,1202.8,0.78,1},{-553.5,1210.2,0.71,1},{-511.6,1321.9,0.89,1},{-702.3,1244.3,0.86,1},{-722.5,1255.1,1.0,3},
		{-687.6,1272.4,0.99,3},{-744.7,1248.2,1.25,4},{-705.2,1268.9,1.25,4},{-639.9,1272.4,1.28,3},{-610.7,1277.4,1.0,1},{-622.8,1267.6,1.27,1},{-633.6,1296.9,0.92,1},{-594.5,1242.4,1.04,3},
		{-570.4,1274.0,0.99,4},{-628.0,1297.2,0.88,4},{-599.9,1274.6,0.92,4},{-851.5,1281.1,0.89,1},{-862.6,1297.7,1.33,1},{-847.2,1300.4,1.14,1},{-854.3,1322.0,1.2,1},{-682.1,1323.4,0.9,3},
		{-643.4,1320.5,1.3,3},{-706.6,1309.1,1.16,1},{-673.4,1311.2,1.07,1},{-613.1,1303.0,0.91,1},{-608.6,1283.9,1.2,4},{-564.4,1269.9,1.3,4},{-638.7,1227.1,1.21,3},{-813.1,1308.3,1.08,3},
		{-654.4,1303.2,1.02,1},{-574.2,1294.0,1.39,3},{-1127.3,1592.7,0.97,1},{-1096.4,1599.0,0.84,1},{-1033.8,1586.8,0.78,1},{-1094.5,2112.4,0.93,1},{-1230.3,2136.8,0.62,1},{-1274.2,2133.0,0.91,1},
		{-1316.4,2083.4,0.95,1},{-1300.8,2047.4,0.76,1},{-1317.4,2163.7,1.15,1},{-1118.8,1899.4,1.24,1},{-1120.1,1953.8,1.01,1},{-1133.5,1925.8,1.23,3},{-1108.8,1938.1,1.22,1},{-1102.3,1937.2,1.29,4},
		{-1098.7,1944.4,0.7,4},{-1195.7,1698.3,1.11,1},{-1184.0,1683.6,1.14,1},{-1184.4,1647.9,0.88,1},{-1130.5,2006.5,1.17,3},{-1111.1,2001.0,1.08,1},{-1133.3,1991.4,0.84,4},{-1113.3,2023.6,0.89,4},
		{-1124.6,2020.1,1.05,4},{-1118.2,1994.0,1.24,4},{-1170.1,2045.5,1.25,1},{-1201.7,2065.7,1.15,3},{-1190.7,2089.7,0.91,1},{-1202.2,2094.7,0.95,4},{-1190.3,2068.6,0.94,4},{-1174.9,2076.7,0.82,4},
		{-1152.0,2078.4,1.02,1},{-1137.8,2084.5,1.21,3},{-1144.4,2093.8,0.82,1},{-1155.5,2088.2,1.23,4},{-1192.6,2077.6,1.3,4},{-1146.4,1784.0,0.88,1},{-1123.1,1779.0,1.13,1},{-1167.6,1762.2,1.06,1},
		{-1148.6,1777.4,1.06,4},{-1170.0,1664.6,1.27,1},{-1142.2,1657.5,1.25,3},{-1163.6,1674.5,0.94,1},{-1133.2,1648.5,1.3,1},{-1142.8,1675.9,0.73,4},{-1170.1,1651.1,0.84,4},{-1187.4,1932.8,0.89,1},
		{-1200.5,1924.5,1.03,3},{-1209.9,1942.1,1.12,1},{-1183.1,1949.9,1.1,4},{-1206.5,1937.7,1.12,4},{-1260.6,2049.5,0.97,1},{-1265.5,2021.4,0.96,1},{-1273.7,2013.9,1.11,1},{-1249.3,2028.5,1.08,1},
		{-1267.5,2033.2,1.19,1},{-1032.9,1888.2,0.9,3},{-1038.0,1921.5,1.0,1},{-1020.6,1897.9,1.22,4},{-1022.1,1904.9,0.97,4},{-1153.3,1916.5,0.99,3},{-1155.4,1935.0,1.18,3},{-1167.5,1920.6,0.85,3},
		{-1157.3,1952.1,1.05,1},{-1135.8,1985.5,0.84,4},{-1149.2,1932.9,1.01,4},{-1245.1,2065.2,1.31,3},{-1224.2,2085.0,0.86,1},{-1210.5,2081.0,1.18,1},{-1187.5,2111.2,1.11,1},{-1230.5,2092.0,0.82,4},
		{-1191.3,2103.1,0.93,4},{-1114.1,1623.9,1.26,3},{-1093.9,1641.9,1.17,1},{-1098.5,1624.2,1.02,1},{-1097.7,1646.1,0.78,4},{-1088.1,1636.5,1.01,4},{-1164.0,1818.9,1.22,3},{-1125.5,1807.8,1.06,1},
		{-1136.6,1804.1,1.22,1},{-1166.1,1776.1,1.18,4},{-1139.9,1823.3,1.21,4},{-1004.0,1599.1,1.28,1},{-1007.3,1580.3,0.79,4},{-1168.7,2086.6,0.95,1},{-1159.6,2120.1,0.95,3},{-1286.9,2078.4,1.1,1},
		{-1281.1,2089.2,0.8,1},{-1293.3,2096.0,1.24,1},{-1143.0,2051.7,0.91,1},{-1108.5,2054.8,1.06,3},{-1126.3,2066.4,1.14,4},{-1188.8,1886.4,1.18,3},{-1134.1,1869.4,1.09,3},{-1204.8,1643.4,1.06,3},
		{-1063.1,1620.2,1.16,1},{-1087.7,1710.7,1.37,1},{-1113.9,2077.2,0.91,3},{-1196.3,1966.7,1.39,3},{-1141.1,1622.1,0.94,1},{-1126.2,2104.4,1.39,3},{-1207.4,1723.4,1.18,1},{-1084.3,1914.0,1.21,1},
		{-1417.9,1681.8,1.04,1},{-1409.0,1676.0,1.27,4},{-348.0,115.6,0.8,1},{-422.3,-19.4,1.22,1},{-358.1,-3.6,1.24,4},{-433.3,4.8,0.79,4},{-420.4,-13.0,1.2,4},{-368.2,151.7,1.21,3},
		{-399.0,146.9,1.22,4},{-375.6,155.3,1.11,4},{-458.6,10.1,1.07,3},{-401.5,-10.6,1.27,1},{-173.9,-1790.0,0.79,1},{-165.2,-1888.7,0.65,1},{-168.5,-2070.2,0.77,1},{-39.8,-2126.7,0.84,1},
		{163.7,-2036.1,0.65,1},{187.3,-2034.1,0.61,1},{256.3,-1795.6,0.99,1},{161.5,-1646.0,0.81,1},{162.4,-1718.9,0.88,3},{217.2,-1714.3,1.21,3},{181.2,-1714.4,1.05,1},{188.0,-1731.3,1.26,1},
		{204.1,-1691.3,1.05,4},{207.3,-1854.6,1.3,1},{180.2,-1870.7,0.9,1},{211.9,-1841.6,1.12,1},{209.8,-1867.9,1.02,1},{193.3,-1879.9,0.89,1},{196.6,-1838.2,1.19,1},{183.3,-1837.4,0.93,3},
		{189.6,-1883.9,1.02,4},{-69.8,-2033.4,1.28,3},{-30.1,-2015.8,0.87,3},{-44.2,-2004.2,1.26,1},{-86.8,-2014.7,1.17,1},{-10.0,-2006.2,1.26,1},{-21.3,-2023.7,1.03,4},{-51.4,-2032.9,0.74,4},
		{-38.5,-2008.1,1.18,4},{-200.7,-1662.1,1.12,1},{-199.2,-1647.0,1.23,1},{0.8,-1842.1,0.83,1},{-0.3,-1860.7,0.98,3},{-35.8,-1833.6,1.19,1},{-29.1,-1848.3,0.91,1},{13.8,-1836.5,1.25,1},
		{-12.6,-1814.3,0.92,1},{-9.3,-1854.1,1.11,3},{20.6,-1860.3,1.16,3},{-9.6,-1832.4,1.18,4},{-4.1,-1856.1,0.95,4},{-18.2,-1874.2,1.23,4},{27.9,-1832.4,0.92,4},{-20.4,-1980.7,1.02,1},
		{-41.8,-2019.9,1.01,1},{-17.3,-2017.4,1.11,4},{-73.5,-2025.5,1.16,4},{163.1,-1694.9,1.03,1},{143.2,-1689.0,0.83,1},{142.3,-1672.7,1.26,3},{182.0,-1684.7,0.77,4},{142.2,-1694.9,1.05,4},
		{-3.7,-1799.6,0.94,3},{-15.2,-1796.8,1.19,1},{12.8,-1810.9,0.96,1},{-17.8,-1813.5,0.89,4},{9.5,-2013.8,1.09,1},{23.7,-2021.6,0.88,3},{25.8,-2000.4,1.25,3},{26.7,-2017.0,1.26,4},
		{4.0,-2006.7,1.18,4},{-175.6,-1953.6,1.28,3},{-177.4,-1966.3,0.9,1},{-142.8,-1960.1,0.89,4},{-148.4,-1979.6,0.99,4},{-68.3,-1811.0,0.85,1},{-73.3,-1825.7,0.83,3},{-29.9,-1827.7,1.04,4},
		{-118.8,-1883.7,1.08,3},{-143.2,-1858.4,1.1,3},{-141.4,-1878.7,1.02,1},{-127.9,-2131.1,1.29,1},{-78.9,-1991.5,0.99,1},{-97.1,-1985.2,1.02,1},{-69.4,-1969.1,1.03,1},{-52.0,-2012.3,1.29,4},
		{-62.7,-2024.7,0.86,4},{-78.4,-2010.0,0.98,4},{40.8,-2012.5,0.88,1},{-109.0,-1861.2,1.0,3},{-79.4,-1842.1,0.89,3},{-108.1,-1836.7,1.08,3},{-115.1,-1832.4,0.92,4},{-150.8,-1827.9,0.93,4},
		{-105.7,-1883.3,0.77,4},{-124.2,-1809.6,0.96,3},{-130.6,-1787.1,1.13,1},{-105.9,-1819.3,0.9,1},{-100.0,-1801.4,0.91,3},{-112.2,-1823.3,1.05,4},{-72.2,-1720.4,0.86,3},{-89.1,-1717.1,1.16,3},
		{-148.5,-1723.3,0.92,1},{-125.5,-1741.1,1.3,1},{-83.3,-1704.8,1.18,4},{-116.7,-1719.5,0.81,4},{-81.7,-2042.3,1.31,3},{-92.2,-2049.0,1.25,3},{-81.2,-1998.9,0.88,4},{-81.0,-2036.7,0.92,4},
		{121.9,-1793.0,1.05,1},{140.1,-1824.2,0.89,1},{75.1,-1807.1,0.92,3},{110.1,-1768.0,1.34,1},{97.1,-1827.7,1.18,3},{71.8,-1837.9,0.94,3},{86.5,-1811.0,0.95,1},{123.6,-1781.3,0.92,1},
		{105.9,-1815.2,0.89,4},{82.7,-1790.6,1.05,4},{151.9,-1823.8,1.21,4},{-58.5,-1836.2,1.05,3},{-55.0,-1823.5,1.08,1},{-60.3,-1827.1,0.76,4},{142.2,-2055.2,1.07,1},{144.1,-2032.9,1.22,1},
		{114.7,-2032.4,0.94,1},{113.8,-2042.9,1.3,4},{123.2,-2036.3,0.94,4},{-72.2,-2077.2,0.87,3},{-85.9,-2077.2,1.31,1},{-112.9,-2102.9,0.89,1},{-74.2,-2094.3,1.24,1},{-52.9,-2100.4,0.83,4},
		{-66.3,-2088.3,0.85,4},{118.7,-1893.4,1.06,1},{127.2,-1903.5,1.31,1},{82.7,-1902.9,1.1,1},{125.2,-1931.3,0.77,4},{108.0,-1926.1,0.77,4},{83.6,-1894.3,0.83,4},{106.5,-1884.4,1.04,4},
		{-145.2,-2080.3,1.3,3},{-150.9,-2049.8,0.91,1},{-149.9,-2074.6,0.89,4},{232.6,-1715.1,0.88,1},{230.9,-1703.4,0.84,3},{261.2,-1702.5,1.33,1},{248.3,-1708.2,0.89,1},{-92.4,-2060.7,1.3,1},
		{-99.5,-2070.6,1.0,1},{-101.4,-2027.1,1.12,1},{-113.8,-2073.4,0.72,4},{78.4,-1692.4,1.17,3},{195.6,-1785.0,1.21,3},{-45.4,-1783.5,1.03,1},{39.0,-2078.0,1.24,3},{103.8,-1702.4,1.16,1},
		{-53.6,-2054.6,1.16,1},{-103.1,-1935.0,1.2,1},{174.6,-2002.5,1.13,1},{70.8,-2030.0,1.39,3},{-40.4,-2078.4,1.12,3},{-140.8,-2007.4,1.37,3},{-426.1,-1652.6,0.91,1},{-550.3,-1769.2,0.94,1},
		{-320.4,-1790.9,1.22,3},{-340.3,-1805.5,0.84,3},{-332.5,-1808.3,0.75,4},{-334.1,-1782.7,0.93,4},{-319.8,-1783.2,0.96,4},{-443.1,-1752.3,0.82,1},{-462.8,-1731.5,1.0,1},{-486.0,-1731.8,0.85,4},
		{-456.5,-1744.2,0.72,4},{-394.0,-1730.7,1.1,1},{-421.2,-1681.7,1.1,1},{-381.6,-1720.2,0.85,3},{-398.9,-1704.3,1.27,3},{-438.1,-1725.6,1.09,3},{-420.1,-1701.8,0.99,1},{-448.4,-1685.9,1.2,1},
		{-469.8,-1719.4,1.01,4},{-445.3,-1713.5,1.29,4},{-397.1,-1709.3,0.98,4},{-337.0,-2172.6,0.64,1},{-347.9,-2001.9,0.71,1},{-699.6,-2148.1,0.76,1},{-641.3,-2165.4,0.72,1},{-549.7,-2165.1,0.91,1},
		{-435.5,-2173.2,0.89,1},{-466.8,-2012.5,0.82,3},{-473.2,-1999.0,0.81,1},{-478.3,-1998.1,0.72,4},{-543.7,-1943.4,1.22,1},{-565.6,-1962.6,1.18,3},{-537.3,-1968.0,0.81,1},{-564.2,-1989.5,1.22,3},
		{-553.4,-1974.0,0.92,1},{-582.6,-1994.5,0.82,4},{-563.3,-1948.3,0.91,4},{-562.3,-1938.9,1.17,4},{-603.6,-2127.3,1.35,1},{-585.0,-2136.9,0.91,1},{-595.9,-2110.3,1.2,4},{-380.8,-1990.5,1.03,1},
		{-389.0,-2011.0,1.3,1},{-393.0,-2024.5,0.83,1},{-392.1,-1990.7,1.17,3},{-391.6,-1980.3,0.77,4},{-382.6,-2003.0,1.16,4},{-376.2,-1941.6,1.08,3},{-417.1,-1961.3,1.16,1},{-396.6,-1938.1,0.84,1},
		{-390.9,-1962.1,1.18,3},{-383.7,-2042.4,1.0,4},{-409.9,-1974.7,0.75,4},{-522.4,-2101.2,0.83,3},{-505.4,-2087.4,1.02,3},{-522.8,-2114.9,1.19,1},{-532.5,-2123.3,1.03,3},{-546.8,-2072.6,1.09,3},
		{-516.9,-2135.4,1.33,3},{-599.4,-2080.9,1.31,1},{-615.4,-2045.1,1.27,4},{-604.4,-2068.1,0.76,4},{-585.0,-2052.9,1.14,4},{-507.5,-1904.8,1.27,3},{-602.7,-2039.2,1.23,1},{-576.4,-2069.4,0.96,1},
		{-595.7,-2030.7,1.26,4},{-569.3,-2031.9,0.98,3},{-561.1,-2048.2,1.06,3},{-556.2,-2052.3,1.06,4},{-532.8,-2070.8,0.9,3},{-581.3,-2034.6,1.28,1},{-557.5,-2069.4,1.13,3},{-576.0,-2092.2,1.11,4},
		{-544.1,-2051.5,0.82,4},{-443.2,-2081.4,1.04,1},{-445.2,-2055.5,1.1,1},{-426.6,-2043.9,1.23,3},{-459.1,-2059.6,1.26,1},{-446.6,-2089.6,1.19,4},{-437.2,-2056.5,0.81,4},{-435.1,-2082.4,0.85,4},
		{-463.5,-2079.9,0.73,4},{-557.2,-2122.3,1.2,3},{-484.0,-2053.8,0.92,3},{-683.2,-2165.6,1.33,3},{-374.1,-2135.0,1.01,1},{1137.8,2167.7,0.68,1},{793.4,2004.6,0.75,1},{611.4,1775.6,0.99,1},
		{609.1,1714.1,0.94,1},{1306.0,1702.1,0.68,1},{1363.6,1699.1,0.87,1},{1606.0,1833.0,0.86,1},{1618.5,1861.8,0.81,1},{1873.9,2231.2,0.69,1},{1128.8,2074.6,1.0,1},{1123.6,2100.3,0.84,1},
		{1118.7,2081.6,1.31,3},{1153.6,2130.1,0.95,4},{1134.5,2084.7,1.23,4},{1123.8,2081.9,0.89,4},{1089.5,2085.2,1.2,4},{1124.4,1919.6,1.34,1},{1128.5,1882.8,0.83,1},{1134.0,1910.1,1.06,1},
		{1137.7,1899.5,0.75,4},{1165.8,2009.9,1.25,3},{1176.2,1998.4,1.25,1},{1179.7,1971.1,1.12,1},{1168.0,1981.0,1.33,1},{1156.3,2007.9,1.08,4},{1153.7,1957.7,0.91,4},{1130.7,2049.6,1.21,4},
		{1173.0,2053.3,0.94,1},{1153.0,2084.9,1.23,3},{1176.0,2074.8,0.88,1},{1172.6,2101.2,1.07,1},{1180.9,2101.7,1.0,4},{711.7,1767.5,1.07,1},{656.2,1802.9,0.85,4},{747.6,1791.4,1.17,4},
		{1281.5,2003.0,1.1,1},{1291.2,1977.1,1.12,1},{1293.6,1991.6,0.97,1},{1285.8,1992.4,0.89,4},{1275.4,2004.2,0.82,4},{875.2,1817.9,1.29,1},{877.9,1831.6,1.17,3},{890.2,1795.3,0.82,1},
		{890.5,1801.6,0.79,4},{908.3,1846.0,1.22,4},{1308.6,2051.9,1.13,3},{1290.8,2045.4,0.96,1},{1274.3,2052.1,0.89,4},{1271.0,2041.1,1.18,4},{1299.0,2023.7,0.71,4},{1145.2,1776.0,1.06,1},
		{1137.1,1762.0,0.99,3},{1086.5,1727.3,0.92,1},{1143.5,1740.8,1.13,3},{1114.5,1748.9,1.12,3},{1159.2,1752.0,1.01,3},{1136.4,1809.5,1.16,4},{1114.3,1761.8,1.22,4},{739.7,1758.1,0.92,1},
		{729.4,1817.9,1.03,1},{728.7,1757.9,1.14,4},{753.5,1784.2,1.22,4},{758.7,1786.4,0.77,4},{991.2,1815.4,0.97,3},{987.2,1794.3,0.99,1},{936.8,1830.0,1.34,1},{978.0,1822.5,1.08,3},
		{965.2,1838.5,1.09,1},{985.7,1830.9,1.16,1},{968.0,1795.0,1.32,1},{1006.4,1854.7,1.05,4},{1000.2,1764.5,0.94,4},{1354.6,1892.3,1.0,1},{1375.4,1893.5,1.19,1},{1371.1,1903.6,1.06,1},
		{1356.1,1899.6,0.74,4},{1341.0,1890.0,1.27,4},{1340.2,1876.3,0.94,4},{724.8,1865.5,0.82,1},{732.8,1856.7,0.81,1},{721.8,1844.2,1.12,3},{728.4,1853.9,1.22,4},{721.4,1869.8,0.86,4},
		{703.2,1852.5,1.25,4},{937.1,1938.1,0.88,1},{941.4,1925.1,1.32,1},{966.9,1920.8,1.23,3},{959.7,1949.7,1.16,1},{957.7,1927.4,0.84,3},{926.8,1919.1,1.27,3},{978.5,1940.2,0.86,1},
		{925.2,1933.9,0.88,3},{957.5,1941.3,0.98,4},{1559.9,1855.4,1.3,3},{1536.4,1840.3,0.88,1},{1535.7,1852.2,1.03,3},{1546.5,1836.6,1.14,4},{1099.1,1802.6,0.82,1},{1117.1,1793.8,0.99,3},
		{1077.9,1825.8,0.83,3},{1084.6,1816.8,1.1,4},{971.5,1771.7,1.05,3},{988.3,1767.6,1.3,1},{1012.8,1744.6,0.86,4},{1514.9,1996.0,1.04,1},{1553.0,1968.7,1.29,3},{1509.0,1947.7,0.82,3},
		{1462.8,1942.8,0.75,4},{1540.4,1984.8,1.1,4},{1070.5,1879.0,0.84,1},{1061.3,1863.2,0.96,1},{1118.1,1837.0,0.96,1},{1065.4,1830.2,1.3,1},{1126.7,1852.0,1.32,3},{1090.7,1841.6,1.02,1},
		{1061.7,1836.9,0.82,4},{932.0,2071.2,1.04,1},{931.7,2058.7,1.35,3},{917.2,2067.0,1.29,3},{930.5,2043.8,0.9,4},{828.0,1888.5,0.85,1},{829.0,1871.1,1.09,1},{821.9,1854.2,1.19,1},
		{844.9,1870.0,0.97,3},{862.1,1884.6,0.93,1},{825.7,1908.2,1.1,4},{1146.3,1994.3,1.23,1},{1148.5,2022.1,0.8,3},{1127.7,1996.3,0.83,1},{1156.7,2031.5,0.84,1},{1172.5,2002.3,0.94,4},
		{1150.2,2028.1,1.04,4},{849.9,1891.5,0.82,1},{836.3,1887.7,0.86,4},{821.9,1892.9,0.95,4},{842.2,1889.0,1.29,4},{1115.3,1701.0,0.84,3},{1079.0,1705.7,1.03,1},{1081.4,1693.9,1.34,1},
		{1119.8,1716.7,1.24,1},{902.9,1801.0,1.0,1},{889.8,1833.1,1.25,3},{898.8,1813.5,0.93,3},{903.7,1789.3,1.2,4},{866.8,1812.9,1.01,4},{894.3,1816.8,1.14,4},{895.1,1822.3,0.79,4},
		{1317.3,1843.4,1.33,3},{1368.7,1824.0,0.91,3},{1346.7,1849.7,1.26,1},{1344.4,1834.5,1.04,1},{1335.0,1803.7,0.94,1},{1379.1,1862.3,1.08,1},{1333.7,1844.6,1.24,3},{1351.5,1818.1,0.73,4},
		{1344.6,1865.2,1.1,4},{1325.1,1825.7,0.77,4},{902.4,1965.6,0.88,3},{889.3,1972.1,0.88,1},{872.0,1948.1,0.91,3},{907.0,1999.9,1.11,1},{863.5,1983.5,1.0,3},{903.8,1949.8,1.12,1},
		{921.9,1971.4,1.16,4},{894.8,1980.3,0.72,4},{1510.3,1811.0,0.84,1},{1474.9,1780.6,0.97,1},{1479.9,1794.4,1.15,3},{1493.1,1801.4,0.9,1},{1461.0,1806.2,0.76,4},{1457.9,1761.8,0.92,4},
		{1391.9,1987.1,1.29,1},{1412.6,1957.3,1.03,3},{1411.3,1997.9,1.25,1},{1396.5,1961.8,0.96,3},{1376.5,1966.9,1.07,1},{1403.9,1967.1,0.74,4},{1378.6,1959.9,1.29,4},{1395.7,1945.5,0.97,4},
		{1519.8,1830.9,1.1,3},{1513.7,1848.7,1.27,3},{1537.4,1823.0,0.92,3},{1539.1,1833.7,0.96,4},{1532.3,1833.3,1.17,4},{1314.7,2029.7,0.86,1},{1281.9,2027.5,1.24,1},{1298.6,2047.3,1.08,4},
		{1289.6,2051.4,0.98,4},{1281.2,2035.5,0.79,4},{1441.9,2105.1,0.97,1},{1466.5,2111.8,0.83,1},{1472.8,2130.2,1.33,3},{1457.5,2135.5,1.33,3},{1488.4,2122.5,1.1,4},{1150.2,2113.8,0.93,1},
		{1169.6,2114.9,1.18,1},{1150.9,2143.5,0.88,1},{1132.8,2122.0,1.23,1},{1160.7,2104.5,1.11,1},{1157.9,2139.9,0.87,4},{1211.0,1708.2,0.86,3},{1179.3,1717.7,1.05,3},{1180.6,1736.9,1.07,3},
		{1159.5,2120.5,0.85,1},{1161.8,2136.4,0.96,4},{1143.8,2136.2,0.89,4},{694.9,1759.1,1.27,1},{667.6,1786.7,0.85,1},{695.6,1787.3,0.89,3},{686.3,1831.6,1.22,1},{714.1,1808.1,0.93,4},
		{658.0,1775.4,0.91,4},{652.5,1811.6,0.78,4},{1356.6,1944.7,0.85,3},{1363.2,1956.4,0.98,3},{1364.8,1914.3,1.23,4},{1399.8,1930.9,1.24,4},{1330.8,1867.1,0.81,1},{1370.3,1854.1,1.31,1},
		{1442.4,1862.4,1.33,1},{1449.7,1852.7,1.07,3},{1445.8,1833.7,1.11,1},{1431.9,1868.9,1.0,1},{1465.4,1852.9,1.32,3},{1486.2,1874.5,1.09,4},{1436.8,1842.5,1.09,4},{1421.8,1970.6,1.07,3},
		{680.8,1641.7,1.22,1},{682.2,1624.6,0.81,3},{693.8,1648.7,1.24,1},{1346.9,1745.3,1.06,3},{1352.8,1727.4,1.2,3},{1335.5,1729.8,1.26,3},{1351.3,1763.6,1.02,3},{1329.3,1755.2,0.94,1},
		{1336.1,1739.9,1.29,4},{1374.8,1740.7,0.74,4},{1046.0,1802.1,0.88,1},{1061.8,1800.9,1.18,1},{1058.8,1811.5,1.01,1},{1069.6,1820.8,0.76,4},{1048.2,1815.8,0.97,4},{1064.3,1816.6,1.22,4},
		{779.3,1821.2,1.0,3},{766.8,1815.3,0.87,1},{793.7,1821.6,0.82,3},{776.6,1805.8,0.89,3},{761.0,1842.4,1.1,1},{789.0,1845.7,1.28,3},{1664.0,1868.5,0.98,3},{1647.8,1891.7,1.05,1},
		{1668.6,1886.8,1.09,1},{1698.7,1876.0,1.21,1},{1637.1,1880.8,1.26,4},{1644.9,1880.8,1.01,4},{773.4,1950.4,0.93,3},{798.8,1941.7,0.86,1},{796.6,1949.4,1.15,4},{874.3,1937.0,1.14,1},
		{909.3,1969.5,0.86,4},{851.8,1944.1,1.18,4},{1243.9,1914.7,0.8,1},{1226.2,1936.8,0.85,1},{1187.4,1955.9,1.02,1},{1202.6,1942.5,1.03,3},{1206.0,1907.4,1.09,4},{1224.6,1878.7,0.96,4},
		{1219.1,1902.2,0.71,4},{722.7,1816.7,1.19,4},{1236.2,2001.7,1.01,1},{1260.0,2016.1,1.03,1},{1248.7,2009.9,1.33,3},{1220.5,1990.0,1.28,3},{1207.6,2035.3,0.97,3},{1241.2,1992.4,0.71,4},
		{1230.0,2006.7,0.82,4},{1491.2,2099.1,0.8,1},{1470.4,2081.2,0.98,3},{1511.1,2084.7,1.22,3},{1529.5,2087.0,0.96,1},{1503.1,2096.7,0.86,1},{1506.7,2092.6,0.98,4},{1481.5,2111.3,1.04,4},
		{1633.2,1893.5,1.34,3},{1612.5,1895.8,1.03,1},{1599.5,1892.9,1.06,1},{1059.6,1759.7,0.85,1},{1100.0,1733.5,1.06,3},{1106.4,1747.6,1.14,4},{1100.3,1723.6,0.94,4},{1076.9,1731.4,1.06,4},
		{1272.6,2127.7,0.86,3},{1258.4,2143.9,1.2,1},{1298.3,1963.9,0.86,1},{1312.8,1957.5,1.15,1},{1300.8,1948.9,0.84,1},{1276.7,1956.6,1.26,1},{1286.8,1961.6,0.91,1},{1279.6,1950.6,1.26,4},
		{1258.3,1945.4,0.98,4},{1298.1,1983.7,0.82,4},{1314.1,1946.1,0.97,4},{756.4,1819.4,1.31,3},{739.7,1808.8,0.81,1},{720.7,1791.9,0.82,4},{720.1,1830.8,0.78,4},{861.5,1846.2,1.27,3},
		{854.3,1860.4,1.26,1},{871.2,1865.4,1.19,1},{858.3,1828.8,0.87,4},{1063.4,2019.1,0.83,1},{1070.5,2005.1,1.29,1},{1096.0,2005.5,1.17,3},{1077.3,2001.2,1.02,4},{712.5,1737.2,0.91,3},
		{719.4,1750.3,0.83,3},{699.2,1737.9,1.24,4},{1246.5,1931.5,0.87,1},{1234.2,1957.7,1.18,1},{1247.8,1969.1,1.21,3},{1239.9,1944.0,1.19,4},{852.1,1910.6,1.23,3},{816.2,1843.7,1.01,1},
		{847.2,1901.2,1.25,4},{1401.9,1843.6,1.04,1},{1413.1,1846.3,1.01,1},{1406.2,1868.2,0.83,3},{1410.1,1871.8,0.76,4},{1424.9,1839.7,1.2,4},{1398.7,1858.0,1.04,4},{1170.9,1785.9,1.33,1},
		{1166.7,1822.4,1.2,3},{1183.3,1827.3,1.16,1},{1171.6,1808.1,0.84,1},{1144.5,1795.8,0.88,3},{1156.4,1811.1,1.34,3},{1162.3,1796.8,0.76,4},{782.7,1773.2,1.29,1},{778.9,1792.4,0.99,1},
		{793.2,1791.8,1.03,1},{1298.0,2104.8,1.36,3},{1331.1,2053.4,1.3,1},{1586.7,1968.7,1.04,3},{1028.2,1823.9,0.96,3},{1408.0,2108.6,1.12,3},{1540.9,1928.3,1.37,1},{1090.4,2021.5,1.01,3},
		{763.5,1899.6,0.95,3},{1198.1,2108.7,1.19,3},{886.2,1778.9,1.01,3},{1570.5,2217.9,1.1,1},{1306.6,1912.2,1.39,3},{959.7,1988.1,1.14,3},{1280.1,1929.5,1.32,3},{687.4,1803.9,1.08,1},
		{1299.1,1790.6,1.11,1},{850.2,1785.2,1.31,1},{881.3,2013.7,0.99,3},{1399.1,2163.2,0.96,1},{1400.2,1801.5,1.03,1},{1557.7,1877.0,1.05,3},{1275.7,1812.5,1.25,1},{1483.7,1826.4,1.12,3},
		{1577.0,1983.5,1.24,1},{1495.5,1921.1,1.28,3},{1233.8,2121.0,1.21,3},{1220.5,2083.2,0.97,1},{695.1,1671.1,1.23,1},{2021.9,2256.1,0.88,1},{2005.6,2271.0,0.8,4},{1929.6,2136.5,1.02,1},
		{1902.0,2147.8,0.84,3},{1455.7,1675.1,1.25,1},{756.9,1311.1,1.06,1},{751.3,1287.0,0.85,3},{745.3,1304.1,0.87,3},{730.7,1372.7,0.83,4},{742.3,1315.5,0.88,4},{749.6,1278.4,0.95,4},
		{729.2,1324.9,0.93,4},{1089.7,1262.2,0.99,3},{1110.3,1280.8,1.3,3},{1091.6,1287.7,1.35,1},{1096.1,1271.6,1.16,4},{1097.2,1281.2,0.9,4},{717.4,1363.6,0.81,3},{708.9,1394.0,1.24,1},
		{704.4,1398.1,1.09,4},{732.0,1389.6,1.04,4},{1169.5,1380.2,1.34,1},{1170.2,1391.5,1.28,1},{1158.5,1381.3,1.24,3},{1146.9,1399.1,1.2,3},{1201.6,1362.2,1.05,4},{1191.0,1370.7,1.1,4},
		{1141.2,1376.2,1.17,4},{1213.9,1353.7,1.26,4},{304.9,1279.3,1.08,1},{305.8,1258.3,0.9,1},{282.4,1244.6,0.93,3},{292.1,1253.7,1.11,1},{294.6,1266.4,1.08,3},{314.3,1243.9,0.98,4},
		{293.5,1260.7,0.79,4},{329.7,1239.6,0.97,4},{278.2,1255.5,1.2,4},{221.4,1275.3,1.14,1},{191.8,1229.2,1.1,1},{182.2,1257.8,1.3,3},{230.6,1309.0,0.81,1},{182.8,1279.0,0.77,4},
		{691.2,1257.5,0.97,3},{677.9,1251.5,1.12,1},{668.9,1257.9,0.86,4},{674.2,1277.0,0.8,4},{683.5,1242.5,0.91,4},{656.9,1262.5,1.11,4},{780.0,1345.9,1.14,1},{779.1,1297.3,1.1,3},
		{755.4,1297.4,1.18,4},{771.3,1330.1,0.88,4},{773.4,1325.2,0.99,4},{861.1,1447.8,1.31,1},{874.4,1454.5,0.95,1},{876.0,1473.1,1.19,1},{864.3,1441.4,0.71,4},{1134.3,1425.4,1.19,1},
		{1114.4,1375.0,0.86,3},{1104.7,1350.0,1.0,3},{1102.4,1378.8,1.16,4},{372.6,1246.9,1.13,3},{355.9,1275.7,1.18,1},{346.9,1219.8,0.82,3},{357.6,1199.1,1.11,1},{377.9,1218.3,0.96,1},
		{383.8,1262.9,0.91,1},{341.5,1248.5,1.0,1},{382.4,1200.6,0.74,4},{311.0,1197.2,1.28,1},{327.9,1163.7,1.33,1},{312.4,1176.3,0.86,3},{365.1,1174.0,1.2,1},{283.5,1174.2,1.23,1},
		{297.9,1146.4,1.03,4},{1025.8,1443.4,1.24,1},{1034.1,1437.5,0.8,4},{1053.1,1465.5,0.94,4},{672.9,1220.4,1.0,1},{669.6,1191.8,1.26,3},{642.0,1223.5,1.28,3},{692.8,1190.9,0.95,1},
		{661.6,1248.2,1.02,3},{697.6,1194.9,0.79,4},{692.7,1200.6,1.13,4},{689.1,1179.1,0.93,4},{451.5,1240.6,1.15,3},{430.3,1231.1,1.1,1},{435.6,1248.8,0.88,1},{474.2,1269.2,1.09,3},
		{452.4,1257.2,0.94,3},{468.2,1286.7,1.02,1},{432.4,1241.5,0.98,4},{1092.9,1322.4,1.13,1},{1079.9,1345.9,0.87,3},{1075.1,1366.0,1.21,1},{1090.6,1377.8,1.05,1},{1110.9,1333.8,0.7,4},
		{1476.7,1552.6,1.34,1},{1507.6,1513.7,0.83,1},{1489.2,1494.3,1.1,4},{1492.4,1519.2,1.14,4},{439.7,1178.8,1.03,3},{394.5,1154.3,1.15,3},{407.5,1170.9,1.33,3},{435.0,1172.8,1.07,4},
		{411.8,1166.8,1.1,4},{410.5,1177.1,1.02,4},{1114.8,1485.7,0.97,1},{1113.4,1437.4,1.01,3},{1070.9,1437.8,1.31,3},{1102.2,1474.1,1.23,1},{1092.0,1458.8,0.83,3},{1102.9,1454.0,1.14,4},
		{1123.5,1443.0,0.77,4},{1575.9,1356.4,1.24,3},{1602.0,1369.9,1.21,1},{1593.0,1376.9,0.84,1},{1593.3,1358.1,1.31,1},{1564.1,1372.7,1.2,1},{1581.4,1369.5,1.06,4},{544.1,1167.8,1.22,1},
		{561.0,1145.3,1.31,1},{903.7,1398.3,0.97,3},{898.5,1430.7,0.86,3},{889.4,1411.6,0.82,1},{884.0,1387.9,1.19,1},{949.1,1424.4,0.97,4},{1190.2,1340.1,0.98,3},{1176.1,1344.2,1.34,1},
		{1175.0,1332.4,0.86,1},{1203.4,1330.1,0.91,4},{1197.8,1335.1,0.73,4},{1510.9,1366.3,1.04,3},{1496.3,1394.1,1.16,3},{1476.0,1385.6,1.35,1},{1494.3,1379.7,1.24,1},{1497.8,1349.7,1.22,4},
		{1493.2,1371.4,1.27,4},{1522.8,1389.4,0.91,4},{287.9,1366.9,1.07,3},{278.9,1359.2,0.95,3},{284.1,1348.6,0.75,4},{228.1,1246.7,1.21,1},{234.5,1266.1,1.04,3},{219.9,1258.5,1.01,3},
		{244.3,1260.8,1.23,1},{243.9,1277.1,0.81,3},{230.3,1262.2,0.72,4},{234.8,1230.4,1.02,4},{240.7,1273.1,1.08,4},{917.8,1226.7,1.05,1},{907.1,1217.3,0.87,1},{1045.8,1373.8,0.92,3},
		{1068.7,1375.9,1.35,3},{1059.2,1362.9,0.92,3},{1057.2,1374.9,1.02,3},{1019.5,1366.0,1.08,4},{1064.9,1385.5,1.06,4},{1046.0,1354.3,1.01,4},{906.5,1443.6,0.75,4},{929.7,1437.3,1.22,4},
		{869.1,1467.0,0.93,4},{785.8,1308.5,0.81,1},{798.6,1296.9,0.81,1},{800.3,1270.0,0.99,1},{814.8,1309.9,0.81,3},{774.0,1285.8,0.8,4},{809.1,1275.3,1.08,4},{372.3,1230.5,0.96,1},
		{403.9,1237.6,1.12,1},{367.7,1213.7,1.17,3},{360.9,1264.0,1.1,3},{868.0,1276.2,0.92,1},{852.1,1266.6,1.13,3},{836.4,1282.2,0.84,1},{862.7,1256.9,1.22,3},{833.9,1345.5,1.21,4},
		{921.3,1376.6,1.3,1},{903.3,1374.8,1.32,3},{901.6,1413.2,1.14,1},{892.6,1400.1,0.9,3},{789.6,1324.4,1.03,1},{800.8,1329.7,1.18,3},{805.0,1316.4,1.05,3},{811.5,1334.9,1.04,4},
		{430.2,1350.9,1.13,1},{402.2,1349.4,1.16,1},{670.6,1387.2,0.84,3},{695.3,1382.6,0.85,1},{684.1,1381.3,1.13,3},{684.4,1369.9,0.91,4},{855.5,1242.6,1.09,1},{873.5,1244.3,0.99,1},
		{842.0,1240.6,1.08,1},{841.9,1271.9,0.82,4},{896.0,1286.2,0.84,4},{873.4,1311.4,0.82,4},{452.6,1380.1,0.95,1},{411.5,1358.2,1.26,4},{255.0,1327.2,1.25,1},{238.9,1345.7,1.28,1},
		{234.8,1331.4,1.28,1},{251.0,1339.6,0.98,1},{239.3,1327.9,0.8,4},{246.4,1314.2,0.94,4},{545.3,1346.4,0.82,3},{579.7,1346.5,1.02,1},{554.3,1317.6,1.23,4},{575.9,1351.5,1.24,4},
		{865.5,1424.6,1.17,1},{851.6,1409.8,0.87,1},{841.3,1413.6,0.99,1},{827.3,1421.7,1.23,1},{850.9,1438.1,0.81,3},{849.5,1404.3,0.93,4},{856.7,1391.0,1.11,4},{836.3,1434.3,0.76,4},
		{1286.2,1457.7,1.08,3},{1282.1,1442.3,0.97,3},{1301.4,1429.3,1.12,4},{1278.9,1462.7,0.97,4},{1304.9,1477.8,1.28,4},{1296.8,1476.4,0.98,4},{917.9,1389.5,1.07,1},{893.7,1386.6,1.06,4},
		{1354.7,1435.9,0.96,1},{1359.4,1479.1,1.11,3},{1309.1,1458.4,1.23,3},{1343.5,1436.2,0.87,3},{1319.9,1436.0,1.04,1},{1359.2,1444.2,1.04,4},{300.4,1229.8,1.2,1},{311.9,1222.8,1.24,1},
		{299.8,1243.2,1.09,3},{312.6,1209.9,1.19,4},{317.7,1234.6,0.97,4},{659.8,1413.0,1.33,1},{1135.6,1468.6,1.1,3},{1124.8,1460.0,1.32,1},{1142.6,1480.5,0.96,1},{1106.8,1458.7,0.73,4},
		{1142.1,1432.7,1.28,4},{1138.9,1452.7,0.83,4},{930.8,1316.0,0.85,3},{921.7,1328.4,1.27,1},{886.7,1330.5,1.01,1},{941.1,1295.3,1.33,3},{951.4,1330.4,0.92,3},{893.6,1334.2,0.77,4},
		{966.3,1314.2,1.07,4},{616.1,1234.8,1.24,1},{628.8,1231.6,1.28,1},{621.2,1206.1,0.94,1},{636.8,1201.1,0.84,1},{614.1,1221.4,1.22,1},{609.4,1208.4,1.19,3},{597.9,1204.7,1.17,4},
		{1245.4,1307.6,1.31,3},{1238.0,1297.7,0.88,3},{1237.1,1290.9,1.2,4},{1265.9,1426.4,0.82,3},{1259.3,1440.7,0.9,3},{1282.8,1412.5,0.72,4},{1273.2,1436.7,1.29,4},{1297.5,1376.6,1.13,3},
		{1283.1,1352.9,1.19,1},{1304.1,1387.5,1.12,1},{1301.7,1350.9,0.93,4},{1269.6,1374.4,1.27,4},{1307.1,1382.5,0.93,4},{911.0,1321.7,0.94,3},{918.7,1310.4,0.96,1},{948.9,1276.5,1.34,1},
		{934.3,1327.2,0.82,1},{923.4,1343.4,1.17,1},{936.0,1366.9,0.75,4},{723.9,1299.9,0.85,1},{738.6,1282.6,1.12,1},{740.4,1268.4,1.35,1},{557.0,1272.9,1.35,3},{570.6,1269.8,1.22,1},
		{602.5,1271.9,1.34,3},{605.2,1243.7,1.16,1},{596.9,1271.2,1.22,4},{605.4,1223.5,1.0,4},{1465.5,1378.3,1.2,1},{1455.4,1359.4,0.95,1},{1455.3,1372.6,1.32,1},{1479.4,1362.0,0.85,3},
		{1472.6,1377.2,0.95,4},{860.8,1298.7,1.31,1},{889.9,1268.6,1.16,1},{876.9,1297.3,0.93,4},{862.1,1310.3,0.87,4},{726.1,1270.5,1.24,4},{752.6,1305.7,1.09,4},{732.2,1293.1,1.1,4},
		{718.4,1280.1,1.12,4},{454.0,1183.1,1.12,3},{455.6,1157.9,1.06,1},{446.7,1169.3,0.88,3},{449.0,1188.9,0.85,4},{369.3,1351.3,1.04,1},{350.2,1378.0,1.08,3},{358.6,1360.3,1.31,3},
		{1414.9,1420.8,1.08,3},{101.0,1315.7,1.24,3},
	},
}
]])
put(folder4, "ModuleScript", "LondonFillData4", [[
--!nocheck
-- Part 4 of the data in LondonFill. MADE BY tools/london_fill.py: don't edit by hand.
return {
	buildings = {
	},
	gardens = {
	},
	walls = {
	},
	trees = {
		{1163.4,1460.5,1.25,1},{142.3,1274.7,1.39,3},{1446.2,1395.9,0.97,1},{569.1,1325.3,1.23,3},{210.6,1298.2,1.11,1},{116.7,1351.6,1.32,1},{127.1,1365.1,1.05,3},{527.5,1219.5,1.31,1},
		{1514.4,1446.2,1.04,1},{1184.7,1422.8,1.39,1},{606.7,1405.5,1.26,1},{520.1,1284.9,1.27,1},{597.0,1434.0,1.37,1},{73.7,1333.7,1.01,3},{255.9,1199.5,1.12,3},{1360.9,1412.3,0.94,1},
		{1420.0,1377.2,0.93,1},{1541.3,1514.7,1.36,3},{756.7,1388.7,1.29,3},{353.8,1131.7,1.22,3},{1344.5,1317.9,1.33,3},{1700.0,1409.0,1.24,3},{384.3,1687.2,0.69,1},{445.7,1686.0,0.82,1},
		{478.4,1722.1,0.89,1},{449.4,1731.9,0.96,4},{-29.3,1625.0,0.74,1},{27.0,1666.7,0.97,1},{58.1,1688.7,0.86,1},{109.5,1731.4,0.91,1},{3.6,1783.5,0.6,1},{-83.7,1764.4,0.86,1},
		{-106.3,1511.6,0.9,1},{-97.6,1504.3,1.18,1},{-98.4,1509.2,0.85,4},{-79.0,1831.4,1.11,1},{-41.2,1713.3,0.84,4},{-39.6,1743.5,0.81,1},{13.1,1686.8,1.13,1},{-0.2,1723.1,1.14,3},
		{-12.7,1755.7,0.83,3},{12.2,1735.3,1.19,1},{-21.3,1687.5,1.19,1},{-30.5,1693.7,1.32,1},{-17.8,1756.1,0.7,4},{6.8,1712.4,0.96,4},{1.4,1715.5,1.02,4},{-58.1,1799.3,1.37,1},
		{-100.7,1574.9,1.33,3},{214.7,1591.5,0.97,1},{61.6,1510.5,0.82,3},{246.3,1658.3,1.25,1},{709.8,2196.1,0.79,1},{639.1,2198.2,0.76,1},{558.0,2206.1,0.95,1},{1836.8,-1521.2,0.97,1},
		{2050.7,-1689.0,0.87,1},{2389.3,-1786.1,0.86,1},{2499.4,-1710.5,0.71,1},{2645.6,-1493.2,0.61,1},{2587.1,-1094.7,0.94,1},{2571.4,-1072.9,0.68,1},{2507.5,-906.9,0.85,1},{2430.4,-793.1,0.96,1},
		{2413.0,-743.5,0.86,1},{1906.4,-597.9,0.6,1},{1590.1,-563.2,0.91,1},{1600.7,-588.5,0.86,1},{1587.1,-717.3,0.97,1},{1590.3,-843.3,0.83,1},{1566.1,-1044.4,0.67,1},{2126.5,-1382.7,1.21,3},
		{2102.5,-1411.9,1.27,1},{2115.1,-1375.9,1.15,1},{2116.9,-1361.6,1.22,1},{2085.4,-1355.8,0.85,1},{2107.7,-1400.4,1.14,1},{2112.8,-1384.3,1.0,4},{2098.8,-1370.2,0.98,4},{2085.5,-1403.4,1.27,4},
		{1855.3,-970.0,1.18,1},{1812.9,-968.0,0.92,1},{1833.5,-956.8,1.32,1},{1840.4,-972.9,0.97,1},{1824.8,-975.0,1.22,1},{1854.4,-991.9,0.96,1},{1848.7,-960.1,1.22,4},{1819.5,-998.0,0.92,4},
		{1845.6,-949.5,1.02,4},{2125.0,-941.8,1.17,3},{2114.0,-974.8,1.26,1},{2121.8,-946.1,1.06,4},{2108.2,-954.8,0.9,4},{1773.8,-814.1,0.95,3},{1763.5,-823.3,1.2,1},{1759.7,-813.0,0.84,1},
		{1761.8,-800.1,0.8,4},{1775.1,-796.6,0.89,4},{1752.3,-815.2,1.23,4},{1961.4,-706.8,0.91,1},{1949.0,-717.9,0.8,3},{1970.4,-727.4,0.77,4},{1970.1,-705.7,1.28,4},{1977.1,-734.7,0.84,4},
		{1855.4,-1333.7,0.81,3},{1866.9,-1293.1,0.8,3},{1839.5,-1371.0,1.2,1},{1826.6,-1329.6,1.3,1},{1857.5,-1368.5,1.27,3},{1849.4,-1340.4,1.28,4},{1834.7,-1303.8,0.9,4},{1876.6,-1289.3,1.18,4},
		{1883.7,-1335.8,1.11,4},{1876.2,-839.6,1.28,1},{1854.3,-834.0,0.99,1},{1819.6,-861.1,1.08,1},{1843.7,-839.8,1.33,1},{1855.0,-866.5,1.31,1},{1832.4,-866.9,1.04,1},{1844.0,-869.2,1.32,3},
		{1831.1,-882.2,1.24,4},{1822.5,-1212.4,1.2,1},{1842.4,-1201.2,1.29,1},{1851.3,-1210.3,1.06,1},{1806.1,-1224.1,1.24,3},{1821.0,-1227.9,1.14,3},{2379.3,-1345.8,1.3,1},{2378.7,-1310.2,0.87,3},
		{2366.9,-1322.9,1.18,4},{2382.9,-1337.1,0.93,4},{2400.8,-1327.2,0.88,4},{2636.9,-1272.4,1.01,1},{2645.8,-1261.6,1.05,3},{2627.3,-1241.9,1.24,4},{1923.9,-729.9,0.81,1},{1948.2,-734.4,1.1,1},
		{1934.5,-681.3,1.32,3},{1928.3,-748.5,0.86,4},{1933.8,-1480.5,0.96,3},{1884.8,-1508.9,1.16,1},{1880.7,-1483.1,1.27,1},{1917.8,-1497.0,1.12,1},{1891.7,-1456.4,1.08,1},{1908.9,-1481.0,1.16,4},
		{1896.7,-1490.9,0.9,4},{1630.9,-875.1,0.92,1},{1631.3,-900.9,0.96,4},{1626.2,-866.1,1.08,4},{1805.5,-714.1,1.06,3},{1865.5,-767.5,1.29,3},{1867.9,-736.2,1.04,3},{1893.8,-760.4,0.78,4},
		{1828.1,-773.3,0.91,4},{2148.0,-1494.5,1.31,3},{2139.9,-1514.6,0.9,1},{2122.1,-1486.6,1.02,1},{2116.5,-1507.5,0.84,3},{2131.9,-1491.8,0.93,3},{2116.1,-1491.4,1.2,4},{2128.1,-1483.1,1.28,4},
		{2121.8,-1531.1,1.19,4},{2129.4,-1501.5,0.99,4},{2272.8,-864.5,0.81,3},{2299.9,-885.2,1.16,1},{2286.2,-908.7,0.97,3},{2294.1,-902.7,1.24,4},{1941.1,-955.9,1.21,3},{1944.6,-941.9,1.11,1},
		{1925.6,-952.6,1.3,1},{1916.3,-932.8,1.14,4},{1922.3,-937.2,1.02,4},{1935.1,-933.2,0.81,4},{1871.2,-1498.2,0.95,1},{1853.7,-1494.8,1.21,1},{1864.4,-1459.0,1.17,1},{1884.7,-1470.5,1.18,4},
		{1865.2,-1485.8,0.86,4},{2261.2,-1586.0,1.29,3},{2243.5,-1575.5,1.19,1},{2247.3,-1587.9,0.98,1},{2251.5,-1558.5,1.14,3},{2230.2,-1565.8,1.2,4},{2266.0,-1581.1,1.13,4},{2169.3,-1687.2,1.03,3},
		{2173.0,-1704.3,1.23,3},{2157.4,-1697.2,0.96,3},{2150.6,-1714.5,0.88,4},{2163.4,-1701.3,1.01,4},{1864.9,-656.1,1.27,1},{1838.6,-667.1,1.25,3},{1814.6,-657.0,1.26,3},{1851.1,-644.7,1.13,3},
		{1821.2,-678.9,0.92,4},{1846.7,-676.7,0.84,4},{1664.5,-977.7,1.31,3},{1668.2,-994.6,1.21,3},{1637.0,-1003.7,1.34,3},{1641.3,-973.8,1.14,4},{1618.3,-1001.2,1.03,4},{2260.1,-1241.7,1.03,3},
		{2208.3,-1245.0,1.13,1},{2243.8,-1242.6,1.11,1},{2230.1,-1237.8,1.0,1},{2232.0,-1265.7,1.29,1},{2219.1,-1224.3,1.19,1},{2219.8,-1249.2,1.2,1},{2211.0,-1256.2,1.13,4},{2213.1,-1237.0,1.26,4},
		{2639.0,-1352.1,1.06,1},{2621.5,-1331.1,0.88,1},{2635.6,-1364.0,0.86,1},{2617.3,-1389.0,0.98,1},{2631.1,-1378.2,0.93,1},{2604.5,-1350.0,0.87,3},{2597.5,-1376.4,1.24,3},{2614.8,-1377.7,0.95,4},
		{2623.7,-1380.4,0.76,4},{2636.9,-1391.3,0.8,4},{2138.1,-1213.2,0.84,1},{2096.4,-1237.6,1.33,1},{2160.3,-1252.6,0.99,3},{2159.3,-1274.1,0.92,4},{1773.6,-1415.9,0.97,1},{1800.1,-1440.0,1.09,3},
		{1793.8,-1449.5,1.15,1},{1774.2,-1448.5,1.25,1},{1759.7,-1426.8,0.84,1},{1766.9,-1427.7,0.76,4},{1792.1,-1422.1,1.27,4},{1760.5,-1393.5,1.12,4},{1747.2,-1450.6,1.15,4},{2392.0,-1316.4,1.28,1},
		{2381.9,-1296.8,0.98,1},{2371.0,-1327.2,1.12,4},{1785.1,-659.8,0.96,3},{1793.6,-637.1,0.9,1},{1763.9,-644.3,1.21,1},{1772.6,-635.2,1.28,1},{1822.1,-651.5,0.86,4},{1787.8,-640.8,1.06,4},
		{2453.8,-1294.7,1.27,3},{2450.9,-1271.5,1.03,3},{2426.0,-1309.5,1.2,1},{2433.2,-1305.1,1.01,4},{2441.3,-1292.8,1.0,4},{1672.2,-927.8,0.92,1},{1648.7,-920.2,0.81,1},{1665.6,-945.3,0.82,3},
		{1645.3,-933.1,1.05,4},{1652.0,-903.7,1.09,4},{1667.6,-915.2,1.27,4},{2149.1,-1528.0,1.11,1},{2114.4,-1539.5,0.78,4},{1801.5,-1002.5,0.88,1},{1813.9,-1033.0,0.9,3},{1793.9,-987.6,1.26,1},
		{1813.9,-953.2,1.27,4},{2125.0,-1723.5,1.27,1},{2129.0,-1727.9,1.19,4},{2196.8,-1397.0,1.16,1},{2199.3,-1410.2,1.02,3},{2185.2,-1396.3,1.15,1},{2210.8,-1417.9,1.16,4},{2205.8,-1416.7,1.14,4},
		{2514.3,-1561.1,0.84,1},{2543.4,-1524.5,1.08,1},{2534.2,-1532.1,1.31,1},{2496.2,-1504.8,1.29,1},{2558.2,-1556.7,1.32,3},{2560.5,-1526.1,1.25,1},{2505.6,-1495.3,1.09,4},{2546.7,-1531.6,1.25,4},
		{1998.8,-632.8,1.04,1},{2013.4,-640.4,1.07,1},{2015.5,-671.5,1.1,3},{2030.4,-642.6,0.75,4},{2183.8,-1274.0,0.83,1},{2156.6,-1231.8,0.86,1},{2192.7,-1260.8,1.11,1},{2172.7,-1266.7,1.26,1},
		{2193.2,-1231.1,0.82,4},{2192.2,-1247.3,1.05,4},{2580.3,-1466.2,0.88,3},{2605.0,-1431.2,1.18,1},{2601.7,-1447.8,1.31,3},{2578.2,-1451.1,1.24,1},{2588.1,-1439.4,0.92,1},{2602.5,-1471.7,0.9,1},
		{2565.2,-1441.8,1.12,1},{2579.5,-1438.1,1.2,4},{1749.0,-1007.5,0.97,1},{1733.5,-1002.7,0.97,1},{1735.1,-1013.9,1.2,1},{1724.2,-1038.9,1.35,1},{1739.7,-1024.3,1.24,1},{1737.9,-1008.0,0.96,4},
		{1720.8,-1043.3,1.24,4},{1684.1,-889.9,1.24,3},{1688.2,-905.3,1.31,3},{1698.3,-898.2,1.3,1},{1678.9,-912.2,1.07,4},{2276.2,-1014.8,0.8,1},{2283.7,-998.3,1.35,1},{2279.3,-1028.7,1.17,1},
		{2306.4,-1029.7,1.29,4},{2270.9,-966.1,1.09,4},{2259.0,-1049.3,0.79,4},{1726.7,-1023.7,1.3,3},{1748.4,-993.6,0.83,1},{1734.3,-990.0,0.96,3},{1745.7,-1014.5,0.77,4},{1759.5,-1000.7,0.79,4},
		{1646.0,-1189.5,0.84,1},{1668.8,-1200.0,1.2,1},{1651.9,-1164.4,1.01,4},{2286.5,-1467.6,1.15,1},{2306.6,-1443.9,0.87,3},{2264.2,-1455.5,0.92,1},{2297.6,-1468.4,0.9,1},{2277.9,-1442.0,0.98,4},
		{2284.3,-1455.3,1.1,4},{2278.2,-1451.4,1.2,4},{2264.5,-1474.4,0.9,4},{1813.3,-691.0,1.08,1},{1799.8,-685.3,1.0,1},{1832.3,-657.0,1.22,4},{1820.1,-667.4,1.16,4},{2288.7,-722.8,1.02,1},
		{2311.3,-721.8,1.33,1},{2326.6,-703.2,1.15,1},{2325.2,-684.2,0.85,1},{2303.3,-751.0,0.75,4},{2319.3,-740.4,0.89,4},{2321.5,-693.5,0.94,4},{2128.8,-1462.5,0.84,1},{2139.6,-1476.2,0.81,1},
		{2151.0,-1468.2,1.29,1},{2156.6,-1465.1,1.25,4},{2150.4,-1479.0,0.87,4},{2145.5,-1474.1,0.88,4},{2169.5,-1478.9,0.85,4},{2200.7,-1454.4,1.19,1},{2198.7,-1438.7,1.1,3},{2217.3,-1458.0,0.88,3},
		{2202.6,-1467.8,1.32,3},{2211.2,-1435.9,0.9,3},{2215.7,-1445.4,1.05,4},{2177.0,-1452.0,1.26,4},{2214.8,-1429.8,1.11,4},{2334.7,-1069.2,1.02,3},{2323.1,-1076.9,1.03,3},{2297.6,-1109.0,0.86,1},
		{2317.6,-1088.8,0.91,1},{2308.5,-1045.6,0.97,4},{2305.2,-1071.6,0.96,4},{2309.8,-1097.2,0.82,4},{1973.1,-1507.3,0.86,1},{1961.8,-1494.8,1.29,1},{1977.5,-1488.9,1.12,1},{1993.3,-1513.7,1.11,4},
		{1969.1,-1485.1,0.72,4},{1992.8,-1521.4,1.26,4},{1984.9,-1504.8,0.83,4},{2347.8,-1040.6,1.19,3},{2346.1,-1024.6,1.03,1},{2333.5,-1001.8,0.83,3},{2318.5,-1023.2,0.81,1},{2334.6,-1048.7,1.18,1},
		{2320.6,-1012.7,0.83,4},{2331.4,-1053.9,0.7,4},{2329.2,-973.6,0.83,4},{1647.9,-1351.5,1.32,3},{1614.2,-1357.9,1.09,1},{1584.8,-1343.1,1.09,1},{1602.2,-1347.1,1.09,1},{1611.6,-1340.6,1.17,3},
		{1633.3,-1336.1,1.33,1},{1621.4,-1382.9,0.8,1},{1593.8,-1388.9,1.02,4},{1804.1,-1156.5,1.14,3},{1782.1,-1158.8,1.18,3},{1794.7,-1177.5,0.98,1},{1797.3,-1143.3,1.16,1},{1769.5,-1148.2,0.99,4},
		{1785.0,-1143.5,1.28,4},{1631.4,-1198.5,1.05,1},{1642.8,-1202.8,1.02,3},{1628.3,-1206.2,1.02,4},{2194.8,-1782.5,1.35,3},{2188.8,-1795.8,0.88,3},{2209.7,-1777.2,1.27,4},{2176.2,-1795.3,1.29,4},
		{2430.9,-1686.2,1.13,1},{2415.3,-1667.5,1.11,3},{2414.4,-1685.5,1.34,3},{2415.6,-1675.7,0.8,4},{1739.4,-1427.8,0.86,1},{1733.1,-1444.0,1.3,3},{1759.1,-1447.0,0.89,1},{1741.3,-1440.1,1.04,4},
		{1735.5,-1455.7,1.04,4},{2106.3,-736.3,1.13,1},{2104.1,-721.9,0.9,1},{2115.1,-699.3,0.84,1},{2084.0,-732.6,1.16,1},{2075.9,-711.4,1.34,1},{2092.7,-731.2,1.21,4},{2113.7,-713.3,1.08,4},
		{2101.5,-731.3,0.75,4},{1970.8,-1608.0,1.15,3},{1973.9,-1621.4,0.9,4},{1986.5,-1592.0,0.73,4},{1992.9,-1194.0,1.27,3},{1990.0,-1163.4,0.94,1},{1986.2,-1181.5,1.2,1},{1980.0,-1226.0,0.82,3},
		{1982.0,-1195.3,1.14,4},{1486.1,-1372.1,1.04,1},{2021.9,-1402.3,1.15,1},{2037.4,-1430.9,0.82,3},{2003.1,-1433.0,1.03,1},{2022.1,-1414.2,1.07,3},{2026.5,-1459.0,0.83,1},{2028.7,-1410.6,0.88,4},
		{2010.9,-1414.0,0.99,4},{2672.3,-1308.8,0.97,3},{2653.5,-1280.4,1.07,3},{2649.3,-1312.6,1.34,3},{2638.2,-1308.1,1.29,3},{2666.3,-1306.6,0.94,4},{2311.4,-1763.5,1.02,1},{2337.5,-1715.1,0.83,1},
		{2327.3,-1723.6,0.98,3},{2320.1,-1750.2,1.28,3},{2313.0,-1733.2,0.99,4},{2327.2,-1686.2,1.18,4},{1776.8,-679.5,1.27,1},{1790.9,-731.6,0.75,4},{1816.0,-699.2,1.23,4},{1756.9,-684.9,0.71,4},
		{1824.4,-710.5,1.0,4},{2186.8,-851.9,1.12,1},{2173.2,-859.5,1.32,1},{2147.5,-833.5,1.13,4},{2214.5,-1836.3,1.07,1},{2214.7,-1798.7,0.98,1},{2229.1,-1844.1,1.14,4},{2223.2,-1809.8,1.08,4},
		{2189.8,-1810.9,0.87,4},{2298.9,-1416.7,0.76,4},{2273.2,-1451.4,1.05,4},{1625.6,-1066.8,1.2,3},{1604.0,-1053.1,1.21,3},{1586.6,-1079.9,1.18,3},{1611.4,-1061.9,0.99,1},{1594.1,-1042.7,1.25,4},
		{1794.2,-777.5,1.31,1},{1841.9,-774.9,1.21,3},{1818.8,-783.1,0.82,1},{1806.1,-794.3,0.88,1},{1837.1,-784.7,0.83,4},{2474.9,-1081.8,1.23,1},{2528.4,-1083.6,1.35,1},{2519.6,-1076.9,1.05,1},
		{2507.6,-1092.8,1.15,3},{2521.0,-1109.1,0.86,3},{2508.1,-1083.1,0.88,4},{2525.4,-1104.4,1.14,4},{2116.6,-811.4,0.85,1},{2087.7,-804.6,1.28,3},{2124.5,-807.1,0.96,4},{2126.1,-818.4,0.86,4},
		{2100.8,-1658.2,1.19,1},{2090.4,-1633.0,1.23,1},{2096.8,-1647.1,0.81,1},{2076.2,-1621.4,0.94,4},{2112.4,-1682.2,1.14,4},{2046.2,-1593.5,1.22,1},{2046.6,-1577.2,0.83,1},{2077.5,-1581.4,0.82,1},
		{2052.2,-1581.8,1.25,4},{2090.3,-1615.9,0.84,1},{2088.8,-1655.9,1.08,4},{2098.3,-1652.9,0.94,4},{2072.8,-1627.7,0.77,4},{1981.0,-675.2,0.98,1},{2005.2,-713.3,0.91,3},{1989.8,-715.3,1.29,3},
		{2001.7,-693.4,1.21,3},{1959.3,-685.9,1.05,1},{1981.2,-702.8,1.01,1},{1991.7,-660.4,1.15,4},{1932.3,-708.3,0.78,4},{1955.0,-665.9,1.2,4},{1992.3,-728.4,1.16,4},{2407.2,-890.1,1.17,3},
		{2399.7,-863.2,1.27,1},{2393.9,-883.4,1.29,3},{2416.8,-871.2,1.31,3},{2415.3,-885.0,0.86,4},{2692.9,-1356.1,0.92,1},{2721.2,-1384.7,0.89,4},{2182.1,-1321.6,1.08,3},{2202.6,-1314.6,1.06,1},
		{2213.9,-1355.3,0.88,1},{2180.8,-1335.6,1.31,3},{2204.1,-1324.3,1.08,4},{2229.9,-1303.2,1.14,4},{2476.7,-1244.1,1.03,1},{2463.3,-1252.5,1.32,1},{2493.7,-1217.9,1.04,1},{2481.0,-1232.2,1.17,4},
		{2475.0,-1262.5,0.87,4},{2483.8,-1241.3,0.95,4},{2437.9,-862.0,0.98,3},{2426.4,-864.3,1.35,1},{2440.3,-892.6,0.94,1},{2448.2,-901.2,0.86,3},{2432.1,-863.9,0.94,4},{2390.1,-1039.7,1.18,3},
		{2402.4,-1041.3,1.19,1},{2419.4,-1061.7,1.13,1},{2424.7,-1015.9,1.2,1},{2383.0,-1049.4,1.08,1},{2389.0,-1069.5,0.98,1},{2433.6,-1034.3,1.26,3},{2465.4,-1085.5,1.16,4},{1863.1,-1471.6,0.9,1},
		{1816.9,-1459.8,1.09,3},{1864.6,-1499.0,0.89,4},{1832.7,-1496.4,0.96,4},{1857.2,-1457.5,0.89,4},{1802.4,-883.8,1.35,1},{1854.2,-913.1,1.24,1},{1818.1,-897.7,0.82,3},{1835.6,-871.1,1.1,4},
		{1837.5,-888.9,1.27,4},{1843.5,-826.5,1.29,4},{1766.9,-932.2,0.93,4},{1542.9,-1391.0,0.91,1},{1529.2,-1402.0,0.81,1},{1557.9,-1398.4,1.09,3},{1544.8,-1406.3,0.96,4},{1576.2,-1389.2,0.94,4},
		{2358.2,-746.2,0.84,3},{2363.7,-756.5,0.9,3},{2377.8,-744.9,1.05,4},{2341.5,-773.7,0.94,4},{1902.2,-772.3,1.33,1},{1914.0,-779.6,0.87,1},{1905.7,-778.4,1.05,4},{2317.3,-990.6,1.19,3},
		{2360.4,-986.0,1.03,4},{2339.2,-1017.9,0.89,4},{2351.9,-969.9,1.28,4},{2347.5,-991.4,0.79,4},{2190.9,-1732.4,1.25,1},{2196.8,-1708.5,1.21,3},{2213.9,-1725.1,0.96,1},{2187.7,-1762.8,1.03,4},
		{2192.2,-1752.8,0.92,4},{2199.3,-1728.3,0.83,4},{2152.4,-1732.5,1.14,4},{1835.6,-915.4,0.9,1},{1858.0,-932.4,1.13,3},{1838.6,-937.5,0.9,1},{1852.6,-920.2,1.13,4},{1834.0,-920.3,1.09,4},
		{1629.6,-1264.0,1.08,1},{1634.0,-1279.0,1.24,1},{1650.7,-1263.3,1.07,1},{1605.3,-1262.6,1.11,1},{1644.2,-1287.6,1.18,1},{1640.4,-1265.2,0.72,4},{1617.7,-1290.2,0.84,4},{2251.5,-753.9,1.11,1},
		{2273.9,-746.9,1.15,1},{2258.3,-781.6,1.12,1},{2288.6,-799.4,0.91,3},{2250.0,-767.6,1.09,1},{2254.7,-799.4,0.92,1},{2244.5,-804.7,1.24,4},{2253.2,-774.4,1.14,4},{2250.8,-807.6,1.29,4},
		{2249.3,-1063.2,0.85,3},{2261.4,-1076.1,0.98,1},{2226.0,-1044.8,0.98,1},{2213.7,-1072.9,1.11,1},{2274.6,-1066.2,0.87,1},{2242.4,-1046.0,1.24,1},{2256.6,-1070.4,1.01,4},{2238.7,-1088.1,1.19,4},
		{2247.4,-1030.0,0.76,4},{2007.8,-1558.2,0.82,3},{1979.3,-1524.2,1.33,1},{2008.0,-1536.2,1.33,3},{1990.9,-1532.7,1.12,4},{2007.5,-1544.2,0.84,4},{2001.5,-1523.8,0.75,4},{2226.3,-1085.0,1.12,1},
		{2257.3,-1098.9,1.03,1},{2217.9,-1092.8,1.27,1},{2218.6,-1108.3,1.34,3},{2219.6,-1066.8,1.11,4},{2238.7,-1103.1,1.01,4},{2224.5,-1077.9,1.19,4},{2204.3,-1085.3,0.99,4},{2181.3,-787.8,1.09,3},
		{2177.4,-829.6,0.86,3},{2157.7,-826.6,0.93,3},{2195.7,-832.2,1.24,1},{2236.0,-817.1,1.27,3},{2208.4,-827.3,1.13,3},{2157.6,-835.4,0.85,4},{1564.0,-1304.5,1.11,1},{1599.3,-1275.3,1.14,1},
		{1564.7,-1320.7,1.01,1},{1590.2,-1312.6,1.23,1},{1567.2,-1255.0,1.22,3},{1588.4,-1290.9,1.02,4},{1563.3,-1290.2,1.25,4},{1578.9,-1319.1,0.74,4},{1764.4,-622.5,1.25,1},{1802.9,-623.4,0.94,3},
		{1803.6,-645.1,1.1,1},{1800.6,-661.2,1.31,3},{1782.4,-634.6,1.17,4},{1839.7,-648.1,1.03,4},{2384.5,-1558.1,0.84,3},{2396.2,-1547.9,0.95,3},{2384.8,-1569.9,1.13,3},{2397.6,-1582.6,1.19,4},
		{2374.3,-1561.2,1.01,4},{2390.7,-1568.9,0.78,4},{2052.9,-1646.4,1.18,1},{2093.5,-1672.1,1.06,1},{2098.2,-1663.9,1.13,4},{2081.2,-1662.6,1.09,4},{2211.9,-639.3,0.99,1},{2241.7,-1806.0,1.08,3},
		{2265.3,-1831.7,0.9,1},{2248.0,-1823.3,1.24,1},{2249.1,-1840.6,1.13,4},{2569.9,-1259.7,0.91,1},{2557.3,-1276.7,0.87,3},{2561.2,-1241.0,1.14,1},{2574.6,-1246.5,1.08,3},{2573.1,-1251.3,0.81,4},
		{2408.6,-1083.0,1.15,1},{2424.9,-1083.8,1.14,1},{2449.3,-1078.2,0.89,1},{2428.4,-1052.4,1.22,1},{2431.7,-1014.7,0.81,4},{2449.3,-1052.2,1.12,4},{2451.5,-1017.1,0.9,4},{2297.5,-1279.6,0.83,1},
		{2315.3,-1298.0,0.94,1},{2300.5,-1293.3,1.1,1},{2303.9,-1316.5,0.94,3},{2283.9,-1307.0,0.86,1},{2314.6,-1329.0,1.1,3},{2301.1,-1327.0,1.27,4},{2156.9,-1498.5,1.12,4},{2105.1,-1227.8,0.85,1},
		{2082.0,-1221.5,1.04,1},{2096.3,-1217.8,0.91,1},{2123.1,-1249.4,1.3,3},{2103.3,-1208.9,1.2,4},{2070.2,-1229.2,1.25,4},{2070.4,-1235.3,1.1,4},{2022.6,-1621.2,1.14,3},{2043.0,-1619.0,1.25,3},
		{2040.7,-1623.9,1.22,4},{2107.1,-1187.6,0.84,1},{2119.1,-1200.4,1.17,1},{2137.6,-1186.9,0.96,4},{1741.8,-1178.6,1.16,1},{1751.9,-1183.5,1.26,1},{1754.4,-1194.8,1.25,1},{1763.8,-1204.6,1.29,3},
		{1726.5,-1212.5,0.73,4},{1743.0,-1161.6,1.24,4},{1614.8,-1220.3,0.96,3},{1653.0,-1198.3,1.22,3},{1617.1,-1189.4,1.09,3},{1631.4,-1182.3,0.81,4},{1659.3,-1192.2,1.3,4},{1636.2,-1185.9,0.83,4},
		{2136.1,-714.2,0.84,4},{2151.5,-1082.1,0.94,1},{2159.4,-1097.6,1.23,1},{2127.1,-1054.5,1.23,4},{2143.0,-1072.8,1.14,4},{1556.0,-1272.3,1.08,1},{1615.5,-1258.4,1.31,1},{1572.5,-1240.2,1.31,1},
		{1571.7,-1273.5,1.13,3},{1582.5,-1269.0,0.97,3},{1580.3,-1298.5,1.2,3},{2111.7,-849.1,1.34,1},{2100.5,-833.8,0.84,1},{2126.0,-833.1,1.03,4},{2119.3,-846.1,0.84,4},{2127.1,-847.9,1.01,4},
		{1952.7,-1528.3,1.01,1},{1953.7,-1550.8,0.94,3},{1962.5,-1557.4,1.21,3},{1963.5,-1541.8,0.95,1},{1932.5,-1521.3,0.92,4},{1944.9,-1540.5,1.03,4},{1950.8,-1534.5,1.17,4},{1957.3,-1013.4,0.83,3},
		{1939.3,-973.1,1.15,1},{1956.7,-994.9,1.03,3},{1987.7,-1001.1,1.01,4},{1986.8,-984.7,0.71,4},{1915.7,-1008.4,1.14,4},{2118.2,-636.5,0.81,1},{2106.7,-651.9,1.02,1},{2092.7,-646.2,1.0,1},
		{2086.6,-657.5,0.82,1},{2074.3,-636.4,0.9,3},{2070.5,-645.8,1.1,4},{1932.9,-650.8,0.9,3},{1958.2,-635.9,1.1,1},{1934.6,-632.2,1.04,1},{1946.2,-644.6,1.11,4},{1937.3,-643.0,0.78,4},
		{2087.9,-1273.2,0.81,3},{2076.6,-1270.1,0.91,3},{2081.9,-1254.5,1.24,1},{2070.7,-1253.3,0.73,4},{1656.1,-1122.1,1.15,1},{1690.5,-1102.8,1.1,1},{1662.0,-1116.7,1.28,4},{2083.5,-974.8,1.0,3},
		{2079.3,-964.2,1.02,1},{2080.7,-922.6,1.1,3},{2098.3,-963.8,1.28,4},{2118.2,-942.5,1.04,4},{2098.3,-958.8,0.92,4},{2144.5,-936.2,0.91,4},{2306.0,-1711.9,0.8,1},{2301.0,-1723.5,1.02,4},
		{2328.1,-1750.4,1.26,4},{2321.0,-1724.4,0.85,4},{1832.2,-1229.1,0.91,3},{1811.6,-1260.8,1.1,3},{1854.3,-1240.0,0.81,1},{1839.9,-1220.3,1.01,4},{1810.5,-1241.2,1.29,4},{1642.4,-734.3,0.83,1},
		{1631.1,-734.6,1.02,3},{1621.1,-742.9,0.9,1},{1630.0,-751.8,0.98,4},{2124.6,-1280.8,1.29,1},{2094.3,-1325.6,1.14,1},{2107.1,-1350.7,0.91,1},{2093.2,-1297.9,0.92,4},{1630.0,-721.5,1.07,1},
		{1612.8,-767.5,0.96,4},{2195.5,-1821.5,1.1,1},{2169.0,-1793.4,1.29,4},{2278.3,-1341.0,1.07,1},{2308.2,-1357.2,1.21,3},{2295.3,-1338.9,1.15,1},{2278.1,-1382.2,0.95,1},{2250.2,-1369.1,0.97,1},
		{2290.7,-1372.9,1.34,3},{2256.8,-1331.3,0.86,4},{2295.5,-1391.4,0.71,4},{2309.9,-1341.9,1.21,4},{1900.5,-682.8,1.1,1},{1907.5,-708.6,0.97,3},{1900.0,-726.9,1.3,1},{1920.1,-765.0,1.03,4},
		{1943.2,-723.5,0.7,4},{1891.0,-689.4,1.13,4},{1942.1,-747.1,1.09,4},{2432.6,-1436.9,1.31,1},{2437.8,-1422.3,1.27,1},{2395.4,-1396.8,0.89,1},{2423.5,-1388.1,1.33,3},{2404.2,-1445.2,0.92,1},
		{2412.8,-1417.7,1.31,3},{2395.7,-1436.0,1.14,1},{2448.4,-1432.3,1.04,4},{2402.0,-1451.5,0.98,4},{2429.4,-902.0,1.03,1},{2421.2,-909.7,0.94,1},{2429.0,-918.4,0.98,1},{2404.2,-901.2,1.2,1},
		{2427.5,-894.4,1.03,4},{2414.4,-898.6,1.07,4},{2410.9,-925.3,0.83,4},{2405.9,-911.9,0.92,4},{1792.1,-1127.2,1.31,1},{1808.8,-1100.0,1.24,1},{1829.1,-1138.1,0.96,1},{1813.8,-1121.6,1.34,3},
		{1783.4,-1118.9,0.81,4},{1805.7,-1182.9,1.22,4},{1848.1,-1110.6,0.76,4},{2035.8,-1253.3,1.16,3},{2078.1,-1284.1,1.08,3},{2074.2,-1248.6,1.02,4},{2377.5,-1374.7,1.01,1},{2375.8,-1358.0,0.85,1},
		{2387.2,-1388.6,1.27,3},{2392.3,-1368.5,1.29,3},{2403.6,-1376.6,1.0,1},{2386.3,-1393.6,1.16,4},{1792.1,-1235.2,1.17,1},{1772.9,-1213.6,0.94,3},{1785.1,-1246.9,1.01,3},{1766.0,-1236.0,0.98,1},
		{1782.6,-1265.6,0.82,3},{1809.5,-1277.2,0.85,4},{1796.9,-1264.2,0.84,4},{1670.1,-751.1,1.34,1},{1685.7,-752.0,1.17,3},{1680.0,-760.9,1.1,4},{1901.9,-1343.7,1.29,1},{1916.3,-1329.0,0.86,1},
		{1878.7,-1321.1,1.15,1},{1838.6,-1325.9,1.07,4},{1916.5,-1341.6,1.24,4},{1829.6,-734.2,0.89,1},{1807.0,-746.4,1.31,1},{1837.7,-747.1,1.25,1},{1852.9,-758.3,0.82,4},{1828.4,-726.5,0.93,4},
		{1712.3,-1316.1,1.15,1},{1709.8,-1299.7,1.26,1},{1734.7,-1292.6,1.18,3},{1680.4,-1282.4,1.1,1},{1716.9,-1318.4,1.25,4},{1645.2,-1328.0,1.34,1},{1663.7,-1395.6,0.83,3},{1642.4,-1378.9,1.34,3},
		{1626.6,-1379.4,1.09,4},{1694.5,-1386.7,1.05,4},{1616.3,-1345.3,0.74,4},{1982.7,-1113.6,1.06,1},{1965.8,-1111.5,0.93,1},{1971.1,-1142.4,1.07,1},{1957.8,-1126.2,0.75,4},{1988.6,-1135.9,1.29,4},
		{2423.4,-1582.8,1.32,3},{2432.7,-1625.9,0.93,1},{2456.1,-1602.7,1.22,3},{2435.7,-1601.8,1.23,1},{2412.9,-1589.2,1.1,3},{2417.6,-1604.0,1.04,4},{1617.8,-1328.8,1.21,3},{1627.9,-1317.7,1.12,3},
		{1596.7,-1327.7,0.97,1},{1600.0,-1376.8,1.13,4},{1642.4,-1311.6,0.89,4},{1583.9,-1060.4,1.32,1},{1607.6,-1035.8,1.14,3},{2565.1,-1473.7,1.18,1},{2517.6,-1456.2,1.3,3},{2539.1,-1501.2,1.1,1},
		{2540.3,-1473.3,1.15,1},{2559.3,-1503.6,1.15,1},{2523.4,-1537.0,0.9,1},{2518.7,-1497.1,0.8,4},{2507.8,-1480.0,0.93,4},{1711.1,-1215.7,0.88,1},{1706.1,-1241.4,0.86,1},{1744.5,-1221.0,1.12,1},
		{1735.8,-1239.7,1.02,3},{1725.2,-1224.0,0.81,4},{1694.2,-1255.2,0.75,4},{1691.2,-1213.5,1.15,4},{2053.4,-885.2,1.19,1},{2019.1,-884.4,0.96,1},{2041.9,-849.0,1.14,1},{2034.5,-876.1,0.99,3},
		{2026.0,-842.9,1.06,3},{2025.8,-864.9,1.12,3},{2052.1,-841.3,0.94,4},{2355.7,-1126.9,1.08,1},{2367.5,-1139.7,1.14,3},{2354.9,-1150.8,1.01,3},{2397.0,-1150.2,1.06,4},{2344.2,-1124.1,1.27,4},
		{2365.9,-1154.6,1.04,4},{2362.5,-1664.3,1.18,3},{2368.7,-1692.6,0.86,3},{2355.5,-1679.0,1.29,1},{2368.6,-1702.2,0.75,4},{2359.7,-1675.5,1.18,4},{2380.1,-1088.1,1.07,3},{2397.9,-1078.0,0.76,4},
		{2374.2,-1068.3,0.95,4},{1714.4,-624.3,1.22,3},{1717.5,-605.5,1.0,3},{1701.1,-610.4,0.91,1},{1700.2,-631.4,1.29,1},{1692.6,-617.3,1.01,4},{2337.3,-1513.0,0.95,3},{2348.0,-1503.9,1.29,1},
		{2358.6,-1500.0,1.2,1},{2376.9,-1508.1,0.79,4},{2372.5,-1505.0,1.21,4},{2343.2,-1500.1,1.03,4},{2365.1,-1501.4,1.0,4},{1907.7,-1276.8,0.86,1},{1924.5,-1253.5,1.32,3},{1955.8,-1287.4,0.92,1},
		{1949.7,-1273.4,0.93,1},{1918.3,-1270.1,1.11,3},{1906.1,-1285.3,0.88,4},{1940.1,-1280.4,1.27,4},{1907.4,-1294.6,1.26,4},{1869.0,-946.6,1.03,3},{1889.8,-933.9,1.26,4},{2210.9,-807.4,1.29,3},
		{2219.4,-799.8,1.17,3},{2209.0,-793.0,1.19,1},{2200.0,-792.4,1.1,4},{2207.7,-787.9,1.13,4},{2213.3,-770.0,1.28,4},{1993.6,-1277.2,0.94,3},{1997.9,-1261.2,0.86,3},{1984.6,-1256.6,0.95,3},
		{1984.1,-1278.5,1.16,4},{1917.0,-662.0,1.19,1},{1928.3,-664.4,1.32,1},{1982.4,-643.0,0.92,3},{1981.9,-648.8,1.21,4},{1970.6,-675.0,0.83,4},{2133.5,-1017.0,1.31,1},{2148.3,-1027.2,0.81,3},
		{2148.7,-1046.2,1.23,3},{2129.9,-1043.8,0.97,1},{2168.5,-1042.3,1.27,4},{2156.5,-1037.5,0.85,4},{2117.6,-1019.4,1.05,4},{2173.3,-1026.6,0.95,4},{2175.8,-1389.5,0.84,1},{2194.6,-1373.3,1.07,1},
		{2172.7,-1376.8,1.23,3},{2163.7,-1382.8,0.83,4},{2169.4,-1400.4,0.78,4},{2192.0,-1384.2,0.72,4},{2570.4,-1355.7,1.07,1},{2583.6,-1344.2,0.83,1},{2568.4,-1318.1,1.01,1},{2562.0,-1335.8,1.12,3},
		{2583.8,-1364.5,1.29,3},{2603.1,-1365.8,0.82,3},{2579.7,-1330.1,1.17,1},{2589.5,-1352.1,1.0,4},{2559.1,-1360.9,0.95,4},{2609.4,-1322.2,1.25,4},{2447.4,-1030.9,1.3,1},{2343.2,-1070.1,1.29,4},
		{2392.5,-1024.8,0.89,4},{1985.3,-898.2,0.92,3},{1961.2,-913.8,0.87,1},{1972.1,-895.5,0.92,3},{1976.9,-923.7,0.94,1},{1946.2,-903.0,0.88,1},{1994.4,-911.1,1.23,4},{1976.8,-888.7,0.81,4},
		{2002.5,-884.4,0.87,1},{1956.0,-938.2,0.95,3},{1998.8,-844.5,0.88,4},{1757.7,-721.9,1.01,1},{1773.4,-714.6,1.24,1},{1763.5,-696.8,1.31,1},{1754.1,-701.5,1.2,4},{1739.0,-705.5,1.16,4},
		{1748.6,-703.3,0.8,4},{2541.0,-1369.3,0.97,1},{2510.8,-1383.5,1.33,1},{2511.4,-1395.5,0.86,1},{2524.1,-1390.6,1.15,3},{2546.7,-1362.0,0.96,4},{2535.5,-1384.8,0.96,4},{2558.1,-1352.5,1.09,4},
		{1847.1,-809.0,1.12,3},{1858.1,-806.5,1.03,4},{1841.7,-789.4,1.09,4},{1820.7,-805.4,0.99,4},{1908.2,-982.5,1.13,1},{1909.3,-1017.9,1.1,3},{1910.7,-996.2,1.21,3},{1891.8,-998.6,1.29,3},
		{1895.7,-1047.6,1.07,4},{1906.3,-1013.7,0.71,4},{1901.8,-1019.1,0.71,4},{2021.8,-1116.2,1.26,3},{1668.4,-1426.5,1.32,1},{1750.8,-1099.5,1.18,1},{2316.3,-792.8,1.32,1},{1965.7,-774.8,1.07,3},
		{2471.8,-1190.9,1.21,1},{1853.8,-1088.3,1.18,1},{2342.3,-713.9,1.07,1},{2178.6,-678.2,1.4,3},{2041.8,-1119.1,0.94,3},{2107.8,-1449.8,1.22,1},{1741.4,-889.6,1.13,1},{2610.9,-1248.9,1.08,1},
		{1687.4,-791.4,1.09,3},{1974.3,-1456.4,1.06,3},{2163.8,-985.5,0.96,1},{2154.2,-706.8,1.33,3},{2257.6,-1616.2,1.3,3},{2430.2,-1196.9,1.17,1},{2205.6,-1619.5,0.93,3},{1581.2,-1172.6,1.0,3},
		{1823.3,-1399.6,1.32,3},{2173.9,-716.8,1.15,1},{1608.6,-958.7,1.09,3},{2265.0,-679.1,1.22,3},{1686.6,-1321.4,1.29,3},{2235.5,-1332.4,0.96,3},{2232.0,-1745.2,1.19,1},{2349.4,-948.7,0.97,3},
		{2170.8,-643.9,1.13,1},{2321.2,-1804.6,0.93,3},{2486.1,-1608.9,1.03,1},{2336.1,-1558.0,0.95,1},{2101.7,-1433.0,1.14,3},{2361.2,-1287.4,1.15,1},{2122.7,-1408.6,1.23,3},{1945.9,-1396.6,0.92,3},
		{1719.4,-1415.0,1.01,1},{2164.4,-1620.8,1.13,1},{2247.8,-1421.3,1.31,1},{2488.3,-1626.4,1.17,1},{2030.9,-1221.2,1.05,3},{2261.8,-1401.7,1.31,1},{2350.3,-905.4,1.13,3},{2544.0,-1265.1,1.09,3},
		{2458.1,-1564.6,1.3,3},{1940.1,-1032.8,1.39,1},{2163.3,-1302.2,1.16,1},{1659.0,-789.3,1.27,1},{2434.5,-1373.9,0.99,1},{2249.6,-883.3,1.05,1},{2202.0,-1051.1,1.08,1},{2349.9,-1313.8,1.08,1},
		{2423.7,-1739.0,0.97,1},{2378.6,-893.3,1.19,3},{2190.6,-736.1,1.12,3},{2256.8,-1496.8,1.24,3},{2472.6,-1297.7,0.94,3},{2245.3,-694.2,1.27,3},{2145.7,-1370.5,1.22,1},{2085.1,-1043.3,1.36,1},
		{2377.3,-1606.0,1.08,1},{2483.5,-1428.2,0.91,1},{1973.1,-1432.0,1.03,3},{2294.8,-864.1,1.23,1},{2491.3,-1007.8,1.22,3},{2460.5,-1176.4,1.02,3},{2251.0,-1192.6,1.36,1},{2027.8,-747.3,1.01,3},
		{2398.9,-1634.6,1.04,3},{1885.6,-901.9,1.39,3},{2052.7,-1058.0,1.02,3},{1950.6,-1436.0,1.21,3},{1892.2,-794.6,1.0,3},{2175.4,-1572.4,1.07,3},{2375.5,-778.4,1.21,3},{2179.9,-1054.2,1.34,1},
		{1089.6,-1704.0,0.78,1},{1304.8,-1844.8,0.7,1},{1313.4,-1646.6,0.62,1},{1172.1,-1667.6,1.11,1},{1187.2,-1656.7,1.27,3},{1149.0,-1683.8,1.08,3},{1192.8,-1679.0,1.27,3},{1160.9,-1648.5,0.95,1},
		{1158.4,-1689.1,1.0,4},{1111.5,-1691.0,1.0,1},{1096.7,-1683.9,1.17,1},{1075.3,-1682.3,1.21,1},{1129.3,-1713.7,1.17,3},{1161.7,-1674.3,1.18,1},{1148.4,-1645.1,1.07,1},{1150.7,-1689.1,0.72,4},
		{1181.6,-1660.4,0.94,4},{1133.5,-1768.7,1.24,3},{1133.1,-1749.6,1.0,1},{1139.3,-1781.6,1.03,1},{1160.8,-1798.0,1.06,4},{1141.3,-1771.9,0.87,4},{1155.3,-1769.6,1.0,4},{1165.1,-1756.0,1.32,3},
		{1170.5,-1782.4,1.1,1},{1135.0,-1774.9,0.74,4},{1171.9,-1761.6,1.27,4},{1155.5,-1754.3,1.05,4},{1208.0,-1629.9,1.25,3},{1181.5,-1628.6,1.26,1},{1190.3,-1638.3,1.15,1},{1229.0,-1610.5,0.8,3},
		{1258.6,-1634.0,0.85,4},{1229.6,-1659.2,1.22,4},{1228.6,-1673.6,0.79,4},{1259.0,-1645.4,0.94,4},{1235.0,-1712.3,0.91,3},{1186.7,-1732.6,1.16,3},{1193.2,-1690.0,1.26,1},{1182.7,-1722.1,1.33,1},
		{1185.5,-1701.0,0.95,1},{1222.0,-1702.0,1.0,3},{1224.8,-1727.9,1.08,3},{1161.0,-1712.7,1.02,1},{1174.9,-1694.6,0.78,4},{1202.1,-1741.5,1.24,4},{1217.7,-1679.4,0.84,4},{1199.2,-1755.1,1.16,4},
		{1266.3,-1614.8,1.22,3},{1288.9,-1764.7,1.22,3},{1305.2,-1755.1,1.33,1},{1272.7,-1788.6,1.15,1},{1154.7,-1579.0,1.33,3},{921.3,-1778.5,0.97,1},{917.5,-1675.2,0.89,1},{899.6,-1658.9,1.08,1},
		{854.5,-1695.0,1.09,4},{870.6,-1711.5,1.21,1},{862.7,-1711.5,1.04,4},{819.6,-1704.9,1.1,4},{901.8,-1705.8,1.09,3},{1614.1,-1792.8,0.89,1},{1633.2,-1685.5,0.92,1},{1614.3,-1650.9,0.96,1},
		{1536.3,-1839.3,0.67,1},{1546.9,-1880.9,0.78,1},{1472.7,-2110.6,0.65,1},{1442.0,-2158.0,0.62,1},{1461.3,-2162.6,1.3,1},{1515.1,-1638.2,1.08,3},{1510.5,-1656.4,0.77,4},{1570.8,-1683.1,1.27,3},
		{1560.9,-1689.8,1.2,4},{1463.9,-2035.6,0.91,3},{1476.9,-2056.6,0.96,3},{1468.8,-2056.5,1.22,4},{1549.0,-2085.5,1.25,3},{1553.7,-2068.4,1.27,1},{1541.4,-2068.5,0.87,4},{1543.7,-2064.0,0.98,4},
		{1531.9,-2111.8,1.22,3},{1460.0,-1566.3,0.89,1},{1792.8,-1789.2,0.75,1},{1779.9,-1922.3,0.65,1},{1768.6,-2061.4,0.79,1},{1753.2,-2154.1,0.79,1},{1808.7,-2130.1,0.85,1},{1999.1,-2030.6,0.87,1},
		{1835.2,-1984.8,0.97,1},{1809.4,-1986.6,1.14,3},{1823.5,-1971.4,1.16,1},{1827.1,-1998.7,1.22,1},{1809.1,-2019.7,0.8,4},{1828.1,-1960.8,1.19,1},{1849.5,-1943.2,1.07,3},{1859.6,-1955.9,0.81,1},
		{1842.5,-1932.5,1.19,1},{1861.9,-1863.5,1.14,1},{1830.6,-1862.1,0.82,1},{1849.3,-1841.7,1.2,4},{1838.0,-1865.7,1.15,4},{1836.2,-1810.8,1.29,3},{1848.4,-1806.6,1.3,3},{1842.0,-1795.1,1.18,4},
		{1948.2,-1973.4,1.0,1},{1944.4,-1987.5,1.34,3},{1968.5,-1972.9,1.25,1},{1900.7,-1977.1,1.05,1},{1811.9,-1695.0,0.89,3},{1773.3,-1680.3,1.25,3},{2050.6,-2037.7,1.23,1},{2834.6,-946.5,1.17,1},
		{2827.6,-923.2,0.96,3},{2848.2,-935.8,1.33,3},{2839.5,-957.8,0.92,3},{2831.2,-968.7,0.91,3},{2828.2,-948.9,1.13,4},{2954.0,-783.5,1.01,1},{2941.2,-803.6,1.15,1},{2929.0,-795.3,0.8,1},
		{2943.6,-776.0,0.86,4},{2942.3,-755.1,0.74,4},{2933.1,-766.2,1.12,4},{2728.4,-844.6,0.85,3},{2723.9,-812.0,0.96,3},{2711.2,-820.7,1.23,1},{2710.1,-852.4,1.21,1},{2723.0,-830.8,0.81,3},
		{2694.5,-842.6,1.22,1},{2724.5,-817.2,1.0,4},{2717.2,-881.2,1.19,4},{2748.1,-833.7,0.92,4},{2720.6,-824.7,0.79,4},{2693.8,-788.1,0.99,1},{2656.8,-759.0,0.93,1},{2714.7,-758.6,0.99,1},
		{2698.6,-775.5,0.85,3},{2683.1,-765.8,0.82,1},{2698.7,-750.6,1.18,1},{2718.3,-791.9,0.9,3},{2652.9,-762.8,0.83,4},{2674.2,-740.5,0.79,4},{2996.6,-771.6,0.98,3},{3001.3,-786.4,1.34,3},
		{2978.1,-806.8,1.13,3},{2982.8,-779.9,1.02,4},{2739.9,-937.9,1.15,3},{2754.0,-907.7,0.81,1},{2726.1,-936.0,0.93,1},{2766.4,-917.5,0.82,1},{2797.5,-922.9,1.16,4},{2704.1,-905.4,1.3,4},
		{3032.6,-923.9,1.27,1},{3015.7,-953.5,0.83,1},{3020.1,-918.7,1.1,1},{3008.3,-936.0,1.27,1},{3003.3,-905.0,1.07,3},{2958.8,-933.2,1.27,1},{3013.5,-924.8,1.06,4},{2980.1,-917.8,0.92,4},
		{3109.9,-778.6,1.09,1},{3083.6,-766.3,0.92,3},{3109.6,-748.4,1.32,1},{3147.6,-759.1,1.11,1},{3088.6,-742.9,0.79,4},{2840.1,-1215.5,0.99,1},{2864.1,-1152.1,0.8,3},{2824.8,-1164.4,1.09,1},
		{2864.3,-1205.3,0.93,3},{2864.5,-1191.9,0.77,4},{3033.8,-854.2,0.91,3},{3035.0,-813.1,1.16,1},{3046.6,-841.1,1.25,1},{3060.0,-833.3,0.95,1},{3031.7,-865.7,1.07,4},{3013.6,-856.0,1.25,4},
		{2994.8,-888.9,0.99,1},{2964.3,-903.0,0.82,1},{2981.7,-875.6,1.2,1},{2941.0,-871.2,0.95,1},{2935.8,-853.1,1.17,3},{3026.3,-893.8,1.21,4},{2870.4,-808.8,1.3,1},{2867.1,-774.6,0.95,3},
		{2847.0,-793.7,1.18,1},{2826.4,-742.7,0.97,1},{2865.7,-795.8,0.87,4},{2846.2,-764.2,1.14,4},{2994.6,-785.5,1.01,4},{3005.0,-792.1,1.13,4},{2904.5,-973.2,1.05,1},{2906.6,-948.9,1.2,3},
		{2920.3,-935.5,0.85,3},{2861.9,-966.8,1.27,4},{2907.5,-941.4,1.02,4},{2840.2,-1139.6,0.94,1},{2837.9,-1153.4,0.86,3},{2976.2,-886.7,1.07,1},{2965.9,-882.0,0.9,3},{2988.6,-898.8,1.23,4},
		{3001.9,-871.5,0.95,4},{3009.1,-882.3,0.92,4},{2976.8,-893.0,1.25,4},{2863.0,-1004.6,1.12,1},{2847.3,-1039.7,1.02,1},{2869.1,-994.5,1.26,1},{2859.6,-1020.4,1.04,4},{2789.6,-662.4,0.95,3},
		{2801.4,-674.0,0.87,3},{2783.7,-686.3,0.88,1},{2630.7,-765.4,0.86,1},{2614.7,-790.1,1.27,1},{2622.9,-777.4,0.77,4},{2656.6,-771.3,0.74,4},{2986.8,-758.3,1.01,3},{2972.3,-766.0,1.12,3},
		{2965.6,-786.4,0.99,1},{3012.4,-777.2,0.99,4},{2855.6,-682.9,0.81,3},{2836.9,-675.4,0.89,3},{2853.8,-660.3,0.84,3},{2873.3,-669.1,1.11,3},{2861.2,-687.9,0.92,4},{2865.1,-705.0,1.03,4},
		{2878.9,-770.4,1.29,1},{2881.3,-795.9,1.02,1},{2881.0,-784.3,1.12,4},{2763.8,-1035.3,0.93,3},{2777.7,-1032.9,0.91,3},{2788.8,-1061.8,0.92,3},{2793.0,-1044.2,0.93,3},{2804.2,-1054.4,1.27,1},
		{2785.8,-1010.9,0.89,3},{2777.5,-1020.0,1.05,3},{2791.4,-1031.0,0.82,4},{2773.7,-1037.1,1.07,4},{2799.5,-962.1,0.85,1},{2798.7,-977.6,1.23,1},{2815.8,-942.4,1.22,1},{2814.1,-959.7,1.09,4},
		{2754.2,-870.8,1.19,4},{2778.4,-924.5,0.75,4},{2790.3,-986.8,0.96,4},{2628.3,-707.5,0.81,3},{2626.4,-686.4,0.94,3},{2616.9,-708.2,0.91,3},{2617.3,-694.8,1.07,4},{2659.8,-723.4,1.07,4},
		{2633.2,-687.1,1.27,4},{2753.1,-1012.0,0.94,3},{2767.9,-1018.0,1.08,4},{2995.0,-861.8,1.12,3},{2987.5,-853.3,0.81,4},{2873.0,-922.0,1.18,3},{2891.1,-984.7,0.84,1},{2868.8,-965.2,0.83,4},
		{2855.2,-988.5,0.87,1},{2829.2,-1002.4,0.99,1},{2888.9,-1045.5,1.32,3},{2874.6,-1031.3,1.14,3},{2840.8,-1014.9,0.93,4},{2860.1,-1050.5,0.82,4},{2850.6,-1016.4,0.85,4},{2882.0,-1028.7,0.89,4},
		{2903.3,-1111.7,0.94,1},{2878.3,-1137.9,1.32,1},{2886.2,-1155.7,1.17,1},{2889.3,-1130.1,0.94,1},{2862.2,-1134.3,1.04,1},{2873.4,-1103.2,0.97,3},{2851.1,-1143.5,1.19,1},{2893.0,-820.7,1.08,3},
		{2910.4,-772.8,1.1,1},{2899.5,-764.0,1.11,1},{2889.6,-758.8,1.07,1},{2914.7,-760.7,1.05,1},{2914.7,-840.1,0.91,4},{2893.5,-765.6,1.24,4},{2947.6,-979.4,0.93,1},{2960.9,-956.4,0.91,1},
		{2999.0,-948.3,0.94,1},{2973.3,-937.7,1.28,1},{2977.9,-950.9,0.92,3},{2959.4,-914.9,0.87,4},{2969.8,-949.2,0.74,4},{2659.4,-656.6,1.33,1},{2653.3,-640.7,1.22,1},{2624.6,-651.2,1.0,3},
		{2671.6,-647.1,1.13,4},{3054.1,-885.4,0.87,1},{3059.1,-944.3,1.26,1},{3068.0,-901.5,0.83,1},{3043.1,-907.6,0.84,1},{3042.5,-887.2,0.86,3},{3022.3,-909.1,1.21,4},{3058.2,-921.1,1.14,4},
		{3054.9,-913.4,0.75,4},{2810.6,-687.6,1.09,1},{2786.2,-708.6,0.84,3},{2800.9,-728.5,0.99,1},{2823.3,-692.1,1.05,3},{2814.3,-709.9,1.35,3},{2780.5,-675.0,0.83,1},{2799.1,-705.6,1.0,1},
		{2844.7,-1179.5,1.33,1},{2836.2,-1187.6,0.82,1},{2881.2,-1188.3,1.16,4},{2845.6,-1198.0,0.79,4},{2992.5,-703.0,0.93,1},{2732.8,-748.7,0.91,3},{2742.9,-775.7,1.02,1},{2757.5,-796.0,1.37,3},
		{2828.3,-878.2,1.11,3},{3079.2,-783.0,1.07,1},{2747.4,-726.9,1.01,1},{2868.6,-1236.9,0.92,1},{2576.1,-621.3,1.38,1},{2997.6,-1051.9,1.4,1},{2917.5,-889.6,1.31,3},{2689.6,-736.1,1.11,3},
		{2906.8,-874.1,1.33,1},{2790.6,-742.5,1.07,1},{2952.2,-718.0,1.24,3},{2954.4,-1067.4,1.26,3},{2809.5,-841.3,1.14,1},{2852.7,-856.7,1.15,3},{2911.5,30.8,0.96,1},{2904.8,162.8,0.86,1},
		{2807.5,73.6,0.91,1},{2910.4,273.9,1.33,3},{2885.4,314.2,1.0,3},{2896.2,291.7,1.32,1},{2920.1,297.4,1.26,4},{2866.6,169.4,1.3,1},{2859.9,178.8,0.87,3},{2856.4,201.3,0.97,1},
		{2844.9,172.3,1.26,1},{2879.0,181.0,1.21,3},{2868.4,189.3,1.02,3},{2825.6,155.7,0.96,4},{2854.1,163.2,0.89,1},{2867.1,154.2,0.97,1},{2838.0,155.5,1.15,1},{2837.9,149.3,0.96,4},
		{2877.9,51.5,1.01,1},{2888.4,46.2,1.2,4},{2934.5,110.8,1.31,3},{2921.2,197.7,1.05,3},{2884.8,256.2,1.3,3},{2773.5,127.7,1.3,3},{2946.9,-51.9,1.2,1},{2766.3,-457.3,0.81,1},
		{2922.1,-335.3,0.67,1},{2803.3,-392.6,0.67,1},{2850.1,-313.8,1.07,3},{2879.5,-299.4,1.22,1},{2850.4,-322.5,0.98,4},{2845.9,-225.5,0.83,1},{2854.4,-197.3,0.94,3},{2885.5,-187.1,1.15,1},
		{2833.2,-223.0,1.12,1},{2844.1,-170.0,0.86,3},{2853.4,-187.8,1.1,4},{2888.0,-335.9,1.25,3},{2865.4,-382.6,1.15,1},{2895.3,-348.2,1.07,3},{2899.2,-361.4,0.93,3},{2855.8,-370.7,0.81,4},
		{2919.2,-311.9,0.95,4},{2897.2,-256.1,1.09,1},{2778.1,-126.6,0.93,3},{2786.3,-116.6,1.21,4},{3061.3,-498.3,0.93,1},{3278.8,-258.4,0.6,1},{3187.8,-222.1,0.64,1},{3044.5,-485.0,0.8,1},
		{3130.4,-344.6,1.22,1},{3147.6,-336.7,1.06,1},{3186.8,-380.0,1.34,3},{3159.4,-341.8,1.33,1},{3175.1,-339.6,1.15,3},{3132.6,-364.5,0.93,4},{3122.4,-366.2,0.77,4},{3048.7,-167.9,1.07,4},
		{3082.5,-184.0,0.79,4},{3131.0,-408.3,1.21,3},{3106.7,-392.7,1.04,1},{3156.9,-421.4,1.31,1},{3125.1,-376.9,0.93,1},{3141.1,-403.4,0.73,4},{3114.7,-416.3,1.22,4},{3140.5,-398.4,0.96,4},
		{3242.6,-248.3,1.11,1},{3234.8,-263.3,1.11,3},{3243.1,-274.7,0.94,3},{3222.2,-291.4,0.98,4},{3198.3,-245.2,0.95,4},{3076.4,-326.4,1.11,3},{3083.8,-306.6,1.24,3},{3097.1,-298.0,0.92,4},
		{3147.3,-297.4,0.88,3},{3135.8,-263.7,1.02,3},{3146.9,-276.0,1.0,1},{3165.3,-259.4,1.08,1},{3113.9,-304.5,0.98,3},{3165.6,-278.9,0.75,4},{3098.8,-250.3,0.9,4},{3175.5,-247.6,0.83,4},
		{3174.4,-397.3,1.19,1},{3172.1,-440.0,1.15,3},{3332.5,-216.6,1.17,1},{3306.8,-205.4,1.03,4},{3209.1,192.6,0.64,1},{3110.2,193.0,0.84,1},{3081.8,-12.1,0.89,1},{3141.3,13.6,1.12,1},
		{3106.0,-3.2,1.08,1},{3153.6,41.0,1.1,4},{3118.4,-25.0,1.27,4},{3239.3,78.2,0.92,1},{3253.1,83.8,1.32,3},{3204.7,103.3,1.07,1},{3243.2,92.1,1.12,3},{3246.8,65.2,1.03,1},
		{3238.4,104.1,0.94,4},{3194.4,11.5,1.15,1},{3206.6,-2.3,0.96,1},{3191.8,-11.1,1.22,1},{3170.2,1.0,1.12,4},{3338.7,88.6,1.35,3},{3258.6,33.8,1.04,1},{3256.9,19.0,0.97,3},
		{3249.6,42.2,0.77,4},{3047.5,94.2,0.89,1},{3072.6,89.8,0.73,4},{3063.9,90.3,1.26,4},{3061.3,94.9,0.8,4},{3067.8,132.7,0.87,4},{3219.6,135.0,0.98,1},
	},
}
]])
put(folder4, "ModuleScript", "LondonLayout", [[
--!nocheck
-- The London map's road network, as data. MADE BY tools/london_layout.py: change that and run it again,
-- don't edit this file by hand. LondonMap and RoadNetwork turn it into roads in the game.

return {
	bounds = { -3200, -2600, 3850, 2750 },
	outline = {
		{ -2596.7, -1793.4 },
		{ -2638.7, -1750.9 },
		{ -2673.9, -1691.4 },
		{ -3015, -856.5 },
		{ -3023.8, -808.2 },
		{ -3117.4, 256.6 },
		{ -2988.6, 1094.8 },
		{ -2972.8, 1153.2 },
		{ -2950.4, 1197.4 },
		{ -2491.8, 1933 },
		{ -2456.6, 1978.2 },
		{ -2419.1, 2010.3 },
		{ -1493.1, 2450 },
		{ -304.8, 2695.4 },
		{ -251.1, 2692.5 },
		{ 1000.1, 2501.5 },
		{ 2199.3, 2595.9 },
		{ 2254.5, 2594.8 },
		{ 3211.6, 2314.9 },
		{ 3284.1, 2279.4 },
		{ 3315.8, 2253.2 },
		{ 3349.4, 2213.4 },
		{ 3377.7, 2160.1 },
		{ 3702.5, 1343.9 },
		{ 3717.7, 1290.9 },
		{ 3758.4, 387.9 },
		{ 3751.4, 313.1 },
		{ 3520.2, -673.5 },
		{ 3099.1, -1540.6 },
		{ 3044.9, -1613.6 },
		{ 2403.3, -2228.9 },
		{ 2362.3, -2261.4 },
		{ 2278.2, -2297 },
		{ 1254.9, -2535 },
		{ 1199.1, -2532.9 },
		{ 250, -2401.4 },
		{ -864.3, -2496.9 },
		{ -915.7, -2496.6 },
		{ -1879.9, -2332 },
		{ -1939.2, -2314.8 },
		{ -2005.1, -2275.1 },
	},
	profiles = {
		back = { lanes = 1, lane = 14, parking = 9, res = 0, shoulder = 0, edge = 0, side = "pavement", sideWidth = 12, limit = 20, rank = 0 },
		street = { lanes = 1, lane = 15, parking = 9, res = 0, shoulder = 0, edge = 0, side = "pavement", sideWidth = 13, limit = 30, rank = 1 },
		main = { lanes = 1, lane = 16, parking = 9, res = 0, shoulder = 0, edge = 0, side = "pavement", sideWidth = 15, limit = 30, rank = 2 },
		high = { lanes = 1, lane = 16, parking = 9, res = 0, shoulder = 0, edge = 0, side = "pavement", sideWidth = 20, limit = 20, rank = 2 },
		dual = { lanes = 2, lane = 14, parking = 0, res = 16, shoulder = 0, edge = 0, side = "pavement", sideWidth = 15, limit = 40, rank = 3 },
		arterial = { lanes = 2, lane = 15, parking = 0, res = 28, shoulder = 0, edge = 1, side = "pavement", sideWidth = 20, limit = 50, rank = 4 },
	},
	nodes = {
		{ id = "MB", x = -1850, z = -1500, kind = "roundabout", radius = 82, island = 50, name = "Marylebone" },
		{ id = "GP", x = -1100, z = -1520, kind = "lights", name = "Great Portland Street" },
		{ id = "EU", x = -600, z = -1540, kind = "lights", name = "Euston" },
		{ id = "KX", x = 350, z = -1530, kind = "roundabout", radius = 82, island = 50, name = "King's Cross" },
		{ id = "OS", x = 1350, z = -1450, kind = "roundabout", radius = 82, island = 50, name = "Old Street" },
		{ id = "AG", x = 1500, z = -420, kind = "roundabout", radius = 82, island = 50, name = "Aldgate" },
		{ id = "MA", x = -1850, z = -950, kind = "roundabout", radius = 72, island = 44, name = "Marble Arch" },
		{ id = "HPC", x = -1850, z = -160, kind = "roundabout", radius = 76, island = 46, name = "Hyde Park Corner" },
		{ id = "CH", x = -1850, z = 545, kind = "lights", name = "Chelsea" },
		{ id = "WM", x = -800, z = 330, kind = "lights", name = "Westminster" },
		{ id = "BF", x = 450, z = 250, kind = "lights", name = "Blackfriars" },
		{ id = "MN", x = 1150, z = 350, kind = "junction", name = "Monument" },
		{ id = "TH", x = 1700, z = 515, kind = "lights", name = "Tower Hill" },
		{ id = "LE", x = 2550, z = 450, kind = "lights", name = "Limehouse" },
		{ id = "CS", x = -1850, z = 935, kind = "lights", name = "Battersea" },
		{ id = "WS", x = -800, z = 720, kind = "lights", name = "Lambeth" },
		{ id = "BS", x = 450, z = 645, kind = "lights", name = "Southwark" },
		{ id = "TS", x = 1700, z = 905, kind = "lights", name = "Tower Bridge Road" },
		{ id = "TR", x = -800, z = -110, kind = "roundabout", radius = 64, island = 40, name = "Trafalgar Square" },
		{ id = "PC", x = -950, z = -560, kind = "lights", name = "Piccadilly Circus" },
		{ id = "OC", x = -1150, z = -950, kind = "lights", name = "Oxford Circus" },
		{ id = "TC", x = -560, z = -950, kind = "lights", name = "Tottenham Court Road" },
		{ id = "HB", x = 250, z = -900, kind = "lights", name = "Holborn" },
		{ id = "AW", x = 200, z = -170, kind = "lights", name = "Aldwych" },
		{ id = "SP", x = 700, z = -230, kind = "lights", name = "St Paul's" },
		{ id = "BK", x = 1000, z = -520, kind = "lights", name = "Bank" },
		{ id = "P1", x = -2380, z = -1600, kind = "roundabout", radius = 96, island = 60, name = "Westbourne Park" },
		{ id = "P2", x = -1850, z = -2080, kind = "roundabout", radius = 96, island = 60, name = "Maida Vale" },
		{ id = "CT", x = -700, z = -1960, kind = "mini", name = "Camden Town" },
		{ id = "P3", x = -900, z = -2260, kind = "roundabout", radius = 96, island = 60, name = "Chalk Farm" },
		{ id = "AN", x = 330, z = -1920, kind = "lights", name = "Angel" },
		{ id = "P4", x = 260, z = -2180, kind = "roundabout", radius = 96, island = 60, name = "Highbury" },
		{ id = "HK", x = 1430, z = -1960, kind = "mini", name = "Dalston" },
		{ id = "P5", x = 1250, z = -2310, kind = "roundabout", radius = 96, island = 60, name = "Stoke Newington" },
		{ id = "P6", x = 2200, z = -2040, kind = "roundabout", radius = 96, island = 60, name = "Clapton" },
		{ id = "NH", x = -2760, z = -950, kind = "roundabout", radius = 96, island = 60, name = "Notting Hill Gate" },
		{ id = "KN", x = -2880, z = -160, kind = "roundabout", radius = 96, island = 60, name = "Kensington" },
		{ id = "WH", x = 2400, z = -520, kind = "lights", name = "Whitechapel" },
		{ id = "P7", x = 2850, z = -1400, kind = "roundabout", radius = 96, island = 60, name = "Hackney Wick" },
		{ id = "P8", x = 3260, z = -650, kind = "roundabout", radius = 96, island = 60, name = "Bow" },
		{ id = "P9", x = 3420, z = 230, kind = "roundabout", radius = 96, island = 60, name = "Poplar" },
		{ id = "CM", x = 2150, z = 50, kind = "junction", name = "Stepney" },
		{ id = "IN", x = 2980, z = 830, kind = "junction", name = "Isle of Dogs" },
		{ id = "IW", x = 2800, z = 1250, kind = "junction", name = "Millwall" },
		{ id = "IS", x = 2960, z = 1670, kind = "junction", name = "Island Gardens" },
		{ id = "IE", x = 3200, z = 1250, kind = "junction", name = "Cubitt Town" },
		{ id = "EL", x = -150, z = 1400, kind = "roundabout", radius = 72, island = 46, name = "Elephant and Castle" },
		{ id = "SW", x = -2650, z = 920, kind = "roundabout", radius = 96, island = 60, name = "Battersea Park" },
		{ id = "RH", x = 2150, z = 1250, kind = "lights", name = "Rotherhithe" },
		{ id = "P16", x = -2300, z = 1780, kind = "roundabout", radius = 96, island = 60, name = "Wandsworth" },
		{ id = "VX", x = -1300, z = 1500, kind = "lights", name = "Vauxhall" },
		{ id = "P15", x = -1450, z = 2200, kind = "roundabout", radius = 96, island = 60, name = "Clapham" },
		{ id = "KE", x = -300, z = 2420, kind = "roundabout", radius = 96, island = 60, name = "Kennington" },
		{ id = "P13", x = 1000, z = 2260, kind = "roundabout", radius = 96, island = 60, name = "Camberwell" },
		{ id = "OK", x = 1500, z = 1620, kind = "lights", name = "Old Kent Road" },
		{ id = "P12", x = 2150, z = 2350, kind = "roundabout", radius = 96, island = 60, name = "Peckham" },
		{ id = "P11", x = 3050, z = 2090, kind = "roundabout", radius = 96, island = 60, name = "Deptford" },
		{ id = "minories_mid", x = 1578, z = -114.4, kind = "junction" },
		{ id = "J0x3_0", x = 250.4, z = 1037.4, kind = "junction" },
		{ id = "J0x3_1", x = 1997.4, z = 1315.4, kind = "junction" },
		{ id = "J0x4_0", x = 3416.5, z = -169.5, kind = "junction" },
		{ id = "J0b6_5_0", x = 617.2, z = 1508.3, kind = "junction" },
		{ id = "J0b6_5_1", x = 557.6, z = 1957.7, kind = "junction" },
		{ id = "J0b6_6_0", x = 349.8, z = 1470.6, kind = "junction" },
		{ id = "J0b6_6_1", x = 309.4, z = 1775.8, kind = "junction" },
		{ id = "J0x7_0", x = -1510.5, z = 1324.5, kind = "junction" },
		{ id = "J0x7_1", x = -2663.1, z = 1335.3, kind = "junction" },
		{ id = "J0b8_0_1", x = -1546.9, z = 877.1, kind = "junction" },
		{ id = "J0b8_2_0", x = -950.7, z = 1470.9, kind = "junction" },
		{ id = "J0b8_2_1", x = -1073.3, z = 780.1, kind = "junction" },
		{ id = "J0b8_4_0", x = -412.8, z = 1423.9, kind = "junction" },
		{ id = "J0b8_4_1", x = -441.4, z = 1108.6, kind = "junction" },
		{ id = "J0x9_1", x = 362.9, z = -1759.7, kind = "junction" },
		{ id = "J0x10_0", x = 221.2, z = -479.7, kind = "junction" },
		{ id = "J0x10_1", x = -637, z = -538.5, kind = "junction" },
		{ id = "J0b11_1_0", x = -260.1, z = -1561.2, kind = "junction" },
		{ id = "J0b11_1_1", x = -255.5, z = -2281.4, kind = "junction" },
		{ id = "J0b13_0_0", x = 2398.7, z = 1772.5, kind = "junction" },
		{ id = "J0b13_0_1", x = 2007.2, z = 2121.5, kind = "junction" },
		{ id = "J0b13_1_0", x = 2217, z = 1390.8, kind = "junction" },
		{ id = "J0b13_1_1", x = 1742.7, z = 1820.3, kind = "junction" },
		{ id = "J0b15_0_0", x = 517.4, z = -208.1, kind = "junction" },
		{ id = "J0b15_0_1", x = 561.5, z = 129.6, kind = "junction" },
		{ id = "J0b15_2_0", x = -21.1, z = -161.2, kind = "junction" },
		{ id = "J0b15_2_1", x = 33.1, z = 253.5, kind = "junction" },
		{ id = "J0b15_3_0", x = -291.9, z = -150.3, kind = "junction" },
		{ id = "J0b15_3_1", x = -237.7, z = 265.1, kind = "junction" },
		{ id = "J0b15_4_0", x = -561.5, z = -129.1, kind = "junction" },
		{ id = "J0b15_4_1", x = -505.9, z = 296.1, kind = "junction" },
		{ id = "J0b16_2_0", x = 56.5, z = -914.5, kind = "junction" },
		{ id = "J0b16_2_1", x = 75.9, z = -1553.3, kind = "junction" },
		{ id = "J0b17_0_0", x = -2159.9, z = 486.5, kind = "junction" },
		{ id = "J0b17_0_1", x = -2160, z = -153.8, kind = "junction" },
		{ id = "J0b17_1_0", x = -2429.9, z = 399.4, kind = "junction" },
		{ id = "J0b17_1_1", x = -2430, z = -151.5, kind = "junction" },
		{ id = "J0b19_1_0", x = -1433.2, z = -400.5, kind = "junction" },
		{ id = "J0b19_1_1", x = -1680.7, z = -962.1, kind = "junction" },
		{ id = "J0b19_2_0", x = -1215.7, z = -477.3, kind = "junction" },
		{ id = "J0b19_2_1", x = -1432.9, z = -970.2, kind = "junction" },
		{ id = "J0b20_1_0", x = -2140, z = -943.6, kind = "junction" },
		{ id = "J0b20_1_1", x = -2106.9, z = -1557.1, kind = "junction" },
		{ id = "J0b21_0_0", x = 1639.7, z = 164.4, kind = "junction" },
		{ id = "J0b21_0_1", x = 1125.4, z = 192, kind = "junction" },
		{ id = "J0b21_1_1", x = 1100.8, z = 33.8, kind = "junction" },
		{ id = "J0b22_0_0", x = 42.4, z = 696, kind = "junction" },
		{ id = "J0b22_0_1", x = 58.3, z = 1217.7, kind = "junction" },
		{ id = "J0b22_2_0", x = -477.1, z = 720, kind = "junction" },
		{ id = "J0b24_1_1", x = -1372.9, z = -1527.2, kind = "junction" },
		{ id = "J0b28_0_0", x = 498.4, z = -837.9, kind = "junction" },
		{ id = "J0b29_0_0", x = 2202.8, z = 476, kind = "junction" },
		{ id = "J0b31_1_0", x = 1779, z = -464.6, kind = "junction" },
		{ id = "J0b31_1_1", x = 1838.2, z = -39.6, kind = "junction" },
		{ id = "J0b32_0_0", x = -1560.5, z = 1593.8, kind = "junction" },
		{ id = "J0b32_0_1", x = -1407.9, z = 2052.7, kind = "junction" },
		{ id = "J0b32_1_0", x = -1845.3, z = 1689.1, kind = "junction" },
		{ id = "J0b32_1_1", x = -1724.9, z = 2108.4, kind = "junction" },
		{ id = "J0b33_1_0", x = 1098.3, z = -913.4, kind = "junction" },
		{ id = "J0b33_1_1", x = 1484.1, z = -841.1, kind = "junction" },
		{ id = "J0b33_2_0", x = 1182.1, z = -1121.5, kind = "junction" },
		{ id = "J0b33_2_1", x = 1438.3, z = -1110.4, kind = "junction" },
		{ id = "J0b34_0_0", x = 853.4, z = -275.7, kind = "junction" },
		{ id = "J0b35_0_1", x = -1127.1, z = -121.9, kind = "junction" },
		{ id = "J0b35_1_1", x = -1402.9, z = -133.2, kind = "junction" },
		{ id = "J0b36_0_0", x = -608.8, z = -689.4, kind = "junction" },
		{ id = "J0b36_0_1", x = -1033.8, z = -689, kind = "junction" },
		{ id = "J0b41_0_0", x = -2214.8, z = -1815.5, kind = "junction" },
		{ id = "J0b41_0_1", x = -1906.2, z = -1757.8, kind = "junction" },
		{ id = "J1b6_0_0", x = 574, z = 1102.4, kind = "junction" },
		{ id = "J1b6_0_1", x = 717.6, z = 692.3, kind = "junction" },
		{ id = "J1b6_1_0", x = 828.8, z = 1153.7, kind = "junction" },
		{ id = "J1b6_1_1", x = 973.7, z = 737.7, kind = "junction" },
		{ id = "J1b6_3_0", x = 1342.3, z = 1238.2, kind = "junction" },
		{ id = "J1b6_3_1", x = 1422.7, z = 838, kind = "junction" },
		{ id = "J1b6_5_0", x = 1840.5, z = 1296.9, kind = "junction" },
		{ id = "J1b6_5_1", x = 1924.2, z = 982, kind = "junction" },
		{ id = "J1b9_1_0", x = 2729.7, z = -61, kind = "junction" },
		{ id = "J1b9_1_1", x = 2666.3, z = -543.7, kind = "junction" },
		{ id = "J1b9_2_0", x = 2996.2, z = -104.2, kind = "junction" },
		{ id = "J1b9_2_1", x = 2934.3, z = -578.5, kind = "junction" },
		{ id = "J1b11_1_0", x = 2816.3, z = 408.6, kind = "junction" },
		{ id = "J1b11_2_0", x = 3080.3, z = 351.3, kind = "junction" },
		{ id = "J1b16_0_0", x = 32.9, z = -481, kind = "junction" },
		{ id = "J1b16_1_0", x = -207.5, z = -482.8, kind = "junction" },
		{ id = "J1b16_1_1", x = -176.8, z = -931.3, kind = "junction" },
		{ id = "J1b16_2_0", x = -445.9, z = -513.7, kind = "junction" },
		{ id = "J1b16_2_1", x = -396.6, z = -942, kind = "junction" },
		{ id = "J1b22_1_0", x = -989.1, z = 1231.7, kind = "junction" },
		{ id = "J1b23_0_0", x = -1016, z = 1074.3, kind = "junction" },
		{ id = "J1b23_0_1", x = -1522, z = 1155.6, kind = "junction" },
		{ id = "J1b24_0_0", x = 1020, z = -1883, kind = "junction" },
		{ id = "J1b24_0_1", x = 1089.4, z = -1513.7, kind = "junction" },
		{ id = "J1b24_1_0", x = 754.7, z = -1833.2, kind = "junction" },
		{ id = "J1b24_1_1", x = 806.9, z = -1554.9, kind = "junction" },
		{ id = "J1b27_0_0", x = -656.1, z = -1813.7, kind = "junction" },
		{ id = "J1b27_0_1", x = -261, z = -1877.4, kind = "junction" },
		{ id = "J1b28_0_0", x = -2130.1, z = -1195.8, kind = "junction" },
		{ id = "J1b28_0_1", x = -2672.2, z = -1224.9, kind = "junction" },
		{ id = "J1b29_0_0", x = 80.3, z = 1037.4, kind = "junction" },
		{ id = "J1b30_0_0", x = 2175.1, z = 207.8, kind = "junction" },
		{ id = "J1b32_0_0", x = -1831.2, z = -1227, kind = "junction" },
		{ id = "J1b32_0_1", x = -1352.7, z = -1311.8, kind = "junction" },
		{ id = "J1b36_0_0", x = 698.1, z = -20.2, kind = "junction" },
		{ id = "J1b40_0_0", x = -1551.9, z = -574.3, kind = "junction" },
		{ id = "J1b40_0_1", x = -1870.6, z = -434.3, kind = "junction" },
		{ id = "J1b42_0_0", x = 1213.2, z = -502.1, kind = "junction" },
		{ id = "J1b42_0_1", x = 1284.6, z = -883.4, kind = "junction" },
		{ id = "J2b3_2_0", x = -1046.2, z = 2321.2, kind = "junction" },
		{ id = "J2b5_0_0", x = 1059.5, z = -758, kind = "junction" },
		{ id = "J2b5_0_1", x = 278.4, z = -1070.1, kind = "junction" },
		{ id = "J2b6_0_1", x = 233.8, z = 2387.2, kind = "junction" },
		{ id = "J2b9_0_0", x = 1657.6, z = -2283.9, kind = "junction" },
		{ id = "J2b9_0_1", x = 1740.5, z = -1599.1, kind = "junction" },
		{ id = "J3b6_2_0", x = -996.8, z = 2062.8, kind = "junction" },
		{ id = "J3b6_2_1", x = -247.3, z = 2145.8, kind = "junction" },
		{ id = "J3b8_0_0", x = -198.3, z = 1881.1, kind = "junction" },
		{ id = "J3b8_1_1", x = 388.5, z = 2239.6, kind = "junction" },
	},
	roads = {
		{
			id = "marylebone",
			profile = "dual",
			a = "MB",
			b = "J0b24_1_1",
			radius = 600,
			name = "Marylebone Road",
			via = {
				{ -1480, -1530 },
			},
		},
		{ id = "marylebone_2", profile = "dual", a = "J0b24_1_1", b = "GP", radius = 600, name = "Marylebone Road" },
		{ id = "euston1", profile = "dual", a = "GP", b = "EU", radius = 120, name = "Euston Road" },
		{ id = "euston2", profile = "dual", a = "EU", b = "J0b11_1_0", radius = 700, name = "Euston Road" },
		{
			id = "euston2_2",
			profile = "dual",
			a = "J0b11_1_0",
			b = "J0b16_2_1",
			radius = 700,
			name = "Euston Road",
			via = {
				{ -120, -1570 },
			},
		},
		{ id = "euston2_2_2", profile = "dual", a = "J0b16_2_1", b = "KX", radius = 700, name = "Euston Road" },
		{ id = "pentonville", profile = "dual", a = "KX", b = "J1b24_1_1", radius = 500, name = "Pentonville Road" },
		{
			id = "pentonville_3",
			profile = "dual",
			a = "J1b24_1_1",
			b = "J1b24_0_1",
			radius = 500,
			name = "Pentonville Road",
			via = {
				{ 900, -1560 },
			},
		},
		{ id = "pentonville_2", profile = "dual", a = "J1b24_0_1", b = "OS", radius = 500, name = "Pentonville Road" },
		{ id = "cityroad", profile = "dual", a = "OS", b = "J0b33_2_1", radius = 500, name = "Bishopsgate" },
		{
			id = "cityroad_3",
			profile = "dual",
			a = "J0b33_2_1",
			b = "J0b33_1_1",
			radius = 500,
			name = "Bishopsgate",
			via = {
				{ 1480, -950 },
			},
		},
		{ id = "cityroad_2", profile = "dual", a = "J0b33_1_1", b = "AG", radius = 500, name = "Bishopsgate" },
		{ id = "parklane", profile = "dual", a = "MA", b = "J1b40_0_1", radius = 600, name = "Park Lane", via = {
				{ -1880, -560 },
			} },
		{ id = "parklane_2", profile = "dual", a = "J1b40_0_1", b = "HPC", radius = 600, name = "Park Lane" },
		{ id = "edgware", profile = "dual", a = "MB", b = "J1b32_0_0", radius = 400, name = "Edgware Road" },
		{ id = "edgware_2", profile = "dual", a = "J1b32_0_0", b = "MA", radius = 400, name = "Edgware Road" },
		{ id = "millbank", profile = "dual", a = "CH", b = "WM", radius = 450, name = "Millbank", via = {
				{ -1500, 290 },
			} },
		{ id = "embankment", profile = "dual", a = "WM", b = "J0b15_4_1", radius = 500, name = "Victoria Embankment" },
		{ id = "embankment_4", profile = "dual", a = "J0b15_4_1", b = "J0b15_3_1", radius = 500, name = "Victoria Embankment" },
		{
			id = "embankment_3",
			profile = "dual",
			a = "J0b15_3_1",
			b = "J0b15_2_1",
			radius = 500,
			name = "Victoria Embankment",
			via = {
				{ -150, 255 },
			},
		},
		{ id = "embankment_2", profile = "dual", a = "J0b15_2_1", b = "BF", radius = 500, name = "Victoria Embankment" },
		{ id = "thames", profile = "main", a = "BF", b = "MN", radius = 400, name = "Upper Thames Street", via = {
				{ 800, 310 },
			} },
		{ id = "thames2", profile = "main", a = "MN", b = "TH", radius = 400, name = "Lower Thames Street", via = {
				{ 1450, 420 },
			} },
		{ id = "highway", profile = "dual", a = "TH", b = "J0b29_0_0", radius = 400, name = "The Highway", via = {
				{ 2150, 480 },
			} },
		{ id = "highway_2", profile = "dual", a = "J0b29_0_0", b = "LE", radius = 400, name = "The Highway" },
		{ id = "minories", profile = "dual", a = "AG", b = "minories_mid", radius = 400, name = "Minories" },
		{
			id = "minories_2",
			profile = "dual",
			a = "minories_mid",
			b = "J0b21_0_0",
			radius = 400,
			name = "Minories",
			via = {
				{ 1620, 50 },
			},
		},
		{ id = "minories_2_2", profile = "dual", a = "J0b21_0_0", b = "TH", radius = 400, name = "Minories" },
		{ id = "chelseabr", profile = "main", a = "CH", b = "CS", radius = 120, name = "Chelsea Bridge" },
		{ id = "westminsterbr", profile = "main", a = "WM", b = "WS", radius = 120, name = "Westminster Bridge" },
		{ id = "blackfriarsbr", profile = "main", a = "BF", b = "BS", radius = 120, name = "Blackfriars Bridge" },
		{ id = "towerbr", profile = "main", a = "TH", b = "TS", radius = 120, name = "Tower Bridge" },
		{ id = "whitehall", profile = "main", a = "TR", b = "WM", radius = 120, name = "Whitehall" },
		{ id = "mall", profile = "main", a = "TR", b = "J0b35_0_1", radius = 400, name = "The Mall" },
		{ id = "mall_2", profile = "main", a = "J0b35_0_1", b = "J0b35_1_1", radius = 400, name = "The Mall", via = {
				{ -1350, -130 },
			} },
		{ id = "mall_2_2", profile = "main", a = "J0b35_1_1", b = "HPC", radius = 400, name = "The Mall" },
		{ id = "piccadilly", profile = "main", a = "HPC", b = "J0b19_1_0", radius = 400, name = "Piccadilly" },
		{
			id = "piccadilly_2",
			profile = "main",
			a = "J0b19_1_0",
			b = "J0b19_2_0",
			radius = 400,
			name = "Piccadilly",
			via = {
				{ -1400, -420 },
			},
		},
		{ id = "piccadilly_2_2", profile = "main", a = "J0b19_2_0", b = "PC", radius = 400, name = "Piccadilly" },
		{ id = "haymarket", profile = "main", a = "PC", b = "TR", radius = 250, name = "Haymarket", via = {
				{ -880, -330 },
			} },
		{ id = "regent", profile = "main", a = "OC", b = "J0b36_0_1", radius = 260, name = "Regent Street", via = {
				{ -1080, -760 },
			} },
		{ id = "regent_2", profile = "main", a = "J0b36_0_1", b = "PC", radius = 260, name = "Regent Street" },
		{ id = "oxford1", profile = "high", a = "MA", b = "J0b19_1_1", radius = 600, name = "Oxford Street" },
		{
			id = "oxford1_2",
			profile = "high",
			a = "J0b19_1_1",
			b = "J0b19_2_1",
			radius = 600,
			name = "Oxford Street",
			via = {
				{ -1500, -975 },
			},
		},
		{ id = "oxford1_2_2", profile = "high", a = "J0b19_2_1", b = "OC", radius = 600, name = "Oxford Street" },
		{ id = "oxford2", profile = "high", a = "OC", b = "TC", radius = 600, name = "Oxford Street", via = {
				{ -850, -935 },
			} },
		{ id = "portland", profile = "main", a = "OC", b = "GP", radius = 400, name = "Portland Place", via = {
				{ -1120, -1250 },
			} },
		{ id = "tcr", profile = "main", a = "TC", b = "EU", radius = 400, name = "Tottenham Court Road", via = {
				{ -590, -1250 },
			} },
		{ id = "charing", profile = "main", a = "TR", b = "J0x10_1", radius = 300, name = "Charing Cross Road", via = {
				{ -640, -520 },
			} },
		{ id = "charing_2", profile = "main", a = "J0x10_1", b = "J0b36_0_0", radius = 300, name = "Charing Cross Road" },
		{ id = "charing_2_2", profile = "main", a = "J0b36_0_0", b = "TC", radius = 300, name = "Charing Cross Road" },
		{ id = "sloane", profile = "main", a = "HPC", b = "CH", radius = 500, name = "Sloane Street", via = {
				{ -1880, 200 },
			} },
		{ id = "holborn", profile = "main", a = "TC", b = "J1b16_2_1", radius = 500, name = "High Holborn" },
		{ id = "holborn_4", profile = "main", a = "J1b16_2_1", b = "J1b16_1_1", radius = 500, name = "High Holborn" },
		{
			id = "holborn_3",
			profile = "main",
			a = "J1b16_1_1",
			b = "J0b16_2_0",
			radius = 500,
			name = "High Holborn",
			via = {
				{ -150, -930 },
			},
		},
		{ id = "holborn_2", profile = "main", a = "J0b16_2_0", b = "HB", radius = 500, name = "High Holborn" },
		{ id = "kingsway", profile = "main", a = "HB", b = "J0x10_0", radius = 120, name = "Kingsway" },
		{ id = "kingsway_2", profile = "main", a = "J0x10_0", b = "AW", radius = 120, name = "Kingsway" },
		{ id = "strand", profile = "high", a = "TR", b = "J0b15_4_0", radius = 400, name = "The Strand" },
		{
			id = "strand_4",
			profile = "high",
			a = "J0b15_4_0",
			b = "J0b15_3_0",
			radius = 400,
			name = "The Strand",
			via = {
				{ -300, -150 },
			},
		},
		{ id = "strand_3", profile = "high", a = "J0b15_3_0", b = "J0b15_2_0", radius = 400, name = "The Strand" },
		{ id = "strand_2", profile = "high", a = "J0b15_2_0", b = "AW", radius = 400, name = "The Strand" },
		{ id = "fleet", profile = "main", a = "AW", b = "J0b15_0_0", radius = 120, name = "Fleet Street" },
		{ id = "fleet_2", profile = "main", a = "J0b15_0_0", b = "SP", radius = 120, name = "Fleet Street" },
		{ id = "cheapside", profile = "main", a = "SP", b = "BK", radius = 120, name = "Cheapside" },
		{ id = "newgate", profile = "main", a = "HB", b = "J0b28_0_0", radius = 300, name = "Holborn Viaduct" },
		{ id = "newgate_2", profile = "main", a = "J0b28_0_0", b = "BK", radius = 300, name = "Holborn Viaduct", via = {
				{ 650, -800 },
			} },
		{ id = "queenvic", profile = "main", a = "BK", b = "J0b34_0_0", radius = 300, name = "Queen Victoria Street" },
		{ id = "queenvic_3", profile = "main", a = "J0b34_0_0", b = "J1b36_0_0", radius = 300, name = "Queen Victoria Street" },
		{ id = "queenvic_3_2", profile = "main", a = "J1b36_0_0", b = "J0b15_0_1", radius = 300, name = "Queen Victoria Street" },
		{ id = "queenvic_2", profile = "main", a = "J0b15_0_1", b = "BF", radius = 300, name = "Queen Victoria Street" },
		{
			id = "kingwilliam",
			profile = "main",
			a = "BK",
			b = "J0b21_1_1",
			radius = 300,
			name = "King William Street",
			via = {
				{ 1080, -100 },
			},
		},
		{ id = "kingwilliam_3", profile = "main", a = "J0b21_1_1", b = "J0b21_0_1", radius = 300, name = "King William Street" },
		{ id = "kingwilliam_2", profile = "main", a = "J0b21_0_1", b = "MN", radius = 300, name = "King William Street" },
		{ id = "leadenhall", profile = "main", a = "BK", b = "J1b42_0_0", radius = 500, name = "Leadenhall Street" },
		{
			id = "leadenhall_2",
			profile = "main",
			a = "J1b42_0_0",
			b = "AG",
			radius = 500,
			name = "Leadenhall Street",
			via = {
				{ 1250, -500 },
			},
		},
		{ id = "moorgate", profile = "main", a = "BK", b = "J2b5_0_0", radius = 300, name = "Moorgate" },
		{ id = "moorgate_3", profile = "main", a = "J2b5_0_0", b = "J0b33_1_0", radius = 300, name = "Moorgate" },
		{
			id = "moorgate_2",
			profile = "main",
			a = "J0b33_1_0",
			b = "J0b33_2_0",
			radius = 300,
			name = "Moorgate",
			via = {
				{ 1120, -1000 },
			},
		},
		{ id = "moorgate_2_2", profile = "main", a = "J0b33_2_0", b = "OS", radius = 300, name = "Moorgate" },
		{ id = "grays", profile = "street", a = "HB", b = "J2b5_0_1", radius = 200, name = "Gray's Inn Road" },
		{ id = "grays_2", profile = "street", a = "J2b5_0_1", b = "KX", radius = 200, name = "Gray's Inn Road", via = {
				{ 300, -1200 },
			} },
		{ id = "harrow", profile = "dual", a = "MB", b = "J0b20_1_1", radius = 400, name = "Harrow Road" },
		{ id = "harrow_2", profile = "dual", a = "J0b20_1_1", b = "P1", radius = 400, name = "Harrow Road", via = {
				{ -2120, -1560 },
			} },
		{ id = "maida", profile = "dual", a = "MB", b = "J0b41_0_1", radius = 400, name = "Maida Vale" },
		{ id = "maida_2", profile = "dual", a = "J0b41_0_1", b = "P2", radius = 400, name = "Maida Vale", via = {
				{ -1920, -1800 },
			} },
		{
			id = "camden",
			profile = "high",
			a = "EU",
			b = "J1b27_0_0",
			radius = 300,
			name = "Camden High Street",
			via = {
				{ -640, -1760 },
			},
		},
		{ id = "camden_2", profile = "high", a = "J1b27_0_0", b = "CT", radius = 300, name = "Camden High Street" },
		{ id = "chalkfarm", profile = "main", a = "CT", b = "P3", radius = 300, name = "Chalk Farm Road", via = {
				{ -800, -2120 },
			} },
		{ id = "upper", profile = "high", a = "KX", b = "J0x9_1", radius = 300, name = "Upper Street", via = {
				{ 370, -1730 },
			} },
		{ id = "upper_2", profile = "high", a = "J0x9_1", b = "AN", radius = 300, name = "Upper Street" },
		{ id = "highbury", profile = "main", a = "AN", b = "P4", radius = 120, name = "Highbury Corner" },
		{ id = "kingsland", profile = "dual", a = "OS", b = "HK", radius = 300, name = "Kingsland Road", via = {
				{ 1440, -1720 },
			} },
		{ id = "stokey", profile = "main", a = "HK", b = "P5", radius = 300, name = "Stoke Newington Road", via = {
				{ 1360, -2150 },
			} },
		{ id = "hackney", profile = "dual", a = "OS", b = "J2b9_0_1", radius = 400, name = "Hackney Road" },
		{ id = "hackney_2", profile = "dual", a = "J2b9_0_1", b = "P6", radius = 400, name = "Hackney Road", via = {
				{ 1900, -1660 },
			} },
		{ id = "north1", profile = "arterial", a = "P1", b = "J0b41_0_0", radius = 500, name = "Kilburn Lane" },
		{
			id = "north1_2",
			profile = "arterial",
			a = "J0b41_0_0",
			b = "P2",
			radius = 500,
			name = "Kilburn Lane",
			via = {
				{ -2150, -1900 },
			},
		},
		{ id = "north2", profile = "arterial", a = "P2", b = "P3", radius = 600, name = "Belsize Road", via = {
				{ -1400, -2240 },
			} },
		{ id = "north3", profile = "arterial", a = "P3", b = "J0b11_1_1", radius = 600, name = "Camden Road", via = {
				{ -350, -2300 },
			} },
		{ id = "north3_2", profile = "arterial", a = "J0b11_1_1", b = "P4", radius = 600, name = "Camden Road" },
		{ id = "north4", profile = "arterial", a = "P4", b = "P5", radius = 600, name = "Essex Road", via = {
				{ 750, -2200 },
			} },
		{ id = "north5", profile = "arterial", a = "P5", b = "J2b9_0_0", radius = 600, name = "Amhurst Road" },
		{ id = "north5_2", profile = "arterial", a = "J2b9_0_0", b = "P6", radius = 600, name = "Amhurst Road", via = {
				{ 1750, -2280 },
			} },
		{
			id = "west1",
			profile = "arterial",
			a = "P1",
			b = "J1b28_0_1",
			radius = 500,
			name = "Ladbroke Grove",
			via = {
				{ -2650, -1300 },
			},
		},
		{ id = "west1_2", profile = "arterial", a = "J1b28_0_1", b = "NH", radius = 500, name = "Ladbroke Grove" },
		{ id = "west2", profile = "arterial", a = "NH", b = "KN", radius = 600, name = "Holland Road", via = {
				{ -2860, -560 },
			} },
		{ id = "west3", profile = "arterial", a = "KN", b = "J0b17_1_0", radius = 500, name = "King's Road", via = {
				{ -2750, 250 },
			} },
		{
			id = "west3_3",
			profile = "arterial",
			a = "J0b17_1_0",
			b = "J0b17_0_0",
			radius = 500,
			name = "King's Road",
			via = {
				{ -2300, 460 },
			},
		},
		{ id = "west3_2", profile = "arterial", a = "J0b17_0_0", b = "CH", radius = 500, name = "King's Road" },
		{ id = "bayswater", profile = "main", a = "MA", b = "J0b20_1_0", radius = 600, name = "Bayswater Road" },
		{
			id = "bayswater_2",
			profile = "main",
			a = "J0b20_1_0",
			b = "NH",
			radius = 600,
			name = "Bayswater Road",
			via = {
				{ -2300, -940 },
			},
		},
		{ id = "kensington", profile = "main", a = "HPC", b = "J0b17_0_1", radius = 600, name = "Kensington Road" },
		{
			id = "kensington_2",
			profile = "main",
			a = "J0b17_0_1",
			b = "J0b17_1_1",
			radius = 600,
			name = "Kensington Road",
			via = {
				{ -2350, -150 },
			},
		},
		{ id = "kensington_2_2", profile = "main", a = "J0b17_1_1", b = "KN", radius = 600, name = "Kensington Road" },
		{ id = "whitechapel", profile = "dual", a = "AG", b = "J0b31_1_0", radius = 500, name = "Whitechapel Road" },
		{
			id = "whitechapel_2",
			profile = "dual",
			a = "J0b31_1_0",
			b = "WH",
			radius = 500,
			name = "Whitechapel Road",
			via = {
				{ 2000, -500 },
			},
		},
		{ id = "mileend", profile = "dual", a = "WH", b = "J1b9_1_1", radius = 500, name = "Mile End Road" },
		{
			id = "mileend_2",
			profile = "dual",
			a = "J1b9_1_1",
			b = "J1b9_2_1",
			radius = 500,
			name = "Mile End Road",
			via = {
				{ 2850, -560 },
			},
		},
		{ id = "mileend_2_2", profile = "dual", a = "J1b9_2_1", b = "P8", radius = 500, name = "Mile End Road" },
		{ id = "roman", profile = "main", a = "WH", b = "P7", radius = 500, name = "Roman Road", via = {
				{ 2650, -1000 },
			} },
		{ id = "east1", profile = "arterial", a = "P6", b = "P7", radius = 500, name = "Homerton Road", via = {
				{ 2600, -1800 },
			} },
		{ id = "east2", profile = "arterial", a = "P7", b = "P8", radius = 500, name = "Old Ford Road", via = {
				{ 3150, -1050 },
			} },
		{ id = "east3", profile = "arterial", a = "P8", b = "J0x4_0", radius = 500, name = "Blackwall Road", via = {
				{ 3420, -200 },
			} },
		{ id = "east3_2", profile = "arterial", a = "J0x4_0", b = "P9", radius = 500, name = "Blackwall Road" },
		{ id = "commercial", profile = "dual", a = "minories_mid", b = "J0b31_1_1", radius = 120, name = "Commercial Road" },
		{ id = "commercial_2", profile = "dual", a = "J0b31_1_1", b = "CM", radius = 120, name = "Commercial Road" },
		{ id = "commercial2", profile = "dual", a = "CM", b = "LE", radius = 400, name = "Commercial Road", via = {
				{ 2350, 250 },
			} },
		{ id = "burdett", profile = "street", a = "WH", b = "CM", radius = 400, name = "Burdett Road", via = {
				{ 2250, -250 },
			} },
		{ id = "eastindia", profile = "dual", a = "LE", b = "J1b11_1_0", radius = 500, name = "East India Dock Road" },
		{
			id = "eastindia_2",
			profile = "dual",
			a = "J1b11_1_0",
			b = "J1b11_2_0",
			radius = 500,
			name = "East India Dock Road",
			via = {
				{ 3000, 380 },
			},
		},
		{ id = "eastindia_2_2", profile = "dual", a = "J1b11_2_0", b = "P9", radius = 500, name = "East India Dock Road" },
		{ id = "westferry", profile = "main", a = "LE", b = "IN", radius = 400, name = "Westferry Road", via = {
				{ 2780, 560 },
			} },
		{ id = "dogs1", profile = "main", a = "IN", b = "IW", radius = 350, name = "Westferry Road", via = {
				{ 2810, 1000 },
			} },
		{ id = "dogs2", profile = "main", a = "IW", b = "IS", radius = 350, name = "Westferry Road", via = {
				{ 2840, 1540 },
			} },
		{ id = "dogs3", profile = "main", a = "IS", b = "IE", radius = 350, name = "Manchester Road", via = {
				{ 3150, 1560 },
			} },
		{ id = "dogs4", profile = "main", a = "IE", b = "IN", radius = 350, name = "Manchester Road", via = {
				{ 3230, 1000 },
			} },
		{ id = "canary", profile = "high", a = "IW", b = "IE", radius = 120, name = "Canary Wharf" },
		{ id = "southbank1", profile = "main", a = "SW", b = "CS", radius = 500, name = "Battersea Park Road", via = {
				{ -2250, 950 },
			} },
		{ id = "southbank2", profile = "dual", a = "CS", b = "J0b8_0_1", radius = 500, name = "Albert Embankment" },
		{
			id = "southbank2_2",
			profile = "dual",
			a = "J0b8_0_1",
			b = "J0b8_2_1",
			radius = 500,
			name = "Albert Embankment",
			via = {
				{ -1300, 830 },
			},
		},
		{ id = "southbank2_2_2", profile = "dual", a = "J0b8_2_1", b = "WS", radius = 500, name = "Albert Embankment" },
		{ id = "southbank3", profile = "dual", a = "WS", b = "J0b22_2_0", radius = 500, name = "Stamford Street" },
		{
			id = "southbank3_3",
			profile = "dual",
			a = "J0b22_2_0",
			b = "J0b22_0_0",
			radius = 500,
			name = "Stamford Street",
			via = {
				{ -150, 720 },
			},
		},
		{ id = "southbank3_2", profile = "dual", a = "J0b22_0_0", b = "BS", radius = 500, name = "Stamford Street" },
		{ id = "southbank4", profile = "dual", a = "BS", b = "J1b6_0_1", radius = 500, name = "Southwark Street" },
		{ id = "southbank4_2", profile = "dual", a = "J1b6_0_1", b = "J1b6_1_1", radius = 500, name = "Southwark Street" },
		{
			id = "southbank4_2_2",
			profile = "dual",
			a = "J1b6_1_1",
			b = "J1b6_3_1",
			radius = 500,
			name = "Southwark Street",
			via = {
				{ 1100, 760 },
			},
		},
		{ id = "southbank4_2_2_2", profile = "dual", a = "J1b6_3_1", b = "TS", radius = 500, name = "Southwark Street" },
		{ id = "southbank5", profile = "main", a = "TS", b = "J1b6_5_1", radius = 400, name = "Jamaica Road" },
		{ id = "southbank5_2", profile = "main", a = "J1b6_5_1", b = "RH", radius = 400, name = "Jamaica Road", via = {
				{ 2000, 1000 },
			} },
		{ id = "stgeorge", profile = "dual", a = "WS", b = "J0b8_4_1", radius = 350, name = "St George's Road", via = {
				{ -450, 1100 },
			} },
		{ id = "stgeorge_2", profile = "dual", a = "J0b8_4_1", b = "EL", radius = 350, name = "St George's Road" },
		{ id = "blackfriarsrd", profile = "dual", a = "BS", b = "J0x3_0", radius = 350, name = "Blackfriars Road" },
		{
			id = "blackfriarsrd_2",
			profile = "dual",
			a = "J0x3_0",
			b = "J0b22_0_1",
			radius = 350,
			name = "Blackfriars Road",
			via = {
				{ 250, 1050 },
			},
		},
		{ id = "blackfriarsrd_2_2", profile = "dual", a = "J0b22_0_1", b = "EL", radius = 350, name = "Blackfriars Road" },
		{ id = "south0", profile = "arterial", a = "SW", b = "J0x7_1", radius = 500, name = "Wandsworth Bridge Road" },
		{
			id = "south0_2",
			profile = "arterial",
			a = "J0x7_1",
			b = "P16",
			radius = 500,
			name = "Wandsworth Bridge Road",
			via = {
				{ -2700, 1400 },
			},
		},
		{
			id = "south1",
			profile = "arterial",
			a = "P16",
			b = "J0b32_1_1",
			radius = 600,
			name = "Lavender Hill",
			via = {
				{ -1900, 2050 },
			},
		},
		{ id = "south1_2", profile = "arterial", a = "J0b32_1_1", b = "P15", radius = 600, name = "Lavender Hill" },
		{ id = "south2", profile = "arterial", a = "P15", b = "J2b3_2_0", radius = 600, name = "Clapham Road" },
		{ id = "south2_2", profile = "arterial", a = "J2b3_2_0", b = "KE", radius = 600, name = "Clapham Road", via = {
				{ -850, 2380 },
			} },
		{ id = "south3", profile = "arterial", a = "KE", b = "J2b6_0_1", radius = 600, name = "Camberwell Road" },
		{
			id = "south3_2",
			profile = "arterial",
			a = "J2b6_0_1",
			b = "P13",
			radius = 600,
			name = "Camberwell Road",
			via = {
				{ 350, 2380 },
			},
		},
		{ id = "south4", profile = "arterial", a = "P13", b = "P12", radius = 600, name = "Peckham Road", via = {
				{ 1600, 2330 },
			} },
		{ id = "south5", profile = "arterial", a = "P12", b = "P11", radius = 600, name = "Evelyn Street", via = {
				{ 2650, 2280 },
			} },
		{ id = "vauxhall", profile = "dual", a = "CS", b = "J0x7_0", radius = 400, name = "Nine Elms Lane", via = {
				{ -1600, 1250 },
			} },
		{ id = "vauxhall_2", profile = "dual", a = "J0x7_0", b = "VX", radius = 400, name = "Nine Elms Lane" },
		{ id = "wandsworth", profile = "dual", a = "VX", b = "J0b32_0_0", radius = 500, name = "Wandsworth Road" },
		{
			id = "wandsworth_2",
			profile = "dual",
			a = "J0b32_0_0",
			b = "J0b32_1_0",
			radius = 500,
			name = "Wandsworth Road",
			via = {
				{ -1800, 1680 },
			},
		},
		{ id = "wandsworth_2_2", profile = "dual", a = "J0b32_1_0", b = "P16", radius = 500, name = "Wandsworth Road" },
		{
			id = "clapham",
			profile = "main",
			a = "VX",
			b = "J0b32_0_1",
			radius = 400,
			name = "South Lambeth Road",
			via = {
				{ -1350, 1850 },
			},
		},
		{ id = "clapham_2", profile = "main", a = "J0b32_0_1", b = "P15", radius = 400, name = "South Lambeth Road" },
		{ id = "kenningtonln", profile = "dual", a = "VX", b = "J0b8_2_0", radius = 400, name = "Kennington Lane" },
		{
			id = "kenningtonln_2",
			profile = "dual",
			a = "J0b8_2_0",
			b = "J0b8_4_0",
			radius = 400,
			name = "Kennington Lane",
			via = {
				{ -700, 1450 },
			},
		},
		{ id = "kenningtonln_2_2", profile = "dual", a = "J0b8_4_0", b = "EL", radius = 400, name = "Kennington Lane" },
		{ id = "kennington", profile = "high", a = "EL", b = "J3b8_0_0", radius = 500, name = "Kennington Road" },
		{
			id = "kennington_3",
			profile = "high",
			a = "J3b8_0_0",
			b = "J3b6_2_1",
			radius = 500,
			name = "Kennington Road",
			via = {
				{ -200, 1900 },
			},
		},
		{ id = "kennington_2", profile = "high", a = "J3b6_2_1", b = "KE", radius = 500, name = "Kennington Road" },
		{ id = "walworth", profile = "main", a = "EL", b = "J0b6_6_1", radius = 500, name = "Walworth Road" },
		{
			id = "walworth_3",
			profile = "main",
			a = "J0b6_6_1",
			b = "J0b6_5_1",
			radius = 500,
			name = "Walworth Road",
			via = {
				{ 400, 1850 },
			},
		},
		{ id = "walworth_2", profile = "main", a = "J0b6_5_1", b = "P13", radius = 500, name = "Walworth Road" },
		{ id = "oldkent", profile = "dual", a = "EL", b = "J0b6_6_0", radius = 500, name = "Old Kent Road" },
		{ id = "oldkent_3", profile = "dual", a = "J0b6_6_0", b = "J0b6_5_0", radius = 500, name = "Old Kent Road" },
		{ id = "oldkent_2", profile = "dual", a = "J0b6_5_0", b = "OK", radius = 500, name = "Old Kent Road", via = {
				{ 700, 1520 },
			} },
		{ id = "oldkent2", profile = "dual", a = "OK", b = "J0b13_1_1", radius = 500, name = "Old Kent Road" },
		{
			id = "oldkent2_3",
			profile = "dual",
			a = "J0b13_1_1",
			b = "J0b13_0_1",
			radius = 500,
			name = "Old Kent Road",
			via = {
				{ 1900, 1950 },
			},
		},
		{ id = "oldkent2_2", profile = "dual", a = "J0b13_0_1", b = "P12", radius = 500, name = "Old Kent Road" },
		{ id = "towerbrrd", profile = "main", a = "RH", b = "J0x3_1", radius = 400, name = "Tower Bridge Road" },
		{
			id = "towerbrrd_2",
			profile = "main",
			a = "J0x3_1",
			b = "OK",
			radius = 400,
			name = "Tower Bridge Road",
			via = {
				{ 1800, 1400 },
			},
		},
		{ id = "lower", profile = "main", a = "RH", b = "J0b13_1_0", radius = 500, name = "Lower Road" },
		{ id = "lower_3", profile = "main", a = "J0b13_1_0", b = "J0b13_0_0", radius = 500, name = "Lower Road" },
		{ id = "lower_2", profile = "main", a = "J0b13_0_0", b = "P11", radius = 500, name = "Lower Road", via = {
				{ 2480, 1950 },
			} },
		{ id = "s0x3", profile = "street", a = "J0x3_0", b = "J1b6_0_0", radius = 180, name = "Albert Street" },
		{ id = "s0x3_2", profile = "street", a = "J1b6_0_0", b = "J1b6_1_0", radius = 180, name = "Albert Street" },
		{
			id = "s0x3_2_2",
			profile = "street",
			a = "J1b6_1_0",
			b = "J1b6_3_0",
			radius = 180,
			name = "Albert Street",
			via = {
				{ 1118.2, 1211.9 },
			},
		},
		{ id = "s0x3_2_2_2", profile = "street", a = "J1b6_3_0", b = "J1b6_5_0", radius = 180, name = "Albert Street" },
		{ id = "s0x3_2_2_2_2", profile = "street", a = "J1b6_5_0", b = "J0x3_1", radius = 180, name = "Albert Street" },
		{ id = "s0x4", profile = "street", a = "J0x4_0", b = "J1b9_2_0", radius = 180, name = "Victoria Road" },
		{
			id = "s0x4_3",
			profile = "street",
			a = "J1b9_2_0",
			b = "J1b9_1_0",
			radius = 180,
			name = "Victoria Road",
			via = {
				{ 2781.3, -70.9 },
			},
		},
		{ id = "s0x4_2", profile = "street", a = "J1b9_1_0", b = "CM", radius = 180, name = "Victoria Road" },
		{
			id = "s0b6_5",
			profile = "back",
			a = "J0b6_5_0",
			b = "J0b6_5_1",
			radius = 180,
			name = "Church Street",
			via = {
				{ 514.3, 1723.3 },
			},
		},
		{ id = "s0b6_6", profile = "back", a = "J0b6_6_0", b = "J0b6_6_1", radius = 180, name = "Mill Lane", via = {
				{ 300.5, 1619.4 },
			} },
		{ id = "s0x7", profile = "street", a = "J0x7_0", b = "J0x7_1", radius = 180, name = "Station Road", via = {
				{ -2086.5, 1367.5 },
			} },
		{ id = "s0b8_0", profile = "back", a = "J0x7_0", b = "J1b23_0_1", radius = 180, name = "Park Road" },
		{
			id = "s0b8_0_2",
			profile = "back",
			a = "J1b23_0_1",
			b = "J0b8_0_1",
			radius = 180,
			name = "Park Road",
			via = {
				{ -1525.7, 1100.6 },
			},
		},
		{ id = "s0b8_2", profile = "back", a = "J0b8_2_0", b = "J1b22_1_0", radius = 180, name = "Queen's Road" },
		{
			id = "s0b8_2_2",
			profile = "back",
			a = "J1b22_1_0",
			b = "J1b23_0_0",
			radius = 180,
			name = "Queen's Road",
			via = {
				{ -1006.2, 1124.5 },
			},
		},
		{ id = "s0b8_2_2_2", profile = "back", a = "J1b23_0_0", b = "J0b8_2_1", radius = 180, name = "Queen's Road" },
		{
			id = "s0b8_4",
			profile = "back",
			a = "J0b8_4_0",
			b = "J0b8_4_1",
			radius = 180,
			name = "King Street",
			via = {
				{ -421.5, 1265.7 },
			},
		},
		{ id = "s0x9", profile = "street", a = "HK", b = "J1b24_0_0", radius = 180, name = "George Street" },
		{ id = "s0x9_2", profile = "street", a = "J1b24_0_0", b = "J1b24_1_0", radius = 180, name = "George Street" },
		{ id = "s0x9_2_2", profile = "street", a = "J1b24_1_0", b = "J0x9_1", radius = 180, name = "George Street" },
		{ id = "s0x10", profile = "street", a = "J0x10_0", b = "J1b16_0_0", radius = 180, name = "Granville Road" },
		{ id = "s0x10_2", profile = "street", a = "J1b16_0_0", b = "J1b16_1_0", radius = 180, name = "Granville Road" },
		{ id = "s0x10_2_2", profile = "street", a = "J1b16_1_0", b = "J1b16_2_0", radius = 180, name = "Granville Road" },
		{ id = "s0x10_2_2_2", profile = "street", a = "J1b16_2_0", b = "J0x10_1", radius = 180, name = "Granville Road" },
		{ id = "s0b11_1", profile = "back", a = "J0b11_1_0", b = "J1b27_0_1", radius = 180, name = "Elm Grove" },
		{
			id = "s0b11_1_2",
			profile = "back",
			a = "J1b27_0_1",
			b = "J0b11_1_1",
			radius = 180,
			name = "Elm Grove",
			via = {
				{ -261.2, -1921.4 },
			},
		},
		{
			id = "s0b13_0",
			profile = "back",
			a = "J0b13_0_0",
			b = "J0b13_0_1",
			radius = 180,
			name = "Cedar Road",
			via = {
				{ 2198.2, 1941.7 },
			},
		},
		{
			id = "s0b13_1",
			profile = "back",
			a = "J0b13_1_0",
			b = "J0b13_1_1",
			radius = 180,
			name = "Princes Street",
			via = {
				{ 1982.8, 1608.8 },
			},
		},
		{
			id = "s0b15_0",
			profile = "back",
			a = "J0b15_0_0",
			b = "J0b15_0_1",
			radius = 180,
			name = "Union Street",
			via = {
				{ 530.9, -38.1 },
			},
		},
		{
			id = "s0b15_2",
			profile = "back",
			a = "J0b15_2_0",
			b = "J0b15_2_1",
			radius = 180,
			name = "Market Street",
			via = {
				{ 4.4, 46.4 },
			},
		},
		{
			id = "s0b15_3",
			profile = "back",
			a = "J0b15_3_0",
			b = "J0b15_3_1",
			radius = 180,
			name = "Chapel Road",
			via = {
				{ -276.5, 58.9 },
			},
		},
		{
			id = "s0b15_4",
			profile = "back",
			a = "J0b15_4_0",
			b = "J0b15_4_1",
			radius = 180,
			name = "Brook Street",
			via = {
				{ -538.2, 84.1 },
			},
		},
		{
			id = "s0b16_2",
			profile = "back",
			a = "J0b16_2_0",
			b = "J0b16_2_1",
			radius = 180,
			name = "Grove Road",
			via = {
				{ 2.1, -1235.9 },
			},
		},
		{
			id = "s0b17_0",
			profile = "back",
			a = "J0b17_0_0",
			b = "J0b17_0_1",
			radius = 180,
			name = "Manor Road",
			via = {
				{ -2158, 166.3 },
			},
		},
		{
			id = "s0b17_1",
			profile = "back",
			a = "J0b17_1_0",
			b = "J0b17_1_1",
			radius = 180,
			name = "Clarence Road",
			via = {
				{ -2436.1, 123.9 },
			},
		},
		{ id = "s0b19_1", profile = "back", a = "J0b19_1_0", b = "J1b40_0_0", radius = 180, name = "Wellington Street" },
		{
			id = "s0b19_1_2",
			profile = "back",
			a = "J1b40_0_0",
			b = "J0b19_1_1",
			radius = 180,
			name = "Wellington Street",
			via = {
				{ -1609.3, -658.2 },
			},
		},
		{
			id = "s0b19_2",
			profile = "back",
			a = "J0b19_2_0",
			b = "J0b19_2_1",
			radius = 180,
			name = "Nelson Road",
			via = {
				{ -1374.5, -701.7 },
			},
		},
		{ id = "s0b20_1", profile = "back", a = "J0b20_1_0", b = "J1b28_0_0", radius = 180, name = "Alma Road" },
		{
			id = "s0b20_1_2",
			profile = "back",
			a = "J1b28_0_0",
			b = "J0b20_1_1",
			radius = 180,
			name = "Alma Road",
			via = {
				{ -2128, -1250.6 },
			},
		},
		{
			id = "s0b21_0",
			profile = "back",
			a = "J0b21_0_0",
			b = "J0b21_0_1",
			radius = 180,
			name = "Milton Street",
			via = {
				{ 1383.2, 190.6 },
			},
		},
		{
			id = "s0b21_1",
			profile = "back",
			a = "minories_mid",
			b = "J0b21_1_1",
			radius = 180,
			name = "Cromwell Road",
			via = {
				{ 1347.7, -13.7 },
			},
		},
		{
			id = "s0b22_0",
			profile = "back",
			a = "J0b22_0_0",
			b = "J1b29_0_0",
			radius = 180,
			name = "Stanley Road",
			via = {
				{ 90.2, 955.6 },
			},
		},
		{ id = "s0b22_0_2", profile = "back", a = "J1b29_0_0", b = "J0b22_0_1", radius = 180, name = "Stanley Road" },
		{
			id = "s0b22_2",
			profile = "back",
			a = "J0b22_2_0",
			b = "J0b8_4_1",
			radius = 180,
			name = "Hamilton Road",
			via = {
				{ -416.9, 910.4 },
			},
		},
		{
			id = "s0b24_1",
			profile = "back",
			a = "J0b19_2_1",
			b = "J1b32_0_1",
			radius = 180,
			name = "Gordon Road",
			via = {
				{ -1346.2, -1242.6 },
			},
		},
		{ id = "s0b24_1_2", profile = "back", a = "J1b32_0_1", b = "J0b24_1_1", radius = 180, name = "Gordon Road" },
		{
			id = "s0b28_0",
			profile = "back",
			a = "J0b28_0_0",
			b = "J0b15_0_0",
			radius = 180,
			name = "Warwick Street",
			via = {
				{ 497.4, -522.7 },
			},
		},
		{
			id = "s0b29_0",
			profile = "back",
			a = "J0b29_0_0",
			b = "J1b30_0_0",
			radius = 180,
			name = "Oxford Road",
			via = {
				{ 2183.8, 262.1 },
			},
		},
		{ id = "s0b29_0_2", profile = "back", a = "J1b30_0_0", b = "CM", radius = 180, name = "Oxford Road" },
		{
			id = "s0b31_1",
			profile = "back",
			a = "J0b31_1_0",
			b = "J0b31_1_1",
			radius = 180,
			name = "Cambridge Street",
			via = {
				{ 1775.4, -247.5 },
			},
		},
		{
			id = "s0b32_0",
			profile = "back",
			a = "J0b32_0_0",
			b = "J0b32_0_1",
			radius = 180,
			name = "York Road",
			via = {
				{ -1465.1, 1816.9 },
			},
		},
		{
			id = "s0b32_1",
			profile = "back",
			a = "J0b32_1_0",
			b = "J0b32_1_1",
			radius = 180,
			name = "Beaufort Street",
			via = {
				{ -1772.2, 1895 },
			},
		},
		{ id = "s0b33_1", profile = "back", a = "J0b33_1_0", b = "J1b42_0_1", radius = 180, name = "Charlotte Street" },
		{
			id = "s0b33_1_2",
			profile = "back",
			a = "J1b42_0_1",
			b = "J0b33_1_1",
			radius = 180,
			name = "Charlotte Street",
			via = {
				{ 1292.2, -882.2 },
			},
		},
		{
			id = "s0b33_2",
			profile = "back",
			a = "J0b33_2_0",
			b = "J0b33_2_1",
			radius = 180,
			name = "Tavistock Road",
			via = {
				{ 1310.9, -1130.8 },
			},
		},
		{ id = "s0b34_0", profile = "back", a = "J0b34_0_0", b = "J0b21_1_1", radius = 180, name = "Ladbroke Street" },
		{
			id = "s0b35_0",
			profile = "back",
			a = "J0b19_2_0",
			b = "J0b35_0_1",
			radius = 180,
			name = "Grafton Road",
			via = {
				{ -1212.7, -289.3 },
			},
		},
		{
			id = "s0b35_1",
			profile = "back",
			a = "J0b19_1_0",
			b = "J0b35_1_1",
			radius = 180,
			name = "Belgrave Road",
			via = {
				{ -1457.3, -262.4 },
			},
		},
		{
			id = "s0b36_0",
			profile = "back",
			a = "J0b36_0_0",
			b = "J0b36_0_1",
			radius = 180,
			name = "Hanover Street",
			via = {
				{ -821.3, -695.8 },
			},
		},
		{
			id = "s0b41_0",
			profile = "back",
			a = "J0b41_0_0",
			b = "J0b41_0_1",
			radius = 180,
			name = "Arundel Road",
			via = {
				{ -2063.6, -1769.7 },
			},
		},
		{
			id = "s1b6_0",
			profile = "back",
			a = "J1b6_0_0",
			b = "J1b6_0_1",
			radius = 180,
			name = "Cornwall Road",
			via = {
				{ 682.3, 910.2 },
			},
		},
		{
			id = "s1b6_1",
			profile = "back",
			a = "J1b6_1_0",
			b = "J1b6_1_1",
			radius = 180,
			name = "Devonshire Street",
			via = {
				{ 943.6, 960.4 },
			},
		},
		{
			id = "s1b6_3",
			profile = "back",
			a = "J1b6_3_0",
			b = "J1b6_3_1",
			radius = 180,
			name = "Exeter Road",
			via = {
				{ 1427.6, 1047.2 },
			},
		},
		{
			id = "s1b6_5",
			profile = "back",
			a = "J1b6_5_0",
			b = "J1b6_5_1",
			radius = 180,
			name = "Fairfield Road",
			via = {
				{ 1909.7, 1146.7 },
			},
		},
		{
			id = "s1b9_1",
			profile = "back",
			a = "J1b9_1_0",
			b = "J1b9_1_1",
			radius = 180,
			name = "Glebe Road",
			via = {
				{ 2739.3, -307.8 },
			},
		},
		{
			id = "s1b9_2",
			profile = "back",
			a = "J1b9_2_0",
			b = "J1b9_2_1",
			radius = 180,
			name = "Holly Street",
			via = {
				{ 3014.4, -347.8 },
			},
		},
		{ id = "s1b11_1", profile = "back", a = "J1b11_1_0", b = "J1b9_1_0", radius = 180, name = "Ivy Road", via = {
				{ 2702.1, 186.9 },
			} },
		{
			id = "s1b11_2",
			profile = "back",
			a = "J1b11_2_0",
			b = "J1b9_2_0",
			radius = 180,
			name = "Jubilee Street",
			via = {
				{ 2981.2, 134.1 },
			},
		},
		{
			id = "s1b16_0",
			profile = "back",
			a = "J1b16_0_0",
			b = "J0b16_2_0",
			radius = 180,
			name = "Kensal Road",
			via = {
				{ 11.5, -699.5 },
			},
		},
		{
			id = "s1b16_1",
			profile = "back",
			a = "J1b16_1_0",
			b = "J1b16_1_1",
			radius = 180,
			name = "Linden Grove",
			via = {
				{ -219.3, -708.9 },
			},
		},
		{
			id = "s1b16_2",
			profile = "back",
			a = "J1b16_2_0",
			b = "J1b16_2_1",
			radius = 180,
			name = "Maple Street",
			via = {
				{ -461.2, -732.5 },
			},
		},
		{
			id = "s1b22_1",
			profile = "back",
			a = "J1b22_1_0",
			b = "J0b8_4_1",
			radius = 180,
			name = "Northfield Road",
			via = {
				{ -726.4, 1120.6 },
			},
		},
		{
			id = "s1b23_0",
			profile = "back",
			a = "J1b23_0_0",
			b = "J1b23_0_1",
			radius = 180,
			name = "Orchard Street",
			via = {
				{ -1266.1, 1133.2 },
			},
		},
		{
			id = "s1b24_0",
			profile = "back",
			a = "J1b24_0_0",
			b = "J1b24_0_1",
			radius = 180,
			name = "Priory Road",
			via = {
				{ 1002.7, -1688.6 },
			},
		},
		{
			id = "s1b24_1",
			profile = "back",
			a = "J1b24_1_0",
			b = "J1b24_1_1",
			radius = 180,
			name = "Rectory Lane",
			via = {
				{ 755.8, -1689.4 },
			},
		},
		{
			id = "s1b26_1",
			profile = "back",
			a = "J0b15_3_0",
			b = "J1b16_1_0",
			radius = 180,
			name = "St John's Road",
			via = {
				{ -283, -325 },
			},
		},
		{
			id = "s1b26_2",
			profile = "back",
			a = "J0b15_2_0",
			b = "J1b16_0_0",
			radius = 180,
			name = "Tower Street",
			via = {
				{ -26.8, -326.6 },
			},
		},
		{
			id = "s1b27_0",
			profile = "back",
			a = "J1b27_0_0",
			b = "J1b27_0_1",
			radius = 180,
			name = "Vicarage Road",
			via = {
				{ -453.7, -1815.4 },
			},
		},
		{
			id = "s1b28_0",
			profile = "back",
			a = "J1b28_0_0",
			b = "J1b28_0_1",
			radius = 180,
			name = "Willow Walk",
			via = {
				{ -2400.1, -1230.5 },
			},
		},
		{
			id = "s1b29_0",
			profile = "back",
			a = "J1b29_0_0",
			b = "J0b8_4_1",
			radius = 180,
			name = "Yew Street",
			via = {
				{ -183.5, 1051.7 },
			},
		},
		{
			id = "s1b30_0",
			profile = "back",
			a = "J1b30_0_0",
			b = "J0b21_0_0",
			radius = 180,
			name = "Abbey Road",
			via = {
				{ 1903, 240.6 },
			},
		},
		{
			id = "s1b32_0",
			profile = "back",
			a = "J1b32_0_0",
			b = "J1b32_0_1",
			radius = 180,
			name = "Bedford Street",
			via = {
				{ -1590.5, -1261.3 },
			},
		},
		{ id = "s1b36_0", profile = "back", a = "J1b36_0_0", b = "MN", radius = 180, name = "Carlton Road", via = {
				{ 926.5, 161.9 },
			} },
		{
			id = "s1b40_0",
			profile = "back",
			a = "J1b40_0_0",
			b = "J1b40_0_1",
			radius = 180,
			name = "Dorset Street",
			via = {
				{ -1710.9, -503.5 },
			},
		},
		{
			id = "s1b42_0",
			profile = "back",
			a = "J1b42_0_0",
			b = "J1b42_0_1",
			radius = 180,
			name = "Eaton Road",
			via = {
				{ 1192.5, -703.3 },
			},
		},
		{ id = "s2b3_2", profile = "back", a = "J2b3_2_0", b = "J3b6_2_0", radius = 180, name = "Frith Street" },
		{
			id = "s2b3_2_2",
			profile = "back",
			a = "J3b6_2_0",
			b = "J0b8_2_0",
			radius = 180,
			name = "Frith Street",
			via = {
				{ -965.6, 1899.7 },
			},
		},
		{
			id = "s2b5_0",
			profile = "back",
			a = "J2b5_0_0",
			b = "J2b5_0_1",
			radius = 180,
			name = "Gower Street",
			via = {
				{ 657.5, -885.4 },
			},
		},
		{
			id = "s2b6_0",
			profile = "back",
			a = "J0b6_5_1",
			b = "J3b8_1_1",
			radius = 180,
			name = "Hereford Road",
			via = {
				{ 431, 2199.1 },
			},
		},
		{ id = "s2b6_0_2", profile = "back", a = "J3b8_1_1", b = "J2b6_0_1", radius = 180, name = "Hereford Road" },
		{
			id = "s2b9_0",
			profile = "back",
			a = "J2b9_0_0",
			b = "J2b9_0_1",
			radius = 180,
			name = "Inverness Street",
			via = {
				{ 1688.8, -1940.3 },
			},
		},
		{
			id = "s3b6_2",
			profile = "back",
			a = "J3b6_2_0",
			b = "J3b6_2_1",
			radius = 180,
			name = "Judd Street",
			via = {
				{ -626.7, 2146.2 },
			},
		},
		{
			id = "s3b8_0",
			profile = "back",
			a = "J3b8_0_0",
			b = "J0b6_5_1",
			radius = 180,
			name = "Kent Street",
			via = {
				{ 185.2, 1864.9 },
			},
		},
		{
			id = "s3b8_1",
			profile = "back",
			a = "J3b6_2_1",
			b = "J3b8_1_1",
			radius = 180,
			name = "Lansdowne Road",
			via = {
				{ 79, 2135.8 },
			},
		},
	},
	river = {
		width = 200,
		radius = 420,
		walk = 24,
		points = {
			{ -3700, 520 },
			{ -2700, 610 },
			{ -1750, 750 },
			{ -1000, 560 },
			{ -300, 450 },
			{ 500, 430 },
			{ 1200, 560 },
			{ 1750, 720 },
			{ 2250, 770 },
			{ 2560, 1080 },
			{ 2620, 1580 },
			{ 2950, 1880 },
			{ 3290, 1680 },
			{ 3420, 1100 },
			{ 3620, 640 },
			{ 4400, 480 },
		},
	},
	districts = {
		{ "canary", 2650, 760, 3400, 1850 },
		{ "westminster", -1850, -560, -560, 470 },
		{ "city", 250, -1450, 1560, 470 },
		{ "westend", -1850, -1500, -560, -560 },
		{ "mansions", -560, -1520, 250, -100 },
		{ "southbank", -1000, 590, 1700, 1080 },
		{ "docklands", 1560, -600, 2700, 760 },
		{ "estate", 450, 1150, 1600, 1720 },
		{ "estate", 2700, -1500, 3800, -500 },
		{ "industrial", 1650, 1150, 2700, 2700 },
		{ "suburb", -3200, 1080, -1250, 2800 },
		{ "suburb", 1560, -2700, 3200, -1500 },
	},
	sites = {
		{ "hydepark", -2410, -905, -1905, -215 },
		{ "stjames", -1790, -70, -1010, 240 },
		{ "palace", -1290, 350, -870, 425 },
		{ "bigwheel", -700, 595, -380, 668 },
		{ "regentspark", -1760, -1990, -1180, -1560 },
		{ "kenningtonpark", -720, 1620, -260, 1960 },
		{ "square", -340, -1360, -180, -1200 },
		{ "square", 700, -1330, 860, -1170 },
	},
	frontSites = {
		{ kind = "petrol", x = 865.9, z = 1593.1, fx = 0.12, fz = -0.99, width = 240, depth = 170 },
		{ kind = "busgarage", x = 1841.2, z = 1973.2, fx = 0.72, fz = -0.69, width = 320, depth = 260 },
		{ kind = "police", x = 265.9, z = -532.2, fx = -1, fz = -0.07, width = 220, depth = 170 },
	},
}
]])
put(folder4, "ModuleScript", "LondonMap", [=[
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
]=])
put(folder4, "Script", "Main", [[
-- Starts everything on the server.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Cars = require(script.Parent.Cars)
local Garage = require(script.Parent.Garage)
local LightingSetup = require(script.Parent.LightingSetup)
local LondonMap = require(script.Parent.LondonMap)
local Pedestrians = require(script.Parent.Pedestrians)
local PlayerData = require(script.Parent.PlayerData)
local TrafficLights = require(script.Parent.TrafficLights)

LightingSetup.apply()
PlayerData.start()
-- Build London, unless it's already saved in the place (built in Studio with the Command Bar)
if Config.BuildMap and not Workspace:FindFirstChild("London") then
	LondonMap.build()
end
LondonMap.startClock()
Pedestrians.setup()
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
put(folder4, "ModuleScript", "Pedestrians", [[
-- People walking on the pavements, like the pedestrians in Birmingham Vehicle Simulator.
-- This part runs on the server: it makes a set of different people (skin, clothes, hair, height) and puts
-- them in ReplicatedStorage → PedestrianModels. Each player's device then walks copies of them along the
-- pavements near that player (see the Pedestrians client script), so they cost the server nothing.
-- The pavements they walk along are in MapInfo → Pavements, written by LondonMap.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Pedestrians = {}

local PEOPLE = 16

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local SKIN = { rgb(255, 220, 190), rgb(234, 192, 160), rgb(198, 150, 112), rgb(160, 110, 80), rgb(110, 72, 50), rgb(80, 52, 38), rgb(245, 205, 175) }
local TOPS = {
	rgb(30, 30, 34), rgb(40, 60, 110), rgb(150, 30, 35), rgb(225, 225, 220), rgb(90, 100, 90), rgb(120, 90, 60),
	rgb(60, 110, 150), rgb(200, 160, 60), rgb(70, 40, 80), rgb(160, 160, 165), rgb(20, 80, 60), rgb(220, 120, 140),
}
local TROUSERS = { rgb(30, 40, 70), rgb(25, 25, 28), rgb(60, 70, 90), rgb(110, 100, 80), rgb(80, 80, 85), rgb(45, 55, 100) }
local HAIR = { rgb(30, 22, 16), rgb(70, 45, 25), rgb(120, 80, 40), rgb(200, 170, 110), rgb(20, 20, 20), rgb(150, 150, 150) }

local function choose<T>(list: { T }, random: Random): T
	return list[random:NextInteger(1, #list)]
end

local function makePerson(index: number, random: Random): Model?
	local description = Instance.new("HumanoidDescription")
	local skin = choose(SKIN, random)
	local top = choose(TOPS, random)
	local longSleeves = random:NextNumber() < 0.6
	description.HeadColor = skin
	description.TorsoColor = top
	description.LeftArmColor = if longSleeves then top else skin
	description.RightArmColor = if longSleeves then top else skin
	description.LeftLegColor = choose(TROUSERS, random)
	description.RightLegColor = description.LeftLegColor
	description.HeightScale = random:NextNumber(0.9, 1.05)
	description.WidthScale = random:NextNumber(0.85, 1)
	description.DepthScale = description.WidthScale
	description.BodyTypeScale = random:NextNumber(0, 0.3)
	local ok, result = pcall(function()
		return Players:CreateHumanoidModelFromDescription(description, Enum.HumanoidRigType.R15)
	end)
	if not ok or not result then
		warn("[Pedestrians] couldn't make a person: " .. tostring(result))
		return nil
	end
	local model = result :: Model
	model.Name = "Person" .. index
	-- Hair: a cap on top of the head, sometimes longer at the back
	local head = model:FindFirstChild("Head")
	if head and head:IsA("BasePart") then
		local long = random:NextNumber() < 0.4
		local hair = Instance.new("Part")
		hair.Name = "Hair"
		hair.Size = Vector3.new(head.Size.X * 1.06, head.Size.Y * (if long then 0.85 else 0.42), head.Size.Z * 1.08)
		hair.CFrame = head.CFrame * CFrame.new(0, head.Size.Y * (if long then 0.12 else 0.34), head.Size.Z * 0.06)
		hair.Color = choose(HAIR, random)
		hair.Material = Enum.Material.Fabric
		hair.TopSurface = Enum.SurfaceType.Smooth
		hair.BottomSurface = Enum.SurfaceType.Smooth
		hair.Parent = model
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = head
		weld.Part1 = hair
		weld.Parent = hair
	end
	for _, item in model:GetDescendants() do
		if item:IsA("BasePart") then
			item.CanCollide = false
			item.CanQuery = false
			item.CanTouch = false
			item.Massless = true
		elseif item:IsA("LuaSourceContainer") then
			item:Destroy()
		end
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		humanoid.EvaluateStateMachine = false
		humanoid.BreakJointsOnDeath = false
	end
	return model
end

-- Makes the people (it takes a few seconds, so it runs in the background)
function Pedestrians.setup()
	task.spawn(function()
		local folder = Instance.new("Folder")
		folder.Name = "PedestrianModels"
		local random = Random.new(42)
		for i = 1, PEOPLE do
			local person = makePerson(i, random)
			if person then
				person.Parent = folder
			end
		end
		folder.Parent = ReplicatedStorage
	end)
end

return Pedestrians
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
local RunService = game:GetService("RunService")

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
	-- Testing in Studio: show every vehicle as owned, without adding them to the save
	if RunService:IsStudio() and Config.UnlockEverythingInStudio then
		for _, vehicle in Vehicles.List do
			player:SetAttribute("Owned_" .. vehicle.id, true)
		end
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
	if vehicle.price == 0 or (RunService:IsStudio() and Config.UnlockEverythingInStudio) then
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
put(folder4, "ModuleScript", "RoadKit", [[
-- Geometry for the roads: smooth paths through control points, strips of road that follow them,
-- triangles (made from two wedges, so curves have no gaps), walls and painted lines.
-- RoadNetwork uses it to build every road, junction and roundabout; LondonMap uses it for the river.
-- A "path" is a list of points along the middle of a road. "Offsets" are distances to the left of the
-- path (negative is right), measured flat across it.

local TownKit = require(script.Parent.TownKit)

local RoadKit = {}

export type Path = {
	points: { Vector3 }, -- points along the middle, with heights
	dists: { number }, -- distance along the path at each point (measured flat)
	normals: { Vector3 }, -- flat unit vector pointing left at each point
	length: number,
	stations: { number }, -- where each control point sits along the path
}

local MAX_TURN_STEP = math.rad(6) -- curves are cut into pieces of at most this angle
local MAX_PIECE = 1000 -- straights are cut into pieces no longer than this (parts can't be over 2048 studs)

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

-- The flat direction 90 degrees to the left of `direction` (x east, z south)
function RoadKit.leftOf(direction: Vector3): Vector3
	return Vector3.new(direction.Z, 0, -direction.X)
end

local leftOf = RoadKit.leftOf

-- A path through `controls` with its corners rounded off to `radius`. Heights go in a straight line
-- from one control point to the next. tools/london_layout.py does exactly the same sums, so distances
-- along the path (for slip roads and laybys) match.
function RoadKit.path(controls: { Vector3 }, radius: number): Path
	local flatPoints: { Vector3 } = { flat(controls[1]) }
	local controlAt: { number } = { 1 }
	for i = 2, #controls - 1 do
		local a, b, c = flat(controls[i - 1]), flat(controls[i]), flat(controls[i + 1])
		local d1, d2 = (b - a).Unit, (c - b).Unit
		local turn = math.acos(math.clamp(d1:Dot(d2), -1, 1))
		if turn < math.rad(0.5) then
			table.insert(flatPoints, b)
			table.insert(controlAt, #flatPoints)
		else
			local t = radius * math.tan(turn / 2)
			local limit = 0.48 * math.min((b - a).Magnitude, (c - b).Magnitude)
			local r = radius
			if t > limit then
				t = limit
				r = t / math.tan(turn / 2)
			end
			local start = b - d1 * t
			local finish = b + d2 * t
			local side = leftOf(d1)
			local towards = if side:Dot(d2) > 0 then side else -side
			local centre = start + towards * r
			local a0 = math.atan2(start.Z - centre.Z, start.X - centre.X)
			local a1 = math.atan2(finish.Z - centre.Z, finish.X - centre.X)
			local sweep = a1 - a0
			while sweep > math.pi do
				sweep -= 2 * math.pi
			end
			while sweep < -math.pi do
				sweep += 2 * math.pi
			end
			local steps = math.max(1, math.ceil(math.abs(sweep) / MAX_TURN_STEP))
			table.insert(flatPoints, start)
			local middle: number? = nil
			for k = 1, steps - 1 do
				local angle = a0 + sweep * k / steps
				table.insert(flatPoints, Vector3.new(centre.X + r * math.cos(angle), 0, centre.Z + r * math.sin(angle)))
				if k == steps // 2 then
					middle = #flatPoints
				end
			end
			table.insert(flatPoints, finish)
			table.insert(controlAt, middle or #flatPoints)
		end
	end
	table.insert(flatPoints, flat(controls[#controls]))
	table.insert(controlAt, #flatPoints)

	local dists = { 0 }
	for k = 2, #flatPoints do
		dists[k] = dists[k - 1] + (flatPoints[k] - flatPoints[k - 1]).Magnitude
	end
	local stations = {}
	for i, index in controlAt do
		stations[i] = dists[index]
	end

	-- Cut long straights into shorter pieces (doesn't change any distances)
	local points: { Vector3 } = { flatPoints[1] }
	local cutDists = { 0 }
	for k = 2, #flatPoints do
		local from, to = flatPoints[k - 1], flatPoints[k]
		local pieces = math.ceil((to - from).Magnitude / MAX_PIECE)
		for j = 1, pieces do
			table.insert(points, from:Lerp(to, j / pieces))
			table.insert(cutDists, dists[k - 1] + (dists[k] - dists[k - 1]) * j / pieces)
		end
	end

	-- Heights: straight lines between control points
	local function heightAt(s: number): number
		for i = 2, #stations do
			if s <= stations[i] or i == #stations then
				local s0, s1 = stations[i - 1], stations[i]
				local f = if s1 - s0 < 1e-6 then 0 else math.clamp((s - s0) / (s1 - s0), 0, 1)
				return controls[i - 1].Y + (controls[i].Y - controls[i - 1].Y) * f
			end
		end
		return controls[#controls].Y
	end
	for k, p in points do
		points[k] = Vector3.new(p.X, heightAt(cutDists[k]), p.Z)
	end

	-- Left normals, averaging the two pieces either side of each point so strips join up neatly
	local normals: { Vector3 } = {}
	for k = 1, #points do
		local before = if k > 1 then flat(points[k] - points[k - 1]) else nil
		local after = if k < #points then flat(points[k + 1] - points[k]) else nil
		local direction: Vector3
		if before and after and before.Magnitude > 1e-6 and after.Magnitude > 1e-6 then
			direction = before.Unit + after.Unit
			if direction.Magnitude < 1e-6 then
				direction = after
			end
		else
			direction = (after or before) :: Vector3
		end
		normals[k] = leftOf(direction.Unit)
	end

	return { points = points, dists = cutDists, normals = normals, length = cutDists[#cutDists], stations = stations }
end

-- Which piece of the path distance `s` falls in, and how far through it (0 to 1)
local function locate(path: Path, s: number): (number, number)
	local dists = path.dists
	local low, high = 1, #dists
	if s <= 0 then
		return 2, 0
	end
	if s >= path.length then
		return #dists, 1
	end
	while high - low > 1 do
		local mid = (low + high) // 2
		if dists[mid] <= s then
			low = mid
		else
			high = mid
		end
	end
	local span = dists[high] - dists[low]
	return high, if span < 1e-9 then 0 else (s - dists[low]) / span
end

-- The point, flat direction of travel and left normal at distance `s` along the path
function RoadKit.at(path: Path, s: number): (Vector3, Vector3, Vector3)
	local k, f = locate(path, s)
	local a, b = path.points[k - 1], path.points[k]
	local direction = flat(b - a)
	direction = if direction.Magnitude > 1e-6 then direction.Unit else Vector3.zAxis
	local normal = path.normals[k - 1]:Lerp(path.normals[k], f)
	normal = if normal.Magnitude > 1e-6 then normal.Unit else leftOf(direction)
	return a:Lerp(b, f), direction, normal
end

-- The points and normals between distances s0 and s1, including the exact ends
function RoadKit.slice(path: Path, s0: number, s1: number): ({ Vector3 }, { Vector3 })
	local points, normals = {}, {}
	if s1 - s0 < 0.05 then
		return points, normals
	end
	local p0, _, n0 = RoadKit.at(path, s0)
	table.insert(points, p0)
	table.insert(normals, n0)
	for k = 1, #path.points do
		local d = path.dists[k]
		if d > s0 + 0.05 and d < s1 - 0.05 then
			table.insert(points, path.points[k])
			table.insert(normals, path.normals[k])
		end
	end
	local p1, _, n1 = RoadKit.at(path, s1)
	table.insert(points, p1)
	table.insert(normals, n1)
	return points, normals
end

-- Normals for any list of points (for kerbs round corners, river banks and so on)
function RoadKit.normalsFor(points: { Vector3 }): { Vector3 }
	local normals = {}
	for k = 1, #points do
		local before = if k > 1 then flat(points[k] - points[k - 1]) else nil
		local after = if k < #points then flat(points[k + 1] - points[k]) else nil
		local direction: Vector3
		if before and after and before.Magnitude > 1e-6 and after.Magnitude > 1e-6 then
			direction = before.Unit + after.Unit
			if direction.Magnitude < 1e-6 then
				direction = after
			end
		else
			direction = (after or before or Vector3.zAxis) :: Vector3
		end
		normals[k] = leftOf(if direction.Magnitude > 1e-6 then direction.Unit else Vector3.zAxis)
	end
	return normals
end

-- Points `offset` studs to the left of each point (raised by `lift`)
function RoadKit.offset(points: { Vector3 }, normals: { Vector3 }, offset: number, lift: number?): { Vector3 }
	local out = {}
	local up = Vector3.new(0, lift or 0, 0)
	for k, p in points do
		out[k] = p + normals[k] * offset + up
	end
	return out
end

-- Points along a circle round `centre`, from angle a0 to a1 (radians, measured with math.atan2(z, x))
function RoadKit.arc(centre: Vector3, radius: number, a0: number, a1: number, maxStep: number?): { Vector3 }
	local sweep = a1 - a0
	local steps = math.max(1, math.ceil(math.abs(sweep) / (maxStep or MAX_TURN_STEP)))
	local points = {}
	for k = 0, steps do
		local angle = a0 + sweep * k / steps
		table.insert(points, Vector3.new(centre.X + radius * math.cos(angle), centre.Y, centre.Z + radius * math.sin(angle)))
	end
	return points
end

-- Surfaces ---------------------------------------------------------------------------------

type Style = { colour: Color3, material: Enum.Material, thickness: number, collide: boolean? }

local function wedge(size: Vector3, cframe: CFrame, style: Style): BasePart
	local part = TownKit.box(size, cframe, style.colour, style.material, "WedgePart")
	if style.collide == false then
		part.CanCollide = false
	end
	return part
end

-- A flat-topped slab in the shape of triangle a-b-c, made from two wedges. The top is exactly on the
-- triangle; the slab hangs `thickness` below it.
function RoadKit.triangle(a: Vector3, b: Vector3, c: Vector3, style: Style, made: { BasePart }?): { BasePart }
	local out = made or {}
	local ab, ac, bc = b - a, c - a, c - b
	local abd, acd, bcd = ab:Dot(ab), ac:Dot(ac), bc:Dot(bc)
	if abd > acd and abd > bcd then
		c, a = a, c
	elseif acd > bcd and acd > abd then
		a, b = b, a
	end
	ab, ac, bc = b - a, c - a, c - b
	local cross = ac:Cross(ab)
	if cross.Magnitude < 1e-4 or bc.Magnitude < 1e-3 then
		return out
	end
	local right = cross.Unit
	local up = bc:Cross(right).Unit
	local back = bc.Unit
	local height = math.abs(ab:Dot(up))
	if height < 0.01 then
		return out
	end
	local top = if right.Y >= 0 then right else -right
	local shift = -top * style.thickness / 2
	local length1 = math.abs(ab:Dot(back))
	local length2 = math.abs(ac:Dot(back))
	if length1 > 0.01 then
		table.insert(out, wedge(Vector3.new(style.thickness, height, length1), CFrame.fromMatrix((a + b) / 2 + shift, right, up, back), style))
	end
	if length2 > 0.01 then
		table.insert(out, wedge(Vector3.new(style.thickness, height, length2), CFrame.fromMatrix((a + c) / 2 + shift, -right, up, -back), style))
	end
	return out
end

-- A slab with corners p1, p2, p3, p4 in order round the edge. Rectangles are one part; anything else is
-- cut into two triangles.
function RoadKit.quad(p1: Vector3, p2: Vector3, p3: Vector3, p4: Vector3, style: Style, made: { BasePart }?): { BasePart }
	local out = made or {}
	local across, along = p2 - p1, p4 - p1
	local width, length = across.Magnitude, along.Magnitude
	if width > 0.01 and length > 0.01 then
		local square = math.abs(across.Unit:Dot(along.Unit)) < 0.002 and ((p1 + across + along) - p3).Magnitude < 0.02
		if square then
			local normal = across:Cross(along).Unit
			if normal.Y < 0 then
				normal = -normal
			end
			local centre = (p1 + p3) / 2 - normal * style.thickness / 2
			local part = TownKit.box(Vector3.new(width, style.thickness, length), CFrame.fromMatrix(centre, across.Unit, normal), style.colour, style.material)
			if style.collide == false then
				part.CanCollide = false
			end
			table.insert(out, part)
			return out
		end
	end
	RoadKit.triangle(p1, p2, p3, style, out)
	RoadKit.triangle(p1, p3, p4, style, out)
	return out
end

-- A strip between offsets `from` and `to` (left is positive) along points with their normals
function RoadKit.strip(points: { Vector3 }, normals: { Vector3 }, from: number, to: number, style: Style, lift: number?): { BasePart }
	local made = {}
	local up = Vector3.new(0, lift or 0, 0)
	for k = 2, #points do
		local r0 = points[k - 1] + normals[k - 1] * from + up
		local l0 = points[k - 1] + normals[k - 1] * to + up
		local r1 = points[k] + normals[k] * from + up
		local l1 = points[k] + normals[k] * to + up
		RoadKit.quad(r0, l0, l1, r1, style, made)
	end
	return made
end

-- A strip whose two edges are given point by point (they must have the same number of points)
function RoadKit.between(right: { Vector3 }, left: { Vector3 }, style: Style): { BasePart }
	local made = {}
	for k = 2, math.min(#right, #left) do
		RoadKit.quad(right[k - 1], left[k - 1], left[k], right[k], style, made)
	end
	return made
end

-- A fan of triangles from `centre` round the outline `ring` (closed)
function RoadKit.fan(centre: Vector3, ring: { Vector3 }, style: Style): { BasePart }
	local made = {}
	for k = 1, #ring do
		local a, b = ring[k], ring[k % #ring + 1]
		if (a - b).Magnitude > 0.02 then
			RoadKit.triangle(centre, a, b, style, made)
		end
	end
	return made
end

-- Resamples a line of points to exactly `count` points, evenly spaced along it
function RoadKit.resample(points: { Vector3 }, count: number): { Vector3 }
	local total = 0
	local lengths = { 0 }
	for k = 2, #points do
		total += (points[k] - points[k - 1]).Magnitude
		lengths[k] = total
	end
	local out = {}
	local k = 2
	for i = 0, count - 1 do
		local s = total * i / (count - 1)
		while k < #points and lengths[k] < s do
			k += 1
		end
		local span = lengths[k] - lengths[k - 1]
		local f = if span < 1e-9 then 0 else math.clamp((s - lengths[k - 1]) / span, 0, 1)
		out[i + 1] = points[k - 1]:Lerp(points[k], f)
	end
	return out
end

-- A wall along a line of points: from height `bottom` to `top` (absolute), `thickness` thick, centred on the line
function RoadKit.wall(points: { Vector3 }, bottom: number, top: number, thickness: number, colour: Color3, material: Enum.Material): { BasePart }
	local made: { BasePart } = {}
	for k = 2, #points do
		local a, b = points[k - 1], points[k]
		local along = Vector3.new(b.X - a.X, 0, b.Z - a.Z)
		local length = along.Magnitude
		if length > 0.05 then
			local middle = Vector3.new((a.X + b.X) / 2, (bottom + top) / 2, (a.Z + b.Z) / 2)
			local part = TownKit.box(Vector3.new(thickness, top - bottom, length + thickness * 0.5), CFrame.lookAt(middle, middle + along), colour, material)
			table.insert(made, part)
		end
	end
	return made
end

-- A wall that follows a sloping line: `height` tall above each point, hanging `below` under it
function RoadKit.parapet(points: { Vector3 }, height: number, below: number, thickness: number, colour: Color3, material: Enum.Material): { BasePart }
	local made: { BasePart } = {}
	for k = 2, #points do
		local a, b = points[k - 1], points[k]
		local along = b - a
		if along.Magnitude > 0.05 then
			local middle = (a + b) / 2 + Vector3.new(0, (height - below) / 2, 0)
			local part = TownKit.box(Vector3.new(thickness, height + below, along.Magnitude + thickness * 0.5), CFrame.lookAt(middle, middle + along), colour, material)
			table.insert(made, part)
		end
	end
	return made
end

-- Paint ------------------------------------------------------------------------------------

local PAINT_LIFT = 0.035 -- paint sits this far above the road so it never flickers

local function paintPiece(a: Vector3, b: Vector3, width: number, colour: Color3, extra: number?): BasePart?
	local along = b - a
	local length = along.Magnitude
	if length < 0.05 then
		return nil
	end
	local middle = (a + b) / 2 + Vector3.new(0, PAINT_LIFT, 0)
	local part = TownKit.detail(Vector3.new(width, 0.05, length + (extra or 0)), CFrame.lookAt(middle, middle + along), colour)
	part.CastShadow = false
	return part
end

-- A solid line `width` wide at `offset` along points (with normals)
function RoadKit.line(points: { Vector3 }, normals: { Vector3 }, offset: number, width: number, colour: Color3)
	for k = 2, #points do
		paintPiece(points[k - 1] + normals[k - 1] * offset, points[k] + normals[k] * offset, width, colour, 0.25)
	end
end

-- A dashed line along a path between s0 and s1: `dash` long, `gap` apart
function RoadKit.dashes(path: Path, s0: number, s1: number, offset: number, width: number, dash: number, gap: number, colour: Color3)
	local s = s0 + gap / 2
	while s + dash <= s1 do
		local a, _, na = RoadKit.at(path, s)
		local b, _, nb = RoadKit.at(path, s + dash)
		paintPiece(a + na * offset, b + nb * offset, width, colour)
		s += dash + gap
	end
end

-- A solid line along a path between s0 and s1
function RoadKit.pathLine(path: Path, s0: number, s1: number, offset: number, width: number, colour: Color3)
	local points, normals = RoadKit.slice(path, s0, s1)
	RoadKit.line(points, normals, offset, width, colour)
end

-- One flat painted rectangle centred on `at`, `along` long in direction `direction`
function RoadKit.mark(at: Vector3, direction: Vector3, width: number, along: number, colour: Color3): BasePart?
	return paintPiece(at - direction * along / 2, at + direction * along / 2, width, colour)
end

-- A painted triangle (give-way triangles, chevrons)
function RoadKit.paintTriangle(a: Vector3, b: Vector3, c: Vector3, colour: Color3)
	local lift = Vector3.new(0, PAINT_LIFT + 0.025, 0)
	local made = RoadKit.triangle(a + lift, b + lift, c + lift, { colour = colour, material = Enum.Material.SmoothPlastic, thickness = 0.05, collide = false })
	for _, part in made do
		part.CanQuery = false
		part.CastShadow = false
	end
end

return RoadKit
]])
put(folder4, "ModuleScript", "RoadNetwork", [[
-- Builds every road in the map from LondonLayout (which tools/london_layout.py writes):
--   * the tarmac, kerbs and pavements, following each road's curves
--   * junctions with rounded kerbs, give-way and stop lines, and traffic lights
--   * roundabouts with an island, and mini roundabouts with a painted dot
--   * lane lines for every kind of road, from side streets to the motorway
--   * bridges and flyovers: parapets, pillars and ramps wherever a road is above the ground
--   * slip roads that taper into the motorway, and laybys
-- LondonMap calls RoadNetwork.build once, then uses what it returns for buildings, props and the minimap.

local Workspace = game:GetService("Workspace")

local RoadKit = require(script.Parent.RoadKit)
local TownKit = require(script.Parent.TownKit)
local TownProps = require(script.Parent.TownProps)

type Path = RoadKit.Path

local C = TownKit.Colours
local ROAD_TOP = TownKit.ROAD_TOP
local KERB = TownKit.KERB_HEIGHT

local ROAD = { colour = C.Asphalt, material = Enum.Material.Asphalt, thickness = 2 }
local MOTORWAY_ROAD = { colour = Color3.fromRGB(90, 91, 94), material = Enum.Material.Asphalt, thickness = 2 }
local PAVEMENT = { colour = C.Pavement, material = Enum.Material.Pavement, thickness = KERB + 2 }
local RED_PAVEMENT = { colour = C.RedPaving, material = Enum.Material.Pavement, thickness = KERB + 2 }
local ISLAND = { colour = C.Grass, material = Enum.Material.Grass, thickness = KERB + 2 }
local CONCRETE = { colour = C.Concrete, material = Enum.Material.Concrete, thickness = KERB + 2 }
local PARAPET_COLOUR = Color3.fromRGB(178, 176, 170)
local PILLAR_COLOUR = Color3.fromRGB(150, 150, 146)

local MAX_TRIM = 150 -- a junction never cuts more than this off a road
local HAZARD_LENGTH = 45 -- long "warning" dashes on the centre line for this far before a junction

export type Profile = {
	lanes: number,
	lane: number,
	parking: number?, -- a strip along each kerb where cars park
	res: number,
	shoulder: number,
	edge: number,
	side: string,
	sideWidth: number,
	limit: number,
	rank: number,
	oneway: boolean?,
}

export type Node = {
	id: string,
	pos: Vector3, -- road surface height
	kind: string,
	radius: number,
	island: number,
	name: string,
	ends: { End },
	reach: number, -- how far the junction's tarmac spreads from its middle
}

export type Road = {
	id: string,
	name: string,
	kind: string,
	profile: Profile,
	a: Node,
	b: Node,
	path: Path,
	hw: number, -- half the width of the tarmac
	sideWidth: number,
	side: string,
	limit: number,
	startTrim: number,
	endTrim: number,
	sideFrom: { [number]: number }, -- [1] left, [-1] right: where the pavement starts and stops
	sideTo: { [number]: number },
	gaps: { { number } },
	laybys: { { number } },
	taper: string?,
	taperFrom: Vector3?,
	raised: { { number } }, -- stretches above the ground (bridges, flyovers, ramps)
}

export type End = {
	road: Road,
	node: Node,
	atStart: boolean,
	sign: number, -- 1 at the start of the road, -1 at the end
	dir: Vector3, -- flat, pointing away from the junction along the road
	left: Vector3, -- flat, to the left looking along dir
	angle: number,
	hw: number,
	trim: number,
	leftTrim: number,
	rightTrim: number,
	major: boolean,
	axis: string?,
}

export type Result = {
	roads: { Road },
	nodes: { Node },
	byId: { [string]: Road },
	minimap: { { any } },
}

local RoadNetwork = {}

local function halfWidth(p: Profile): number
	if p.oneway then
		return p.lanes * p.lane / 2 + p.edge
	end
	return p.res / 2 + p.lanes * p.lane + (p.parking or 0) + p.shoulder + p.edge
end

-- Where along the road a point `distance` from this end is
local function stationFor(e: End, distance: number): number
	return if e.atStart then distance else e.road.path.length - distance
end

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

-- Where the line p + d*s meets the line q + e*u (flat)
local function intersect(p: Vector3, d: Vector3, q: Vector3, e: Vector3): (number?, number?)
	local den = d.X * e.Z - d.Z * e.X
	if math.abs(den) < 1e-6 then
		return nil, nil
	end
	local dx, dz = q.X - p.X, q.Z - p.Z
	return (dx * e.Z - dz * e.X) / den, (dx * d.Z - dz * d.X) / den
end

-- Points round a circle from one point to another, the short way
local function shortArc(centre: Vector3, from: Vector3, to: Vector3, y: number): { Vector3 }
	local a0 = math.atan2(from.Z - centre.Z, from.X - centre.X)
	local a1 = math.atan2(to.Z - centre.Z, to.X - centre.X)
	local sweep = a1 - a0
	while sweep > math.pi do
		sweep -= 2 * math.pi
	end
	while sweep < -math.pi do
		sweep += 2 * math.pi
	end
	local radius = (Vector3.new(from.X, 0, from.Z) - Vector3.new(centre.X, 0, centre.Z)).Magnitude
	return RoadKit.arc(Vector3.new(centre.X, y, centre.Z), radius, a0, a0 + sweep)
end

local function setLimit(parts: { BasePart }, limit: number)
	for _, part in parts do
		part:SetAttribute("SpeedLimit", limit)
	end
end

local function cylinder(radius: number, thickness: number, top: Vector3, colour: Color3, material: Enum.Material): Part
	local part = TownKit.box(Vector3.new(thickness, radius * 2, radius * 2), CFrame.new(top - Vector3.new(0, thickness / 2, 0)) * CFrame.Angles(0, 0, math.pi / 2), colour, material)
	part.Shape = Enum.PartType.Cylinder
	return part
end

-- Kerb radius at a corner between two roads
local function cornerRadius(a: End, b: End): number
	local rank = math.max(a.road.profile.rank, b.road.profile.rank)
	local base = if rank >= 3 then 24 else 16
	local pave = math.max(if a.road.side == "pavement" then a.road.sideWidth else 0, if b.road.side == "pavement" then b.road.sideWidth else 0)
	return math.max(base, pave + 3)
end

-- Junctions ----------------------------------------------------------------------------------

type Corner = {
	a: End,
	b: End,
	straight: boolean,
	centre: Vector3?,
	radius: number,
	ta: Vector3?,
	tb: Vector3?,
	sharp: boolean?,
}

local function solveJunction(node: Node): { Corner }
	local ends = node.ends
	local corners: { Corner } = {}
	for _, e in ends do
		e.trim, e.leftTrim, e.rightTrim = 2, 0, 0
	end
	if #ends < 2 then
		return corners
	end
	local origin = flat(node.pos)
	for i, a in ends do
		local b = ends[i % #ends + 1]
		local delta = (b.angle - a.angle) % (2 * math.pi)
		if #ends == 2 and i == 2 then
			delta = (2 * math.pi) - ((ends[2].angle - ends[1].angle) % (2 * math.pi))
		end
		local corner: Corner = { a = a, b = b, straight = true, radius = 0 }
		if delta < math.rad(170) and delta > 1e-3 then
			local radius = cornerRadius(a, b)
			for _ = 1, 6 do
				local pa = origin + a.left * (a.hw + radius)
				local pb = origin - b.left * (b.hw + radius)
				local s, u = intersect(pa, a.dir, pb, b.dir)
				if s and u and s >= 0 and u >= 0 and s < MAX_TRIM and u < MAX_TRIM then
					corner.straight = false
					corner.radius = radius
					corner.centre = pa + a.dir * s
					corner.ta = origin + a.dir * s + a.left * a.hw
					corner.tb = origin + b.dir * u - b.left * b.hw
					a.leftTrim = math.max(a.leftTrim, s)
					b.rightTrim = math.max(b.rightTrim, u)
					break
				end
				radius *= 0.6
				if radius < 3 then
					break
				end
			end
			if corner.straight then
				-- A sharp corner where the two kerbs meet
				local s, u = intersect(origin + a.left * a.hw, a.dir, origin - b.left * b.hw, b.dir)
				if s and u and s >= 0 and u >= 0 and s < MAX_TRIM * 2 and u < MAX_TRIM * 2 then
					corner.straight = false
					corner.sharp = true
					corner.ta = origin + a.dir * s + a.left * a.hw
					corner.tb = corner.ta
					a.leftTrim = math.max(a.leftTrim, s)
					b.rightTrim = math.max(b.rightTrim, u)
				end
			end
		end
		table.insert(corners, corner)
	end
	for _, e in ends do
		e.trim = math.max(e.trim, e.leftTrim, e.rightTrim) + 1
	end
	return corners
end

-- The edges of a road's tarmac at `distance` from this end: (right, left) looking away from the junction
local function endEdges(e: End, distance: number): (Vector3, Vector3)
	local p, _, n = RoadKit.at(e.road.path, stationFor(e, distance))
	local left = n * e.sign
	return p - left * e.hw, p + left * e.hw
end

local function buildJunctionSurface(node: Node, corners: { Corner })
	local ring: { Vector3 } = {}
	local y = node.pos.Y
	for i, a in node.ends do
		local right, left = endEdges(a, a.trim)
		table.insert(ring, right)
		table.insert(ring, left)
		local corner = corners[i]
		if corner and not corner.straight then
			local b = corner.b
			local ta = Vector3.new((corner.ta :: Vector3).X, y, (corner.ta :: Vector3).Z)
			local tb = Vector3.new((corner.tb :: Vector3).X, y, (corner.tb :: Vector3).Z)
			if a.leftTrim < a.trim - 0.05 then
				table.insert(ring, ta)
			end
			if not corner.sharp then
				local arc = shortArc(corner.centre :: Vector3, ta, tb, y)
				for k = 2, #arc - 1 do
					table.insert(ring, arc[k])
				end
			end
			if b.rightTrim < b.trim - 0.05 then
				table.insert(ring, tb)
			end
		end
	end
	local limit = 0
	for _, e in node.ends do
		limit = math.max(limit, e.road.limit)
	end
	setLimit(RoadKit.fan(node.pos, ring, ROAD), limit)
	local reach = 0
	for _, p in ring do
		reach = math.max(reach, (flat(p) - flat(node.pos)).Magnitude)
	end
	node.reach = reach
end

-- Pavement round each rounded corner, joining the pavements of the two roads
local function buildCornerPavements(node: Node, corners: { Corner })
	if node.pos.Y > 1 + ROAD_TOP then
		return
	end
	for _, corner in corners do
		if corner.straight or corner.sharp then
			continue
		end
		local a, b = corner.a, corner.b
		local widthA = if a.road.side == "pavement" then a.road.sideWidth else 0
		local widthB = if b.road.side == "pavement" then b.road.sideWidth else 0
		local width = math.min(math.max(widthA, widthB), corner.radius - 1)
		if width <= 0 then
			continue
		end
		local y = node.pos.Y
		local ta, tb = corner.ta :: Vector3, corner.tb :: Vector3
		local points = shortArc(corner.centre :: Vector3, Vector3.new(ta.X, y, ta.Z), Vector3.new(tb.X, y, tb.Z), y)
		RoadKit.strip(points, RoadKit.normalsFor(points), -width, 0, PAVEMENT, KERB)
	end
end

-- Roundabouts --------------------------------------------------------------------------------

type Fillet = { centre: Vector3, onRoad: Vector3, onCircle: Vector3 }
type RoundaboutEnd = { e: End, left: Fillet, right: Fillet }

local function solveRoundabout(node: Node): { RoundaboutEnd }
	local origin = node.pos
	local outer = node.radius
	local out: { RoundaboutEnd } = {}
	for _, e in node.ends do
		local width = if e.road.side == "pavement" then e.road.sideWidth else 0
		local radius = math.max(18, width + 3)
		local hw = math.min(e.hw, outer - 4)
		local along = math.sqrt(math.max(0, (outer + radius) ^ 2 - (hw + radius) ^ 2))
		local function fillet(side: number): Fillet
			local centre = origin + e.dir * along + e.left * side * (hw + radius)
			local onRoad = origin + e.dir * along + e.left * side * hw
			local onCircle = origin + flat(centre - origin).Unit * outer
			return { centre = centre, onRoad = onRoad, onCircle = onCircle }
		end
		e.trim = along + 1
		e.leftTrim, e.rightTrim = along, along
		table.insert(out, { e = e, left = fillet(1), right = fillet(-1) })
	end
	return out
end

local function buildRoundabout(node: Node, ends: { RoundaboutEnd })
	local y = node.pos.Y
	local limit = 0
	for _, info in ends do
		limit = math.max(limit, info.e.road.limit)
	end
	-- The circle of tarmac, a touch lower than the roads so the two never flicker
	local disc = cylinder(node.radius, 2, node.pos - Vector3.new(0, 0.05, 0), C.Asphalt, Enum.Material.Asphalt)
	disc:SetAttribute("SpeedLimit", limit)
	-- The island: a kerb ring, filled with real grass (Terrain), which looks better than a grassy part
	cylinder(node.island + 0.6, KERB + 1.5, node.pos + Vector3.new(0, KERB - 0.1, 0), C.Kerb, Enum.Material.Concrete)
	-- A low grassy mound that rises a little above the kerb. Terrain needs at least 4 studs of height to
	-- fill anything, so most of this sits hidden below the road.
	Workspace.Terrain:FillCylinder(CFrame.new(node.pos + Vector3.new(0, KERB - 2.1, 0)), 6, node.island - 0.4, Enum.Material.Grass)
	-- On stilts if it's above the ground (motorway junctions)
	if y > 1 + ROAD_TOP then
		cylinder(node.radius - 1, y - 2, node.pos - Vector3.new(0, 2, 0), PILLAR_COLOUR, Enum.Material.Concrete)
	end

	-- Where each road opens out into the circle
	for _, info in ends do
		local e = info.e
		local right, left = endEdges(e, e.trim)
		local leftChain = { left, Vector3.new(info.left.onRoad.X, y, info.left.onRoad.Z) }
		for _, p in shortArc(info.left.centre, info.left.onRoad, info.left.onCircle, y) do
			table.insert(leftChain, p)
		end
		local rightChain = { right, Vector3.new(info.right.onRoad.X, y, info.right.onRoad.Z) }
		for _, p in shortArc(info.right.centre, info.right.onRoad, info.right.onCircle, y) do
			table.insert(rightChain, p)
		end
		local count = math.max(#leftChain, #rightChain, 6)
		setLimit(RoadKit.between(RoadKit.resample(rightChain, count), RoadKit.resample(leftChain, count), ROAD), limit)
	end

	-- Kerb, pavement (or a parapet on stilts) round the outside, between each pair of roads
	table.sort(ends, function(p, q)
		return p.e.angle < q.e.angle
	end)
	local raised = y > 1 + ROAD_TOP
	for i, info in ends do
		local nextInfo = ends[i % #ends + 1]
		local a, b = info.e, nextInfo.e
		local width = math.max(if a.road.side == "pavement" then a.road.sideWidth else 0, if b.road.side == "pavement" then b.road.sideWidth else 0)
		local points: { Vector3 } = {}
		for _, p in shortArc(info.left.centre, info.left.onRoad, info.left.onCircle, y) do
			table.insert(points, p)
		end
		-- Round the circle the way that doesn't cross either road (clockwise on the map)
		local from = math.atan2(info.left.onCircle.Z - node.pos.Z, info.left.onCircle.X - node.pos.X)
		local to = math.atan2(nextInfo.right.onCircle.Z - node.pos.Z, nextInfo.right.onCircle.X - node.pos.X)
		local sweep = (from - to) % (2 * math.pi)
		if #ends == 1 then
			sweep = 2 * math.pi - 0.01
		else
			-- When two roads come in close together their kerb curves overlap, and the pavement would go the
			-- long way round, straight across every other road's entrance. Leave it out instead.
			local gap = (math.atan2(a.dir.Z, a.dir.X) - math.atan2(b.dir.Z, b.dir.X)) % (2 * math.pi)
			if sweep > gap + 0.3 then
				continue
			end
		end
		local circle = RoadKit.arc(Vector3.new(node.pos.X, y, node.pos.Z), node.radius, from, from - sweep)
		for k = 2, #circle - 1 do
			table.insert(points, circle[k])
		end
		for _, p in shortArc(nextInfo.right.centre, nextInfo.right.onCircle, nextInfo.right.onRoad, y) do
			table.insert(points, p)
		end
		local normals = RoadKit.normalsFor(points)
		if raised then
			RoadKit.parapet(RoadKit.offset(points, normals, -0.6), 3, 2, 1.2, PARAPET_COLOUR, Enum.Material.Concrete)
		elseif width > 0 then
			RoadKit.strip(points, normals, -math.min(width, 17), 0, PAVEMENT, KERB)
		end
	end

	-- Lane line round the middle of big roundabouts
	local ring = node.radius - node.island
	if ring >= 24 then
		local middle = node.island + ring / 2
		local count = math.floor(2 * math.pi * middle / 14)
		for k = 0, count - 1 do
			local angle = k / count * 2 * math.pi
			local at = node.pos + Vector3.new(math.cos(angle) * middle, 0, math.sin(angle) * middle)
			RoadKit.mark(at, Vector3.new(-math.sin(angle), 0, math.cos(angle)), 0.45, 6, C.White)
		end
	end
	node.reach = node.radius + 4
end

-- Markings at the end of a road -------------------------------------------------------------

-- Which offsets (left is positive) carry traffic towards this end of the road
local function incomingSpan(e: End): (number?, number?)
	local road = e.road
	local p = road.profile
	if p.oneway then
		if e.atStart then
			return nil, nil -- one-way roads only arrive at their far end
		end
		return -road.hw + p.edge, road.hw - p.edge
	end
	local inner = p.res / 2
	local outer = road.hw - p.edge - p.shoulder
	-- Traffic heading towards this end drives on its left, which is the road's right at the start
	if e.atStart then
		return -outer, -inner
	end
	return inner, outer
end

local function acrossLine(e: End, distance: number, from: number, to: number, dashed: boolean, thick: number)
	local p, _, n = RoadKit.at(e.road.path, stationFor(e, distance))
	if dashed then
		local o = from + 1.3
		while o + 0.8 <= to do
			RoadKit.mark(p + n * o, n, 0.5 * thick, 1.6, C.White)
			o += 2.6
		end
	else
		RoadKit.mark(p + n * ((from + to) / 2), n, 0.7 * thick, to - from - 0.6, C.White)
	end
end

local function giveWay(e: End, distance: number)
	local from, to = incomingSpan(e)
	if not from or not to then
		return
	end
	acrossLine(e, distance + 0.6, from, to, true, 1)
	acrossLine(e, distance + 1.8, from, to, true, 1)
	-- The upside-down triangle warning drivers before the line
	if e.road.profile.rank <= 2 and e.road.path.length > e.trim + 60 then
		local p, _, n = RoadKit.at(e.road.path, stationFor(e, distance + 22))
		local middle = (from + to) / 2
		local towards = flat(e.dir) * -1 -- the direction traffic is going
		local tip = p + n * middle + towards * 5
		local baseCentre = p + n * middle - towards * 9
		RoadKit.paintTriangle(tip, baseCentre + n * 3.2, baseCentre - n * 3.2, C.White)
	end
end

local function stopLine(e: End, distance: number)
	local from, to = incomingSpan(e)
	if not from or not to then
		return
	end
	acrossLine(e, distance + 1, from, to, false, 1)
end

-- Picks the main road through a junction: the two roads that line up best, biggest first
local function markMajor(node: Node)
	local best, bestScore = nil, -math.huge
	for i = 1, #node.ends do
		for j = i + 1, #node.ends do
			local a, b = node.ends[i], node.ends[j]
			local straightness = -a.dir:Dot(b.dir)
			local score = straightness + (a.road.profile.rank + b.road.profile.rank) * 0.3
			if straightness > 0.5 and score > bestScore then
				best, bestScore = { a, b }, score
			end
		end
	end
	if best then
		best[1].major = true
		best[2].major = true
	end
end

-- A spot on the pavement or verge to the left of the traffic coming in at this end, `distance` from the junction,
-- facing that traffic (where give way signs and traffic lights stand)
local function roadsideSpot(e: End, distance: number, extra: number?): (Vector3, Vector3)
	local p, _, n = RoadKit.at(e.road.path, stationFor(e, distance))
	local side = if e.atStart then -1 else 1
	local base = p + n * side * (e.hw + (extra or 1.6))
	return Vector3.new(base.X, base.Y + KERB, base.Z), e.dir
end

-- White arrows in the lanes coming up to a set of traffic lights
local function laneArrows(e: End)
	local from, to = incomingSpan(e)
	if not from or not to or e.road.path.length < e.trim + 60 then
		return
	end
	local p = e.road.profile
	local lanes = p.lanes
	-- The arrow sits in the moving lanes, not in the parking strip along the kerb
	local inner = math.min(math.abs(from), math.abs(to))
	local sign = if from < 0 then -1 else 1
	for lane = 1, lanes do
		local offset = sign * (inner + p.lane * (lane - 0.5))
		local at, _, n = RoadKit.at(e.road.path, stationFor(e, e.trim + 22))
		TownProps.laneArrow(at + n * offset, -e.dir)
	end
end

local function trafficLights(node: Node)
	-- Opposite roads change together
	local ends = node.ends
	local paired: { [End]: boolean } = {}
	local axes = { "NS", "EW" }
	local which = 1
	for _, a in ends do
		if paired[a] then
			continue
		end
		local partner, best = nil, 0.5
		for _, b in ends do
			if b ~= a and not paired[b] and -a.dir:Dot(b.dir) > best then
				partner, best = b, -a.dir:Dot(b.dir)
			end
		end
		a.axis = axes[which]
		paired[a] = true
		if partner then
			partner.axis = axes[which]
			paired[partner] = true
		end
		which = which % 2 + 1
	end
	for _, e in ends do
		local from, to = incomingSpan(e)
		if not from or not to then
			continue
		end
		local p, _, n = RoadKit.at(e.road.path, stationFor(e, e.trim + 3))
		-- On the pavement to the left of the traffic coming in
		local side = if e.atStart then -1 else 1
		local base = p + n * side * (e.hw + 1.6)
		TownProps.trafficLight(TownKit.facing(Vector3.new(base.X, base.Y - ROAD_TOP, base.Z), e.dir), node.id, e.axis or "NS")
	end
end

-- Roads -------------------------------------------------------------------------------------

-- Splits [s0, s1] into the pieces on one side that aren't in a gap
local function sidePieces(road: Road, side: number, s0: number, s1: number): { { number } }
	local cuts = { { s0, s1 } }
	local function cut(c0: number, c1: number)
		local out = {}
		for _, piece in cuts do
			if c1 <= piece[1] or c0 >= piece[2] then
				table.insert(out, piece)
			else
				if c0 > piece[1] then
					table.insert(out, { piece[1], c0 })
				end
				if c1 < piece[2] then
					table.insert(out, { c1, piece[2] })
				end
			end
		end
		cuts = out
	end
	for _, gap in road.gaps do
		if gap[1] == side then
			cut(gap[2], gap[3])
		end
	end
	for _, layby in road.laybys do
		if layby[1] == side then
			cut(layby[2], layby[3])
		end
	end
	return cuts
end

local function centreLines(road: Road, s0: number, s1: number)
	local p = road.profile
	local path = road.path
	if p.oneway then
		local inside = road.hw - p.edge - 0.6
		RoadKit.pathLine(path, s0, s1, inside, 0.45, C.White)
		RoadKit.pathLine(path, s0, s1, -inside, 0.45, C.White)
		return
	end
	if p.res == 0 then
		local dash, gap = 6, 6
		if road.kind == "street" or road.kind == "lane" or road.kind == "back" then
			dash, gap = 3, 9
		elseif road.kind == "high" then
			dash, gap = 4, 7
		end
		-- Long warning dashes just before junctions
		local hazardStart = if road.a.kind == "attach" or road.a.kind == "end" or road.a.kind == "join" then s0 else s0 + HAZARD_LENGTH
		local hazardEnd = if road.b.kind == "attach" or road.b.kind == "end" or road.b.kind == "join" then s1 else s1 - HAZARD_LENGTH
		if hazardEnd - hazardStart > 30 then
			RoadKit.dashes(path, s0, hazardStart, 0, 0.5, 6, 2, C.White)
			RoadKit.dashes(path, hazardStart, hazardEnd, 0, 0.5, dash, gap, C.White)
			RoadKit.dashes(path, hazardEnd, s1, 0, 0.5, 6, 2, C.White)
		else
			RoadKit.dashes(path, s0, s1, 0, 0.5, 6, 2, C.White)
		end
		if p.edge > 0 then
			for _, side in { 1, -1 } do
				for _, piece in sidePieces(road, side, s0, s1) do
					RoadKit.pathLine(path, piece[1], piece[2], side * (road.hw - p.edge - 0.4), 0.4, C.White)
				end
			end
		end
		-- Double yellow lines (no parking) along the kerbs near each junction. The parking strips themselves
		-- aren't marked, like in BVS, which keeps the streets clean (and saves thousands of parts).
		local parking = p.parking or 0
		if parking > 0 then
			local near = math.min(55, (s1 - s0) / 2)
			for _, range in { { s0, s0 + near }, { s1 - near, s1 } } do
				for _, side in { 1, -1 } do
					for _, inset in { 0.9, 1.6 } do
						RoadKit.pathLine(path, range[1], range[2], side * (road.hw - inset), 0.32, C.Yellow)
					end
				end
			end
		end
		return
	end
	-- Dual carriageways and the motorway: each side has its own lanes
	for _, side in { 1, -1 } do
		local inner = p.res / 2
		RoadKit.pathLine(path, s0, s1, side * (inner + 0.6), 0.45, C.White)
		for k = 1, p.lanes - 1 do
			RoadKit.dashes(path, s0, s1, side * (inner + p.lane * k), 0.45, 9, 14, C.White)
		end
		local laneEdge = inner + p.lanes * p.lane
		local width = if p.shoulder > 0 then 0.8 else 0.45
		local offset = if p.shoulder > 0 then laneEdge else road.hw - p.edge - 0.5
		-- Solid along the edge, broken where slip roads join or a layby opens
		local covered = s0
		for _, piece in sidePieces(road, side, s0, s1) do
			if piece[1] > covered + 1 then
				RoadKit.dashes(path, covered, piece[1], side * offset, width, 6, 6, C.White)
			end
			RoadKit.pathLine(path, piece[1], piece[2], side * offset, width, C.White)
			covered = piece[2]
		end
		if s1 > covered + 1 then
			RoadKit.dashes(path, covered, s1, side * offset, width, 6, 6, C.White)
		end
	end
end

local function buildLayby(road: Road, layby: { number })
	local side, s0, s1 = layby[1], layby[2], layby[3]
	local depth, taper = 11, 30
	local inner, outer = {}, {}
	local s = s0
	while true do
		local p, _, n = RoadKit.at(road.path, s)
		local into = depth
		if s < s0 + taper then
			into = depth * (s - s0) / taper
		elseif s > s1 - taper then
			into = depth * (s1 - s) / taper
		end
		table.insert(inner, p + n * side * road.hw)
		table.insert(outer, p + n * side * (road.hw + math.max(into, 0.05)))
		if s >= s1 then
			break
		end
		s = math.min(s + 10, s1)
	end
	if side > 0 then
		setLimit(RoadKit.between(inner, outer, ROAD), road.limit)
	else
		setLimit(RoadKit.between(outer, inner, ROAD), road.limit)
	end
	-- A blue "P" sign in the middle
	local p, direction, n = RoadKit.at(road.path, (s0 + s1) / 2)
	local post = p + n * side * (road.hw + depth + 3)
	TownKit.post(0.3, 7, Vector3.new(post.X, post.Y - ROAD_TOP, post.Z), C.LampGrey, Enum.Material.Metal)
	local facing = if side > 0 then -direction else direction
	local sign = TownKit.detail(Vector3.new(2.4, 2.4, 0.15), TownKit.facing(post + Vector3.new(0, 7, 0), facing), Color3.fromRGB(20, 70, 160))
	TownKit.text(sign, Enum.NormalId.Front, "P", Color3.new(1, 1, 1))
end

local function groundBelow(ground: (number, number) -> number, p: Vector3): number
	return ground(p.X, p.Z)
end

local function buildRaised(road: Road, ground: (number, number) -> number, isRoad: (number, number) -> boolean)
	local path = road.path
	local s0, s1 = road.startTrim, path.length - road.endTrim
	if s1 - s0 < 1 then
		return
	end
	-- Find the stretches above the ground
	local raised: { { number } } = {}
	local currentStretch: { number }? = nil
	local s = s0
	while s <= s1 do
		local p, _, n = RoadKit.at(path, s)
		local height = p.Y - ROAD_TOP
		local above = math.max(
			height - groundBelow(ground, p),
			height - groundBelow(ground, p + n * road.hw),
			height - groundBelow(ground, p - n * road.hw)
		)
		if above > 1.2 then
			local stretch = currentStretch or { math.max(s0, s - 8), s }
			if not currentStretch then
				table.insert(raised, stretch)
				currentStretch = stretch
			end
			stretch[2] = math.min(s1, s + 8)
		else
			currentStretch = nil
		end
		if s >= s1 then
			break
		end
		s = math.min(s + 8, s1)
	end
	road.raised = raised

	local outer = road.hw + (if road.side == "pavement" then road.sideWidth else 0)
	local walkLift = if road.side == "pavement" then KERB else 0
	for _, stretch in raised do
		local points, normals = RoadKit.slice(path, stretch[1], stretch[2])
		for _, side in { 1, -1 } do
			-- Parapet walls along both edges
			local edge = RoadKit.offset(points, normals, side * (outer + 0.6), walkLift)
			RoadKit.parapet(edge, 3, 2.5 + walkLift, 1.2, PARAPET_COLOUR, Enum.Material.Concrete)
		end
		-- Pillars, or solid walls where the road is only a little way up
		local spacing = 60
		local distance = stretch[1] + 10
		while distance < stretch[2] - 5 do
			local p, direction, n = RoadKit.at(path, distance)
			local bottom = p.Y - 2
			local groundY = groundBelow(ground, p)
			local inWater = groundY < -5
			if bottom - groundY > 6 then
				local positions: { number } = if road.hw > 22 then { -road.hw * 0.55, road.hw * 0.55 } else { 0 }
				for _, offset in positions do
					local at = p + n * offset
					if inWater or not isRoad(at.X, at.Z) then
						local height = bottom - groundY
						local colour = if inWater then C.Stone else PILLAR_COLOUR
						local material = if inWater then Enum.Material.Limestone else Enum.Material.Concrete
						local size = if inWater then Vector3.new(road.hw * 2 + 6, height, 10) else Vector3.new(5, height, 7)
						if inWater and offset ~= positions[1] then
							continue
						end
						local centre = if inWater then p else at
						TownKit.box(size, CFrame.lookAt(Vector3.new(centre.X, groundY + height / 2, centre.Z), Vector3.new(centre.X, groundY + height / 2, centre.Z) + direction), colour, material)
					end
				end
				distance += if inWater then 80 else spacing
			else
				distance += 8
			end
		end
		-- Low stretches (ramps) get side walls down to the ground instead of pillars
		for _, side in { 1, -1 } do
			local edge = RoadKit.offset(points, normals, side * (outer + 0.6), 0)
			for k = 2, #edge do
				local a, b = edge[k - 1], edge[k]
				local middle = (a + b) / 2
				local groundY = groundBelow(ground, middle)
				local drop = middle.Y - 2.5 - groundY
				if drop > 0.2 and drop < 7 and groundY > -5 then
					RoadKit.parapet({ a - Vector3.new(0, 2.5, 0), b - Vector3.new(0, 2.5, 0) }, 0, drop + 0.5, 1.4, PARAPET_COLOUR, Enum.Material.Concrete)
				end
			end
		end
	end
end

local function buildRoad(road: Road)
	local path = road.path
	local p = road.profile
	local s0, s1 = road.startTrim, path.length - road.endTrim
	if s1 - s0 < 0.5 then
		return
	end
	local points, normals = RoadKit.slice(path, s0, s1)
	local style = if road.kind == "motorway" then MOTORWAY_ROAD else ROAD
	setLimit(RoadKit.strip(points, normals, -road.hw, road.hw, style), road.limit)

	-- Central reservation: grass between kerbs on dual carriageways, a concrete barrier on the motorway
	if p.res > 0 and not p.oneway and s1 - s0 > 16 then
		local nose = 8
		local resPoints, resNormals = RoadKit.slice(path, s0 + nose, s1 - nose)
		if road.kind == "motorway" or road.kind == "westway" then
			RoadKit.strip(resPoints, resNormals, -p.res / 2, p.res / 2, CONCRETE, 0.25)
			RoadKit.parapet(resPoints, 2.6, 0, 1.2, PARAPET_COLOUR, Enum.Material.Concrete)
		else
			RoadKit.strip(resPoints, resNormals, -p.res / 2 + 0.4, p.res / 2 - 0.4, ISLAND, KERB)
			RoadKit.strip(resPoints, resNormals, -p.res / 2, -p.res / 2 + 0.4, CONCRETE, KERB - 0.05)
			RoadKit.strip(resPoints, resNormals, p.res / 2 - 0.4, p.res / 2, CONCRETE, KERB - 0.05)
			-- Keep-left bollards on both ends of the island, facing the traffic coming at them
			if road.a.kind ~= "attach" then
				local at, direction = RoadKit.at(path, s0 + nose + 1.5)
				TownProps.keepLeft(at + Vector3.new(0, KERB, 0), -direction)
			end
			if road.b.kind ~= "attach" then
				local at, direction = RoadKit.at(path, s1 - nose - 1.5)
				TownProps.keepLeft(at + Vector3.new(0, KERB, 0), direction)
			end
		end
	end

	-- Pavements
	if road.side == "pavement" then
		for _, side in { 1, -1 } do
			local from, to = road.sideFrom[side], road.sideTo[side]
			for _, piece in sidePieces(road, side, from, to) do
				local sidePoints, sideNormals = RoadKit.slice(path, piece[1], piece[2])
				local walkStyle = if road.kind == "high" then RED_PAVEMENT else PAVEMENT
				if side > 0 then
					RoadKit.strip(sidePoints, sideNormals, road.hw, road.hw + road.sideWidth, walkStyle, KERB)
				else
					RoadKit.strip(sidePoints, sideNormals, -road.hw - road.sideWidth, -road.hw, walkStyle, KERB)
				end
			end
		end
	end

	centreLines(road, s0, s1)
	for _, layby in road.laybys do
		buildLayby(road, layby)
	end

	-- Slip roads: a tapering wedge of tarmac where they leave or join the motorway
	if road.taper and road.taperFrom then
		local atStart = road.taper == "start"
		local q, _, n = RoadKit.at(path, if atStart then 0 else path.length)
		local from = Vector3.new((road.taperFrom :: Vector3).X, q.Y, (road.taperFrom :: Vector3).Z)
		setLimit(RoadKit.triangle(from, q - n * road.hw, q + n * road.hw, ROAD), road.limit)
	end
end

-- Building it all -----------------------------------------------------------------------------

local function minimapKind(kind: string): string
	if kind == "motorway" then
		return "motorway"
	elseif kind == "dual" or kind == "arterial" or kind == "westway" or kind == "slip" then
		return "dual"
	elseif kind == "street" or kind == "lane" or kind == "back" then
		return "side"
	end
	return "main"
end

-- `ground(x, z)` gives the height of the ground; `isRoad(x, z)` says whether a spot is already road
-- (LondonMap fills that in once the roads are down, so pillars don't stand in the middle of a road below).
function RoadNetwork.build(layout: any, ground: (number, number) -> number, isRoad: (number, number) -> boolean, onRoadsDown: ((Result) -> ())?): Result
	local profiles: { [string]: Profile } = layout.profiles
	local nodesById: { [string]: Node } = {}
	local nodes: { Node } = {}
	for _, info in layout.nodes do
		local node: Node = {
			id = info.id,
			pos = Vector3.new(info.x, (info.y or 0) + ROAD_TOP, info.z),
			kind = info.kind,
			radius = info.radius or 0,
			island = info.island or 0,
			name = info.name or "",
			ends = {},
			reach = 0,
		}
		nodesById[node.id] = node
		table.insert(nodes, node)
	end

	local roads: { Road } = {}
	local byId: { [string]: Road } = {}
	for _, info in layout.roads do
		local a, b = nodesById[info.a], nodesById[info.b]
		local controls = { a.pos }
		local lastY = a.pos.Y
		for _, v in info.via or {} do
			local y = if v[3] then v[3] + ROAD_TOP else lastY
			table.insert(controls, Vector3.new(v[1], y, v[2]))
			lastY = y
		end
		table.insert(controls, b.pos)
		local profile = profiles[info.profile]
		local hw = halfWidth(profile)
		local road: Road = {
			id = info.id,
			name = info.name or "",
			kind = info.profile,
			profile = profile,
			a = a,
			b = b,
			path = RoadKit.path(controls, info.radius),
			hw = hw,
			sideWidth = profile.sideWidth,
			side = profile.side,
			limit = profile.limit,
			startTrim = 0,
			endTrim = 0,
			sideFrom = {},
			sideTo = {},
			gaps = info.gaps or {},
			laybys = info.laybys or {},
			taper = info.taper,
			taperFrom = if info.taperFrom then Vector3.new(info.taperFrom[1], 0, info.taperFrom[2]) else nil,
			raised = {},
		}
		table.insert(roads, road)
		byId[road.id] = road
		for _, atStart in { true, false } do
			local node = if atStart then a else b
			local _, direction = RoadKit.at(road.path, if atStart then 0 else road.path.length)
			local dir = if atStart then direction else -direction
			local e: End = {
				road = road,
				node = node,
				atStart = atStart,
				sign = if atStart then 1 else -1,
				dir = dir,
				left = RoadKit.leftOf(dir),
				angle = math.atan2(-dir.X, -dir.Z),
				hw = hw,
				trim = 0,
				leftTrim = 0,
				rightTrim = 0,
				major = false,
			}
			table.insert(node.ends, e)
		end
	end

	-- Work out every junction first: how much each road loses at each end
	local cornersByNode: { [Node]: { Corner } } = {}
	local roundaboutsByNode: { [Node]: { RoundaboutEnd } } = {}
	for _, node in nodes do
		table.sort(node.ends, function(p, q)
			return p.angle < q.angle
		end)
		if node.kind == "roundabout" then
			roundaboutsByNode[node] = solveRoundabout(node)
		elseif node.kind == "attach" or node.kind == "end" then
			for _, e in node.ends do
				e.trim, e.leftTrim, e.rightTrim = 0, 0, 0
			end
		else
			cornersByNode[node] = solveJunction(node)
		end
	end
	for _, node in nodes do
		for _, e in node.ends do
			local road = e.road
			-- Pavements stop where the kerb starts to curve: the road's left at its start is the end's left
			local leftSide = if e.atStart then 1 else -1
			if e.atStart then
				road.startTrim = e.trim
				road.sideFrom[leftSide] = e.leftTrim
				road.sideFrom[-leftSide] = e.rightTrim
			else
				road.endTrim = e.trim
				road.sideTo[leftSide] = road.path.length - e.leftTrim
				road.sideTo[-leftSide] = road.path.length - e.rightTrim
			end
		end
	end

	-- Roads, then junctions
	for _, road in roads do
		buildRoad(road)
	end
	for _, node in nodes do
		if node.kind == "roundabout" then
			buildRoundabout(node, roundaboutsByNode[node])
		elseif node.kind == "end" then
			local e = node.ends[1]
			if e then
				local disc = cylinder(e.hw + 7, 2, node.pos - Vector3.new(0, 0.05, 0), C.Asphalt, Enum.Material.Asphalt)
				disc:SetAttribute("SpeedLimit", e.road.limit)
				node.reach = e.hw + 7
			end
		elseif node.kind ~= "attach" then
			local corners = cornersByNode[node]
			buildJunctionSurface(node, corners)
			buildCornerPavements(node, corners)
		end
	end

	local result: Result = { roads = roads, nodes = nodes, byId = byId, minimap = {} }
	if onRoadsDown then
		onRoadsDown(result)
	end

	-- Markings and signals at junctions
	for _, node in nodes do
		if node.kind == "lights" then
			for _, e in node.ends do
				stopLine(e, e.trim)
				laneArrows(e)
			end
			trafficLights(node)
		elseif node.kind == "junction" then
			markMajor(node)
			local busiest = 0
			for _, e in node.ends do
				busiest = math.max(busiest, e.road.profile.rank)
			end
			for _, e in node.ends do
				if not e.major then
					giveWay(e, e.trim)
					-- A give way sign where a side street joins a bigger road
					if e.road.profile.rank < busiest and e.road.path.length > e.trim + 30 then
						local at, facing = roadsideSpot(e, e.trim + 4)
						TownProps.sign("GiveWay", at, facing)
					end
				end
			end
		elseif node.kind == "mini" then
			for _, e in node.ends do
				giveWay(e, e.trim)
				if e.road.path.length > e.trim + 50 then
					local at, facing = roadsideSpot(e, e.trim + 30)
					TownProps.sign("MiniRoundabout", at, facing)
				end
			end
			local dot = cylinder(4, 0.08, node.pos + Vector3.new(0, 0.06, 0), C.White, Enum.Material.SmoothPlastic)
			dot.CanCollide = false
			dot.CastShadow = false
		elseif node.kind == "roundabout" then
			for _, e in node.ends do
				giveWay(e, node.radius + 0.5)
				-- No Entry at the top of each motorway exit, so nobody drives down it the wrong way
				if e.road.taper == "start" and not e.atStart then
					for _, side in { -1, 1 } do
						local p, _, n = RoadKit.at(e.road.path, stationFor(e, e.trim + 3))
						local at = p + n * side * (e.hw + 2)
						TownProps.sign("NoEntry", Vector3.new(at.X, at.Y, at.Z), -e.dir)
					end
				end
			end
		end
	end

	-- Bridges, flyovers and ramps
	for _, road in roads do
		buildRaised(road, ground, isRoad)
	end

	-- The minimap: each road as straight lines, joining up the little pieces of each curve
	for _, road in roads do
		local kind = minimapKind(road.kind)
		local width = math.round(road.hw * 2)
		local points = road.path.points
		local function line(a: Vector3, b: Vector3)
			table.insert(result.minimap, { "l" :: any, math.round(a.X), math.round(a.Z), math.round(b.X), math.round(b.Z), width, kind })
		end
		local anchor = points[1]
		local anchorDirection: Vector3? = nil
		for k = 2, #points do
			local piece = flat(points[k] - points[k - 1])
			if piece.Magnitude > 0.01 then
				local direction = piece.Unit
				local start = anchorDirection or direction
				if start:Dot(direction) < math.cos(math.rad(10)) or flat(points[k] - anchor).Magnitude > 300 then
					if flat(points[k - 1] - anchor).Magnitude > 0.5 then
						line(anchor, points[k - 1])
						anchor = points[k - 1]
					end
					start = direction
				end
				anchorDirection = start
			end
		end
		line(anchor, points[#points])
	end
	for _, node in nodes do
		if node.kind == "roundabout" then
			table.insert(result.minimap, { "c" :: any, math.round(node.pos.X), math.round(node.pos.Z), node.radius, "main" })
		end
	end
	return result
end

return RoadNetwork
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

-- An office block or tower of flats. `style` is "glass", "stone" or "concrete". `facing` turns it to face
-- a road (its front is the side facing that way); it faces north if left out.
function TownBuildings.tower(centre: Vector3, sizeX: number, sizeZ: number, height: number, style: string, facing: Vector3?)
	local base = Vector3.new(centre.X, PAVEMENT_TOP, centre.Z)
	local orient = if facing then TownKit.facing(base, facing) else CFrame.new(base)
	local function at(x: number, y: number, z: number): CFrame
		return orient * CFrame.new(x, y, z)
	end
	local floors = math.floor(height / FLOOR)
	-- A plinth so the building meets the ground cleanly
	box(Vector3.new(sizeX + 4, PAVEMENT_TOP, sizeZ + 4), at(0, -PAVEMENT_TOP / 2, 0), C.Pavement, Enum.Material.Pavement)

	if style == "glass" then
		local body = box(Vector3.new(sizeX, height, sizeZ), at(0, height / 2, 0), C.Glass, Enum.Material.Glass)
		body.Reflectance = 0.3
		for floor = 1, floors - 1 do
			detail(Vector3.new(sizeX + 0.5, 0.8, sizeZ + 0.5), at(0, floor * FLOOR, 0), Color3.fromRGB(200, 202, 206), Enum.Material.Metal)
		end
		local mullions = math.floor(sizeX / 10)
		for i = 1, mullions - 1 do
			local x = -sizeX / 2 + i * sizeX / mullions
			for _, z in { -sizeZ / 2 - 0.2, sizeZ / 2 + 0.2 } do
				detail(Vector3.new(0.5, height, 0.4), at(x, height / 2, z), Color3.fromRGB(175, 178, 184), Enum.Material.Metal)
			end
		end
	else
		local wall = if style == "stone" then C.Portland else C.Concrete
		local material = if style == "stone" then Enum.Material.Limestone else Enum.Material.Concrete
		box(Vector3.new(sizeX, height, sizeZ), at(0, height / 2, 0), wall, material)
		for floor = 0, floors - 1 do
			window(Vector3.new(sizeX + 0.3, 5, sizeZ + 0.3), at(0, floor * FLOOR + 5.5, 0))
		end
		local spacing = if style == "stone" then 6 else 8
		for _, alongX in { true, false } do
			local span = if alongX then sizeX else sizeZ
			local across = if alongX then sizeZ else sizeX
			local count = math.floor(span / spacing)
			for i = 1, count - 1 do
				local offset = -span / 2 + i * span / count
				for _, side in { -1, 1 } do
					local cframe = if alongX then at(offset, height / 2, side * (across / 2 + 0.25)) else at(side * (across / 2 + 0.25), height / 2, offset)
					local size = if alongX then Vector3.new(1.6, height, 0.6) else Vector3.new(0.6, height, 1.6)
					box(size, cframe, wall, material)
				end
			end
		end
	end
	-- Lift motor room on the roof
	box(Vector3.new(sizeX * 0.4, 8, sizeZ * 0.4), at(0, height + 4, 0), C.Concrete, Enum.Material.Concrete)
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

-- A clock face for the clock tower. The server turns the hands to London time (see LondonMap).
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

-- Depots and big sites. Each one is built in its own "frame": the middle of the site's front edge at ground
-- level, facing the road. Local x runs across the site, and +z goes back away from the road.

-- A flat roof on columns, for the bus garage and the petrol station canopy
local function canopy(frame: CFrame, sizeX: number, sizeZ: number, height: number, roofColour: Color3, columns: { Vector3 })
	box(Vector3.new(sizeX, 1.6, sizeZ), frame * CFrame.new(0, height, 0), roofColour, Enum.Material.Metal)
	for _, offset in columns do
		box(Vector3.new(1.4, height, 1.4), frame * CFrame.new(offset.X, height / 2, offset.Z), Color3.fromRGB(220, 220, 222), Enum.Material.Metal)
	end
end

-- White lines between parking bays, `count` bays wide, each `spacing` across and `length` deep
local function bays(frame: CFrame, firstX: number, spacing: number, count: number, length: number, z: number)
	for i = 0, count do
		local line = TownKit.paint(0.5, length, Vector3.zero)
		line.CFrame = frame * CFrame.new(firstX + i * spacing, ROAD_TOP + 0.02, z)
	end
end

-- Tarmac over the whole site, at road level so you can drive straight in
local function yard(frame: CFrame, width: number, depth: number): BasePart
	local surface = box(Vector3.new(width, 1, depth), frame * CFrame.new(0, ROAD_TOP - 0.5, depth / 2), C.Asphalt, Enum.Material.Asphalt)
	surface:SetAttribute("SpeedLimit", 10)
	return surface
end

local function spawnSpot(frame: CFrame, x: number, z: number, size: Vector3, depot: Model)
	local spot = detail(size, frame * CFrame.new(x, ROAD_TOP, z), C.White)
	spot.Name = "Spawn"
	spot.Transparency = 1
	spot.Parent = depot
end

-- The Car team's depot: a petrol station forecourt with pumps, a canopy and a mini market
function TownBuildings.petrolStation(frame: CFrame, width: number, depth: number, depot: Model)
	yard(frame, width, depth)
	-- Parking spaces along the front, cars facing the road
	local spacing = 14
	local count = math.floor((width - 40) / spacing)
	local firstX = -count * spacing / 2
	bays(frame, firstX, spacing, count, 20, 26)
	for i = 0, count - 1 do
		spawnSpot(frame, firstX + (i + 0.5) * spacing, 26, Vector3.new(6, 1, 14), depot)
	end

	-- The forecourt
	local forecourt = frame * CFrame.new(0, ROAD_TOP, depth * 0.5)
	local columns = {}
	for _, x in { -30, 0, 30 } do
		for _, z in { -16, 16 } do
			table.insert(columns, Vector3.new(x, 0, z))
		end
	end
	canopy(forecourt, 76, 44, 17, Color3.fromRGB(235, 235, 235), columns)
	detail(Vector3.new(76.4, 2.6, 44.4), forecourt * CFrame.new(0, 17, 0), Color3.fromRGB(30, 130, 70))
	local band = detail(Vector3.new(20, 2.2, 0.2), forecourt * CFrame.new(0, 17, -22.3), Color3.fromRGB(30, 130, 70))
	TownKit.text(band, Enum.NormalId.Front, "PETROL", C.White)
	for _, x in { -30, 30 } do
		local island = forecourt * CFrame.new(x, 0, 0)
		box(Vector3.new(4, 0.6, 26), island * CFrame.new(0, 0.3, 0), C.Kerb, Enum.Material.Concrete)
		for _, z in { -7, 7 } do
			box(Vector3.new(2.4, 5.5, 3), island * CFrame.new(0, 3.35, z), Color3.fromRGB(200, 30, 35))
			detail(Vector3.new(2.5, 1.2, 1.6), island * CFrame.new(0, 4.6, z), C.StreetBlack, Enum.Material.Glass)
		end
	end

	-- The mini market at the back
	local shop = frame * CFrame.new(0, ROAD_TOP, depth - 22)
	box(Vector3.new(60, 15, 26), shop * CFrame.new(0, 7.5, 4), Color3.fromRGB(70, 72, 76), Enum.Material.Concrete)
	window(Vector3.new(44, 8, 0.3), shop * CFrame.new(-6, 4.6, -9))
	local fascia = detail(Vector3.new(60.4, 3, 0.8), shop * CFrame.new(0, 13.2, -9.2), Color3.fromRGB(30, 130, 70))
	TownKit.text(fascia, Enum.NormalId.Front, "MINI MART", C.White)

	-- Price board by the road
	local totem = frame * CFrame.new(width / 2 - 12, PAVEMENT_TOP, 6)
	box(Vector3.new(6, 14, 1.4), totem * CFrame.new(0, 7, 0), Color3.fromRGB(30, 130, 70))
	local prices = detail(Vector3.new(5, 6, 0.1), totem * CFrame.new(0, 8, -0.75), C.StreetBlack)
	TownKit.text(prices, Enum.NormalId.Front, "UNLEADED 139.9\nDIESEL 146.9", Color3.fromRGB(255, 200, 40))

	-- In the daylight between the parking spaces and the canopy, angled for a good look
	local spot = frame * CFrame.new(0, ROAD_TOP, 58)
	depot:SetAttribute("ShowroomSpot", TownKit.facing(spot.Position, frame:VectorToWorldSpace(Vector3.new(1, 0, -0.35))))
end

-- The Bus team's depot: a yard of bus bays in front of a big open garage
function TownBuildings.busGarage(frame: CFrame, width: number, depth: number, depot: Model)
	yard(frame, width, depth)
	local spacing = 24
	local count = math.floor((width - 40) / spacing)
	local firstX = -count * spacing / 2
	bays(frame, firstX, spacing, count, 52, 40)
	for i = 0, count - 1 do
		spawnSpot(frame, firstX + (i + 0.5) * spacing, 40, Vector3.new(11, 1, 48), depot)
	end

	local shedDepth = math.min(150, depth - 110)
	local shed = frame * CFrame.new(0, ROAD_TOP, depth - shedDepth / 2 - 6)
	local shedWidth = width - 30
	local columns = {}
	for x = -shedWidth / 2 + 4, shedWidth / 2 - 4, shedWidth / 4 do
		for _, z in { -shedDepth / 2 + 4, 0, shedDepth / 2 - 4 } do
			table.insert(columns, Vector3.new(x, 0, z))
		end
	end
	canopy(shed, shedWidth, shedDepth, 26, Color3.fromRGB(120, 125, 130), columns)
	box(Vector3.new(shedWidth, 26, 2), shed * CFrame.new(0, 13, shedDepth / 2), C.RedBrick, Enum.Material.Brick)
	local sign = detail(Vector3.new(70, 5, 0.4), shed * CFrame.new(0, 23, -shedDepth / 2 - 0.3), Color3.fromRGB(210, 30, 35))
	TownKit.text(sign, Enum.NormalId.Front, "BUS GARAGE", C.White)

	local spot = frame * CFrame.new(width / 2 - 70, ROAD_TOP, 105)
	depot:SetAttribute("ShowroomSpot", TownKit.facing(spot.Position, frame:VectorToWorldSpace(Vector3.new(-0.25, 0, -1))))
end

-- The Emergency team's depot: a yard in front of a brick police station with a blue lamp
function TownBuildings.policeStation(frame: CFrame, width: number, depth: number, depot: Model)
	yard(frame, width, depth)
	local spacing = 14
	local count = math.floor((width - 60) / spacing)
	local firstX = -count * spacing / 2
	bays(frame, firstX, spacing, count, 24, 30)
	for i = 0, count - 1 do
		spawnSpot(frame, firstX + (i + 0.5) * spacing, 30, Vector3.new(7, 1, 19), depot)
	end

	-- The station across the back, facing the yard
	local station = frame * CFrame.new(0, PAVEMENT_TOP, depth - 50)
	box(Vector3.new(width - 20, 0.6, 50), station * CFrame.new(0, -0.3, 25), C.Pavement, Enum.Material.Pavement)
	TownBuildings.plainRow(station, width - 40, 46, 3, C.RedBrick)
	local sign = detail(Vector3.new(40, 4, 0.6), station * CFrame.new(0, 9.4, -0.5), Color3.fromRGB(15, 40, 120))
	TownKit.text(sign, Enum.NormalId.Front, "POLICE", C.White)
	-- The traditional blue lamp over the door
	local lamp = detail(Vector3.new(2, 2.6, 2), station * CFrame.new(0, 14, -2), Color3.fromRGB(40, 90, 230), Enum.Material.Neon)
	local glow = Instance.new("PointLight")
	glow.Color = Color3.fromRGB(60, 110, 255)
	glow.Range = 14
	glow.Parent = lamp

	local spot = frame * CFrame.new(width / 2 - 60, ROAD_TOP, 95)
	depot:SetAttribute("ShowroomSpot", TownKit.facing(spot.Position, frame:VectorToWorldSpace(Vector3.new(-1, 0, -0.4))))
end

-- Motorway services: a car park, a fuel canopy and a long low building with a café
function TownBuildings.services(frame: CFrame, width: number, depth: number)
	yard(frame, width, depth)
	local spacing = 14
	for row = 0, 2 do
		local z = 40 + row * 46
		local count = math.floor((width * 0.55) / spacing)
		bays(frame, -width / 2 + 20, spacing, count, 20, z)
	end
	local building = frame * CFrame.new(width * 0.2, PAVEMENT_TOP, depth - 60)
	box(Vector3.new(width * 0.45, 0.6, 60), building * CFrame.new(0, -0.3, 22), C.Pavement, Enum.Material.Pavement)
	box(Vector3.new(width * 0.4, 18, 40), building * CFrame.new(0, 9, 26), Color3.fromRGB(210, 205, 195), Enum.Material.Concrete)
	window(Vector3.new(width * 0.4 - 6, 10, 0.3), building * CFrame.new(0, 6, 5.9))
	local fascia = detail(Vector3.new(50, 4, 0.6), building * CFrame.new(0, 15, 5.6), Color3.fromRGB(240, 120, 20))
	TownKit.text(fascia, Enum.NormalId.Front, "SERVICES  ·  FOOD  ·  FUEL", C.White)
	local fuel = frame * CFrame.new(-width / 2 + 70, ROAD_TOP, depth - 60)
	local columns = {}
	for _, x in { -24, 24 } do
		for _, z in { -14, 14 } do
			table.insert(columns, Vector3.new(x, 0, z))
		end
	end
	canopy(fuel, 64, 40, 16, Color3.fromRGB(235, 235, 235), columns)
	detail(Vector3.new(64.4, 2.4, 40.4), fuel * CFrame.new(0, 16, 0), Color3.fromRGB(240, 120, 20))
end

-- A power station like Battersea's: a huge brick hall with a white chimney at each corner
function TownBuildings.powerStation(centre: Vector3, sizeX: number, sizeZ: number)
	local base = Vector3.new(centre.X, PAVEMENT_TOP, centre.Z)
	local brick = Color3.fromRGB(150, 85, 60)
	box(Vector3.new(sizeX, 70, sizeZ), CFrame.new(base + Vector3.new(0, 35, 0)), brick, Enum.Material.Brick)
	box(Vector3.new(sizeX * 0.6, 20, sizeZ * 0.8), CFrame.new(base + Vector3.new(0, 80, 0)), brick, Enum.Material.Brick)
	for _, x in { -1, 1 } do
		for _, z in { -1, 1 } do
			local foot = base + Vector3.new(x * (sizeX / 2 - 10), 0, z * (sizeZ / 2 - 10))
			box(Vector3.new(18, 75, 18), CFrame.new(foot + Vector3.new(0, 37.5, 0)), brick, Enum.Material.Brick)
			TownKit.post(12, 80, foot + Vector3.new(0, 75, 0), Color3.fromRGB(238, 236, 230), Enum.Material.Concrete)
			TownKit.post(13, 3, foot + Vector3.new(0, 152, 0), Color3.fromRGB(200, 198, 190), Enum.Material.Concrete)
		end
	end
	for floor = 0, 4 do
		window(Vector3.new(sizeX + 0.3, 6, sizeZ * 0.6), CFrame.new(base + Vector3.new(0, 12 + floor * 11, 0)))
	end
end

-- A tall column with a statue on top and four lions round the base, for the middle of a big roundabout
function TownBuildings.column(base: Vector3)
	box(Vector3.new(26, 2, 26), CFrame.new(base + Vector3.new(0, 1, 0)), C.Stone, Enum.Material.Limestone)
	box(Vector3.new(20, 2, 20), CFrame.new(base + Vector3.new(0, 3, 0)), C.Stone, Enum.Material.Limestone)
	box(Vector3.new(12, 15, 12), CFrame.new(base + Vector3.new(0, 11.5, 0)), C.Portland, Enum.Material.Limestone)
	TownKit.post(5.5, 105, base + Vector3.new(0, 19, 0), C.Portland, Enum.Material.Limestone)
	box(Vector3.new(8, 4, 8), CFrame.new(base + Vector3.new(0, 126, 0)), C.Bronze, Enum.Material.Metal)
	box(Vector3.new(2.4, 8, 2.4), CFrame.new(base + Vector3.new(0, 132, 0)), C.Bronze, Enum.Material.Metal)
	box(Vector3.new(3.2, 1, 3.2), CFrame.new(base + Vector3.new(0, 136.5, 0)), C.Bronze, Enum.Material.Metal)
	for _, offset in { Vector3.new(1, 0, 0), Vector3.new(-1, 0, 0), Vector3.new(0, 0, 1), Vector3.new(0, 0, -1) } do
		local lion = TownKit.facing(base + offset * 10 + Vector3.new(0, 4, 0), offset)
		box(Vector3.new(3.6, 3.6, 8), lion * CFrame.new(0, 1.8, 0), C.Bronze, Enum.Material.Metal)
		box(Vector3.new(4, 4, 3.4), lion * CFrame.new(0, 4.2, -3), C.Bronze, Enum.Material.Metal)
	end
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
-- TownProps, TownBuildings, RoadKit and LondonMap all use these, so the whole town shares one set of colours and heights.

local CollectionService = game:GetService("CollectionService")
local ServerStorage = game:GetService("ServerStorage")

local TownKit = {}

-- Heights, in studs. Roads sit just above the ground and pavements are one kerb higher.
TownKit.ROAD_TOP = 0.1
TownKit.KERB_HEIGHT = 0.5
TownKit.PAVEMENT_TOP = TownKit.ROAD_TOP + TownKit.KERB_HEIGHT
TownKit.FLOOR = 11 -- one storey of a building

TownKit.Colours = {
	Asphalt = Color3.fromRGB(150, 150, 153), -- light grainy grey, like Birmingham Vehicle Simulator's roads
	White = Color3.fromRGB(235, 235, 232),
	Yellow = Color3.fromRGB(240, 190, 20),
	Pavement = Color3.fromRGB(206, 196, 186), -- the Pavement material draws herringbone block paving, like BVS
	RedPaving = Color3.fromRGB(176, 112, 100), -- block paving on the high streets
	Kerb = Color3.fromRGB(152, 150, 144),
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
	surface.MaxDistance = 220 -- don't bother drawing words nobody's close enough to read
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

-- A copy of a prop from the bought packs (ServerStorage → PropKit, made by tools/prepare_prop_kit.luau),
-- standing at `cframe` with its front facing the way `cframe` faces. nil if the kit doesn't have it.
function TownKit.prop(name: string, cframe: CFrame): Model?
	local kit = ServerStorage:FindFirstChild("PropKit")
	local template = kit and kit:FindFirstChild(name)
	if not template or not template:IsA("Model") then
		return nil
	end
	local model = template:Clone()
	model:PivotTo(cframe)
	model.Parent = folder
	return model
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

-- A tree: the mesh tree from the prop kit when the place has it, otherwise one made of parts. `form` stretches
-- it: "tall" makes a slim, tall tree like the pines in BVS's woods, "wide" a broad spreading one, nil as it is.
-- Each one is turned a random way, so no two look the same.
function TownProps.tree(at: Vector3, scale: number?, form: string?)
	local s = scale or 1
	local hash = (at.X * 12.9898 + at.Z * 78.233) % 1
	local turn = hash * 2 * math.pi
	local kitTree = TownKit.prop("Tree", CFrame.new(at) * CFrame.Angles(0, turn, 0))
	if kitTree then
		if math.abs(s - 1) > 0.01 then
			kitTree:ScaleTo(kitTree:GetScale() * s)
		end
		local across, up = 1, 1
		if form == "tall" then
			across, up = 0.55, 1.65
		elseif form == "wide" then
			across, up = 1.35, 0.85
		end
		local base = kitTree:GetPivot()
		for _, part in kitTree:GetDescendants() do
			if part:IsA("BasePart") then
				part.CanTouch = false
				if across ~= 1 or up ~= 1 then
					-- Stretch about the foot of the tree (it's only turned about the vertical, so this is exact)
					local offset = base:PointToObjectSpace(part.Position)
					local stretched = Vector3.new(offset.X * across, offset.Y * up, offset.Z * across)
					local rotation = part.CFrame - part.Position
					part.Size = Vector3.new(part.Size.X * across, part.Size.Y * up, part.Size.Z * across)
					part.CFrame = CFrame.new(base:PointToWorldSpace(stretched)) * rotation
				end
				if part.Name == "Leaves" then
					part.CanCollide = false
					part.CanQuery = false
				end
			end
		end
		kitTree.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
		return
	end
	local foot = Vector3.new(at.X, at.Y, at.Z)
	post(1.2 * s, 9 * s, foot, C.TreeTrunk, Enum.Material.Wood)
	local leaves = C.Leaves
	box(Vector3.new(10, 9, 10) * s, CFrame.new(foot + Vector3.new(0, 12 * s, 0)), leaves, Enum.Material.Grass, "Part").Shape = Enum.PartType.Ball
	local top = box(Vector3.new(7, 7, 7) * s, CFrame.new(foot + Vector3.new(1.5 * s, 16 * s, -1 * s)), leaves:Lerp(Color3.new(0.3, 0.5, 0.2), 0.15), Enum.Material.Grass)
	top.Shape = Enum.PartType.Ball
end

-- A bush: the leafy bush from the prop kit, or a green ball
function TownProps.bush(at: Vector3, scale: number?)
	local s = scale or 1
	local turn = ((at.X * 7.31 + at.Z * 3.17) % 1) * 2 * math.pi
	local kitBush = TownKit.prop("Bush", CFrame.new(at) * CFrame.Angles(0, turn, 0))
	if kitBush then
		if math.abs(s - 1) > 0.01 then
			kitBush:ScaleTo(kitBush:GetScale() * s)
		end
		for _, part in kitBush:GetDescendants() do
			if part:IsA("BasePart") then
				part.CanCollide = false
				part.CanQuery = false
				part.CanTouch = false
			end
		end
		kitBush.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
		return
	end
	local ball = TownKit.detail(Vector3.new(7, 5, 7) * s, CFrame.new(at + Vector3.new(0, 2 * s, 0)), C.Hedge, Enum.Material.LeafyGrass)
	ball.Shape = Enum.PartType.Ball
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

local BINS = { "BinHooded", "BinSquare", "BinPark" }

function TownProps.bin(at: Vector3, facing: Vector3?)
	local base = onPavement(at)
	local choice = BINS[math.floor(math.abs(at.X * 7 + at.Z * 3)) % #BINS + 1]
	if TownKit.prop(choice, TownKit.facing(base, facing or Vector3.new(0, 0, -1))) then
		return
	end
	post(1.6, 3.2, base, C.StreetBlack, Enum.Material.Metal)
	detail(Vector3.new(1.8, 0.3, 1.8), CFrame.new(base + Vector3.new(0, 3.3, 0)), C.Gold, Enum.Material.Metal)
end

function TownProps.bollard(at: Vector3)
	local base = onPavement(at)
	post(0.8, 3, base, C.StreetBlack, Enum.Material.Metal)
	post(0.86, 0.35, base + Vector3.new(0, 2.2, 0), C.White)
end

-- A telephone box: the classic red one, or the modern kind from the bought pack
function TownProps.phoneBox(at: Vector3, facing: Vector3, modern: boolean?)
	local frame = TownKit.facing(onPavement(at), facing)
	if modern and TownKit.prop("PhoneBoxModern", frame) then
		return
	end
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
	if TownKit.prop("BusShelter", frame * CFrame.new(0, PAVEMENT_TOP, 5.8)) then
		TownProps.busFlagAndMarkings(frame)
		return
	end
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
	TownProps.busFlagAndMarkings(frame)
end

-- The red bus stop flag on its pole and the yellow "BUS STOP" box on the road, next to a shelter
function TownProps.busFlagAndMarkings(frame: CFrame)
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
	-- The bought traffic light, if the kit has it (its lamps are already called Red, Amber and Green)
	local bought = TownKit.prop("TrafficLight", base)
	if bought then
		bought.Name = "TrafficLight"
		bought:SetAttribute("Junction", junctionId)
		bought:SetAttribute("Axis", axis)
		TownKit.tag(bought, "TrafficLight")
		return
	end
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
	local bought = TownKit.prop("SpeedCamera", base)
	if bought then
		bought:SetAttribute("SpeedLimit", limit)
		TownKit.tag(bought, "SpeedCamera")
		return
	end
	box(Vector3.new(0.6, 10, 0.6), base * CFrame.new(0, 5, 0), C.LampGrey, Enum.Material.Metal)
	local camera = box(Vector3.new(1.8, 2.2, 3.2), base * CFrame.new(0, 10.4, 0), Color3.fromRGB(245, 205, 30))
	camera:SetAttribute("SpeedLimit", limit)
	TownKit.tag(camera, "SpeedCamera")
	detail(Vector3.new(1.2, 1.2, 0.1), base * CFrame.new(0, 10.4, -1.62), C.StreetBlack, Enum.Material.Glass)
end

-- A round speed limit sign on a pole. 70 shows the national speed limit sign.
function TownProps.limitSign(at: Vector3, facing: Vector3, limit: number)
	local frame = TownKit.facing(onPavement(at), facing)
	if TownKit.prop(if limit >= 70 then "NationalLimit" else "Limit" .. limit, frame) then
		return
	end
	box(Vector3.new(0.3, 8, 0.3), frame * CFrame.new(0, 4, 0), C.LampGrey, Enum.Material.Metal)
	local disc = detail(Vector3.new(0.15, 2.6, 2.6), frame * CFrame.new(0, 8.6, -0.2) * CFrame.Angles(0, math.pi / 2, 0), Color3.fromRGB(210, 30, 30))
	disc.Shape = Enum.PartType.Cylinder
	local face = detail(Vector3.new(1.9, 1.9, 0.05), frame * CFrame.new(0, 8.6, -0.3), C.White)
	TownKit.text(face, Enum.NormalId.Front, tostring(limit), Color3.new(0, 0, 0))
end

-- A road sign from the bought pack ("GiveWay", "NoEntry", "OneWay", "MiniRoundabout", "SpeedCameraSign"),
-- standing at `at` (its height is used, so it works on islands and bridges) with its face towards `facing`
function TownProps.sign(name: string, at: Vector3, facing: Vector3): boolean
	return TownKit.prop(name, TownKit.facing(at, facing)) ~= nil
end

-- A black and yellow keep-left bollard on the nose of a traffic island, facing the traffic coming at it
function TownProps.keepLeft(at: Vector3, facing: Vector3)
	TownKit.prop("KeepLeft", TownKit.facing(at, facing))
end

-- A white arrow painted on the road. `direction` is the way the traffic is going.
-- (The arrows in the pack point along +Z, so they're turned to face back the other way.)
function TownProps.laneArrow(at: Vector3, direction: Vector3, name: string?)
	TownKit.prop(name or "ArrowAhead", TownKit.facing(Vector3.new(at.X, at.Y + 0.03, at.Z), -direction))
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
-- The minimap reads the roads from ReplicatedStorage → MapInfo → Minimap, which LondonMap writes.

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Ui = require(script.Parent:WaitForChild("Ui"))
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Gearbox = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Gearbox"))

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

-- The gear you're in, under the time, and a rev counter: a thin bar along the top of the map that fills
-- up as the engine revs and goes red near the redline (Driving puts Rpm and Gear on your car)
local gearLabel = Ui.label("", 12, Enum.FontWeight.Bold, {
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -16, 0, 32),
	Size = UDim2.fromOffset(120, 16),
	TextXAlignment = Enum.TextXAlignment.Right,
	Parent = panel,
})
local revTrack = Ui.make("Frame", {
	Position = UDim2.fromOffset(16, MAP_TOP - 6),
	Size = UDim2.new(1, -32, 0, 3),
	BackgroundColor3 = Color3.fromRGB(70, 74, 82),
	BorderSizePixel = 0,
	Parent = panel,
})
Ui.corner(revTrack, 2)
local revFill = Ui.make("Frame", { Size = UDim2.fromScale(0, 1), BorderSizePixel = 0, Parent = revTrack })
Ui.corner(revFill, 2)

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
	motorway = Color3.fromRGB(95, 150, 225),
	yard = Color3.fromRGB(70, 74, 82),
	water = Color3.fromRGB(45, 85, 130),
	park = Color3.fromRGB(40, 85, 50),
}
local ROAD_ORDER = { water = 1, park = 1, yard = 2, side = 3, main = 4, dual = 5, motorway = 6 }
local ROADS = { side = true, main = true, dual = true, motorway = true }

-- One thing on the map. Entries are:
--   { "l", x1, z1, x2, z2, width, kind }  a straight line (roads, the river)
--   { "c", x, z, radius, kind }           a circle (roundabouts)
--   { "q", x, z, width, depth, degrees, kind }  a turned rectangle (depots)
--   { x, z, sizeX, sizeZ, kind }           a rectangle (parks)
-- Every drawn thing with where it is, so the ones outside the little map window can be hidden: thousands
-- of frames redrawn every frame inside the CanvasGroup made the game lag
type Drawn = { frame: Frame, x: number, z: number, reach: number }
local drawn: { Drawn } = {}

local function drawEntry(entry: { any })
	local kind: string
	local frame: Frame
	local cx, cz, reach = 0, 0, 0
	if entry[1] == "l" then
		local x1, z1, x2, z2, width = entry[2], entry[3], entry[4], entry[5], entry[6]
		kind = entry[7]
		local dx, dz = x2 - x1, z2 - z1
		local length = math.sqrt(dx * dx + dz * dz)
		cx, cz, reach = (x1 + x2) / 2, (z1 + z2) / 2, length / 2 + width
		-- Draw roads thinner than they really are so the map stays readable
		local thickness = if ROADS[kind] then math.max(3, width * MAP_SCALE * 0.55) else width * MAP_SCALE
		frame = Ui.make("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset((x1 + x2) / 2 * MAP_SCALE, (z1 + z2) / 2 * MAP_SCALE),
			-- A little longer than the line so the pieces of a curve overlap
			Size = UDim2.fromOffset(length * MAP_SCALE + thickness * 0.5, thickness),
			Rotation = math.deg(math.atan2(dz, dx)),
			BorderSizePixel = 0,
			Parent = world,
		})
	elseif entry[1] == "c" then
		local radius = entry[4]
		kind = entry[5]
		cx, cz, reach = entry[2], entry[3], radius
		frame = Ui.make("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(entry[2] * MAP_SCALE, entry[3] * MAP_SCALE),
			Size = UDim2.fromOffset(radius * 2 * MAP_SCALE, radius * 2 * MAP_SCALE),
			BorderSizePixel = 0,
			Parent = world,
		})
		Ui.corner(frame, radius * MAP_SCALE)
	elseif entry[1] == "q" then
		kind = entry[7]
		cx, cz, reach = entry[2], entry[3], math.max(entry[4], entry[5])
		frame = Ui.make("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(entry[2] * MAP_SCALE, entry[3] * MAP_SCALE),
			Size = UDim2.fromOffset(entry[4] * MAP_SCALE, entry[5] * MAP_SCALE),
			Rotation = -entry[6],
			BorderSizePixel = 0,
			Parent = world,
		})
	else
		kind = entry[5]
		cx, cz, reach = entry[1], entry[2], math.max(entry[3], entry[4])
		frame = Ui.make("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(entry[1] * MAP_SCALE, entry[2] * MAP_SCALE),
			Size = UDim2.fromOffset(entry[3] * MAP_SCALE, entry[4] * MAP_SCALE),
			BorderSizePixel = 0,
			Parent = world,
		})
	end
	frame.BackgroundColor3 = ROAD_COLOURS[kind] or ROAD_COLOURS.side
	frame.ZIndex = ROAD_ORDER[kind] or 3
	frame.BackgroundTransparency = if kind == "yard" then 0.4 else 0
	frame.Visible = false
	table.insert(drawn, { frame = frame, x = cx, z = cz, reach = reach })
end

-- How far from you the map window can show, in studs (corner to corner, with room for turning)
local VIEW = math.sqrt(PANEL_WIDTH ^ 2 + PANEL_HEIGHT ^ 2) / MAP_SCALE * 0.6
local sinceCull = math.huge

local function cull(position: Vector3)
	for _, item in drawn do
		local dx, dz = item.x - position.X, item.z - position.Z
		local near = VIEW + item.reach
		item.frame.Visible = dx * dx + dz * dz < near * near
	end
end

local function drawMap()
	local mapInfo = ReplicatedStorage:WaitForChild("MapInfo", 30)
	local data = mapInfo and mapInfo:WaitForChild("Minimap", 30)
	if not data or not data:IsA("StringValue") then
		return
	end
	local ok, entries = pcall(function(): any
		return HttpService:JSONDecode(data.Value)
	end)
	if not ok or type(entries) ~= "table" then
		return
	end
	for _, entry in entries do
		drawEntry(entry)
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
	Size = UDim2.fromOffset(300, 0),
	AutomaticSize = Enum.AutomaticSize.Y,
	BackgroundTransparency = 1,
	Parent = gui,
})
Ui.make("UIListLayout", { Padding = UDim.new(0, 7), HorizontalAlignment = Enum.HorizontalAlignment.Right, SortOrder = Enum.SortOrder.LayoutOrder, Parent = controlsList })

local blueLightsRow: Frame? = nil
-- Each control's key on a keyboard, then its button on a controller
local keyLabels: { { label: TextLabel, keyboard: string, gamepad: string } } = {}
for order, control in {
	{ "Steering", "WASD", "Stick + RT / LT" },
	{ "Handbrake", "Space", "A" },
	{ "Indicators", "Q-E", "D-pad left / right" },
	{ "Hazards", "B", "D-pad down" },
	{ "Lights", "L", "D-pad up" },
	{ "Blue lights", "R", "X" },
	{ "Horn", "H", "Press left stick" },
	{ "Get out", "F", "Y" },
} do
	-- The action name and its key side by side, lined up on the right, however long the key's name is
	local row = Ui.make("Frame", { Size = UDim2.new(1, 0, 0, 28), BackgroundTransparency = 1, LayoutOrder = order, Parent = controlsList })
	Ui.make("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Right,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 10),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = row,
	})
	local key = Ui.label(control[2], 13, Enum.FontWeight.Medium, {
		Size = UDim2.fromOffset(0, 28),
		AutomaticSize = Enum.AutomaticSize.X,
		LayoutOrder = 2,
		Parent = row,
	})
	Ui.padding(key, 9, 0)
	Ui.corner(key, 14)
	Ui.make("UIStroke", { ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Color = Color3.new(1, 1, 1), Thickness = 1.5, Parent = key })
	local action = Ui.label(control[1], 14, Enum.FontWeight.Regular, {
		Size = UDim2.fromOffset(0, 28),
		AutomaticSize = Enum.AutomaticSize.X,
		TextXAlignment = Enum.TextXAlignment.Right,
		LayoutOrder = 1,
		Parent = row,
	})
	action.TextStrokeTransparency = 0.6
	key.TextStrokeTransparency = 0.7
	table.insert(keyLabels, { label = key, keyboard = control[2], gamepad = control[3] })
	if control[1] == "Blue lights" then
		blueLightsRow = row
	end
end

-- Show controller buttons when you're using a controller, keys when you're using the keyboard
local function showInputType(inputType: Enum.UserInputType)
	local isGamepad = inputType.Name:sub(1, 7) == "Gamepad"
	local isKeyboard = inputType == Enum.UserInputType.Keyboard or inputType.Name:sub(1, 5) == "Mouse"
	if not isGamepad and not isKeyboard then
		return
	end
	for _, entry in keyLabels do
		entry.label.Text = if isGamepad then entry.gamepad else entry.keyboard
	end
end
UserInputService.LastInputTypeChanged:Connect(showInputType)
showInputType(UserInputService:GetLastInputType())

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

	local rpm, gear = car:GetAttribute("Rpm"), car:GetAttribute("Gear")
	if typeof(rpm) == "number" and typeof(gear) == "number" then
		local share = Gearbox.share(rpm)
		revFill.Size = UDim2.fromScale(share, 1)
		revFill.BackgroundColor3 = if rpm >= Gearbox.UP_AT then C.Red else C.Text
		gearLabel.Text = if gear <= 0 then "R" else "Gear " .. gear
	end
	revTrack.Visible = typeof(rpm) == "number"
	gearLabel.Visible = typeof(gear) == "number"

	-- Slide and turn the map so you're in the middle, facing up
	local position = seat.Position
	sinceCull += dt
	if sinceCull > 0.4 then
		sinceCull = 0
		cull(position)
	end
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
-- Q / E indicators, B hazards, R blue lights, H horn.
-- On a controller: right trigger to go, left trigger to brake and reverse, left stick to steer (Roblox does
-- those for every VehicleSeat), A handbrake, Y get out, D-pad up lights, D-pad left / right indicators,
-- D-pad down hazards, X blue lights, press the left stick for the horn.
-- The car rides on springs and tyres worked out by RaycastCar; this script does the pedals, steering and engine.
-- The car has a gearbox (see Gearbox): it revs up, changes gear with a short gap in the drive, and the engine
-- slows the car when you lift off. What it's doing (rpm, gear, throttle, sliding) goes on the car as attributes
-- on your device only, for VehicleEffects to make the sounds from.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Gearbox = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Gearbox"))
local RaycastCar = require(script.Parent:WaitForChild("RaycastCar"))
local carControl = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("CarControl") :: RemoteEvent

local CAR = Config.Car
local STEERING_LOCK = math.rad(CAR.SteeringLockDegrees)

local player = Players.LocalPlayer
local driving: { Disconnect: (any) -> () }? = nil -- the running car, stopped with Disconnect

-- Roblox's own controls, for the move direction from the keyboard (WASD and arrows), the phone thumbstick
-- and the controller's left stick. We read the pedals ourselves rather than trusting the seat's ThrottleFloat:
-- Roblox's car controller doesn't switch on if you're put in the seat while the menu has your controls off.
local controls: any = nil
task.spawn(function()
	local ok, playerModule = pcall(function(): any
		local module = player:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule")
		return (require :: any)(module) -- Roblox's own module, so the type checker can't see inside it
	end)
	if ok and playerModule then
		controls = playerModule:GetControls()
	end
end)

local TRIGGER_DEADZONE = 0.05
-- A car standing still is "asleep" to the physics engine, and the first tiny bit of speed gets thrown away,
-- so pulling away always starts at least this fast (studs per second, about 2 mph)
local START_SPEED = 3

-- Accelerator (+1) or brake / reverse (-1), and steering (-1 left to +1 right), from every kind of input
local function readPedals(): (number, number)
	local move = if controls then controls:GetMoveVector() else Vector3.zero
	local throttle = -move.Z
	local steer = move.X
	-- Controller triggers: right to go, left to brake and reverse
	for _, gamepad in UserInputService:GetConnectedGamepads() do
		for _, state in UserInputService:GetGamepadState(gamepad) do
			if state.KeyCode == Enum.KeyCode.ButtonR2 and state.Position.Z > TRIGGER_DEADZONE then
				throttle += state.Position.Z
			elseif state.KeyCode == Enum.KeyCode.ButtonL2 and state.Position.Z > TRIGGER_DEADZONE then
				throttle -= state.Position.Z
			end
		end
	end
	-- Testing in Studio: the Command Bar can press the pedals with player:SetAttribute("TestThrottle", 1),
	-- and steer with "TestSteer" (-1 left to 1 right)
	if RunService:IsStudio() then
		local test = player:GetAttribute("TestThrottle")
		if typeof(test) == "number" then
			throttle = test
		end
		local testSteer = player:GetAttribute("TestSteer")
		if typeof(testSteer) == "number" then
			steer = testSteer
		end
	end
	return math.clamp(throttle, -1, 1), math.clamp(steer, -1, 1)
end
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
	[Enum.KeyCode.DPadUp] = "Lights",
	[Enum.KeyCode.DPadLeft] = "Left",
	[Enum.KeyCode.DPadRight] = "Right",
	[Enum.KeyCode.DPadDown] = "Hazard",
	[Enum.KeyCode.ButtonX] = "BlueLights",
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

-- Space (A on a controller) is the handbrake while driving. Binding it stops it making you jump out of the seat;
-- whether it's held is read straight from the keyboard and controller every frame, so it can never get stuck on.
local function onHandbrake(_: string, _state: Enum.UserInputState): Enum.ContextActionResult
	return Enum.ContextActionResult.Sink
end

local function handbrakeHeld(): boolean
	if UserInputService:IsKeyDown(Enum.KeyCode.Space) or (RunService:IsStudio() and player:GetAttribute("TestHandbrake")) then
		return true
	end
	for _, gamepad in UserInputService:GetConnectedGamepads() do
		if UserInputService:IsGamepadButtonDown(gamepad, Enum.KeyCode.ButtonA) then
			return true
		end
	end
	return false
end

-- The horn: held down, so the server tells everyone to hear it while you hold it
local function onHorn(_: string, state: Enum.UserInputState): Enum.ContextActionResult
	if state == Enum.UserInputState.Begin then
		carControl:FireServer("HornOn")
	elseif state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then
		carControl:FireServer("HornOff")
	end
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

-- `switches` is false for A-Chassis cars: their own lights script works the lights and indicators (on the same
-- keys), and it ignores keys we've taken
local function bindKeys(switches: boolean)
	local priority = Enum.ContextActionPriority.High.Value
	if switches then
		local switchKeys = {}
		for keyCode in SWITCHES do
			table.insert(switchKeys, keyCode)
		end
		ContextActionService:BindActionAtPriority("CarSwitches", onSwitch, false, priority, table.unpack(switchKeys))
	end
	ContextActionService:BindActionAtPriority("Handbrake", onHandbrake, false, priority, Enum.KeyCode.Space, Enum.KeyCode.ButtonA)
	ContextActionService:BindActionAtPriority("GetOut", onGetOut, false, priority, Enum.KeyCode.F, Enum.KeyCode.ButtonY)
	ContextActionService:BindActionAtPriority("Horn", onHorn, false, priority, Enum.KeyCode.H, Enum.KeyCode.ButtonL3)
end

local function unbindKeys()
	ContextActionService:UnbindAction("CarSwitches")
	ContextActionService:UnbindAction("Handbrake")
	ContextActionService:UnbindAction("GetOut")
	ContextActionService:UnbindAction("Horn")
	carControl:FireServer("HornOff")
	handbrake = false
end

local chassisSeat: VehicleSeat? = nil -- the A-Chassis car you're driving, if it is one

-- Drift assist for A-Chassis cars. Roblox tyres don't lose grip gradually like real ones, so once the back of a
-- car let go it snapped straight round into a spin. It only steps in on real oversteer (the car rotating into the
-- slide past SLIDING_FROM), never on normal turn-in, so the steering stays sharp:
--   - the slide can only wind up so fast, so it builds over a moment instead of snapping
--   - the rotation is capped, lower at higher speed
--   - countersteering pulls it back, more the bigger the angle, so a held drift at a sensible angle flows while
--     a big one gets caught; past SPIN_GUARD it's damped hard so it doesn't swap ends
local SLIDING_FROM = math.rad(10)
local SPIN_GUARD = math.rad(40)
local MAX_YAW_ACCELERATION = 6 -- how quickly a slide can wind up, radians per second per second
local COUNTERSTEER_CATCH = 2 -- how hard countersteering slows the rotation (at big angles)

local function driftAssist(seat: BasePart, state: { yaw: number }, dt: number)
	local cframe = seat.CFrame
	local up = cframe.UpVector
	local velocity = seat.AssemblyLinearVelocity
	local forwardSpeed = velocity:Dot(cframe.LookVector)
	local sideSpeed = velocity:Dot(cframe.RightVector)
	local spin = seat.AssemblyAngularVelocity
	local yaw = spin:Dot(up) -- positive is turning left
	local speed = math.abs(forwardSpeed)
	if speed < 12 or math.abs(up.Y) < 0.6 then
		state.yaw = yaw
		return
	end
	local slip = math.atan2(math.abs(sideSpeed), speed)
	-- Oversteer: the car's rotating the same way its back is sliding out (turning left with the back swinging
	-- right shows as yaw > 0 with the car moving to its right)
	local oversteer = slip > SLIDING_FROM and sideSpeed * yaw * math.sign(forwardSpeed) > 0
	-- (Limiting how fast the rotation could change on every turn made swapping from left to right lag by half a
	-- second, measured 18 Oct 2026: only slides are slowed down now)
	local newYaw = yaw
	if oversteer then
		if math.abs(newYaw) > math.abs(state.yaw) then
			newYaw = state.yaw + math.clamp(newYaw - state.yaw, -MAX_YAW_ACCELERATION * dt, MAX_YAW_ACCELERATION * dt)
		end
		local cap = math.clamp(2.6 - speed / 160, 1.2, 2.6)
		newYaw = math.clamp(newYaw, -cap, cap)
		local _, steer = readPedals()
		if newYaw * steer > 0 then
			local angle = math.clamp((slip - math.rad(20)) / math.rad(25), 0, 1)
			newYaw -= newYaw * math.min(1, COUNTERSTEER_CATCH * math.abs(steer) * angle * dt)
		end
		if slip > SPIN_GUARD then
			newYaw -= newYaw * math.min(1, 2.5 * dt)
		end
	end
	if newYaw ~= yaw then
		seat.AssemblyAngularVelocity = spin + up * (newYaw - yaw)
	end
	state.yaw = newYaw
end

local function stopDriving()
	if driving then
		driving:Disconnect()
		driving = nil
	end
	chassisSeat = nil
	unbindKeys()
	if normalMinZoom then
		player.CameraMinZoomDistance = normalMinZoom
		normalMinZoom = nil
	end
end

local function startDriving(seat: VehicleSeat)
	if driving or chassisSeat == seat then
		return
	end
	local car = seat.Parent :: Model
	-- A-Chassis cars drive themselves (their own script runs on your device while you're in the seat): we just
	-- add the horn and getting out, and keep Space from making you jump out
	if car:GetAttribute("ChassisCar") then
		chassisSeat = seat
		bindKeys(false)
		normalMinZoom = player.CameraMinZoomDistance
		local assist = { yaw = 0 }
		driving = RunService.Heartbeat:Connect(function(dt)
			driftAssist(seat, assist, dt)
		end)
		return
	end
	local chassis = car.PrimaryPart
	if not chassis or not car:GetAttribute("ArcadeHandling") then
		-- Either not one of our cars (bought cars come with their own driving scripts), or the car hasn't
		-- finished arriving on this device yet: the check further down tries again shortly
		return
	end
	bindKeys(true)

	-- Keep the camera far enough back to see the whole vehicle: a bus is over twice as long as a car
	normalMinZoom = player.CameraMinZoomDistance
	player.CameraMinZoomDistance = math.max(normalMinZoom :: number, chassis.Size.Z * 1.25)

	local topSpeed = stat(car, "TopSpeed", CAR.TopSpeed)
	local reverseSpeed = stat(car, "ReverseSpeed", CAR.ReverseSpeed)
	local acceleration = stat(car, "Acceleration", CAR.Acceleration)
	local wheelRadius = stat(car, "WheelRadius", CAR.WheelRadius)
	local brakes = stat(car, "Brakes", CAR.BrakeDeceleration)
	local grip = stat(car, "Grip", CAR.CorneringGrip)
	local box = Gearbox.boxFor(car)
	local topGear = #box.ratios

	local physics = RaycastCar.new(car, chassis, {
		grip = grip,
		wheelRadius = wheelRadius,
		maxLock = STEERING_LOCK,
	}, { car, player.Character :: Instance })

	local steer = 0
	local gear = 1
	local shiftUntil = 0 -- no drive until then, while a gear change happens
	local lastShift = 0
	local upshifts, downshifts = 0, 0

	local connection = RunService.PreSimulation:Connect(function(dt)
		local now = os.clock()
		local forwardSpeed = chassis.AssemblyLinearVelocity:Dot(chassis.CFrame.LookVector)
		local throttle, steerInput = readPedals()

		-- Turn the steering wheel gradually, even with a keyboard, and let it come back to the middle quicker
		-- than it goes out, so swapping from left to right doesn't lag
		local returning = math.abs(steerInput) < math.abs(steer) or steerInput * steer < 0
		steer = approach(steer, steerInput, (if returning then 7 else 4) * dt)

		-- The gearbox: reverse when going backwards, otherwise change up near the redline on the accelerator
		-- and down when the revs drop
		local reversing = forwardSpeed < -1 or (throttle < 0 and forwardSpeed <= START_SPEED)
		if reversing then
			gear = 0
		elseif gear == 0 then
			gear = 1
		end
		local rpm = Gearbox.rpm(box, forwardSpeed, gear, topSpeed, reverseSpeed)
		-- Changing down goes quicker than changing up, so it can drop a few gears when you brake hard
		if gear >= 1 and now > lastShift + (if throttle > 0.1 then 0.35 else 0.16) then
			if throttle > 0.1 and rpm >= Gearbox.UP_AT and gear < topGear then
				gear += 1
				shiftUntil = now + box.shiftTime
				lastShift = now
				upshifts += 1
			elseif rpm < (if throttle < 0 then Gearbox.DOWN_BRAKING else Gearbox.DOWN_AT) and gear > 1 then
				gear -= 1
				lastShift = now
				downshifts += 1
			end
			rpm = Gearbox.rpm(box, forwardSpeed, gear, topSpeed, reverseSpeed)
		end
		local shifting = now < shiftUntil

		-- What the driver's asking of the car
		handbrake = handbrakeHeld()
		local drive = if shifting then 0 else throttle -- what the engine's actually doing, for the sounds
		local input: RaycastCar.Input = { steer = steer, drive = 0, brake = 0, coast = 1.5, handbrake = handbrake }
		if throttle > 0 then
			if forwardSpeed < -START_SPEED then
				input.brake = brakes * throttle -- rolling backwards: brake first
			elseif shifting then
				input.coast = CAR.CoastDeceleration
			else
				-- Each gear pulls less hard than the one before, and can't go past its own top speed (the rev
				-- limiter) until it changes up
				local pull = acceleration * box.pull[math.max(gear, 1)] * Gearbox.torque(rpm)
				local limit = if gear >= topGear then topSpeed else math.min(topSpeed, Gearbox.gearTop(box, gear, topSpeed) * 1.03)
				input.drive = if forwardSpeed < limit then pull * throttle else 0
			end
		elseif throttle < 0 then
			if forwardSpeed > START_SPEED then
				input.brake = brakes * -throttle -- moving forwards: brake first
				drive = 0
			else
				input.drive = if forwardSpeed > -reverseSpeed then -acceleration * 0.5 * -throttle else 0
				drive = -throttle
			end
		else
			-- Lifting off: the engine slows the car, more so at high revs
			input.coast = CAR.CoastDeceleration + 9 * Gearbox.share(rpm)
		end
		if handbrake then
			drive = math.max(drive, 0)
		end

		local result = physics:step(dt, input)

		-- For the sounds (VehicleEffects): attributes set here only exist on this device. Spinning wheels rev
		-- the engine past what the car's speed says.
		local engineRpm = if result.spinning and throttle > 0 then math.min(Gearbox.REDLINE, rpm + 2200 * throttle) else rpm
		car:SetAttribute("Rpm", math.round(engineRpm))
		car:SetAttribute("Gear", gear)
		car:SetAttribute("Drive", math.round(drive * 100) / 100)
		car:SetAttribute("Throttle", math.round(throttle * 100) / 100)
		car:SetAttribute("Upshifts", upshifts)
		car:SetAttribute("Downshifts", downshifts)
		car:SetAttribute("Spinning", result.spinning)
		local braking = throttle < 0 and forwardSpeed > 20
		car:SetAttribute("Slip", math.round(result.slip + (if result.spinning then 18 else 0) + (if braking then 6 else 0)))
	end)
	driving = {
		Disconnect = function()
			connection:Disconnect()
			physics:destroy()
		end,
	} :: any
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

-- Straight after spawning you can be put in the seat a moment before the whole car has arrived on your
-- device, and then the driving never started (the car just sat there). So keep checking: if you're in a
-- driver's seat and the car isn't being driven yet, start.
task.spawn(function()
	while true do
		task.wait(0.4)
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local seat = humanoid and humanoid.SeatPart
		if seat and seat:IsA("VehicleSeat") and not driving then
			startDriving(seat)
		end
	end
end)

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

-- nil means the vehicle keeps its own colours
local function paintOf(vehicle: Vehicle): Color3?
	local picked = player:GetAttribute("Paint_" .. vehicle.id)
	return Vehicles.paintColour(vehicle, if typeof(picked) == "number" then picked else nil)
end

local function cash(): number
	local value = player:GetAttribute("Cash")
	return if typeof(value) == "number" then value else 0
end

-- Repaints a vehicle's body panels, or puts its original colours back when `colour` is nil
local function recolour(model: Instance, colour: Color3?)
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") and descendant:GetAttribute("Paint") then
			local original = descendant:GetAttribute("BaseColour")
			if colour then
				descendant.Color = colour
			elseif typeof(original) == "Color3" then
				descendant.Color = original
			end
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
put(folder7, "LocalScript", "ParkedCars", [[
-- Fills the parking spaces near you with parked cars, like the streets in Birmingham Vehicle Simulator.
-- The map lists every space (ReplicatedStorage → MapInfo → ParkedCars, written by LondonMap). Only the ones
-- near your camera get a car, and cars are reused as you drive along, so thousands of spaces cost very little.
-- They're on your device only. Each space always gets the same car and colour, so every player sees the
-- same street. You can bump into them, but they don't move.

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Vehicles = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Vehicles"))

local SHOW_WITHIN = 260 -- studs from the camera
local HIDE_BEYOND = 320
local MOST_CARS = 45
local CELL = 200 -- spaces are sorted into squares this big, so finding the near ones is quick

-- Everyday colours for parked cars (indexes into Vehicles.Paints)
local PARKED_PAINTS = { 1, 1, 2, 2, 3, 3, 4, 5, 7, 8, 9, 13 }

local mapInfo = ReplicatedStorage:WaitForChild("MapInfo")
local data = mapInfo:WaitForChild("ParkedCars") :: StringValue
local models = ReplicatedStorage:WaitForChild("VehicleModels")

type Spot = { position: Vector3, cframe: CFrame, template: string, paint: number }

local spots: { Spot } = {}
local cells: { [string]: { number } } = {}

local function cellKey(x: number, z: number): string
	return math.floor(x / CELL) .. "," .. math.floor(z / CELL)
end

-- The cars people park: everything on the Car team that has a model
local templates: { string } = {}
for _, vehicle in Vehicles.forTeam("Car") do
	if not vehicle.hero and models:WaitForChild(vehicle.id, 10) then
		table.insert(templates, vehicle.id)
	end
end
if #templates == 0 then
	return
end

local ok, decoded = pcall(function(): any
	return HttpService:JSONDecode(data.Value)
end)
if not ok or type(decoded) ~= "table" then
	return
end
for index, entry in decoded do
	local position = Vector3.new(entry[1], entry[2], entry[3])
	local spot: Spot = {
		position = position,
		cframe = CFrame.new(position) * CFrame.Angles(0, math.rad(entry[4]), 0),
		-- The same car and colour in each space every time, without storing them
		template = templates[(index * 7919) % #templates + 1],
		paint = PARKED_PAINTS[(index * 104729) % #PARKED_PAINTS + 1],
	}
	table.insert(spots, spot)
	local key = cellKey(position.X, position.Z)
	cells[key] = cells[key] or {}
	table.insert(cells[key], index)
end

local folder = Instance.new("Folder")
folder.Name = "ParkedCars"
folder.Parent = Workspace

local pools: { [string]: { Model } } = {}
local active: { [number]: Model } = {}

local function recolour(model: Model, colour: Color3?)
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") and part:GetAttribute("Paint") then
			local original = part:GetAttribute("BaseColour")
			if colour then
				part.Color = colour
			elseif typeof(original) == "Color3" then
				part.Color = original
			end
		end
	end
end

local function take(spot: Spot): Model?
	local pool = pools[spot.template]
	local model: Model
	if pool and #pool > 0 then
		model = table.remove(pool) :: Model
	else
		local source = models:FindFirstChild(spot.template)
		if not source then
			return nil
		end
		model = source:Clone() :: Model
		-- The display copies can't be touched; parked cars should be solid
		for _, name in { "Chassis", "Hull" } do
			local part = model:FindFirstChild(name)
			if part and part:IsA("BasePart") then
				part.CanCollide = true
			end
		end
	end
	local vehicle = Vehicles.ById[spot.template]
	local keepColours = vehicle and (vehicle.fixedPaint or vehicle.livery == "Taxi")
	local paint = if keepColours then nil else Vehicles.Paints[spot.paint].colour
	recolour(model, paint)
	model:PivotTo(spot.cframe)
	model.Parent = folder
	return model
end

local function give(index: number)
	local model = active[index]
	if not model then
		return
	end
	active[index] = nil
	model.Parent = nil
	local template = spots[index].template
	pools[template] = pools[template] or {}
	table.insert(pools[template], model)
end

local camera = Workspace.CurrentCamera
while true do
	local focus = camera.Focus.Position
	-- Put away cars that are now far behind
	for index in active do
		if (spots[index].position - focus).Magnitude > HIDE_BEYOND then
			give(index)
		end
	end
	-- Find the nearby spaces, nearest first
	local near: { { number } } = {}
	local reach = math.ceil(SHOW_WITHIN / CELL)
	local cx, cz = math.floor(focus.X / CELL), math.floor(focus.Z / CELL)
	for i = cx - reach, cx + reach do
		for j = cz - reach, cz + reach do
			local list = cells[i .. "," .. j]
			if list then
				for _, index in list do
					local distance = (spots[index].position - focus).Magnitude
					if distance <= SHOW_WITHIN then
						table.insert(near, { index, distance })
					end
				end
			end
		end
	end
	table.sort(near, function(a, b)
		return a[2] < b[2]
	end)
	local count = 0
	for _ in active do
		count += 1
	end
	-- A few at a time, nearest first: making lots of cars at once made the game stutter when you drove
	-- into a new area
	local added = 0
	for _, entry in near do
		local index = entry[1]
		if not active[index] then
			if count >= MOST_CARS or added >= 2 then
				break
			end
			local model = take(spots[index])
			if model then
				active[index] = model
				count += 1
				added += 1
			end
		end
	end
	task.wait(0.1)
end
]])
put(folder7, "LocalScript", "Pedestrians", [=[
-- People walking along the pavements near you, so the streets feel alive like Birmingham Vehicle Simulator.
-- They're on your device only, so they cost the server nothing. The server makes the people
-- (ReplicatedStorage → PedestrianModels, see the Pedestrians module) and LondonMap lists the pavements
-- (MapInfo → Pavements: each one a line of points along the middle of a pavement). Up to MOST_PEOPLE walk
-- near the camera; they turn round at the end of their pavement and disappear when you're far away.

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local MOST_PEOPLE = 20
local SHOW_WITHIN = 200 -- studs from the camera
local HIDE_BEYOND = 260
local CELL = 200
local WALK_ANIMATION = "rbxassetid://507777826" -- Roblox's own R15 walk
local PAVEMENT_TOP = 0.6

local mapInfo = ReplicatedStorage:WaitForChild("MapInfo")
local data = mapInfo:WaitForChild("Pavements") :: StringValue
local models = ReplicatedStorage:WaitForChild("PedestrianModels", 60)
if not models then
	return
end
-- The server makes them one at a time; wait until there are a few
for _ = 1, 40 do
	if #models:GetChildren() >= 4 then
		break
	end
	task.wait(0.25)
end
local templates = models:GetChildren()
if #templates == 0 then
	return
end

type Line = { points: { Vector3 }, dists: { number }, length: number }

local lines: { Line } = {}
local cells: { [string]: { number } } = {}

local function cellKey(x: number, z: number): string
	return math.floor(x / CELL) .. "," .. math.floor(z / CELL)
end

local ok, decoded = pcall(function(): any
	return HttpService:JSONDecode(data.Value)
end)
if not ok or type(decoded) ~= "table" then
	return
end
for _, flat in decoded do
	local points: { Vector3 }, dists: { number } = {}, {}
	for k = 1, #flat - 1, 2 do
		local p = Vector3.new(flat[k], PAVEMENT_TOP, flat[k + 1])
		table.insert(points, p)
		dists[#points] = if #points == 1 then 0 else dists[#points - 1] + (p - points[#points - 1]).Magnitude
	end
	if #points >= 2 and dists[#points] > 20 then
		table.insert(lines, { points = points, dists = dists, length = dists[#points] })
		local index = #lines
		local seen: { [string]: boolean } = {}
		for _, p in points do
			local key = cellKey(p.X, p.Z)
			if not seen[key] then
				seen[key] = true
				cells[key] = cells[key] or {}
				table.insert(cells[key], index)
			end
		end
	end
end
if #lines == 0 then
	return
end

-- Where along a line, and which way it runs there. `hint` is the segment last used, to save searching.
local function pointAt(line: Line, s: number, hint: number): (Vector3, Vector3, number)
	local k = math.clamp(hint, 2, #line.points)
	while k < #line.points and line.dists[k] < s do
		k += 1
	end
	while k > 2 and line.dists[k - 1] > s do
		k -= 1
	end
	local a, b = line.points[k - 1], line.points[k]
	local seg = line.dists[k] - line.dists[k - 1]
	local f = if seg > 1e-6 then math.clamp((s - line.dists[k - 1]) / seg, 0, 1) else 0
	return a:Lerp(b, f), (b - a).Unit, k
end

type Walker = {
	model: Model,
	root: BasePart,
	height: number,
	track: AnimationTrack?,
	line: Line,
	s: number,
	direction: number,
	speed: number,
	segment: number,
	sideStep: number,
}

local folder = Instance.new("Folder")
folder.Name = "Pedestrians"
folder.Parent = Workspace

local walkers: { Walker } = {}
local pool: { Walker } = {}
local random = Random.new()

local walkAnimation = Instance.new("Animation")
walkAnimation.AnimationId = WALK_ANIMATION

local function newWalker(): Walker?
	local template = templates[random:NextInteger(1, #templates)]
	local model = template:Clone() :: Model
	local root = model:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid then
		model:Destroy()
		return nil
	end
	root.Anchored = true
	local height = humanoid.HipHeight + root.Size.Y / 2
	model.Parent = folder
	local track: AnimationTrack? = nil
	local animator = humanoid:FindFirstChildOfClass("Animator") or Instance.new("Animator", humanoid)
	local loaded, result = pcall(function()
		return animator:LoadAnimation(walkAnimation)
	end)
	if loaded and result then
		track = result
		result.Looped = true
	end
	return {
		model = model,
		root = root,
		height = height,
		track = track,
		line = lines[1],
		s = 0,
		direction = 1,
		speed = 4,
		segment = 2,
		sideStep = 0,
	}
end

local function spawnOn(line: Line, s: number)
	local walker = table.remove(pool) or newWalker()
	if not walker then
		return
	end
	walker.line = line
	walker.s = s
	walker.direction = if random:NextNumber() < 0.5 then 1 else -1
	walker.speed = random:NextNumber(3.6, 5.2)
	walker.segment = 2
	walker.sideStep = random:NextNumber(-2.2, 2.2) -- not everyone walks down the exact middle
	walker.model.Parent = folder
	local track = walker.track
	if track then
		track:Play(0.2)
		track:AdjustSpeed(walker.speed / 11)
	end
	table.insert(walkers, walker)
end

local function putAway(index: number)
	local walker = table.remove(walkers, index)
	if not walker then
		return
	end
	if walker.track then
		walker.track:Stop(0)
	end
	walker.model.Parent = nil
	table.insert(pool, walker)
end

-- Walking, every frame
RunService.Heartbeat:Connect(function(dt)
	if #walkers == 0 then
		return
	end
	local parts: { BasePart } = {}
	local frames: { CFrame } = {}
	for _, walker in walkers do
		local line = walker.line
		walker.s += walker.direction * walker.speed * dt
		if walker.s >= line.length then
			walker.s = line.length
			walker.direction = -1
		elseif walker.s <= 0 then
			walker.s = 0
			walker.direction = 1
		end
		local p, along, k = pointAt(line, walker.s, walker.segment)
		walker.segment = k
		local facing = along * walker.direction
		local side = Vector3.new(-facing.Z, 0, facing.X)
		local at = p + side * walker.sideStep + Vector3.new(0, walker.height, 0)
		table.insert(parts, walker.root)
		table.insert(frames, CFrame.lookAt(at, at + facing))
	end
	Workspace:BulkMoveTo(parts, frames, Enum.BulkMoveMode.FireCFrameChanged)
end)

-- Adding people near the camera and taking away the ones left far behind, twice a second
local camera = Workspace.CurrentCamera
while true do
	local focus = camera.CFrame.Position
	for index = #walkers, 1, -1 do
		local walker = walkers[index]
		if (walker.root.Position - focus).Magnitude > HIDE_BEYOND then
			putAway(index)
		end
	end
	if #walkers < MOST_PEOPLE then
		local near: { number } = {}
		local reach = math.ceil(SHOW_WITHIN / CELL)
		local cx, cz = math.floor(focus.X / CELL), math.floor(focus.Z / CELL)
		for i = cx - reach, cx + reach do
			for j = cz - reach, cz + reach do
				local list = cells[i .. "," .. j]
				if list then
					for _, index in list do
						table.insert(near, index)
					end
				end
			end
		end
		local added = 0
		for _ = 1, 12 do
			if #near == 0 or #walkers >= MOST_PEOPLE or added >= 1 then
				break
			end
			local line = lines[near[random:NextInteger(1, #near)]]
			local s = random:NextNumber(0, line.length)
			local p = pointAt(line, s, 2)
			local distance = (p - focus).Magnitude
			if distance < SHOW_WITHIN and distance > 30 then
				spawnOn(line, s)
				added += 1
			end
		end
	end
	task.wait(0.25)
end
]=])
put(folder7, "ModuleScript", "RaycastCar", [[
-- How a car sits on its springs and grips the road, built to feel solid and catchable like Birmingham Vehicle
-- Simulator rather than twitchy like Roblox's physical wheels.
--
-- Each wheel casts a ray down to the road. A spring and damper hold the car up at its proper ride height (so it
-- rides bumps and leans naturally), and the tyre pushes on the road with forces we work out ourselves:
--   - sideways grip builds up smoothly with how much the tyre is slipping, peaks, then fades only a little past
--     the limit, so a slide grows gradually and can always be caught (real tyres behave like this; Roblox's
--     physical wheels go from full grip to none at once, which is why cars snapped into spins)
--   - each tyre has one budget of grip shared between cornering and accelerating or braking, so braking hard or
--     flooring it in a bend uses grip the tyre would otherwise corner with: that's how the back steps out when
--     you ask it to, and only then
--   - grip goes with the weight on the tyre, which moves about as the car brakes, accelerates and corners
-- All forces go through a VectorForce at each wheel hub, made on the driver's device (which runs the car's
-- physics), so nothing here touches the server. Driving works out the engine, gears and pedals and calls step.
--
-- Units: studs, seconds, studs per second per second. Grip and brakes are given as accelerations, not
-- friction coefficients, because Roblox's gravity is about 5.6 times real gravity at this game's scale: an honest
-- friction coefficient would give cars 5 g of grip.

local Workspace = game:GetService("Workspace")

local RaycastCar = {}
RaycastCar.__index = RaycastCar

-- The suspension: how bouncy (natural frequency, per second) and how damped. About 1.9 Hz and 0.45 feels like
-- a firm road car.
local SPRING_HZ = 1.9
local DAMPING_RATIO = 0.45
local RIDE_LENGTH = 1.2 -- studs from the top of the spring to the hub at ride height
local DROOP = 0.7 -- how far a wheel can drop below ride height before it leaves the road
local BUMP_STOP = 0.3 -- spring length where the bump stop takes over
local ANTI_ROLL = 0.6 -- anti-roll bars, as a share of the spring stiffness

-- The tyre's grip curve (a cut-down Pacejka "magic formula"): grip rises steeply to a peak at about 10 degrees
-- of slip and fades to about 85% when sliding sideways. The back fades a little more, so slides happen at the
-- back and can be held.
local CURVE_B = 10
local CURVE_C_FRONT = 1.45
local CURVE_C_REAR = 1.52
local SLIP_FLOOR = 4 -- studs/s: below this, slip angles are worked out as if moving this fast (no jitter at a stop)

local HANDBRAKE_GRIP = 0.6 -- share of sideways grip the rear tyres keep with the handbrake on

-- Stability: a slide may only rotate the car so fast. A grip-limited car turns at most at grip / speed; a slide is
-- allowed SLIDE_YAW times that (plus a little), so the back swings out properly but at a speed you can catch
-- with countersteer, instead of spinning round in half a second. Normal driving never reaches the limit.
local SLIDE_YAW = 1.15
local SLIDE_YAW_EXTRA = 0.2 -- radians per second
local STABILITY_RATE = 10 -- how firmly it holds the limit (per second)
-- Spin guard: once the car is more than SPIN_GUARD sideways, its rotation is damped, more the further round it
-- is, so a big slide that's left alone straightens up rather than swapping ends
local SPIN_GUARD = math.rad(30)
local SPIN_GUARD_RATE = 6
-- Traction control: in a big slide, spinning rear wheels get only this share of their grip as drive, so keeping
-- your foot in holds the slide rather than spinning the car round
local SLIDE_TRACTION = 0.6
local SLIDE_TRACTION_FROM = math.rad(20)
local DRAG = 3.5e-4 -- air resistance: deceleration = DRAG * speed^2

export type Stats = {
	grip: number, -- most sideways acceleration the tyres can make, studs/s²
	wheelRadius: number,
	maxLock: number, -- full steering lock, radians
}

export type Input = {
	steer: number, -- -1 full left to 1 full right (already smoothed)
	drive: number, -- acceleration the engine asks for through the driven (rear) wheels, studs/s², negative in reverse
	brake: number, -- deceleration asked of the brakes, studs/s²
	coast: number, -- engine braking and rolling resistance through the driven wheels, studs/s²
	handbrake: boolean,
}

export type Telemetry = {
	forwardSpeed: number,
	sideSpeed: number,
	wheelsDown: number,
	slip: number, -- how hard the tyres are scrubbing sideways (studs/s), for the squeal and smoke
	spinning: boolean, -- the rear wheels are spinning
	steerAngle: number,
}

type Wheel = {
	joint: Motor6D,
	hub: Vector3, -- hub position at ride height, in the chassis' own space
	front: boolean,
	left: boolean,
	attachment: Attachment,
	force: VectorForce,
	length: number, -- spring length last frame
	compression: number,
	spin: number,
	grounded: boolean,
}

export type Car = typeof(setmetatable({} :: {
	car: Model,
	chassis: BasePart,
	stats: Stats,
	wheels: { Wheel },
	drag: VectorForce,
	stability: Torque,
	turnInertia: number,
	contacts: { BasePart },
	rayParams: RaycastParams,
}, RaycastCar))

function RaycastCar.new(car: Model, chassis: BasePart, stats: Stats, ignore: { Instance }): Car
	local wheels: { Wheel } = {}
	for _, joint in chassis:GetChildren() do
		if joint:IsA("Motor6D") then
			local hub = joint.C0.Position
			local attachment = Instance.new("Attachment")
			attachment.Name = "SuspensionHub"
			attachment.Position = hub
			attachment.Parent = chassis
			local force = Instance.new("VectorForce")
			force.Name = "Suspension"
			force.Attachment0 = attachment
			force.RelativeTo = Enum.ActuatorRelativeTo.World
			force.ApplyAtCenterOfMass = false
			force.Force = Vector3.zero
			force.Parent = chassis
			table.insert(wheels, {
				joint = joint,
				hub = hub,
				front = hub.Z < 0,
				left = hub.X < 0,
				attachment = attachment,
				force = force,
				length = RIDE_LENGTH,
				compression = 0,
				spin = 0,
				grounded = false,
			})
		end
	end

	local centre = Instance.new("Attachment")
	centre.Name = "DragPoint"
	centre.Parent = chassis
	local drag = Instance.new("VectorForce")
	drag.Name = "Drag"
	drag.Attachment0 = centre
	drag.RelativeTo = Enum.ActuatorRelativeTo.World
	drag.ApplyAtCenterOfMass = true
	drag.Force = Vector3.zero
	drag.Parent = chassis

	local stability = Instance.new("Torque")
	stability.Name = "Stability"
	stability.Attachment0 = centre
	stability.RelativeTo = Enum.ActuatorRelativeTo.World
	stability.Torque = Vector3.zero
	stability.Parent = chassis
	-- How hard the car is to turn (it's the chassis box that carries the weight)
	local size = chassis.Size
	local turnInertia = chassis.AssemblyMass * (size.X * size.X + size.Z * size.Z) / 12

	-- The invisible balls that hold a parked car up get out of the springs' way while it's being driven
	local contacts: { BasePart } = {}
	for _, part in car:GetChildren() do
		if part:IsA("BasePart") and part.Name == "TyreContact" then
			part.CanCollide = false
			table.insert(contacts, part)
		end
	end

	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = ignore
	rayParams.IgnoreWater = true

	return setmetatable({
		car = car,
		chassis = chassis,
		stats = stats,
		wheels = wheels,
		drag = drag,
		stability = stability,
		turnInertia = turnInertia,
		contacts = contacts,
		rayParams = rayParams,
	}, RaycastCar)
end

-- How much of a tyre's grip it uses at a slip angle
local function curve(slip: number, c: number): number
	return math.sin(c * math.atan(CURVE_B * slip))
end

-- Moves the car on for this frame: suspension, tyres, steering, and the wheels you can see. Called before each
-- physics step with that step's length.
function RaycastCar.step(self: Car, dt: number, input: Input): Telemetry
	local chassis = self.chassis
	local stats = self.stats
	local cframe = chassis.CFrame
	local up = cframe.UpVector
	local look = cframe.LookVector
	local velocity = chassis.AssemblyLinearVelocity
	local forwardSpeed = velocity:Dot(look)
	local sideSpeed = velocity:Dot(cframe.RightVector)
	local mass = chassis.AssemblyMass
	local gravity = Workspace.Gravity
	local quarter = mass / 4

	-- Springs, from the car's weight each frame (so a passenger doesn't change how it rides)
	local omega = 2 * math.pi * SPRING_HZ
	local stiffness = quarter * omega * omega
	local damping = 2 * DAMPING_RATIO * omega * quarter
	local freeLength = RIDE_LENGTH + gravity / (omega * omega)
	local maxLength = RIDE_LENGTH + DROOP
	local radius = stats.wheelRadius
	local mu = stats.grip / gravity -- grip as a share of the tyre's load

	-- Steering: full lock when parking, less and less with speed (a little goes a long way at 60 mph). Steering
	-- into a slide gets as much lock as it takes to catch it.
	local speed = math.abs(forwardSpeed)
	local lock = stats.maxLock / (1 + speed / 33)
	local bodySlip = math.atan2(sideSpeed, math.max(speed, 1))
	if input.steer * bodySlip > 0 then
		lock = math.min(stats.maxLock, math.max(lock, math.abs(bodySlip) + math.rad(6)))
	end
	local steerAngle = input.steer * lock

	-- Pass 1: where each wheel meets the road, and how hard its spring pushes
	type Contact = { wheel: Wheel, hit: RaycastResult?, load: number }
	local contacts: { Contact } = {}
	local drivenDown = 0
	for _, wheel in self.wheels do
		local mount = cframe:PointToWorldSpace(wheel.hub + Vector3.new(0, RIDE_LENGTH, 0))
		local hit = Workspace:Raycast(mount, -up * (maxLength + radius), self.rayParams)
		local length = maxLength
		local load = 0
		if hit then
			length = math.clamp((hit.Position - mount).Magnitude - radius, 0, maxLength)
			local rate = (length - wheel.length) / dt
			load = stiffness * (freeLength - length) - damping * rate
			if length < BUMP_STOP then
				load += stiffness * 4 * (BUMP_STOP - length)
			end
			load = math.max(load, 0)
			if not wheel.front then
				drivenDown += 1
			end
		end
		wheel.length = length
		wheel.compression = if hit then freeLength - length else 0
		wheel.grounded = hit ~= nil
		table.insert(contacts, { wheel = wheel, hit = hit, load = load })
	end

	-- Anti-roll bars: share load between the two wheels on each axle as the car leans
	for _, a in contacts do
		for _, b in contacts do
			if a.wheel.front == b.wheel.front and a.wheel.left and not b.wheel.left and a.hit and b.hit then
				local transfer = ANTI_ROLL * stiffness * (a.wheel.compression - b.wheel.compression)
				a.load = math.max(a.load + transfer, 0)
				b.load = math.max(b.load - transfer, 0)
			end
		end
	end

	-- Pass 2: the tyre forces
	local slip = 0
	local spinning = false
	for _, contact in contacts do
		local wheel = contact.wheel
		local hit = contact.hit
		local total = Vector3.zero
		local vLong = forwardSpeed
		if hit then
			local normal = hit.Normal
			local heading = if wheel.front then CFrame.fromAxisAngle(up, -steerAngle):VectorToWorldSpace(look) else look
			local forward = (heading - normal * heading:Dot(normal)).Unit
			local side = forward:Cross(normal)
			local pointVelocity = chassis:GetVelocityAtPosition(hit.Position)
			vLong = pointVelocity:Dot(forward)
			local vLat = pointVelocity:Dot(side)
			local load = contact.load
			local budget = mu * load -- most force this tyre can make, in any direction

			-- Sideways: from the slip angle, but never more than would stop the sideways motion this frame
			local slipAngle = math.atan2(vLat, math.max(math.abs(vLong), SLIP_FLOOR))
			local lateral = -budget * curve(slipAngle, if wheel.front then CURVE_C_FRONT else CURVE_C_REAR)
			local stopSideways = math.abs(vLat) * quarter / dt
			lateral = math.clamp(lateral, -stopSideways, stopSideways)

			-- Along the wheel: the engine (rear wheels), the brakes (more at the front), engine braking and the
			-- handbrake
			local direction = if vLong > 0.5 then 1 elseif vLong < -0.5 then -1 else 0
			local longitudinal = 0
			if not wheel.front and drivenDown > 0 then
				longitudinal += mass * input.drive / drivenDown
				longitudinal -= direction * mass * input.coast / drivenDown
			end
			local brakeShare = if wheel.front then 0.3 else 0.2
			local braking = mass * input.brake * brakeShare
			local stopRolling = math.abs(vLong) * quarter / dt
			if braking > 0 then
				longitudinal -= if direction ~= 0 then direction * math.min(braking, stopRolling) else vLong * quarter / dt
			end
			local locked = input.handbrake and not wheel.front
			if locked then
				longitudinal = -direction * math.min(budget * 0.9, stopRolling)
				lateral *= HANDBRAKE_GRIP
			end
			-- Standing still with nothing pressed: the tyres hold the car where it is
			if input.drive == 0 and math.abs(vLong) < 1 then
				longitudinal = -vLong * quarter / dt
			end

			-- One grip budget for both directions. Asking a rear tyre for more drive than it can take spins it,
			-- and a spinning tyre has little sideways grip left: that's the power slide.
			local wanted = math.sqrt(longitudinal * longitudinal + lateral * lateral)
			if wanted > budget and budget > 0 then
				if not wheel.front and not locked and math.abs(longitudinal) > budget * 0.9 and input.drive ~= 0 then
					spinning = true
					local share = if math.abs(bodySlip) > SLIDE_TRACTION_FROM then SLIDE_TRACTION else 0.85
					longitudinal = math.sign(longitudinal) * budget * share
					lateral = math.sign(lateral) * math.min(math.abs(lateral), math.sqrt(budget * budget - longitudinal * longitudinal) * 0.7)
				else
					local scale = budget / wanted
					longitudinal *= scale
					lateral *= scale
				end
			end

			total = up * load + forward * longitudinal + side * lateral
			if not wheel.front and math.abs(slipAngle) > 0.12 then
				slip += math.abs(vLat)
			end
			if locked and math.abs(vLong) > 5 then
				slip += 8
			end
		end
		wheel.force.Force = total

		-- The wheel you see: up and down with the spring, turned by the steering, rolling with the road
		local spinRate = vLong / radius + (if spinning and not wheel.front then 25 * math.sign(input.drive) else 0)
		if input.handbrake and not wheel.front then
			spinRate = 0
		end
		wheel.spin -= spinRate * dt
		wheel.joint.Transform = CFrame.new(0, RIDE_LENGTH - wheel.length, 0)
			* CFrame.Angles(0, if wheel.front then -steerAngle else 0, 0)
			* CFrame.Angles(wheel.spin, 0, 0)
	end

	self.drag.Force = -velocity * velocity.Magnitude * DRAG * mass

	-- Stability: hold a slide's rotation to a speed that can be caught
	local yaw = chassis.AssemblyAngularVelocity:Dot(up)
	local limit = SLIDE_YAW * stats.grip / math.max(speed, 12) + SLIDE_YAW_EXTRA
	local excess = math.abs(yaw) - limit
	local correction = 0
	if excess > 0 and speed > 8 then
		correction -= math.sign(yaw) * excess * STABILITY_RATE
	end
	local sideways = math.abs(bodySlip)
	if sideways > SPIN_GUARD and speed > 8 then
		correction -= yaw * SPIN_GUARD_RATE * math.min((sideways - SPIN_GUARD) / SPIN_GUARD, 1)
	end
	self.stability.Torque = up * correction * self.turnInertia

	local down = 0
	for _, wheel in self.wheels do
		if wheel.grounded then
			down += 1
		end
	end
	return {
		forwardSpeed = forwardSpeed,
		sideSpeed = sideSpeed,
		wheelsDown = down,
		slip = slip,
		spinning = spinning,
		steerAngle = steerAngle,
	}
end

-- Takes the forces away and puts the wheels back, when the driver gets out
function RaycastCar.destroy(self: Car)
	for _, wheel in self.wheels do
		wheel.force:Destroy()
		wheel.attachment:Destroy()
		wheel.joint.Transform = CFrame.identity
	end
	local point = self.drag.Attachment0
	self.drag:Destroy()
	self.stability:Destroy()
	if point then
		point:Destroy()
	end
	for _, part in self.contacts do
		part.CanCollide = true
	end
end

return RaycastCar
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
put(folder7, "LocalScript", "VehicleEffects", [[
-- Engine sounds and body movement for every vehicle near you, on your device only.
--   Sounds: the engine idles and revs with the rpm, the turbo whines and the blow-off valve hisses when it
--   changes up. Cars with an EngineSound profile (see EngineSounds) play real engine recordings blended by rpm
--   instead, start up when someone gets in, and fart and burble with recorded sounds. Cars with the Pops attribute "brap" on every flat-out upshift, and crackle and pop when you
--   lift off, with flames out of the exhaust. Tyres squeal when they slide or you brake hard, and the horn
--   sounds while the driver holds it (the server sets the Horn attribute, see Cars).
--   Body: the body squats when you accelerate, dips its nose when you brake and leans in corners, on the
--   BodyJoint CarBuilder hangs the body off (only cars with a detailed body have one).
-- Sounds made on a device are only heard on that device, so every player's device does this for every car.
-- For the car you're driving it reads what Driving says the engine is doing (Rpm, Gear, Drive, Throttle,
-- Upshifts, Downshifts, Slip); for everyone else's car it works it out from how the car is moving (see Gearbox.guess).

local ContentProvider = game:GetService("ContentProvider")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local EngineSounds = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("EngineSounds"))
local Gearbox = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Gearbox"))

local player = Players.LocalPlayer

local HEAR_WITHIN = 240 -- studs from the camera
local FORGET_BEYOND = 300
local MOST_ENGINES = 10 -- the nearest cars get sound, the rest are too far off to matter

local SOUNDS = {
	idle = "rbxassetid://7588250185",
	rev = "rbxassetid://7588254585",
	whine = "rbxassetid://404779487",
	skid = "rbxassetid://435752381",
	horn = "rbxassetid://9029412098",
	pop = "rbxassetid://810616601", -- a double bang in the first 0.15 seconds, then silence
	blowOff = "rbxassetid://4940167544",
}
local BANGS = 10 -- pop sounds kept ready on each car that pops, played in turn so they can overlap

-- A new sound takes about 0.3 seconds to load before it plays, which makes a pop late and a brap a mess.
-- So every car keeps its pop and blow-off sounds loaded and ready, and these get loaded once up front.
task.spawn(function()
	local loading = {}
	local ids = EngineSounds.allIds()
	for _, id in SOUNDS :: { [string]: string } do
		table.insert(ids, id)
	end
	for _, id in ids do
		local sound = Instance.new("Sound")
		sound.SoundId = id
		table.insert(loading, sound)
	end
	pcall(function()
		ContentProvider:PreloadAsync(loading)
	end)
end)

type Engine = {
	car: Model,
	chassis: BasePart,
	seat: VehicleSeat?,
	joint: Motor6D?,
	exhausts: { Attachment },
	box: Gearbox.Box,
	profile: EngineSounds.Profile?, -- real engine recordings, for cars that have them
	loops: { Sound }, -- the profile's recordings, playing while the engine runs
	farts: { Sound }, -- the profile's upshift braps, ready-loaded
	burble: Sound?,
	startup: Sound?,
	startedAt: number,
	smoke: { ParticleEmitter }, -- tyre smoke at the rear wheels
	idle: Sound?,
	rev: Sound?,
	whine: Sound?,
	skid: Sound?,
	horn: Sound?,
	bangs: { Sound }, -- ready-loaded pop sounds (cars that pop only)
	nextBang: number,
	bangPlays: { [Sound]: number }, -- counts plays, so a delayed stop doesn't cut off a newer pop
	blowOff: Sound?,
	-- what the engine is doing
	rpm: number,
	gear: number,
	upshifts: number,
	downshifts: number,
	lastPedal: number, -- how far the accelerator was down last frame
	crackleUntil: number,
	nextPop: number,
	blipUntil: number,
	brapUntil: number, -- engine sound cut while it braps
	lastUpshift: number,
	-- how the car is moving
	lastSpeed: number,
	accel: number,
	pitch: number,
	pitchSpeed: number,
	roll: number,
	rollSpeed: number,
}

local engines: { [Model]: Engine } = {}
local random = Random.new()

local function newSound(id: string, parent: Instance, looped: boolean, volume: number): Sound
	local sound = Instance.new("Sound")
	sound.SoundId = id
	sound.Looped = looped
	sound.Volume = volume
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMinDistance = 14
	sound.RollOffMaxDistance = HEAR_WITHIN
	sound.Parent = parent
	return sound
end

-- One bang from the exhaust, on the next ready pop sound. `cutAfter` stops it early (seconds).
local function bang(engine: Engine, volume: number, speed: number, cutAfter: number)
	local bangs = engine.bangs
	if #bangs == 0 then
		return
	end
	local sound = bangs[engine.nextBang]
	engine.nextBang = engine.nextBang % #bangs + 1
	sound:Stop()
	sound.Volume = volume
	sound.PlaybackSpeed = speed
	sound.TimePosition = 0
	sound:Play()
	local plays = (engine.bangPlays[sound] or 0) + 1
	engine.bangPlays[sound] = plays
	task.delay(cutAfter, function()
		if engine.bangPlays[sound] == plays then
			sound:Stop()
		end
	end)
end

-- A flame out of each exhaust and a flash of orange light, for a split second
local function flame(engine: Engine, big: boolean)
	for _, tip in engine.exhausts do
		local emitter = tip:FindFirstChild("Flame") :: ParticleEmitter?
		if emitter then
			emitter:Emit(if big then 9 else 5)
		end
		local light = tip:FindFirstChild("Glow") :: PointLight?
		if light then
			light.Brightness = if big then 6 else 3.5
			light.Enabled = true
			task.delay(0.07, function()
				light.Enabled = false
			end)
		end
	end
end

local function pop(engine: Engine, big: boolean)
	local volume = if big then random:NextNumber(1.3, 1.7) else random:NextNumber(0.75, 1.15)
	local speed = if big then random:NextNumber(0.8, 0.95) else random:NextNumber(0.95, 1.35)
	bang(engine, volume, speed, 0.35)
	flame(engine, big)
end

-- The "brap" a sporty straight-six makes on a flat-out gear change: the ignition cuts for a split second
-- and the exhaust fires off a quick, deep burst of bangs, with a flame
local BRAP_GAPS = { 0, 0.03, 0.058, 0.09, 0.118, 0.15 }
local function brap(engine: Engine)
	engine.brapUntil = os.clock() + 0.2
	local deep = random:NextNumber(0.68, 0.8)
	for i, gap in BRAP_GAPS do
		task.delay(gap, function()
			if engine.chassis.Parent then
				bang(engine, random:NextNumber(1.4, 1.8), deep + random:NextNumber(-0.04, 0.06), 0.2)
				if i % 2 == 1 then
					flame(engine, i == 1)
				end
			end
		end)
	end
end

-- The recorded brap, for cars with real engine sounds: a random one of the profile's, with flames
local function fart(engine: Engine)
	local farts = engine.farts
	engine.brapUntil = os.clock() + 0.18
	local sound = farts[random:NextInteger(1, #farts)]
	sound.PlaybackSpeed = random:NextNumber(0.92, 1.05)
	sound.TimePosition = 0
	sound:Play()
	for i, gap in { 0, 0.06, 0.12 } do
		task.delay(gap, function()
			if engine.chassis.Parent then
				flame(engine, i == 1)
			end
		end)
	end
end

-- Tyre smoke at each rear wheel, by the road, made thicker the harder the tyres slide or spin
local function addSmoke(chassis: BasePart): { ParticleEmitter }
	local emitters = {}
	for _, joint in chassis:GetChildren() do
		local hub = if joint:IsA("Motor6D") and not joint:GetAttribute("Steers") then joint.Part1 else nil
		if hub then
			local spot = Instance.new("Attachment")
			spot.Name = "TyreSmoke"
			spot.WorldPosition = hub.Position - chassis.CFrame.UpVector * 0.9
			spot.Parent = hub
			local emitter = Instance.new("ParticleEmitter")
			emitter.Texture = "rbxasset://textures/particles/smoke_main.dds"
			emitter.Rate = 0
			emitter.Lifetime = NumberRange.new(1.2, 2.2)
			emitter.Speed = NumberRange.new(1.5, 4)
			emitter.SpreadAngle = Vector2.new(60, 60)
			emitter.EmissionDirection = Enum.NormalId.Top
			emitter.Drag = 1.5
			emitter.Acceleration = Vector3.new(0, 1.2, 0)
			emitter.RotSpeed = NumberRange.new(-40, 40)
			emitter.Rotation = NumberRange.new(0, 360)
			emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.5), NumberSequenceKeypoint.new(1, 9) })
			emitter.Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.55),
				NumberSequenceKeypoint.new(0.3, 0.7),
				NumberSequenceKeypoint.new(1, 1),
			})
			emitter.Color = ColorSequence.new(Color3.fromRGB(225, 225, 228))
			emitter.LightInfluence = 1
			emitter.Parent = spot
			table.insert(emitters, emitter)
		end
	end
	return emitters
end

local function addFlames(tip: Attachment)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "Flame"
	emitter.Texture = "rbxasset://textures/particles/fire_main.dds"
	emitter.EmissionDirection = Enum.NormalId.Back -- out of the back of the car
	emitter.Rate = 0
	emitter.Lifetime = NumberRange.new(0.06, 0.13)
	emitter.Speed = NumberRange.new(10, 18)
	emitter.SpreadAngle = Vector2.new(12, 12)
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.55), NumberSequenceKeypoint.new(1, 0.15) })
	emitter.Color = ColorSequence.new(Color3.fromRGB(120, 170, 255), Color3.fromRGB(255, 120, 30))
	emitter.LightEmission = 1
	emitter.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) })
	emitter.Parent = tip
	local light = Instance.new("PointLight")
	light.Name = "Glow"
	light.Color = Color3.fromRGB(255, 140, 50)
	light.Range = 10
	light.Enabled = false
	light.Parent = tip
end

local function number(car: Instance, name: string, default: number): number
	local value = car:GetAttribute(name)
	return if typeof(value) == "number" then value else default
end

local function newEngine(car: Model): Engine?
	local chassis = car.PrimaryPart
	if not chassis then
		return nil
	end
	local bodyRoot = car:FindFirstChild("BodyRoot")
	local joint = bodyRoot and bodyRoot:FindFirstChild("BodyJoint")
	local pops = car:GetAttribute("Pops") == true
	local exhausts: { Attachment } = {}
	if bodyRoot then
		for _, child in bodyRoot:GetChildren() do
			if child:IsA("Attachment") and child.Name:sub(1, 7) == "Exhaust" then
				table.insert(exhausts, child)
				if pops then
					addFlames(child)
				end
			end
		end
	end
	local bangs: { Sound } = {}
	if pops then
		for _ = 1, BANGS do
			table.insert(bangs, newSound(SOUNDS.pop, chassis, false, 1))
		end
	end
	local profileName = car:GetAttribute("EngineSound")
	local profile = if typeof(profileName) == "string" then EngineSounds.Profiles[profileName] else nil
	local farts: { Sound } = {}
	local burble, startup = nil, nil
	if profile then
		local fartIds: { string } = profile.farts or {}
		for _, id in fartIds do
			table.insert(farts, newSound(id, chassis, false, profile.fartVolume or 2))
		end
		burble = if profile.burble then newSound(profile.burble, chassis, false, 1.3) else nil
		startup = if profile.startup then newSound(profile.startup, chassis, false, 1.4) else nil
	end
	return {
		car = car,
		chassis = chassis,
		seat = (car:FindFirstChild("DriverSeat") or car:FindFirstChild("DriveSeat")) :: VehicleSeat?,
		joint = if joint and joint:IsA("Motor6D") then joint else nil,
		exhausts = exhausts,
		box = Gearbox.boxFor(car),
		profile = profile,
		loops = {},
		farts = farts,
		burble = burble,
		startup = startup,
		startedAt = 0,
		smoke = addSmoke(chassis),
		bangs = bangs,
		nextBang = 1,
		bangPlays = {},
		blowOff = if number(car, "EngineVolume", 1) > 0 then newSound(SOUNDS.blowOff, chassis, false, 0.4) else nil,
		rpm = Gearbox.IDLE,
		gear = 1,
		upshifts = number(car, "Upshifts", 0),
		downshifts = number(car, "Downshifts", 0),
		lastPedal = 0,
		crackleUntil = 0,
		nextPop = 0,
		blipUntil = 0,
		brapUntil = 0,
		lastUpshift = 0,
		lastSpeed = 0,
		accel = 0,
		pitch = 0,
		pitchSpeed = 0,
		roll = 0,
		rollSpeed = 0,
	}
end

local function startSounds(engine: Engine)
	if engine.whine then
		return
	end
	local volume = number(engine.car, "EngineVolume", 1)
	local chassis = engine.chassis
	local function loop(id: string): Sound
		local sound = newSound(id, chassis, true, 0)
		sound:Play()
		return sound
	end
	local profile = engine.profile
	if profile then
		-- Real recordings: all of them play all the time, and the mix picks the right ones for the revs.
		-- The engine starts up first, with the idle fading in behind it.
		for _, recording in profile.loops do
			table.insert(engine.loops, loop(recording.id))
		end
		engine.startedAt = os.clock()
		local startup = engine.startup
		if startup then
			startup.TimePosition = 0
			startup:Play()
		end
	elseif volume > 0 then
		engine.idle = loop(SOUNDS.idle)
		engine.rev = loop(SOUNDS.rev)
	end
	engine.whine = loop(SOUNDS.whine)
	engine.skid = loop(SOUNDS.skid)
end

local function stopSounds(engine: Engine)
	for _, emitter in engine.smoke do
		emitter.Rate = 0
	end
	for _, sound in engine.loops do
		sound:Destroy()
	end
	table.clear(engine.loops)
	if engine.burble then
		engine.burble:Stop()
	end
	for _, key in { "idle", "rev", "whine", "skid", "horn" } do
		local sound = (engine :: any)[key] :: Sound?
		if sound then
			sound:Destroy()
			;(engine :: any)[key] = nil
		end
	end
end

-- The values A-Chassis keeps about the car you're driving (revs, gear, throttle), in its screen. There can be
-- old screens left over from cars you drove before, so it's the one whose Car points at this car.
local function aChassisValues(car: Model): Instance?
	local gui = player:FindFirstChild("PlayerGui")
	for _, interface in if gui then gui:GetChildren() else {} do
		local owner = interface.Name == "A-Chassis Interface" and interface:FindFirstChild("Car")
		if owner and owner:IsA("ObjectValue") and owner.Value == car then
			return interface:FindFirstChild("Values")
		end
	end
	return nil
end

-- The horn, while the driver holds it (the server sets the Horn attribute)
local function updateHorn(engine: Engine)
	local hornOn = engine.car:GetAttribute("Horn") == true
	local horn = engine.horn
	if hornOn and not horn then
		local sound = newSound(SOUNDS.horn, engine.chassis, true, 0.9)
		sound:Play()
		engine.horn = sound
	elseif not hornOn and horn then
		horn:Destroy()
		engine.horn = nil
	end
end

-- A spring for the body's lean: quick, with a little bounce
local function spring(value: number, speed: number, target: number, dt: number): (number, number)
	speed += ((target - value) * 160 - speed * 15) * dt
	return value + speed * dt, speed
end

local function update(engine: Engine, dt: number, now: number, mine: boolean)
	local car, chassis = engine.car, engine.chassis
	local cframe = chassis.CFrame
	local velocity = chassis.AssemblyLinearVelocity
	local forwardSpeed = velocity:Dot(cframe.LookVector)
	local sideSpeed = velocity:Dot(cframe.RightVector)
	local yawRate = chassis.AssemblyAngularVelocity:Dot(cframe.UpVector)
	local accel = (forwardSpeed - engine.lastSpeed) / math.max(dt, 1 / 240)
	engine.lastSpeed = forwardSpeed
	engine.accel += (math.clamp(accel, -150, 150) - engine.accel) * math.min(dt * 10, 1)

	-- The body leaning: back down when it pulls away, nose down under braking, outwards in a corner
	local joint = engine.joint
	if joint then
		-- Kept subtle, like Birmingham Vehicle Simulator: about 1 degree under hard braking, less pulling away
		local pitchTarget = math.clamp(engine.accel * 0.00022, -0.018, 0.011)
		local rollTarget = math.clamp(-forwardSpeed * yawRate * 0.0004, -0.035, 0.035)
		engine.pitch, engine.pitchSpeed = spring(engine.pitch, engine.pitchSpeed, pitchTarget, dt)
		engine.roll, engine.rollSpeed = spring(engine.roll, engine.rollSpeed, rollTarget, dt)
		joint.Transform = CFrame.Angles(engine.pitch, 0, engine.roll)
	end

	-- The engine's only running with someone in the driver's seat
	local seat = engine.seat
	local running = seat ~= nil and seat.Occupant ~= nil
	if not running then
		stopSounds(engine)
		return
	end
	local chassisCar = car:GetAttribute("ChassisCar") == true
	if chassisCar and not engine.profile then
		updateHorn(engine) -- A-Chassis cars make their own engine, tyre and exhaust sounds unless we give them ours
		return
	end
	startSounds(engine)

	-- What the engine's doing: the driver's own device knows; for anyone else's car, guess from how it moves
	local topSpeed = number(car, "TopSpeed", 120)
	local rpmNow, drive, slip, pedal
	local upshifted, downshifted = false, false
	local chassisValues = if mine and chassisCar then aChassisValues(car) else nil
	if chassisValues then
		-- An A-Chassis car you're driving: its own revs, gear and throttle
		local function value(name: string, default: number): number
			local holder = chassisValues:FindFirstChild(name)
			local v = holder and (holder :: any).Value
			return if typeof(v) == "number" then v else default
		end
		rpmNow = math.max(value("RPM", Gearbox.IDLE), Gearbox.IDLE)
		drive = math.clamp(value("Throttle", 0), 0, 1)
		pedal = drive
		local gear = value("Gear", 1)
		upshifted = gear > engine.gear and engine.gear >= 1
		downshifted = gear < engine.gear and gear >= 1
		engine.gear = gear
		slip = math.abs(sideSpeed) + (if value("Brake", 0) > 0.5 and math.abs(forwardSpeed) > 20 then 6 else 0)
	elseif mine then
		rpmNow = number(car, "Rpm", Gearbox.IDLE)
		drive = number(car, "Drive", 0)
		pedal = number(car, "Throttle", 0)
		slip = number(car, "Slip", 0)
		local ups, downs = number(car, "Upshifts", 0), number(car, "Downshifts", 0)
		upshifted = ups > engine.upshifts
		downshifted = downs > engine.downshifts
		engine.upshifts, engine.downshifts = ups, downs
	else
		local accelerating = engine.accel > 3
		local gear = if forwardSpeed < -1 then 0 else Gearbox.guess(engine.box, forwardSpeed, engine.gear, topSpeed, accelerating)
		upshifted = gear > engine.gear and engine.gear >= 1
		downshifted = gear < engine.gear and gear >= 1
		engine.gear = gear
		rpmNow = Gearbox.rpm(engine.box, forwardSpeed, gear, topSpeed, number(car, "ReverseSpeed", 24))
		drive = if accelerating then math.clamp(engine.accel / (number(car, "Acceleration", 15) * 0.6), 0.3, 1) else 0
		slip = math.abs(sideSpeed) + (if engine.accel < -40 then 6 else 0)
		pedal = drive
	end

	-- The needle doesn't jump: it swings to the new revs quickly (a gear change drops it in a tenth of a second)
	engine.rpm += (rpmNow - engine.rpm) * math.min(dt * 18, 1)
	local share = Gearbox.share(engine.rpm)
	local pitch = number(car, "EnginePitch", 1)
	local volume = number(car, "EngineVolume", 1)

	-- Changing down: the engine blips its revs to match
	if downshifted then
		engine.blipUntil = now + 0.12
	end
	local blip = if now < engine.blipUntil then 0.12 else 0

	local cut = if now < engine.brapUntil then 0.3 else 1 -- the ignition cut on a brap
	local profile = engine.profile
	if profile and #engine.loops > 0 then
		-- Real recordings: the two nearest the revs play, each sped up or slowed down to match, faded across
		-- with equal power so the loudness stays even. Louder on the accelerator, quieter on the overrun.
		-- After a start-up the idle fades in behind the starter.
		local loops = profile.loops
		local soundRpm = engine.rpm * (1 + blip)
		local fadeIn = if engine.startup then math.clamp((now - engine.startedAt - 0.6) / 0.8, 0, 1) else 1
		local loudness = volume * cut * fadeIn * (0.5 + 0.5 * drive) * (0.8 + 0.4 * share)
		local below = 1
		for i = 1, #loops - 1 do
			if soundRpm >= loops[i].rpm then
				below = i
			end
		end
		-- Only fade across the middle half of the gap, so no recording gets stretched too far from its own revs
		local blend = 0
		if #loops > 1 then
			local along = (soundRpm - loops[below].rpm) / (loops[below + 1].rpm - loops[below].rpm)
			blend = math.clamp((along - 0.25) / 0.5, 0, 1)
		end
		for i, recording in loops do
			local weight = if i == below then math.cos(blend * math.pi / 2) elseif i == below + 1 then math.sin(blend * math.pi / 2) else 0
			local sound = engine.loops[i]
			sound.Volume = recording.volume * weight * loudness
			sound.PlaybackSpeed = math.clamp(soundRpm / recording.rpm, 0.5, 2.2) * pitch
		end
	end
	local idle, rev, whine, skid = engine.idle, engine.rev, engine.whine, engine.skid
	if idle and rev then
		-- Two recordings mixed: the tick-over fades out as the revs rise and the revving one takes over
		idle.Volume = volume * math.clamp(0.75 - share * 1.6, 0, 0.75)
		idle.PlaybackSpeed = pitch * (0.95 + share * 0.5)
		rev.Volume = cut * volume * math.clamp(share * 3, 0, 1) * (0.35 + 0.45 * drive + 0.25 * share)
		rev.PlaybackSpeed = pitch * (0.62 + (share + blip) * 0.9)
	end
	if whine then
		whine.Volume = (if volume > 0 then (if profile then 0.03 else 0.05) + 0.12 * share * drive else 0.15 + 0.25 * share)
		whine.PlaybackSpeed = 0.7 + share * 1.1
	end
	if skid then
		local squeal = math.clamp((slip - 9) / 22, 0, 1)
		skid.Volume = squeal * 0.7
		skid.PlaybackSpeed = 0.9 + squeal * 0.2
	end
	local smokiness = math.clamp((slip - 14) / 22, 0, 1)
	for _, emitter in engine.smoke do
		emitter.Rate = smokiness * 45
	end

	updateHorn(engine)

	-- Changing up: a hiss from the turbo's blow-off valve (not on real-engine cars, whose recordings have
	-- their own), and a brap from the exhaust on cars that pop: recorded if the engine has one, made up if not
	if upshifted then
		engine.lastUpshift = now
		if volume > 0 and engine.rpm > 4500 then
			local blowOff = engine.blowOff
			if blowOff and not profile then
				blowOff.PlaybackSpeed = random:NextNumber(0.95, 1.1)
				blowOff.TimePosition = 0
				blowOff:Play()
			end
			if car:GetAttribute("Pops") then
				if #engine.farts > 0 then
					fart(engine)
				else
					brap(engine)
				end
			end
		end
	end

	-- Lifting off at high revs: the exhaust crackles and pops for a second or so (cars that pop only), with
	-- the engine's own recorded burble if it has one. For other players' cars we only see the car slow down,
	-- and a gear change looks the same, so skip those.
	if car:GetAttribute("Pops") then
		local changingGear = not mine and now - engine.lastUpshift < 0.4
		local burble = engine.burble
		if engine.lastPedal > 0.5 and pedal < 0.1 and engine.rpm > 4000 and not changingGear then
			engine.crackleUntil = now + random:NextNumber(0.8, 1.4)
			engine.nextPop = now + random:NextNumber(0.03, 0.1)
			pop(engine, true)
			if burble then
				burble.PlaybackSpeed = random:NextNumber(0.95, 1.05)
				burble.TimePosition = 0
				burble:Play()
			end
		end
		if burble and burble.IsPlaying and (pedal > 0.3 or now > engine.crackleUntil + 0.3) then
			burble:Stop() -- back on the accelerator, or the crackle's over
		end
		if downshifted and random:NextNumber() < 0.6 then
			pop(engine, false)
		end
		if now < engine.crackleUntil and pedal < 0.1 and engine.rpm > 2800 and now >= engine.nextPop and not changingGear then
			-- With a recorded burble the bangs are in the recording: just the flames, and the odd extra bang
			if burble and random:NextNumber() < 0.7 then
				flame(engine, false)
			else
				pop(engine, false)
			end
			engine.nextPop = now + random:NextNumber(0.06, 0.2)
		end
	end
	engine.lastPedal = pedal
end

-- Every frame: the nearest cars to the camera get their sounds and lean; cars far away are forgotten
local camera = Workspace.CurrentCamera
RunService.Heartbeat:Connect(function(dt)
	local cars = Workspace:FindFirstChild("Cars")
	if not cars then
		return
	end
	local now = os.clock()
	local focus = camera.CFrame.Position
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")

	local near: { { car: Model, distance: number } } = {}
	for _, car in cars:GetChildren() do
		local chassis = if car:IsA("Model") then car.PrimaryPart else nil
		if chassis then
			local distance = (chassis.Position - focus).Magnitude
			if distance < HEAR_WITHIN then
				table.insert(near, { car = car :: Model, distance = distance })
			end
		end
	end
	table.sort(near, function(a, b)
		return a.distance < b.distance
	end)

	local heard: { [Model]: boolean } = {}
	for i, entry in near do
		if i > MOST_ENGINES then
			break
		end
		local car = entry.car
		local engine = engines[car] or newEngine(car)
		if engine then
			engines[car] = engine
			heard[car] = true
			local seat = engine.seat
			local mine = humanoid ~= nil and seat ~= nil and seat.Occupant == humanoid
			update(engine, dt, now, mine)
		end
	end

	-- Quiet the cars that dropped out of range, and forget cars that have gone
	for car, engine in engines do
		if not heard[car] then
			stopSounds(engine)
			local chassis = engine.chassis
			if not car.Parent or not chassis.Parent or (chassis.Position - focus).Magnitude > FORGET_BEYOND then
				if engine.joint then
					engine.joint.Transform = CFrame.identity
				end
				for _, sound in engine.bangs do
					sound:Destroy()
				end
				if engine.blowOff then
					engine.blowOff:Destroy()
				end
				for _, sound in engine.farts do
					sound:Destroy()
				end
				for _, emitter in engine.smoke do
					if emitter.Parent then
						emitter.Parent:Destroy()
					end
				end
				for _, sound in { engine.burble, engine.startup } do
					if sound then
						sound:Destroy()
					end
				end
				engines[car] = nil
			end
		end
	end
end)
]])
put(folder7, "LocalScript", "VehicleLights", [[
-- Makes every vehicle's lights work on your screen: headlights, indicators, hazards and blue lights.
-- The driver flicks a switch (see Driving), the server sets an attribute on the car, and this script
-- on every player's device does the flashing, so it's smooth and costs the server nothing.
-- Lamps are parts with a "LightRole" attribute (set by CarBuilder and tools/prepare_vehicle_bodies.luau):
-- Head, Beam and Tail come on with the headlights, IndicatorL / IndicatorR flash, BlueA / BlueB take turns.

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

type Lamp = { part: BasePart, role: string }

local MATERIALS: { [string]: Enum.Material } = {}
for _, material in Enum.Material:GetEnumItems() do
	MATERIALS[material.Name] = material
end

-- Each car's lamps, found once, and whether each lamp is on right now
local lampsOf: { [Instance]: { Lamp } } = setmetatable({}, { __mode = "k" }) :: any
local lit: { [BasePart]: boolean } = setmetatable({}, { __mode = "k" }) :: any

local function findLamps(car: Instance): { Lamp }
	local lamps = {}
	for _, descendant in car:GetDescendants() do
		local role = descendant:GetAttribute("LightRole")
		if descendant:IsA("BasePart") and typeof(role) == "string" then
			table.insert(lamps, { part = descendant, role = role })
		end
	end
	return lamps
end

local function setLamp(part: BasePart, on: boolean)
	if lit[part] == on then
		return
	end
	lit[part] = on
	local colour = part:GetAttribute(if on then "OnColor" else "OffColor")
	local transparency = part:GetAttribute(if on then "OnTransparency" else "OffTransparency")
	local offMaterial = part:GetAttribute("OffMaterial")
	if typeof(colour) == "Color3" then
		part.Color = colour
	end
	if typeof(transparency) == "number" then
		part.Transparency = transparency
	end
	part.Material = if on then Enum.Material.Neon elseif typeof(offMaterial) == "string" and MATERIALS[offMaterial] then MATERIALS[offMaterial] else Enum.Material.SmoothPlastic
	for _, child in part:GetChildren() do
		if child:IsA("Light") then
			child.Enabled = on
		end
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
		local lamps = lampsOf[car]
		if not lamps then
			lamps = findLamps(car)
			lampsOf[car] = lamps
		end
		local indicator = car:GetAttribute("Indicator")
		local blueLights = car:GetAttribute("BlueLights") == true
		local headlights = car:GetAttribute("Headlights") == true
		local left = blink and (indicator == "Hazard" or indicator == "Left")
		local right = blink and (indicator == "Hazard" or indicator == "Right")

		for _, lamp in lamps do
			local role = lamp.role
			local on = false
			if role == "Head" or role == "Beam" or role == "Tail" then
				on = headlights
			elseif role == "IndicatorL" then
				on = left
			elseif role == "IndicatorR" then
				on = right
			elseif role == "BlueA" then
				on = blueLights and flashA
			elseif role == "BlueB" then
				on = blueLights and not flashA
			end
			setLamp(lamp.part, on)
		end
	end
end)
]])
removeOldScripts(folder7)

workspace.StreamingEnabled = true
pcall(function()
	workspace.StreamingTargetRadius = 900
end)
pcall(function()
	(workspace :: any).StreamOutBehavior = (Enum :: any).StreamOutBehavior.Opportunistic
end)


do
	local MaterialService = game:GetService("MaterialService")
	for _, info in { { "LdnTarmac", Enum.Material.Asphalt }, { "LdnSlabs", Enum.Material.Pavement }, { "LdnConcrete", Enum.Material.Concrete }, { "LdnSlate", Enum.Material.Slate }, { "LdnRender", Enum.Material.Plaster } } do
		local variant = MaterialService:FindFirstChild(info[1])
		if variant then
			variant:Destroy()
		end
		if MaterialService:GetBaseMaterialOverride(info[2]) == info[1] then
			MaterialService:SetBaseMaterialOverride(info[2], "")
		end
	end
end


print("London Simulator installed 38 scripts. Press Play to test!")
