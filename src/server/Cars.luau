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
