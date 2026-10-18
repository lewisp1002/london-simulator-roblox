--!nocheck
-- Turns the free Swat Motors Company models into clean vehicle bodies for London Simulator.
--
-- How to use it, in Roblox Studio:
--   1. Put the models in ServerStorage → SwatImport (each one keeps a "SourceAssetId" attribute).
--   2. Paste this whole file into the Command Bar and press Enter.
--   3. The clean bodies appear in ServerStorage → VehicleBodies, one per vehicle id in Shared → Vehicles.
--
-- What it does to each model:
--   - shrinks it to the map's scale (the models are built bigger than Birmingham Vehicle Simulator's roads)
--   - deletes every script, sound, GUI button, joint and constraint (our own Driving script drives the car)
--   - turns the body so the front faces -Z with the middle of its footprint at (0, 0, 0)
--   - remembers where the seats were, then removes them (CarBuilder adds our own seats there)
--   - finds the four wheels and tags their parts so they can spin and steer
--   - tags lamps with a LightRole (Head, Tail, IndicatorL, IndicatorR, BlueA, BlueB) and switches them off
--   - tags the main body colour as "Paint" so Customise can repaint it
-- The bought or free model files never go in the git repo: they live only in the place file.

local ServerStorage = game:GetService("ServerStorage")

-- Swat Motors asset id → our vehicle id (see src/shared/Vehicles.luau)
local MAP = {
	[89070722089679] = "norvik_response",
	[106975271979574] = "halden_astor_response",
	[84016430676957] = "halden_vantage_ambulance",
	[90105689540205] = "brenner_paramedic",
	[16789590062] = "police_carrier",
	[15138451631] = "norvik_traffic",
	[131830276463649] = "norvik_urgent_care",
	[17417606954] = "norvik_admin",
	[115892029228205] = "halden_astor",
	[120637461864767] = "halden_senator",
	[101653893168052] = "aurel_comet",
	[116782045743039] = "jaxon_xr",
	[94390892021767] = "volta_glide",
	[113405241973181] = "ridgeline_sport",
	[135224262991601] = "capital_enviro",
	[74064065564710] = "heritage_decker",
	[84805351808482] = "metro_citaro",
	-- Not Swat Motors: a free 2020+ G20-shape saloon (the "Bmw M340i" model by boomsaell), checked 18 Oct 2026:
	-- its only scripts are its own A-Chassis driving scripts, which are deleted like all scripts
	[14001785089] = "brenner_340",
	-- Not Swat Motors: a free 2017 F20 facelift M140i hatch with an M Performance front splitter and a full
	-- interior and engine bay (the "M140i" model by IoudM5, uploaded Dec 2023), checked 18 Oct 2026: its scripts
	-- are A-Chassis and CarPlay (no backdoors found), and all of them are deleted like every model's
	[15521430429] = "brenner_140",
}

-- Models that aren't Swat Motors' size: the length (in studs) to scale them to, so they match the other cars
local TARGET_LENGTH = {
	[14001785089] = 17.6,
	[15521430429] = 16.2, -- 4.32 m long against the G20's 4.71 m
}

-- Models whose dashboard screens show real maker logos: every picture on their screens is removed
local STRIP_SCREENS = {
	[14001785089] = true,
	[15521430429] = true,
}

-- Models whose body colour is shared with their windows and trim, so the most-used colour can't be trusted:
-- this picks the painted panels instead, from each part and the group it came from in the original model
local PAINT_PICK = {
	[15521430429] = function(part: BasePart, group: string): boolean
		local c = part.Color
		if math.floor(c.R * 255 + 0.5) ~= 17 or part.Material ~= Enum.Material.SmoothPlastic then
			return false
		end
		if group ~= "Body" and group ~= "Model" and group ~= "m140i" then
			return false -- the interior, roll cage, engine bay and wheels have their own groups
		end
		local name = part.Name:lower()
		for _, word in { "glass", "window", "windscreen", "light", "lamp", "int", "bottom", "trim", "chrome", "grill", "black" } do
			if name:find(word) then
				return false
			end
		end
		if name == "bumperfront02" then
			return false -- the honeycomb mesh in the bumper's air intakes, black on the real car
		end
		return math.max(part.Size.X, part.Size.Y, part.Size.Z) > 3.5
	end,
}

