-- People walking along the pavements near you, so the streets feel alive like Birmingham Vehicle Simulator.
-- They're on your device only, so they cost the server nothing. The server makes the people
-- (ReplicatedStorage → PedestrianModels, see the Pedestrians module) and LondonMap lists the pavements
-- (MapInfo → Pavements: each one a line of points along the middle of a pavement). Up to MOST_PEOPLE walk
-- near the camera; they turn round at the end of their pavement and disappear when you're far away.

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local MOST_PEOPLE = 20
local SHOW_WITHIN = 200 -- studs from the camera
local HIDE_BEYOND = 260
local CELL = 200
local WALK_ANIMATION = "rbxassetid://507777826" -- Roblox's own R15 walk
local PAVEMENT_TOP = 0.6

local mapInfo = ReplicatedStorage:WaitForChild("MapInfo")
local data = mapInfo:WaitForChild("Pavements") :: StringValue
local models = ReplicatedStorage:WaitForChild("PedestrianModels", 60)
if not models then
	return
end
-- The server makes them one at a time; wait until there are a few
for _ = 1, 40 do
	if #models:GetChildren() >= 4 then
		break
	end
	task.wait(0.25)
end
local templates = models:GetChildren()
if #templates == 0 then
	return
end

type Line = { points: { Vector3 }, dists: { number }, length: number }

local lines: { Line } = {}
local cells: { [string]: { number } } = {}

local function cellKey(x: number, z: number): string
	return math.floor(x / CELL) .. "," .. math.floor(z / CELL)
end

local ok, decoded = pcall(function(): any
	return HttpService:JSONDecode(data.Value)
end)
if not ok or type(decoded) ~= "table" then
	return
