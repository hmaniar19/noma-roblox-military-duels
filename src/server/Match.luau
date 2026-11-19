--!strict
-- Match flow: a short lobby to pick 1v1 or 2v2, then first to 5 round wins. Each round: an 8-second
-- freeze to pick a loadout, 2:00 live, then a win, loss or draw. Sides swap every round; at 4-4 each
-- team plays Sudden Death with one sniper and one knife. Bots fill empty slots. A player who leaves
-- is replaced by a bot; a team with no players left forfeits. Spectators watch from the gallery.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Bot = require(script.Parent.Bot)
local Combat = require(script.Parent.Combat)
local Combatants = require(script.Parent.Combatants)
local Config = require(ReplicatedStorage.Shared.Config)
local Gadgets = require(script.Parent.Gadgets)
local Loadout = require(script.Parent.Loadout)
local Map = require(script.Parent.Map)
local Net = require(script.Parent.Net)
local Rig = require(script.Parent.Rig)

type Combatant = Combatants.Combatant
type TeamId = Config.TeamId
type Entry = { player: Player?, team: TeamId, name: string, combatant: Combatant? }
type Result = TeamId | "Draw"
type Scores = { Navy: number, Grey: number }

local Match = {}

local state = Instance.new("Folder")
state.Name = "GameState"
state:SetAttribute("Phase", "Waiting")
state:SetAttribute("Mode", "1v1")
state.Parent = ReplicatedStorage

local bots = Instance.new("Folder")
bots.Name = "Bots"
bots.Parent = workspace

local queue: { Player } = {}
local roster: { Entry } = {}
local forfeit: TeamId? = nil
local decided = false
local lastElimination = ""
local random = Random.new()

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

local function teamNames(team: TeamId): string
	local names = {}
	for _, e in roster do
		if e.team == team then
			table.insert(names, e.name)
		end
	end
	return table.concat(names, " & ")
end

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

-- Combat stops the instant a side is wiped out, so the survivors can't keep shooting into the end.
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

