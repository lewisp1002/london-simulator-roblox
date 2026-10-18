-- The menus you see when you join or press Menu: the main menu (Drive / Spawn / Close), the team picker,
-- the vehicle picker (filmed live at your team's depot) and customising your paint.
-- Laid out like Birmingham Vehicle Simulator (see docs/BVS-NOTES.md), with our own London look and names.

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SocialService = game:GetService("SocialService")
local StarterGui = game:GetService("StarterGui")
local Teams = game:GetService("Teams")
local Workspace = game:GetService("Workspace")

local Ui = require(script.Parent:WaitForChild("Ui"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Format = require(Shared:WaitForChild("Format"))
local Vehicles = require(Shared:WaitForChild("Vehicles"))

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local chooseTeamRemote = remotes:WaitForChild("ChooseTeam") :: RemoteEvent
local buyRemote = remotes:WaitForChild("BuyVehicle") :: RemoteFunction
local setPaintRemote = remotes:WaitForChild("SetPaint") :: RemoteEvent
local spawnRemote = remotes:WaitForChild("SpawnVehicle") :: RemoteEvent
local spawnOnFootRemote = remotes:WaitForChild("SpawnOnFoot") :: RemoteEvent
local vehicleModels = ReplicatedStorage:WaitForChild("VehicleModels")
local mapInfo = ReplicatedStorage:WaitForChild("MapInfo", 15)

type Vehicle = Vehicles.Vehicle

local C = Ui.Colours
local player = Players.LocalPlayer
local camera = Workspace.CurrentCamera

local gui = Ui.screen("Menu", 10)
gui.Enabled = false

-- Blurs the world behind the main menu and team picker (only on this device)
local blur = Instance.new("BlurEffect")
blur.Name = "MenuBlur"
blur.Size = 0
blur.Parent = Lighting

local shade = Ui.make("Frame", {
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = Color3.new(0, 0, 0),
	BackgroundTransparency = 0.45,
	BorderSizePixel = 0,
	Parent = gui,
})

-- Player controls, switched off while the menu is open
local controls: any = nil
task.spawn(function()
	local ok, playerModule = pcall(function(): any
		local module = player:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule")
		return (require :: any)(module) -- Roblox's own module, so the type checker can't see inside it
	end)
	if ok and playerModule then
		controls = playerModule:GetControls()
		if Ui.menuOpen then
			controls:Disable()
		end
	end
end)

-- The menu flies the camera to fixed shots
local cameraTarget: CFrame? = nil
RunService:BindToRenderStep("MenuCamera", Enum.RenderPriority.Camera.Value + 1, function()
	if cameraTarget then
		camera.CameraType = Enum.CameraType.Scriptable
		camera.CFrame = camera.CFrame:Lerp(cameraTarget, 0.12)
	end
end)

local function mapSetting(name: string): any
	return if mapInfo then mapInfo:GetAttribute(name) else nil
end

-- Ask the server to send this player the parts around a spot, in case the place streams the map in
local function streamAround(position: Vector3)
	task.spawn(function()
		pcall(function()
			player:RequestStreamAroundAsync(position)
		end)
	end)
end

local function flyTo(shot: CFrame, snap: boolean?)
	streamAround(shot.Position)
	cameraTarget = shot
	if snap then
		camera.CameraType = Enum.CameraType.Scriptable
		camera.CFrame = shot
	end
end

local function menuShot(): CFrame
	local shot = mapSetting("MenuCamera")
	return if typeof(shot) == "CFrame" then shot else camera.CFrame
end

local function isOwned(vehicle: Vehicle): boolean
	return vehicle.price == 0 or player:GetAttribute("Owned_" .. vehicle.id) == true
end

-- nil means the vehicle keeps its own colours
local function paintOf(vehicle: Vehicle): Color3?
	local picked = player:GetAttribute("Paint_" .. vehicle.id)
	return Vehicles.paintColour(vehicle, if typeof(picked) == "number" then picked else nil)
end

local function cash(): number
	local value = player:GetAttribute("Cash")
	return if typeof(value) == "number" then value else 0
end

-- Repaints a vehicle's body panels, or puts its original colours back when `colour` is nil
local function recolour(model: Instance, colour: Color3?)
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") and descendant:GetAttribute("Paint") then
			local original = descendant:GetAttribute("BaseColour")
			if colour then
				descendant.Color = colour
			elseif typeof(original) == "Color3" then
				descendant.Color = original
			end
		end
	end
end

-- A vehicle in a little 3D window, seen from the front left like a showroom photo
local function showVehicle(viewport: ViewportFrame, vehicleId: string, paint: Color3?)
	viewport:ClearAllChildren()
	local source = vehicleModels:FindFirstChild(vehicleId)
	if not source then
		return
	end
	local model = source:Clone() :: Model
	if paint then
		recolour(model, paint)
	end
	model:PivotTo(CFrame.new())
	model.Parent = viewport
	local size = model:GetExtentsSize()
	local viewCamera = Instance.new("Camera")
	viewCamera.FieldOfView = 30
	viewCamera.Parent = viewport
	viewport.CurrentCamera = viewCamera
	local focus = Vector3.new(0, size.Y * 0.42, 0)
	local direction = Vector3.new(-0.8, 0.42, -1).Unit
	local distance = size.Z * 1.55 + 6
	viewCamera.CFrame = CFrame.lookAt(focus + direction * distance, focus)
end

local function viewport(props: { [string]: any }): ViewportFrame
	local frame = Ui.make("ViewportFrame", props)
	frame.BackgroundColor3 = props.BackgroundColor3 or Color3.fromRGB(8, 9, 12)
	frame.Ambient = Color3.fromRGB(165, 165, 172)
	frame.LightColor = Color3.new(1, 1, 1)
	frame.LightDirection = Vector3.new(-1, -1.2, -0.4)
	return frame
end

local function backButton(parent: Instance, text: string, onClick: () -> ())
	local button = Ui.button("‹  " .. text, "dark", {
		Position = UDim2.fromOffset(24, 72),
		Size = UDim2.fromOffset(0, 40),
		AutomaticSize = Enum.AutomaticSize.X,
		TextSize = 15,
		Parent = parent,
	})
	Ui.padding(button, 16, 0)
	button.Activated:Connect(onClick)
end

local function cashPill(parent: Instance): TextLabel
	local pill = Ui.panel({
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -24, 0, 72),
		Size = UDim2.fromOffset(0, 40),
		AutomaticSize = Enum.AutomaticSize.X,
		Parent = parent,
	})
	Ui.padding(pill, 16, 0)
	return Ui.label("", 16, Enum.FontWeight.SemiBold, { Size = UDim2.fromScale(0, 1), AutomaticSize = Enum.AutomaticSize.X, Parent = pill })
end

-- Screens ---------------------------------------------------------------------------------

local screens: { [string]: Frame } = {}
local function screen(name: string): Frame
	local frame = Ui.make("Frame", { Name = name, Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false, Parent = gui })
	screens[name] = frame
	return frame
end

local mainScreen = screen("Main")
local teamScreen = screen("Teams")
local pickerScreen = screen("Picker")

local openMenu: () -> ()
local closeMenu: () -> ()
local showTeams: () -> ()
local showPicker: (team: string) -> ()

local function showScreen(name: string)
	for screenName, frame in screens do
		frame.Visible = screenName == name
	end
	local blurred = name ~= "Picker"
	shade.Visible = blurred
	blur.Size = if blurred then 18 else 0
end

-- Main menu: logo, three big cards and two wide buttons ------------------------------------

local logo = Ui.make("Frame", {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0.15, 0),
	Size = UDim2.fromOffset(560, 116),
	BackgroundTransparency = 1,
	Parent = mainScreen,
})
for i, stripe in { { icon = "🚶", colour = C.Walk }, { icon = "🚗", colour = C.Blue }, { icon = "🚌", colour = C.Red } } do
	local bar = Ui.make("Frame", {
		Position = UDim2.fromOffset(18 - (i - 1) * 9, (i - 1) * 39),
		Size = UDim2.fromOffset(150, 34),
		BackgroundColor3 = stripe.colour,
		BorderSizePixel = 0,
		Parent = logo,
	})
	Ui.corner(bar, 5)
	Ui.label(stripe.icon, 20, nil, { Size = UDim2.fromScale(1, 1), Parent = bar })
end
Ui.label("LONDON", 76, Enum.FontWeight.Bold, {
	Position = UDim2.fromOffset(186, -8),
	Size = UDim2.fromOffset(380, 80),
	TextXAlignment = Enum.TextXAlignment.Left,
	Parent = logo,
})
Ui.label("S I M U L A T O R", 27, Enum.FontWeight.Medium, {
	Position = UDim2.fromOffset(190, 76),
	Size = UDim2.fromOffset(380, 34),
	TextXAlignment = Enum.TextXAlignment.Left,
	Parent = logo,
})

local cardRow = Ui.make("Frame", {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0.44, 0),
	Size = UDim2.fromOffset(150 * 3 + 20 * 2, 180),
	BackgroundTransparency = 1,
	Parent = mainScreen,
})
Ui.make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 20), SortOrder = Enum.SortOrder.LayoutOrder, Parent = cardRow })

