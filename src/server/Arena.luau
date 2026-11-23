--!strict
-- One arena per map, all running at once. Players queue for a map from the Camp More Maniar lobby; the
-- first player to queue picks 1v1 or 2v2, and everyone who queues for the same map within the
-- countdown plays together (bots fill empty slots). A match is first to 5 round wins. Each round:
-- an 8-second freeze to pick a loadout, 2:00 live, then a win, loss or draw. Sides swap every round;
-- at 4-4 each team plays Sudden Death with one sniper and one knife. A player who leaves is replaced
-- by a bot; a team with no players left forfeits. After the match everyone returns to the lobby.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Bot = require(script.Parent.Bot)
local Celebration = require(script.Parent.Celebration)
local Combat = require(script.Parent.Combat)
local Combatants = require(script.Parent.Combatants)
local Config = require(ReplicatedStorage.Shared.Config)
local Economy = require(script.Parent.Economy)
local Friends = require(script.Parent.Friends)
local Gadgets = require(script.Parent.Gadgets)
local Loadout = require(script.Parent.Loadout)
local MapKit = require(script.Parent.Maps.MapKit)
local Net = require(script.Parent.Net)
local Rig = require(script.Parent.Rig)

type Combatant = Combatants.Combatant
type TeamId = Config.TeamId
-- `userId` on a bot entry: the friend whose avatar and name the bot wears.
type Entry = { player: Player?, team: TeamId, name: string, combatant: Combatant?, userId: number? }
type Result = TeamId | "Draw"
type Scores = { Navy: number, Grey: number }

export type Arena = {
	id: string,
	join: (player: Player, mode: string) -> (),
	leave: (player: Player) -> (), -- leaving the queue, or the game mid-match
	loadoutChanged: (player: Player) -> (),
}

local Arena = {}

local stateRoot = Instance.new("Folder")
stateRoot.Name = "Arenas"
stateRoot.Parent = ReplicatedStorage
local botsRoot = Instance.new("Folder")
botsRoot.Name = "Bots"
botsRoot.Parent = workspace

local function other(team: TeamId): TeamId
	return if team == "Navy" then "Grey" else "Navy"
end

