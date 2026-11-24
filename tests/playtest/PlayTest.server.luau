-- Game test, server side. Runs in the test place only (tests/playtest/default.project.json), never in
-- the shipped game. It drives the steps (the client test follows the "TestStep" player attribute),
-- watches real play, and ends rounds through the normal damage path. It only shortcuts what a player
-- couldn't do in time: shorter queues and matches (restored at the end), XP and the title for unlocks,
-- and placing a bot where a stab or a grenade can reach it.
-- Every result is a log line: "PLAYTEST PASS <name>", "PLAYTEST FAIL <name>: <why>", "PLAYTEST DONE".
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Server = ServerScriptService:WaitForChild("Server")
local Combat = require(Server:WaitForChild("Combat"))
local Combatants = require(Server:WaitForChild("Combatants"))
local Economy = require(Server:WaitForChild("Economy"))
local Report = require(Server:WaitForChild("Report"))
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Profile = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Profile"))
-- Config values the test shortens; restored before it finishes.
local defaults = {
	RoundsToWin = Config.RoundsToWin,
	SuddenDeathAt = Config.SuddenDeathAt,
	QueueSeconds = Config.QueueSeconds,
}

local function result(name: string, ok: boolean, why: any?)
	print(if ok then `PLAYTEST PASS {name}` else `PLAYTEST FAIL {name}: {tostring(why)}`)
end

local function waitFor(seconds: number, check: () -> boolean): boolean
	local deadline = os.clock() + seconds
	while os.clock() < deadline do
		if check() then
			return true
		end
		task.wait(0.1)
	end
	return check()
end

local player = Players.PlayerAdded:Wait()
-- Trace the attributes that steer the flow, so a failure can be read from the log.
for _, key in { "Arena", "Queued", "Team", "Weapon", "PickPrimary", "Celebrating" } do
	player:GetAttributeChangedSignal(key):Connect(function()
		print(`PLAYTEST TRACE {string.format("%.1f", os.clock())} {key}={tostring(player:GetAttribute(key))}`)
	end)
end
local arenas = ReplicatedStorage:WaitForChild("Arenas")

local steps = 0
local function step(name: string)
	steps += 1
	player:SetAttribute("TestStep", `{name}:{steps}`) -- unique, so repeating a step still signals
end
local function root(): BasePart?
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
end
local function inLobby(): boolean
	local r = root()
	return player:GetAttribute("Arena") == nil and r ~= nil and r.Position.Z < -1400
end
local function combatantsOf(arena: string): { Combatants.Combatant }
	local out = {}
	for _, c in Combatants.all() do
		if c.arena.id == arena then
			table.insert(out, c)
		end
	end
	return out
end
local function botOf(arena: string): Combatants.Combatant?
	for _, c in combatantsOf(arena) do
		if not c.player and c.alive then
			return c
		end
	end
	return nil
end

-- Lobby ------------------------------------------------------------------------------------------
result("lobby: player spawns in Camp More Maniar", waitFor(25, inLobby))
for _, m in Config.Maps do
	local a = arenas:FindFirstChild(m.id)
	result(`arena {m.id} is waiting`, a ~= nil and a:GetAttribute("Phase") == "Waiting", a and a:GetAttribute("Phase"))
end
result(
	"settings: first join asks for HUD colors",
	player:GetAttribute("ThemePicked") == false,
	player:GetAttribute("ThemePicked")
)
step("PickTheme")
result(
	"settings: theme saved",
	waitFor(5, function()
		return player:GetAttribute("HudTheme") == "MidnightCyan" and player:GetAttribute("ThemePicked") == true
	end),
	player:GetAttribute("HudTheme")
)
result("starter: first join asks for a starter pick", player:GetAttribute("StarterPicked") == false)
step("PickStarter")
result(
	"starter: SMG in Forest Camo is the default primary",
	waitFor(5, function()
		return player:GetAttribute("StarterPicked") == true
			and player:GetAttribute("PickPrimary") == "SMG"
			and Profile.skin(player, "SMG") == "ForestCamo"
	end),
	`{player:GetAttribute("PickPrimary")} {Profile.skin(player, "SMG")}`
)
step("EquipFinisher")
result(
	"finisher: equip a finisher style",
	waitFor(5, function()
		return player:GetAttribute("Finisher") == "Thunder"
	end),
	player:GetAttribute("Finisher")
)

