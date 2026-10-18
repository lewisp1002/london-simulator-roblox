--!nocheck
-- Turns free A-Chassis 6 car models into London Simulator cars that drive with real physics: springs, tyres,
-- torque through the gearbox, traction control (the same kit the realistic Roblox car games use).
--
-- How to use it, in Roblox Studio:
--   1. Put the models in ServerStorage → SwatImport (each one keeps a "SourceAssetId" attribute).
--   2. Paste this whole file into the Command Bar and press Enter.
--   3. The finished cars appear in ServerStorage → ChassisCars, one per vehicle id in Shared → Vehicles.
--      Cars spawns these instead of building a body (see Cars.luau), so the car keeps its own driving,
--      engine sounds and lights.
--
-- What it does to each model:
--   - checks every script against a list of backdoor tricks and stops if any turn up
--   - deletes scripts we don't want: Slipstream (clones parts into the workspace forever), and AntiCollide /
--     AntiCollideCar (their own collision groups, which fight our spawn ghosting)
--   - deletes real makers' badges and logos, and covers ones moulded into the body with a disc in the body colour
--   - tags the painted panels "Paint" so the server can paint the car the player picked
--   - makes it right-hand drive like a UK car: the seats swap sides, the steering wheel and dials move across
--   - moves A-Chassis' and EpicLights' keys onto ours (L lights, Q / E indicators, B hazards, Space handbrake;
--     gears move to Z / X), so nothing clashes with our controls
--   - pivots it at the middle of its footprint on the ground, facing the way it drives
-- The free model files never go in the git repo: they live only in the place file.

local ServerStorage = game:GetService("ServerStorage")

local function paint140(part: BasePart): boolean
	local c = part.Color
	if math.floor(c.R * 255 + 0.5) ~= 17 or part.Material ~= Enum.Material.SmoothPlastic then
		return false
	end
	local group = if part.Parent then part.Parent.Name else ""
	if group ~= "Body" and group ~= "Model" and group ~= "m140i" then
		return false -- the interior, engine bay, lights and wheels have their own groups
	end
	local name = part.Name:lower()
	for _, word in { "glass", "window", "windscreen", "light", "lamp", "int", "bottom", "trim", "chrome", "grill", "black" } do
		if name:find(word) then
			return false
		end
	end
	if name == "bumperfront02" then
		return false -- the honeycomb in the bumper's air intakes, black on the real car
	end
	return math.max(part.Size.X, part.Size.Y, part.Size.Z) > 3.5
end

