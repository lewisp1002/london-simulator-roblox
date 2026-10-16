-- London Simulator installer
-- Paste ALL of this into Roblox Studio's Command Bar and press Enter.
-- It creates every folder and script in the right place, replacing old copies.
-- Made by tools/build_installer.py from the files in src/, so don't edit this file by hand.

local function folder(parent: Instance, name: string): Instance
	local existing = parent:FindFirstChild(name)
	if existing then
		return existing
	end
	local newFolder = Instance.new("Folder")
	newFolder.Name = name
	newFolder.Parent = parent
	return newFolder
end

local function put(parent: Instance, className: string, name: string, source: string)
	local old = parent:FindFirstChild(name)
	if old then
		old:Destroy()
	end
	local newScript: any = Instance.new(className)
	newScript.Name = name
	newScript.Source = source
	newScript.Parent = parent
end

local folder1 = game:GetService("ReplicatedStorage")
local folder2 = folder(folder1, "Shared")
put(folder2, "ModuleScript", "Config", [[
-- Game-wide settings. Change the numbers here to rebalance the game.

local Config = {}

Config.CurrencySymbol = "£"

-- Money a brand new player starts with
Config.StartingCash = 500

-- Placeholder income until jobs exist: everyone gets paid on a timer.
-- Set the interval to 10 while testing so you don't have to wait.
Config.PaychequeAmount = 100
Config.PaychequeIntervalSeconds = 300

-- How often everyone's data is saved, on top of saving when they leave
Config.AutosaveIntervalSeconds = 120

-- Changing this name starts everyone from scratch (e.g. to wipe test data before launch)
Config.DataStoreName = "PlayerData_v1"

return Config
]])
put(folder2, "ModuleScript", "Format", [[
-- Turns numbers into text for the UI.

local Config = require(script.Parent.Config)

local Format = {}

-- 1250 -> "£1,250"
function Format.money(amount: number): string
	local digits = tostring(math.floor(math.abs(amount)))
	local withCommas = digits:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
	local sign = if amount < 0 then "-" else ""
	return sign .. Config.CurrencySymbol .. withCommas
end

return Format
]])
local folder3 = game:GetService("ServerScriptService")
local folder4 = folder(folder3, "Server")
put(folder4, "Script", "Main", [[
-- Starts everything on the server.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local PlayerData = require(script.Parent.PlayerData)

PlayerData.start()

-- Placeholder income until jobs are added: pay everyone on a timer
while true do
	task.wait(Config.PaychequeIntervalSeconds)
	for _, player in Players:GetPlayers() do
		PlayerData.addCash(player, Config.PaychequeAmount)
	end
end
]])
put(folder4, "ModuleScript", "PlayerData", [[
-- Loads, saves and changes each player's saved data (just cash for now).
-- Other server scripts use it like this:
--   PlayerData.addCash(player, 50)

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local MAX_ATTEMPTS = 3

type Data = {
	cash: number,
}

type Session = {
	data: Data,
	-- Stays false if loading failed, so a Roblox outage can never overwrite someone's real save
	canSave: boolean,
}

local PlayerData = {}

local sessions: { [Player]: Session } = {}

-- This fails until the game is published, so the game still runs, just without saving
local storeOk, store = pcall(DataStoreService.GetDataStore, DataStoreService, Config.DataStoreName)
if not storeOk then
	warn("[PlayerData] Saving is off until the game is published:", store)
end

local function keyFor(player: Player): string
	return "player_" .. player.UserId
end

-- DataStore calls sometimes fail for a moment, so try a few times before giving up
local function retry(action: () -> ...any): (boolean, any)
	local ok, result = false, nil
	for attempt = 1, MAX_ATTEMPTS do
		ok, result = pcall(action)
		if ok or attempt == MAX_ATTEMPTS then
			break
		end
		task.wait(attempt * 2)
	end
	return ok, result
end

local function onPlayerAdded(player: Player)
	local data: Data = {
		cash = Config.StartingCash,
	}
	local canSave = false

	if storeOk then
		local ok, saved = retry(function()
			return store:GetAsync(keyFor(player))
		end)
		if ok then
			if type(saved) == "table" and type(saved.cash) == "number" then
				data.cash = saved.cash
			end
			canSave = true
		else
			warn(`[PlayerData] Couldn't load {player.Name}'s data, so it won't be saved this session:`, saved)
		end
	end

	if player.Parent ~= Players then
		return -- they left while their data was loading
	end

	sessions[player] = { data = data, canSave = canSave }
	player:SetAttribute("Cash", data.cash)
end

local function save(player: Player)
	local session = sessions[player]
	if not session or not session.canSave then
		return
	end
	local ok, err = retry(function()
		store:SetAsync(keyFor(player), session.data, { player.UserId })
	end)
	if not ok then
		warn(`[PlayerData] Couldn't save {player.Name}'s data:`, err)
	end
end

local function onPlayerRemoving(player: Player)
	save(player)
	sessions[player] = nil
end

function PlayerData.addCash(player: Player, amount: number)
	local session = sessions[player]
	if not session then
		return -- their data hasn't loaded yet
	end
	session.data.cash += amount
	player:SetAttribute("Cash", session.data.cash)
end

function PlayerData.start()
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	-- Catch anyone who joined before this script started (happens when testing in Studio)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end

	-- The server is shutting down: save everyone at once and wait until every save finishes
	game:BindToClose(function()
		local pending = 0
		for _, player in Players:GetPlayers() do
			pending += 1
			task.spawn(function()
				save(player)
				pending -= 1
			end)
		end
		while pending > 0 do
			task.wait()
		end
	end)

	task.spawn(function()
		while true do
			task.wait(Config.AutosaveIntervalSeconds)
			for _, player in Players:GetPlayers() do
				task.spawn(save, player)
			end
		end
	end)
end

return PlayerData
]])
local folder5 = game:GetService("StarterPlayer")
local folder6 = folder5:WaitForChild("StarterPlayerScripts")
local folder7 = folder(folder6, "Client")
put(folder7, "LocalScript", "Hud", [[
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
]])

print("London Simulator installed 5 scripts. Press Play to test!")
