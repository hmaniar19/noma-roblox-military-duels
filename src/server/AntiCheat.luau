--!strict
-- Server-side checks on what players claim. Movement itself is server-authoritative: the place runs
-- with Workspace.AuthorityMode = Server, so the server simulates every character from inputs and
-- speed, fly and teleport hacks can't move it. This module checks shot claims (look vs aim) and
-- keeps everyone inside the map. Every rejection adds a cheat flag; penalties come in phase 6.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Combatants = require(script.Parent.Combatants)
local Config = require(ReplicatedStorage.Shared.Config)
local Hitbox = require(ReplicatedStorage.Shared.Hitbox)

local AC = Config.AntiCheat

local AntiCheat = {}

export type Flag = { t: number, reason: string }
local log: { [Player]: { Flag } } = {}
local counts: { [Player]: number } = {}
local lastWarn: { [Player]: number } = {}

-- Counts every rejection; keeps the 50 most recent reasons and warns at most twice a second.
function AntiCheat.flag(c: Combatants.Combatant, reason: string)
	local player = c.player
	if not player then
		return
	end
	local entries = log[player] or {}
	log[player] = entries
	table.insert(entries, { t = os.time(), reason = reason })
	if #entries > 50 then
		table.remove(entries, 1)
	end
	counts[player] = (counts[player] or 0) + 1
	player:SetAttribute("CheatFlags", counts[player])
	if os.clock() - (lastWarn[player] or 0) > 0.5 then
		lastWarn[player] = os.clock()
		warn(`[AntiCheat] {player.Name} ({player.UserId}): {reason} (total {counts[player]})`)
	end
end

Players.PlayerRemoving:Connect(function(player)
	log[player], counts[player], lastWarn[player] = nil, nil, nil
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
-- the reported look history covers pitch, which has no server-side source.
function AntiCheat.aimMatches(c: Combatants.Combatant, dir: Vector3): boolean
	local flat = Vector3.new(dir.X, 0, dir.Z)
	local face = c.root.CFrame.LookVector
	if flat.Magnitude > 0.2 and Hitbox.angleBetween(flat, Vector3.new(face.X, 0, face.Z)) > AC.MaxYawAngle then
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

local function inside(p: Vector3, lo: Vector3, hi: Vector3): boolean
	return p.X >= lo.X and p.X <= hi.X and p.Y >= lo.Y and p.Y <= hi.Y and p.Z >= lo.Z and p.Z <= hi.Z
end

local boundsMin, boundsMax = Vector3.zero, Vector3.zero

-- Physics glitches (wedging into geometry, getting flung) can still push a character out of the map;
-- anything that ends up outside is returned to its last grounded spot.
local function check(c: Combatants.Combatant, now: number, force: boolean)
	if now - c.lastCheck < AC.CheckInterval and not force then
		return
	end
	c.lastCheck = now
	local root = c.root
	local pos = root.Position
	if inside(pos, boundsMin, boundsMax) then
		if c.humanoid.FloorMaterial ~= Enum.Material.Air then
			c.lastGrounded = root.CFrame
		end
		return
	end
	-- Falling off is not cheating; getting above the ceiling or past the walls is.
	if pos.Y >= boundsMin.Y then
		AntiCheat.flag(c, `out of bounds at {math.floor(pos.X)},{math.floor(pos.Y)},{math.floor(pos.Z)}`)
	end
	Combatants.teleport(c, c.lastGrounded)
end

-- Validate a player's position right now (before trusting it for a shot).
function AntiCheat.validate(c: Combatants.Combatant)
	if c.player and c.alive and not c.root.Anchored and c.root.Parent then
		check(c, os.clock(), true)
	end
end

function AntiCheat.start(min: Vector3, max: Vector3)
	boundsMin, boundsMax = min, max
	-- Movement is only cheat-proof under Server Authority; refuse to run a duel without it.
	if workspace.AuthorityMode ~= Enum.AuthorityMode.Server then
		error("[AntiCheat] Workspace.AuthorityMode must be Server (set in default.project.json)")
	end
	RunService.Heartbeat:Connect(function()
		local now = os.clock()
		for _, c in Combatants.all() do
			if c.player and c.alive and not c.root.Anchored and c.root.Parent then
				check(c, now, false)
			end
		end
	end)
end

return AntiCheat
