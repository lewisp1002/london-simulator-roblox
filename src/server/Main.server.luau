-- Starts everything on the server.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Cars = require(script.Parent.Cars)
local Garage = require(script.Parent.Garage)
local LightingSetup = require(script.Parent.LightingSetup)
local LondonMap = require(script.Parent.LondonMap)
local Pedestrians = require(script.Parent.Pedestrians)
local PlayerData = require(script.Parent.PlayerData)
local TrafficLights = require(script.Parent.TrafficLights)

LightingSetup.apply()
PlayerData.start()
-- Build London, unless it's already saved in the place (built in Studio with the Command Bar)
if Config.BuildMap and not Workspace:FindFirstChild("London") then
	LondonMap.build()
end
LondonMap.startClock()
Pedestrians.setup()
TrafficLights.start()
Cars.start()
Garage.start()

-- Placeholder income until jobs are added: pay everyone on a timer
while true do
	task.wait(Config.PaychequeIntervalSeconds)
	for _, player in Players:GetPlayers() do
		PlayerData.addCash(player, Config.PaychequeAmount)
	end
end