-- Practice range: stand at the first rack and take a weapon; then walk off the range.
local rangeFolder = workspace:WaitForChild("PracticeRange", 10)
local rack = rangeFolder and rangeFolder:FindFirstChildWhichIsA("Model")
local prompt = rack and rack:FindFirstChildWhichIsA("ProximityPrompt", true)
result("range: racks with prompts", prompt ~= nil)
if rack and root() then
	local at = rack:GetPivot().Position;
	(root() :: BasePart).CFrame = CFrame.lookAt(at + Vector3.new(0, 1.5, -3), at + Vector3.new(0, 1.5, 10))
	task.wait(0.5)
	step("TakeRackWeapon")
	result(
		"range: practicing with a weapon",
		waitFor(8, function()
			return player:GetAttribute("Arena") == "Practice" and player:GetAttribute("Weapon") ~= nil
		end),
		player:GetAttribute("Weapon")
	)
	local targets = 0
	for _, c in combatantsOf("Practice") do
		targets += if c.player then 0 else 1
	end
	result("range: target dummies standing", targets >= 3, targets)
	local target = rangeFolder:FindFirstChild("Target")
	local r = root()
	if target and r then
		r.CFrame = CFrame.lookAt(r.Position, Vector3.new(target:GetPivot().X, r.Position.Y, target:GetPivot().Z))
	end
	step("ShootTarget")
	task.wait(6)
	r = root()
	if r then
		r.CFrame = r.CFrame - Vector3.new(0, 0, 40) -- walk off the range toward the statue
	end
	result(
		"range: walking off ends practice",
		waitFor(5, function()
			return player:GetAttribute("Arena") == nil and player:GetAttribute("Team") == nil
		end),
		player:GetAttribute("Arena")
	)
end

-- Lobby features, before the first queue ---------------------------------------------------------
step("Leaderboard") -- the client reads the board's two columns
task.wait(0.5)

local theme = if player:GetAttribute("HudTheme") == Config.HudThemes[1].id
	then Config.HudThemes[2].id
	else Config.HudThemes[1].id
step(`Theme {theme}`)
result(
	"settings: HUD theme changes",
	waitFor(5, function()
		return player:GetAttribute("HudTheme") == theme
	end),
	player:GetAttribute("HudTheme")
)

result("ranked: locked below level 50", player:GetAttribute("RankedUnlocked") == false, player:GetAttribute("Level"))
step("Ranked on")
task.wait(1.5)
result(
	"ranked: the toggle is refused while locked",
	player:GetAttribute("Ranked") == false,
	player:GetAttribute("Ranked")
)

-- Shop. Developers own the whole catalog for free, so the test account shops as a regular player here.
local developer = Config.Developers[player.UserId]
Config.Developers[player.UserId] = nil
local STARTER_WEAPON, STARTER_COLOR = "SMG", "ForestCamo" -- the PickStarter step's choice
local skin = Config.Skins[1]
for _, s in Config.Skins do
	-- A tie skips the starter colour: the checks below need it unowned on other weapons.
	if s.price > 0 and s.id ~= STARTER_COLOR and (skin.price == 0 or s.price < skin.price) then
		skin = s
	end
end
local coins = player:GetAttribute("Coins") or 0
step(`Buy {skin.id}`)
result(
	`shop: {skin.name} costs {skin.price} coins`,
	waitFor(5, function()
		return player:GetAttribute("Coins") == coins - skin.price
	end),
	`{coins} -> {player:GetAttribute("Coins")}`
)
result(`shop: {skin.name} shows as owned`, Profile.owns(player, skin.id))
step(`EquipSkin AR {skin.id}`)
result(
	`shop: {skin.name} equipped on the Assault Rifle`,
	waitFor(5, function()
		return Profile.skin(player, "AR") == skin.id
	end),
	Profile.skin(player, "AR")
)
result(
	"starter: its colour shows as owned for the starter weapon",
	Profile.owns(player, `{STARTER_WEAPON}_{STARTER_COLOR}`)
)
result("starter: its colour isn't owned on other weapons", not Profile.owns(player, STARTER_COLOR))
step(`EquipSkin AR {STARTER_COLOR}`)
task.wait(1.5)
result(
	"starter: its colour can't go on another weapon",
	Profile.skin(player, "AR") == skin.id,
	Profile.skin(player, "AR")
)

local finisher = Config.Finishers[1]
for _, f in Config.Finishers do
	if f.price > 0 and (finisher.price == 0 or f.price < finisher.price) then
		finisher = f
	end
end
coins = player:GetAttribute("Coins") or 0
local wear = finisher
if coins >= finisher.price then
	step(`Buy Finisher_{finisher.id}`)
	result(
		`shop: {finisher.name} costs {finisher.price} coins`,
		waitFor(5, function()
			return player:GetAttribute("Coins") == coins - finisher.price
		end),
		`{coins} -> {player:GetAttribute("Coins")}`
	)
	result(`shop: {finisher.name} shows as owned`, Profile.owns(player, `Finisher_{finisher.id}`))
else
	print(`PLAYTEST INFO shop: the cheapest finisher, {finisher.name}, costs {finisher.price}; {coins} coins left`)
	step(`BuyBroke Finisher_{finisher.id}`) -- the client expects the "Not enough coins" toast
	task.wait(1.5)
	result(
		`shop: {finisher.name} refused without enough coins`,
		player:GetAttribute("Coins") == coins and not Profile.owns(player, `Finisher_{finisher.id}`),
		player:GetAttribute("Coins")
	)
	-- Equipping is still shown with a free finisher.
	for _, f in Config.Finishers do
		if f.price == 0 and f.id ~= player:GetAttribute("Finisher") then
			wear = f
			break
		end
	end
