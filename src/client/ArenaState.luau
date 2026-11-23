--!strict
-- Read-only view of the match state of the arena this player is fighting in. Several arenas run at
-- once (one per map); the server sets the player's "Arena" attribute while they are in a match and
-- each arena publishes its state as attributes on ReplicatedStorage.Arenas.<MapId>. In the Camp
-- Moore lobby there is no arena and every attribute reads nil.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer :: Player
local arenas = ReplicatedStorage:WaitForChild("Arenas")

local ArenaState = {}

function ArenaState.folder(): Instance?
	local id = player:GetAttribute("Arena")
	return if typeof(id) == "string" then arenas:FindFirstChild(id) else nil
end

function ArenaState.GetAttribute(_self: any, name: string): any
	local folder = ArenaState.folder()
	return if folder then folder:GetAttribute(name) else nil
end

return ArenaState
