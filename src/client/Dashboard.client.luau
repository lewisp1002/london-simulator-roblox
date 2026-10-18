-- What you see while driving, laid out like Birmingham Vehicle Simulator:
--   bottom left: a panel with your speed in mph, the speed limit, the day and time, and a minimap
--     of the roads around you (other players are blue dots, you're the white arrow in the middle)
--   right: the driving controls list
-- The minimap reads the roads from ReplicatedStorage → MapInfo → Minimap, which LondonMap writes.

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Ui = require(script.Parent:WaitForChild("Ui"))
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Gearbox = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Gearbox"))

local LIMIT_CHECK_SECONDS = 0.25
local MAP_SCALE = 0.32 -- pixels per stud
local PANEL_WIDTH, PANEL_HEIGHT = 300, 232
local MAP_TOP = 58 -- the speed and time sit above the map

local C = Ui.Colours
local player = Players.LocalPlayer

local gui = Ui.screen("Dashboard", 4)
gui.Enabled = false

local panel = Ui.panel({
	AnchorPoint = Vector2.new(0, 1),
	Position = UDim2.new(0, 16, 1, -16),
	Size = UDim2.fromOffset(PANEL_WIDTH, PANEL_HEIGHT),
	Parent = gui,
})
panel.BackgroundTransparency = 0.18

local speedLabel = Ui.label("0", 36, Enum.FontWeight.Bold, {
	Position = UDim2.fromOffset(16, 8),
	Size = UDim2.fromOffset(0, 40),
	AutomaticSize = Enum.AutomaticSize.X,
	TextXAlignment = Enum.TextXAlignment.Left,
	Parent = panel,
})
local unitLabel = Ui.label("mph", 12, Enum.FontWeight.Medium, {
	Size = UDim2.fromOffset(30, 16),
	TextXAlignment = Enum.TextXAlignment.Left,
	TextColor3 = C.Muted,
	Parent = panel,
})

-- Speed limit roundel: a white disc with a red ring
local limitSign = Ui.make("Frame", { Size = UDim2.fromOffset(34, 34), BackgroundColor3 = Color3.new(1, 1, 1), Visible = false, Parent = panel })
Ui.corner(limitSign, 17)
Ui.make("UIStroke", { Color = Color3.fromRGB(215, 30, 30), Thickness = 4, Parent = limitSign })
local limitLabel = Ui.label("", 15, Enum.FontWeight.Bold, { Size = UDim2.fromScale(1, 1), TextColor3 = Color3.new(0, 0, 0), Parent = limitSign })

local clockLabel = Ui.label("", 12, Enum.FontWeight.Medium, {
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -16, 0, 14),
	Size = UDim2.fromOffset(120, 16),
	TextXAlignment = Enum.TextXAlignment.Right,
	Parent = panel,
})

-- The gear you're in, under the time, and a rev counter: a thin bar along the top of the map that fills
-- up as the engine revs and goes red near the redline (Driving puts Rpm and Gear on your car)
local gearLabel = Ui.label("", 12, Enum.FontWeight.Bold, {
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -16, 0, 32),
	Size = UDim2.fromOffset(120, 16),
	TextXAlignment = Enum.TextXAlignment.Right,
	Parent = panel,
})
local revTrack = Ui.make("Frame", {
	Position = UDim2.fromOffset(16, MAP_TOP - 6),
	Size = UDim2.new(1, -32, 0, 3),
	BackgroundColor3 = Color3.fromRGB(70, 74, 82),
	BorderSizePixel = 0,
	Parent = panel,
})
Ui.corner(revTrack, 2)
local revFill = Ui.make("Frame", { Size = UDim2.fromScale(0, 1), BorderSizePixel = 0, Parent = revTrack })
Ui.corner(revFill, 2)

-- The map: a CanvasGroup clips it to the rounded panel even when it's turned
local mapWindow = Ui.make("CanvasGroup", {
	Position = UDim2.fromOffset(0, MAP_TOP),
	Size = UDim2.new(1, 0, 1, -MAP_TOP),
	BackgroundColor3 = Color3.fromRGB(22, 24, 30),
	BackgroundTransparency = 0.25,
	BorderSizePixel = 0,
	Parent = panel,
})
Ui.corner(mapWindow, 14)
local mapCentre = Vector2.new(PANEL_WIDTH / 2, (PANEL_HEIGHT - MAP_TOP) * 0.62)
-- `pivot` turns around the player; `world` slides so the player stays in the middle
local pivot = Ui.make("Frame", { Position = UDim2.fromOffset(mapCentre.X, mapCentre.Y), Size = UDim2.new(), BackgroundTransparency = 1, Parent = mapWindow })
local world = Ui.make("Frame", { Size = UDim2.new(), BackgroundTransparency = 1, Parent = pivot })
local dots = Ui.make("Frame", { Size = UDim2.new(), BackgroundTransparency = 1, ZIndex = 5, Parent = world })

