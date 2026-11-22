-- Game test, server side. Runs in the test place only (tests/playtest/default.project.json), never in
-- the shipped game. It watches the real match without changing gameplay, then ends the match through
-- the normal damage path to check the celebration and the return to the lobby.
-- Every result is a log line: "PLAYTEST PASS <name>", "PLAYTEST FAIL <name>: <why>", "PLAYTEST DONE".
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Server = ServerScriptService:WaitForChild("Server")
local Combat = require(Server:WaitForChild("Combat"))
local Combatants = require(Server:WaitForChild("Combatants"))
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local function result(name: string, ok: boolean, why: string?)
	print(if ok then `PLAYTEST PASS {name}` else `PLAYTEST FAIL {name}: {why or "?"}`)
end

local function waitFor(seconds: number, check: () -> boolean): boolean
	local deadline = os.clock() + seconds
	while os.clock() < deadline do
		if check() then
			return true
		end
		task.wait(0.25)
	end
	return check()
end

local player = Players.PlayerAdded:Wait()
local arenas = ReplicatedStorage:WaitForChild("Arenas")
local range = arenas:WaitForChild("ShootingRange")

-- Lobby.
result(
	"lobby: player spawns",
	waitFor(20, function()
		return player.Character ~= nil and player.Character:FindFirstChild("HumanoidRootPart") ~= nil
	end)
)
local lobbyPos = player.Character and player.Character:GetPivot().Position
result("lobby: spawned in Camp More Maniar", lobbyPos ~= nil and lobbyPos.Z < -1400, tostring(lobbyPos))
for _, m in Config.Maps do
	local a = arenas:FindFirstChild(m.id)
	result(`arena {m.id} is waiting`, a ~= nil and a:GetAttribute("Phase") == "Waiting", a and a:GetAttribute("Phase"))
end

-- The client queues for the Shooting Range; the match must start and go live.
result(
	"match: goes live",
	waitFor(60, function()
		return range:GetAttribute("Phase") == "Live"
	end),
	tostring(range:GetAttribute("Phase"))
)

local function bots(): { Combatants.Combatant }
	local out = {}
	for _, c in Combatants.all() do
		if not c.player and c.arena.id == "ShootingRange" then
			table.insert(out, c)
		end
	end
	return out
end
local function me(): Combatants.Combatant?
	return Combatants.byPlayer(player)
end

local bot = bots()[1]
result("match: a bot is fighting", bot ~= nil and bot.alive, "no living bot")
if bot then
	-- Real play for 30 seconds: the bot must stay alive unless shot, move around, and shoot.
	local start = bot.root.Position
	local maxMoved = 0
	local shots = 0
	local lastAmmo = bot.ammo[bot.weapons[1]]
	local myStart = me() and (me() :: any).humanoid.Health or 100
	local diedWithoutReason = false
	local deadline = os.clock() + 30
	while os.clock() < deadline and range:GetAttribute("Phase") == "Live" do
		task.wait(0.5)
		if not bot.alive then
			local hp = bot.humanoid.Health
			diedWithoutReason = hp > 0 -- marked dead while its humanoid still had health
			break
		end
		maxMoved = math.max(maxMoved, (bot.root.Position - start).Magnitude)
		local ammo = bot.ammo[bot.weapons[bot.equipped]]
		if ammo and lastAmmo and ammo < lastAmmo then
			shots += lastAmmo - ammo
		end
		lastAmmo = ammo
	end
	result("bot: moves around", maxMoved > 8, `moved {math.floor(maxMoved)} studs`)
	result("bot: not killed by the game itself", not diedWithoutReason, "bot was marked dead with health left")
	local mine = me()
	local myHealth = mine and mine.humanoid.Health or 0
	result(
		"bot: shoots at the player",
		shots > 0 or myHealth < myStart,
		`bot shots {shots}, player health {myStart} -> {myHealth}`
	)
	print(`PLAYTEST INFO bot health {bot.humanoid.Health}, alive {bot.alive}, phase {range:GetAttribute("Phase")}`)

	-- End the match through the normal damage path (first to 1 from here).
	Config.RoundsToWin = 1
	if bot.alive and mine then
		Combat.damage(bot, 999, mine, "Body")
	end
	result(
		"match: ends after the round",
		waitFor(20, function()
			return range:GetAttribute("Phase") == "MatchEnd"
		end),
		tostring(range:GetAttribute("Phase"))
	)
	result(
		"celebration: stage appears",
		waitFor(5, function()
			return workspace:FindFirstChild("Celebration") ~= nil
		end)
	)
	result(
		"after match: back in the lobby",
		waitFor(Config.MatchEndSeconds + 15, function()
			local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
			return player:GetAttribute("Arena") == nil and root ~= nil and root.Position.Z < -1400
		end)
	)
	result("after match: celebration cleaned up", workspace:FindFirstChild("Celebration") == nil)
	result(
		"after match: arena ready again",
		waitFor(5, function()
			return range:GetAttribute("Phase") == "Waiting"
		end),
		tostring(range:GetAttribute("Phase"))
	)
end
print("PLAYTEST SERVER DONE")
