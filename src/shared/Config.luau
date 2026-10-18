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

-- Builds the map (roads, river, parks, buildings) when the game starts. Turn it off if the map is saved in the
-- place file instead.
Config.BuildMap = true

-- Which map: "Cambridge" (the city and countryside, see CambridgeMap and tools/cambridge_layout.py) or "London"
-- (the first map, see LondonMap and tools/london_layout.py)
Config.Map = "Cambridge"

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
	SteeringLockDegrees = 45, -- full lock at parking and U-turn speeds; less above 15 mph
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
