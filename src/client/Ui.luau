-- The shared look for every menu and the HUD: dark see-through panels, rounded corners and Montserrat text,
-- plus helpers the other client scripts use. Change a colour here and it changes everywhere.
-- It also holds what the client scripts need to share: whether the menu is open, the settings,
-- and the pop-up messages ("toasts") at the top of the screen.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local Ui = {}

Ui.Colours = {
	Panel = Color3.fromRGB(16, 18, 23),
	Raised = Color3.fromRGB(34, 37, 46),
	Text = Color3.new(1, 1, 1),
	Muted = Color3.fromRGB(160, 166, 178),
	Green = Color3.fromRGB(95, 210, 125),
	Red = Color3.fromRGB(235, 90, 80),
	Yellow = Color3.fromRGB(245, 195, 50),
	Blue = Color3.fromRGB(90, 140, 230),
	Walk = Color3.fromRGB(70, 195, 155),
}
Ui.PanelTransparency = 0.12

local MONTSERRAT = "rbxasset://fonts/families/Montserrat.json"

function Ui.font(weight: Enum.FontWeight?): Font
	return Font.new(MONTSERRAT, weight or Enum.FontWeight.Medium)
end

-- Makes an Instance and sets its properties in one go, e.g. Ui.make("Frame", { Size = ..., Parent = gui })
function Ui.make(className: string, props: { [string]: any }?, children: { Instance }?): any
	local object: any = Instance.new(className :: any)
	local parent = nil
	if props then
		for key, value in props do
			if key == "Parent" then
				parent = value
			else
				object[key] = value
			end
		end
	end
	if children then
		for _, child in children do
			child.Parent = object
		end
	end
	if parent then
		object.Parent = parent
	end
	return object
end

function Ui.corner(parent: Instance, radius: number?)
	Ui.make("UICorner", { CornerRadius = UDim.new(0, radius or 14), Parent = parent })
end

function Ui.outline(parent: Instance, transparency: number?, colour: Color3?)
	Ui.make("UIStroke", {
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Color = colour or Color3.new(1, 1, 1),
		Transparency = transparency or 0.9,
		Thickness = 1,
		Parent = parent,
	})
end

function Ui.padding(parent: Instance, x: number, y: number?)
	Ui.make("UIPadding", {
		PaddingLeft = UDim.new(0, x),
		PaddingRight = UDim.new(0, x),
		PaddingTop = UDim.new(0, y or x),
		PaddingBottom = UDim.new(0, y or x),
		Parent = parent,
	})
end

-- A full-screen ScreenGui. Higher `order` draws on top.
function Ui.screen(name: string, order: number): ScreenGui
	return Ui.make("ScreenGui", {
		Name = name,
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = order,
		Parent = Players.LocalPlayer:WaitForChild("PlayerGui"),
	})
end

-- The dark rounded panel everything sits on
function Ui.panel(props: { [string]: any }): Frame
	local frame = Ui.make("Frame", props)
	frame.BackgroundColor3 = props.BackgroundColor3 or Ui.Colours.Panel
	frame.BackgroundTransparency = props.BackgroundTransparency or Ui.PanelTransparency
	frame.BorderSizePixel = 0
	Ui.corner(frame, 14)
	Ui.outline(frame)
	return frame
end

function Ui.label(text: string, size: number, weight: Enum.FontWeight?, props: { [string]: any }?): TextLabel
	local label = Ui.make("TextLabel", props)
	label.BackgroundTransparency = 1
	label.FontFace = Ui.font(weight)
	label.TextSize = size
	label.TextColor3 = if props and props.TextColor3 then props.TextColor3 else Ui.Colours.Text
	label.Text = text
	return label
end

