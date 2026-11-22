--!strict
-- The free practice Shooting Range in Camp More Maniar: pick any weapon from a rack (ProximityPrompt)
-- and shoot the target dummies with the real combat code. Practice ends when you walk off the range,
-- press LEAVE RANGE, or queue for a match. It uses the lobby as its bounds, so walking away never
-- trips the anti-cheat.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Combat = require(script.Parent.Combat)
local Combatants = require(script.Parent.Combatants)
local Config = require(ReplicatedStorage.Shared.Config)
local Gun = require(ReplicatedStorage.Shared.Gun)
local Net = require(script.Parent.Net)
local Rig = require(script.Parent.Rig)

export type RangeInfo = { min: Vector3, max: Vector3, racks: { CFrame }, targets: { CFrame } }
export type Range = { leave: (player: Player) -> (), isPracticing: (player: Player) -> boolean }

local PracticeRange = {}

local ID = "Practice"
-- One rack per weapon a player can pick (the Pistol and Knife come with every practice kit).
local RACK_WEAPONS = { "AR", "SMG", "Shotgun", "Sniper", "MothersWrath", "DoubleTrouble" }
local DEFAULT_WALK = 16

local function inside(p: Vector3, lo: Vector3, hi: Vector3): boolean
	return p.X >= lo.X and p.X <= hi.X and p.Y >= lo.Y and p.Y <= hi.Y and p.Z >= lo.Z and p.Z <= hi.Z
end

-- `lobbyMin` / `lobbyMax` bound the whole lobby (the anti-cheat box while practicing).
function PracticeRange.new(info: RangeInfo, lobbyMin: Vector3, lobbyMax: Vector3): Range
	local state = Instance.new("Folder")
	state.Name = ID
	state:SetAttribute("Name", "Practice Range")
	state:SetAttribute("Phase", "Live") -- the client only fires while its arena is live
	state.Parent = ReplicatedStorage:WaitForChild("Arenas")
	local folder = Instance.new("Folder")
	folder.Name = "PracticeRange"
	folder.Parent = workspace

	local hooks: Combatants.ArenaHooks = {
		id = ID,
		isLive = function()
			return true
		end,
		onElimination = function() end,
		boundsMin = lobbyMin,
		boundsMax = lobbyMax,
	}

	local function leave(player: Player)
		local c = Combatants.byPlayer(player)
		if not c or c.arena ~= hooks then
			return
		end
		Combat.setStance(c, "Stand")
		Combatants.remove(c)
		for _, child in c.model:GetChildren() do
			if child:IsA("Tool") then
				child:Destroy()
			end
		end
		c.humanoid.WalkSpeed = DEFAULT_WALK
		c.model:SetAttribute("Team", nil)
		player:SetAttribute("Team", nil)
		player:SetAttribute("Arena", nil)
		player.CameraMode = Enum.CameraMode.Classic
	end

	local lastTry: { [Player]: number } = {}
	local function practice(player: Player, weapon: string)
		local now = os.clock()
		if now - (lastTry[player] or 0) < 0.5 then
			return
		end
		lastTry[player] = now
		local current = player:GetAttribute("Arena")
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if (current ~= nil and current ~= ID) or player:GetAttribute("Queued") or not root or not humanoid then
			return -- in (or queued for) a real match
		end
		if humanoid.Health <= 0 or not inside((root :: BasePart).Position, info.min, info.max) then
			return
		end
		local c = Combatants.byPlayer(player)
		if c and c.arena ~= hooks then
			return
		end
		if not c then
			local pivot = (character :: Model):GetPivot()
			local ok, made = pcall(function()
				return Combatants.new(hooks, player.DisplayName, player, "Navy", character :: Model, pivot)
			end)
			if not ok then
				return
			end
			c = made
			player:SetAttribute("Team", "Navy")
			player:SetAttribute("Arena", ID)
			player.CameraMode = Enum.CameraMode.LockFirstPerson
			-- Dying on the range ends practice; the lobby's own death handler then respawns them.
			humanoid.Died:Once(function()
				if Combatants.byPlayer(player) == made then
					leave(player)
				end
			end)
		elseif Combatants.weapon(c) == weapon then
			return -- already holding it
		end
		local melee = Config.Weapons[weapon].kind == "melee"
		Combat.arm(
			c :: Combatants.Combatant,
			if melee then { weapon, "Pistol" } else { weapon, "Pistol", "Knife" },
			nil
		)
	end

	-- Racks: one weapon on each, with a prompt to try it.
	for i, cf in info.racks do
		local weapon = RACK_WEAPONS[i]
		if not weapon then
			break
		end
		local display = Instance.new("Model")
		display.Name = weapon
		local handle = Gun.build(display, weapon)
		display.PrimaryPart = handle
		display:PivotTo(cf * CFrame.new(0, 0.5, 0) * CFrame.Angles(0, 0, math.rad(90)))
		for _, d in display:GetDescendants() do
			if d:IsA("BasePart") then
				d.Anchored = true
			end
		end
		display.Parent = folder
		local prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = `Try {Config.Weapons[weapon].name}`
		prompt.ObjectText = "Practice Range"
		prompt.HoldDuration = 0
		prompt.MaxActivationDistance = 9
		prompt.RequiresLineOfSight = false
		prompt.Parent = handle
		prompt.Triggered:Connect(function(player)
			practice(player, weapon)
		end)
	end

	-- Target dummies stand at the end of each lane and come back 2 seconds after they drop.
	local function dummy(cf: CFrame)
		local ok, err = pcall(function()
			local model = Rig.spawnBot("Grey", "Target", cf, folder)
			local made, c = pcall(function()
				return Combatants.new(hooks, "Target", nil, "Grey", model, cf)
			end)
			if not made then
				model:Destroy()
				error(c)
			end
			c.root.Anchored = true
			c.humanoid.Died:Once(function()
				task.wait(2)
				Combatants.remove(c)
				model:Destroy()
				dummy(cf)
			end)
		end)
		if not ok then
			warn("Practice dummy failed, retrying:", err)
			task.delay(5, dummy, cf)
		end
	end
	for _, cf in info.targets do
		task.spawn(dummy, cf)
	end

	Net.Practice.OnServerEvent:Connect(function(player, action)
		if action == "Leave" and Net.allow(player, "Practice", 4, 2) then
			leave(player)
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		lastTry[player] = nil
		leave(player)
	end)
	task.spawn(function()
		while true do
			task.wait(0.25)
			for _, player in Players:GetPlayers() do
				local c = Combatants.byPlayer(player)
				if c and c.arena == hooks and not inside(c.root.Position, info.min, info.max) then
					leave(player) -- walked off the range
				end
			end
		end
	end)

	return {
		leave = leave,
		isPracticing = function(player)
			return player:GetAttribute("Arena") == ID
		end,
	}
end

return PracticeRange