local function bigCard(icon: string, text: string, colour: Color3, order: number, onClick: () -> ())
	local card = Ui.make("TextButton", {
		Size = UDim2.fromOffset(150, 180),
		BackgroundColor3 = C.Panel,
		BackgroundTransparency = 0.15,
		AutoButtonColor = false,
		Text = "",
		LayoutOrder = order,
		Parent = cardRow,
	})
	Ui.corner(card, 14)
	Ui.outline(card)
	Ui.label(icon, 40, nil, { Position = UDim2.fromOffset(0, 36), Size = UDim2.new(1, 0, 0, 50), TextColor3 = colour, Parent = card })
	Ui.label(text, 20, Enum.FontWeight.SemiBold, { Position = UDim2.fromOffset(0, 104), Size = UDim2.new(1, 0, 0, 26), Parent = card })
	local underline = Ui.make("Frame", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -12),
		Size = UDim2.fromOffset(56, 4),
		BackgroundColor3 = colour,
		BorderSizePixel = 0,
		Parent = card,
	})
	Ui.corner(underline, 2)
	card.MouseEnter:Connect(function()
		card.BackgroundColor3 = C.Raised
	end)
	card.MouseLeave:Connect(function()
		card.BackgroundColor3 = C.Panel
	end)
	card.Activated:Connect(onClick)
