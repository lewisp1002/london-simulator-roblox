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

local function put(parent: Instance, className: string, name: string, source: string)
	local old = parent:FindFirstChild(name)
	if old then
		old:Destroy()
	end
	local newScript: any = Instance.new(className)
	newScript.Name = name
	newScript.Source = source
	newScript.Parent = parent
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
	SpawnCooldownSeconds = 3,
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
local folder3 = game:GetService("ServerScriptService")
local folder4 = folder(folder3, "Server")
put(folder4, "ModuleScript", "Cars", [[
-- Spawns and looks after players' cars: one car each, built from parts.
-- The driving itself happens in the Driving LocalScript, on the driver's own device, so it feels instant.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)

local CAR = Config.Car

-- Car parts slide with no friction: the Driving script controls speed and grip itself
local SLIDING = PhysicalProperties.new(0.7, 0, 0, 100, 100)
-- Parked cars grip the road hard so they don't get shoved around, like a handbrake
local PARKED = PhysicalProperties.new(0.7, 2, 0, 100, 100)
-- A heavy, low chassis stops the car tipping over
local HEAVY_SLIDING = PhysicalProperties.new(3, 0, 0, 100, 100)

-- Height of the middle of the chassis above the road
local CHASSIS_HEIGHT = 2.1

local PAINT_COLOURS = {
	Color3.fromRGB(240, 240, 240), -- white
	Color3.fromRGB(25, 25, 28), -- black
	Color3.fromRGB(160, 165, 170), -- silver
	Color3.fromRGB(180, 20, 30), -- red
	Color3.fromRGB(30, 70, 160), -- blue
	Color3.fromRGB(0, 66, 37), -- British racing green
}
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

-- `offset` is measured from the middle of the car at road level. The front of the car is -Z.
local function place(part: BasePart, car: Model, origin: CFrame, size: Vector3, offset: Vector3)
	part.Size = size
	part.CFrame = origin * CFrame.new(offset)
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Material = Enum.Material.SmoothPlastic
	part.CustomPhysicalProperties = SLIDING
	part.Parent = car
end

local function addPart(car: Model, origin: CFrame, name: string, size: Vector3, offset: Vector3): Part
	local part = Instance.new("Part")
	part.Name = name
	place(part, car, origin, size, offset)
	return part
end

local function weld(part: BasePart, chassis: BasePart)
	part.Massless = true
	local joint = Instance.new("WeldConstraint")
	joint.Part0 = chassis
	joint.Part1 = part
	joint.Parent = part
end

local function addPlate(car: Model, origin: CFrame, chassis: BasePart, plateText: string, z: number, face: Enum.NormalId, colour: Color3)
	local plate = addPart(car, origin, "NumberPlate", Vector3.new(2.6, 0.6, 0.1), Vector3.new(0, 1.8, z))
	plate.Color = colour
	plate.CanCollide = false
	weld(plate, chassis)

	local surface = Instance.new("SurfaceGui")
	surface.Face = face
	surface.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	surface.PixelsPerStud = 100
	surface.Parent = plate

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.TextColor3 = Color3.new(0, 0, 0)
	label.Text = plateText
	label.Parent = surface
end

local function addPrompt(seat: BasePart, actionText: string, objectText: string, key: Enum.KeyCode): ProximityPrompt
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = actionText
	prompt.ObjectText = objectText
	prompt.KeyboardKeyCode = key
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.Parent = seat
	return prompt
end

local function setParked(car: Model, parked: boolean)
	for _, part in car:GetChildren() do
		if part.Name == "TyreContact" and part:IsA("BasePart") then
			part.CustomPhysicalProperties = if parked then PARKED else SLIDING
		end
	end
end

-- Builds a car standing on the road at `origin`, facing the way `origin` faces
local function buildCar(owner: Player, origin: CFrame): (Model, VehicleSeat)
	local paint = PAINT_COLOURS[random:NextInteger(1, #PAINT_COLOURS)]
	local plateText = randomPlate()

	local car = Instance.new("Model")
	car.Name = owner.Name .. "'s car"
	car:SetAttribute("OwnerUserId", owner.UserId)

	local chassis = addPart(car, origin, "Chassis", Vector3.new(6.6, 1.6, 13.6), Vector3.new(0, CHASSIS_HEIGHT, 0))
	chassis.Color = paint
	chassis.CustomPhysicalProperties = HEAVY_SLIDING
	chassis.RootPriority = 127
	car.PrimaryPart = chassis

	local cabin = addPart(car, origin, "Windows", Vector3.new(6, 3.3, 6.8), Vector3.new(0, 4.55, 0.6))
	cabin.Material = Enum.Material.Glass
	cabin.Color = Color3.fromRGB(35, 45, 55)
	cabin.Transparency = 0.35
	weld(cabin, chassis)

	local roof = addPart(car, origin, "Roof", Vector3.new(6.2, 0.3, 7), Vector3.new(0, 6.35, 0.6))
	roof.Color = paint
	weld(roof, chassis)

	for _, side in { -1, 1 } do
		local headlight = addPart(car, origin, "Headlight", Vector3.new(1.4, 0.5, 0.2), Vector3.new(side * 2.3, 2.5, -6.85))
		headlight.Material = Enum.Material.Neon
		headlight.Color = Color3.fromRGB(255, 250, 225)
		headlight.CanCollide = false
		weld(headlight, chassis)

		local taillight = addPart(car, origin, "Taillight", Vector3.new(1.4, 0.5, 0.2), Vector3.new(side * 2.3, 2.5, 6.85))
		taillight.Material = Enum.Material.Neon
		taillight.Color = Color3.fromRGB(200, 0, 0)
		taillight.CanCollide = false
		weld(taillight, chassis)
	end

	-- UK plates: white on the front, yellow on the back
	addPlate(car, origin, chassis, plateText, -6.85, Enum.NormalId.Front, Color3.fromRGB(245, 245, 245))
	addPlate(car, origin, chassis, plateText, 6.85, Enum.NormalId.Back, Color3.fromRGB(255, 205, 0))

	local axle = CAR.Wheelbase / 2
	for _, z in { -axle, axle } do
		for _, side in { -1, 1 } do
			local offset = Vector3.new(side * 3, CAR.WheelRadius, z)

			-- The wheel you see. It's jointed (not welded) so Driving can turn and spin it.
			local wheel = addPart(car, origin, "Wheel", Vector3.new(1, CAR.WheelRadius * 2, CAR.WheelRadius * 2), offset)
			wheel.Shape = Enum.PartType.Cylinder
			wheel.Color = Color3.fromRGB(20, 20, 20)
			wheel.CanCollide = false
			wheel.Massless = true
			local joint = Instance.new("Motor6D")
			joint.Name = "WheelJoint"
			joint.Part0 = chassis
			joint.Part1 = wheel
			joint.C0 = CFrame.new(offset - Vector3.new(0, CHASSIS_HEIGHT, 0))
			joint:SetAttribute("Steers", z < 0)
			joint.Parent = chassis

			-- An invisible ball inside each wheel is what actually touches the road
			local contact = addPart(car, origin, "TyreContact", Vector3.one * CAR.WheelRadius * 2, offset)
			contact.Shape = Enum.PartType.Ball
			contact.Transparency = 1
			weld(contact, chassis)
		end
	end

	-- Right-hand drive, like a real British car
	local driverSeat = Instance.new("VehicleSeat")
	driverSeat.Name = "DriverSeat"
	driverSeat.HeadsUpDisplay = false -- we draw our own speedometer
	driverSeat.Transparency = 1
	driverSeat.CanCollide = false
	place(driverSeat, car, origin, Vector3.new(2, 0.4, 2), Vector3.new(1.4, 1.7, -0.6))
	weld(driverSeat, chassis)

	local passengerSeat = Instance.new("Seat")
	passengerSeat.Name = "PassengerSeat"
	passengerSeat.Transparency = 1
	passengerSeat.CanCollide = false
	place(passengerSeat, car, origin, Vector3.new(2, 0.4, 2), Vector3.new(-1.4, 1.7, -0.6))
	weld(passengerSeat, chassis)

	local drivePrompt = addPrompt(driverSeat, "Drive", owner.DisplayName .. "'s car", Enum.KeyCode.E)
	local passengerPrompt = addPrompt(passengerSeat, "Get in", owner.DisplayName .. "'s car", Enum.KeyCode.F)

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
		-- The driver's device runs the car's physics while they drive, so there's no lag
		chassis:SetNetworkOwner(driver)
	end)

	passengerSeat:GetPropertyChangedSignal("Occupant"):Connect(function()
		passengerPrompt.Enabled = passengerSeat.Occupant == nil
	end)

	setParked(car, true)
	car.Parent = carsFolder
	return car, driverSeat
end

local function spawnCar(player: Player)
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

	-- Work out where they are before removing their old car, as they might be sitting in it
	local rootCFrame = root.CFrame
	local oldCar = carsByPlayer[player]
	if oldCar then
		oldCar:Destroy()
	end

	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = { humanoid.Parent :: Instance, carsFolder }
	local ground = Workspace:Raycast(rootCFrame.Position, Vector3.new(0, -12, 0), rayParams)
	if not ground then
		return -- they're not standing on anything
	end

	-- Put the car right where they're standing, facing the way they face
	local facing = rootCFrame.LookVector * Vector3.new(1, 0, 1)
	if facing.Magnitude < 0.01 then
		facing = Vector3.new(0, 0, -1)
	end
	local origin = CFrame.lookAt(ground.Position, ground.Position + facing.Unit)

	local car, driverSeat = buildCar(player, origin)
	carsByPlayer[player] = car
	driverSeat:Sit(humanoid)
end

function Cars.start()
	carsFolder = Instance.new("Folder")
	carsFolder.Name = "Cars"
	carsFolder.Parent = Workspace

	local remotes = Instance.new("Folder")
	remotes.Name = "Remotes"
	local spawnRemote = Instance.new("RemoteEvent")
	spawnRemote.Name = "SpawnCar"
	spawnRemote.Parent = remotes
	remotes.Parent = ReplicatedStorage
	spawnRemote.OnServerEvent:Connect(spawnCar)

	Players.PlayerRemoving:Connect(function(player)
		local car = carsByPlayer[player]
		if car then
			car:Destroy()
		end
		carsByPlayer[player] = nil
		lastSpawnTime[player] = nil
	end)
end

return Cars
]])
put(folder4, "Script", "Main", [[
-- Starts everything on the server.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Cars = require(script.Parent.Cars)
local PlayerData = require(script.Parent.PlayerData)
local TestTown = require(script.Parent.TestTown)

PlayerData.start()
Cars.start()
if Config.BuildTestTown then
	TestTown.build()
end

-- Placeholder income until jobs are added: pay everyone on a timer
while true do
	task.wait(Config.PaychequeIntervalSeconds)
	for _, player in Players:GetPlayers() do
		PlayerData.addCash(player, Config.PaychequeAmount)
	end
end
]])
put(folder4, "ModuleScript", "PlayerData", [[
-- Loads, saves and changes each player's saved data (just cash for now).
-- Other server scripts use it like this:
--   PlayerData.addCash(player, 50)

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local MAX_ATTEMPTS = 3

type Data = {
	cash: number,
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

local function onPlayerAdded(player: Player)
	local data: Data = {
		cash = Config.StartingCash,
	}
	local canSave = false

	if storeOk then
		local ok, saved = retry(function()
			return store:GetAsync(keyFor(player))
		end)
		if ok then
			if type(saved) == "table" and type(saved.cash) == "number" then
				data.cash = saved.cash
			end
			canSave = true
		else
			warn(`[PlayerData] Couldn't load {player.Name}'s data, so it won't be saved this session:`, saved)
		end
	end

	if player.Parent ~= Players then
		return -- they left while their data was loading
	end

	sessions[player] = { data = data, canSave = canSave }
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

function PlayerData.addCash(player: Player, amount: number)
	local session = sessions[player]
	if not session then
		return -- their data hasn't loaded yet
	end
	session.data.cash += amount
	player:SetAttribute("Cash", session.data.cash)
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
put(folder4, "ModuleScript", "TestTown", [[
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
]])
local folder5 = game:GetService("StarterPlayer")
local folder6 = folder5:WaitForChild("StarterPlayerScripts")
local folder7 = folder(folder6, "Client")
put(folder7, "LocalScript", "Driving", [[
-- Drives the car you're sitting in the driver's seat of.
-- It runs on your own device (the server hands the driver control of the car's physics), so steering feels instant.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local CAR = Config.Car
local STEERING_LOCK = math.rad(CAR.SteeringLockDegrees)

local player = Players.LocalPlayer
local driving: RBXScriptConnection? = nil

-- Moves `value` towards `target` by at most `step`
local function approach(value: number, target: number, step: number): number
	if value < target then
		return math.min(value + step, target)
	end
	return math.max(value - step, target)
end

local function stopDriving()
	if driving then
		driving:Disconnect()
		driving = nil
	end
end

local function startDriving(seat: VehicleSeat)
	local car = seat.Parent :: Model
	local chassis = car.PrimaryPart
	if not chassis then
		return
	end

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
		wheelSpin -= forwardSpeed * dt / CAR.WheelRadius
		for _, joint in wheelJoints do
			local steerAngle = if joint:GetAttribute("Steers") then -steer * STEERING_LOCK else 0
			joint.Transform = CFrame.Angles(0, steerAngle, 0) * CFrame.Angles(wheelSpin, 0, 0)
		end

		-- Only accelerate and steer while the wheels are on the ground
		if not Workspace:Raycast(chassis.Position, -up * 3.5, rayParams) then
			return
		end

		local throttle = seat.ThrottleFloat
		if throttle > 0 then
			if forwardSpeed < 0 then
				forwardSpeed = approach(forwardSpeed, 0, CAR.BrakeDeceleration * dt) -- rolling backwards: brake first
			else
				forwardSpeed = approach(forwardSpeed, CAR.TopSpeed, CAR.Acceleration * throttle * dt)
			end
		elseif throttle < 0 then
			if forwardSpeed > 0 then
				forwardSpeed = approach(forwardSpeed, 0, CAR.BrakeDeceleration * dt) -- moving forwards: brake first
			else
				forwardSpeed = approach(forwardSpeed, -CAR.ReverseSpeed, CAR.Acceleration * -throttle * dt)
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
		local turnRate = math.min(speed * math.tan(STEERING_LOCK) / CAR.Wheelbase, maxTurnRate)
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
		if seat and seat:IsA("VehicleSeat") then
			startDriving(seat)
		end
	end)
end

player.CharacterAdded:Connect(onCharacterAdded)
player.CharacterRemoving:Connect(stopDriving)
if player.Character then
	onCharacterAdded(player.Character)
end
]])
put(folder7, "LocalScript", "Hud", [[
-- The bar in the top-right corner: a button to spawn your car, and your cash (with a "+£100" pop-up when you earn money).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Format = require(Shared:WaitForChild("Format"))

local spawnCarRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("SpawnCar") :: RemoteEvent

local GREEN = Color3.fromRGB(80, 220, 120)

local player = Players.LocalPlayer

local gui = Instance.new("ScreenGui")
gui.Name = "Hud"
gui.ResetOnSpawn = false -- keep the HUD when the player respawns
gui.IgnoreGuiInset = true -- lets us line up with Roblox's own top bar buttons
gui.Parent = player:WaitForChild("PlayerGui")

local topBar = Instance.new("Frame")
topBar.Name = "TopBar"
topBar.AnchorPoint = Vector2.new(1, 0)
topBar.Position = UDim2.new(1, -12, 0, 12)
topBar.Size = UDim2.fromOffset(0, 44)
topBar.AutomaticSize = Enum.AutomaticSize.X
topBar.BackgroundTransparency = 1
topBar.Parent = gui

local layout = Instance.new("UIListLayout")
layout.FillDirection = Enum.FillDirection.Horizontal
layout.HorizontalAlignment = Enum.HorizontalAlignment.Right
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Padding = UDim.new(0, 8)
layout.Parent = topBar

-- Rounded black "pill" shape shared by everything in the top bar
local function stylePill(pill: TextButton, order: number)
	pill.LayoutOrder = order
	pill.Size = UDim2.fromOffset(0, 44)
	pill.AutomaticSize = Enum.AutomaticSize.X
	pill.BackgroundColor3 = Color3.new(0, 0, 0)
	pill.BackgroundTransparency = 0.3
	pill.Font = Enum.Font.GothamBold
	pill.TextSize = 18
	pill.TextColor3 = Color3.new(1, 1, 1)

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0) -- fully rounded ends
	corner.Parent = pill

	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 16)
	padding.PaddingRight = UDim.new(0, 16)
	padding.Parent = pill

	pill.Parent = topBar
end

local spawnButton = Instance.new("TextButton")
spawnButton.Name = "SpawnCar"
spawnButton.Text = "🚗 Spawn car"
stylePill(spawnButton, 1)

-- A button so it can open the shop later on
local cashPill = Instance.new("TextButton")
cashPill.Name = "Cash"
cashPill.AutoButtonColor = false
cashPill.Visible = false -- hidden until their data has loaded
stylePill(cashPill, 2)

local coolingDown = false
spawnButton.Activated:Connect(function()
	if coolingDown then
		return
	end
	coolingDown = true
	spawnCarRemote:FireServer()
	spawnButton.TextTransparency = 0.5
	task.wait(Config.Car.SpawnCooldownSeconds)
	spawnButton.TextTransparency = 0
	coolingDown = false
end)

local function showGain(amount: number)
	local popup = Instance.new("TextLabel")
	popup.AnchorPoint = Vector2.new(1, 0)
	popup.Position = UDim2.new(1, -16, 0, 60)
	popup.Size = UDim2.fromOffset(200, 24)
	popup.BackgroundTransparency = 1
	popup.Font = Enum.Font.GothamBold
	popup.TextSize = 20
	popup.TextColor3 = GREEN
	popup.TextStrokeTransparency = 0.6
	popup.TextXAlignment = Enum.TextXAlignment.Right
	popup.Text = "+" .. Format.money(amount)
	popup.Parent = gui

	local tween = TweenService:Create(popup, TweenInfo.new(1.5), {
		Position = popup.Position + UDim2.fromOffset(0, 24),
		TextTransparency = 1,
		TextStrokeTransparency = 1,
	})
	tween.Completed:Once(function()
		popup:Destroy()
	end)
	tween:Play()
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
	cashPill.Text = Format.money(cash)
	cashPill.Visible = true
end

player:GetAttributeChangedSignal("Cash"):Connect(onCashChanged)
onCashChanged()
]])
put(folder7, "LocalScript", "Speedometer", [[
-- While you're driving: your speed in mph, the speed limit of the road you're on, and the keyboard controls.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local LIMIT_CHECK_SECONDS = 0.25
local RED = Color3.fromRGB(220, 30, 30)
local WHITE = Color3.new(1, 1, 1)

local player = Players.LocalPlayer

local gui = Instance.new("ScreenGui")
gui.Name = "Speedometer"
gui.ResetOnSpawn = false
gui.Enabled = false
gui.Parent = player:WaitForChild("PlayerGui")

local panel = Instance.new("Frame")
panel.AnchorPoint = Vector2.new(0, 1)
panel.Position = UDim2.new(0, 16, 1, -16)
panel.Size = UDim2.fromOffset(190, 80)
panel.BackgroundColor3 = Color3.new(0, 0, 0)
panel.BackgroundTransparency = 0.3
panel.Parent = gui

local panelCorner = Instance.new("UICorner")
panelCorner.CornerRadius = UDim.new(0, 12)
panelCorner.Parent = panel

local speedLabel = Instance.new("TextLabel")
speedLabel.Position = UDim2.fromOffset(12, 4)
speedLabel.Size = UDim2.fromOffset(90, 50)
speedLabel.BackgroundTransparency = 1
speedLabel.Font = Enum.Font.GothamBold
speedLabel.TextSize = 44
speedLabel.TextColor3 = WHITE
speedLabel.TextXAlignment = Enum.TextXAlignment.Right
speedLabel.Text = "0"
speedLabel.Parent = panel

local unitLabel = Instance.new("TextLabel")
unitLabel.Position = UDim2.fromOffset(12, 52)
unitLabel.Size = UDim2.fromOffset(90, 18)
unitLabel.BackgroundTransparency = 1
unitLabel.Font = Enum.Font.GothamBold
unitLabel.TextSize = 14
unitLabel.TextColor3 = Color3.fromRGB(180, 180, 180)
unitLabel.TextXAlignment = Enum.TextXAlignment.Right
unitLabel.Text = "mph"
unitLabel.Parent = panel

-- A UK speed limit sign: white circle, red ring, black number
local limitSign = Instance.new("Frame")
limitSign.AnchorPoint = Vector2.new(1, 0.5)
limitSign.Position = UDim2.new(1, -16, 0.5, 0)
limitSign.Size = UDim2.fromOffset(54, 54)
limitSign.BackgroundColor3 = WHITE
limitSign.Visible = false
limitSign.Parent = panel

local signCorner = Instance.new("UICorner")
signCorner.CornerRadius = UDim.new(1, 0)
signCorner.Parent = limitSign

local signRing = Instance.new("UIStroke")
signRing.Color = RED
signRing.Thickness = 6
signRing.Parent = limitSign

local limitLabel = Instance.new("TextLabel")
limitLabel.Size = UDim2.fromScale(1, 1)
limitLabel.BackgroundTransparency = 1
limitLabel.Font = Enum.Font.GothamBold
limitLabel.TextSize = 24
limitLabel.TextColor3 = Color3.new(0, 0, 0)
limitLabel.Parent = limitSign

-- Keyboard controls listed down the right-hand side
local CONTROLS = {
	{ "Accelerate", "W" },
	{ "Brake / reverse", "S" },
	{ "Steer", "A-D" },
	{ "Get out", "Space" },
}

local controlsList = Instance.new("Frame")
controlsList.AnchorPoint = Vector2.new(1, 1)
controlsList.Position = UDim2.new(1, -16, 1, -16)
controlsList.Size = UDim2.fromOffset(220, 0)
controlsList.AutomaticSize = Enum.AutomaticSize.Y
controlsList.BackgroundTransparency = 1
controlsList.Visible = UserInputService.KeyboardEnabled
controlsList.Parent = gui

local controlsLayout = Instance.new("UIListLayout")
controlsLayout.SortOrder = Enum.SortOrder.LayoutOrder
controlsLayout.Padding = UDim.new(0, 6)
controlsLayout.Parent = controlsList

for i, control in CONTROLS do
	local row = Instance.new("Frame")
	row.LayoutOrder = i
	row.Size = UDim2.new(1, 0, 0, 28)
	row.BackgroundTransparency = 1
	row.Parent = controlsList

	local key = Instance.new("TextLabel")
	key.AnchorPoint = Vector2.new(1, 0)
	key.Position = UDim2.fromScale(1, 0)
	key.Size = UDim2.fromOffset(0, 28)
	key.AutomaticSize = Enum.AutomaticSize.X
	key.BackgroundTransparency = 1
	key.Font = Enum.Font.GothamMedium
	key.TextSize = 14
	key.TextColor3 = WHITE
	key.Text = control[2]
	key.Parent = row

	local keyPadding = Instance.new("UIPadding")
	keyPadding.PaddingLeft = UDim.new(0, 10)
	keyPadding.PaddingRight = UDim.new(0, 10)
	keyPadding.Parent = key

	local keyCorner = Instance.new("UICorner")
	keyCorner.CornerRadius = UDim.new(1, 0)
	keyCorner.Parent = key

	local keyOutline = Instance.new("UIStroke")
	keyOutline.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	keyOutline.Color = WHITE
	keyOutline.Thickness = 1.5
	keyOutline.Parent = key

	local action = Instance.new("TextLabel")
	action.Size = UDim2.new(1, -70, 1, 0)
	action.BackgroundTransparency = 1
	action.Font = Enum.Font.GothamMedium
	action.TextSize = 14
	action.TextColor3 = WHITE
	action.TextStrokeTransparency = 0.6
	action.TextXAlignment = Enum.TextXAlignment.Right
	action.Text = control[1]
	action.Parent = row
end

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

local speedLimit: number? = nil
local sinceLimitCheck = math.huge

RunService.Heartbeat:Connect(function(dt)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local seat = humanoid and humanoid.SeatPart
	if not seat or not seat:IsA("VehicleSeat") then
		gui.Enabled = false
		sinceLimitCheck = math.huge
		return
	end
	gui.Enabled = true

	sinceLimitCheck += dt
	if sinceLimitCheck >= LIMIT_CHECK_SECONDS then
		sinceLimitCheck = 0
		rayParams.FilterDescendantsInstances = { seat.Parent :: Instance, character :: Instance }
		local hit = Workspace:Raycast(seat.Position, Vector3.new(0, -8, 0), rayParams)
		local limit = hit and hit.Instance:GetAttribute("SpeedLimit")
		speedLimit = if typeof(limit) == "number" then limit else nil
	end

	local mph = math.floor(math.abs(seat.AssemblyLinearVelocity:Dot(seat.CFrame.LookVector)) * Config.MphPerStudPerSecond + 0.5)
	speedLabel.Text = tostring(mph)
	speedLabel.TextColor3 = if speedLimit and mph > speedLimit then RED else WHITE
	limitSign.Visible = speedLimit ~= nil
	limitLabel.Text = if speedLimit then tostring(speedLimit) else ""
end)
]])

print("London Simulator installed 9 scripts. Press Play to test!")