end
step(`WearFinisher {wear.id}`)
result(
	`finisher: {wear.name} equipped`,
	waitFor(5, function()
		return player:GetAttribute("Finisher") == wear.id
	end),
	player:GetAttribute("Finisher")
)
Config.Developers[player.UserId] = developer

-- Emotes: animations play on the character's Animator; "pose:" emotes turn the right shoulder.
local character = player.Character :: Model
local humanoid = character:FindFirstChildOfClass("Humanoid") :: Humanoid
local upperArm = character:FindFirstChild("RightUpperArm")
local shoulder = upperArm and upperArm:FindFirstChild("RightShoulder") :: Motor6D?
local rest = shoulder and shoulder.C0
local function posing(): boolean
	return character:GetAttribute("Posing") == true and shoulder ~= nil and shoulder.C0 ~= rest
end
local function trackPlaying(anim: string): boolean
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		return false
	end
	for _, track in animator:GetPlayingAnimationTracks() do
		if track.Animation and track.Animation.AnimationId == anim then
			return true
		end
	end
	return false
end
-- The Emote remote allows one a second, and a pose holds for 2 s.
local function emoteDone()
	task.wait(1.1)
	waitFor(3, function()
		return character:GetAttribute("Posing") == nil
	end)
end
local gold: typeof(Config.Emotes[1])? = nil
for _, e in Config.Emotes do
	if e.title then
		gold = e
		continue
	end
	local pose = string.sub(e.anim, 1, 5) == "pose:"
	step(`Emote {e.id}`)
	result(
		`emote: {e.name} ({e.id}) plays`,
		waitFor(3, function()
			return if pose then posing() else trackPlaying(e.anim)
		end),
		if pose then "no pose on the right shoulder" else "no AnimationTrack playing"
	)
	emoteDone()
end
if gold and gold.title then
	local title = gold.title
	step(`Emote {gold.id}`)
	result(
		"gold salute: refused below level 200",
		(player:GetAttribute("Level") or 0) < 200 and not waitFor(1.5, posing),
		player:GetAttribute("Level")
	)
	emoteDone()
	player:SetAttribute("Title", title) -- what Economy publishes at level 200
	local head = character:FindFirstChild("Head")
	result(
		"title: Eddie's Honor tag over the head",
		waitFor(5, function()
			local tag = head and head:FindFirstChild("TitleTag")
			return tag ~= nil and tag:IsA("BillboardGui")
		end)
	)
	step(`Emote {gold.id}`)
	result(
		"gold salute: plays with the title, with a gold glint",
		waitFor(3, function()
			local hand = character:FindFirstChild("RightHand")
			return posing() and hand ~= nil and hand:FindFirstChildOfClass("Sparkles") ~= nil
		end)
	)
	emoteDone()
	player:SetAttribute("Title", nil)
else
	result("gold salute: in the emote list", false, "no emote needs a title")
end

-- A full match on the Shooting Range ------------------------------------------------------------
local range = arenas:WaitForChild("ShootingRange")
step("QueueShootingRange")
result(
	"match: freeze starts",
	waitFor(60, function()
		return range:GetAttribute("Phase") == "Freeze"
	end),
	range:GetAttribute("Phase")
)
task.wait(2)
local staging = workspace:FindFirstChild("Staging")
local rides = staging and staging:FindFirstChild("ShootingRange")
result(
	`drop-in: {range:GetAttribute("Drop")} ride is on the map`,
	rides ~= nil and #rides:GetChildren() > 0,
	rides and #rides:GetChildren()
)
local r = root()
result("drop-in: riders can't act during the ride", r ~= nil and r.Anchored)
result(
	"drop-in: lands and the round goes live",
	waitFor(15, function()
		return range:GetAttribute("Phase") == "Live"
	end)
)
r = root()
result("drop-in: player free to move after landing", r ~= nil and not r.Anchored)