-- `toLobby` sends a player back to Camp More Maniar (it clears their Team and Arena attributes).
function Arena.new(info: MapKit.MapInfo, toLobby: (Player) -> ()): Arena
	local id = info.id
	local state = Instance.new("Folder")
	state.Name = id
	state:SetAttribute("Name", info.name)
	state:SetAttribute("Phase", "Waiting")
	state:SetAttribute("Mode", "1v1")
	state:SetAttribute("Queued", 0)
	state.Parent = stateRoot
	local bots = Instance.new("Folder")
	bots.Name = id
	bots.Parent = botsRoot

	local queue: { Player } = {}
	local roster: { Entry } = {}
	local forfeit: TeamId? = nil
	local decided = false
	local lastElimination = ""
	local lastZone: Config.Zone? = nil -- zone of the latest elimination (for the payout)

	local function setPhase(phase: string)
		state:SetAttribute("Phase", phase)
	end

	local function setQueued()
		state:SetAttribute("Queued", #queue)
	end

	-- Banners go only to the people fighting here.
	local function banner(kind: string, data: { [string]: any })
		for _, e in roster do
			if e.player and e.player.Parent then
				Net.Banner:FireClient(e.player, kind, data)
			end
		end
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

	local hooks: Combatants.ArenaHooks
	local function living(team: TeamId): { Combatant }
		local out = {}
		for _, c in Combatants.all() do
			if c.arena == hooks and c.alive and c.team == team then
				table.insert(out, c)
			end
		end
		return out
	end

	-- Combat stops the instant a side is wiped out, so the survivors can't keep shooting into the end.
	local function latchIfWiped()
		if hooks.isLive() and (#living("Navy") == 0 or #living("Grey") == 0) then
			setPhase("RoundEnd")
		end
	end

	hooks = {
		id = id,
		boundsMin = info.boundsMin,
		boundsMax = info.boundsMax,
		-- Live only until the deadline the HUD shows, not until the round loop next wakes up.
		isLive = function()
			return state:GetAttribute("Phase") == "Live"
				and workspace:GetServerTimeNow() < (state:GetAttribute("RoundEndsAt") or 0)
		end,
		onElimination = function(victim, attacker, zone)
			-- Only a kill by someone else can make the deciding elimination a headshot.
			lastZone = if attacker and attacker ~= victim then zone else nil
			if attacker and attacker ~= victim then
				lastElimination = `{attacker.name} eliminated {victim.name}`
					.. (if zone == "Head" then " with a HEADSHOT" else "")
			end
			latchIfWiped()
		end,
	}

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
					local kit = if sudden then Loadout.suddenDeath(roles[i], e.player) else Loadout.standard(e.player)
					Combat.arm(c, kit.weapons, kit.gadget)
				end
			end
		end
	end

	local function spawnEntry(entry: Entry, cf: CFrame): Combatant?
		local model: Model?
		local ok, err = pcall(function()
			if entry.player then
				entry.player.CameraMode = Enum.CameraMode.LockFirstPerson
				entry.player:SetAttribute("Team", entry.team)
				model = Rig.spawnPlayer(entry.player, entry.team, cf)
			else
				model = Rig.spawnBot(entry.team, entry.name, cf, bots, entry.userId)
			end
		end)
		if not ok then
			warn(`[Arena {id}] could not spawn {entry.name}: {err}`)
		end
		if not model then
			return nil
		end
		local c = Combatants.new(hooks, entry.name, entry.player, entry.team, model, cf)
		c.root.Anchored = true
		c.humanoid.Died:Once(function()
			if c.alive then
				c.alive = false
				lastElimination = `{c.name} was eliminated`
				lastZone = nil
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

	local function clearField()
		Combatants.clear(hooks)
		Gadgets.reset(id)
		bots:ClearAllChildren()
	end

	local function playRound(round: number, scores: Scores): Result?
		clearField()
		lastElimination = ""
		lastZone = nil
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
			entry.combatant = spawnEntry(entry, cf)
			if not entry.combatant then
				-- They left mid-spawn or their character failed to load: a bot stands in for this round.
				local standIn: Entry = { player = nil, team = entry.team, name = `{Config.Bot.Name} (stand-in)` }
				entry.combatant = spawnEntry(standIn, cf)
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
			if c.arena == hooks and c.root.Parent then
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
		latchIfWiped() -- someone who reset or left during the freeze already lost this round

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

	-- Noelle's rules: the winners earn 120 if the match-winning elimination was a headshot, else 80
	-- (a forfeit win counts as 80); the losers earn 10 for each round they won.
	local function payout(winner: TeamId, scores: Scores, headshot: boolean)
		local P = Config.Payouts
		for _, e in roster do
			local player = e.player
			if player and player.Parent then
				if e.team == winner then
					local amount = if headshot then P.WinHeadshot else P.WinBody
					Economy.award(player, amount, if headshot then "Headshot win!" else "Victory!")
				elseif scores[e.team] > 0 then
					Economy.award(player, P.LoserPerRound * scores[e.team], `{scores[e.team]} round(s) won`)
				end
			end
		end
	end

	local function playMatch()
		local scores: Scores = { Navy = 0, Grey = 0 }
		state:SetAttribute("NavyScore", 0)
		state:SetAttribute("GreyScore", 0)
		state:SetAttribute("NavyName", teamNames("Navy"))
		state:SetAttribute("GreyName", teamNames("Grey"))
		state:SetAttribute("Winner", nil)
		local humans = {}
		for _, e in roster do
			if e.player then
				table.insert(humans, e.player)
			end
		end
		Loadout.resetRoles(humans)

		local round = 0
		local result: Result? = nil
		while scores.Navy < Config.RoundsToWin and scores.Grey < Config.RoundsToWin and not forfeit do
			round += 1
			result = playRound(round, scores)
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
		banner("MatchEnd", { winner = winner, navy = scores.Navy, grey = scores.Grey, forfeit = not decided })
		payout(winner, scores, decided and lastZone == "Head")
		-- The fight is over: the celebration stage replaces the field for everyone in the match.
		clearField()
		local members: { Celebration.Member } = {}
		for _, e in roster do
			local player = if e.player and e.player.Parent then e.player else nil
			local kit = Loadout.standard(player)
			table.insert(members, {
				player = player,
				team = e.team,
				name = e.name,
				userId = e.userId,
				primary = kit.weapons[1],
				melee = kit.weapons[3],
			})
		end
		local center = (info.boundsMin + info.boundsMax) / 2
		local ground = Vector3.new(center.X, info.boundsMin.Y + 12, center.Z)
		local focus, finish = Celebration.play(ground, winner, members, bots)
		banner("Celebrate", { focus = focus, seconds = Config.MatchEndSeconds })
		task.wait(Config.MatchEndSeconds)
		finish()
		clearField()
		local leaving = roster
		roster = {}
		for _, e in leaving do
			if e.player and e.player.Parent then
				task.spawn(toLobby, e.player)
			end
		end
	end

	-- The first players in the queue fill the teams (alternating Navy, Grey) and leave the queue;
	-- bots take the empty slots. Anyone still queued waits for the next match.
	local function pickRoster(): boolean
		while #queue == 0 do
			setPhase("Waiting")
			task.wait(0.5)
		end
		state:SetAttribute("StartsAt", workspace:GetServerTimeNow() + Config.QueueSeconds)
		setPhase("Starting")
		local starts = os.clock() + Config.QueueSeconds
		local perTeam = 1
		while os.clock() < starts do
			perTeam = if state:GetAttribute("Mode") == "2v2" then 2 else 1
			if #queue == 0 then
				return false -- everyone left during the countdown
			elseif #queue >= perTeam * 2 then
				break -- full: no need to wait
			end
			task.wait(0.2)
		end
		-- A new match: from here a leaver's side can forfeit (Friends.pick below may yield).
		forfeit = nil
		decided = false
		roster = {}
		local botNumber = 0
		local humans: { Player } = {}
		local botEntries: { Entry } = {}
		for i = 1, perTeam * 2 do
			local team: TeamId = if i % 2 == 1 then "Navy" else "Grey"
			local player = table.remove(queue, 1)
			if player then
				player:SetAttribute("Queued", nil)
				player:SetAttribute("Arena", id)
				table.insert(humans, player)
				table.insert(roster, { player = player, team = team, name = player.DisplayName } :: Entry)
			else
				botNumber += 1
				local name = if perTeam == 1 then Config.Bot.Name else `{Config.Bot.Name} {botNumber}`
				local entry: Entry = { player = nil, team = team, name = name }
				table.insert(roster, entry)
				table.insert(botEntries, entry)
			end
		end
		-- Bots wear the avatars and names of the players' friends, so it feels like a real opponent.
		if #botEntries > 0 then
			for i, friend in Friends.pick(humans, #botEntries) do
				botEntries[i].userId = friend.userId
				botEntries[i].name = friend.name
			end
		end
		setQueued()
		return true
	end

	local arena: Arena = {
		id = id,
		join = function(player, mode)
			if table.find(queue, player) then
				return
			end
			-- The first in line picks the mode; it stays fixed while the next match is assembling.
			if #queue == 0 and state:GetAttribute("Phase") ~= "Starting" then
				state:SetAttribute("Mode", if mode == "2v2" then "2v2" else "1v1")
			end
			table.insert(queue, player)
			player:SetAttribute("Queued", id)
			setQueued()
		end,
		leave = function(player)
			local i = table.find(queue, player)
			if i then
				table.remove(queue, i)
				player:SetAttribute("Queued", nil)
				setQueued()
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
		end,
		-- Picks made during the freeze show up immediately (the screen previews the real kit).
		loadoutChanged = function(player)
			if state:GetAttribute("Phase") == "Freeze" and inRoster(player) then
				armAll()
			end
		end,
	}

	task.spawn(function()
		while true do
			if pickRoster() then
				playMatch()
			end
			task.wait()
		end
	end)
	return arena
end

return Arena
