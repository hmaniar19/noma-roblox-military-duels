--!strict
-- Match flow: 1v1, first to 5 round wins. Each round: freeze, 2:00 live, then a win, loss or draw.
-- Sides swap every round. A bot fills the second slot when only one player is here. Leaving
-- mid-match forfeits it. Players who aren't dueling watch from the spectator gallery.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Bot = require(script.Parent.Bot)
local Combat = require(script.Parent.Combat)
local Combatants = require(script.Parent.Combatants)
local Config = require(ReplicatedStorage.Shared.Config)
local Map = require(script.Parent.Map)
local Net = require(script.Parent.Net)
local Rig = require(script.Parent.Rig)

type Combatant = Combatants.Combatant
type TeamId = Config.TeamId
type Entry = { player: Player?, team: TeamId, name: string }
type Result = TeamId | "Draw"
type Scores = { Navy: number, Grey: number }

local Match = {}

local state = Instance.new("Folder")
state.Name = "GameState"
state:SetAttribute("Phase", "Waiting")
state.Parent = ReplicatedStorage

local bots = Instance.new("Folder")
bots.Name = "Bots"
bots.Parent = workspace

local queue: { Player } = {}
local roster: { Entry } = {}
local forfeit: TeamId? = nil
local decided = false
local lastElimination = ""

local function other(team: TeamId): TeamId
	return if team == "Navy" then "Grey" else "Navy"
end

local function setPhase(phase: string)
	state:SetAttribute("Phase", phase)
end

local function banner(kind: string, data: { [string]: any })
	Net.Banner:FireAllClients(kind, data)
end

local function inRoster(player: Player): Entry?
	for _, e in roster do
		if e.player == player then
			return e
		end
	end
	return nil
end

local random = Random.new()

local function toGallery(player: Player, gallery: CFrame)
	player:SetAttribute("Team", nil)
	player.CameraMode = Enum.CameraMode.Classic
	if player.Parent == nil then
		return
	end
	player:LoadCharacterAsync()
	local character = player.Character
	-- Skip the move if they were picked for a duel while this load was running.
	if character and player:GetAttribute("Team") == nil then
		character:PivotTo(gallery * CFrame.new(random:NextNumber(-12, 12), 0, 0))
	end
end

local function living(team: TeamId): { Combatant }
	local out = {}
	for _, c in Combatants.all() do
		if c.alive and c.team == team then
			table.insert(out, c)
		end
	end
	return out
end

