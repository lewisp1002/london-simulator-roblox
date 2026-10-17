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
