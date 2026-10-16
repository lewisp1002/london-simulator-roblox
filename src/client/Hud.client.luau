-- Shows the player's cash in the top-right corner, with a "+£100" pop-up when they earn money.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Format = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Format"))

local GREEN = Color3.fromRGB(80, 220, 120)

local player = Players.LocalPlayer

local gui = Instance.new("ScreenGui")
gui.Name = "Hud"
gui.ResetOnSpawn = false -- keep the HUD when the player respawns
gui.IgnoreGuiInset = true -- lets us line up with Roblox's own top bar buttons
gui.Parent = player:WaitForChild("PlayerGui")

local cashPill = Instance.new("TextLabel")
cashPill.Name = "Cash"
cashPill.Visible = false -- hidden until their data has loaded
cashPill.AnchorPoint = Vector2.new(1, 0)
cashPill.Position = UDim2.new(1, -12, 0, 12)
cashPill.Size = UDim2.fromOffset(0, 44)
cashPill.AutomaticSize = Enum.AutomaticSize.X
cashPill.BackgroundColor3 = Color3.new(0, 0, 0)
cashPill.BackgroundTransparency = 0.3
cashPill.Font = Enum.Font.GothamBold
cashPill.TextSize = 18
cashPill.TextColor3 = Color3.new(1, 1, 1)
cashPill.Parent = gui

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(1, 0) -- fully rounded ends
corner.Parent = cashPill

local padding = Instance.new("UIPadding")
padding.PaddingLeft = UDim.new(0, 16)
padding.PaddingRight = UDim.new(0, 16)
padding.Parent = cashPill

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
