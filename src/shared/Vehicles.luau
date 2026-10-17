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
