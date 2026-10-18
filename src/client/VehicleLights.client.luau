-- Makes every vehicle's lights work on your screen: headlights, indicators, hazards and blue lights.
-- The driver flicks a switch (see Driving), the server sets an attribute on the car, and this script
-- on every player's device does the flashing, so it's smooth and costs the server nothing.
-- Lamps are parts with a "LightRole" attribute (set by CarBuilder and tools/prepare_vehicle_bodies.luau):
-- Head, Beam and Tail come on with the headlights, IndicatorL / IndicatorR flash, BlueA / BlueB take turns.

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

type Lamp = { part: BasePart, role: string }

local MATERIALS: { [string]: Enum.Material } = {}
for _, material in Enum.Material:GetEnumItems() do
	MATERIALS[material.Name] = material
end

-- Each car's lamps, found once, and whether each lamp is on right now
local lampsOf: { [Instance]: { Lamp } } = setmetatable({}, { __mode = "k" }) :: any
local lit: { [BasePart]: boolean } = setmetatable({}, { __mode = "k" }) :: any

local function findLamps(car: Instance): { Lamp }
	local lamps = {}
	for _, descendant in car:GetDescendants() do
		local role = descendant:GetAttribute("LightRole")
		if descendant:IsA("BasePart") and typeof(role) == "string" then
			table.insert(lamps, { part = descendant, role = role })
		end
	end
	return lamps
end

local function setLamp(part: BasePart, on: boolean)
	if lit[part] == on then
		return
	end
	lit[part] = on
	local colour = part:GetAttribute(if on then "OnColor" else "OffColor")
	local transparency = part:GetAttribute(if on then "OnTransparency" else "OffTransparency")
	local offMaterial = part:GetAttribute("OffMaterial")
	if typeof(colour) == "Color3" then
		part.Color = colour
	end
	if typeof(transparency) == "number" then
		part.Transparency = transparency
	end
	part.Material = if on then Enum.Material.Neon elseif typeof(offMaterial) == "string" and MATERIALS[offMaterial] then MATERIALS[offMaterial] else Enum.Material.SmoothPlastic
	for _, child in part:GetChildren() do
		if child:IsA("Light") then
			child.Enabled = on
		end
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
		local lamps = lampsOf[car]
		if not lamps then
			lamps = findLamps(car)
			lampsOf[car] = lamps
		end
		local indicator = car:GetAttribute("Indicator")
		local blueLights = car:GetAttribute("BlueLights") == true
		local headlights = car:GetAttribute("Headlights") == true
		local left = blink and (indicator == "Hazard" or indicator == "Left")
		local right = blink and (indicator == "Hazard" or indicator == "Right")

		for _, lamp in lamps do
			local role = lamp.role
			local on = false
			if role == "Head" or role == "Beam" or role == "Tail" then
				on = headlights
			elseif role == "IndicatorL" then
				on = left
			elseif role == "IndicatorR" then
				on = right
			elseif role == "BlueA" then
				on = blueLights and flashA
			elseif role == "BlueB" then
				on = blueLights and not flashA
			end
			setLamp(lamp.part, on)
		end
	end
end)
