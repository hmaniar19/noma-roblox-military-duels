--!strict
-- A server-controlled duelist that fills an empty slot. It plays by the same rules as players:
-- it shoots through Combat.fire, so walls, ammo, reloads, spread and hitboxes all apply.
local PathfindingService = game:GetService("PathfindingService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Combat = require(script.Parent.Combat)
local Combatants = require(script.Parent.Combatants)
local Config = require(ReplicatedStorage.Shared.Config)
local Hitbox = require(ReplicatedStorage.Shared.Hitbox)

type Combatant = Combatants.Combatant

local B = Config.Bot
local BODY_OFFSET = Config.Hitboxes[2].offset

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

local function visiblePoint(c: Combatant, enemy: Combatant): Vector3?
	local eye = Combat.headPosition(c)
	local params = Combat.occlusion()
	for _, offset in { Config.Hitboxes[1].offset, BODY_OFFSET } do
		local point = (enemy.root.CFrame * CFrame.new(offset)).Position
		if not workspace:Raycast(eye, point - eye, params) then
			return point
		end
	end
	return nil
end

-- Runs until the bot dies or the round ends. `enemies` returns the living opponents.
function Bot.run(c: Combatant, waypoints: { Vector3 }, enemies: () -> { Combatant })
	local humanoid, root = c.humanoid, c.root
	animate(humanoid)
	local seenSince: number? = nil
	local nextShot, burstLeft = 0, B.BurstShots
	local strafe, strafeUntil = 1, 0
	local path: { PathWaypoint } = {}
	local pathIndex, nextPath = 1, 0
	local lastPos, stuckSince = root.Position, os.clock()

	while c.alive and root.Parent do
		local now = os.clock()
		if not Combat.isLive() then
			humanoid:Move(Vector3.zero)
			task.wait(B.Think)
			continue
		end

		local target: Combatant? = nil
		local best = math.huge
		for _, e in enemies() do
			local d = (e.root.Position - root.Position).Magnitude
			if d < best then
				target, best = e, d
			end
		end
		if not target then
			humanoid:Move(Vector3.zero)
			task.wait(B.Think)
			continue
		end

		local spot = visiblePoint(c, target)
		if spot then
			-- Engage: face the enemy, strafe, shoot in bursts after a human-like reaction delay.
			seenSince = seenSince or now
			humanoid.AutoRotate = false
			local flat = Vector3.new(target.root.Position.X, root.Position.Y, target.root.Position.Z)
			root.CFrame = CFrame.lookAt(root.Position, flat)
			if now > strafeUntil then
				strafe = if rng:NextNumber() < 0.5 then -1 else 1
				strafeUntil = now + rng:NextNumber(0.6, 1.4)
			end
			humanoid:Move(root.CFrame.RightVector * strafe)
			c.aiming = best > 60
			if now - (seenSince :: number) >= B.ReactionTime and now >= nextShot then
				local aimAt = if rng:NextNumber() < B.HeadshotChance
					then (target.root.CFrame * CFrame.new(Config.Hitboxes[1].offset)).Position
					else spot
				local eye = Combat.headPosition(c)
				local err = B.AimErrorDegrees * (1 + best / 120)
				Combat.fire(c, eye, Hitbox.spread((aimAt - eye).Unit, err, rng))
				burstLeft -= 1
				nextShot = now + Config.AssaultRifle.fireInterval
				if burstLeft <= 0 then
					burstLeft = B.BurstShots
					nextShot = now + B.BurstPause
				end
			end
		else
			-- Hunt: path toward the cover point nearest the enemy.
			seenSince = nil
			humanoid.AutoRotate = true
			c.aiming = false
			if now >= nextPath or pathIndex > #path then
				nextPath = now + 1.5
				local goal = waypoints[1]
				local goalDist = math.huge
				for _, w in waypoints do
					local d = (w - target.root.Position).Magnitude
					if d < goalDist then
						goal, goalDist = w, d
					end
				end
				if (goal - root.Position).Magnitude < 8 then
					goal = target.root.Position
				end
				local p = PathfindingService:CreatePath({ AgentRadius = 2, AgentHeight = 5.5, AgentCanJump = true })
				local ok = pcall(p.ComputeAsync, p, root.Position, goal)
				if ok and p.Status == Enum.PathStatus.Success then
					path, pathIndex = p:GetWaypoints(), 2
				else
					path, pathIndex = {}, 1
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
				humanoid.Jump = true
				nextPath = 0
				stuckSince = now
			end
		end
		task.wait(B.Think)
	end
end

return Bot
