--!strict
-- One arena per map, all running at once. Players queue for a map and a mode (1v1 or 2v2) from the
-- Camp More Maniar lobby; each mode and ranked setting has its own queue per map (bots fill empty
-- slots in casual ones). A match is first to 5 round wins. Each round:
-- an 8-second freeze to pick a loadout, 2:00 live, then a win, loss or draw. Sides swap every round;
-- at 4-4 each team plays Sudden Death with one sniper and one knife. A player who leaves or concedes is
-- replaced by a bot and the match counts as their loss; a team with no players left forfeits. After the match
-- everyone returns to the lobby. A player in Bot Bootcamp only ever plays alone against perfect bots.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AntiCheat = require(script.Parent.AntiCheat)
local Bot = require(script.Parent.Bot)
local Celebration = require(script.Parent.Celebration)
local Combat = require(script.Parent.Combat)
local Combatants = require(script.Parent.Combatants)
local Drop = require(script.Parent.Drop)
local Config = require(ReplicatedStorage.Shared.Config)
local Economy = require(script.Parent.Economy)
local Friends = require(script.Parent.Friends)
local Gadgets = require(script.Parent.Gadgets)
local Loadout = require(script.Parent.Loadout)
local MapKit = require(script.Parent.Maps.MapKit)
local Net = require(script.Parent.Net)
local Report = require(script.Parent.Report)
local Rig = require(script.Parent.Rig)

type Combatant = Combatants.Combatant
type TeamId = Config.TeamId
-- `userId` on a bot entry: the friend whose avatar and name the bot wears. `paid`: their result is committed.
type Entry = {
	player: Player?,
	team: TeamId,
	name: string,
	combatant: Combatant?,
	userId: number?,
	paid: boolean?,
}
type Result = TeamId | "Draw"
type Scores = { Navy: number, Grey: number }

export type Arena = {
	id: string,
	join: (player: Player, mode: string) -> (),
	leave: (player: Player) -> (), -- leaving the queue, or the game mid-match
	concede: (player: Player) -> (), -- giving up mid-match (the round-end screen): a loss, then the lobby
	loadoutChanged: (player: Player) -> (),
}

local Arena = {}

