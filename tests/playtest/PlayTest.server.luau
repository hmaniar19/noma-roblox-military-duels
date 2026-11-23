-- Game test, server side. Runs in the test place only (tests/playtest/default.project.json), never in
-- the shipped game. It drives the steps (the client test follows the "TestStep" player attribute),
-- watches real play without changing it, and ends rounds through the normal damage path.
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
	while os.clock() < deadline and range:GetAttribute("Phase") == "Live" and bot.alive do
		task.wait(0.5)
		moved = math.max(moved, (bot.root.Position - start).Magnitude)
		local ammo = bot.ammo[bot.weapons[bot.equipped]]
		if ammo and lastAmmo and ammo < lastAmmo then
			shots += lastAmmo - ammo
		end
		lastAmmo = ammo
	end
	result("bot: moves around (Shooting Range)", moved > 8, `{math.floor(moved)} studs`)
	local me = Combatants.byPlayer(player)
	result("bot: shoots at the player", shots > 0 or (me ~= nil and me.humanoid.Health < 100), shots)
	-- Round 1: a headshot win -> bullet cam, then the finisher.
	if bot.alive and me then
		Combat.damage(bot, 999, me, "Head")
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
if bot and me then
	Combat.damage(bot, 999, me, "Body")
end
result(
	"match: ends after the deciding round",
	waitFor(25, function()
		return range:GetAttribute("Phase") == "MatchEnd"
	end),
	range:GetAttribute("Phase")
)
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

-- Bots on the other two maps: a short match on each, first to 1.
Config.RoundsToWin = 1
for _, mapId in { "DesertOutpost", "UrbanTown" } do
	local arena = arenas:WaitForChild(mapId)
	-- Desert Outpost doubles as the Bot Bootcamp check: a flagged player plays perfect bots alone.
	local bootcamp = mapId == "DesertOutpost"
	if bootcamp then
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
		local mine = Combatants.byPlayer(player)
		if b.alive and mine then
			Combat.damage(b, 999, mine, "Body")
		end
	else
		result(`bot: present on {mapId}`, false, "no bot")
	end
	result(`{mapId}: back in the lobby after the match`, waitFor(Config.MatchEndSeconds + 25, inLobby))
	if bootcamp then
		Economy.setBootcamp(player, false)
	end
end

step("Done")
print("PLAYTEST SERVER DONE")
