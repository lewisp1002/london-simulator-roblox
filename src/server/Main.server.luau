-- Starts everything on the server.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Cars = require(script.Parent.Cars)
local Garage = require(script.Parent.Garage)
local LightingSetup = require(script.Parent.LightingSetup)
local PlayerData = require(script.Parent.PlayerData)
local TestTown = require(script.Parent.TestTown)
local TrafficLights = require(script.Parent.TrafficLights)

LightingSetup.apply()
PlayerData.start()
if Config.BuildTestTown then
	TestTown.build()
end
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