-- Lamps placed by hand, for models whose own lamps can't be found by colour. Each one sits on the outside of
-- the lens, invisible until it's switched on, then glows (headlights also throw a beam). Positions are for the
-- right-hand side of the finished body (front facing -Z) and are mirrored for the left; `normal` is the way the
-- lens faces, measured by raycasting the lens. Indicators get IndicatorL / IndicatorR by side.
local LAMPS = {
	[15521430429] = {
		{ role = "Head", at = Vector3.new(1.85, 2.22, -7.47), normal = Vector3.new(0.33, 0, -0.94), size = Vector2.new(0.55, 0.32) },
		{ role = "Head", at = Vector3.new(2.38, 2.2, -7.18), normal = Vector3.new(0.6, -0.05, -0.8), size = Vector2.new(0.5, 0.3), beam = false },
		{ role = "Indicator", at = Vector3.new(2.76, 2.24, -6.78), normal = Vector3.new(0.82, 0, -0.57), size = Vector2.new(0.32, 0.22) },
		{ role = "Tail", at = Vector3.new(1.7, 2.95, 7.53), normal = Vector3.new(0.18, 0, 0.98), size = Vector2.new(0.72, 0.32) },
		{ role = "Tail", at = Vector3.new(2.48, 3.0, 7.22), normal = Vector3.new(0.6, 0.05, 0.8), size = Vector2.new(0.5, 0.3) },
		{ role = "Indicator", at = Vector3.new(2.55, 2.8, 7.16), normal = Vector3.new(0.62, 0, 0.78), size = Vector2.new(0.42, 0.14) },
	},
}

-- Left-hand-drive models made right-hand drive, like UK cars: the seats swap sides, and the steering wheel and
-- instrument cluster move across (parts whose place in the original model mentions one of these words)
local RIGHT_HAND_DRIVE = {
	[15521430429] = { "steer", "cluster", "gauge", "paddle", "stalk" },
}

local LAMP_COLOURS = {
	Head = Color3.fromRGB(255, 250, 235),
	Tail = Color3.fromRGB(255, 25, 25),
	Indicator = Color3.fromRGB(255, 140, 20),
}

-- Odd jobs for particular models, done on the finished body
local FIXES = {
	[15521430429] = function(body: Model)
		for _, part in body:GetChildren() do
			if part:IsA("BasePart") then
				local name = part.Name:lower()
				local c = part.Color
				if name:find("windscreen") or name:find("window") then
					-- Each window is two layers of dark tint, which looks solid black: thin them so you can see in
					part.Transparency = math.max(part.Transparency, 0.6)
				elseif name == "spacewall" then
					-- A hidden panel inside the nose with a starry space picture on it, which shows through the grille
					for _, texture in part:GetChildren() do
						if texture:IsA("Texture") or texture:IsA("Decal") then
							texture:Destroy()
						end
					end
					part.Color = Color3.fromRGB(15, 15, 15)
				elseif c.R > 0.55 and c.B > 0.55 and c.G < 0.45 then
					-- Suspension arms whose texture doesn't load show bright pink behind the wheels
					part.Color = Color3.fromRGB(45, 45, 48)
				end
			end
		end
	end,
}

-- Badges moulded into a model's trim, which can't be deleted on their own: a disc in the body colour goes over
-- them (like a "badge delete" on a real car). Positions are on the finished body (front facing -Z).
local BADGE_COVERS = {
	[14001785089] = {
		{ at = Vector3.new(0, 2.55, -8.2), normal = Vector3.new(0, 0.5, -0.87), size = 0.6 }, -- bonnet roundel
	},
	[15521430429] = {
		{ at = Vector3.new(0, 2.56, -7.66), normal = Vector3.new(0, 0.83, -0.55), size = 0.42 }, -- roundel above the grille
	},
}

