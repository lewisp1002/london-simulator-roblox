--!nocheck
-- Turns the bought street furniture packs into a kit of clean props that the map puts along the roads:
-- traffic lights, the speed camera, bus shelter, bins, signs, keep-left bollards, road arrows and trees.
--
-- How to use it, in Roblox Studio:
--   1. The packs go in ServerStorage → PackImport: "Street Asset Pack V3" (ClearlyDev UK Road Asset Bundle)
--      and "AHDEV Roads" (ClearlyDev UK Single Carriageway Road Pack).
--   2. Paste this whole file into the Command Bar and press Enter.
--   3. The kit appears in ServerStorage → PropKit. Press Play: the map uses it straight away.
--
-- What it does to each prop:
--   - deletes every script, sound, GUI and value (checked 17 Oct 2026: no backdoors, but the map runs its own)
--   - deletes the fast-food style advert on the bus shelter and covers the speed camera maker's logo
--   - scales it to the map, turns it so its front faces -Z, and puts its pivot on the ground under its middle
--   - traffic lights: the three lamps are renamed Red, Amber, Green and made solid, so TrafficLights runs them
-- The pack files never go in the git repo: the kit lives only in the place file.

local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local BLOCKED_IMAGES = { 10341339810 } -- "SUB SAY" sandwich advert on the bus shelter

-- id, which pack, the name to look for in it (searched all the way down), scale, degrees to turn
local KIT = {
	{ id = "TrafficLight", pack = "Street Asset Pack V3", find = "Basic TL set (ungroup)", child = 1, scale = 1.05 },
	{ id = "SpeedCamera", pack = "Street Asset Pack V3", find = "Speed Camera", scale = 1.0 },
	{ id = "PhoneBoxModern", pack = "Street Asset Pack V3", find = "Telephone Box", scale = 0.95 },
	{ id = "BusShelter", pack = "Street Asset Pack V3", find = "UK bus shelter - ism dev", scale = 1.05 },
	{ id = "BinHooded", pack = "Street Asset Pack V3", find = "Hooded Top Bin round", scale = 1.25 },
	{ id = "BinSquare", pack = "Street Asset Pack V3", find = "Square Litter Bin - CSGStudios", scale = 1.25 },
	{ id = "BinPark", pack = "Street Asset Pack V3", find = "Park Bin", scale = 1.25 },
	{ id = "KeepLeft", pack = "Street Asset Pack V3", find = "Keep Left Bollard - CSG Studios", scale = 1.3 },
	{ id = "Guardrail", pack = "Street Asset Pack V3", find = "Pedestrian Guardrail - CSG Studios", scale = 1.1 },
	{ id = "RoadworksBarrier", pack = "Street Asset Pack V3", find = "Road Works Barrier - CSGStudios", scale = 1.1 },
	{ id = "Cone", pack = "Street Asset Pack V3", find = "Traffic Cone", scale = 1.2 },
	{ id = "GiveWay", pack = "Street Asset Pack V3", find = "Give Way", scale = 1.35 },
	{ id = "NoEntry", pack = "Street Asset Pack V3", find = "No Entry", scale = 1.35 },
	{ id = "OneWay", pack = "Street Asset Pack V3", find = "One Way", scale = 1.35 },
	{ id = "MiniRoundabout", pack = "Street Asset Pack V3", find = "Mini Roundabout", scale = 1.35 },
	{ id = "Limit10", pack = "Street Asset Pack V3", find = "Speed Limit 10", scale = 1.35 },
	{ id = "Limit20", pack = "Street Asset Pack V3", find = "Speed Limit 20", scale = 1.35 },
	{ id = "Limit30", pack = "Street Asset Pack V3", find = "Speed Limit 30", scale = 1.35 },
	{ id = "Limit40", pack = "Street Asset Pack V3", find = "Speed Limit 40", scale = 1.35 },
	{ id = "Limit50", pack = "Street Asset Pack V3", find = "Speed Limit 50", scale = 1.35 },
	{ id = "Limit60", pack = "Street Asset Pack V3", find = "Speed Limit 60", scale = 1.35 },
	{ id = "NationalLimit", pack = "Street Asset Pack V3", find = "National Speed Limit", scale = 1.35 },
	{ id = "SpeedCameraSign", pack = "Street Asset Pack V3", find = "Speed Camera Sign", scale = 1.35 },
	{ id = "Bollard", pack = "AHDEV Roads", find = "Bollard", scale = 1.2 },
	{ id = "ArrowAhead", pack = "AHDEV Roads", find = "[MARK] S Arrow", scale = 1.0, flat = true },
	{ id = "ArrowLeftAhead", pack = "AHDEV Roads", find = "[MARK] LS Arrow", scale = 1.0, flat = true },
	-- A proper tree (a trunk and a ball of leaves, both meshes) from the "UK Map PBR" village map
	{ id = "Tree", pack = "UK Map PBR", tree = true, scale = 1.0 },
	-- A bush (just a ball of leaves) from the same map, scaled up
	{ id = "Bush", pack = "UK Map PBR", bush = true, scale = 4.0 },
}

