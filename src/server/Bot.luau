--!strict
-- A server-controlled fighter that fills an empty slot. It plays by the same rules as players: it
-- shoots through Combat.fire (walls, ammo, cadence, spread and hitboxes all apply), can't see through
-- smoke, closes to its weapon's effective range, and patches up with a med kit in cover.
local PathfindingService = game:GetService("PathfindingService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Combat = require(script.Parent.Combat)
local Combatants = require(script.Parent.Combatants)
local Config = require(ReplicatedStorage.Shared.Config)
local Gadgets = require(script.Parent.Gadgets)
local Hitbox = require(ReplicatedStorage.Shared.Hitbox)

type Combatant = Combatants.Combatant

local B = Config.Bot
local BODY_OFFSET = Config.Hitboxes[2].offset
local HEAD_OFFSET = Config.Hitboxes[1].offset
local ADS_RANGE = 30 -- guns aim down sights past this; hip spread at mid range wastes the burst
local KNIFE_STOP = 3 -- a knife walks straight in until this close, never strafing
local KNIFE_REACTION = 0.25

-- Roblox's default R15 animations; bots have no client to run the Animate script.
local ANIMS: { [string]: string } = {
	idle = "rbxassetid://507766388",
	run = "rbxassetid://913376220",
	hold = "rbxassetid://507768375",
}

local Bot = {}

local rng = Random.new()

local function animate(humanoid: Humanoid)
	local animator: Animator = humanoid:FindFirstChildOfClass("Animator") or Instance.new("Animator")
	animator.Parent = humanoid
	local tracks: { [string]: AnimationTrack } = {}
	for name, id in ANIMS do
		local anim = Instance.new("Animation")
		anim.AnimationId = id
		local ok, track = pcall(animator.LoadAnimation, animator, anim)
		if ok then
			track.Looped = true
			tracks[name] = track
		end
	end
	if tracks.idle then
		tracks.idle:Play()
	end
	if tracks.hold then
		tracks.hold:Play(0.1, 1, 1)
		tracks.hold.Priority = Enum.AnimationPriority.Action
	end
	humanoid.Running:Connect(function(speed)
		local run = tracks.run
		if run then
			if speed > 1 and not run.IsPlaying then
				run:Play(0.15)
			elseif speed <= 1 and run.IsPlaying then
				run:Stop(0.2)
			end
		end
	end)
end

-- The first visible hitbox point (body first, or head first for a perfect bot's head shots).
local function visiblePoint(c: Combatant, enemy: Combatant, headFirst: boolean): Vector3?
	local eye = Combat.headPosition(c)
	local params = Combat.occlusion()
	local order: { Vector3 } = if headFirst then { HEAD_OFFSET, BODY_OFFSET } else { BODY_OFFSET, HEAD_OFFSET }
	for _, offset in order do
		local point = (enemy.root.CFrame * CFrame.new(offset)).Position
		if not workspace:Raycast(eye, point - eye, params) and not Gadgets.smokeBlocks(eye, point, c.arena.id) then
			return point
		end
	end
	return nil
end

-- Runs until the bot dies or the round ends. `enemies` returns the living opponents. A `perfect` bot
-- (Bot Bootcamp) reacts fast, aims for a visible head with every gun, has no spread (Combat), never
-- pauses between bursts, and strafes less.
function Bot.run(c: Combatant, waypoints: { Vector3 }, enemies: () -> { Combatant }, perfect: boolean?)
	local reaction = if perfect then B.PerfectReactionTime else B.ReactionTime
	if perfect then
		c.perfect = true
	end
	local humanoid, root = c.humanoid, c.root
	animate(humanoid)
	local seenSince: number? = nil
	local nextShot, burstLeft = 0, B.BurstShots
	local strafe, strafeUntil = 1, 0
	local path: { PathWaypoint } = {}
	local pathIndex, nextPath = 1, 0
	local lastPos, stuckSince = root.Position, os.clock()
	local stuck, wasRetreating = false, false
	local pathOnlyUntil = 0 -- after snagging while closing in, follow a path for a moment
	local woundedUntil: number? = nil -- one 4-second fall-back per life when health first drops low
	-- Searching for a hidden enemy: the waypoint being walked to, and those already reached or
	-- blocked without seeing them (cleared on sight, or once all are tried).
	local lastGoal: number? = nil
	local tried: { [number]: boolean } = {}

	while c.alive and root.Parent do
		local now = os.clock()
		if not Combat.isLive(c) then
			humanoid:Move(Vector3.zero)
			task.wait(B.Think)
			continue
		end

		-- Nearest enemy it can see; if none are visible, the nearest one to hunt.
		local id = Combatants.weapon(c)
		local w = if id then Config.Weapons[id] else nil
		local melee = w ~= nil and w.kind == "melee"
		local target: Combatant? = nil
		local spot: Vector3? = nil
		local best = math.huge
		for _, e in enemies() do
			local d = (e.root.Position - root.Position).Magnitude
			local seen = visiblePoint(c, e, perfect == true and not melee)
			if (seen and not spot) or ((seen ~= nil) == (spot ~= nil) and d < best) then
				target, spot, best = e, seen, d
			end
		end
		if not target then
			humanoid:Move(Vector3.zero)
			task.wait(B.Think)
			continue
		end

		if not woundedUntil and humanoid.Health < B.RetreatHealth then
			woundedUntil = now + 4
		end
		local retreating = c.reloading or c.healingUntil > 0 or (woundedUntil ~= nil and now < woundedUntil)
		if retreating ~= wasRetreating then
			wasRetreating, nextPath = retreating, 0
		end
		if not spot and c.gadget == "Medkit" and c.gadgetLeft > 0 and humanoid.Health < B.HealBelow then
			Gadgets.use(c, root.CFrame.LookVector)
		end
		if spot and w and not retreating and now >= pathOnlyUntil then
			-- Engage: face the enemy, close to the weapon's range or strafe, and fire after a human-like
			-- reaction delay (bursts for automatics). A knife walks straight in and swings on contact.
			seenSince = seenSince or now
			lastGoal = nil
			table.clear(tried)
			humanoid.AutoRotate = false
			local flat = Vector3.new(target.root.Position.X, root.Position.Y, target.root.Position.Z)
			root.CFrame = CFrame.lookAt(root.Position, flat)
			if now > strafeUntil then
				strafe = if perfect and rng:NextNumber() < 0.6 then 0 elseif rng:NextNumber() < 0.5 then -1 else 1
				strafeUntil = now + rng:NextNumber(0.6, 1.4)
			end
			-- Draw the sidearm when the primary can't reach, and back when it can.
			local primary = Config.Weapons[c.weapons[1]]
			local wantSlot = if c.weapons[2] and best > primary.botRange * 2.5 then 2 else 1
			if c.equipped ~= wantSlot and not c.reloading then
				Combat.equip(c, wantSlot)
			end
			if best > (if melee then KNIFE_STOP else w.botRange) then
				humanoid:MoveTo(target.root.Position)
				-- Walking straight at a visible enemy can snag on low cover: path around it instead. A
				-- knife pressing into its target isn't snagged.
				if (root.Position - lastPos).Magnitude > 1.5 or (melee and best < 6) then
					lastPos, stuckSince = root.Position, now
				elseif now - stuckSince > 1.5 then
					pathOnlyUntil, nextPath, stuckSince = now + 2.5, 0, now
				end
			else
				humanoid:Move(if melee then Vector3.zero else root.CFrame.RightVector * strafe)
			end
			c.aiming = not melee and (best > ADS_RANGE or w.scoped)
			humanoid.WalkSpeed = if c.aiming then Config.AimWalkSpeed else Config.WalkSpeed
			local eye = Combat.headPosition(c)
			local aimAt = if not perfect
					and not melee
					and rng:NextNumber() < B.HeadshotChance
				then (target.root.CFrame * CFrame.new(HEAD_OFFSET)).Position
				else spot
			local inReach = if melee then (aimAt - eye).Magnitude <= w.range else best <= w.botRange * 2.5
			local react = if melee then math.min(reaction, KNIFE_REACTION) else reaction
			if inReach and now - (seenSince :: number) >= react and now >= nextShot then
				-- Human-like misses, as a lateral offset at the target so the hit rate holds at range:
				-- aim starts rough and settles over the first moments, and a running target is harder.
				local settle = 1 + math.max(0, B.AimSettleSeconds - (now - (seenSince :: number))) / B.AimSettleSeconds
				local v = target.root.AssemblyLinearVelocity
				local running = if Vector3.new(v.X, 0, v.Z).Magnitude > 10 then B.MovingTargetPenalty else 1
				local miss = if perfect or melee
					then 0
					else math.min(B.AimMissCap, B.AimMissStuds * (1 + best / B.AimMissRange))
						* settle
						* running
						* (if w.scoped then B.SniperAimScale else 1)
				local toAim = aimAt - eye
				Combat.fire(c, eye, Hitbox.spread(toAim.Unit, math.deg(math.atan2(miss, toAim.Magnitude)), rng))
				burstLeft -= 1
				nextShot = now + w.fireInterval + (if w.auto then 0 else 0.2)
				if w.auto and burstLeft <= 0 and not perfect then
					burstLeft = B.BurstShots
					nextShot = now + B.BurstPause
				end
			end
		else
			-- Hunt toward the cover point nearest the enemy, or, while reloading or hurt, fall back to
			-- the nearest cover point the enemy can't see.
			seenSince = nil
			humanoid.AutoRotate = true
			c.aiming = false
			humanoid.WalkSpeed = Config.WalkSpeed
			if now >= nextPath then
				nextPath = now + 1.5
				local goal = waypoints[rng:NextInteger(1, #waypoints)]
				if retreating then
					if not stuck then
						local enemyEye, goalDist = Combat.headPosition(target), math.huge
						for _, point in waypoints do
							local d = (point - root.Position).Magnitude
							if
								d < goalDist
								and workspace:Raycast(
									enemyEye,
									point + Vector3.new(0, 2, 0) - enemyEye,
									Combat.occlusion()
								)
							then
								goal, goalDist = point, d
							end
						end
					end
				else
					-- Sweep the cover points nearest the enemy, pushing for the enemy from each one reached.
					-- One reached or blocked without seeing them isn't picked again.
					if stuck and lastGoal then
						tried[lastGoal] = true
					end
					local pick: number?, pickDist = nil, math.huge
					for i, point in waypoints do
						local d = (point - target.root.Position).Magnitude
						if not tried[i] and d < pickDist then
							pick, pickDist = i, d
						end
					end
					lastGoal = nil
					if not pick then
						table.clear(tried)
					elseif (waypoints[pick] - root.Position).Magnitude >= 8 then
						goal, lastGoal = waypoints[pick], pick
					else
						tried[pick] = true
					end
					if not stuck and not lastGoal then
						goal = target.root.Position
					end
				end
				stuck = false
				local p = PathfindingService:CreatePath({ AgentRadius = 2, AgentHeight = 5.5, AgentCanJump = true })
				local ok = pcall(p.ComputeAsync, p, root.Position, goal)
				path, pathIndex = if ok and p.Status == Enum.PathStatus.Success then p:GetWaypoints() else {}, 2
				if #path == 0 then
					humanoid:MoveTo(goal)
				end
			end
			local wp = path[pathIndex]
			if wp then
				humanoid:MoveTo(wp.Position)
				if wp.Action == Enum.PathWaypointAction.Jump then
					humanoid.Jump = true
				end
				if (wp.Position - root.Position).Magnitude < 4 then
					pathIndex += 1
				end
			end
			if (root.Position - lastPos).Magnitude > 1.5 then
				lastPos, stuckSince = root.Position, now
			elseif now - stuckSince > 1.5 then
				-- Blocked: jump, and route somewhere other than the same goal.
				humanoid.Jump = true
				stuck, nextPath, stuckSince = true, 0, now
			end
		end
		task.wait(B.Think)
	end
end

return Bot
