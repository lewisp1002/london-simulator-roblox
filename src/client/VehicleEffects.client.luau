-- Engine sounds and body movement for every vehicle near you, on your device only.
--   Sounds: the engine idles and revs with the rpm, the turbo whines and the blow-off valve hisses when it
--   changes up. Cars with an EngineSound profile (see EngineSounds) play real engine recordings blended by rpm
--   instead, start up when someone gets in, and fart and burble with recorded sounds. Cars with the Pops attribute "brap" on every flat-out upshift, and crackle and pop when you
--   lift off, with flames out of the exhaust. Tyres squeal when they slide or you brake hard, and the horn
--   sounds while the driver holds it (the server sets the Horn attribute, see Cars).
--   Body: stays level, like Birmingham Vehicle Simulator (no squat, dive or lean: it felt floaty).
-- Sounds made on a device are only heard on that device, so every player's device does this for every car.
-- For the car you're driving it reads what Driving says the engine is doing (Rpm, Gear, Drive, Throttle,
-- Upshifts, Downshifts, Slip); for everyone else's car it works it out from how the car is moving (see Gearbox.guess).

local ContentProvider = game:GetService("ContentProvider")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local EngineSounds = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("EngineSounds"))
local Gearbox = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Gearbox"))

local player = Players.LocalPlayer

local HEAR_WITHIN = 240 -- studs from the camera
local FORGET_BEYOND = 300
local MOST_ENGINES = 10 -- the nearest cars get sound, the rest are too far off to matter

local SOUNDS = {
	idle = "rbxassetid://7588250185",
	rev = "rbxassetid://7588254585",
	whine = "rbxassetid://404779487",
	skid = "rbxassetid://435752381",
	horn = "rbxassetid://9029412098",
	pop = "rbxassetid://810616601", -- a double bang in the first 0.15 seconds, then silence
	blowOff = "rbxassetid://4940167544",
}
local BANGS = 10 -- pop sounds kept ready on each car that pops, played in turn so they can overlap

-- A new sound takes about 0.3 seconds to load before it plays, which makes a pop late and a brap a mess.
-- So every car keeps its pop and blow-off sounds loaded and ready, and these get loaded once up front.
task.spawn(function()
	local loading = {}
	local ids = EngineSounds.allIds()
	for _, id in SOUNDS :: { [string]: string } do
		table.insert(ids, id)
	end
	for _, id in ids do
		local sound = Instance.new("Sound")
		sound.SoundId = id
		table.insert(loading, sound)
	end
	pcall(function()
		ContentProvider:PreloadAsync(loading)
	end)
end)

type Engine = {
	car: Model,
	chassis: BasePart,
	seat: VehicleSeat?,
	joint: Motor6D?,
	exhausts: { Attachment },
	box: Gearbox.Box,
	profile: EngineSounds.Profile?, -- real engine recordings, for cars that have them
	loops: { Sound }, -- the profile's recordings, playing while the engine runs
	farts: { Sound }, -- the profile's upshift braps, ready-loaded
	burble: Sound?,
	startup: Sound?,
	startedAt: number,
	smoke: { ParticleEmitter }, -- tyre smoke at the rear wheels
	idle: Sound?,
	rev: Sound?,
	whine: Sound?,
	skid: Sound?,
	horn: Sound?,
	bangs: { Sound }, -- ready-loaded pop sounds (cars that pop only)
	nextBang: number,
	bangPlays: { [Sound]: number }, -- counts plays, so a delayed stop doesn't cut off a newer pop
	blowOff: Sound?,
	-- what the engine is doing
	rpm: number,
	gear: number,
	upshifts: number,
	downshifts: number,
	lastPedal: number, -- how far the accelerator was down last frame
	crackleUntil: number,
	nextPop: number,
	blipUntil: number,
	brapUntil: number, -- engine sound cut while it braps
	lastUpshift: number,
	-- how the car is moving
	lastSpeed: number,
	accel: number,
	pitch: number,
	pitchSpeed: number,
	roll: number,
	rollSpeed: number,
}

local engines: { [Model]: Engine } = {}
local random = Random.new()

local function newSound(id: string, parent: Instance, looped: boolean, volume: number): Sound
	local sound = Instance.new("Sound")
	sound.SoundId = id
	sound.Looped = looped
	sound.Volume = volume
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMinDistance = 14
	sound.RollOffMaxDistance = HEAR_WITHIN
	sound.Parent = parent
	return sound
end