end

bigCard("🚗", "Drive", C.Blue, 1, function()
	showTeams()
end)
bigCard("🚶", "Spawn", C.Walk, 2, function()
	spawnOnFootRemote:FireServer()
	closeMenu()
end)
bigCard("×", "Close", C.Red, 3, function()
	closeMenu()
end)

local wideRow = Ui.make("Frame", {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0.44, 200),
	Size = UDim2.fromOffset(490, 50),
	BackgroundTransparency = 1,
	Parent = mainScreen,
})
local avatarButton = Ui.button("👤  Change avatar", "dark", { Size = UDim2.new(0.5, -8, 1, 0), Parent = wideRow })
avatarButton.Activated:Connect(function()
	Ui.toast("Coming soon", "Changing your avatar in the game is on the way. For now, change it on the Roblox website.", C.Blue)
end)
local inviteButton = Ui.button("➕  Invite friends", "dark", { Position = UDim2.new(0.5, 8, 0, 0), Size = UDim2.new(0.5, -8, 1, 0), Parent = wideRow })
inviteButton.Activated:Connect(function()
	local ok = pcall(function()
		SocialService:PromptGameInvite(player)
	end)
	if not ok then
		Ui.toast("Invites don't work here", "Inviting friends works once the game is published and you're playing it on Roblox.", C.Red)
	end
end)

-- Team picker -------------------------------------------------------------------------------

backButton(teamScreen, "Back", function()
	showScreen("Main")
end)
Ui.label("Choose your team", 46, Enum.FontWeight.Regular, {
	Position = UDim2.new(0.12, 0, 0, 120),
	Size = UDim2.fromOffset(700, 56),
	TextXAlignment = Enum.TextXAlignment.Left,
	Parent = teamScreen,
})
Ui.label("Pick a service and hit the road", 20, Enum.FontWeight.Regular, {
	Position = UDim2.new(0.12, 0, 0, 178),
	Size = UDim2.fromOffset(700, 28),
	TextXAlignment = Enum.TextXAlignment.Left,
	TextColor3 = C.Muted,
	Parent = teamScreen,
})

local teamRow = Ui.make("Frame", {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 236),
	Size = UDim2.new(0.76, 0, 0, 440),
	BackgroundTransparency = 1,
	Parent = teamScreen,
})
Ui.make("UIListLayout", {
	FillDirection = Enum.FillDirection.Horizontal,
	Padding = UDim.new(0, 24),
	HorizontalAlignment = Enum.HorizontalAlignment.Center,
	SortOrder = Enum.SortOrder.LayoutOrder,
	Parent = teamRow,
})

local memberStrips: { [string]: { count: TextLabel, faces: Frame } } = {}
local headshots: { [number]: string } = {}

