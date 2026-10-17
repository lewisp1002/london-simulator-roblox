-- Little bits of movement in the town, done on your own device so they're smooth:
--   the big wheel on the south bank turns slowly
--   the amber globes on zebra crossings flash

local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local WHEEL_SPEED = math.rad(1.2) -- radians per second: one turn takes about five minutes
local GLOBE_ON = Color3.fromRGB(255, 160, 20)
local GLOBE_OFF = Color3.fromRGB(120, 80, 30)

-- Remember where each wheel started, so it turns around its hub rather than drifting
local wheels: { [Model]: CFrame } = {}
local function addWheel(instance: Instance)
	if instance:IsA("Model") then
		wheels[instance] = instance:GetPivot()
	end
end
CollectionService:GetInstanceAddedSignal("BigWheelRotor"):Connect(addWheel)
CollectionService:GetInstanceRemovedSignal("BigWheelRotor"):Connect(function(instance)
	if instance:IsA("Model") then
		wheels[instance] = nil
	end
end)
for _, instance in CollectionService:GetTagged("BigWheelRotor") do
	addWheel(instance)
end

local elapsed = 0
local globesLit = true
RunService.Heartbeat:Connect(function(dt)
	elapsed += dt

	for wheel, start in wheels do
		local hub = wheel:GetAttribute("Hub")
		if typeof(hub) == "Vector3" and wheel.Parent then
			-- Spin around the hub's axle, which points north-south (the Z axis)
			local turn = CFrame.new(hub) * CFrame.Angles(0, 0, elapsed * WHEEL_SPEED) * CFrame.new(-hub)
			wheel:PivotTo(turn * start)
		end
	end

	local lit = elapsed % 1 < 0.5
	if lit ~= globesLit then
		globesLit = lit
		for _, globe in CollectionService:GetTagged("BelishaGlobe") do
			if globe:IsA("BasePart") then
				globe.Color = if lit then GLOBE_ON else GLOBE_OFF
				globe.Material = if lit then Enum.Material.Neon else Enum.Material.SmoothPlastic
			end
		end
	end
end)
