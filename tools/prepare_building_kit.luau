--!nocheck
-- Turns the bought and free building packs into a kit of clean buildings that LondonMap puts along the streets.
--
-- How to use it, in Roblox Studio:
--   1. The packs go in ServerStorage → PackImport (bought packs keep a "SourceAssetId" attribute; the free
--      .rbxm models sit there under their own names).
--   2. Paste this whole file into the Command Bar and press Enter.
--   3. The kit appears in ServerStorage → BuildingKit. Press Play: LondonMap uses it straight away.
--
-- What it does to each building:
--   - deletes every script, sound, prompt, seat and GUI button (none of the packs had backdoors, checked
--     17 Oct 2026, but the map doesn't need any of them)
--   - deletes real logos (see BLOCKED_IMAGES)
--   - turns it so its front faces -Z, and moves it so the middle of its front edge is at (0, 0, 0) on the ground
--   - writes its Width, Depth, Height, Kind and Weight (how often to use it) as attributes
-- The pack files never go in the git repo: the kit lives only in the place file.

local ServerStorage = game:GetService("ServerStorage")

-- Real logos found in the packs: the Police Scotland crest and the National Lottery sign
local BLOCKED_IMAGES = { 5664435353, 9610363007 }

-- The free houses from the "Starz Production" .rbxm are built bigger than the rest
local ZIP_SCALE = 0.8

-- Each entry: how to find the building, its kind, which way its front faces in the pack, and how often to use it.
-- Kinds: "terrace" (a row of houses), "semi" (a pair), "detached", "large" (big detached), "shop", "shopwide".
-- turn: degrees to turn it so the front faces -Z (worked out by looking at them from every side)
local KIT = {
	{ id = "terrace_a", pack = "UK House Pack", path = { "UK House Pack", "Model3" }, kind = "terrace", turn = 0, weight = 4 },
	{ id = "terrace_b", pack = "UK House Pack", path = { "UK House Pack", "Model4" }, kind = "terrace", turn = 0, weight = 4 },
	{ id = "semi_a", pack = "UK House Pack", path = { "UK House Pack", "Model1" }, kind = "semi", turn = 0, weight = 3 },
	{ id = "semi_b", pack = "UK House Pack", path = { "UK House Pack", "Model2" }, kind = "semi", turn = 0, weight = 3 },
	{ id = "semi_c", pack = "UK House Pack", path = { "UK House Pack", "Model6" }, kind = "semi", turn = 0, weight = 2 },
	{ id = "detached_a", pack = "UK House Pack", path = { "UK House Pack", "Model5" }, kind = "detached", turn = 0, weight = 2 },
	{ id = "detached_b", pack = "UK House Pack", path = { "UK House Pack", "Model9" }, kind = "detached", turn = 0, weight = 2 },
	{ id = "detached_c", pack = "UK House Pack", path = { "UK House Pack", "Model7" }, kind = "detached", turn = 0, weight = 1 },
	{ id = "detached_d", pack = "UK House Pack", path = { "UK House Pack", "Model8" }, kind = "detached", turn = 0, weight = 1 },
	{ id = "gosford", pack = "The Gosford", kind = "detached", turn = -90, weight = 1, scale = ZIP_SCALE },
	{ id = "gosford_double", pack = "The Gosford Double", kind = "semi", turn = -90, weight = 1, scale = ZIP_SCALE },
	{ id = "mitchell", pack = "The Mitchell", kind = "large", turn = -90, weight = 1, scale = ZIP_SCALE },
	{ id = "windsor", pack = "The Windsor", kind = "large", turn = 90, weight = 1, scale = ZIP_SCALE },
	{ id = "darwick", pack = "The Darwick", kind = "large", turn = -90, weight = 1, scale = ZIP_SCALE },
	{ id = "morton", pack = "The Morton", kind = "large", turn = -90, weight = 1, scale = ZIP_SCALE },
	{ id = "duggen", pack = "The Duggen", kind = "large", turn = -90, weight = 1, scale = ZIP_SCALE },
}

local REMOVE_CLASSES = {
	Script = true, LocalScript = true, ModuleScript = true, Sound = true, ProximityPrompt = true,
	ClickDetector = true, ScreenGui = true, Camera = true, RemoteEvent = true, RemoteFunction = true,
	BindableEvent = true, BindableFunction = true, Humanoid = true, Tool = true, Dialog = true,
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

-- Box round everything you can see, in world space
local function bounds(model: Model): (Vector3, Vector3)
	local lo, hi = Vector3.one * math.huge, -Vector3.one * math.huge
	for _, p in model:GetDescendants() do
		if p:IsA("BasePart") and p.Transparency < 0.95 then
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
	return lo, hi
end

local function clean(model: Model)
	for _, d in model:GetDescendants() do
		if d.Parent == nil then
			continue
		end
		if REMOVE_CLASSES[d.ClassName] or d:IsA("ValueBase") then
			d:Destroy()
		elseif d:IsA("Seat") or d:IsA("VehicleSeat") then
			-- Keep the look, lose the sitting: swap the seat for a plain part
			local plain = Instance.new("Part")
			plain.Size, plain.CFrame, plain.Color, plain.Material = d.Size, d.CFrame, d.Color, d.Material
			plain.Transparency = d.Transparency
			plain.Parent = d.Parent
			d:Destroy()
		elseif d:IsA("Decal") or d:IsA("Texture") then
			local id = imageId(d)
			if id and blocked[id] then
				d:Destroy()
			end
		elseif d:IsA("BasePart") then
			d.Anchored = true
			d.CanTouch = false
		end
	end
end

local function find(entry): Model?
	local import = ServerStorage:FindFirstChild("PackImport")
	if not import then
		return nil
	end
	local node = import:FindFirstChild(entry.pack)
	for _, name in entry.path or {} do
		node = node and node:FindFirstChild(name)
	end
	return if node and node:IsA("Model") then node else nil
end

local function prepare(source: Model, entry): Model
	local building = source:Clone()
	building.Name = entry.id
	clean(building)
	if entry.scale then
		building:ScaleTo(building:GetScale() * entry.scale)
	end
	-- Turn it so the front faces -Z
	local lo, hi = bounds(building)
	local centre = (lo + hi) / 2
	building:PivotTo(CFrame.new(centre) * CFrame.Angles(0, math.rad(entry.turn), 0) * CFrame.new(centre):Inverse() * building:GetPivot())
	-- Pivot at the middle of the front edge, on the ground
	lo, hi = bounds(building)
	local size = hi - lo
	building.WorldPivot = CFrame.new((lo.X + hi.X) / 2, lo.Y, lo.Z)
	building:PivotTo(CFrame.new())
	building.WorldPivot = CFrame.new()
	building.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	-- A low-detail stand-in far away (only Studio can set this, so it's set here on the kit, and copies keep it)
	building.LevelOfDetail = Enum.ModelLevelOfDetail.StreamingMesh

	local parts = 0
	for _, d in building:GetDescendants() do
		if d:IsA("BasePart") then
			parts += 1
		end
	end
	building:SetAttribute("Width", math.round(size.X * 10) / 10)
	building:SetAttribute("Depth", math.round(size.Z * 10) / 10)
	building:SetAttribute("Height", math.round(size.Y * 10) / 10)
	building:SetAttribute("Kind", entry.kind)
	building:SetAttribute("Weight", entry.weight)
	building:SetAttribute("Parts", parts)
	print(string.format("[Kit] %-15s %-9s %5.1f wide %5.1f deep %5.1f tall  %4d parts", entry.id, entry.kind, size.X, size.Z, size.Y, parts))
	return building
end

-- The shops in the UK Shop Pack aren't named, so they're found by size: narrow 3-storey shops and wide ones.
-- The block with no shopfront (lots of parts, no shop window) is left out.
local function shopEntries()
	local entries = {}
	local import = ServerStorage:FindFirstChild("PackImport")
	local pack = import and import:FindFirstChild("UK Shop Pack")
	local inner = pack and pack:FindFirstChild("Model")
	if not inner then
		return entries
	end
	local count = 0
	for _, shop in inner:GetChildren() do
		if shop:IsA("Model") then
			local lo, hi = bounds(shop)
			local width = math.min(hi.X - lo.X, hi.Z - lo.Z)
			local parts = 0
			for _, d in shop:GetDescendants() do
				if d:IsA("BasePart") then
					parts += 1
				end
			end
			if parts < 150 then
				count += 1
				local wide = (hi.X - lo.X) > 30
				table.insert(entries, { model = shop, entry = { id = "shop_" .. count, kind = if wide then "shopwide" else "shop", turn = 0, weight = if wide then 2 else 3 } })
			end
		end
	end
	return entries
end

local out = ServerStorage:FindFirstChild("BuildingKit") or Instance.new("Folder")
out.Name = "BuildingKit"
out:ClearAllChildren()
local made = 0
for _, entry in KIT do
	local source = find(entry)
	if source then
		local ok, result = pcall(prepare, source, entry)
		if ok then
			result.Parent = out
			made += 1
		else
			warn("[Kit] " .. entry.id .. " failed: " .. tostring(result))
		end
	else
		warn("[Kit] couldn't find " .. entry.id .. " in PackImport")
	end
end
for _, shop in shopEntries() do
	local ok, result = pcall(prepare, shop.model, shop.entry)
	if ok then
		result.Parent = out
		made += 1
	else
		warn("[Kit] " .. shop.entry.id .. " failed: " .. tostring(result))
	end
end
out.Parent = ServerStorage
print("[Kit] done: " .. made .. " buildings in ServerStorage.BuildingKit")
