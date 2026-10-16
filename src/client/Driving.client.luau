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