for order, info in Config.Teams do
	local column = Ui.make("Frame", { Size = UDim2.new(1 / 3, -16, 1, 0), BackgroundTransparency = 1, LayoutOrder = order, Parent = teamRow })
	local card = Ui.make("TextButton", {
		Size = UDim2.new(1, 0, 0, 330),
		BackgroundColor3 = Color3.fromRGB(10, 11, 14),
		AutoButtonColor = false,
		Text = "",
		Parent = column,
	})
	Ui.corner(card, 16)
	Ui.outline(card)
	local window = viewport({ Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(14, 15, 19), Parent = card })
	Ui.corner(window, 16)
	showVehicle(window, info.showcase, nil)
	-- Fade to black at the bottom so the words are easy to read
	local fade = Ui.make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0), BorderSizePixel = 0, Parent = card })
	Ui.corner(fade, 16)
	Ui.make("UIGradient", {
		Rotation = 90,
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.55, 1), NumberSequenceKeypoint.new(1, 0.1) }),
		Parent = fade,
	})
	Ui.label(info.icon .. "  " .. info.name, 30, Enum.FontWeight.SemiBold, {
		Position = UDim2.new(0, 20, 1, -86),
		Size = UDim2.new(1, -40, 0, 36),
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = card,
	})
	Ui.label(info.description, 14, Enum.FontWeight.Regular, {
		Position = UDim2.new(0, 20, 1, -46),
		Size = UDim2.new(1, -40, 0, 34),
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextColor3 = Color3.fromRGB(215, 218, 225),
		Parent = card,
	})
	local accent = Ui.make("Frame", { Size = UDim2.new(1, 0, 0, 4), BackgroundColor3 = info.colour, BorderSizePixel = 0, Parent = card })
	Ui.corner(accent, 2)
	card.MouseEnter:Connect(function()
		accent.Size = UDim2.new(1, 0, 0, 6)
	end)
	card.MouseLeave:Connect(function()
		accent.Size = UDim2.new(1, 0, 0, 4)
	end)
	card.Activated:Connect(function()
		chooseTeamRemote:FireServer(info.name)
		showPicker(info.name)
	end)

	local members = Ui.panel({ Position = UDim2.fromOffset(0, 342), Size = UDim2.new(1, 0, 0, 88), Parent = column })
	Ui.padding(members, 16, 12)
	Ui.label("Current members", 14, Enum.FontWeight.Medium, { Size = UDim2.new(1, 0, 0, 18), TextXAlignment = Enum.TextXAlignment.Left, Parent = members })
	local count = Ui.label("0 players", 13, Enum.FontWeight.Regular, { Size = UDim2.new(1, 0, 0, 18), TextXAlignment = Enum.TextXAlignment.Right, TextColor3 = C.Muted, Parent = members })
	local faces = Ui.make("Frame", { Position = UDim2.fromOffset(0, 28), Size = UDim2.new(1, 0, 0, 36), BackgroundTransparency = 1, Parent = members })
	Ui.make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder, Parent = faces })
	memberStrips[info.name] = { count = count, faces = faces }
end

local function headshot(userId: number): string
	if headshots[userId] then
		return headshots[userId]
	end
	local ok, image = pcall(function()
		return Players:GetUserThumbnailAsync(userId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size48x48)
	end)
	headshots[userId] = if ok then image else ""
	return headshots[userId]
end

local function refreshMembers()
	for teamName, strip in memberStrips do
		local team = Teams:FindFirstChild(teamName) :: Team?
		local list: { Player } = if team then team:GetPlayers() else {}
		strip.count.Text = `{#list} {if #list == 1 then "player" else "players"}`
		for _, child in strip.faces:GetChildren() do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		for index, member in list do
			if index > 6 then
				local more = Ui.label(`+{#list - 6}`, 13, Enum.FontWeight.SemiBold, { Size = UDim2.fromOffset(36, 36), BackgroundTransparency = 0, BackgroundColor3 = C.Raised, LayoutOrder = 7, Parent = strip.faces })
				more.BackgroundTransparency = 0
				Ui.corner(more, 18)
				break
			end
			local face = Ui.make("ImageLabel", { Size = UDim2.fromOffset(36, 36), BackgroundColor3 = C.Raised, LayoutOrder = index, Parent = strip.faces })
			Ui.corner(face, 18)
			task.spawn(function()
				face.Image = headshot(member.UserId)
			end)
		end
	end
end

showTeams = function()
	showScreen("Teams")
	flyTo(menuShot())
	refreshMembers()