-- One bang from the exhaust, on the next ready pop sound. `cutAfter` stops it early (seconds).
local function bang(engine: Engine, volume: number, speed: number, cutAfter: number)
	local bangs = engine.bangs
	if #bangs == 0 then
		return
	end
	local sound = bangs[engine.nextBang]
	engine.nextBang = engine.nextBang % #bangs + 1
	sound:Stop()
	sound.Volume = volume
	sound.PlaybackSpeed = speed
	sound.TimePosition = 0
	sound:Play()
	local plays = (engine.bangPlays[sound] or 0) + 1
	engine.bangPlays[sound] = plays
	task.delay(cutAfter, function()
		if engine.bangPlays[sound] == plays then
			sound:Stop()
		end
	end)
end

-- A flame out of each exhaust and a flash of orange light, for a split second
local function flame(engine: Engine, big: boolean)
	for _, tip in engine.exhausts do
		local emitter = tip:FindFirstChild("Flame") :: ParticleEmitter?
		if emitter then
			emitter:Emit(if big then 9 else 5)
		end
		local light = tip:FindFirstChild("Glow") :: PointLight?
		if light then
			light.Brightness = if big then 6 else 3.5
			light.Enabled = true
			task.delay(0.07, function()
				light.Enabled = false
			end)
		end
	end
end

local function pop(engine: Engine, big: boolean)
	local volume = if big then random:NextNumber(1.3, 1.7) else random:NextNumber(0.75, 1.15)
	local speed = if big then random:NextNumber(0.8, 0.95) else random:NextNumber(0.95, 1.35)
	bang(engine, volume, speed, 0.35)
	flame(engine, big)
end

-- The "brap" a sporty straight-six makes on a flat-out gear change: the ignition cuts for a split second
-- and the exhaust fires off a quick, deep burst of bangs, with a flame
local BRAP_GAPS = { 0, 0.03, 0.058, 0.09, 0.118, 0.15 }
local function brap(engine: Engine)
	engine.brapUntil = os.clock() + 0.2
	local deep = random:NextNumber(0.68, 0.8)
	for i, gap in BRAP_GAPS do
		task.delay(gap, function()
			if engine.chassis.Parent then
				bang(engine, random:NextNumber(1.4, 1.8), deep + random:NextNumber(-0.04, 0.06), 0.2)
				if i % 2 == 1 then
					flame(engine, i == 1)
				end
			end
		end)
	end
end

-- The recorded brap, for cars with real engine sounds: a random one of the profile's, with flames
local function fart(engine: Engine)
	local farts = engine.farts
	engine.brapUntil = os.clock() + 0.18
	local sound = farts[random:NextInteger(1, #farts)]
	sound.PlaybackSpeed = random:NextNumber(0.92, 1.05)
	sound.TimePosition = 0
	sound:Play()
	for i, gap in { 0, 0.06, 0.12 } do
		task.delay(gap, function()
			if engine.chassis.Parent then
				flame(engine, i == 1)
			end
		end)
	end
end

-- Tyre smoke at each rear wheel, by the road, made thicker the harder the tyres slide or spin
local function addSmoke(chassis: BasePart): { ParticleEmitter }
	local emitters = {}
	for _, joint in chassis:GetChildren() do
		local hub = if joint:IsA("Motor6D") and not joint:GetAttribute("Steers") then joint.Part1 else nil
		if hub then
			local spot = Instance.new("Attachment")
			spot.Name = "TyreSmoke"
			spot.WorldPosition = hub.Position - chassis.CFrame.UpVector * 0.9
			spot.Parent = hub
			local emitter = Instance.new("ParticleEmitter")
			emitter.Texture = "rbxasset://textures/particles/smoke_main.dds"
			emitter.Rate = 0
			emitter.Lifetime = NumberRange.new(1.2, 2.2)
			emitter.Speed = NumberRange.new(1.5, 4)
			emitter.SpreadAngle = Vector2.new(60, 60)
			emitter.EmissionDirection = Enum.NormalId.Top
			emitter.Drag = 1.5
			emitter.Acceleration = Vector3.new(0, 1.2, 0)
			emitter.RotSpeed = NumberRange.new(-40, 40)
			emitter.Rotation = NumberRange.new(0, 360)
			emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.5), NumberSequenceKeypoint.new(1, 9) })
			emitter.Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.55),
				NumberSequenceKeypoint.new(0.3, 0.7),
				NumberSequenceKeypoint.new(1, 1),
			})
			emitter.Color = ColorSequence.new(Color3.fromRGB(225, 225, 228))
			emitter.LightInfluence = 1
			emitter.Parent = spot
			table.insert(emitters, emitter)
		end
	end
	return emitters
