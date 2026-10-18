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
