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
	car:SetAttribute("ArcadeHandling", true) -- tells the Driving script to drive it

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