local SETUP = {
	-- "M140i" by IoudM5: a 2017 F20 facelift M140i with an M Performance splitter, a full interior and engine
	-- bay, on A-Chassis 6 (223 hp, rear-wheel drive, DCT automatic, traction control and ABS) with a B58 engine
	-- sound pack. Checked 18 Oct 2026: 70 scripts, all A-Chassis and its plugins, no backdoors.
	[15521430429] = {
		id = "brenner_140",
		paint = paint140,
		-- Parts (or the models they're in) with these words in their name are deleted
		remove = { "bmw logo", "badge", "cage", "bootparts03" }, -- bootparts03 is the model badge on the boot
		-- Discs over badges moulded into the body. Positions are on our 16.2-stud body from
		-- prepare_vehicle_bodies (front facing -Z), scaled to this model's own size.
		covers = { { at = Vector3.new(0, 2.56, -7.66), normal = Vector3.new(0, 0.83, -0.55), size = 0.42, length = 16.2 } },
		rightHandDrive = { "steer", "cluster", "gauge", "paddle", "stalk" },
		tune = {
			-- Traction control steps in later and cuts less, so the back can step out on the throttle
			TCSThreshold = "32", TCSLimit = "30",
			-- A little stiffer and a touch higher, and a bit less steering lock, so the tyres stop rubbing the arches
			FSusStiffness = "26000", RSusStiffness = "26000", FPreCompress = ".3", RPreCompress = ".3",
			SteerInner = "40", SteerOuter = "34",
			-- A bigger dead zone on the controller sticks, so a stick that doesn't sit dead centre doesn't steer
			ControlLDZone = "15", ControlRDZone = "15",
		},
		fix = function(car: Model)
			for _, part in car:GetDescendants() do
				if part:IsA("BasePart") then
					local name = part.Name:lower()
					local c = part.Color
					if name == "boot02" then
						part:SetAttribute("PaintedBadge", true) -- the roundel on the boot: painted over, like a badge delete
					elseif name == "spacewall" then
						for _, texture in part:GetChildren() do
							if texture:IsA("Texture") or texture:IsA("Decal") then
								texture:Destroy() -- a starry space picture that showed through the grille
							end
						end
						part.Color = Color3.fromRGB(15, 15, 15)
					elseif c.R > 0.55 and c.B > 0.55 and c.G < 0.45 then
						part.Color = Color3.fromRGB(45, 45, 48) -- suspension arms whose texture doesn't load show pink
					end
				end
			end
		end,
	},

	-- "2022 Audi A6 Unmarked" from Lewis's bought "2022 Audi A6 Pack" (a .rbxm file, loaded from disk, so it's keyed by
	-- its name). Classic A-Chassis 6 (Inspare build): 335 hp, four-wheel drive, 6-speed auto, soft realistic
	-- suspension and camber. Already right-hand drive. Checked 18 Oct 2026: 127 scripts, all A-Chassis, EasyLS
	-- emergency lights and a siren panel, no backdoors. The civilian version loses all the police kit.
	["2022 Audi A6 Unmarked"] = {
		id = "aurel_sovereign",
		paint = function(part: BasePart): boolean
			return part.Parent ~= nil and part.Parent.Name == "Skin"
		end,
		tune = {
			ControlLDZone = "15", ControlRDZone = "15",
			-- Rear-wheel drive with traction control off to start with (T turns it on), so the back steps out on the
			-- throttle and it drifts like the hot hatch in Lewis's reference game
			Config = '"RWD"',
			-- Traction control on but gentle: it only trims wheelspin, so a slide doesn't snap with the throttle
			TCSEnabled = "true", TCSThreshold = "50", TCSGradient = "30", TCSLimit = "70",
			-- Steering weighted like Birmingham Vehicle Simulator's, measured there 18 Oct 2026 (a half-second full-right tap at
			-- 40 mph turns the car about 18 degrees by release and about 65 in all). A-Chassis turns the wheel at
			-- SteerSpeed away from centre and ReturnSpeed back towards it, per step at 60 a second: a third of a second
			-- to full lock, and a fast return so swapping from left to right doesn't lag (it took half a second before)
			SteerSpeed = ".05", ReturnSpeed = ".09",
			-- A lower centre of gravity: steadier, less wobble
			CGHeight = ".6",
			-- Lock, and how much of it is left at speed, matched to that same test
			SteerInner = "35", SteerOuter = "34", SteerDecay = "400", MinSteer = "20",
		},
		-- Our own engine sound (several real recordings blended by revs, see EngineSounds) instead of its single
		-- sped-up loop, and pops and a brap on the upshifts
		engine = "b58",
		pops = true,
		deletePlugins = { "AC6_Stock_Sound" },
		-- Rear tyres a little less grippy than the fronts, so it slides at the back, not the front
		rearFriction = 0.63,
		-- Scripts read by hand and passed, by name and most characters: the plate generators use string.char to
		-- pick random letters
		reviewed = { LicensePlateGenerator = 500 },
		fix = function(car: Model)
			local seat = car:FindFirstChild("DriveSeat")
			for _, name in { "Pickup", "SirenControl" } do
				local thing = seat and seat:FindFirstChild(name)
				if thing then
					thing:Destroy() -- the siren panel, and a script that renamed the car "<player>'s Car"
				end
			end
			local plugins = car["A-Chassis Tune"]:FindFirstChild("Plugins")
			local els = plugins and plugins:FindFirstChild("EasyLS_Client")
			if els then
				els:Destroy() -- emergency lights
			end
			local body = car:FindFirstChild("Body")
			local kit = body and body:FindFirstChild("ELS_Related")
			if kit then
				-- Hidden blue lights, the siren speaker and the mirror strobes go; the number plates stay
				local plate = kit:FindFirstChild("Plate", true)
				if plate then
					plate.Parent = body
				end
				kit:Destroy()
			end
		end,
	},
}