end

-- Vehicle picker ---------------------------------------------------------------------------

local pickerTeam = "Car"
local pickerFilter = "All"
local selectedId: string? = nil
local previewModel: Model? = nil
local customising = false

backButton(pickerScreen, "Back to teams", function()
	showTeams()
end)
local pickerCash = cashPill(pickerScreen)

-- Darken the bottom of the screen behind the picker
local bottomFade = Ui.make("Frame", {
	AnchorPoint = Vector2.new(0, 1),
	Position = UDim2.fromScale(0, 1),
	Size = UDim2.new(1, 0, 0, 340),
	BackgroundColor3 = Color3.new(0, 0, 0),
	BorderSizePixel = 0,
	ZIndex = 0,
	Parent = pickerScreen,
})
Ui.make("UIGradient", {
	Rotation = 90,
	Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0.25) }),
	Parent = bottomFade,
})

local nameLabel = Ui.label("", 40, Enum.FontWeight.Bold, {
	AnchorPoint = Vector2.new(0, 1),
	Position = UDim2.new(0, 28, 1, -236),
	Size = UDim2.new(0.5, 0, 0, 48),
	TextXAlignment = Enum.TextXAlignment.Left,
	Parent = pickerScreen,
})
local statusLabel = Ui.label("", 15, Enum.FontWeight.Medium, {
	AnchorPoint = Vector2.new(0, 1),
	Position = UDim2.new(0, 30, 1, -212),
	Size = UDim2.new(0.5, 0, 0, 20),
	TextXAlignment = Enum.TextXAlignment.Left,
	RichText = true,
	Parent = pickerScreen,
})

local actionRow = Ui.make("Frame", {
	AnchorPoint = Vector2.new(1, 1),
	Position = UDim2.new(1, -28, 1, -214),
	Size = UDim2.fromOffset(360, 48),
	BackgroundTransparency = 1,
	Parent = pickerScreen,
})
local customiseButton = Ui.button("Customise", "dark", { Size = UDim2.new(0.42, -6, 1, 0), Parent = actionRow })
local mainButton = Ui.button("Spawn", "light", { Position = UDim2.new(0.42, 6, 0, 0), Size = UDim2.new(0.58, -6, 1, 0), Parent = actionRow })

-- The list of vehicles along the bottom, with tabs above it
local listArea = Ui.make("Frame", {
	AnchorPoint = Vector2.new(0, 1),
	Position = UDim2.new(0, 0, 1, -16),
	Size = UDim2.new(1, 0, 0, 186),
	BackgroundTransparency = 1,
	Parent = pickerScreen,
})
local tabRow = Ui.make("Frame", { Position = UDim2.fromOffset(28, 0), Size = UDim2.new(1, -56, 0, 26), BackgroundTransparency = 1, Parent = listArea })
Ui.make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 22), SortOrder = Enum.SortOrder.LayoutOrder, Parent = tabRow })
local ownedCount = Ui.label("", 13, Enum.FontWeight.Regular, {
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -28, 0, 2),
	Size = UDim2.fromOffset(240, 20),
	TextXAlignment = Enum.TextXAlignment.Right,
	TextColor3 = C.Muted,
	RichText = true,
	Parent = listArea,
})
local carousel = Ui.make("ScrollingFrame", {
	Position = UDim2.fromOffset(0, 40),
	Size = UDim2.new(1, 0, 0, 146),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	ScrollingDirection = Enum.ScrollingDirection.X,
	AutomaticCanvasSize = Enum.AutomaticSize.X,
	CanvasSize = UDim2.new(),
	ScrollBarThickness = 4,
	Parent = listArea,
})
Ui.padding(carousel, 28, 6)
Ui.make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 12), SortOrder = Enum.SortOrder.LayoutOrder, Parent = carousel })

