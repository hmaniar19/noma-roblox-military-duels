--!strict
-- Server-side checks on what players claim. Movement itself is server-authoritative: the place runs
-- with Workspace.AuthorityMode = Server, so the server simulates every character from inputs and
-- speed, fly and teleport hacks can't move it. This module checks shot claims (look vs aim) and
-- keeps everyone inside the map. Every rejection adds to a decaying suspicion score; a player whose
-- score reaches Config.AntiCheat.FlagThreshold is sent to Bot Bootcamp.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Combatants = require(script.Parent.Combatants)
local Config = require(ReplicatedStorage.Shared.Config)
local Economy = require(script.Parent.Economy)
local Hitbox = require(ReplicatedStorage.Shared.Hitbox)
local Net = require(script.Parent.Net)

local AC = Config.AntiCheat

local AntiCheat = {}

export type Flag = { t: number, reason: string } -- t is os.clock()
local log: { [Player]: { Flag } } = {}
local scores: { [Player]: { value: number, at: number } } = {} -- the score as of os.clock() `at`
local lastWarn: { [Player]: number } = {}

local function weight(reason: string): number
	for prefix, w in AC.FlagWeights do
		if string.sub(reason, 1, #prefix) == prefix then
			return w
		end
	end
	return AC.FlagDefaultWeight
end

local function score(player: Player, now: number): number
	local s = scores[player]
	return if s then math.max(0, s.value - AC.FlagDecayPerMinute * (now - s.at) / 60) else 0
end

-- Scores every rejection; keeps the 50 most recent reasons and warns at most twice a second.
function AntiCheat.flag(c: Combatants.Combatant, reason: string)
	local player = c.player
	if not player then
		return
	end
	local now = os.clock()
	local entries = log[player] or {}
	log[player] = entries
	table.insert(entries, { t = now, reason = reason })
	if #entries > 50 then
		table.remove(entries, 1)
	end
	local value = score(player, now) + weight(reason)
	scores[player] = { value = value, at = now }
	player:SetAttribute("CheatFlags", math.floor(value))
	if value >= AC.FlagThreshold and not player:GetAttribute("Bootcamp") then
		Economy.setBootcamp(player, true)
		Net.Toast:FireClient(player, "Bot Bootcamp", `{Config.BootcampCleanMatches} clean matches in a row to get out`)
	end
	if now - (lastWarn[player] or 0) > 0.5 then
		lastWarn[player] = now
		warn(`[AntiCheat] {player.Name} ({player.UserId}): {reason} (score {math.floor(value)})`)
	end
end

-- How many flags the player has collected since os.clock() time `t` (a clean match has none).
function AntiCheat.flagsSince(player: Player, t: number): number
	local n = 0
	local entries: { Flag } = log[player] or {}
	for _, f in entries do
		if f.t >= t then
			n += 1
		end
	end
	return n
end

Players.PlayerRemoving:Connect(function(player)
	log[player], scores[player], lastWarn[player] = nil, nil, nil
end)

function AntiCheat.recordLook(c: Combatants.Combatant, dir: Vector3)
	local now = os.clock()
	table.insert(c.looks, { t = now, dir = dir })
	while #c.looks > 1 and now - c.looks[1].t > 1 do
		table.remove(c.looks, 1)
	end
end

-- A shot must point roughly where the player was actually looking a moment ago. Stops silent aim,
-- where a tool fires at the enemy while the camera points somewhere else. The yaw is checked against
-- the body's facing, which the server simulates (first-person characters turn with the camera);
-- the reported look history covers pitch, which has no server-side source. Any facing within the
-- lag-compensation window counts, because the server's copy of a fast flick arrives late.
local function facedRecently(c: Combatants.Combatant, flat: Vector3): boolean
	local function near(cf: CFrame): boolean
		local face = cf.LookVector
		return Hitbox.angleBetween(flat, Vector3.new(face.X, 0, face.Z)) <= AC.MaxYawAngle
	end
	if near(c.root.CFrame) then
		return true
	end
	local since = os.clock() - AC.MaxRewind - 0.15
	for i = #c.historyT, 1, -1 do
		if c.historyT[i] < since then
			break
		elseif near(c.historyCF[i]) then
			return true
		end
	end
	return false
end

function AntiCheat.aimMatches(c: Combatants.Combatant, dir: Vector3): boolean
	local flat = Vector3.new(dir.X, 0, dir.Z)
	if flat.Magnitude > 0.2 and not facedRecently(c, flat) then
		return false
	end
	local now = os.clock()
	for i = #c.looks, 1, -1 do
		local look = c.looks[i]
		if now - look.t > AC.LookWindow then
			break
		end
		if Hitbox.angleBetween(look.dir, dir) <= AC.MaxAimAngle then
			return true
		end
	end
	return false
end

-- A shot whose direction didn't match is dropped at once, but only flagged if the body still hasn't
-- turned that way a moment later: the server's copy of a fast flick arrives late.
function AntiCheat.flagAim(c: Combatants.Combatant, dir: Vector3, reason: string)
	local flat = Vector3.new(dir.X, 0, dir.Z)
	task.delay(AC.MaxRewind, function()
		if c.alive and (flat.Magnitude <= 0.2 or not facedRecently(c, flat)) then
			AntiCheat.flag(c, reason)
		end
	end)
end

local function inside(p: Vector3, lo: Vector3, hi: Vector3): boolean
	return p.X >= lo.X and p.X <= hi.X and p.Y >= lo.Y and p.Y <= hi.Y and p.Z >= lo.Z and p.Z <= hi.Z
end

-- Physics glitches (wedging into geometry, getting flung) can still push a character out of the map;
-- anything that ends up outside is returned to its last grounded spot.
-- Returns true when it had to move the combatant back.
local function check(c: Combatants.Combatant, now: number, force: boolean): boolean
	if now - c.lastCheck < AC.CheckInterval and not force then
		return false
	end
	c.lastCheck = now
	local root = c.root
	local pos = root.Position
	local boundsMin, boundsMax = c.arena.boundsMin, c.arena.boundsMax
	if inside(pos, boundsMin, boundsMax) then
		if c.humanoid.FloorMaterial ~= Enum.Material.Air then
			c.lastGrounded = root.CFrame
			c.doubleJumped = false -- landing recharges the mid-air jump
		end
		return false
	end
	-- Falling off is not cheating; getting above the ceiling or past the walls is.
	if pos.Y >= boundsMin.Y then
		AntiCheat.flag(c, `out of bounds at {math.floor(pos.X)},{math.floor(pos.Y)},{math.floor(pos.Z)}`)
	end
	Combatants.teleport(c, c.lastGrounded)
	return true
end

-- Validate a player's position right now (before trusting it for a shot). True if it was corrected,
-- in which case the shot is dropped: it was fired from a position the server didn't accept.
function AntiCheat.validate(c: Combatants.Combatant): boolean
	return c.player ~= nil and c.alive and not c.root.Anchored and c.root.Parent ~= nil and check(c, os.clock(), true)
end

function AntiCheat.start()
	-- Movement is only cheat-proof under Server Authority; refuse to run a duel when it is off. The
	-- property is readable in Studio and live servers today; the pcall keeps a future restriction on
	-- reading it from taking the whole server down.
	local readable, mode = pcall(function()
		return workspace.AuthorityMode
	end)
	if readable and mode ~= Enum.AuthorityMode.Server then
		error("[AntiCheat] Workspace.AuthorityMode must be Server (set in default.project.json)")
	elseif not readable then
		warn("[AntiCheat] could not read Workspace.AuthorityMode; assuming the project setting (Server)")
	end
	RunService.Heartbeat:Connect(function()
		local now = os.clock()
		for _, c in Combatants.all() do
			if c.alive and not c.root.Anchored and c.root.Parent then
				check(c, now, false)
			end
		end
	end)
	-- The published score drains too, not only when the next flag lands.
	task.spawn(function()
		while true do
			task.wait(5)
			local now = os.clock()
			for player in scores do
				local value = score(player, now)
				player:SetAttribute("CheatFlags", math.floor(value))
				if value <= 0 then
					scores[player] = nil
				end
			end
		end
	end)
end

return AntiCheat