local ROAD_COLOURS = {
	side = Color3.fromRGB(120, 124, 132),
	main = Color3.fromRGB(165, 168, 176),
	dual = Color3.fromRGB(200, 202, 210),
	motorway = Color3.fromRGB(95, 150, 225),
	yard = Color3.fromRGB(70, 74, 82),
	water = Color3.fromRGB(45, 85, 130),
	park = Color3.fromRGB(40, 85, 50),
}
local ROAD_ORDER = { water = 1, park = 1, yard = 2, side = 3, main = 4, dual = 5, motorway = 6 }
local ROADS = { side = true, main = true, dual = true, motorway = true }

-- One thing on the map. Entries are:
--   { "l", x1, z1, x2, z2, width, kind }  a straight line (roads, the river)
--   { "c", x, z, radius, kind }           a circle (roundabouts)
--   { "q", x, z, width, depth, degrees, kind }  a turned rectangle (depots)
--   { x, z, sizeX, sizeZ, kind }           a rectangle (parks)
-- Every drawn thing with where it is, so the ones outside the little map window can be hidden: thousands
-- of frames redrawn every frame inside the CanvasGroup made the game lag
type Drawn = { frame: Frame, x: number, z: number, reach: number }
local drawn: { Drawn } = {}

local function drawEntry(entry: { any })
	local kind: string
	local frame: Frame
	local cx, cz, reach = 0, 0, 0
	if entry[1] == "l" then
		local x1, z1, x2, z2, width = entry[2], entry[3], entry[4], entry[5], entry[6]
		kind = entry[7]
		local dx, dz = x2 - x1, z2 - z1
		local length = math.sqrt(dx * dx + dz * dz)
		cx, cz, reach = (x1 + x2) / 2, (z1 + z2) / 2, length / 2 + width
		-- Draw roads thinner than they really are so the map stays readable
		local thickness = if ROADS[kind] then math.max(3, width * MAP_SCALE * 0.55) else width * MAP_SCALE
		frame = Ui.make("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset((x1 + x2) / 2 * MAP_SCALE, (z1 + z2) / 2 * MAP_SCALE),
			-- A little longer than the line so the pieces of a curve overlap
			Size = UDim2.fromOffset(length * MAP_SCALE + thickness * 0.5, thickness),
			Rotation = math.deg(math.atan2(dz, dx)),
			BorderSizePixel = 0,
			Parent = world,
		})
	elseif entry[1] == "c" then
		local radius = entry[4]
		kind = entry[5]
		cx, cz, reach = entry[2], entry[3], radius
		frame = Ui.make("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(entry[2] * MAP_SCALE, entry[3] * MAP_SCALE),
			Size = UDim2.fromOffset(radius * 2 * MAP_SCALE, radius * 2 * MAP_SCALE),
			BorderSizePixel = 0,
			Parent = world,
		})
		Ui.corner(frame, radius * MAP_SCALE)
	elseif entry[1] == "q" then
		kind = entry[7]
		cx, cz, reach = entry[2], entry[3], math.max(entry[4], entry[5])
		frame = Ui.make("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(entry[2] * MAP_SCALE, entry[3] * MAP_SCALE),
			Size = UDim2.fromOffset(entry[4] * MAP_SCALE, entry[5] * MAP_SCALE),
			Rotation = -entry[6],
			BorderSizePixel = 0,
			Parent = world,
		})
	else
		kind = entry[5]
		cx, cz, reach = entry[1], entry[2], math.max(entry[3], entry[4])
		frame = Ui.make("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(entry[1] * MAP_SCALE, entry[2] * MAP_SCALE),
			Size = UDim2.fromOffset(entry[3] * MAP_SCALE, entry[4] * MAP_SCALE),
			BorderSizePixel = 0,
			Parent = world,
		})
	end
	frame.BackgroundColor3 = ROAD_COLOURS[kind] or ROAD_COLOURS.side
	frame.ZIndex = ROAD_ORDER[kind] or 3
	frame.BackgroundTransparency = if kind == "yard" then 0.4 else 0
	frame.Visible = false
	table.insert(drawn, { frame = frame, x = cx, z = cz, reach = reach })
