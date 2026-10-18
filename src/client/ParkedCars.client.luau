-- Fills the parking spaces near you with parked cars, like the streets in Birmingham Vehicle Simulator.
-- The map lists every space (ReplicatedStorage → MapInfo → ParkedCars, written by LondonMap). Only the ones
-- near your camera get a car, and cars are reused as you drive along, so thousands of spaces cost very little.
-- They're on your device only. Each space always gets the same car and colour, so every player sees the
-- same street. You can bump into them, but they don't move.

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Vehicles = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Vehicles"))

local SHOW_WITHIN = 260 -- studs from the camera
local HIDE_BEYOND = 320
local MOST_CARS = 45
local CELL = 200 -- spaces are sorted into squares this big, so finding the near ones is quick

-- Everyday colours for parked cars (indexes into Vehicles.Paints)
local PARKED_PAINTS = { 1, 1, 2, 2, 3, 3, 4, 5, 7, 8, 9, 13 }

local mapInfo = ReplicatedStorage:WaitForChild("MapInfo")
local data = mapInfo:WaitForChild("ParkedCars") :: StringValue
local models = ReplicatedStorage:WaitForChild("VehicleModels")

type Spot = { position: Vector3, cframe: CFrame, template: string, paint: number }

local spots: { Spot } = {}
local cells: { [string]: { number } } = {}

local function cellKey(x: number, z: number): string
	return math.floor(x / CELL) .. "," .. math.floor(z / CELL)
end

-- The cars people park: everything on the Car team that has a model
local templates: { string } = {}
for _, vehicle in Vehicles.forTeam("Car") do
	if not vehicle.hero and models:WaitForChild(vehicle.id, 10) then
		table.insert(templates, vehicle.id)
	end
end
if #templates == 0 then
	return
end

local ok, decoded = pcall(function(): any
	return HttpService:JSONDecode(data.Value)
end)
if not ok or type(decoded) ~= "table" then
	return
end
for index, entry in decoded do
	local position = Vector3.new(entry[1], entry[2], entry[3])
	local spot: Spot = {
		position = position,
		cframe = CFrame.new(position) * CFrame.Angles(0, math.rad(entry[4]), 0),
		-- The same car and colour in each space every time, without storing them
		template = templates[(index * 7919) % #templates + 1],
		paint = PARKED_PAINTS[(index * 104729) % #PARKED_PAINTS + 1],
	}
	table.insert(spots, spot)
	local key = cellKey(position.X, position.Z)
	cells[key] = cells[key] or {}
	table.insert(cells[key], index)
end

local folder = Instance.new("Folder")
folder.Name = "ParkedCars"
folder.Parent = Workspace

local pools: { [string]: { Model } } = {}
local active: { [number]: Model } = {}

local function recolour(model: Model, colour: Color3?)
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") and part:GetAttribute("Paint") then
			local original = part:GetAttribute("BaseColour")
			if colour then
				part.Color = colour
			elseif typeof(original) == "Color3" then
				part.Color = original
			end
		end
	end
end

local function take(spot: Spot): Model?
	local pool = pools[spot.template]
	local model: Model
	if pool and #pool > 0 then
		model = table.remove(pool) :: Model
	else
		local source = models:FindFirstChild(spot.template)
		if not source then
			return nil
		end
		model = source:Clone() :: Model
		-- The display copies can't be touched; parked cars should be solid
		for _, name in { "Chassis", "Hull" } do
			local part = model:FindFirstChild(name)
			if part and part:IsA("BasePart") then
				part.CanCollide = true
			end
		end
	end
	local vehicle = Vehicles.ById[spot.template]
	local keepColours = vehicle and (vehicle.fixedPaint or vehicle.livery == "Taxi")
	local paint = if keepColours then nil else Vehicles.Paints[spot.paint].colour
	recolour(model, paint)
	model:PivotTo(spot.cframe)
	model.Parent = folder
	return model
end

local function give(index: number)
	local model = active[index]
	if not model then
		return
	end
	active[index] = nil
	model.Parent = nil
	local template = spots[index].template
	pools[template] = pools[template] or {}
	table.insert(pools[template], model)
end

local camera = Workspace.CurrentCamera
while true do
	local focus = camera.Focus.Position
	-- Put away cars that are now far behind
	for index in active do
		if (spots[index].position - focus).Magnitude > HIDE_BEYOND then
			give(index)
		end
	end
	-- Find the nearby spaces, nearest first
	local near: { { number } } = {}
	local reach = math.ceil(SHOW_WITHIN / CELL)
	local cx, cz = math.floor(focus.X / CELL), math.floor(focus.Z / CELL)
	for i = cx - reach, cx + reach do
		for j = cz - reach, cz + reach do
			local list = cells[i .. "," .. j]
			if list then
				for _, index in list do
					local distance = (spots[index].position - focus).Magnitude
					if distance <= SHOW_WITHIN then
						table.insert(near, { index, distance })
					end
				end
			end
		end
	end
	table.sort(near, function(a, b)
		return a[2] < b[2]
	end)
	local count = 0
	for _ in active do
		count += 1
	end
	-- A few at a time, nearest first: making lots of cars at once made the game stutter when you drove
	-- into a new area
	local added = 0
	for _, entry in near do
		local index = entry[1]
		if not active[index] then
			if count >= MOST_CARS or added >= 2 then
				break
			end
			local model = take(spots[index])
			if model then
				active[index] = model
				count += 1
				added += 1
			end
		end
	end
	task.wait(0.1)
end