-- A rounded button. `style` is "light" (white, for the main action), "dark" or "clear".
function Ui.button(text: string, style: string, props: { [string]: any }?): TextButton
	local button = Ui.make("TextButton", props)
	button.AutoButtonColor = false
	button.BorderSizePixel = 0
	button.FontFace = Ui.font(Enum.FontWeight.SemiBold)
	button.TextSize = if props and props.TextSize then props.TextSize else 16
	button.Text = text
	local normal, hover
	if style == "light" then
		button.TextColor3 = Color3.fromRGB(15, 15, 18)
		normal, hover = Color3.fromRGB(245, 245, 247), Color3.fromRGB(215, 215, 220)
		button.BackgroundTransparency = 0
	else
		button.TextColor3 = Ui.Colours.Text
		normal, hover = Ui.Colours.Raised, Color3.fromRGB(52, 56, 68)
		button.BackgroundTransparency = if style == "clear" then 0.35 else 0.05
		Ui.outline(button)
	end
	button.BackgroundColor3 = normal
	Ui.corner(button, 12)
	button.MouseEnter:Connect(function()
		button.BackgroundColor3 = hover
	end)
	button.MouseLeave:Connect(function()
		button.BackgroundColor3 = normal
	end)
	return button
end

-- Shared state ------------------------------------------------------------------------------

Ui.menuOpen = false
local menuChanged = Instance.new("BindableEvent")
Ui.MenuChanged = menuChanged.Event -- fires with true/false when the menu opens or closes

function Ui.setMenuOpen(open: boolean)
	Ui.menuOpen = open
	menuChanged:Fire(open)
end

-- The HUD's Menu button asks for the menu through this, and the Menu script listens
local menuRequested = Instance.new("BindableEvent")
Ui.MenuRequested = menuRequested.Event
function Ui.requestMenu()
	menuRequested:Fire()
end

Ui.settings = {
	Shadows = true,
	Controls = true,
	TurnMap = true,
}
local settingChanged = Instance.new("BindableEvent")
Ui.SettingChanged = settingChanged.Event -- fires with (name, value)

function Ui.setSetting(name: string, value: boolean)
	(Ui.settings :: any)[name] = value
	settingChanged:Fire(name, value)
end

-- Toasts: pop-up messages at the top of the screen ---------------------------------------------

local toastList: Frame? = nil

local function getToastList(): Frame
	if toastList then
		return toastList
	end
	local gui = Ui.screen("Toasts", 50)
	local list = Ui.make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 16),
		Size = UDim2.fromOffset(380, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Parent = gui,
	})
	Ui.make("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder, Parent = list })
	toastList = list
	return list
end

local toastCount = 0

-- Ui.toast("Collisions on", "Other players can now hit you", Ui.Colours.Yellow)
function Ui.toast(title: string, body: string?, colour: Color3?, seconds: number?)
	local list = getToastList()
	local duration = seconds or 4
	toastCount += 1

	local card = Ui.panel({ Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = toastCount, Parent = list })
	Ui.padding(card, 14, 12)
	Ui.make("Frame", {
		Size = UDim2.fromOffset(8, 8),
		Position = UDim2.fromOffset(0, 5),
		BackgroundColor3 = colour or Ui.Colours.Yellow,
		Parent = card,
	}, { Ui.make("UICorner", { CornerRadius = UDim.new(1, 0) }) })
	Ui.label(title, 15, Enum.FontWeight.SemiBold, {
		Position = UDim2.fromOffset(18, 0),
		Size = UDim2.new(1, -18, 0, 18),
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = card,
	})
	if body then
		Ui.label(body, 13, Enum.FontWeight.Regular, {
			Position = UDim2.fromOffset(18, 22),
			Size = UDim2.new(1, -18, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = Ui.Colours.Muted,
			Parent = card,
		})
	end
	-- A bar along the bottom that shrinks until the toast goes
	local bar = Ui.make("Frame", {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 0, 1, 8),
		Size = UDim2.new(1, 0, 0, 3),
		BackgroundColor3 = colour or Ui.Colours.Yellow,
		BackgroundTransparency = 0.3,
		BorderSizePixel = 0,
		Parent = card,
	})
	TweenService:Create(bar, TweenInfo.new(duration, Enum.EasingStyle.Linear), { Size = UDim2.new(0, 0, 0, 3) }):Play()
	task.delay(duration, function()
		card:Destroy()
	end)
end

-- Colour names the server can send with a toast
function Ui.colourNamed(name: string?): Color3
	if name and (Ui.Colours :: any)[name] then
		return (Ui.Colours :: any)[name]
	end
	return Ui.Colours.Yellow
end

return Ui