end

-- How far from you the map window can show, in studs (corner to corner, with room for turning)
local VIEW = math.sqrt(PANEL_WIDTH ^ 2 + PANEL_HEIGHT ^ 2) / MAP_SCALE * 0.6
local sinceCull = math.huge

local function cull(position: Vector3)
	for _, item in drawn do
		local dx, dz = item.x - position.X, item.z - position.Z
		local near = VIEW + item.reach
		item.frame.Visible = dx * dx + dz * dz < near * near
	end
end

local function drawMap()
	local mapInfo = ReplicatedStorage:WaitForChild("MapInfo", 30)
	local data = mapInfo and mapInfo:WaitForChild("Minimap", 30)
	if not data or not data:IsA("StringValue") then
		return
	end
	local ok, entries = pcall(function(): any
		return HttpService:JSONDecode(data.Value)
	end)
	if not ok or type(entries) ~= "table" then
		return
	end
	for _, entry in entries do
		drawEntry(entry)
	end
end
task.spawn(drawMap)

-- You: a white arrow in the middle, always pointing up
local arrow = Ui.label("▲", 18, Enum.FontWeight.Bold, {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromOffset(mapCentre.X, mapCentre.Y),
	Size = UDim2.fromOffset(20, 20),
	ZIndex = 10,
	Parent = mapWindow,
})
arrow.TextStrokeTransparency = 0.3

local playerDots: { [Player]: Frame } = {}
local function dotFor(other: Player): Frame
	local existing = playerDots[other]
	if existing then
		return existing
	end
	local dot: Frame = Ui.make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(9, 9),
		BackgroundColor3 = Color3.fromRGB(80, 140, 255),
		BorderSizePixel = 0,
		ZIndex = 6,
		Parent = dots,
	})
	Ui.corner(dot, 5)
	Ui.make("UIStroke", { Color = Color3.new(1, 1, 1), Thickness = 1.5, Parent = dot })
	playerDots[other] = dot
	return dot
end
Players.PlayerRemoving:Connect(function(other)
	local dot = playerDots[other]
	if dot then
		dot:Destroy()
		playerDots[other] = nil
	end
end)

-- Driving controls on the right --------------------------------------------------------------

local controlsList = Ui.make("Frame", {
	AnchorPoint = Vector2.new(1, 1),
	Position = UDim2.new(1, -16, 1, -16),
	Size = UDim2.fromOffset(300, 0),
	AutomaticSize = Enum.AutomaticSize.Y,
	BackgroundTransparency = 1,
	Parent = gui,
})
Ui.make("UIListLayout", { Padding = UDim.new(0, 7), HorizontalAlignment = Enum.HorizontalAlignment.Right, SortOrder = Enum.SortOrder.LayoutOrder, Parent = controlsList })

local blueLightsRow: Frame? = nil
-- Each control's key on a keyboard, then its button on a controller
local keyLabels: { { label: TextLabel, keyboard: string, gamepad: string } } = {}
for order, control in {
	{ "Steering", "WASD", "Stick + RT / LT" },
	{ "Handbrake", "Space", "A" },
	{ "Indicators", "Q-E", "D-pad left / right" },
	{ "Hazards", "B", "D-pad down" },
	{ "Lights", "L", "D-pad up" },
	{ "Blue lights", "R", "X" },
	{ "Horn", "H", "Press left stick" },
	{ "Get out", "F", "Y" },
} do
	-- The action name and its key side by side, lined up on the right, however long the key's name is
	local row = Ui.make("Frame", { Size = UDim2.new(1, 0, 0, 28), BackgroundTransparency = 1, LayoutOrder = order, Parent = controlsList })
	Ui.make("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Right,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 10),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = row,
	})
	local key = Ui.label(control[2], 13, Enum.FontWeight.Medium, {
		Size = UDim2.fromOffset(0, 28),
		AutomaticSize = Enum.AutomaticSize.X,
		LayoutOrder = 2,
		Parent = row,
	})
	Ui.padding(key, 9, 0)
	Ui.corner(key, 14)
	Ui.make("UIStroke", { ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Color = Color3.new(1, 1, 1), Thickness = 1.5, Parent = key })
	local action = Ui.label(control[1], 14, Enum.FontWeight.Regular, {
		Size = UDim2.fromOffset(0, 28),
		AutomaticSize = Enum.AutomaticSize.X,
		TextXAlignment = Enum.TextXAlignment.Right,
		LayoutOrder = 1,
		Parent = row,
	})
	action.TextStrokeTransparency = 0.6
	key.TextStrokeTransparency = 0.7
	table.insert(keyLabels, { label = key, keyboard = control[2], gamepad = control[3] })
	if control[1] == "Blue lights" then
		blueLightsRow = row
	end