-- Parts near a wheel with these words in their name are suspension, not wheel: they stay still while it spins
local NOT_WHEEL = { "spring", "arm", "hub", "caliper", "strut", "knuckle", "damper", "shock", "coil", "axle" }

-- Parts named like this are real makers' badges, whatever picture they use
local BADGE_NAMES = { "logo", "emblem", "badge", "roundel" }

-- The Swat Motors models are about 0.22 m per stud; our roads are about 0.28 m per stud (like BVS).
-- 0.85 brings them most of the way while leaving room for Roblox characters inside.
local SCALE = 0.85

-- For models with no driver's seat to show which way is forward: degrees to turn the longest side to the front
local FORWARD_FIX = {}

-- Real car makers', bus companies', police forces' and NHS logos on the models. They're deleted.
local BLOCKED_IMAGES = {
	3946766101, -- "320" boot badge on the Brenner 340
	5009638877, -- wheel maker's logo on the Brenner 340's wheel centre caps
	1047780746, 11093189043, 1175618086, 11945221907, 124404822, 1252155118, 1321764097, 137867839,
	2243392468, 252036847, 2639188808, 2639273016, 2639273313, 287507682, 319672700, 344795094,
	367088684, 388468713, 5143806516, 5509202736, 57261056, 5860703384, 729244061, 8418472588, 85649240,
}

-- Real names printed on the models, swapped for our own made-up ones
local TEXT_SWAPS = {
	["www.met.police.uk"] = "",
	["LONDON TRANSPORT"] = "CAPITAL TRANSPORT",
	["North West  Ambulance Service"] = "Capital Ambulance Service",
	["CHESHIRE POLICE"] = "POLICE",
	["CRIME STOPPERS"] = "",
	["0800 555 111"] = "",
	["Not In Service"] = "73  Oxford Circus",
	["Not in Service"] = "38  Victoria",
}

local function imageId(object: Instance): string?
	local ok, value = pcall(function()
		return if object:IsA("ImageLabel") or object:IsA("ImageButton") then object.Image else (object :: any).Texture
	end)
	return if ok and type(value) == "string" then value:match("(%d%d%d%d%d+)") else nil
end

local REMOVE_CLASSES = {
	Script = true, LocalScript = true, ModuleScript = true, Sound = true, ProximityPrompt = true,
	ClickDetector = true, ScreenGui = true, BillboardGui = true, RemoteEvent = true, RemoteFunction = true,
	BindableEvent = true, BindableFunction = true, Animation = true, ParticleEmitter = true, Fire = true,
	Smoke = true, Sparkles = true, Beam = true, Trail = true, Humanoid = true, Configuration = true,
	ForceField = true, Explosion = true, Dialog = true, Tool = true, AnimationController = true,
}

local function shouldRemove(object: Instance): boolean
	if REMOVE_CLASSES[object.ClassName] then
		return true
	end
	return object:IsA("ValueBase") or object:IsA("JointInstance") or object:IsA("WeldConstraint")
		or object:IsA("Constraint") or object:IsA("BodyMover") or object:IsA("Attachment")
		or object:IsA("NoCollisionConstraint") or object:IsA("GuiButton") or object:IsA("TextBox")
end

local function isVisible(part: BasePart): boolean
	return part.Transparency < 0.95
end

local function hasDecoration(part: BasePart): boolean
	for _, child in part:GetChildren() do
		if child:IsA("Light") or child:IsA("SurfaceGui") or child:IsA("Decal") then
			return true
		end
	end
	return false
end

local function classify(colour: Color3): string?
	local r, g, b = colour.R, colour.G, colour.B
	if b > 0.45 and b > r * 1.4 and b > g * 1.15 then
		return "Blue"
	elseif r > 0.5 and g < 0.38 and b < 0.38 then
		return "Red"
	elseif r > 0.6 and g > 0.3 and g < 0.85 and b < 0.35 then
		return "Amber"
	elseif r > 0.75 and g > 0.75 and b > 0.6 then
		return "White"
	end
	return nil
end

local function sortedDims(size: Vector3): (number, number, number)
	local d = { size.X, size.Y, size.Z }
	table.sort(d)
	return d[1], d[2], d[3]
end