local bot = botOf("ShootingRange")
result("match: a bot is fighting", bot ~= nil)
if bot then
	local start = bot.root.Position
	local moved, shots = 0, 0
	local lastAmmo = bot.ammo[bot.weapons[1]]
	local deadline = os.clock() + 25
	local mine = Combatants.byPlayer(player)
	-- Stop as soon as the bot has shown it moves and shoots, or before it can take the round: the test
	-- player stands still, and the round must go to the test's headshot.
	while os.clock() < deadline and range:GetAttribute("Phase") == "Live" and bot.alive do
		task.wait(0.5)
		moved = math.max(moved, (bot.root.Position - start).Magnitude)
		local ammo = bot.ammo[bot.weapons[bot.equipped]]
		if ammo and lastAmmo and ammo < lastAmmo then
			shots += lastAmmo - ammo
		end
		lastAmmo = ammo
		local hurt = mine ~= nil and mine.humanoid.Health < 100
		if (moved > 8 and (shots > 0 or hurt)) or (mine ~= nil and mine.humanoid.Health < 50) then
			break
		end
	end
	result("bot: moves around (Shooting Range)", moved > 8, `{math.floor(moved)} studs`)
	local me = Combatants.byPlayer(player)
	result("bot: shoots at the player", shots > 0 or (me ~= nil and me.humanoid.Health < 100), shots)
	-- Round 1: a headshot win -> bullet cam, then the finisher.
	print(`PLAYTEST INFO round 1 kill: bot alive {bot.alive}, me {me ~= nil}`)
	if bot.alive and me then
		local killed = Combat.damage(bot, 999, me, "Head", "AR") -- a gun kill: only those get the bullet cam
		print(`PLAYTEST INFO round 1 headshot landed: {killed}`)
	end
end
result(
	"cutscene: next round waits for the cutscenes",
	waitFor(25, function()
		return range:GetAttribute("Phase") == "Freeze" and range:GetAttribute("Round") == 2
	end),
	range:GetAttribute("Phase")
)
step("ReportCutscenes")
task.wait(1)

-- Round 2: both sides knocked out at once -> a draw -> the handshake.
waitFor(20, function()
	return range:GetAttribute("Phase") == "Live"
end)
task.wait(Config.SpawnShieldSeconds + 0.5) -- spawn shields block damage for the first seconds
local me = Combatants.byPlayer(player)
bot = botOf("ShootingRange")
if bot and me then
	Combat.damage(bot, 999, me, "Body")
	Combat.damage(me, 999, bot, "Body")
end
result(
	"cutscene: handshake draw, then round 3",
	waitFor(25, function()
		return range:GetAttribute("Phase") == "Freeze" and range:GetAttribute("Round") == 3
	end),
	range:GetAttribute("Round")
)
step("ReportCutscenes")
task.wait(1)

-- Round 3 decides the match (first to 2 from here): finisher, celebration, back to the lobby.
Config.RoundsToWin = 2
waitFor(20, function()
	return range:GetAttribute("Phase") == "Live"
end)
task.wait(Config.SpawnShieldSeconds + 0.5)
me = Combatants.byPlayer(player)
bot = botOf("ShootingRange")
-- Retried until it lands: a spawn shield blocks damage, and the round must not go to the bot first.
print(`PLAYTEST INFO round 3: bot {bot ~= nil}, me {me ~= nil}, me alive {me and me.alive}`)
local landed = waitFor(10, function()
	return bot == nil or me == nil or not bot.alive or Combat.damage(bot, 999, me, "Body", "AR") ~= nil
end)
print(`PLAYTEST INFO round 3 kill landed {landed}, bot alive {bot and bot.alive}, me alive {me and me.alive}`)
result("match: ends after the deciding round", landed and waitFor(25, function()
	return range:GetAttribute("Phase") == "MatchEnd"
end), `{range:GetAttribute("Phase")} {range:GetAttribute("NavyScore")}-{range:GetAttribute("GreyScore")}`)
result(
	"celebration: stage appears",
	waitFor(8, function()
		return workspace:FindFirstChild("Celebration") ~= nil
	end)
)
result("after match: back in the lobby", waitFor(Config.MatchEndSeconds + 15, inLobby))
result("progression: XP earned for the match", (player:GetAttribute("XP") or 0) > 0, player:GetAttribute("XP"))
result(
	"after match: arena ready again",
	waitFor(5, function()
		return range:GetAttribute("Phase") == "Waiting"
	end),
	range:GetAttribute("Phase")
)
step("ReportCutscenes")
task.wait(1)

-- REPORT from the lobby saves the round just played (in Studio without DataStore access, in memory).
step("SendReport")
result(
	"report: last round saved",
	waitFor(10, function()
		local last = Report.saved[1]
		return last ~= nil and last.payload.reporter == player.UserId and #last.payload.rows > 0
	end),
	#Report.saved
)

-- Match features on the Shooting Range: gadgets, reload, sniper scope and knife --------------------
-- Each plan is one round's kit and the checks played with it. Bots kill an idle player fast: a check
-- cut short by the player's death (or the round ending) runs again next round with the same kit.
Config.QueueSeconds = 2
local G = Config.Gadgets

-- Waits for `check` while the player fights in a live round; nil if the player or the round ended first.
local function whileFighting(me: Combatants.Combatant, arena: Instance, seconds: number, check: () -> boolean): boolean?
	local deadline = os.clock() + seconds
	while os.clock() < deadline do
		if check() then
			return true
		end
		if not me.alive or arena:GetAttribute("Phase") ~= "Live" then
			return nil
		end
		task.wait(0.05)
	end
	return check()
end

