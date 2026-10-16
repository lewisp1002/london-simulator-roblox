-- The bar in the top-right corner: a button to spawn your car, and your cash (with a "+£100" pop-up when you earn money).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Format = require(Shared:WaitForChild("Format"))

local spawnCarRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("SpawnCar") :: RemoteEvent

local GREEN = Color3.fromRGB(80, 220, 120)

local player = Players.LocalPlayer

local gui = Instance.new("ScreenGui")
gui.Name = "Hud"
gui.ResetOnSpawn = false -- keep the HUD when the player respawns
gui.IgnoreGuiInset = true -- lets us line up with Roblox's own top bar buttons
gui.Parent = player:WaitForChild("PlayerGui")

local topBar = Instance.new("Frame")
topBar.Name = "TopBar"
topBar.AnchorPoint = Vector2.new(1, 0)
topBar.Position = UDim2.new(1, -12, 0, 12)
topBar.Size = UDim2.fromOffset(0, 44)
topBar.AutomaticSize = Enum.AutomaticSize.X
topBar.BackgroundTransparency = 1
topBar.Parent = gui

local layout = Instance.new("UIListLayout")
layout.FillDirection = Enum.FillDirection.Horizontal
layout.HorizontalAlignment = Enum.HorizontalAlignment.Right
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Padding = UDim.new(0, 8)
layout.Parent = topBar

-- Rounded black "pill" shape shared by everything in the top bar
local function stylePill(pill: TextButton, order: number)
	pill.LayoutOrder = order
	pill.Size = UDim2.fromOffset(0, 44)
	pill.AutomaticSize = Enum.AutomaticSize.X
	pill.BackgroundColor3 = Color3.new(0, 0, 0)
	pill.BackgroundTransparency = 0.3
	pill.Font = Enum.Font.GothamBold
	pill.TextSize = 18
	pill.TextColor3 = Color3.new(1, 1, 1)

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0) -- fully rounded ends
	corner.Parent = pill

	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 16)
	padding.PaddingRight = UDim.new(0, 16)
	padding.Parent = pill

	pill.Parent = topBar
end

local spawnButton = Instance.new("TextButton")
spawnButton.Name = "SpawnCar"
spawnButton.Text = "🚗 Spawn car"
stylePill(spawnButton, 1)

-- A button so it can open the shop later on
local cashPill = Instance.new("TextButton")
cashPill.Name = "Cash"
cashPill.AutoButtonColor = false
cashPill.Visible = false -- hidden until their data has loaded
stylePill(cashPill, 2)

local coolingDown = false
spawnButton.Activated:Connect(function()
	if coolingDown then
		return
	end
	coolingDown = true
	spawnCarRemote:FireServer()
	spawnButton.TextTransparency = 0.5
	task.wait(Config.Car.SpawnCooldownSeconds)
	spawnButton.TextTransparency = 0
	coolingDown = false
end)

local function showGain(amount: number)
	local popup = Instance.new("TextLabel")
	popup.AnchorPoint = Vector2.new(1, 0)
	popup.Position = UDim2.new(1, -16, 0, 60)
	popup.Size = UDim2.fromOffset(200, 24)
	popup.BackgroundTransparency = 1
	popup.Font = Enum.Font.GothamBold
	popup.TextSize = 20
	popup.TextColor3 = GREEN
	popup.TextStrokeTransparency = 0.6
	popup.TextXAlignment = Enum.TextXAlignment.Right
	popup.Text = "+" .. Format.money(amount)
	popup.Parent = gui

	local tween = TweenService:Create(popup, TweenInfo.new(1.5), {
		Position = popup.Position + UDim2.fromOffset(0, 24),
		TextTransparency = 1,
		TextStrokeTransparency = 1,
	})
	tween.Completed:Once(function()
		popup:Destroy()
	end)
	tween:Play()
end

local lastCash: number? = nil

local function onCashChanged()
	local cash = player:GetAttribute("Cash")
	if typeof(cash) ~= "number" then
		return
	end
	if lastCash and cash > lastCash then
		showGain(cash - lastCash)
	end
	lastCash = cash
	cashPill.Text = Format.money(cash)
	cashPill.Visible = true
end

player:GetAttributeChangedSignal("Cash"):Connect(onCashChanged)
onCashChanged()