local function visibleLength(model: Model): number
	local lo, hi = Vector3.one * math.huge, -Vector3.one * math.huge
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and d.Transparency < 0.95 then
			lo = lo:Min(d.Position - d.Size / 2)
			hi = hi:Max(d.Position + d.Size / 2)
		end
	end
	local size = hi - lo
	return math.max(size.X, size.Z)
end

local function prepare(source: Model, vehicleId: string): Model
	local body = source:Clone()
	body.Name = vehicleId
	local sourceId = source:GetAttribute("SourceAssetId")
	local target = TARGET_LENGTH[sourceId]
	if target then
		body:ScaleTo(body:GetScale() * target / visibleLength(body))
	else
		body:ScaleTo(body:GetScale() * SCALE)
	end
	-- Badges by name, and dashboard screens that show real logos
	for _, d in body:GetDescendants() do
		if d.Parent then
			local name = d.Name:lower()
			local isBadge = false
			for _, word in BADGE_NAMES do
				if name:find(word) then
					isBadge = true
				end
			end
			if isBadge and (d:IsA("BasePart") or d:IsA("Decal") or d:IsA("Texture") or d:IsA("SurfaceGui") or d:IsA("Model")) then
				d:Destroy()
			elseif STRIP_SCREENS[sourceId] and (d:IsA("ImageLabel") or d:IsA("ImageButton")) then
				d:Destroy()
			end
		end
	end

	-- Seats: remember where they are (the driver's seat also tells us which way is forward)
	local driver: BasePart? = nil
	local seats: { BasePart } = {}
	for _, d in body:GetDescendants() do
		if d:IsA("VehicleSeat") then
			if not driver or d.Name == "VehicleSeat" or d.Name == "DriveSeat" then
				if driver and driver ~= d then
					table.insert(seats, driver)
				end
				driver = d
			else
				table.insert(seats, d)
			end
		elseif d:IsA("Seat") then
			table.insert(seats, d)
		end
	end

	-- Every part goes straight under the body first: some sit inside joints or scripts that are about to go.
	-- Which group each part came from is remembered for PAINT_PICK.
	local groupOf: { [BasePart]: string } = {}
	local pathOf: { [BasePart]: string } = {}
	for _, d in body:GetDescendants() do
		if d:IsA("BasePart") then
			groupOf[d] = if d.Parent then d.Parent.Name else ""
			pathOf[d] = d:GetFullName():lower()
			d.Parent = body
		end
	end

	-- Strip everything that isn't looks
	for _, d in body:GetDescendants() do
		if d.Parent and shouldRemove(d) then
			d:Destroy()
		end
	end
	-- Real logos and names
	local blocked = {}
	for _, id in BLOCKED_IMAGES do
		blocked[tostring(id)] = true
	end
	for _, d in body:GetDescendants() do
		if d:IsA("Decal") or d:IsA("ImageLabel") or d:IsA("ImageButton") then
			local id = imageId(d)
			if id and blocked[id] then
				d:Destroy()
			end
		elseif d:IsA("MeshPart") then
			local id = d.TextureID:match("(%d%d%d%d%d+)")
			if id and blocked[id] then
				d.TextureID = ""
			end
		elseif d:IsA("TextLabel") then
			local swap = TEXT_SWAPS[d.Text]
			if swap then
				d.Text = swap
			end
			d.Text = d.Text:gsub("NHS", "")
		end
	end

	-- SurfaceGuis that sit outside a part get moved onto the part they draw on
	for _, d in body:GetDescendants() do
		if d:IsA("SurfaceGui") and not (d.Parent and d.Parent:IsA("BasePart")) then
			if d.Adornee and d.Adornee:IsDescendantOf(body) then
				d.Parent = d.Adornee
			else
				d:Destroy()
			end
		end
	end

	-- Which way is forward
	local forward: Vector3
	if driver then
		forward = driver.CFrame.LookVector * Vector3.new(1, 0, 1)
	else
		local cf, size = body:GetBoundingBox()
		forward = if size.X > size.Z then cf.RightVector else cf.LookVector
		forward *= Vector3.new(1, 0, 1)
	end
	forward = forward.Unit
	local turn = FORWARD_FIX[body:GetAttribute("SourceAssetId")]
	if turn then
		forward = (CFrame.Angles(0, math.rad(turn), 0) * CFrame.new(forward)).Position.Unit
	end
	local rotation = CFrame.lookAt(Vector3.zero, forward)

	-- Footprint in that direction, from the visible parts only
	local minV, maxV = Vector3.one * math.huge, -Vector3.one * math.huge
	for _, d in body:GetDescendants() do
		if d:IsA("BasePart") and isVisible(d) and not d:IsA("Seat") and not d:IsA("VehicleSeat") then
			local half = d.Size / 2
			for _, sx in { -1, 1 } do
				for _, sy in { -1, 1 } do
					for _, sz in { -1, 1 } do
						local corner = d.CFrame:PointToWorldSpace(Vector3.new(sx * half.X, sy * half.Y, sz * half.Z))
						local p = rotation:PointToObjectSpace(corner)
						minV = minV:Min(p)
						maxV = maxV:Max(p)
					end
				end
			end
		end
	end
	local centre = Vector3.new((minV.X + maxV.X) / 2, minV.Y, (minV.Z + maxV.Z) / 2)
	local pivot = CFrame.new(rotation:PointToWorldSpace(centre)) * rotation.Rotation
	local size = maxV - minV

	-- Seat positions relative to the new pivot, then remove the seats. Right-hand drive swaps them side to side.
	local rhd = RIGHT_HAND_DRIVE[sourceId]
	local function seatSpot(seat: BasePart): CFrame
		local spot = pivot:ToObjectSpace(seat.CFrame)
		return if rhd then CFrame.new(-spot.X, spot.Y, spot.Z) * spot.Rotation else spot
	end
	if driver then
		body:SetAttribute("DriverSeat", seatSpot(driver))
	end
	local count = 0
	for _, seat in seats do
		count += 1
		body:SetAttribute("Seat" .. count, seatSpot(seat))
	end
	body:SetAttribute("SeatCount", count)

	-- Move the body so its pivot is at the origin facing -Z
	body.WorldPivot = pivot
	body:PivotTo(CFrame.new())

	-- Right-hand drive: the steering wheel and dials move across to the other side, as one piece
	if rhd then
		local moving: { BasePart } = {}
		local sumX = 0
		for _, d in body:GetChildren() do
			if d:IsA("BasePart") then
				for _, word in rhd do
					if (pathOf[d] or ""):find(word) then
						table.insert(moving, d)
						sumX += d.Position.X
						break
					end
				end
			end
		end
		if #moving > 0 then
			local shift = Vector3.new(-2 * sumX / #moving, 0, 0)
			for _, d in moving do
				d.CFrame += shift
			end
		end
		print(string.format("[Bodies] %s: right-hand drive, moved %d steering and dial parts", vehicleId, #moving))
	end

	-- Seats and invisible empty parts go
	for _, d in body:GetChildren() do
		if d:IsA("BasePart") then
			if d:IsA("Seat") or d:IsA("VehicleSeat") or (not isVisible(d) and not hasDecoration(d)) then
				d:Destroy()
			else
				d.Anchored = true
				d.CanCollide = false
				d.CanTouch = false
				d.CanQuery = false
				d.Massless = true
			end
		end
	end
	for _, d in body:GetChildren() do
		if not d:IsA("BasePart") then
			d:Destroy()
		end
	end
	body.PrimaryPart = nil
	body.WorldPivot = CFrame.new()

	local width, height, length = size.X, size.Y, size.Z
	body:SetAttribute("BodySize", Vector3.new(width, height, length))

	local fix = FIXES[sourceId]
	if fix then
		fix(body)
	end

	-- Lights that aren't lamps: A-Chassis "backfire" flash lights hidden by the exhaust (they'd flash as
	-- indicators), and interior lights
	for _, part in body:GetChildren() do
		if part:IsA("BasePart") then
			local name = part.Name:lower()
			if name:sub(1, 7) == "bflight" or name:find("backfire") then
				part:Destroy()
			elseif name:find("interior") then
				for _, l in part:GetChildren() do
					if l:IsA("Light") then
						l:Destroy()
					end
				end
			end
		end
	end

	-- Lamps: tag by colour and position, then switch off
	local lamps = 0
	for _, part in body:GetChildren() do
		if part:IsA("BasePart") then
			local light = part:FindFirstChildWhichIsA("Light")
			local colour = if light then light.Color elseif part.Material == Enum.Material.Neon then part.Color else nil
			local kind = colour and classify(colour)
			if colour and classify(part.Color) == "Amber" then
				kind = "Amber" -- an amber lens is an indicator, whatever colour its light was given
			end
			if kind then
				local p = part.Position
				local front = p.Z < 0
				local left = p.X < 0
				local role = nil
				if kind == "Blue" then
					role = if left then "BlueA" else "BlueB"
				elseif kind == "Amber" then
					role = if left then "IndicatorL" else "IndicatorR"
				elseif kind == "Red" then
					role = if front then (if left then "BlueA" else "BlueB") else "Tail"
				elseif kind == "White" then
					role = if front then "Head" else nil
				end
				if role then
					lamps += 1
					part:SetAttribute("LightRole", role)
					part:SetAttribute("OnColor", if part.Material == Enum.Material.Neon then part.Color else colour)
					part:SetAttribute("OnTransparency", if part.Transparency >= 0.9 then 0.15 else part.Transparency)
					part:SetAttribute("OffTransparency", part.Transparency)
					part:SetAttribute("OffMaterial", if part.Material == Enum.Material.Neon then "SmoothPlastic" else part.Material.Name)
					part:SetAttribute("OffColor", part.Color)
					for _, l in part:GetChildren() do
						if l:IsA("Light") then
							l.Enabled = false
						end
					end
					if part.Material == Enum.Material.Neon then
						part.Material = Enum.Material.SmoothPlastic
					end
				end
			end
		end
	end

	-- Hand-placed lamps replace whatever was found by colour
	local placed = LAMPS[sourceId]
	if placed then
		lamps = 0
		for _, part in body:GetChildren() do
			if part:IsA("BasePart") and part:GetAttribute("LightRole") then
				for _, key in { "LightRole", "OnColor", "OnTransparency", "OffTransparency", "OffMaterial", "OffColor" } do
					part:SetAttribute(key, nil)
				end
				for _, l in part:GetChildren() do
					if l:IsA("Light") then
						l:Destroy()
					end
				end
			end
		end
		for _, lamp in placed do
			for _, side in { 1, -1 } do
				local at = lamp.at * Vector3.new(side, 1, 1)
				local normal = (lamp.normal * Vector3.new(side, 1, 1)).Unit
				local part = Instance.new("Part")
				part.Name = lamp.role .. "Lamp"
				part.Size = Vector3.new(lamp.size.X, lamp.size.Y, 0.03)
				part.CFrame = CFrame.lookAt(at + normal * 0.03, at + normal * 1.03)
				part.Material = Enum.Material.SmoothPlastic
				part.Color = LAMP_COLOURS[lamp.role]
				part.Transparency = 1
				part.CastShadow = false
				part.Anchored = true
				part.CanCollide = false
				part.CanTouch = false
				part.CanQuery = false
				part.Massless = true
				local role = if lamp.role == "Indicator" then (if side < 0 then "IndicatorL" else "IndicatorR") else lamp.role
				part:SetAttribute("LightRole", role)
				part:SetAttribute("OnColor", LAMP_COLOURS[lamp.role])
				part:SetAttribute("OnTransparency", if lamp.role == "Head" then 0.25 else 0.15)
				part:SetAttribute("OffTransparency", 1)
				part:SetAttribute("OffMaterial", "SmoothPlastic")
				part:SetAttribute("OffColor", LAMP_COLOURS[lamp.role])
				if lamp.role == "Head" and lamp.beam ~= false then
					local beam = Instance.new("SpotLight")
					beam.Face = Enum.NormalId.Front
					beam.Range = 45
					beam.Angle = 70
					beam.Brightness = 4
					beam.Color = Color3.fromRGB(255, 248, 230)
					beam.Enabled = false
					beam.Parent = part
				elseif lamp.role ~= "Head" then
					local glow = Instance.new("PointLight")
					glow.Range = 3
					glow.Brightness = 1
					glow.Color = LAMP_COLOURS[lamp.role]
					glow.Enabled = false
					glow.Parent = part
				end
				part.Parent = body
				lamps += 1
			end
		end
	end

	-- Every light: no shadows (a light's shadows update slower than a car moves, so the beam seems to lag
	-- behind), and indicator glows kept small so they don't light up the whole side of the car
	for _, part in body:GetChildren() do
		if part:IsA("BasePart") then
			local role = part:GetAttribute("LightRole")
			for _, l in part:GetChildren() do
				if l:IsA("Light") then
					l.Shadows = false
					if role == "IndicatorL" or role == "IndicatorR" then
						l.Range = math.min(l.Range, 3)
						l.Brightness = math.min(l.Brightness, 1)
						if not l:IsA("PointLight") then
							l:Destroy()
						end
					end
				end
			end
		end
	end

	-- Wheels: in each corner, the biggest round part that touches the ground is the tyre
	local function quadrant(p: Vector3): string
		return (if p.Z < 0 then "F" else "R") .. (if p.X < 0 then "L" else "R")
	end
	local tyres: { [string]: BasePart } = {}
	for _, part in body:GetChildren() do
		if part:IsA("BasePart") and not part:GetAttribute("LightRole") and isVisible(part) then
			local small, mid, big = sortedDims(part.Size)
			local round = mid >= big * 0.92 and small <= big * 0.9
			local onGround = math.abs(part.Position.Y - big / 2) < 0.45
			local atSide = math.abs(part.Position.X) > width * 0.2 and math.abs(part.Position.Z) > length * 0.15
			if round and onGround and atSide and big >= 1.4 and big <= height * 0.6 then
				local q = quadrant(part.Position)
				local current = tyres[q]
				local currentBig = if current then select(3, sortedDims(current.Size)) else 0
				-- A part actually named as a tyre always wins: a curved body panel near a wheel can look just as round
				local named = part.Name:lower():find("tire") or part.Name:lower():find("tyre")
				local currentNamed = current and (current.Name:lower():find("tire") or current.Name:lower():find("tyre"))
				if (named and not currentNamed) or ((not currentNamed or named) and big > currentBig) then
					tyres[q] = part
				end
			end
		end
	end
	local found = 0
	local radius = 0
	local centres = {}
	for q, tyre in tyres do
		found += 1
		local _, _, big = sortedDims(tyre.Size)
		centres[q] = tyre.Position
		radius = math.max(radius, big / 2)
	end
	local wheelParts = 0
	if found == 4 then
		for q, hub in centres do
			body:SetAttribute("Wheel" .. q, hub)
		end
		body:SetAttribute("WheelRadius", radius)
		for _, part in body:GetChildren() do
			-- Suspension pieces sit inside the wheel too, but mustn't spin with it (they'd whirl round the axle)
			local lower = part.Name:lower()
			local suspension = false
			for _, word in NOT_WHEEL do
				if lower:find(word) then
					suspension = true
				end
			end
			if part:IsA("BasePart") and not part:GetAttribute("LightRole") and not suspension then
				local q = quadrant(part.Position)
				local hub = centres[q]
				local _, _, big = sortedDims(part.Size)
				if (part.Position - hub).Magnitude <= radius * 1.1 and big <= radius * 2.4 and part.Position.Y <= hub.Y + radius then
					part:SetAttribute("Wheel", q)
					wheelParts += 1
				end
			end
		end
	end

	-- Paint: the colour covering the most body panel area
	local area: { [string]: number } = {}
	local colours: { [string]: Color3 } = {}
	for _, part in body:GetChildren() do
		if part:IsA("BasePart") and not part:GetAttribute("Wheel") and not part:GetAttribute("LightRole")
			and part.Transparency < 0.3 and part.Material ~= Enum.Material.Glass then
			local c = part.Color
			local lum = c.R * 0.3 + c.G * 0.59 + c.B * 0.11
			if lum > 0.08 then
				local key = string.format("%d,%d,%d", c.R * 255, c.G * 255, c.B * 255)
				local _, mid, big = sortedDims(part.Size)
				area[key] = (area[key] or 0) + mid * big
				colours[key] = c
			end
		end
	end
	local best, bestArea = nil, 0
	for key, a in area do
		if a > bestArea then
			best, bestArea = key, a
		end
	end
	local painted = 0
	local pick = PAINT_PICK[sourceId]
	if pick then
		for _, part in body:GetChildren() do
			if part:IsA("BasePart") and not part:GetAttribute("Wheel") and not part:GetAttribute("LightRole") and pick(part, groupOf[part] or "") then
				part:SetAttribute("Paint", true)
				painted += 1
			end
		end
	elseif best then
		for _, part in body:GetChildren() do
			if part:IsA("BasePart") and not part:GetAttribute("Wheel") and not part:GetAttribute("LightRole") then
				local c = part.Color
				if string.format("%d,%d,%d", c.R * 255, c.G * 255, c.B * 255) == best then
					part:SetAttribute("Paint", true)
					painted += 1
				end
			end
		end
	end

	-- Discs in the body colour over badges moulded into the trim
	local paintPart: BasePart? = nil
	for _, part in body:GetChildren() do
		if part:IsA("BasePart") and part:GetAttribute("Paint") then
			paintPart = part
			break
		end
	end
	for _, cover in BADGE_COVERS[sourceId] or {} do
		local n = cover.normal.Unit
		local disc = Instance.new("Part")
		disc.Name = "BadgeCover"
		disc.Shape = Enum.PartType.Cylinder
		disc.Size = Vector3.new(0.12, cover.size, cover.size)
		disc.CFrame = CFrame.fromMatrix(cover.at, n, n:Cross(Vector3.xAxis).Unit)
		disc.Color = if paintPart then paintPart.Color else Color3.fromRGB(60, 90, 140)
		disc.Material = if paintPart then paintPart.Material else Enum.Material.SmoothPlastic
		disc.Anchored = true
		disc.CanCollide = false
		disc.CanTouch = false
		disc.CanQuery = false
		disc.Massless = true
		disc:SetAttribute("Paint", true)
		disc.Parent = body
	end

	-- Words printed on the body, so we can spot real force and brand names
	local words = {}
	for _, d in body:GetDescendants() do
		if (d:IsA("TextLabel") or d:IsA("TextButton")) and d.Text ~= "" then
			words[d.Text] = true
		end
	end
	local list = {}
	for w in words do
		table.insert(list, w)
	end

	local parts = 0
	for _, d in body:GetChildren() do
		if d:IsA("BasePart") then
			parts += 1
		end
	end
	print(string.format("[Bodies] %-26s %3d parts  size %.1f x %.1f x %.1f  driver %s  seats %d  wheels %d (%d parts, r %.2f)  lamps %d  paint %d  words: %s",
		vehicleId, parts, width, height, length, tostring(driver ~= nil), count, found, wheelParts, radius, lamps, painted, table.concat(list, " | ")))
	return body
end

local import = ServerStorage:FindFirstChild("SwatImport")
assert(import, "Put the Swat Motors models in ServerStorage → SwatImport first")
local out = ServerStorage:FindFirstChild("VehicleBodies") or Instance.new("Folder")
out.Name = "VehicleBodies"
out:ClearAllChildren() -- start fresh each run
for _, source in import:GetChildren() do
	local id = MAP[source:GetAttribute("SourceAssetId")]
	if id and source:IsA("Model") then
		local old = out:FindFirstChild(id)
		if old then
			old:Destroy()
		end
		local ok, result = pcall(prepare, source, id)
		if ok then
			result.Parent = out
		else
			warn("[Bodies] " .. id .. " failed: " .. tostring(result))
		end
	end
end
out.Parent = ServerStorage
print("[Bodies] done: " .. #out:GetChildren() .. " bodies in ServerStorage.VehicleBodies")