local function topScore(arena: Instance): number
	local navy = (arena:GetAttribute("NavyScore") or 0) :: number
	local grey = (arena:GetAttribute("GreyScore") or 0) :: number
	return math.max(navy, grey)
end

-- Ends a live round with the player's side winning (spawn shields can block the first tries).
local function winRound(arena: Instance)
	waitFor(10, function()
		local me = Combatants.byPlayer(player)
		if me and arena:GetAttribute("Phase") == "Live" then
			for _, c in combatantsOf(arena.Name) do
				if c.alive and c.team ~= me.team then
					Combat.damage(c, 999, me, "Body")
				end
			end
		end
		return arena:GetAttribute("Phase") ~= "Live"
	end)
end

-- Wins every remaining round until the match is over; true once the player is back in the lobby.
local function finishMatch(arena: Instance): boolean
	local deadline = os.clock() + 120
	while os.clock() < deadline and not inLobby() do
		if arena:GetAttribute("Phase") == "Live" then
			winRound(arena)
		end
		task.wait(0.5)
	end
	return waitFor(Config.MatchEndSeconds + 15, inLobby)
end

local function gadgetsOf(arena: Instance): Instance
	return workspace:WaitForChild("Gadgets"):WaitForChild(arena.Name)
end

local function throwSmoke(me: Combatants.Combatant, arena: Instance): boolean
	step("UseGadget")
	local used = whileFighting(me, arena, 2, function()
		return player:GetAttribute("GadgetLeft") == 0
	end)
	if used == nil then
		return false
	end
	result("smoke: throwing it uses the gadget charge", used, player:GetAttribute("GadgetLeft"))
	local folder, puffs = gadgetsOf(arena), 0
	result(
		"smoke: a smoke cloud appears in the arena",
		waitFor(G.Smoke.fuse + 3, function()
			puffs = 0
			for _, p in folder:GetChildren() do
				if p:IsA("BasePart") and p.Size.X > G.Smoke.radius then
					puffs += 1
				end
			end
			return puffs >= 7
		end),
		`{puffs} smoke parts`
	)
	return true
end

local function reload(me: Combatants.Combatant, arena: Instance): boolean
	local gun = Combatants.weapon(me)
	if not gun or Config.Weapons[gun].kind ~= "gun" then
		result("reload: a gun in hand", false, gun)
		return true
	end
	local w = Config.Weapons[gun]
	step("FireShots")
	local spent = whileFighting(me, arena, 4, function()
		return me.ammo[gun] < w.magazine
	end)
	if spent == nil then
		return false
	end
	result("reload: shots use ammo", spent, `{me.ammo[gun]}/{w.magazine}`)
	if not spent then
		return true
	end
	local started = os.clock()
	step("Reload")
	local reloading = whileFighting(me, arena, 2, function()
		return me.reloading
	end)
	local full = reloading
		and whileFighting(me, arena, w.reloadTime + 2, function()
			return not me.reloading and me.ammo[gun] == w.magazine
		end)
	if reloading == nil or full == nil then
		return false
	end
	local took = os.clock() - started
	result(
		"reload: the magazine is full again after the reload time",
		full == true and took >= w.reloadTime - 0.2,
		`{me.ammo[gun]}/{w.magazine} after {string.format("%.1f", took)} s`
	)
	return true
end

local function knife(me: Combatants.Combatant, arena: Instance): boolean
	step("DrawKnife")
	local drawn = whileFighting(me, arena, 3, function()
		return Combatants.weapon(me) == Config.Loadout.Melee
	end)
	if drawn == nil then
		return false
	end
	if not drawn then
		result("knife: the melee slot is drawn", false, Combatants.weapon(me))
		return true
	end
	local bot = botOf(arena.Name)
	if not bot then
		return false
	end
	local target = bot
	waitFor(Config.SpawnShieldSeconds + 1, function()
		return os.clock() >= target.shieldUntil
	end)
	-- Close in on the server side: in front of the player, facing them. Anchored for the stab, since a
	-- bot strafes at point-blank range.
	local r = me.root.CFrame
	target.root.Anchored = true
	Combatants.teleport(target, CFrame.lookAt((r * CFrame.new(0, 0, -3.5)).Position, r.Position))
	local before = target.humanoid.Health
	local damage = Config.Weapons[Config.Loadout.Melee].damage
	step("Stab")
	local hit = whileFighting(me, arena, 3, function()
		return not target.alive or target.humanoid.Health <= before - damage + 0.5
	end)
	if target.root.Parent then
		target.root.Anchored = false
	end
	if hit == nil then
		return false
	end
	result(
		"knife: a stab damages the adjacent bot",
		hit,
		`{math.floor(before)} -> {math.floor(target.humanoid.Health)}`
	)
	return true
end

