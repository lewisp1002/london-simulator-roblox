-- Makes every vehicle's lights work on your screen: headlights, indicators, hazards and blue lights.
-- The driver flicks a switch (see Driving), the server sets an attribute on the car, and this script
-- on every player's device does the flashing, so it's smooth and costs the server nothing.

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local INDICATOR_ON = Color3.fromRGB(255, 160, 20)
local INDICATOR_OFF = Color3.fromRGB(150, 95, 30)
local BLUE_ON = Color3.fromRGB(40, 100, 255)
local BLUE_OFF = Color3.fromRGB(25, 35, 75)
local HEADLIGHT_ON = Color3.fromRGB(255, 252, 235)
local HEADLIGHT_OFF = Color3.fromRGB(225, 228, 230)

local function setLamp(part: BasePart, on: boolean, onColour: Color3, offColour: Color3)
	part.Color = if on then onColour else offColour
	part.Material = if on then Enum.Material.Neon else Enum.Material.SmoothPlastic
	local glow = part:FindFirstChildWhichIsA("Light")
	if glow then
		glow.Enabled = on
	end
end

local elapsed = 0
RunService.Heartbeat:Connect(function(dt)
	elapsed += dt
	local cars = Workspace:FindFirstChild("Cars")
	if not cars then
		return
	end
	local blink = elapsed % 0.8 < 0.4 -- indicators: on for 0.4s, off for 0.4s
	local flashA = elapsed % 0.3 < 0.15 -- blue lights swap sides quickly

	for _, car in cars:GetChildren() do
		local indicator = car:GetAttribute("Indicator")
		local blueLights = car:GetAttribute("BlueLights") == true
		local headlights = car:GetAttribute("Headlights") == true
		for _, part in car:GetChildren() do
			if part:IsA("BasePart") then
				local name = part.Name
				if name:sub(1, 9) == "Indicator" then
					local isLeft = name:sub(-1) == "L"
					local on = blink and (indicator == "Hazard" or (indicator == "Left" and isLeft) or (indicator == "Right" and not isLeft))
					setLamp(part, on, INDICATOR_ON, INDICATOR_OFF)
				elseif name == "BlueLightA" then
					setLamp(part, blueLights and flashA, BLUE_ON, BLUE_OFF)
				elseif name == "BlueLightB" then
					setLamp(part, blueLights and not flashA, BLUE_ON, BLUE_OFF)
				elseif name == "Headlight" then
					setLamp(part, headlights, HEADLIGHT_ON, HEADLIGHT_OFF)
				end
			end
		end
	end
end)
