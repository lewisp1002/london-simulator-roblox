-- Makes the RemoteEvents and RemoteFunctions the menus and HUD use to talk to the server.
-- They all live in ReplicatedStorage → Remotes, so client scripts can find them by name.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = {}

local folder = Instance.new("Folder")
folder.Name = "Remotes"
folder.Parent = ReplicatedStorage

function Remotes.event(name: string): RemoteEvent
	local remote = Instance.new("RemoteEvent")
	remote.Name = name
	remote.Parent = folder
	return remote
end

function Remotes.func(name: string): RemoteFunction
	local remote = Instance.new("RemoteFunction")
	remote.Name = name
	remote.Parent = folder
	return remote
end

-- Pop-up messages at the top of a player's screen, e.g. Remotes.notify(player, "Bought!", "It's in your garage")
local notifyRemote = Remotes.event("Notify")
function Remotes.notify(player: Player, title: string, body: string?, colour: string?)
	notifyRemote:FireClient(player, title, body, colour)
end

return Remotes