local function sniper(me: Combatants.Combatant, arena: Instance): boolean
	local id = Combatants.weapon(me)
	if id ~= "Sniper" then
		result("sniper: equipped as primary", false, id)
		return true
	end
	step("AimSniper") -- the client also checks the scope overlay
	local aimed = whileFighting(me, arena, 3, function()
		return me.aiming and me.humanoid.WalkSpeed == Config.AimWalkSpeed
	end)
	if aimed == nil then
		return false
	end
	result("sniper: the server sees the player aiming (and slows them)", aimed, me.aiming)
	return true
end

local function frag(me: Combatants.Combatant, arena: Instance): boolean
	local bot = botOf(arena.Name)
	if not bot then
		return false
	end
	local target = bot
	waitFor(Config.SpawnShieldSeconds + 1, function()
		return os.clock() >= target.shieldUntil
	end)
	local grenade: BasePart? = nil
	local thrownAt = 0
	local blast, blastLive = false, false
	local watch = gadgetsOf(arena).ChildAdded:Connect(function(child)
		if child:IsA("Explosion") then
			blast, blastLive = true, arena:GetAttribute("Phase") == "Live"
		elseif child:IsA("BasePart") and child.Size.X < 1 then
			grenade, thrownAt = child, os.clock()
		end
	end)
	step("UseGadget")
	local thrown = whileFighting(me, arena, 2, function()
		return grenade ~= nil
	end)
	if not thrown or not grenade then
		watch:Disconnect()
		if thrown == false then
			result("frag: thrown", false, "no grenade in the arena")
		end
		return thrown == false
	end
	result(
		"frag: throwing it uses the gadget charge",
		player:GetAttribute("GadgetLeft") == 0,
		player:GetAttribute("GadgetLeft")
	)
	-- A thrown grenade rarely lands on a moving bot: the bot stands on it just before the fuse runs out.
	local g = grenade
	while os.clock() < thrownAt + G.Frag.fuse - 0.3 and g.Parent do
		task.wait()
	end
	local before = target.humanoid.Health
	if g.Parent and target.alive then
		target.root.Anchored = true
		Combatants.teleport(target, CFrame.new(g.Position + Vector3.new(0, 2.6, 0)))
	end
	waitFor(2, function()
		return blast
	end)
	task.wait(0.2)
	watch:Disconnect()
	if target.root.Parent then
		target.root.Anchored = false
	end
	if blast and not blastLive then
		return false -- the round ended first, so the blast deals no damage
	end
	local after = if target.alive then target.humanoid.Health else 0
	result(
		"frag: the explosion damages the bot",
		blast and after < before,
		`blast {blast}, bot {math.floor(before)} -> {math.floor(after)}`
	)
	return true
end

local function medkit(me: Combatants.Combatant, arena: Instance): boolean
	local bot = botOf(arena.Name)
	waitFor(Config.SpawnShieldSeconds + 1, function()
		return os.clock() >= me.shieldUntil and (bot == nil or os.clock() >= bot.shieldUntil)
	end)
	if not me.alive or arena:GetAttribute("Phase") ~= "Live" then
		return false
	end
	-- A badly hurt bot falls back to cover for a few seconds, so its fire can't cut the heal short.
	if bot and bot.humanoid.Health > 30 then
		Combat.damage(bot, bot.humanoid.Health - 25, me, "Body")
	end
	Combat.damage(me, 40, bot or me, "Body")
	local start = me.humanoid.Health
	step("UseGadget")
	local prev, rises, biggest, first, last = start, 0, 0, 0, 0
	local deadline = os.clock() + G.Medkit.channel + 1.5
	while os.clock() < deadline do
		task.wait(0.05)
		local h = me.humanoid.Health
		if not me.alive or h < prev - 1e-3 or arena:GetAttribute("Phase") ~= "Live" then
			print(`PLAYTEST INFO medkit: heal cut short (health {math.floor(h)}, alive {me.alive}); next round`)
			return false
		elseif h > prev + 1e-3 then
			rises += 1
			biggest = math.max(biggest, h - prev)
			first = if first == 0 then os.clock() else first
			last = os.clock()
		end
		prev = h
	end
	local gained = prev - start
	local expected = math.min(G.Medkit.heal, me.humanoid.MaxHealth - start)
	result(
		"medkit: health rises in steps over the channel",
		rises >= 5 and biggest <= G.Medkit.heal / 4 and last - first >= 1.5 and gained >= expected - 1,
		`+{math.floor(gained)} in {rises} steps over {string.format("%.1f", last - first)} s, biggest {string.format(
			"%.1f",
			biggest
		)}`
	)
	return true
end

type Check = { name: string, run: (Combatants.Combatant, Instance) -> boolean }
type Plan = { gadget: string, primary: string, checks: { Check } }
local plans: { Plan } = {
	{
		gadget = "Smoke",
		primary = "AR",
		checks = {
			{ name = "smoke", run = throwSmoke },
			{ name = "reload", run = reload },
			{ name = "knife", run = knife },
		},
	},
	{
		gadget = "Frag",
		primary = "Sniper",
		checks = { { name = "sniper", run = sniper }, { name = "frag", run = frag } },
	},
	{ gadget = "Medkit", primary = "AR", checks = { { name = "medkit", run = medkit } } },
}