-- The first model in `pack` that's only a small ball of "Leaves" (a bush)
local function findBush(pack: Instance): Instance?
	for _, d in pack:GetDescendants() do
		if d:IsA("Model") and d:FindFirstChild("Leaves") and not d:FindFirstChild("Bark") and #d:GetChildren() == 1 then
			return d
		end
	end
	return nil
end

-- The first model in `pack` made of a "Bark" trunk and "Leaves"
local function findTree(pack: Instance): Instance?
	for _, d in pack:GetDescendants() do
		if d:IsA("Model") and d:FindFirstChild("Bark") and d:FindFirstChild("Leaves") then
			return d
		end
	end
	return nil
end

local summary = {} -- one line per prop, printed at the end

local REMOVE_CLASSES = {
	Script = true, LocalScript = true, ModuleScript = true, Sound = true, ProximityPrompt = true,
	ClickDetector = true, ScreenGui = true, BillboardGui = true, Camera = true, RemoteEvent = true,
	RemoteFunction = true, BindableEvent = true, BindableFunction = true, ParticleEmitter = true,
	Configuration = true, Humanoid = true,
}

local blocked = {}
for _, id in BLOCKED_IMAGES do
	blocked[tostring(id)] = true
end

local function imageId(object: Instance): string?
	local ok, value = pcall(function()
		return if object:IsA("ImageLabel") then object.Image else (object :: any).Texture
	end)
	return if ok and type(value) == "string" then value:match("(%d%d%d%d%d+)") else nil
end

local function bounds(model: Model, includeHidden: boolean?): (Vector3, Vector3)
	local lo, hi = Vector3.one * math.huge, -Vector3.one * math.huge
	for _, p in model:GetDescendants() do
		if p:IsA("BasePart") and (includeHidden or p.Transparency < 0.98) then
			local h = p.Size / 2
			for _, sx in { -1, 1 } do
				for _, sy in { -1, 1 } do
					for _, sz in { -1, 1 } do
						local c = p.CFrame:PointToWorldSpace(Vector3.new(sx * h.X, sy * h.Y, sz * h.Z))
						lo = lo:Min(c)
						hi = hi:Max(c)
					end
				end
			end
		end
	end
	-- Road arrows are see-through parts with a picture on top: measure those too
	if lo.X == math.huge and not includeHidden then
		return bounds(model, true)
	end
	return lo, hi
end

local function clean(model: Model)
	for _, d in model:GetDescendants() do
		if d.Parent == nil then
			continue
		end
		if REMOVE_CLASSES[d.ClassName] or d:IsA("ValueBase") or d:IsA("BodyMover") or d:IsA("Constraint") then
			d:Destroy()
		elseif d:IsA("Decal") or d:IsA("Texture") then
			local id = imageId(d)
			if id and blocked[id] then
				d:Destroy()
			end
		elseif d:IsA("BasePart") then
			d.Anchored = true
			d.CanTouch = false
			-- Little bits (screws, lettering) don't need to block anything
			if d.Size.Magnitude < 1.2 then
				d.CanCollide = false
				d.CanQuery = false
			end
		end
	end
end

-- The traffic light's lamps: Red, Yellow → Amber, Green. They start see-through in the pack (its own script
-- showed them); TrafficLights colours them instead, so they're made solid and moved to the top of the model.
local function wireLamps(model: Model)
	for _, name in { "Red", "Yellow", "Green" } do
		local lamp = model:FindFirstChild(name, true)
		if lamp and lamp:IsA("BasePart") then
			lamp.Name = if name == "Yellow" then "Amber" else name
			lamp.Transparency = 0
			lamp.Material = Enum.Material.SmoothPlastic
			lamp.Color = Color3.fromRGB(38, 36, 34)
			lamp.Parent = model
		end
	end
end