-- Scripts we never keep
local DELETE_SCRIPTS = { Slipstream = true, AntiCollide = true, AntiCollideCar = true }

-- A-Chassis plugins we don't keep: the ones that put dials and readouts on the screen (rev counter, speedo,
-- horsepower readout, brake temperature, the Controls button: we have our own dashboard), and Creep, which pushes
-- the car along at walking pace whenever you're off the accelerator (it felt like the car drove itself).
-- PacejkaTires goes too: putting its tyre script back made the car turn in circles by itself.
local DELETE_PLUGINS = {
	AC6C_Stock_Gauges = true, AC6_Controls_Module = true, HP_TQ_PTW_Reader = true, BRAKETEMP = true,
	TZBrakeTEMP = true, AC6_Creep = true, PacejkaTires = true, AC6_Stock_Gauges = true, Ignition = true,
}

-- Tune settings changed from the model's own, per car (see SETUP)
local function setTune(source: string, key: string, value: string): (string, number)
	-- A number, a word in quotes, or true / false
	return source:gsub("(%f[%w_]" .. key .. "%s*=%s*)[^%s,]+", "%1" .. value)
end

-- Things a backdoor does. Any of these in a script stops the whole car from being made.
local SUSPICIOUS = {
	"require%s*%(%s*%d", "require%s*%(%s*tonumber", "getfenv", "setfenv", "loadstring", "string%.char",
	"\\x%x%x", "HttpService", "TeleportService", "MarketplaceService", "InsertService", "MessagingService",
	"DataStoreService", ":Kick", "GetObjects", "LoadAsset", "string%.reverse",
}

-- Keys A-Chassis and EpicLights use that clash with ours, moved elsewhere
local TUNE_KEYS = {
	ShiftUp = "X", ShiftDown = "Z", MouseShiftUp = "X", MouseShiftDown = "Z",
	ToggleMouseDrive = "F8", PBrake = "Space",
	ContlrShiftUp = "ButtonR1", ContlrShiftDown = "ButtonL1", ContlrClutch = "ButtonR3", ContlrPBrake = "ButtonA",
	ContlrToggleTMode = "F10", ContlrToggleTCS = "F11", ContlrToggleABS = "F12",
}
local LIGHT_KEYS = { Headlights = "L", SignalLeft = "Q", SignalRight = "E", Hazards = "B", Popups = "F7", HighBeamFlash = "K" }

local function setKeys(script: LuaSourceContainer, keys: { [string]: string }, prefix: string): number
	local source = script.Source
	local changed = 0
	for name, key in keys do
		local count
		source, count = source:gsub("(%f[%w_.]" .. prefix .. name .. "%s*=%s*)Enum%.KeyCode%.%w+", "%1Enum.KeyCode." .. key)
		changed += count
	end
	script.Source = source
	return changed
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

-- After moving parts, every joint touching one of them is set to hold the parts where they are now (two moved
-- parts joined together, like the two seats, have changed places relative to each other too)
local function rejoin(car: Model, moved: { [BasePart]: boolean })
	for _, joint in car:GetDescendants() do
		if joint:IsA("JointInstance") and joint.Part0 and joint.Part1 then
			if moved[joint.Part0] or moved[joint.Part1] then
				joint.C0 = joint.Part0.CFrame:Inverse() * joint.Part1.CFrame * joint.C1
			end
		elseif joint:IsA("WeldConstraint") and joint.Part0 and joint.Part1 then
			if moved[joint.Part0] or moved[joint.Part1] then
				local other = joint.Part1
				joint.Part1 = nil
				joint.Part1 = other
			end
		end
	end