end

local function addFlames(tip: Attachment)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "Flame"
	emitter.Texture = "rbxasset://textures/particles/fire_main.dds"
	emitter.EmissionDirection = Enum.NormalId.Back -- out of the back of the car
	emitter.Rate = 0
	emitter.Lifetime = NumberRange.new(0.06, 0.13)
	emitter.Speed = NumberRange.new(10, 18)
	emitter.SpreadAngle = Vector2.new(12, 12)
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.55), NumberSequenceKeypoint.new(1, 0.15) })
	emitter.Color = ColorSequence.new(Color3.fromRGB(120, 170, 255), Color3.fromRGB(255, 120, 30))
	emitter.LightEmission = 1
	emitter.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) })
	emitter.Parent = tip
	local light = Instance.new("PointLight")
	light.Name = "Glow"
	light.Color = Color3.fromRGB(255, 140, 50)
	light.Range = 10
	light.Enabled = false
	light.Parent = tip
end

local function number(car: Instance, name: string, default: number): number
	local value = car:GetAttribute(name)
	return if typeof(value) == "number" then value else default
end

local function newEngine(car: Model): Engine?
	local chassis = car.PrimaryPart
	if not chassis then
		return nil
	end
	local bodyRoot = car:FindFirstChild("BodyRoot")
	local joint = bodyRoot and bodyRoot:FindFirstChild("BodyJoint")
	local pops = car:GetAttribute("Pops") == true
	local exhausts: { Attachment } = {}
	if bodyRoot then
		for _, child in bodyRoot:GetChildren() do
			if child:IsA("Attachment") and child.Name:sub(1, 7) == "Exhaust" then
				table.insert(exhausts, child)
				if pops then
					addFlames(child)
				end
			end
		end
	end
	local bangs: { Sound } = {}
	if pops then
		for _ = 1, BANGS do
			table.insert(bangs, newSound(SOUNDS.pop, chassis, false, 1))
		end
	end
	local profileName = car:GetAttribute("EngineSound")
	local profile = if typeof(profileName) == "string" then EngineSounds.Profiles[profileName] else nil
	local farts: { Sound } = {}
	local burble, startup = nil, nil
	if profile then
		local fartIds: { string } = profile.farts or {}
		for _, id in fartIds do
			table.insert(farts, newSound(id, chassis, false, profile.fartVolume or 2))
		end
		burble = if profile.burble then newSound(profile.burble, chassis, false, 1.3) else nil
		startup = if profile.startup then newSound(profile.startup, chassis, false, 1.4) else nil
	end
	return {
		car = car,
		chassis = chassis,
		seat = (car:FindFirstChild("DriverSeat") or car:FindFirstChild("DriveSeat")) :: VehicleSeat?,
		joint = if joint and joint:IsA("Motor6D") then joint else nil,
		exhausts = exhausts,
		box = Gearbox.boxFor(car),
		profile = profile,
		loops = {},
		farts = farts,
		burble = burble,
		startup = startup,
		startedAt = 0,
		smoke = addSmoke(chassis),
		bangs = bangs,
		nextBang = 1,
		bangPlays = {},
		blowOff = if number(car, "EngineVolume", 1) > 0 then newSound(SOUNDS.blowOff, chassis, false, 0.4) else nil,
		rpm = Gearbox.IDLE,
		gear = 1,
		upshifts = number(car, "Upshifts", 0),
		downshifts = number(car, "Downshifts", 0),
		lastPedal = 0,
		crackleUntil = 0,
		nextPop = 0,
		blipUntil = 0,
		brapUntil = 0,
		lastUpshift = 0,
		lastSpeed = 0,
		accel = 0,
		pitch = 0,
		pitchSpeed = 0,
		roll = 0,
		rollSpeed = 0,
	}
end

local function startSounds(engine: Engine)
	if engine.whine then
		return
	end
	local volume = number(engine.car, "EngineVolume", 1)
	local chassis = engine.chassis
	local function loop(id: string): Sound
		local sound = newSound(id, chassis, true, 0)
		sound:Play()
		return sound
	end
	local profile = engine.profile
	if profile then
		-- Real recordings: all of them play all the time, and the mix picks the right ones for the revs.
		-- The engine starts up first, with the idle fading in behind it.
		for _, recording in profile.loops do
			table.insert(engine.loops, loop(recording.id))
		end
		engine.startedAt = os.clock()
		local startup = engine.startup
		if startup then
			startup.TimePosition = 0
			startup:Play()
		end
	elseif volume > 0 then
		engine.idle = loop(SOUNDS.idle)
		engine.rev = loop(SOUNDS.rev)
	end
	engine.whine = loop(SOUNDS.whine)
	engine.skid = loop(SOUNDS.skid)