end

-- Show controller buttons when you're using a controller, keys when you're using the keyboard
local function showInputType(inputType: Enum.UserInputType)
	local isGamepad = inputType.Name:sub(1, 7) == "Gamepad"
	local isKeyboard = inputType == Enum.UserInputType.Keyboard or inputType.Name:sub(1, 5) == "Mouse"
	if not isGamepad and not isKeyboard then
		return
	end
	for _, entry in keyLabels do
		entry.label.Text = if isGamepad then entry.gamepad else entry.keyboard
	end
end
UserInputService.LastInputTypeChanged:Connect(showInputType)
showInputType(UserInputService:GetLastInputType())

local function applyControlsSetting()
	controlsList.Visible = Ui.settings.Controls
end
Ui.SettingChanged:Connect(applyControlsSetting)
applyControlsSetting()

-- Every frame while driving ----------------------------------------------------------------

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

local speedLimit: number? = nil
local sinceLimitCheck = math.huge

RunService.Heartbeat:Connect(function(dt)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local seat = humanoid and humanoid.SeatPart
	if Ui.menuOpen or not seat or not seat:IsA("VehicleSeat") then
		gui.Enabled = false
		sinceLimitCheck = math.huge
		return
	end
	gui.Enabled = true
	local car = seat.Parent :: Instance

	sinceLimitCheck += dt
	if sinceLimitCheck >= LIMIT_CHECK_SECONDS then
		sinceLimitCheck = 0
		rayParams.FilterDescendantsInstances = { car, character :: Instance }
		local hit = Workspace:Raycast(seat.Position, Vector3.new(0, -10, 0), rayParams)
		local limit = hit and hit.Instance:GetAttribute("SpeedLimit")
		speedLimit = if typeof(limit) == "number" then limit else nil
		clockLabel.Text = os.date("%a %H:%M") :: string
		if blueLightsRow then
			blueLightsRow.Visible = car:GetAttribute("HasBlueLights") == true
		end
	end

	local mph = math.floor(math.abs(seat.AssemblyLinearVelocity:Dot(seat.CFrame.LookVector)) * Config.MphPerStudPerSecond + 0.5)
	speedLabel.Text = tostring(mph)
	speedLabel.TextColor3 = if speedLimit and mph > speedLimit then C.Red else C.Text
	local speedWidth = speedLabel.TextBounds.X
	unitLabel.Position = UDim2.fromOffset(16 + speedWidth + 4, 30)
	limitSign.Visible = speedLimit ~= nil
	limitSign.Position = UDim2.fromOffset(16 + speedWidth + 38, 12)
	limitLabel.Text = if speedLimit then tostring(speedLimit) else ""

	local rpm, gear = car:GetAttribute("Rpm"), car:GetAttribute("Gear")
	if typeof(rpm) == "number" and typeof(gear) == "number" then
		local share = Gearbox.share(rpm)
		revFill.Size = UDim2.fromScale(share, 1)
		revFill.BackgroundColor3 = if rpm >= Gearbox.UP_AT then C.Red else C.Text
		gearLabel.Text = if gear <= 0 then "R" else "Gear " .. gear
	end
	revTrack.Visible = typeof(rpm) == "number"
	gearLabel.Visible = typeof(gear) == "number"

	-- Slide and turn the map so you're in the middle, facing up
	local position = seat.Position
	sinceCull += dt
	if sinceCull > 0.4 then
		sinceCull = 0
		cull(position)
	end
	world.Position = UDim2.fromOffset(-position.X * MAP_SCALE, -position.Z * MAP_SCALE)
	local look = seat.CFrame.LookVector
	pivot.Rotation = if Ui.settings.TurnMap then -90 - math.deg(math.atan2(look.Z, look.X)) else 0
	arrow.Rotation = if Ui.settings.TurnMap then 0 else 90 + math.deg(math.atan2(look.Z, look.X))

	for _, other in Players:GetPlayers() do
		if other ~= player then
			local otherCharacter = other.Character
			local root = otherCharacter and otherCharacter:FindFirstChild("HumanoidRootPart") :: BasePart?
			local dot = dotFor(other)
			dot.Visible = root ~= nil
			if root then
				dot.Position = UDim2.fromOffset(root.Position.X * MAP_SCALE, root.Position.Z * MAP_SCALE)
			end
		end
	end
end)
