--!strict
-- Camp More Maniar: everyone spawns here, walks around, and queues for a map from the lobby bar. Players
-- who queue for the same map play each other; each map runs its own arena. After a match players
-- come back here.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Arena = require(script.Parent.Arena)
local Config = require(ReplicatedStorage.Shared.Config)
local Economy = require(script.Parent.Economy)
local Loadout = require(script.Parent.Loadout)
local Net = require(script.Parent.Net)
local PracticeRange = require(script.Parent.PracticeRange)
local Rig = require(script.Parent.Rig)
local World = require(script.Parent.World)

local Lobby = {}

local random = Random.new()

function Lobby.run(world: World.World)
	Players.CharacterAutoLoads = false
	local spawn = world.lobby.spawn
	local loads: { [Player]: number } = {}

	local function toLobby(player: Player)
		player:SetAttribute("Team", nil)
		player:SetAttribute("Arena", nil)
		player.CameraMode = Enum.CameraMode.Classic
		if player.Parent == nil then
			return
		end
		-- Each call supersedes earlier ones still yielding; only the newest load may move the player.
		local gen = (loads[player] or 0) + 1
		loads[player] = gen
		local function stale(): boolean
			return loads[player] ~= gen or not player:IsDescendantOf(Players) or player:GetAttribute("Arena") ~= nil
		end
		local at = spawn * CFrame.new(random:NextNumber(-10, 10), 0, random:NextNumber(-6, 6))
		-- Stream Camp More Maniar to their client before the character exists: a new character starts
		-- at the default spawn point, so the move below must follow the load with no wait in between.
		pcall(player.RequestStreamAroundAsync, player, at.Position)
		if stale() then
			return
		end
		local loaded = false
		for _ = 1, 3 do
			loaded = pcall(player.LoadCharacterAsync, player)
			if loaded or stale() then
				break
			end
			task.wait(1)
		end
		local character = player.Character
		if not loaded or not character or stale() then
			return
		end
		character:PivotTo(at)
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid.Died:Once(function()
				task.wait(3)
				if player.Parent and player:GetAttribute("Arena") == nil and player.Character == character then
					toLobby(player)
				end
			end)
		end
	end

	local arenas: { [string]: Arena.Arena } = {}
	for _, m in Config.Maps do
		arenas[m.id] = Arena.new(world.maps[m.id], toLobby)
	end
	-- The lobby box (Camp More Maniar's walls) is the practice range's anti-cheat bounds.
	local lobbyOrigin = spawn.Position - Vector3.new(0, 3.5, 22)
	local range = PracticeRange.new(
		world.lobby.range,
		lobbyOrigin + Vector3.new(-90, -12, -70),
		lobbyOrigin + Vector3.new(90, 60, 70)
	)

	local function arenaOf(player: Player, attribute: string): Arena.Arena?
		local id = player:GetAttribute(attribute)
		return if typeof(id) == "string" then arenas[id] else nil
	end

	Net.Queue.OnServerEvent:Connect(function(player, action, mapId, mode)
		if not Net.allow(player, "Queue", 4, 2) then
			return
		end
		local target: Arena.Arena? = nil
		if action == "Join" then
			if typeof(mapId) ~= "string" or not arenas[mapId] or (mode ~= "1v1" and mode ~= "2v2") then
				return
			end
			if typeof(player:GetAttribute("Coins")) ~= "number" then
				return -- profile still loading
			end
			target = arenas[mapId]
		elseif action ~= "Leave" then
			return
		end
		if range.isPracticing(player) then
			range.leave(player) -- queueing ends practice
		end
		if player:GetAttribute("Arena") ~= nil then
			return -- already in a match
		end
		local current = arenaOf(player, "Queued")
		if current then
			current.leave(player)
		end
		if target then
			target.join(player, if mode == "2v2" then "2v2" else "1v1")
		end
	end)

	-- Free emotes in Camp More Maniar; the gold salute is for players with the Eddie's Honor title.
	Net.Emote.OnServerEvent:Connect(function(player, id)
		local character = player.Character
		if not character or player:GetAttribute("Arena") ~= nil or not Net.allow(player, "Emote", 1, 2) then
			return
		end
		for _, e in Config.Emotes do
			if e.id == id and (e.title == nil or player:GetAttribute("Title") == e.title) then
				Rig.emote(character, e.anim)
			end
		end
	end)

	Loadout.onChange = function(player)
		local arena = arenaOf(player, "Arena")
		if arena then
			arena.loadoutChanged(player)
		end
	end

	Players.PlayerAdded:Connect(toLobby)
	for _, player in Players:GetPlayers() do
		task.spawn(toLobby, player)
	end
	Players.PlayerRemoving:Connect(function(player)
		loads[player] = nil
		for _, attribute in { "Queued", "Arena" } do
			local arena = arenaOf(player, attribute)
			if arena then
				arena.leave(player)
			end
		end
	end)

	while true do
		world.lobby.leaderboard.Text = Economy.leaderboard(8)
		task.wait(5)
	end
end

return Lobby
