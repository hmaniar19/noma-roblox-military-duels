--!strict
-- Registry of everyone in the current duel (players and bots), plus the server-side state the
-- client is never trusted with: weapons and ammo, reload, gadget, shield, position history for lag
-- compensation, and recent look directions.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)

-- What a combatant needs from the arena (map + match) it fights in. Several arenas run at once.
export type ArenaHooks = {
	id: string,
	isLive: () -> boolean,
	onElimination: (victim: any, attacker: any?, zone: Config.Zone?, weapon: string?) -> (),
	boundsMin: Vector3,
	boundsMax: Vector3,
}

export type Combatant = {
	arena: ArenaHooks,
	name: string,
	player: Player?,
	team: Config.TeamId,
	model: Model,
	humanoid: Humanoid,
	root: BasePart,
	alive: boolean,
	weapons: { Config.WeaponId }, -- slot order
	equipped: number,
	ammo: { [Config.WeaponId]: number },
	gadget: Config.GadgetId?,
	gadgetLeft: number,
	healingUntil: number, -- med kit channel end, 0 when not healing
	stance: "Stand" | "Sprint" | "Crouch",
	slideUntil: number, -- slide burst end
	lastSlide: number,
	doubleJumped: boolean, -- the one mid-air jump is used until the next landing
	reloadToken: number,
	reloading: boolean,
	lastShot: number,
	aiming: boolean,
	shieldUntil: number,
	historyT: { number },
	historyCF: { CFrame },
	historyCrouch: { boolean },
	perfect: boolean?, -- Bootcamp bots: no spread at all
	looks: { { t: number, dir: Vector3 } },
	lastGrounded: CFrame,
	lastCheck: number,
}

local HISTORY_SECONDS = 1

local Combatants = {}

local SYNCED = { "Weapon", "Slots", "Ammo", "Reloading", "Gadget", "GadgetLeft", "Healing", "Shielded", "Stance" }

local list: { Combatant } = {}
local watchers: { [Combatant]: RBXScriptConnection } = {}

function Combatants.new(
	arena: ArenaHooks,
	name: string,
	player: Player?,
	team: Config.TeamId,
	model: Model,
	spawn: CFrame
): Combatant
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local root = model:FindFirstChild("HumanoidRootPart")
	if not humanoid or not root or not root:IsA("BasePart") then
		error(`Combatants.new: {model:GetFullName()} has no Humanoid or HumanoidRootPart`)
	end
	local c: Combatant = {
		arena = arena,
		name = name,
		player = player,
		team = team,
		model = model,
		humanoid = humanoid,
		root = root,
		alive = true,
		weapons = {},
		equipped = 1,
		ammo = {},
		gadget = nil,
		gadgetLeft = 0,
		healingUntil = 0,
		stance = "Stand",
		slideUntil = 0,
		lastSlide = 0,
		doubleJumped = false,
		reloadToken = 0,
		reloading = false,
		lastShot = 0,
		aiming = false,
		shieldUntil = 0,
		historyT = {},
		historyCF = {},
		historyCrouch = {},
		looks = {},
		lastGrounded = spawn,
		lastCheck = os.clock(),
	}
	model:SetAttribute("Team", team)
	table.insert(list, c)
	watchers[c] = model.AncestryChanged:Connect(function()
		if not model:IsDescendantOf(game) then
			c.alive = false
		end
	end)
	return c
end

function Combatants.weapon(c: Combatant): Config.WeaponId?
	return c.weapons[c.equipped]
end

function Combatants.all(): { Combatant }
	return list
end

local function retire(c: Combatant)
	c.alive = false
	c.reloadToken += 1
	local watcher = watchers[c]
	if watcher then
		watcher:Disconnect()
		watchers[c] = nil
	end
	if c.player then
		for _, key in SYNCED do
			c.player:SetAttribute(key, nil)
		end
	end
end

-- Ends every combatant in one arena (other arenas keep fighting).
function Combatants.clear(arena: ArenaHooks)
	for i = #list, 1, -1 do
		if list[i].arena == arena then
			retire(list[i])
			table.remove(list, i)
		end
	end
end

-- Ends one combatant (the lobby practice range adds and removes them one at a time).
function Combatants.remove(c: Combatant)
	local i = table.find(list, c)
	if i then
		retire(c)
		table.remove(list, i)
	end
end

function Combatants.byPlayer(player: Player): Combatant?
	for _, c in list do
		if c.player == player then
			return c
		end
	end
	return nil
end

-- Mirror the state the HUD needs onto the player (read-only for the client).
function Combatants.sync(c: Combatant)
	local player = c.player
	if player then
		local id: Config.WeaponId? = c.weapons[c.equipped]
		player:SetAttribute("Weapon", id)
		player:SetAttribute("Slots", table.concat(c.weapons :: { any }, ","))
		player:SetAttribute("Ammo", if id then c.ammo[id] else 0)
		player:SetAttribute("Reloading", c.reloading)
		player:SetAttribute("Gadget", c.gadget)
		player:SetAttribute("GadgetLeft", c.gadgetLeft)
		player:SetAttribute("Healing", c.healingUntil > 0)
		player:SetAttribute("Stance", c.stance)
		player:SetAttribute("Shielded", os.clock() < c.shieldUntil)
	end
end

-- Server-initiated moves reset the movement check so they never count as teleport hacks.
function Combatants.teleport(c: Combatant, cf: CFrame)
	c.model:PivotTo(cf)
	c.root.AssemblyLinearVelocity = Vector3.zero
	c.lastGrounded = cf
	c.lastCheck = os.clock()
	table.clear(c.historyT)
	table.clear(c.historyCF)
	table.clear(c.historyCrouch)
end

-- Where `c` was `secondsAgo` ago, interpolated from recorded history, and whether it was crouched.
function Combatants.rewound(c: Combatant, secondsAgo: number): (CFrame, boolean)
	local times, cfs, crouch = c.historyT, c.historyCF, c.historyCrouch
	local n = #times
	if n == 0 or secondsAgo <= 0 then
		return c.root.CFrame, c.stance == "Crouch"
	end
	local t = os.clock() - secondsAgo
	if t <= times[1] then
		return cfs[1], crouch[1]
	end
	for i = n, 2, -1 do
		if times[i - 1] <= t then
			local a = math.clamp((t - times[i - 1]) / math.max(times[i] - times[i - 1], 1e-6), 0, 1)
			return cfs[i - 1]:Lerp(cfs[i], a), if a < 0.5 then crouch[i - 1] else crouch[i]
		end
	end
	return cfs[n], crouch[n]
end

RunService.Heartbeat:Connect(function()
	local now = os.clock()
	for _, c in list do
		if c.alive and c.root.Parent then
			table.insert(c.historyT, now)
			table.insert(c.historyCF, c.root.CFrame)
			table.insert(c.historyCrouch, c.stance == "Crouch")
			while #c.historyT > 2 and now - c.historyT[1] > HISTORY_SECONDS do
				table.remove(c.historyT, 1)
				table.remove(c.historyCF, 1)
				table.remove(c.historyCrouch, 1)
			end
		end
		local shielded = now < c.shieldUntil
		if c.player and c.player:GetAttribute("Shielded") ~= shielded then
			c.player:SetAttribute("Shielded", shielded)
		end
	end
end)

return Combatants