local stateRoot = Instance.new("Folder")
stateRoot.Name = "Arenas"
stateRoot.Parent = ReplicatedStorage
local botsRoot = Instance.new("Folder")
botsRoot.Name = "Bots"
botsRoot.Parent = workspace
-- Drop-in vehicles and cutscene stand-ins, one folder per arena.
local stagingRoot = Instance.new("Folder")
stagingRoot.Name = "Staging"
stagingRoot.Parent = workspace
local random = Random.new()

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
	local rides = Instance.new("Folder")
	rides.Name = id
	rides.Parent = stagingRoot

	local queue: { Player } = {}
	local modeOf: { [Player]: string } = {} -- each queued player's chosen mode
	local joinedAt: { [Player]: number } = {} -- server time each queued player joined
	local roster: { Entry } = {}
	local scores: Scores = { Navy = 0, Grey = 0 }
	local rankedMatch = false -- every slot is a real player who entered ranked (fixed at the roster pick)
	local forfeit: TeamId? = nil
	local decided = false
	local lastElimination = ""
	local lastZone: Config.Zone? = nil -- zone of the latest elimination (for the payout)
	-- The latest elimination by someone else, for the round-end cutscenes (bullet cam, finisher).
	local lastKill: { attacker: Combatant, victim: Combatant, weapon: string?, from: Vector3, to: Vector3 }? = nil
	local kills: { [Player]: number } = {} -- eliminations this match, for XP
	local matchStart = 0 -- os.clock() when the match began, for counting flags
	local perfectBots = false -- a Bot Bootcamp match: every bot plays perfectly
	local endCelebration: (() -> ())? = nil -- tears down a celebration in progress

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
		onElimination = function(victim, attacker, zone, weapon)
			-- Only a gun kill by someone else can make the deciding elimination a headshot.
			local gun = weapon ~= nil and Config.Weapons[weapon] ~= nil and Config.Weapons[weapon].kind == "gun"
			lastZone = if attacker and attacker ~= victim and gun then zone else nil
			if attacker and attacker ~= victim then
				if attacker.player then
					kills[attacker.player] = (kills[attacker.player] or 0) + 1
				end
				lastElimination = `{attacker.name} eliminated {victim.name}`
					.. (if lastZone == "Head" then " with a HEADSHOT" else "")
				lastKill = {
					attacker = attacker,
					weapon = weapon,
					victim = victim,
					-- The decisive pellet's real path (Combat.fire records it first), else head to head.
					from = gun and attacker.lastShotFrom or Combat.headPosition(attacker),
					to = gun and attacker.lastShotHit or Combat.headPosition(victim),
				}
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
		local player, name = entry.player, entry.name
		local ok, err = pcall(function()
			if player then
				player.CameraMode = Enum.CameraMode.LockFirstPerson
				player:SetAttribute("Team", entry.team)
				model = Rig.spawnPlayer(player, entry.team, cf)
			else
				model = Rig.spawnBot(entry.team, name, cf, bots, entry.userId)
			end
		end)
		if not ok then
			warn(`[Arena {id}] could not spawn {name}: {err}`)
		end
		if player and entry.player ~= player then
			-- They left while their character loaded: a bot takes the slot instead.
			if model then
				model:Destroy()
				-- If they conceded mid-load, this was their only character: send them back again
				-- (toLobby's newest call wins).
				if player.Parent and player:GetAttribute("Arena") == nil then
					task.spawn(toLobby, player)
				end
			end
			player, name, model = nil, entry.name, nil
			pcall(function()
				model = Rig.spawnBot(entry.team, name, cf, bots, entry.userId)
			end)
		end
		if not model then
			return nil
		end
		local c = Combatants.new(hooks, name, player, entry.team, model, cf)
		c.root.Anchored = true
		c.humanoid.Died:Once(function()
			if c.alive then
				c.alive = false
				lastElimination = `{c.name} was eliminated`
				lastZone = nil
			end
			latchIfWiped()
		end)
		if not player then
			task.spawn(Bot.run, c, info.waypoints, function()
				return living(other(c.team))
			end, perfectBots)
		end
		return c
	end

	local function clearField()
		Combatants.clear(hooks)
		Gadgets.reset(id)
		bots:ClearAllChildren()
		rides:ClearAllChildren()
	end

	-- Cutscenes play on the clients, but the server starts them and holds the next round until every
	-- player in the match has reported finishing (or a grace period passes). Stale tokens are ignored.
	local cutsceneToken = 0
	local waiting: { [Player]: boolean } = {}
	Net.CutsceneDone.OnServerEvent:Connect(function(player, t)
		-- Charged before any check, so malformed or stale acknowledgments still cost the sender.
		if
			Net.allow(player, "CutsceneDone", 4, 4)
			and type(t) == "number"
			and t == cutsceneToken
			and waiting[player]
		then
			waiting[player] = nil
		end
	end)
	local function cutscene(kind: string, data: { [string]: any }, seconds: number)
		if forfeit then
			return -- the match is already over
		end
		cutsceneToken += 1
		data.token, data.seconds = cutsceneToken, seconds
		table.clear(waiting)
		for _, e in roster do
			if e.player and e.player.Parent then
				waiting[e.player] = true
				Net.Cutscene:FireClient(e.player, kind, data)
			end
		end
		local started = os.clock()
		local deadline = started + seconds + Config.CutsceneGraceSeconds
		while os.clock() < deadline and not forfeit do
			for player in waiting do
				if player.Parent == nil then
					waiting[player] = nil
				end
			end
			local elapsed = os.clock() - started
			-- Never before the scene's full length, so nobody skips the ending.
			if next(waiting) == nil and elapsed >= seconds then
				break
			end
			task.wait(0.1)
		end
		table.clear(waiting)
	end

	local function characters(): { Instance }
		local list: { Instance } = { bots, rides }
		for _, e in roster do
			if e.player and e.player.Character then
				table.insert(list, e.player.Character)
			end
		end
		return list
	end

	-- Anime finisher: freeze frame with the round's winner standing over the player they beat.
	local function finisher(winner: TeamId): boolean
		local kill = lastKill
		local victor = if kill
				and kill.attacker.team == winner
				and kill.attacker.alive
			then kill.attacker
			else living(winner)[1]
		local defeated = if kill and kill.victim.team ~= winner then kill.victim else nil
		if not defeated then
			for _, e in roster do
				local c = e.combatant
				if c and c.team ~= winner and not c.alive then
					defeated = c
				end
			end
		end
		if not victor or not defeated or not victor.root.Parent or not defeated.root.Parent then
			return false
		end
		local at = defeated.root.Position
		local away = (victor.root.Position - at) * Vector3.new(1, 0, 1)
		local dir = if away.Magnitude > 0.1 then away.Unit else Vector3.xAxis
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = characters()
		local function clear(from: Vector3, to: Vector3): boolean
			return workspace:Raycast(from, to - from, params) == nil
		end
		local floor = workspace:Raycast(at + Vector3.new(0, 4, 0), Vector3.new(0, -20, 0), params)
		local base = Vector3.new(at.X, (if floor then floor.Position.Y else at.Y - 1) + 3, at.Z)
		local lift = Vector3.new(0, 1.2, 0) -- the camera aims this far above the pair's midpoint
		-- Eight angles around the defeated player, nearest the victor's side first: the victor needs open
		-- floor 3.5 studs out and the camera, 10 studs to either side, a clear view of both. Failing
		-- that, the victor stands as far out as cover allows and the camera looks straight down.
		local function stage(): (Vector3, Vector3, boolean)
			for _, step in { 0, 1, -1, 2, -2, 3, -3, 4 } do
				local d = CFrame.Angles(0, step * math.pi / 4, 0):VectorToWorldSpace(dir)
				local spot = base + d * 3.5
				if clear(at, at + d * 4.5) and not clear(spot, spot - Vector3.new(0, 6, 0)) then
					local mid = (spot + at) / 2
					local right = d:Cross(Vector3.yAxis)
					for _, side in { right, -right } do
						local camera = mid + side * 10 - Vector3.new(0, 1.3, 0)
						if clear(mid + lift, camera) then
							return spot, camera, false
						end
					end
				end
			end
			local wall = workspace:Raycast(at, dir * 4.5, params)
			local spot = base + dir * (if wall then math.max(wall.Distance - 1, 1.5) else 3.5)
			local target = (spot + at) / 2 + lift
			local roof = workspace:Raycast(target, Vector3.new(0, 14, 0), params)
			return spot, target + Vector3.new(0, if roof then math.max(roof.Distance - 1, 2) else 14, 0), true
		end
		local stand, camera, overhead = stage()
		victor.root.Anchored = true
		victor.root.CFrame = CFrame.lookAt(stand, Vector3.new(at.X, stand.Y, at.Z))
		cutscene("Finisher", {
			winnerName = victor.name,
			ink = Economy.finisherInk(victor.player),
			winnerTeam = winner,
			defeatedName = defeated.name,
			winnerPos = stand,
			defeatedPos = at,
			focus = (stand + at) / 2 + lift,
			camera = camera,
			overhead = overhead,
		}, 3.2)
		return true
	end

	-- Draw: each Navy fighter pairs with the Grey fighter at the same roster slot, side by side on a
	-- small stage above the arena, and they shake hands. Stand-ins work even when both sides were eliminated.
	local function handshake()
		local middle = (info.boundsMin + info.boundsMax) / 2
		local center = Vector3.new(middle.X, info.boundsMin.Y + 12 + 140, middle.Z)
		local pad = Instance.new("Part")
		pad.Anchored, pad.Size = true, Vector3.new(36, 1, 18)
		pad.CFrame = CFrame.new(center - Vector3.new(0, 0.5, 0))
		pad.Material, pad.Color = Enum.Material.Concrete, Color3.fromRGB(120, 116, 108)
		pad.Parent = rides
		local actors: { { model: Model, side: number, x: number } } = {}
		local slots: { [TeamId]: number } = { Navy = 0, Grey = 0 }
		local count = 0
		for _, e in roster do
			slots[e.team] += 1
			count = math.max(count, slots[e.team])
		end
		slots = { Navy = 0, Grey = 0 }
		for _, e in roster do
			slots[e.team] += 1
			local side = if e.team == "Navy" then -1 else 1
			local x = (slots[e.team] - (count + 1) / 2) * 6
			local start = center + Vector3.new(x, 3, side * 10)
			local userId = if e.player then e.player.UserId else e.userId
			local cf = CFrame.lookAt(start, center + Vector3.new(x, 3, 0))
			local ok, model = pcall(Rig.spawnBot, e.team, e.name, cf, rides, userId)
			local actorRoot = if ok and model then model:FindFirstChild("HumanoidRootPart") else nil
			if actorRoot and actorRoot:IsA("BasePart") then
				model.PrimaryPart = actorRoot
				actorRoot.Anchored = true
				table.insert(actors, { model = model, side = side, x = x })
			elseif ok and model then
				model:Destroy()
			end
		end
		task.spawn(function()
			local runs = {}
			for _, a in actors do
				table.insert(runs, Rig.animate(a.model, "run", true))
			end
			local steps = 36
			for s = 1, steps do
				for _, a in actors do
					if a.model.Parent then
						local z = a.side * (10 - 8.4 * s / steps)
						local p = center + Vector3.new(a.x, 3, z)
						a.model:PivotTo(CFrame.lookAt(p, p - Vector3.new(0, 0, a.side)))
					end
				end
				task.wait(0.05)
			end
			for _, track in runs do
				if track then
					track:Stop(0.2)
				end
			end
			-- Right arms out to meet in the middle, then a few shakes.
			local shoulders = {}
			for _, a in actors do
				local arm = a.model:FindFirstChild("RightUpperArm")
				local joint = arm and arm:FindFirstChild("RightShoulder")
				if joint and joint:IsA("Motor6D") then
					table.insert(shoulders, { joint = joint, rest = joint.C0 })
				end
			end
			for beat = 0, 16 do
				for _, s in shoulders do
					if s.joint.Parent then
						local bob = if beat > 3 then math.sin(beat * 1.6) * 0.12 else 0
						s.joint.C0 = s.rest * CFrame.Angles(math.rad(75) + bob, 0, 0)
					end
				end
				task.wait(0.1)
			end
		end)
		cutscene("Handshake", { center = center }, 4.5)
		for _, a in actors do
			a.model:Destroy()
		end
		pad:Destroy()
	end

	-- The round's cutscenes: a headshot win gets the bullet cam first, every win gets the finisher,
	-- and a draw gets the handshake. Returns false when nothing could be staged.
	local function roundCutscenes(result: Result): boolean
		if result == "Draw" then
			handshake()
			return true
		end
		local kill = lastKill
		local gun = kill and kill.weapon and Config.Weapons[kill.weapon]
		if lastZone == "Head" and kill and gun and gun.kind == "gun" and kill.attacker.team == result then
			cutscene("BulletCam", {
				from = kill.from,
				to = kill.to,
				shooterName = kill.attacker.name,
				victimName = kill.victim.name,
			}, 2.6)
		end
		return finisher(result :: TeamId)
	end

	local function playRound(round: number): Result?
		clearField()
		Report.roundStart(id, `{id}_{math.floor(matchStart)}`, round)
		lastElimination = ""
		lastZone = nil
		lastKill = nil
		local navySide = if round % 2 == 1 then "A" else "B"
		state:SetAttribute("Round", round)
		state:SetAttribute("NavySide", navySide)
		local sudden = scores.Navy == Config.SuddenDeathAt and scores.Grey == Config.SuddenDeathAt
		state:SetAttribute("SuddenDeath", sudden)
		setPhase("Freeze")

		local slots = { Navy = 0, Grey = 0 }
		local navyRide: Drop.Group = { team = "Navy", spawns = {}, riders = {} }
		local greyRide: Drop.Group = { team = "Grey", spawns = {}, riders = {} }
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
			if entry.combatant then
				local group = if entry.team == "Navy" then navyRide else greyRide
				table.insert(group.spawns, cf)
				table.insert(group.riders, entry.combatant)
			end
		end
		-- A side that can't field anyone loses the match rather than leaving a one-sided round.
		for _, g in { navyRide, greyRide } do
			if #g.riders == 0 and not forfeit then
				forfeit = g.team
			end
		end
		armAll()
		-- Each round everyone arrives by one random drop-in; the loadout pick happens during the ride.
		local drop = Drop.KINDS[random:NextInteger(1, #Drop.KINDS)]
		state:SetAttribute("Drop", drop)
		state:SetAttribute("FreezeEndsAt", workspace:GetServerTimeNow() + Config.FreezeSeconds)
		banner("RoundStart", { round = round, sudden = sudden, navySide = navySide, drop = drop })
		local landed = false
		local freezeEnds = os.clock() + Config.FreezeSeconds + 1
		task.spawn(function()
			Drop.run(drop, { navyRide, greyRide }, Config.FreezeSeconds, rides, function()
				return landed or forfeit ~= nil or os.clock() >= freezeEnds
			end)
			landed = true
		end)
		while not landed and os.clock() < freezeEnds and not forfeit do
			task.wait(0.05)
		end
		landed = true
		for _, g in { navyRide, greyRide } do
			for i, c in g.riders do
				if c.root.Parent then
					c.root.CFrame = g.spawns[i] or g.spawns[1]
				end
			end
		end
		if forfeit then
			-- Removing the vehicles ends the ride for anyone still aboard.
			rides:ClearAllChildren()
			Report.roundEnd(id)
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
		Report.roundEnd(id)
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
	-- (a forfeit win counts as 80); the losers earn 10 for each round they won. Everyone who finishes
	-- earns XP (more for a win and per elimination), and ranked players gain or lose rank points. Each
	-- player is paid once, as soon as the result is known: at the fifth point, before the closing scenes.
	local function loserCoins(player: Player, team: TeamId)
		local won = scores[team]
		if won > 0 then
			Economy.award(player, Config.Payouts.LoserPerRound * won, `{won} round(s) won`)
		end
	end

	local function payout(winner: TeamId, headshot: boolean)
		local P, X = Config.Payouts, Config.Xp
		for _, e in roster do
			local player = e.player
			if player and player.Parent and not e.paid then
				e.paid = true
				local won = e.team == winner
				if won then
					local amount = if headshot then P.WinHeadshot else P.WinBody
					Economy.award(player, amount, if headshot then "Headshot win!" else "Victory!")
				else
					loserCoins(player, e.team)
				end
				local earned = X.Elimination * (kills[player] or 0)
				Economy.awardXp(player, X.Finish + (if won then X.Win else 0) + earned)
				if rankedMatch then
					Economy.ranked(player, won)
				end
				Economy.matchResult(player, won, AntiCheat.flagsSince(player, matchStart) == 0)
			end
		end
	end

	local function playMatch()
		table.clear(kills)
		matchStart = os.clock()
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
			result = playRound(round)
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
			-- The fifth point locks the result and pays it out; leaving during the scenes can't flip or lose it.
			decided = scores.Navy >= Config.RoundsToWin or scores.Grey >= Config.RoundsToWin
			if decided then
				local champion: TeamId = if scores.Navy >= Config.RoundsToWin then "Navy" else "Grey"
				payout(champion, lastZone == "Head")
			end
			banner("RoundEnd", { winner = result, detail = lastElimination, cutscene = true })
			if not roundCutscenes(result :: Result) then
				local resume = os.clock() + Config.RoundEndSeconds
				while os.clock() < resume and not forfeit do -- a concede here ends the match at once
					task.wait(0.1)
				end
			end
		end

		-- A forfeit gives the other side the match; otherwise the side that reached RoundsToWin wins.
		local winner: TeamId = if forfeit then other(forfeit) elseif scores.Navy > scores.Grey then "Navy" else "Grey"
		decided = true
		setPhase("MatchEnd")
		state:SetAttribute("Winner", winner)
		banner("MatchEnd", { winner = winner, navy = scores.Navy, grey = scores.Grey, forfeit = forfeit ~= nil })
		payout(winner, not forfeit and lastZone == "Head")
		table.clear(kills)
		lastKill = nil
		-- The fight is over: the celebration stage replaces the field for everyone in the match.
		clearField()
		do
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
			endCelebration = finish
			banner("Celebrate", { focus = focus, seconds = Config.MatchEndSeconds })
			task.wait(Config.MatchEndSeconds)
			endCelebration = nil
			finish()
		end
		clearField()
		local leaving = roster
		roster = {}
		for _, e in leaving do
			if e.player and e.player.Parent then
				task.spawn(toLobby, e.player)
			end
		end
	end

	-- Each map has a separate queue per mode and ranked setting, oldest first. A queue starts as soon as
	-- it is full; a casual one also starts once its longest waiter has waited Config.QueueSeconds, with
	-- bots in the empty slots (a ranked one waits for real players). Teams alternate Navy, Grey. A Bot
	-- Bootcamp player is a queue of their own: a 1v1 against perfect bots, at once.
	local function bucketOf(p: Player): string
		if p:GetAttribute("Bootcamp") == true then
			return "Bootcamp"
		end
		return modeOf[p] .. (if p:GetAttribute("Ranked") == true then " ranked" else "")
	end

	-- The first queue ready to start (none: empty): its players in line order and the players per team.
	local function readyBucket(): ({ Player }, number)
		local seen: { [string]: boolean } = {}
		for _, first in queue do
			local key = bucketOf(first)
			if key == "Bootcamp" then
				return { first }, 1
			elseif not seen[key] then
				seen[key] = true
				local perTeam = if modeOf[first] == "2v2" then 2 else 1
				local members = {}
				for _, p in queue do
					if #members < perTeam * 2 and bucketOf(p) == key then
						table.insert(members, p)
					end
				end
				local timedOut = workspace:GetServerTimeNow() >= joinedAt[first] + Config.QueueSeconds
				if #members == perTeam * 2 or (timedOut and first:GetAttribute("Ranked") ~= true) then
					return members, perTeam
				end
			end
		end
		return {}, 1
	end

	local function dequeue(player: Player)
		local i = table.find(queue, player)
		modeOf[player], joinedAt[player] = nil, nil
		if i then
			table.remove(queue, i)
			player:SetAttribute("Queued", nil)
			player:SetAttribute("QueuedMode", nil)
			setQueued()
		end
	end

	local function pickRoster()
		local picked, perTeam = readyBucket()
		while #picked == 0 do
			-- The lobby shows the longest waiter's queue and when it fills with bots.
			local first = queue[1]
			if first then
				state:SetAttribute("Mode", modeOf[first])
				state:SetAttribute("Ranked", first:GetAttribute("Ranked") == true)
				state:SetAttribute("StartsAt", joinedAt[first] + Config.QueueSeconds)
			end
			setPhase(if first then "Starting" else "Waiting")
			task.wait(0.2)
			picked, perTeam = readyBucket()
		end
		-- A new match: from here a leaver's side can forfeit (Friends.pick below may yield).
		forfeit = nil
		decided = false
		roster = {}
		scores = { Navy = 0, Grey = 0 }
		perfectBots = bucketOf(picked[1]) == "Bootcamp"
		-- A ranked queue only starts full, so every slot is a real player who entered ranked.
		rankedMatch = not perfectBots and picked[1]:GetAttribute("Ranked") == true
		state:SetAttribute("Mode", if perTeam == 2 then "2v2" else "1v1")
		state:SetAttribute("Ranked", rankedMatch)
		state:SetAttribute("Bootcamp", perfectBots)
		local botNumber = 0
		local humans: { Player } = {}
		local botEntries: { Entry } = {}
		for i = 1, perTeam * 2 do
			local team: TeamId = if i % 2 == 1 then "Navy" else "Grey"
			local player = picked[i]
			if player then
				dequeue(player)
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
	end

	local arena: Arena
	arena = {
		id = id,
		join = function(player, mode)
			if table.find(queue, player) then
				return
			end
			modeOf[player] = if mode == "2v2" then "2v2" else "1v1"
			joinedAt[player] = workspace:GetServerTimeNow()
			table.insert(queue, player)
			player:SetAttribute("Queued", id)
			player:SetAttribute("QueuedMode", modeOf[player])
			setQueued()
		end,
		leave = function(player)
			dequeue(player)
			local entry = inRoster(player)
			if not entry or decided or entry.paid or state:GetAttribute("Phase") == "MatchEnd" then
				return
			end
			-- Leaving mid-match settles the leaver now: a saved loss with the loser's coins for the rounds
			-- their team has won so far (and rank points in a ranked match, which stays ranked for the
			-- rest). The leaver's slot goes to a bot from next round on.
			loserCoins(player, entry.team)
			if rankedMatch then
				Economy.ranked(player, false)
			end
			Economy.matchResult(player, false, false)
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
		-- The same saved loss as leaving the game (a team left with no players forfeits the match at
		-- once), then straight back to the lobby. Once the result is decided there is nothing to concede.
		concede = function(player)
			local entry = inRoster(player)
			local c = entry and entry.combatant
			arena.leave(player)
			if entry and entry.player == nil then
				if c and c.player == player then
					Combatants.remove(c) -- so it no longer answers for this player in the lobby
				end
				waiting[player] = nil -- the scene in progress no longer waits on them
				task.spawn(toLobby, player)
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
			pickRoster()
			local ok = xpcall(playMatch, function(err)
				warn(`[Arena {id}] match failed: {err}\n{debug.traceback()}`)
			end)
			if not ok then
				if endCelebration then
					pcall(endCelebration)
					endCelebration = nil
				end
				Report.roundEnd(id) -- a round that errored still closes its recording
				pcall(clearField)
				table.clear(kills)
				lastKill = nil
				for _, key in { "RoundEndsAt", "FreezeEndsAt", "Winner", "SuddenDeath" } do
					state:SetAttribute(key, nil)
				end
				setPhase("Waiting")
				local leaving = roster
				roster = {}
				for _, e in leaving do
					if e.player and e.player.Parent then
						e.player:SetAttribute("Celebrating", nil)
						task.spawn(toLobby, e.player)
					end
				end
			end
			task.wait()
		end
	end)
	return arena
end

return Arena