-- The customise sheet, which takes the list's place
local sheet = Ui.panel({
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -16),
	Size = UDim2.new(1, -56, 0, 186),
	Visible = false,
	Parent = pickerScreen,
})
Ui.padding(sheet, 20, 16)
Ui.label("Customise", 20, Enum.FontWeight.SemiBold, { Size = UDim2.fromOffset(300, 24), TextXAlignment = Enum.TextXAlignment.Left, Parent = sheet })
local sheetSubtitle = Ui.label("", 13, Enum.FontWeight.Regular, {
	Position = UDim2.fromOffset(0, 26),
	Size = UDim2.fromOffset(500, 18),
	TextXAlignment = Enum.TextXAlignment.Left,
	TextColor3 = C.Muted,
	Parent = sheet,
})
Ui.label("Body colour", 14, Enum.FontWeight.SemiBold, { Position = UDim2.fromOffset(0, 58), Size = UDim2.fromOffset(200, 18), TextXAlignment = Enum.TextXAlignment.Left, Parent = sheet })
local swatches = Ui.make("ScrollingFrame", {
	Position = UDim2.fromOffset(0, 86),
	Size = UDim2.new(1, 0, 0, 64),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	ScrollingDirection = Enum.ScrollingDirection.X,
	AutomaticCanvasSize = Enum.AutomaticSize.X,
	CanvasSize = UDim2.new(),
	ScrollBarThickness = 3,
	Parent = sheet,
})
Ui.padding(swatches, 4, 4)
Ui.make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder, Parent = swatches })
local fixedNote = Ui.label("This vehicle's livery can't be changed.", 14, Enum.FontWeight.Regular, {
	Position = UDim2.fromOffset(0, 96),
	Size = UDim2.fromOffset(500, 20),
	TextXAlignment = Enum.TextXAlignment.Left,
	TextColor3 = C.Muted,
	Visible = false,
	Parent = sheet,
})
local sheetButtons = Ui.make("Frame", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 0), Size = UDim2.fromOffset(330, 42), BackgroundTransparency = 1, Parent = sheet })
local resetButton = Ui.button("Reset", "dark", { Size = UDim2.new(0.4, -6, 1, 0), Parent = sheetButtons })
local doneButton = Ui.button("Back to vehicles", "light", { Position = UDim2.new(0.4, 6, 0, 0), Size = UDim2.new(0.6, -6, 1, 0), Parent = sheetButtons })

local refreshPicker: () -> ()

local function selectedVehicle(): Vehicle?
	return if selectedId then Vehicles.ById[selectedId] else nil
end

-- Puts the selected vehicle at the depot's display spot and points the camera at it
local function showPreview(vehicle: Vehicle)
	if previewModel then
		previewModel:Destroy()
		previewModel = nil
	end
	local source = vehicleModels:FindFirstChild(vehicle.id)
	if not source then
		return
	end
	local spot = mapSetting("Showroom_" .. pickerTeam)
	if typeof(spot) ~= "CFrame" then
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		spot = if root then root.CFrame * CFrame.new(0, -3, -20) else CFrame.new(0, 0.1, 0)
	end
	local model = source:Clone() :: Model
	recolour(model, paintOf(vehicle))
	model:PivotTo(spot)
	model.Parent = Workspace
	previewModel = model

	local size = model:GetExtentsSize()
	local length = math.max(size.Z, size.X)
	local focus = spot.Position + Vector3.new(0, size.Y * 0.38, 0)
	local offset = spot.LookVector * (length * 0.75 + 5) - spot.RightVector * (length * 0.62 + 4) + Vector3.new(0, size.Y * 0.35 + 2, 0)
	flyTo(CFrame.lookAt(focus + offset, focus - Vector3.new(0, size.Y * 0.25, 0)))
end

local function selectVehicle(vehicleId: string)
	selectedId = vehicleId
	local vehicle = Vehicles.ById[vehicleId]
	if vehicle then
		showPreview(vehicle)
	end
	refreshPicker()
end

local function vehicleCard(vehicle: Vehicle, order: number)
	local owned = isOwned(vehicle)
	local card = Ui.make("TextButton", {
		Size = UDim2.fromOffset(150, 132),
		BackgroundColor3 = C.Panel,
		BackgroundTransparency = 0.1,
		AutoButtonColor = false,
		Text = "",
		LayoutOrder = order,
		Parent = carousel,
	})
	Ui.corner(card, 12)
	if vehicle.id == selectedId then
		Ui.make("UIStroke", { ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Color = Color3.new(1, 1, 1), Thickness = 2, Parent = card })
	else
		Ui.outline(card)
	end
	local window = viewport({ Position = UDim2.fromOffset(6, 6), Size = UDim2.new(1, -12, 0, 88), Parent = card })
	Ui.corner(window, 9)
	showVehicle(window, vehicle.id, paintOf(vehicle))
	if owned then
		local badge = Ui.label("✓ Owned", 11, Enum.FontWeight.SemiBold, {
			Position = UDim2.fromOffset(12, 12),
			Size = UDim2.fromOffset(62, 20),
			BackgroundTransparency = 0,
			BackgroundColor3 = Color3.fromRGB(60, 160, 90),
			Parent = card,
		})
		badge.BackgroundTransparency = 0
		Ui.corner(badge, 6)
	else
		local price = Ui.label(Format.money(vehicle.price), 12, Enum.FontWeight.SemiBold, {
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -12, 0, 72),
			Size = UDim2.fromOffset(80, 18),
			TextXAlignment = Enum.TextXAlignment.Right,
			Parent = card,
		})
		price.TextStrokeTransparency = 0.5
	end
	Ui.label(vehicle.name .. (if vehicle.electric then " ⚡" else ""), 13, Enum.FontWeight.SemiBold, {
		Position = UDim2.fromOffset(10, 100),
		Size = UDim2.new(1, -20, 0, 22),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = card,
	})
	card.Activated:Connect(function()
		selectVehicle(vehicle.id)
	end)