Config.RoundsToWin = 2
step("Join ShootingRange 1v1")
local featureRound = 0
local giveUp = os.clock() + 240
while #plans > 0 and os.clock() < giveUp do
	local plan = plans[1]
	local frozen = waitFor(60, function()
		return range:GetAttribute("Phase") == "Freeze" and (range:GetAttribute("Round") or 0) > featureRound
	end)
	if not frozen then
		break
	end
	featureRound = range:GetAttribute("Round")
	step(`Kit {plan.gadget} {plan.primary}`) -- picked during the freeze, like a player
	if not waitFor(20, function()
		return range:GetAttribute("Phase") == "Live"
	end) then
		break
	end
	-- First to 2, but never decided while checks remain: a round lost to the bot must not end the match.
	Config.RoundsToWin = math.max(2, topScore(range) + 2)
	local fighter = Combatants.byPlayer(player)
	while fighter and #plan.checks > 0 and plan.checks[1].run(fighter, range) do
		table.remove(plan.checks, 1)
	end
	if #plan.checks == 0 then
		table.remove(plans, 1)
	end
	if #plans == 0 then
		Config.RoundsToWin = math.max(2, topScore(range) + 1) -- this round's win decides the match
	end
	winRound(range)
end
for _, plan in plans do
	for _, check in plan.checks do
		result(`{check.name}: checked in the features match`, false, "the player never lived long enough")
	end
end
if #plans > 0 then
	-- Checks gave up mid-match: decide it on the next win. (Never touched once decided: the arena reads
	-- RoundsToWin again after the closing cutscenes.)
	Config.RoundsToWin = math.max(2, topScore(range) + 1)
end
result("features match: over, back in the lobby", finishMatch(range))

-- Bots on the other two maps: a short match on each, first to 1.
Config.RoundsToWin = 1
for _, mapId in { "DesertOutpost", "UrbanTown" } do
	local arena = arenas:WaitForChild(mapId)
	-- Desert Outpost doubles as the Bot Bootcamp check: a flagged player plays perfect bots alone.
	local bootcamp = mapId == "DesertOutpost"
	if bootcamp then
		waitFor(Config.MatchEndSeconds + 30, inLobby)
		Economy.setBootcamp(player, true)
		result("bootcamp: status published", player:GetAttribute("Bootcamp") == true)
	end
	step("Queue" .. mapId)
	local live = waitFor(60, function()
		return arena:GetAttribute("Phase") == "Live"
	end)
	result(`{mapId}: match goes live`, live, arena:GetAttribute("Phase"))
	local b = botOf(mapId)
	if bootcamp then
		result("bootcamp: solo match", arena:GetAttribute("Bootcamp") == true, arena:GetAttribute("Bootcamp"))
		result("bootcamp: bots play perfectly", b ~= nil and b.perfect == true)
	end
	if live and b then
		local start, moved = b.root.Position, 0
		local deadline = os.clock() + 20
		while os.clock() < deadline and b.alive and arena:GetAttribute("Phase") == "Live" do
			task.wait(0.5)
			moved = math.max(moved, (b.root.Position - start).Magnitude)
		end
		result(`bot: moves around ({mapId})`, moved > 8, `{math.floor(moved)} studs`)
		-- The kill can trade with the bot's last shot; a draw replays the round, so keep finishing the
		-- bot whenever a round is live until the match is over.
		local finishBy = os.clock() + 60
		while os.clock() < finishBy and not inLobby() do
			local target, mine = botOf(mapId), Combatants.byPlayer(player)
			if arena:GetAttribute("Phase") == "Live" and target and mine then
				Combat.damage(target, 999, mine, "Body")
			end
			task.wait(0.5)
		end
	else
		result(`bot: present on {mapId}`, false, "no bot")
	end
	result(`{mapId}: back in the lobby after the match`, waitFor(Config.MatchEndSeconds + 25, inLobby))
	if bootcamp then
		Economy.setBootcamp(player, false)
	end
end

-- Sudden Death from 0-0, so round 1 is one ------------------------------------------------------
Config.RoundsToWin = 1
Config.SuddenDeathAt = 0
step("Join ShootingRange 1v1")
result("sudden death: round 1 is Sudden Death", waitFor(60, function()
	return range:GetAttribute("Phase") == "Freeze"
end) and range:GetAttribute("SuddenDeath") == true, range:GetAttribute("SuddenDeath"))
local fighter: Combatants.Combatant? = nil
waitFor(15, function()
	fighter = Combatants.byPlayer(player)
	return fighter ~= nil and #fighter.weapons > 0
end)
local function sniperOrKnife(c: Combatants.Combatant?): boolean
	if not c or #c.weapons == 0 then
		return false
	end
	for _, id in c.weapons do
		local w = Config.Weapons[id]
		if not w.scoped and w.kind ~= "melee" then
			return false
		end
	end
	return true