end

local function prepare(source: Model, setup): Model
	local car = source:Clone()
	car.Name = setup.id
	local report = {}

	-- Scripts: check, then delete the ones we don't keep
	for _, d in car:GetDescendants() do
		local reviewedSize = setup.reviewed and setup.reviewed[d.Name]
		if d:IsA("LuaSourceContainer") and not (reviewedSize and #d.Source <= reviewedSize) then
			for _, pattern in SUSPICIOUS do
				if d.Source:find(pattern) then
					error(`suspicious script {d:GetFullName()} ({pattern}): check it by hand`)
				end
			end
		end
	end
	for _, d in car:GetChildren() do
		if d:IsA("Script") and DELETE_SCRIPTS[d.Name] then
			d:Destroy()
		end
	end
	local plugins = car:FindFirstChild("A-Chassis Tune") and car["A-Chassis Tune"]:FindFirstChild("Plugins")
	for _, d in if plugins then plugins:GetChildren() else {} do
		if DELETE_PLUGINS[d.Name] then
			d:Destroy()
		end
	end
	for _, name in setup.deletePlugins or {} do
		local plugin = plugins and plugins:FindFirstChild(name)
		if plugin then
			plugin:Destroy()
		end
	end
	local mobileSetup = plugins and plugins:FindFirstChild("Mobile_setup", true)
	if mobileSetup then
		mobileSetup:Destroy() -- it moves the stock gauges about on phones, and they're gone
	end

	local seat = car:FindFirstChild("DriveSeat") :: VehicleSeat
	assert(seat, "no DriveSeat: not an A-Chassis car?")
	local scale = setup.covers and setup.covers[1] and visibleLength(car) / setup.covers[1].length or 1

	-- Badges and logos
	local removed = 0
	for _, d in car:GetDescendants() do
		if d.Parent and (d:IsA("BasePart") or d:IsA("Model") or d:IsA("Decal")) then
			local name = d.Name:lower()
			for _, word in setup.remove or {} do
				if name:find(word) then
					d:Destroy()
					removed += 1
					break
				end
			end
		end
	end
	table.insert(report, `{removed} badges/logos removed`)

	if setup.fix then
		setup.fix(car)
	end

	-- The car's frame: facing the way the driver's seat faces, at the middle of its footprint on the ground
	local forward = (seat.CFrame.LookVector * Vector3.new(1, 0, 1)).Unit
	local rotation = CFrame.lookAt(Vector3.zero, forward)
	local minV, maxV = Vector3.one * math.huge, -Vector3.one * math.huge
	for _, d in car:GetDescendants() do
		if d:IsA("BasePart") and d.Transparency < 0.95 and not d:IsA("Seat") and not d:IsA("VehicleSeat") then
			local half = d.Size / 2
			for _, sx in { -1, 1 } do
				for _, sy in { -1, 1 } do
					for _, sz in { -1, 1 } do
						local p = rotation:PointToObjectSpace(d.CFrame:PointToWorldSpace(Vector3.new(sx * half.X, sy * half.Y, sz * half.Z)))
						minV = minV:Min(p)
						maxV = maxV:Max(p)
					end
				end
			end
		end
	end
	local frame = CFrame.new(rotation:PointToWorldSpace(Vector3.new((minV.X + maxV.X) / 2, minV.Y, (minV.Z + maxV.Z) / 2))) * rotation.Rotation
	local size = maxV - minV
	table.insert(report, string.format("size %.1f x %.1f x %.1f", size.X, size.Y, size.Z))

	-- Paint, glossy like a real car's clear coat (it reflects the sky)
	local painted = 0
	for _, d in car:GetDescendants() do
		if d:IsA("BasePart") and (setup.paint(d) or d:GetAttribute("PaintedBadge")) then
			d:SetAttribute("Paint", true)
			d:SetAttribute("BaseColour", d.Color)
			d.Material = Enum.Material.SmoothPlastic
			d.Reflectance = 0.12
			painted += 1
		end
	end
	table.insert(report, `{painted} painted panels`)

	-- Discs over moulded badges, inside the body so A-Chassis welds them on
	local body = car:FindFirstChild("Body")
	for _, cover in setup.covers or {} do
		local n = frame:VectorToWorldSpace(cover.normal.Unit)
		local at = frame:PointToWorldSpace(cover.at * scale)
		local disc = Instance.new("Part")
		disc.Name = "BadgeCover"
		disc.Shape = Enum.PartType.Cylinder
		disc.Size = Vector3.new(0.12, cover.size * scale, cover.size * scale)
		disc.CFrame = CFrame.fromMatrix(at, n, n:Cross(frame.RightVector).Unit)
		disc.Color = Color3.fromRGB(17, 17, 17)
		disc.Material = Enum.Material.SmoothPlastic
		disc.Anchored = true
		disc.CanCollide = false
		disc.CanTouch = false
		disc.CanQuery = false
		disc.Massless = true
		disc:SetAttribute("Paint", true)
		disc.Parent = body or car
	end

	-- Right-hand drive: the seats swap sides, and the steering wheel and dials move across as one piece
	if setup.rightHandDrive then
		local right = frame.RightVector
		local function mirrorShift(position: Vector3): Vector3
			return -2 * (position - frame.Position):Dot(right) * right
		end
		local moved: { [BasePart]: boolean } = {}
		local passenger: BasePart? = nil
		for _, d in car:GetDescendants() do
			if d:IsA("Seat") and (not passenger or (d.Position - seat.Position).Magnitude < (passenger.Position - seat.Position).Magnitude) then
				passenger = d
			end
		end
		for _, s in { seat, passenger } do
			if s then
				s.CFrame += mirrorShift(s.Position)
				moved[s] = true
			end
		end
		local wheelParts, sum = {}, Vector3.zero
		for _, d in car:GetDescendants() do
			local path = d:GetFullName():lower()
			-- (the engine bay has a power steering pump, which stays where it is)
			if d:IsA("BasePart") and not moved[d] and not path:find("b58") and not path:find("engine") then
				for _, word in setup.rightHandDrive do
					if path:find(word) then
						table.insert(wheelParts, d)
						sum += d.Position
						break
					end
				end
			end
		end
		if #wheelParts > 0 then
			local shift = mirrorShift(sum / #wheelParts)
			for _, d in wheelParts do
				d.CFrame += shift
				moved[d] = true
			end
		end
		rejoin(car, moved)
		table.insert(report, `right-hand drive ({#wheelParts} steering/dial parts moved)`)
	end

	-- Passenger seats aren't welded on by A-Chassis (one slid off behind the car), so weld them to the
	-- driver's seat where they are
	local welded = 0
	for _, d in car:GetDescendants() do
		if d:IsA("Seat") then
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = seat
			weld.Part1 = d
			weld.Parent = d
			welded += 1
		end
	end
	table.insert(report, `{welded} passenger seats welded`)

	-- Testing in Studio: the Command Bar can press A-Chassis' pedals and steering through the player's
	-- TestThrottle (-1 to 1), TestSteer (-1 to 1) and TestHandbrake attributes, like our own Driving script
	local drive = car:FindFirstChild("Drive", true)
	if drive and drive:IsA("LocalScript") then
		-- Also: let go of every pedal when the game window loses focus, or a button held as it lost focus stays
		-- held for good (the car then drives itself)
		-- The newer A-Chassis (AC6C) reads the pedals into _InThrot / _InBrake and runs on Heartbeat; the classic one
		-- reads them straight into _GThrot / _GBrake (idle is the tune's IdleThrottle) and runs in a while loop
		local modern = drive.Source:find('game%["Run Service"%]%.Heartbeat:connect%(function%(dt%)') ~= nil
		local gas = if modern then "_InThrot" else "_GThrot"
		local brake = if modern then "_InBrake" else "_GBrake"
		local idle = if modern then "0" else "(_Tune.IdleThrottle/100)"
		local body = ([[
	-- A controller trigger that has never been seen let go is ignored (a faulty or badly mapped controller
	-- can report a trigger as held all the time, and the car then drives off by itself in circles)
	local uis = game:GetService("UserInputService")
	for _, pad in uis:GetConnectedGamepads() do
		for _, state in uis:GetGamepadState(pad) do
			local isGas, isBrake = state.KeyCode == Enum.KeyCode.ButtonR2, state.KeyCode == Enum.KeyCode.ButtonL2
			if isGas or isBrake then
				local key = tostring(pad) .. state.KeyCode.Name
				if state.Position.Z < 0.1 then
					padTrusted[key] = true
				elseif not padTrusted[key] then
					if isGas and not (uis:IsKeyDown(Enum.KeyCode.W) or uis:IsKeyDown(Enum.KeyCode.Up)) then GAS = IDLE end
					if isBrake and not (uis:IsKeyDown(Enum.KeyCode.S) or uis:IsKeyDown(Enum.KeyCode.Down)) then BRAKE = 0 end
				end
			end
		end
	end
	-- Pressing the accelerator lets the handbrake off (A-Chassis otherwise leaves it on as a parking brake
	-- after a tap at a standstill, and the car won't move), unless the handbrake button is held
	if _PBrake and GAS > IDLE + 0.2 then
		local held = uis:IsKeyDown(Enum.KeyCode.Space)
		for _, pad in uis:GetConnectedGamepads() do
			held = held or uis:IsGamepadButtonDown(pad, Enum.KeyCode.ButtonA)
		end
		if not held then _PBrake = false end
	end
	if game:GetService("RunService"):IsStudio() then
		local testPlayer = game:GetService("Players").LocalPlayer
		local testThrottle = testPlayer:GetAttribute("TestThrottle")
		if typeof(testThrottle) == "number" then GAS = math.max(testThrottle, IDLE) BRAKE = math.max(-testThrottle, 0) end
		local testSteer = testPlayer:GetAttribute("TestSteer")
		if typeof(testSteer) == "number" then _GSteerT = testSteer end
		local testHandbrake = testPlayer:GetAttribute("TestHandbrake")
		if testHandbrake ~= nil then _PBrake = testHandbrake == true end
	end]]):gsub("GAS", gas):gsub("BRAKE", brake):gsub("IDLE", idle)
		local prefix = ([[game:GetService("UserInputService").WindowFocusReleased:Connect(function()
	GAS = IDLE BRAKE = 0 _GSteerT = 0
end)
local padTrusted = {}
]]):gsub("GAS", gas):gsub("BRAKE", brake):gsub("IDLE", idle)
		local anchor = if modern then 'game%["Run Service"%]%.Heartbeat:connect%(function%(dt%)' else "while wait%(%) do"
		-- The classic one's loop runs on wait(), only 30 times a second, which makes the steering and revs steppy:
		-- it runs every frame instead, and its per-step rates are halved to match (see halveRates)
		local opening = if modern then 'game["Run Service"].Heartbeat:connect(function(dt)' else "while task.wait() do"
		local source, count = drive.Source:gsub(anchor, function()
			return prefix .. opening .. "\n" .. body
		end, 1)
		drive.Source = source
		table.insert(report, if count == 1 then "test hook added" else "TEST HOOK NOT ADDED")
		if not modern then
			setup.halveRates = true
		end
	end

	-- Keys
	local tune = car:FindFirstChild("A-Chassis Tune")
	local keysChanged = if tune then setKeys(tune, TUNE_KEYS, "") else 0
	if tune then
		-- Automatic only, the way that works like Birmingham Vehicle Simulator: it pulls away in Drive when you
		-- press accelerate and goes into Reverse when you hold the brake at a standstill (A-Chassis' "Old" auto)
		local source = tune.Source
		source = source:gsub("(Tune%.TransModes%s*=%s*)%b{}", '%1{"Auto"}')
		source = source:gsub('(Tune%.AutoShiftVers%s*=%s*)"%a+"', '%1"Old"')
		local tuned = 0
		if setup.halveRates then
			-- Per-step amounts, halved because the loop now runs twice as often
			for _, key in { "SteerSpeed", "ReturnSpeed", "RevAccel", "RevDecay" } do
				source = source:gsub("(%f[%w_]Tune%." .. key .. "%s*=%s*)([%d%.]+)", function(head, number)
					return head .. tostring(tonumber(number) / 2)
				end)
			end
		end
		for key, value in setup.tune or {} do
			local count
			source, count = setTune(source, key, value)
			tuned += count
		end
		table.insert(report, `{tuned} tune settings changed`)
		tune.Source = source
	end
	local lightsConfig = car:FindFirstChild("Configuration", true)
	local lightKeys = if lightsConfig and lightsConfig:IsA("ModuleScript") then setKeys(lightsConfig, LIGHT_KEYS, "config%.") else 0
	table.insert(report, `{keysChanged} A-Chassis keys and {lightKeys} light keys moved`)

	-- Pivot and tags
	car.PrimaryPart = seat
	seat.PivotOffset = seat.CFrame:ToObjectSpace(frame) -- with a PrimaryPart the pivot lives on it, not the model
	car:SetAttribute("ChassisCar", true)
	if setup.engine then
		car:SetAttribute("EngineSound", setup.engine) -- VehicleEffects plays this instead of A-Chassis' own engine
		car:SetAttribute("Gears", 6)
	end
	if setup.pops then
		car:SetAttribute("Pops", true)
	end
	if setup.rearFriction then
		local wheels = car:FindFirstChild("Wheels")
		for _, name in { "RL", "RR" } do
			local wheel = wheels and wheels:FindFirstChild(name)
			if wheel and wheel:IsA("BasePart") then
				local current = wheel.CustomPhysicalProperties or PhysicalProperties.new(wheel.Material)
				wheel.CustomPhysicalProperties = PhysicalProperties.new(current.Density, setup.rearFriction, current.Elasticity, current.FrictionWeight, current.ElasticityWeight)
			end
		end
	end
	car:SetAttribute("VehicleId", setup.id)
	car:PivotTo(CFrame.new())
	for _, d in car:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true -- A-Chassis unanchors everything once it's welded the car together
		end
	end
	print("[ChassisCars] " .. setup.id .. ": " .. table.concat(report, ", "))
	return car
end

local import = ServerStorage:FindFirstChild("SwatImport")
assert(import, "Put the models in ServerStorage → SwatImport first")
local out = ServerStorage:FindFirstChild("ChassisCars") or Instance.new("Folder")
out.Name = "ChassisCars"
out.Parent = ServerStorage
for _, source in import:GetChildren() do
	local setup = SETUP[source:GetAttribute("SourceAssetId") or source:GetAttribute("SourceFile")]
	if setup and source:IsA("Model") then
		local old = out:FindFirstChild(setup.id)
		if old then
			old:Destroy()
		end
		local ok, result = pcall(prepare, source, setup)
		if ok then
			result.Parent = out
		else
			warn("[ChassisCars] " .. setup.id .. " failed: " .. tostring(result))
		end
	end
end
print("[ChassisCars] done: " .. #out:GetChildren() .. " cars in ServerStorage.ChassisCars")