end

local function stopSounds(engine: Engine)
	for _, emitter in engine.smoke do
		emitter.Rate = 0
	end
	for _, sound in engine.loops do
		sound:Destroy()
	end
	table.clear(engine.loops)
	if engine.burble then
		engine.burble:Stop()
	end
	for _, key in { "idle", "rev", "whine", "skid", "horn" } do
		local sound = (engine :: any)[key] :: Sound?
		if sound then
			sound:Destroy()
			;(engine :: any)[key] = nil
		end
	end
end

-- The values A-Chassis keeps about the car you're driving (revs, gear, throttle), in its screen. There can be
-- old screens left over from cars you drove before, so it's the one whose Car points at this car.
local function aChassisValues(car: Model): Instance?
	local gui = player:FindFirstChild("PlayerGui")
	for _, interface in if gui then gui:GetChildren() else {} do
		local owner = interface.Name == "A-Chassis Interface" and interface:FindFirstChild("Car")
		if owner and owner:IsA("ObjectValue") and owner.Value == car then
			return interface:FindFirstChild("Values")
		end
	end
	return nil
end

-- The horn, while the driver holds it (the server sets the Horn attribute)
local function updateHorn(engine: Engine)
	local hornOn = engine.car:GetAttribute("Horn") == true
	local horn = engine.horn
	if hornOn and not horn then
		local sound = newSound(SOUNDS.horn, engine.chassis, true, 0.9)
		sound:Play()
		engine.horn = sound
	elseif not hornOn and horn then
		horn:Destroy()
		engine.horn = nil
	end
end

