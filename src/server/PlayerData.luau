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
