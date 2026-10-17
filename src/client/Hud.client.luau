-- The bar across the top of the screen while you play, laid out like Birmingham Vehicle Simulator:
--   top left: a Menu button next to Roblox's own buttons (asks before putting your vehicle away)
--   top right: settings, the shop and your cash (with a "+£100" pill when you earn money)
-- It also shows the server's pop-up messages.

local GuiService = game:GetService("GuiService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Ui = require(script.Parent:WaitForChild("Ui"))
local Format = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Format"))

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local returnRemote = remotes:WaitForChild("ReturnToMenu") :: RemoteEvent
local notifyRemote = remotes:WaitForChild("Notify") :: RemoteEvent

local C = Ui.Colours
local player = Players.LocalPlayer

local gui = Ui.screen("Hud", 5)

-- A round dark button or pill in the top bar
local function topButton(text: string, size: UDim2, parent: Instance): TextButton
	local button = Ui.button(text, "clear", { Size = size, TextSize = 16, Parent = parent })
	button.BackgroundColor3 = C.Panel
	button.BackgroundTransparency = 0.2
	Ui.corner(button, 22)
	return button
end

-- Top left, just right of Roblox's buttons (GuiService tells us where their space ends)
local menuButton = topButton("      Menu", UDim2.fromOffset(104, 44), gui)
-- Three short lines for the "menu" icon (the font doesn't have one)
for i = 0, 2 do
	Ui.make("Frame", {
		Position = UDim2.fromOffset(18, 15 + i * 6),
		Size = UDim2.fromOffset(16, 2),
		BackgroundColor3 = C.Text,
		BorderSizePixel = 0,
		Parent = menuButton,
	})
end
local function placeMenuButton()
	local inset = GuiService.TopbarInset
	local height = math.max(inset.Height, 44)
	menuButton.Position = UDim2.fromOffset(inset.Min.X + 8, (height - 44) / 2 + (if inset.Height > 0 then 0 else 12))
end
placeMenuButton()
GuiService:GetPropertyChangedSignal("TopbarInset"):Connect(placeMenuButton)

-- Top right
local topRight = Ui.make("Frame", {
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -12, 0, 8),
	Size = UDim2.fromOffset(0, 44),
	AutomaticSize = Enum.AutomaticSize.X,
	BackgroundTransparency = 1,
	Parent = gui,
})
Ui.make("UIListLayout", {
	FillDirection = Enum.FillDirection.Horizontal,
	HorizontalAlignment = Enum.HorizontalAlignment.Right,
	Padding = UDim.new(0, 8),
	SortOrder = Enum.SortOrder.LayoutOrder,
	Parent = topRight,
})
local settingsButton = topButton("⚙", UDim2.fromOffset(44, 44), topRight)
settingsButton.LayoutOrder = 1
settingsButton.TextSize = 20
local shopButton = topButton("🛒", UDim2.fromOffset(44, 44), topRight)
shopButton.LayoutOrder = 2
local cashPill = topButton("", UDim2.fromOffset(0, 44), topRight)
cashPill.LayoutOrder = 3
cashPill.AutomaticSize = Enum.AutomaticSize.X
cashPill.Visible = false -- hidden until their data has loaded
Ui.padding(cashPill, 16, 0)

-- Pop-up windows ------------------------------------------------------------------------------

local function dialog(title: string, width: number, height: number): (Frame, () -> ())
	local backdrop = Ui.make("TextButton", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.5,
		AutoButtonColor = false,
		Text = "",
		Visible = false,
		ZIndex = 10,
		Parent = gui,
	})
	local window = Ui.panel({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(width, height),
		ZIndex = 11,
		Parent = backdrop,
	})
	window.BackgroundTransparency = 0.04
	Ui.padding(window, 22, 18)
	local close = Ui.make("TextButton", {
		Size = UDim2.fromOffset(24, 24),
		BackgroundTransparency = 1,
		FontFace = Ui.font(Enum.FontWeight.SemiBold),
		TextSize = 18,
		TextColor3 = C.Text,
		Text = "×",
		ZIndex = 12,
		Parent = window,
	})
	Ui.label(title, 20, Enum.FontWeight.SemiBold, {
		Position = UDim2.fromOffset(34, 0),
		Size = UDim2.new(1, -34, 0, 24),
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 12,
		Parent = window,
	})
	local function hide()
		backdrop.Visible = false
	end
	close.Activated:Connect(hide)
	return window, function()
		backdrop.Visible = true
	end
end

-- "Return to the menu?"
local confirmBackdrop = Ui.make("Frame", {
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = Color3.new(0, 0, 0),
	BackgroundTransparency = 0.55,
	Visible = false,
	ZIndex = 10,
	Parent = gui,
})
local confirm = Ui.panel({
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(360, 150),
	ZIndex = 11,
	Parent = confirmBackdrop,
})
confirm.BackgroundTransparency = 0.04
Ui.padding(confirm, 20, 18)
Ui.label("Return to the menu?", 18, Enum.FontWeight.SemiBold, { Size = UDim2.new(1, 0, 0, 22), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 12, Parent = confirm })
Ui.label("Your vehicle will be put away. You can get it out again from the menu.", 13, Enum.FontWeight.Regular, {
	Position = UDim2.fromOffset(0, 28),
	Size = UDim2.new(1, 0, 0, 34),
	TextWrapped = true,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextYAlignment = Enum.TextYAlignment.Top,
	TextColor3 = C.Muted,
	ZIndex = 12,
	Parent = confirm,
})
local confirmButtons = Ui.make("Frame", { AnchorPoint = Vector2.new(1, 1), Position = UDim2.fromScale(1, 1), Size = UDim2.fromOffset(230, 38), BackgroundTransparency = 1, ZIndex = 12, Parent = confirm })
local stayButton = Ui.button("Stay", "dark", { Size = UDim2.new(0.38, -5, 1, 0), ZIndex = 12, Parent = confirmButtons })
local leaveButton = Ui.button("Return to menu", "light", { Position = UDim2.new(0.38, 5, 0, 0), Size = UDim2.new(0.62, -5, 1, 0), ZIndex = 12, Parent = confirmButtons })