local function update(engine: Engine, dt: number, now: number, mine: boolean)
	local car, chassis = engine.car, engine.chassis
	local cframe = chassis.CFrame
	local velocity = chassis.AssemblyLinearVelocity
	local forwardSpeed = velocity:Dot(cframe.LookVector)
	local sideSpeed = velocity:Dot(cframe.RightVector)
	local accel = (forwardSpeed - engine.lastSpeed) / math.max(dt, 1 / 240)
	engine.lastSpeed = forwardSpeed
	engine.accel += (math.clamp(accel, -150, 150) - engine.accel) * math.min(dt * 10, 1)

	-- The body stays level on the chassis, like Birmingham Vehicle Simulator: no squat, dive or lean
	local joint = engine.joint
	if joint then
		joint.Transform = CFrame.identity
	end

	-- The engine's only running with someone in the driver's seat
	local seat = engine.seat
	local running = seat ~= nil and seat.Occupant ~= nil
	if not running then
		stopSounds(engine)
		return
	end
	local chassisCar = car:GetAttribute("ChassisCar") == true
	if chassisCar and not engine.profile then
		updateHorn(engine) -- A-Chassis cars make their own engine, tyre and exhaust sounds unless we give them ours
		return
	end
	startSounds(engine)

	-- What the engine's doing: the driver's own device knows; for anyone else's car, guess from how it moves
	local topSpeed = number(car, "TopSpeed", 120)
	local rpmNow, drive, slip, pedal
	local upshifted, downshifted = false, false
	local chassisValues = if mine and chassisCar then aChassisValues(car) else nil
	if chassisValues then
		-- An A-Chassis car you're driving: its own revs, gear and throttle
		local function value(name: string, default: number): number
			local holder = chassisValues:FindFirstChild(name)
			local v = holder and (holder :: any).Value
			return if typeof(v) == "number" then v else default
		end
		rpmNow = math.max(value("RPM", Gearbox.IDLE), Gearbox.IDLE)
		drive = math.clamp(value("Throttle", 0), 0, 1)
		pedal = drive
		local gear = value("Gear", 1)
		upshifted = gear > engine.gear and engine.gear >= 1
		downshifted = gear < engine.gear and gear >= 1
		engine.gear = gear
		slip = math.abs(sideSpeed) + (if value("Brake", 0) > 0.5 and math.abs(forwardSpeed) > 20 then 6 else 0)
	elseif mine then
		rpmNow = number(car, "Rpm", Gearbox.IDLE)
		drive = number(car, "Drive", 0)
		pedal = number(car, "Throttle", 0)
		slip = number(car, "Slip", 0)
		local ups, downs = number(car, "Upshifts", 0), number(car, "Downshifts", 0)
		upshifted = ups > engine.upshifts
		downshifted = downs > engine.downshifts
		engine.upshifts, engine.downshifts = ups, downs
	else
		local accelerating = engine.accel > 3
		local gear = if forwardSpeed < -1 then 0 else Gearbox.guess(engine.box, forwardSpeed, engine.gear, topSpeed, accelerating)
		upshifted = gear > engine.gear and engine.gear >= 1
		downshifted = gear < engine.gear and gear >= 1
		engine.gear = gear
		rpmNow = Gearbox.rpm(engine.box, forwardSpeed, gear, topSpeed, number(car, "ReverseSpeed", 24))
		drive = if accelerating then math.clamp(engine.accel / (number(car, "Acceleration", 15) * 0.6), 0.3, 1) else 0
		slip = math.abs(sideSpeed) + (if engine.accel < -40 then 6 else 0)
		pedal = drive
	end

	-- The needle doesn't jump: it swings to the new revs quickly (a gear change drops it in a tenth of a second)
	engine.rpm += (rpmNow - engine.rpm) * math.min(dt * 18, 1)
	local share = Gearbox.share(engine.rpm)
	local pitch = number(car, "EnginePitch", 1)
	local volume = number(car, "EngineVolume", 1)

	-- Changing down: the engine blips its revs to match
	if downshifted then
		engine.blipUntil = now + 0.12
	end
	local blip = if now < engine.blipUntil then 0.12 else 0

	local cut = if now < engine.brapUntil then 0.3 else 1 -- the ignition cut on a brap
	local profile = engine.profile
	if profile and #engine.loops > 0 then
		-- Real recordings: the two nearest the revs play, each sped up or slowed down to match, faded across
		-- with equal power so the loudness stays even. Louder on the accelerator, quieter on the overrun.
		-- After a start-up the idle fades in behind the starter.
		local loops = profile.loops
		local soundRpm = engine.rpm * (1 + blip)
		local fadeIn = if engine.startup then math.clamp((now - engine.startedAt - 0.6) / 0.8, 0, 1) else 1
		local loudness = volume * cut * fadeIn * (0.5 + 0.5 * drive) * (0.8 + 0.4 * share)
		local below = 1
		for i = 1, #loops - 1 do
			if soundRpm >= loops[i].rpm then
				below = i
			end
		end
		-- Only fade across the middle half of the gap, so no recording gets stretched too far from its own revs
		local blend = 0
		if #loops > 1 then
			local along = (soundRpm - loops[below].rpm) / (loops[below + 1].rpm - loops[below].rpm)
			blend = math.clamp((along - 0.25) / 0.5, 0, 1)
		end
		for i, recording in loops do
			local weight = if i == below then math.cos(blend * math.pi / 2) elseif i == below + 1 then math.sin(blend * math.pi / 2) else 0
			local sound = engine.loops[i]
			sound.Volume = recording.volume * weight * loudness
			sound.PlaybackSpeed = math.clamp(soundRpm / recording.rpm, 0.5, 2.2) * pitch
		end
	end
	local idle, rev, whine, skid = engine.idle, engine.rev, engine.whine, engine.skid
	if idle and rev then
		-- Two recordings mixed: the tick-over fades out as the revs rise and the revving one takes over
		idle.Volume = volume * math.clamp(0.75 - share * 1.6, 0, 0.75)
		idle.PlaybackSpeed = pitch * (0.95 + share * 0.5)
		rev.Volume = cut * volume * math.clamp(share * 3, 0, 1) * (0.35 + 0.45 * drive + 0.25 * share)
		rev.PlaybackSpeed = pitch * (0.62 + (share + blip) * 0.9)
	end
	if whine then
		whine.Volume = (if volume > 0 then (if profile then 0.03 else 0.05) + 0.12 * share * drive else 0.15 + 0.25 * share)
		whine.PlaybackSpeed = 0.7 + share * 1.1
	end
	if skid then
		local squeal = math.clamp((slip - 9) / 22, 0, 1)
		skid.Volume = squeal * 0.7
		skid.PlaybackSpeed = 0.9 + squeal * 0.2
	end
	local smokiness = math.clamp((slip - 14) / 22, 0, 1)
	for _, emitter in engine.smoke do
		emitter.Rate = smokiness * 45
	end

	updateHorn(engine)

	-- Changing up: a hiss from the turbo's blow-off valve (not on real-engine cars, whose recordings have
	-- their own), and a brap from the exhaust on cars that pop: recorded if the engine has one, made up if not
	if upshifted then
		engine.lastUpshift = now
		if volume > 0 and engine.rpm > 4500 then
			local blowOff = engine.blowOff
			if blowOff and not profile then
				blowOff.PlaybackSpeed = random:NextNumber(0.95, 1.1)
				blowOff.TimePosition = 0
				blowOff:Play()
			end
			if car:GetAttribute("Pops") then
				if #engine.farts > 0 then
					fart(engine)
				else
					brap(engine)
				end
			end
		end
	end

	-- Lifting off at high revs: the exhaust crackles and pops for a second or so (cars that pop only), with
	-- the engine's own recorded burble if it has one. For other players' cars we only see the car slow down,
	-- and a gear change looks the same, so skip those.
	if car:GetAttribute("Pops") then
		local changingGear = not mine and now - engine.lastUpshift < 0.4
		local burble = engine.burble
		if engine.lastPedal > 0.5 and pedal < 0.1 and engine.rpm > 4000 and not changingGear then
			engine.crackleUntil = now + random:NextNumber(0.8, 1.4)
			engine.nextPop = now + random:NextNumber(0.03, 0.1)
			pop(engine, true)
			if burble then
				burble.PlaybackSpeed = random:NextNumber(0.95, 1.05)
				burble.TimePosition = 0
				burble:Play()
			end
		end
		if burble and burble.IsPlaying and (pedal > 0.3 or now > engine.crackleUntil + 0.3) then
			burble:Stop() -- back on the accelerator, or the crackle's over
		end
		if downshifted and random:NextNumber() < 0.6 then
			pop(engine, false)
		end
		if now < engine.crackleUntil and pedal < 0.1 and engine.rpm > 2800 and now >= engine.nextPop and not changingGear then
			-- With a recorded burble the bangs are in the recording: just the flames, and the odd extra bang
			if burble and random:NextNumber() < 0.7 then
				flame(engine, false)
			else
				pop(engine, false)
			end
			engine.nextPop = now + random:NextNumber(0.06, 0.2)
		end
	end
	engine.lastPedal = pedal
