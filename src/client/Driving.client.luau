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
