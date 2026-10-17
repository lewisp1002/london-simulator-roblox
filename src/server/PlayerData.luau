-- Loads, saves and changes each player's saved data: cash, the vehicles they own and the colours they picked.
-- Other server scripts use it like this:
--   PlayerData.addCash(player, 50)
--   if PlayerData.owns(player, "regent_gt") then ... end
-- The client can read it too, through attributes on the player: "Cash", "Owned_<vehicle id>" and "Paint_<vehicle id>".

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Vehicles = require(ReplicatedStorage.Shared.Vehicles)

local MAX_ATTEMPTS = 3

type Data = {
	cash: number,
	owned: { string }, -- ids of vehicles they've bought
	paints: { [string]: number }, -- vehicle id -> paint number they picked
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

-- Copies a save into fresh data, skipping anything broken or for vehicles that no longer exist
local function readSave(saved: any, data: Data)
	if type(saved) ~= "table" then
		return
	end
	if type(saved.cash) == "number" then
		data.cash = saved.cash
	end
	if type(saved.owned) == "table" then
		for _, id in saved.owned do
			if type(id) == "string" and Vehicles.ById[id] and not table.find(data.owned, id) then
				table.insert(data.owned, id)
			end
		end
	end
	if type(saved.paints) == "table" then
		for id, paint in saved.paints do
			if type(id) == "string" and Vehicles.ById[id] and type(paint) == "number" and Vehicles.Paints[paint] then
				data.paints[id] = paint
			end
		end
	end
end

local function onPlayerAdded(player: Player)
	local data: Data = {
		cash = Config.StartingCash,
		owned = {},
		paints = {},
	}
	local canSave = false

	if storeOk then
		local ok, saved = retry(function()
			return store:GetAsync(keyFor(player))
		end)
		if ok then
			readSave(saved, data)
			canSave = true
		else
			warn(`[PlayerData] Couldn't load {player.Name}'s data, so it won't be saved this session:`, saved)
		end
	end

	if player.Parent ~= Players then
		return -- they left while their data was loading
	end

	sessions[player] = { data = data, canSave = canSave }
	for _, id in data.owned do
		player:SetAttribute("Owned_" .. id, true)
	end
	for id, paint in data.paints do
		player:SetAttribute("Paint_" .. id, paint)
	end
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

function PlayerData.isLoaded(player: Player): boolean
	return sessions[player] ~= nil
end

function PlayerData.addCash(player: Player, amount: number)
	local session = sessions[player]
	if not session then
		return -- their data hasn't loaded yet
	end
	session.data.cash += amount
	player:SetAttribute("Cash", session.data.cash)
end

-- Takes money only if they've got enough. Returns true if it worked.
function PlayerData.trySpend(player: Player, amount: number): boolean
	local session = sessions[player]
	if not session or session.data.cash < amount then
		return false
	end
	session.data.cash -= amount
	player:SetAttribute("Cash", session.data.cash)
	return true
end

-- Free vehicles (price 0) count as owned by everyone
function PlayerData.owns(player: Player, vehicleId: string): boolean
	local vehicle = Vehicles.ById[vehicleId]
	if not vehicle then
		return false
	end
	if vehicle.price == 0 then
		return true
	end
	local session = sessions[player]
	return session ~= nil and table.find(session.data.owned, vehicleId) ~= nil
end

function PlayerData.giveVehicle(player: Player, vehicleId: string)
	local session = sessions[player]
	if not session or table.find(session.data.owned, vehicleId) then
		return
	end
	table.insert(session.data.owned, vehicleId)
	player:SetAttribute("Owned_" .. vehicleId, true)
end

function PlayerData.paintOf(player: Player, vehicleId: string): number?
	local session = sessions[player]
	return session and session.data.paints[vehicleId]
end

function PlayerData.setPaint(player: Player, vehicleId: string, paint: number?)
	local session = sessions[player]
	if not session then
		return
	end
	local paints: { [string]: number? } = session.data.paints
	paints[vehicleId] = paint
	player:SetAttribute("Paint_" .. vehicleId, paint)
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
