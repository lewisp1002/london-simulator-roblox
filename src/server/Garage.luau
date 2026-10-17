-- Teams, buying vehicles and picking paint colours: everything the menu asks the server to do
-- before you drive off.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Teams = game:GetService("Teams")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Vehicles = require(ReplicatedStorage.Shared.Vehicles)
local Cars = require(script.Parent.Cars)
local PlayerData = require(script.Parent.PlayerData)
local Remotes = require(script.Parent.Remotes)

local Garage = {}

local function makeTeams()
	for _, info in Config.Teams do
		local team = Teams:FindFirstChild(info.name) :: Team?
		if not team then
			local newTeam = Instance.new("Team")
			newTeam.Name = info.name
			newTeam.Parent = Teams
			team = newTeam
		end
		local teamToUse = team :: Team
		teamToUse.TeamColor = BrickColor.new(info.colour)
		teamToUse.AutoAssignable = false -- everyone picks a team in the menu
	end
end

local function chooseTeam(player: Player, teamName: unknown)
	if typeof(teamName) ~= "string" then
		return
	end
	local team = Teams:FindFirstChild(teamName)
	if not team or not team:IsA("Team") or player.Team == team then
		return
	end
	-- Changing team puts your old team's vehicle away
	Cars.despawn(player)
	player.Neutral = false
	player.Team = team
end

local function buyVehicle(player: Player, vehicleId: unknown): (boolean, string)
	if typeof(vehicleId) ~= "string" then
		return false, "That vehicle doesn't exist."
	end
	local vehicle = Vehicles.ById[vehicleId]
	if not vehicle then
		return false, "That vehicle doesn't exist."
	end
	if not PlayerData.isLoaded(player) then
		return false, "Your garage is still loading. Try again in a moment."
	end
	if PlayerData.owns(player, vehicle.id) then
		return true, "You already own it."
	end
	if not PlayerData.trySpend(player, vehicle.price) then
		return false, `You need {Format.money(vehicle.price)} for the {vehicle.name}.`
	end
	PlayerData.giveVehicle(player, vehicle.id)
	return true, `The {vehicle.name} is yours. Enjoy!`
end

local function setPaint(player: Player, vehicleId: unknown, paint: unknown)
	if typeof(vehicleId) ~= "string" then
		return
	end
	local vehicle = Vehicles.ById[vehicleId]
	if not vehicle or vehicle.fixedPaint or not PlayerData.owns(player, vehicle.id) then
		return
	end
	if paint == nil then
		PlayerData.setPaint(player, vehicle.id, nil) -- back to the factory colour
	elseif typeof(paint) == "number" and Vehicles.Paints[paint] then
		PlayerData.setPaint(player, vehicle.id, paint)
	end
end

function Garage.start()
	makeTeams()
	Remotes.event("ChooseTeam").OnServerEvent:Connect(chooseTeam)
	Remotes.event("SetPaint").OnServerEvent:Connect(setPaint)
	Remotes.func("BuyVehicle").OnServerInvoke = buyVehicle

	-- Nobody's on a team until they pick one
	Players.PlayerAdded:Connect(function(player)
		player.Neutral = true
	end)
end

return Garage