end

local function tab(text: string, filter: string, count: number, order: number)
	local active = filter == pickerFilter
	local button = Ui.make("TextButton", {
		Size = UDim2.fromScale(0, 1),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 1,
		FontFace = Ui.font(if active then Enum.FontWeight.SemiBold else Enum.FontWeight.Regular),
		TextSize = 14,
		TextColor3 = if active then C.Text else C.Muted,
		RichText = true,
		Text = `{text}  <font color="#8c919c">{count}</font>`,
		LayoutOrder = order,
		Parent = tabRow,
	})
	if active then
		Ui.make("Frame", {
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.new(0, 0, 1, 2),
			Size = UDim2.new(1, 0, 0, 2),
			BackgroundColor3 = C.Text,
			BorderSizePixel = 0,
			Parent = button,
		})
	end
	button.Activated:Connect(function()
		pickerFilter = filter
		refreshPicker()
	end)
end

local function refreshSwatches(vehicle: Vehicle)
	for _, child in swatches:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	swatches.Visible = not vehicle.fixedPaint
	fixedNote.Visible = vehicle.fixedPaint == true
	resetButton.Visible = not vehicle.fixedPaint
	if vehicle.fixedPaint then
		return
	end
	local picked = player:GetAttribute("Paint_" .. vehicle.id)
	local current = if typeof(picked) == "number" then picked else vehicle.paint
	for index, paint in Vehicles.Paints do
		local swatch = Ui.make("TextButton", {
			Size = UDim2.fromOffset(48, 48),
			BackgroundColor3 = paint.colour,
			AutoButtonColor = false,
			Text = "",
			LayoutOrder = index,
			Parent = swatches,
		})
		Ui.corner(swatch, 10)
		Ui.make("UIStroke", {
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
			Color = Color3.new(1, 1, 1),
			Thickness = if index == current then 3 else 1,
			Transparency = if index == current then 0 else 0.8,
			Parent = swatch,
		})
		swatch.Activated:Connect(function()
			setPaintRemote:FireServer(vehicle.id, index)
			if previewModel then
				recolour(previewModel, paint.colour)
			end
		end)
	end
end