end
result(
	"sudden death: the player carries only a sniper or a knife",
	sniperOrKnife(fighter),
	fighter and table.concat(fighter.weapons, ",")
)
step("SuddenDeathKnife") -- asks for the knife role during the freeze
result(
	"sudden death: the knife role arms a knife only",
	waitFor(5, function()
		return fighter ~= nil and #fighter.weapons == 1 and Config.Weapons[fighter.weapons[1]].kind == "melee"
	end),
	fighter and table.concat(fighter.weapons, ",")
)
Config.SuddenDeathAt = defaults.SuddenDeathAt
result("sudden death: match over, back in the lobby", finishMatch(range))

-- 2v2: three bots fill the other slots ----------------------------------------------------------
local desert = arenas:WaitForChild("DesertOutpost")
step("Join DesertOutpost 2v2")
local teams = { Navy = 0, Grey = 0 }
local botCount = 0
local four = waitFor(60, function()
	return desert:GetAttribute("Phase") == "Freeze" and #combatantsOf("DesertOutpost") == 4
end)
for _, c in combatantsOf("DesertOutpost") do
	teams[c.team] += 1
	botCount += if c.player then 0 else 1
end
result(
	"2v2: four fighters, three of them bots",
	four and botCount == 3,
	`{#combatantsOf("DesertOutpost")}, {botCount} bots`
)
result("2v2: two on each team", teams.Navy == 2 and teams.Grey == 2, `{teams.Navy} v {teams.Grey}`)
result("2v2: the arena runs a 2v2", desert:GetAttribute("Mode") == "2v2", desert:GetAttribute("Mode"))
result("2v2: match over, back in the lobby", finishMatch(desert))

-- Ranked: level 50 through the real XP path, then a ranked queue nobody else joins ------------------
local urban = arenas:WaitForChild("UrbanTown")
local need = 0
for level = 1, 49 do
	need += Config.Xp.Base + Config.Xp.PerLevel * level
end
Economy.awardXp(player, need - (player:GetAttribute("XP") or 0))
result(
	"ranked: unlocked at level 50",
	waitFor(3, function()
		return player:GetAttribute("RankedUnlocked") == true
	end),
	player:GetAttribute("Level")
)
result(
	"ranked: a toggle sent while locked was not kept",
	player:GetAttribute("Ranked") ~= true,
	"ranked turned on by itself at level 50"
)
step("Ranked on")
result(
	"ranked: the toggle turns ranked on once unlocked",
	waitFor(5, function()
		return player:GetAttribute("Ranked") == true
	end)
)
task.wait(0.5) -- separate steps: the client reads the step attribute when its change signal runs
step("Join UrbanTown 1v1")
local queued = waitFor(5, function()
	return player:GetAttribute("Queued") == "UrbanTown"
end)
local queuedAt = os.clock()
local filled = waitFor(Config.QueueSeconds + 40, function()
	return player:GetAttribute("Arena") == "UrbanTown"
end)
local waited, due = os.clock() - queuedAt, Config.QueueSeconds + 20
result(
	`ranked: an empty ranked queue fills with a bot after {due} s`,
	queued and filled and waited >= due - 0.5 and waited < due + 5,
	`{string.format("%.1f", waited)} s`
)
result("ranked: a bot-filled match isn't ranked", urban:GetAttribute("Ranked") == false, urban:GetAttribute("Ranked"))
step("CheckRankedToast")

-- Leaving a live match: back to the lobby, and the match ends as a forfeit -----------------------
result(
	"leave: match goes live",
	waitFor(30, function()
		return urban:GetAttribute("Phase") == "Live"
	end),
	urban:GetAttribute("Phase")
)
local myTeam = player:GetAttribute("Team")
step("Leave")
result(
	"leave: back in the lobby",
	waitFor(15, function()
		return player:GetAttribute("Arena") == nil and inLobby()
	end),
	player:GetAttribute("Arena")
)
result(
	"leave: the match ends as a forfeit to the other side",
	waitFor(10, function()
		return urban:GetAttribute("Phase") == "MatchEnd" or urban:GetAttribute("Phase") == "Waiting"
	end)
		and urban:GetAttribute("Winner") ~= nil
		and urban:GetAttribute("Winner") ~= myTeam,
	`{urban:GetAttribute("Phase")}, winner {urban:GetAttribute("Winner")}, left {myTeam}`
)
result(
	"leave: arena waiting again",
	waitFor(Config.MatchEndSeconds + 15, function()
		return urban:GetAttribute("Phase") == "Waiting"
	end),
	urban:GetAttribute("Phase")
)

for key, value in defaults do
	(Config :: any)[key] = value
end

step("Done")
print("PLAYTEST SERVER DONE")