menuButton.Activated:Connect(function()
	confirmBackdrop.Visible = true
end)
stayButton.Activated:Connect(function()
	confirmBackdrop.Visible = false
end)
leaveButton.Activated:Connect(function()
	confirmBackdrop.Visible = false
	returnRemote:FireServer()
	Ui.requestMenu()
end)

-- Settings
local settingsWindow, showSettings = dialog("Settings", 420, 260)
local settingRows = Ui.make("Frame", { Position = UDim2.fromOffset(0, 40), Size = UDim2.new(1, 0, 1, -40), BackgroundTransparency = 1, ZIndex = 12, Parent = settingsWindow })
Ui.make("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder, Parent = settingRows })

local function toggleRow(label: string, setting: string, order: number)
	local row = Ui.make("TextButton", {
		Size = UDim2.new(1, 0, 0, 46),
		BackgroundColor3 = C.Raised,
		BackgroundTransparency = 0.3,
		AutoButtonColor = false,
		Text = "",
		LayoutOrder = order,
		ZIndex = 12,
		Parent = settingRows,
	})
	Ui.corner(row, 10)
	Ui.label(label, 14, Enum.FontWeight.Medium, { Position = UDim2.fromOffset(14, 0), Size = UDim2.new(1, -80, 1, 0), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 13, Parent = row })
	local track = Ui.make("Frame", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -14, 0.5, 0), Size = UDim2.fromOffset(40, 22), BorderSizePixel = 0, ZIndex = 13, Parent = row })
	Ui.corner(track, 11)
	local knob = Ui.make("Frame", { AnchorPoint = Vector2.new(0, 0.5), Size = UDim2.fromOffset(18, 18), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, ZIndex = 14, Parent = track })
	Ui.corner(knob, 9)
	local function draw()
		local on = (Ui.settings :: any)[setting] == true
		track.BackgroundColor3 = if on then C.Green else Color3.fromRGB(70, 74, 84)
		knob.Position = if on then UDim2.new(1, -20, 0.5, 0) else UDim2.new(0, 2, 0.5, 0)
	end
	draw()
	row.Activated:Connect(function()
		Ui.setSetting(setting, not (Ui.settings :: any)[setting])
		draw()
	end)
end
toggleRow("Shadows", "Shadows", 1)
toggleRow("Show driving controls", "Controls", 2)
toggleRow("Turn the minimap with your car", "TurnMap", 3)

Ui.SettingChanged:Connect(function(name, value)
	if name == "Shadows" then
		Lighting.GlobalShadows = value -- only changes it on this device
	end
end)
settingsButton.Activated:Connect(showSettings)

-- The shop isn't open yet (roadmap step 13), but the button shows what's coming
local shopWindow, showShop = dialog("Shop", 420, 210)
Ui.label("Cash packs, game passes and redeem codes are coming soon.\n\nFor now, earn money by playing: everyone gets paid every few minutes.", 14, Enum.FontWeight.Regular, {
	Position = UDim2.fromOffset(0, 44),
	Size = UDim2.new(1, 0, 1, -44),
	TextWrapped = true,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextYAlignment = Enum.TextYAlignment.Top,
	TextColor3 = C.Muted,
	ZIndex = 12,
	Parent = shopWindow,
})
shopButton.Activated:Connect(showShop)
cashPill.Activated:Connect(showShop)

-- Cash -------------------------------------------------------------------------------------------

local function showGain(amount: number)
	local pill = Ui.label("+" .. Format.money(amount), 13, Enum.FontWeight.SemiBold, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -16, 0, 58),
		Size = UDim2.fromOffset(0, 24),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 0,
		BackgroundColor3 = Color3.fromRGB(55, 150, 85),
		Parent = gui,
	})
	pill.BackgroundTransparency = 0
	Ui.corner(pill, 12)
	Ui.padding(pill, 10, 0)
	local tween = TweenService:Create(pill, TweenInfo.new(1.6, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		Position = pill.Position + UDim2.fromOffset(0, 18),
		TextTransparency = 1,
		BackgroundTransparency = 1,
	})
	tween.Completed:Once(function()
		pill:Destroy()
	end)
	task.delay(1, function()
		tween:Play()
	end)
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
	cashPill.Text = "💷  " .. Format.money(cash)
	cashPill.Visible = true
end
player:GetAttributeChangedSignal("Cash"):Connect(onCashChanged)
onCashChanged()

-- Hide the HUD while the menu is open
Ui.MenuChanged:Connect(function(open)
	gui.Enabled = not open
	if open then
		confirmBackdrop.Visible = false
	end
end)
gui.Enabled = not Ui.menuOpen

notifyRemote.OnClientEvent:Connect(function(title, body, colour)
	if typeof(title) == "string" then
		Ui.toast(title, if typeof(body) == "string" then body else nil, Ui.colourNamed(if typeof(colour) == "string" then colour else nil))
	end
end)