-- A yellow plate over the camera maker's logo, a small tag in the bottom corner of the box's front
local function coverLogo(model: Model)
	local camera = model:FindFirstChildWhichIsA("MeshPart", true)
	if not camera then
		return
	end
	local lo, hi = bounds(model)
	model.Parent = Workspace
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { camera }
	-- Find the front face of the box: rays from in front, over the top half of the camera
	local front = math.huge
	local minX, maxX, minY, maxY = math.huge, -math.huge, math.huge, -math.huge
	for x = lo.X + 0.1, hi.X - 0.1, 0.15 do
		for y = hi.Y - 6, hi.Y - 0.05, 0.15 do
			local hit = Workspace:Raycast(Vector3.new(x, y, lo.Z - 10), Vector3.new(0, 0, 40), params)
			if hit then
				front = math.min(front, hit.Position.Z)
			end
		end
	end
	for x = lo.X + 0.1, hi.X - 0.1, 0.15 do
		for y = hi.Y - 6, hi.Y - 0.05, 0.15 do
			local hit = Workspace:Raycast(Vector3.new(x, y, lo.Z - 10), Vector3.new(0, 0, 40), params)
			if hit and hit.Position.Z < front + 0.3 then
				minX, maxX = math.min(minX, x), math.max(maxX, x)
				minY, maxY = math.min(minY, y), math.max(maxY, y)
			end
		end
	end
	model.Parent = nil
	if front == math.huge then
		warn("[Props] couldn't find the speed camera's front")
		return
	end
	local w, h = maxX - minX, maxY - minY
	-- Looking at the front from -Z, +X is on the left: the tag is near the left (+X) edge, low down
	local x0, x1 = maxX - w * 0.32, maxX - w * 0.02
	local y0, y1 = minY + h * 0.04, minY + h * 0.26
	local plate = Instance.new("Part")
	plate.Name = "LogoCover"
	plate.Anchored = true
	plate.CanCollide = false
	plate.CanQuery = false
	plate.CanTouch = false
	plate.Size = Vector3.new(x1 - x0, y1 - y0, 0.06)
	plate.CFrame = CFrame.new((x0 + x1) / 2, (y0 + y1) / 2, front - 0.04)
	plate.Color = Color3.fromRGB(206, 170, 38)
	plate.Material = Enum.Material.SmoothPlastic
	plate.Parent = model
	print(string.format("[Props] speed camera logo covered: box front %.2f, %.1f x %.1f", front, w, h))
end

local function prepare(source: Instance, entry): Model
	local model: Model
	if source:IsA("Model") then
		model = source:Clone()
	else
		model = Instance.new("Model")
		source:Clone().Parent = model
	end
	model.Name = entry.id
	clean(model)
	if entry.id == "TrafficLight" then
		wireLamps(model)
	end
	if entry.scale and entry.scale ~= 1 then
		model:ScaleTo(model:GetScale() * entry.scale)
	end
	if entry.turn and entry.turn ~= 0 then
		local lo, hi = bounds(model)
		local centre = (lo + hi) / 2
		model:PivotTo(CFrame.new(centre) * CFrame.Angles(0, math.rad(entry.turn), 0) * CFrame.new(centre):Inverse() * model:GetPivot())
	end
	-- Pivot on the ground under the middle, at the origin
	local lo, hi = bounds(model)
	model.WorldPivot = CFrame.new((lo.X + hi.X) / 2, lo.Y, (lo.Z + hi.Z) / 2)
	model:PivotTo(CFrame.new())
	if entry.id == "SpeedCamera" then
		coverLogo(model)
	end
	model.WorldPivot = CFrame.new()
	lo, hi = bounds(model)
	local size = hi - lo
	local parts = 0
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			parts += 1
		end
	end
	model:SetAttribute("Height", math.round(size.Y * 100) / 100)
	model:SetAttribute("Width", math.round(size.X * 100) / 100)
	model:SetAttribute("Depth", math.round(size.Z * 100) / 100)
	model:SetAttribute("Parts", parts)
	if entry.flat then
		model:SetAttribute("Flat", true)
	end
	table.insert(summary, string.format("%s %.1fx%.1fx%.1f/%d", entry.id, size.X, size.Y, size.Z, parts))
	return model
end

local import = ServerStorage:FindFirstChild("PackImport")
assert(import, "Put the packs in ServerStorage → PackImport first")
local out = ServerStorage:FindFirstChild("PropKit") or Instance.new("Folder")
out.Name = "PropKit"
out:ClearAllChildren()
local made = 0
for _, entry in KIT do
	local pack = import:FindFirstChild(entry.pack)
	local source = if pack and entry.tree then findTree(pack) elseif pack and entry.bush then findBush(pack) elseif pack then pack:FindFirstChild(entry.find, true) else nil
	if source and entry.child then
		local children = {}
		for _, c in source:GetChildren() do
			if c:IsA("Model") then
				table.insert(children, c)
			end
		end
		source = children[entry.child]
	end
	if source then
		local ok, result = pcall(prepare, source, entry)
		if ok then
			result.Parent = out
			made += 1
		else
			warn("[Props] " .. entry.id .. " failed: " .. tostring(result))
		end
	else
		warn("[Props] couldn't find " .. (entry.find or entry.id) .. " in " .. entry.pack)
	end
end
out.Parent = ServerStorage
print("[Props] done: " .. made .. " props in ServerStorage.PropKit: " .. table.concat(summary, " | "))