end
for _, flat in decoded do
	local points: { Vector3 }, dists: { number } = {}, {}
	for k = 1, #flat - 1, 2 do
		local p = Vector3.new(flat[k], PAVEMENT_TOP, flat[k + 1])
		table.insert(points, p)
		dists[#points] = if #points == 1 then 0 else dists[#points - 1] + (p - points[#points - 1]).Magnitude
	end
	if #points >= 2 and dists[#points] > 20 then
		table.insert(lines, { points = points, dists = dists, length = dists[#points] })
		local index = #lines
		local seen: { [string]: boolean } = {}
		for _, p in points do
			local key = cellKey(p.X, p.Z)
			if not seen[key] then
				seen[key] = true
				cells[key] = cells[key] or {}
				table.insert(cells[key], index)
			end
		end
	end
end
if #lines == 0 then
	return
end

-- Where along a line, and which way it runs there. `hint` is the segment last used, to save searching.
local function pointAt(line: Line, s: number, hint: number): (Vector3, Vector3, number)
	local k = math.clamp(hint, 2, #line.points)
	while k < #line.points and line.dists[k] < s do
		k += 1
	end
	while k > 2 and line.dists[k - 1] > s do
		k -= 1
	end
	local a, b = line.points[k - 1], line.points[k]
	local seg = line.dists[k] - line.dists[k - 1]
	local f = if seg > 1e-6 then math.clamp((s - line.dists[k - 1]) / seg, 0, 1) else 0
	return a:Lerp(b, f), (b - a).Unit, k
end

type Walker = {
	model: Model,
	root: BasePart,
	height: number,
	track: AnimationTrack?,
	line: Line,
	s: number,
	direction: number,
	speed: number,
	segment: number,
	sideStep: number,
}

local folder = Instance.new("Folder")
folder.Name = "Pedestrians"
folder.Parent = Workspace

local walkers: { Walker } = {}
local pool: { Walker } = {}
local random = Random.new()

local walkAnimation = Instance.new("Animation")
walkAnimation.AnimationId = WALK_ANIMATION

local function newWalker(): Walker?
	local template = templates[random:NextInteger(1, #templates)]
	local model = template:Clone() :: Model
	local root = model:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid then
		model:Destroy()
		return nil
	end
	root.Anchored = true
	local height = humanoid.HipHeight + root.Size.Y / 2
	model.Parent = folder
	local track: AnimationTrack? = nil
	local animator = humanoid:FindFirstChildOfClass("Animator") or Instance.new("Animator", humanoid)
	local loaded, result = pcall(function()
		return animator:LoadAnimation(walkAnimation)
	end)
	if loaded and result then
		track = result
		result.Looped = true
	end
	return {
		model = model,
		root = root,
		height = height,
		track = track,
		line = lines[1],
		s = 0,
		direction = 1,
		speed = 4,
		segment = 2,
		sideStep = 0,
	}
end

local function spawnOn(line: Line, s: number)
	local walker = table.remove(pool) or newWalker()
	if not walker then
		return
	end
	walker.line = line
	walker.s = s
	walker.direction = if random:NextNumber() < 0.5 then 1 else -1
	walker.speed = random:NextNumber(3.6, 5.2)
	walker.segment = 2
	walker.sideStep = random:NextNumber(-2.2, 2.2) -- not everyone walks down the exact middle
	walker.model.Parent = folder
	local track = walker.track
	if track then
		track:Play(0.2)
		track:AdjustSpeed(walker.speed / 11)
	end
	table.insert(walkers, walker)
end

local function putAway(index: number)
	local walker = table.remove(walkers, index)
	if not walker then
		return
	end
	if walker.track then
		walker.track:Stop(0)
	end
	walker.model.Parent = nil
	table.insert(pool, walker)
end

-- Walking, every frame
RunService.Heartbeat:Connect(function(dt)
	if #walkers == 0 then
		return
	end
	local parts: { BasePart } = {}
	local frames: { CFrame } = {}
	for _, walker in walkers do
		local line = walker.line
		walker.s += walker.direction * walker.speed * dt
		if walker.s >= line.length then
			walker.s = line.length
			walker.direction = -1
		elseif walker.s <= 0 then
			walker.s = 0
			walker.direction = 1
		end
		local p, along, k = pointAt(line, walker.s, walker.segment)
		walker.segment = k
		local facing = along * walker.direction
		local side = Vector3.new(-facing.Z, 0, facing.X)
		local at = p + side * walker.sideStep + Vector3.new(0, walker.height, 0)
		table.insert(parts, walker.root)
		table.insert(frames, CFrame.lookAt(at, at + facing))
	end
	Workspace:BulkMoveTo(parts, frames, Enum.BulkMoveMode.FireCFrameChanged)
end)

-- Adding people near the camera and taking away the ones left far behind, twice a second
local camera = Workspace.CurrentCamera
while true do
	local focus = camera.CFrame.Position
	for index = #walkers, 1, -1 do
		local walker = walkers[index]
		if (walker.root.Position - focus).Magnitude > HIDE_BEYOND then
			putAway(index)
		end
	end
	if #walkers < MOST_PEOPLE then
		local near: { number } = {}
		local reach = math.ceil(SHOW_WITHIN / CELL)
		local cx, cz = math.floor(focus.X / CELL), math.floor(focus.Z / CELL)
		for i = cx - reach, cx + reach do
			for j = cz - reach, cz + reach do
				local list = cells[i .. "," .. j]
				if list then
					for _, index in list do
						table.insert(near, index)
					end
				end
			end
		end
		local added = 0
		for _ = 1, 12 do
			if #near == 0 or #walkers >= MOST_PEOPLE or added >= 1 then
				break
			end
			local line = lines[near[random:NextInteger(1, #near)]]
			local s = random:NextNumber(0, line.length)
			local p = pointAt(line, s, 2)
			local distance = (p - focus).Magnitude
			if distance < SHOW_WITHIN and distance > 30 then
				spawnOn(line, s)
				added += 1
			end
		end
	end
	task.wait(0.25)
end