-- Combat stops the instant a side is wiped out, so the survivor can't keep shooting into the end.
local function latchIfWiped()
	if Combat.isLive() and (#living("Navy") == 0 or #living("Grey") == 0) then
		setPhase("RoundEnd")
	end
end

-- Live only until the deadline the HUD shows, not until the round loop next wakes up.
Combat.isLive = function()
	return state:GetAttribute("Phase") == "Live"
		and workspace:GetServerTimeNow() < (state:GetAttribute("RoundEndsAt") or 0)
end

Combat.onElimination = function(victim, attacker, zone)
	if attacker and attacker ~= victim then
		lastElimination = `{attacker.name} eliminated {victim.name}`
			.. (if zone == "Head" then " with a HEADSHOT" else "")
	end
	latchIfWiped()
end

local function spawnEntry(entry: Entry, cf: CFrame, info: Map.MapInfo): Combatant?
	local model: Model?
	local ok, err = pcall(function()
		if entry.player then
			entry.player.CameraMode = Enum.CameraMode.LockFirstPerson
			entry.player:SetAttribute("Team", entry.team)
			model = Rig.spawnPlayer(entry.player, entry.team, cf)
		else
			model = Rig.spawnBot(entry.team, entry.name, cf, bots)
		end
	end)
	if not ok then
		warn(`[Match] could not spawn {entry.name}: {err}`)
	end
	if not model then
		return nil
	end
	local c = Combatants.new(entry.name, entry.player, entry.team, model, cf)
	c.root.Anchored = true
	c.humanoid.Died:Once(function()
		if c.alive then
			c.alive = false
			lastElimination = `{c.name} was eliminated`
		end
		latchIfWiped()
	end)
	if not entry.player then
		task.spawn(Bot.run, c, info.waypoints, function()
			return living(other(c.team))
		end)
	end
	return c
end

local function playRound(round: number, info: Map.MapInfo, scores: Scores): Result?
	Combatants.clear()
	bots:ClearAllChildren()
	lastElimination = ""
	local navySide = if round % 2 == 1 then "A" else "B"
	state:SetAttribute("Round", round)
	state:SetAttribute("NavySide", navySide)
	local sudden = scores.Navy == Config.SuddenDeathAt and scores.Grey == Config.SuddenDeathAt
	state:SetAttribute("SuddenDeath", sudden)
	setPhase("Freeze")

	local slots = { Navy = 0, Grey = 0 }
	local spawned: { Combatant } = {}
	for _, entry in roster do
		local side = if entry.team == "Navy" then navySide else (if navySide == "A" then "B" else "A")
		slots[entry.team] += 1
		local cf = (info.spawns :: any)[side][slots[entry.team]]
		local c = spawnEntry(entry, cf, info)
		if c then
			table.insert(spawned, c)
		elseif not forfeit then
			-- A side that can't field anyone loses the match rather than leaving a one-sided round.
			forfeit = entry.team
		end
	end
	state:SetAttribute("FreezeEndsAt", workspace:GetServerTimeNow() + Config.FreezeSeconds)
	banner("RoundStart", { round = round, sudden = sudden, navySide = navySide })
	task.wait(Config.FreezeSeconds)
	if forfeit then
		return nil
	end

	local now = os.clock()
	for _, c in spawned do
		if c.root.Parent then
			c.root.Anchored = false
			Combatants.teleport(c, c.root.CFrame)
			c.shieldUntil = now + Config.SpawnShieldSeconds
			local field = Instance.new("ForceField")
			field.Parent = c.model
			task.delay(Config.SpawnShieldSeconds, function()
				if field.Parent then
					field:Destroy()
				end
			end)
		end
	end
	state:SetAttribute("RoundEndsAt", workspace:GetServerTimeNow() + Config.RoundSeconds)
	setPhase("Live")

	local deadline = os.clock() + Config.RoundSeconds
	while os.clock() < deadline and not forfeit and state:GetAttribute("Phase") == "Live" do
		task.wait(0.1)
	end
	-- A wipe latches RoundEnd itself; reaching here still Live means time ran out: a draw, even if
	-- someone dies in the instant before this line runs.
	local timedOut = state:GetAttribute("Phase") == "Live"
	setPhase("RoundEnd")
	if forfeit then
		return nil
	end
	if timedOut then
		return "Draw"
	end
	local navyUp, greyUp = #living("Navy") > 0, #living("Grey") > 0
	if navyUp and not greyUp then
		return "Navy"
	elseif greyUp and not navyUp then
		return "Grey"
	end
	return "Draw"
end

local function playMatch(info: Map.MapInfo)
	local scores: Scores = { Navy = 0, Grey = 0 }
	forfeit = nil
	decided = false
	state:SetAttribute("NavyScore", 0)
	state:SetAttribute("GreyScore", 0)
	state:SetAttribute("NavyName", roster[1].name)
	state:SetAttribute("GreyName", roster[2].name)
	state:SetAttribute("Winner", nil)

	local round = 0
	while scores.Navy < Config.RoundsToWin and scores.Grey < Config.RoundsToWin and not forfeit do
		round += 1
		local result = playRound(round, info, scores)
		if not result then
			break
		end
		if result == "Navy" then
			scores.Navy += 1
		elseif result == "Grey" then
			scores.Grey += 1
		end
		state:SetAttribute("NavyScore", scores.Navy)
		state:SetAttribute("GreyScore", scores.Grey)
		-- The fifth point locks the result; leaving during the banners can't flip it.
		decided = scores.Navy >= Config.RoundsToWin or scores.Grey >= Config.RoundsToWin
		banner("RoundEnd", { winner = result, detail = if result == "Draw" then "Time ran out" else lastElimination })
		task.wait(Config.RoundEndSeconds)
	end

	local winner: TeamId = if decided
		then (if scores.Navy >= Config.RoundsToWin then "Navy" else "Grey")
		else other(forfeit or "Navy")
	setPhase("MatchEnd")
	state:SetAttribute("Winner", winner)
	banner("MatchEnd", {
		winner = winner,
		navy = scores.Navy,
		grey = scores.Grey,
		forfeit = not decided,
	})
	task.wait(Config.MatchEndSeconds)
	Combatants.clear()
	bots:ClearAllChildren()
end

-- Up to two waiting players duel; a bot fills the second slot. Players who just played go to the
-- back of the queue so a third player gets a turn.
local function pickRoster()
	while #queue == 0 do
		setPhase("Waiting")
		task.wait(0.5)
	end
	roster = {}
	local teams: { TeamId } = { "Navy", "Grey" }
	for i, team in teams do
		local player = queue[i]
		if player then
			table.insert(roster, { player = player, team = team :: TeamId, name = player.DisplayName } :: Entry)
		else
			table.insert(roster, { player = nil, team = team :: TeamId, name = Config.Bot.Name } :: Entry)
		end
	end
	for _, e in roster do
		local i = if e.player then table.find(queue, e.player) else nil
		if i then
			table.insert(queue, table.remove(queue, i) :: Player)
		end
	end
end

function Match.run(info: Map.MapInfo)
	Players.CharacterAutoLoads = false
	local function joined(player: Player)
		table.insert(queue, player)
		-- Mid-match arrivals watch from the gallery; while waiting, pickRoster spawns them directly.
		if state:GetAttribute("Phase") ~= "Waiting" then
			task.spawn(toGallery, player, info.gallery)
		end
	end
	Players.PlayerAdded:Connect(joined)
	for _, player in Players:GetPlayers() do
		joined(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		local i = table.find(queue, player)
		if i then
			table.remove(queue, i)
		end
		local entry = inRoster(player)
		if entry and not decided and state:GetAttribute("Phase") ~= "MatchEnd" then
			forfeit = entry.team
		end
	end)

	while true do
		pickRoster()
		for _, player in Players:GetPlayers() do
			if not inRoster(player) and player:GetAttribute("Team") ~= nil then
				task.spawn(toGallery, player, info.gallery)
			end
		end
		playMatch(info)
	end
end

return Match
