-- While you're driving: your speed in mph, the speed limit of the road you're on, and the keyboard controls.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local LIMIT_CHECK_SECONDS = 0.25
local RED = Color3.fromRGB(220, 30, 30)
local WHITE = Color3.new(1, 1, 1)

local player = Players.LocalPlayer

local gui = Instance.new("ScreenGui")
gui.Name = "Speedometer"
gui.ResetOnSpawn = false
gui.Enabled = false
gui.Parent = player:WaitForChild("PlayerGui")

local panel = Instance.new("Frame")
panel.AnchorPoint = Vector2.new(0, 1)
panel.Position = UDim2.new(0, 16, 1, -16)
panel.Size = UDim2.fromOffset(190, 80)
panel.BackgroundColor3 = Color3.new(0, 0, 0)
panel.BackgroundTransparency = 0.3
panel.Parent = gui

local panelCorner = Instance.new("UICorner")
panelCorner.CornerRadius = UDim.new(0, 12)
panelCorner.Parent = panel

local speedLabel = Instance.new("TextLabel")
speedLabel.Position = UDim2.fromOffset(12, 4)
speedLabel.Size = UDim2.fromOffset(90, 50)
speedLabel.BackgroundTransparency = 1
speedLabel.Font = Enum.Font.GothamBold
speedLabel.TextSize = 44
speedLabel.TextColor3 = WHITE
speedLabel.TextXAlignment = Enum.TextXAlignment.Right
speedLabel.Text = "0"
speedLabel.Parent = panel

local unitLabel = Instance.new("TextLabel")
unitLabel.Position = UDim2.fromOffset(12, 52)
unitLabel.Size = UDim2.fromOffset(90, 18)
unitLabel.BackgroundTransparency = 1
unitLabel.Font = Enum.Font.GothamBold
unitLabel.TextSize = 14
unitLabel.TextColor3 = Color3.fromRGB(180, 180, 180)
unitLabel.TextXAlignment = Enum.TextXAlignment.Right
unitLabel.Text = "mph"
unitLabel.Parent = panel

-- A UK speed limit sign: white circle, red ring, black number
local limitSign = Instance.new("Frame")
limitSign.AnchorPoint = Vector2.new(1, 0.5)
limitSign.Position = UDim2.new(1, -16, 0.5, 0)
limitSign.Size = UDim2.fromOffset(54, 54)
limitSign.BackgroundColor3 = WHITE
limitSign.Visible = false
limitSign.Parent = panel

local signCorner = Instance.new("UICorner")
signCorner.CornerRadius = UDim.new(1, 0)
signCorner.Parent = limitSign

local signRing = Instance.new("UIStroke")
signRing.Color = RED
signRing.Thickness = 6
signRing.Parent = limitSign

local limitLabel = Instance.new("TextLabel")
limitLabel.Size = UDim2.fromScale(1, 1)
limitLabel.BackgroundTransparency = 1
limitLabel.Font = Enum.Font.GothamBold
limitLabel.TextSize = 24
limitLabel.TextColor3 = Color3.new(0, 0, 0)
limitLabel.Parent = limitSign

-- Keyboard controls listed down the right-hand side
local CONTROLS = {
	{ "Accelerate", "W" },
	{ "Brake / reverse", "S" },
	{ "Steer", "A-D" },
	{ "Get out", "Space" },
}

local controlsList = Instance.new("Frame")
controlsList.AnchorPoint = Vector2.new(1, 1)
controlsList.Position = UDim2.new(1, -16, 1, -16)
controlsList.Size = UDim2.fromOffset(220, 0)
controlsList.AutomaticSize = Enum.AutomaticSize.Y
controlsList.BackgroundTransparency = 1
controlsList.Visible = UserInputService.KeyboardEnabled
controlsList.Parent = gui

local controlsLayout = Instance.new("UIListLayout")
controlsLayout.SortOrder = Enum.SortOrder.LayoutOrder
controlsLayout.Padding = UDim.new(0, 6)
controlsLayout.Parent = controlsList

for i, control in CONTROLS do
	local row = Instance.new("Frame")
	row.LayoutOrder = i
	row.Size = UDim2.new(1, 0, 0, 28)
	row.BackgroundTransparency = 1
	row.Parent = controlsList

	local key = Instance.new("TextLabel")
	key.AnchorPoint = Vector2.new(1, 0)
	key.Position = UDim2.fromScale(1, 0)
	key.Size = UDim2.fromOffset(0, 28)
	key.AutomaticSize = Enum.AutomaticSize.X
	key.BackgroundTransparency = 1
	key.Font = Enum.Font.GothamMedium
	key.TextSize = 14
	key.TextColor3 = WHITE
	key.Text = control[2]
	key.Parent = row

	local keyPadding = Instance.new("UIPadding")
	keyPadding.PaddingLeft = UDim.new(0, 10)
	keyPadding.PaddingRight = UDim.new(0, 10)
	keyPadding.Parent = key

	local keyCorner = Instance.new("UICorner")
	keyCorner.CornerRadius = UDim.new(1, 0)
	keyCorner.Parent = key

	local keyOutline = Instance.new("UIStroke")
	keyOutline.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	keyOutline.Color = WHITE
	keyOutline.Thickness = 1.5
	keyOutline.Parent = key

	local action = Instance.new("TextLabel")
	action.Size = UDim2.new(1, -70, 1, 0)
	action.BackgroundTransparency = 1
	action.Font = Enum.Font.GothamMedium
	action.TextSize = 14
	action.TextColor3 = WHITE
	action.TextStrokeTransparency = 0.6
	action.TextXAlignment = Enum.TextXAlignment.Right
	action.Text = control[1]
	action.Parent = row
end

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

local speedLimit: number? = nil
local sinceLimitCheck = math.huge

RunService.Heartbeat:Connect(function(dt)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local seat = humanoid and humanoid.SeatPart
	if not seat or not seat:IsA("VehicleSeat") then
		gui.Enabled = false
		sinceLimitCheck = math.huge
		return
	end
	gui.Enabled = true

	sinceLimitCheck += dt
	if sinceLimitCheck >= LIMIT_CHECK_SECONDS then
		sinceLimitCheck = 0
		rayParams.FilterDescendantsInstances = { seat.Parent :: Instance, character :: Instance }
		local hit = Workspace:Raycast(seat.Position, Vector3.new(0, -8, 0), rayParams)
		local limit = hit and hit.Instance:GetAttribute("SpeedLimit")
		speedLimit = if typeof(limit) == "number" then limit else nil
	end

	local mph = math.floor(math.abs(seat.AssemblyLinearVelocity:Dot(seat.CFrame.LookVector)) * Config.MphPerStudPerSecond + 0.5)
	speedLabel.Text = tostring(mph)
	speedLabel.TextColor3 = if speedLimit and mph > speedLimit then RED else WHITE
	limitSign.Visible = speedLimit ~= nil
	limitLabel.Text = if speedLimit then tostring(speedLimit) else ""
end)
