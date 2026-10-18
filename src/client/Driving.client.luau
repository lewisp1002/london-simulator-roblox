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