refreshPicker = function()
	pickerCash.Text = "💷  " .. Format.money(cash())
	local all = Vehicles.forTeam(pickerTeam)
	local ownedTotal = 0
	for _, vehicle in all do
		if isOwned(vehicle) then
			ownedTotal += 1
		end
	end

	for _, child in tabRow:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	tab("All", "All", #all, 1)
	tab("Owned", "Owned", ownedTotal, 2)
	tab("Not owned", "NotOwned", #all - ownedTotal, 3)
	ownedCount.Text = `Vehicles owned  <b><font color="#ffffff">{ownedTotal} / {#all}</font></b>`

	for _, child in carousel:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	for order, vehicle in all do
		local owned = isOwned(vehicle)
		if pickerFilter == "All" or (pickerFilter == "Owned" and owned) or (pickerFilter == "NotOwned" and not owned) then
			vehicleCard(vehicle, order)
		end
	end

	local vehicle = selectedVehicle()
	if not vehicle then
		return
	end
	local owned = isOwned(vehicle)
	nameLabel.Text = vehicle.name
	local details = {}
	table.insert(details, if owned then `<font color="#5fd27d">Owned</font>` else Format.money(vehicle.price))
	if vehicle.electric then
		table.insert(details, "⚡ Electric")
	end
	table.insert(details, `Top speed {math.floor(vehicle.topSpeed * Config.MphPerStudPerSecond + 0.5)} mph`)
	statusLabel.Text = table.concat(details, "   ·   ")
	mainButton.Text = if owned then "Spawn" else `Buy  ·  {Format.money(vehicle.price)}`
	customiseButton.TextTransparency = if owned then 0 else 0.6
	sheetSubtitle.Text = `{vehicle.name}  ·  Every pick saves straight away`
	if customising then
		refreshSwatches(vehicle)
	end
end

local function setCustomising(on: boolean)
	customising = on
	sheet.Visible = on
	listArea.Visible = not on
	actionRow.Visible = not on
	local vehicle = selectedVehicle()
	if on and vehicle then
		refreshSwatches(vehicle)
	end
end

customiseButton.Activated:Connect(function()
	local vehicle = selectedVehicle()
	if vehicle and isOwned(vehicle) then
		setCustomising(true)
	elseif vehicle then
		Ui.toast("Buy it first", `You can customise the {vehicle.name} once it's yours.`, C.Blue)
	end
end)
doneButton.Activated:Connect(function()
	setCustomising(false)
end)
resetButton.Activated:Connect(function()
	local vehicle = selectedVehicle()
	if vehicle then
		setPaintRemote:FireServer(vehicle.id, nil)
		if previewModel then
			recolour(previewModel, Vehicles.paintColour(vehicle, nil))
		end
	end
end)

local spawning = false
mainButton.Activated:Connect(function()
	local vehicle = selectedVehicle()
	if not vehicle or spawning then
		return
	end
	if not isOwned(vehicle) then
		local ok, message = buyRemote:InvokeServer(vehicle.id)
		Ui.toast(if ok then "Bought!" else "Can't buy that yet", message, if ok then C.Green else C.Red)
		refreshPicker()
		return
	end

	spawning = true
	mainButton.Text = "Spawning…"
	spawnRemote:FireServer(vehicle.id)
	-- Close the menu as soon as we're sitting in the new vehicle
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local started = os.clock()
	while os.clock() - started < 6 do
		local seat = humanoid and humanoid.SeatPart
		if seat and seat:IsA("VehicleSeat") then
			spawning = false
			closeMenu()
			return
		end
		task.wait(0.1)
	end
	spawning = false
	refreshPicker()
	Ui.toast("Couldn't get your vehicle out", "Wait a moment and try again.", C.Red)
end)

showPicker = function(team: string)
	pickerTeam = team
	pickerFilter = "All"
	setCustomising(false)
	local list = Vehicles.forTeam(team)
	if not selectedId or not Vehicles.ById[selectedId] or Vehicles.ById[selectedId].team ~= team then
		selectedId = if list[1] then list[1].id else nil
	end
	showScreen("Picker")
	local vehicle = selectedVehicle()
	if vehicle then
		local spot = mapSetting("Showroom_" .. team)
		if typeof(spot) == "CFrame" then
			-- Jump straight there: the world might not have loaded around the depot yet
			streamAround(spot.Position)
		end
		showPreview(vehicle)
	end
	refreshPicker()
end

player.AttributeChanged:Connect(function()
	if gui.Enabled and screens.Picker.Visible then
		refreshPicker()
	end
end)

-- Opening and closing ------------------------------------------------------------------------

-- Roblox's own player list sits where our cash goes, so hide it while the menu is open
local function showPlayerList(show: boolean)
	pcall(function()
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, show)
	end)
end

openMenu = function()
	Ui.setMenuOpen(true)
	showPlayerList(false)
	gui.Enabled = true
	if controls then
		controls:Disable()
	end
	showScreen("Main")
	flyTo(menuShot(), true)
end

closeMenu = function()
	gui.Enabled = false
	blur.Size = 0
	if previewModel then
		previewModel:Destroy()
		previewModel = nil
	end
	cameraTarget = nil
	camera.CameraType = Enum.CameraType.Custom
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		camera.CameraSubject = humanoid
	end
	if controls then
		controls:Enable()
	end
	showPlayerList(true)
	Ui.setMenuOpen(false)
end

Ui.MenuRequested:Connect(openMenu)

-- Teams can be joined and left while the team picker is open, so keep the member lists fresh
task.spawn(function()
	while true do
		task.wait(3)
		if gui.Enabled and screens.Teams.Visible then
			refreshMembers()
		end
	end
end)

-- Show the menu when you first join
local character = player.Character or player.CharacterAdded:Wait()
character:WaitForChild("Humanoid")
task.wait(0.5)
openMenu()
