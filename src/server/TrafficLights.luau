-- Runs every set of traffic lights in the map, UK style: red, red and amber, green, amber, red.
-- Each light head is a Model tagged "TrafficLight" with lamps called Red, Amber and Green, and two attributes:
--   Junction: which junction it belongs to (heads with the same name change together)
--   Axis: "NS" or "EW", which way the traffic it controls is going
-- The junction's current state is written to ReplicatedStorage → TrafficSignals as an attribute
-- (e.g. "NS" = green for north-south), ready for red-light cameras later.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GREEN_SECONDS = 14
local AMBER_SECONDS = 3
local RED_AMBER_SECONDS = 2
local ALL_RED_SECONDS = 2

local LIT = {
	Red = Color3.fromRGB(255, 45, 35),
	Amber = Color3.fromRGB(255, 165, 0),
	Green = Color3.fromRGB(40, 255, 120),
}
local OFF = Color3.fromRGB(38, 36, 34)

-- What each axis shows in each step of the cycle
type Step = { ns: { string }, ew: { string }, seconds: number, green: string? }
local CYCLE: { Step } = {
	{ ns = { "Green" }, ew = { "Red" }, seconds = GREEN_SECONDS, green = "NS" },
	{ ns = { "Amber" }, ew = { "Red" }, seconds = AMBER_SECONDS },
	{ ns = { "Red" }, ew = { "Red" }, seconds = ALL_RED_SECONDS },
	{ ns = { "Red" }, ew = { "Red", "Amber" }, seconds = RED_AMBER_SECONDS },
	{ ns = { "Red" }, ew = { "Green" }, seconds = GREEN_SECONDS, green = "EW" },
	{ ns = { "Red" }, ew = { "Amber" }, seconds = AMBER_SECONDS },
	{ ns = { "Red" }, ew = { "Red" }, seconds = ALL_RED_SECONDS },
	{ ns = { "Red", "Amber" }, ew = { "Red" }, seconds = RED_AMBER_SECONDS },
}

local TrafficLights = {}

local function show(head: Instance, lit: { string })
	for _, name in { "Red", "Amber", "Green" } do
		local lamp = head:FindFirstChild(name)
		if lamp and lamp:IsA("BasePart") then
			local on = table.find(lit, name) ~= nil
			lamp.Color = if on then LIT[name] else OFF
			lamp.Material = if on then Enum.Material.Neon else Enum.Material.SmoothPlastic
		end
	end
end

local function runJunction(id: string, heads: { Instance }, signals: Configuration, startStep: number)
	-- Attribute names can only use letters, numbers and underscores, so "120,480" becomes "Junction_120_480"
	local attribute = "Junction_" .. (id:gsub("[^%w]", "_"))
	local step = startStep
	while true do
		local current = CYCLE[step]
		for _, head in heads do
			show(head, if head:GetAttribute("Axis") == "NS" then current.ns else current.ew)
		end
		signals:SetAttribute(attribute, current.green or "None")
		task.wait(current.seconds)
		step = step % #CYCLE + 1
	end
end

function TrafficLights.start()
	local signals = Instance.new("Configuration")
	signals.Name = "TrafficSignals"
	signals.Parent = ReplicatedStorage

	local junctions: { [string]: { Instance } } = {}
	for _, head in CollectionService:GetTagged("TrafficLight") do
		local id = head:GetAttribute("Junction")
		if typeof(id) == "string" then
			junctions[id] = junctions[id] or {}
			table.insert(junctions[id], head)
		end
	end

	-- Start each junction at a different point in the cycle so the whole town doesn't change at once
	local random = Random.new(42)
	for id, heads in junctions do
		task.spawn(runJunction, id, heads, signals, random:NextInteger(1, #CYCLE))
	end
end

return TrafficLights