end

-- Every frame: the nearest cars to the camera get their sounds and lean; cars far away are forgotten
local camera = Workspace.CurrentCamera
RunService.Heartbeat:Connect(function(dt)
	local cars = Workspace:FindFirstChild("Cars")
	if not cars then
		return
	end
	local now = os.clock()
	local focus = camera.CFrame.Position
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")

	local near: { { car: Model, distance: number } } = {}
	for _, car in cars:GetChildren() do
		local chassis = if car:IsA("Model") then car.PrimaryPart else nil
		if chassis then
			local distance = (chassis.Position - focus).Magnitude
			if distance < HEAR_WITHIN then
				table.insert(near, { car = car :: Model, distance = distance })
			end
		end
	end
	table.sort(near, function(a, b)
		return a.distance < b.distance
	end)

	local heard: { [Model]: boolean } = {}
	for i, entry in near do
		if i > MOST_ENGINES then
			break
		end
		local car = entry.car
		local engine = engines[car] or newEngine(car)
		if engine then
			engines[car] = engine
			heard[car] = true
			local seat = engine.seat
			local mine = humanoid ~= nil and seat ~= nil and seat.Occupant == humanoid
			update(engine, dt, now, mine)
		end
	end

	-- Quiet the cars that dropped out of range, and forget cars that have gone
	for car, engine in engines do
		if not heard[car] then
			stopSounds(engine)
			local chassis = engine.chassis
			if not car.Parent or not chassis.Parent or (chassis.Position - focus).Magnitude > FORGET_BEYOND then
				if engine.joint then
					engine.joint.Transform = CFrame.identity
				end
				for _, sound in engine.bangs do
					sound:Destroy()
				end
				if engine.blowOff then
					engine.blowOff:Destroy()
				end
				for _, sound in engine.farts do
					sound:Destroy()
				end
				for _, emitter in engine.smoke do
					if emitter.Parent then
						emitter.Parent:Destroy()
					end
				end
				for _, sound in { engine.burble, engine.startup } do
					if sound then
						sound:Destroy()
					end
				end
				engines[car] = nil
			end
		end
	end
end)
