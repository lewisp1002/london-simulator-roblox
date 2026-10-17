-- What you see while driving, laid out like Birmingham Vehicle Simulator:
--   bottom left: a panel with your speed in mph, the speed limit, the day and time, and a minimap
--     of the roads around you (other players are blue dots, you're the white arrow in the middle)
--   right: the driving controls list
-- The minimap reads the roads from ReplicatedStorage → MapInfo → Minimap, which TestTown writes.

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Ui = require(script.Parent:WaitForChild("Ui"))
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

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
	yard = Color3.fromRGB(70, 74, 82),
	water = Color3.fromRGB(45, 85, 130),
	park = Color3.fromRGB(40, 85, 50),
}
local ROAD_ORDER = { water = 1, park = 1, yard = 2, side = 3, main = 4, dual = 5 }

local function drawMap()
	local mapInfo = ReplicatedStorage:WaitForChild("MapInfo", 30)
	local data = mapInfo and mapInfo:WaitForChild("Minimap", 30)
	if not data or not data:IsA("StringValue") then
		return
	end
	local ok, rects = pcall(function(): any
		return HttpService:JSONDecode(data.Value)
	end)
	if not ok or type(rects) ~= "table" then
		return
	end
	for _, rect in rects do
		local x, z, sizeX, sizeZ, kind = rect[1], rect[2], rect[3], rect[4], rect[5]
		local isRoad = kind == "side" or kind == "main" or kind == "dual"
		-- Draw roads thinner than they really are so the map stays readable
		local thin = if isRoad then 0.55 else 1
		local width = if isRoad and sizeX < sizeZ then math.max(3, sizeX * MAP_SCALE * thin) else sizeX * MAP_SCALE
		local height = if isRoad and sizeZ <= sizeX then math.max(3, sizeZ * MAP_SCALE * thin) else sizeZ * MAP_SCALE
		local frame = Ui.make("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(x * MAP_SCALE, z * MAP_SCALE),
			Size = UDim2.fromOffset(width, height),
			BackgroundColor3 = ROAD_COLOURS[kind] or ROAD_COLOURS.side,
			BorderSizePixel = 0,
			ZIndex = ROAD_ORDER[kind] or 3,
			Parent = world,
		})
		frame.BackgroundTransparency = if kind == "yard" then 0.4 else 0
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
	Size = UDim2.fromOffset(220, 0),
	AutomaticSize = Enum.AutomaticSize.Y,
	BackgroundTransparency = 1,
	Parent = gui,
})
Ui.make("UIListLayout", { Padding = UDim.new(0, 7), HorizontalAlignment = Enum.HorizontalAlignment.Right, SortOrder = Enum.SortOrder.LayoutOrder, Parent = controlsList })

local blueLightsRow: Frame? = nil
for order, control in {
	{ "Steering", "WASD" },
	{ "Handbrake", "Space" },
	{ "Indicators", "Q-E" },
	{ "Hazards", "B" },
	{ "Lights", "L" },
	{ "Blue lights", "R" },
	{ "Get out", "F" },
} do
	local row = Ui.make("Frame", { Size = UDim2.new(1, 0, 0, 28), BackgroundTransparency = 1, LayoutOrder = order, Parent = controlsList })
	local key = Ui.label(control[2], 13, Enum.FontWeight.Medium, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.fromOffset(0, 28),
		AutomaticSize = Enum.AutomaticSize.X,
		Parent = row,
	})
	Ui.padding(key, 9, 0)
	Ui.corner(key, 14)
	Ui.make("UIStroke", { ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Color = Color3.new(1, 1, 1), Thickness = 1.5, Parent = key })
	local action = Ui.label(control[1], 14, Enum.FontWeight.Regular, {
		Size = UDim2.new(1, -70, 1, 0),
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = row,
	})
	action.TextStrokeTransparency = 0.6
	key.TextStrokeTransparency = 0.7
	if control[1] == "Blue lights" then
		blueLightsRow = row
	end
end

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

	-- Slide and turn the map so you're in the middle, facing up
	local position = seat.Position
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