-- Gives every combatant its kit: the picked loadout, or a Sudden Death role resolved per team.
local function armAll()
	local sudden = state:GetAttribute("SuddenDeath") == true
	for _, team in { "Navy", "Grey" } :: { TeamId } do
		local members: { Entry } = {}
		for _, e in roster do
			if e.team == team and e.combatant then
				table.insert(members, e)
			end
		end
		local players: { Player? } = {}
		for i, e in members do
			players[i] = e.player
		end
		local roles = if sudden then Loadout.roles(players, #members) else {}
		for i, e in members do
			local c = e.combatant :: Combatant
			-- Bots roll their loadout once per round; Sudden Death roles can still shift with picks.
			if e.player or sudden or #c.weapons == 0 then
				local kit = if sudden then Loadout.suddenDeath(roles[i]) else Loadout.standard(e.player)
				Combat.arm(c, kit.weapons, kit.gadget)
			end
		end
	end
end

-- Picks made during the freeze show up immediately (the screen previews the real kit).
Loadout.onChange = function(player)
	if state:GetAttribute("Phase") == "Freeze" and inRoster(player) then
		armAll()
	end
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
	Gadgets.reset()
	bots:ClearAllChildren()
	lastElimination = ""
	local navySide = if round % 2 == 1 then "A" else "B"
	state:SetAttribute("Round", round)
	state:SetAttribute("NavySide", navySide)
	local sudden = scores.Navy == Config.SuddenDeathAt and scores.Grey == Config.SuddenDeathAt
	state:SetAttribute("SuddenDeath", sudden)
	setPhase("Freeze")

	local slots = { Navy = 0, Grey = 0 }
	for _, entry in roster do
		local side = if entry.team == "Navy" then navySide else (if navySide == "A" then "B" else "A")
		slots[entry.team] += 1
		local cf = (info.spawns :: any)[side][slots[entry.team]]
		entry.combatant = spawnEntry(entry, cf, info)
		if not entry.combatant then
			-- They left mid-spawn or their character failed to load: a bot stands in for this round.
			local standIn: Entry = { player = nil, team = entry.team, name = `{Config.Bot.Name} (stand-in)` }
			entry.combatant = spawnEntry(standIn, cf, info)
		end
		if not entry.combatant and not forfeit then
			-- A side that can't field anyone loses the match rather than leaving a one-sided round.
			forfeit = entry.team
		end
	end
	armAll()
	-- The pick countdown starts once everyone is in, so slow character loads don't eat into it.
	state:SetAttribute("FreezeEndsAt", workspace:GetServerTimeNow() + Config.FreezeSeconds)
	banner("RoundStart", { round = round, sudden = sudden, navySide = navySide })
	local freezeEnds = os.clock() + Config.FreezeSeconds
	while os.clock() < freezeEnds and not forfeit do
		task.wait(0.1)
	end
	if forfeit then
		return nil
	end

	armAll() -- final kits (Sudden Death roles are settled now)
	local now = os.clock()
	for _, c in Combatants.all() do
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
		lastElimination = "Time ran out"
		return "Draw"
	end
	local navyUp, greyUp = #living("Navy") > 0, #living("Grey") > 0
	if navyUp and not greyUp then
		return "Navy"
	elseif greyUp and not navyUp then
		return "Grey"
	end
	lastElimination = "Both sides were eliminated"
	return "Draw"
end

local function playMatch(info: Map.MapInfo)
	local scores: Scores = { Navy = 0, Grey = 0 }
	forfeit = nil
	decided = false
	state:SetAttribute("NavyScore", 0)
	state:SetAttribute("GreyScore", 0)
	state:SetAttribute("NavyName", teamNames("Navy"))
	state:SetAttribute("GreyName", teamNames("Grey"))
	state:SetAttribute("Winner", nil)
	Loadout.resetRoles()

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
		banner("RoundEnd", { winner = result, detail = lastElimination })
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
	Gadgets.reset()
	bots:ClearAllChildren()
end

-- A short lobby where anyone can switch the next match between 1v1 and 2v2; then the first waiting
-- players fill the teams (alternating Navy, Grey) and bots take the empty slots. Players who just
-- played go to the back of the queue so others get a turn.
local function pickRoster(): boolean
	while #queue == 0 do
		setPhase("Waiting")
		task.wait(0.5)
	end
	state:SetAttribute("LobbyEndsAt", workspace:GetServerTimeNow() + Config.LobbySeconds)
	setPhase("Lobby")
	task.wait(Config.LobbySeconds)
	if #queue == 0 then
		return false -- everyone left during the countdown
	end
	local perTeam = if state:GetAttribute("Mode") == "2v2" then 2 else 1
	roster = {}
	local botNumber = 0
	for i = 1, perTeam * 2 do
		local team: TeamId = if i % 2 == 1 then "Navy" else "Grey"
		local player = queue[i]
		if player then
			table.insert(roster, { player = player, team = team, name = player.DisplayName } :: Entry)
		else
			botNumber += 1
			local name = if perTeam == 1 then Config.Bot.Name else `{Config.Bot.Name} {botNumber}`
			table.insert(roster, { player = nil, team = team, name = name } :: Entry)
		end
	end
	for _, e in roster do
		local i = if e.player then table.find(queue, e.player) else nil
		if i then
			table.insert(queue, table.remove(queue, i) :: Player)
		end
	end
	return true
end

function Match.run(info: Map.MapInfo)
	Players.CharacterAutoLoads = false
	local function joined(player: Player)
		table.insert(queue, player)
		-- Mid-match arrivals watch from the gallery; otherwise pickRoster spawns them directly.
		local phase = state:GetAttribute("Phase")
		if phase ~= "Waiting" and phase ~= "Lobby" then
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
		if not entry or decided or state:GetAttribute("Phase") == "MatchEnd" then
			return
		end
		-- The leaver's slot goes to a bot from next round on; their character is out now.
		entry.player = nil
		entry.name = `{Config.Bot.Name} (sub)`
		if entry.combatant then
			entry.combatant.alive = false
			latchIfWiped()
		end
		local teamHasPlayer = false
		for _, e in roster do
			teamHasPlayer = teamHasPlayer or (e.team == entry.team and e.player ~= nil)
		end
		if not teamHasPlayer then
			forfeit = entry.team
		end
	end)
	Net.Mode.OnServerEvent:Connect(function(player, mode)
		local phase = state:GetAttribute("Phase")
		local open = phase == "Lobby" or phase == "MatchEnd" or phase == "Waiting"
		if open and (mode == "1v1" or mode == "2v2") and Net.allow(player, "Mode", 4, 2) then
			state:SetAttribute("Mode", mode)
		end
	end)

	while true do
		while not pickRoster() do
			task.wait()
		end
		for _, player in Players:GetPlayers() do
			if not inRoster(player) and player:GetAttribute("Team") ~= nil then
				task.spawn(toGallery, player, info.gallery)
			end
		end
		playMatch(info)
	end
end

return Match
