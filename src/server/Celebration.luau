--!strict
-- Match-win celebration, staged in the sky above the arena while everyone's camera sweeps across it
-- (client: Hud). The winners stand on a podium: they cheer, dance, then stand menacingly with their
-- primary weapon, pointing down at the losers, who lie face down in front of them with a winner's
-- melee weapon planted in their backs. Confetti and fireworks in the winning team's color. Blocky
-- characters and no blood: within the game's Mild rating. Animations are Roblox's default R15 emotes.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Gun = require(ReplicatedStorage.Shared.Gun)
local Rig = require(script.Parent.Rig)

export type Member = {
	player: Player?,
	team: Config.TeamId,
	name: string,
	userId: number?, -- a bot's friend avatar
	primary: string,
	melee: string,
}

local Celebration = {}

local EMOTES = {
	cheer = "rbxassetid://507770677",
	dance = "rbxassetid://507771019",
	point = "rbxassetid://507770453",
	hold = "rbxassetid://507768375",
}

local function play(model: Model, emote: string, looped: boolean): AnimationTrack?
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return nil
	end
	local animator: Animator? = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		local created = Instance.new("Animator")
		created.Parent = humanoid
		animator = created
	end
	assert(animator, "animator")
	local anim = Instance.new("Animation")
	anim.AnimationId = EMOTES[emote]
	local ok, track = pcall(animator.LoadAnimation, animator, anim)
	if not ok or not track then
		return nil
	end
	track.Priority = Enum.AnimationPriority.Action
	track.Looped = looped
	track:Play(0.2)
	return track
end

local function part(folder: Instance, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?): Part
	local p = Instance.new("Part")
	p.Anchored, p.Size, p.CFrame, p.Color = true, size, cf, color
	p.Material = material or Enum.Material.Concrete
	p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
	p.Parent = folder
	return p
end

-- A weapon model on its own (not held), all parts anchored, planted point-down with its tip at `tip`.
local function plant(folder: Instance, id: string, tip: Vector3)
	local model = Instance.new("Model")
	model.Name = id
	local handle = Gun.build(model, id)
	model.PrimaryPart = handle
	local muzzle = handle:FindFirstChild("Muzzle") :: Attachment
	local length = muzzle.Position.Magnitude
	model:PivotTo(CFrame.lookAt(tip + Vector3.new(0, length, 0), tip))
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
		end
	end
	model.Parent = folder
end

local function equip(model: Model, id: string)
	local tool = Instance.new("Tool")
	tool.Name = Config.Weapons[id].name
	tool.CanBeDropped = false
	tool.Grip = Gun.Grip
	Gun.build(tool, id)
	tool.Parent = model
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid:EquipTool(tool)
	end
end

local function firework(folder: Instance, from: Vector3, color: Color3)
	local shell = part(folder, Vector3.new(0.6, 0.6, 0.6), CFrame.new(from), color, Enum.Material.Neon)
	shell.Shape = Enum.PartType.Ball
	shell.CanCollide = false
	local apex = from + Vector3.new(math.random(-6, 6), math.random(22, 30), math.random(-4, 4))
	local steps = 20
	for i = 1, steps do
		shell.Position = from:Lerp(apex, i / steps)
		task.wait(0.03)
	end
	shell.Transparency = 1
	local burst = Instance.new("ParticleEmitter")
	burst.Color = ColorSequence.new(color, Color3.new(1, 1, 1))
	burst.LightEmission = 1
	burst.Size = NumberSequence.new(0.6, 0)
	burst.Lifetime = NumberRange.new(0.8, 1.4)
	burst.Speed = NumberRange.new(18, 26)
	burst.SpreadAngle = Vector2.new(180, 180)
	burst.Acceleration = Vector3.new(0, -12, 0)
	burst.Rate = 0
	burst.Parent = shell
	burst:Emit(70)
	task.delay(2, shell.Destroy, shell)
end

-- Builds and runs the celebration above `ground`. Returns the point the cameras should look at and
-- a function that tears everything down (it also clears each player's "Celebrating" attribute).
function Celebration.play(
	ground: Vector3,
	winner: Config.TeamId,
	members: { Member },
	botsFolder: Instance
): (Vector3, () -> ())
	local folder = Instance.new("Folder")
	folder.Name = "Celebration"
	folder.Parent = workspace
	local stage = CFrame.new(ground + Vector3.new(0, 160, 0))
	local color = Config.Teams[winner].hud
	part(folder, Vector3.new(44, 2, 30), stage * CFrame.new(0, -1, 0), Color3.fromRGB(60, 62, 66))
	part(folder, Vector3.new(30, 1.6, 8), stage * CFrame.new(0, 0.8, -6), color, Enum.Material.SmoothPlastic) -- podium
	for _, x in { -20, 20 } do
		part(
			folder,
			Vector3.new(0.4, 14, 0.4),
			stage * CFrame.new(x, 7, -12),
			Color3.fromRGB(200, 200, 200),
			Enum.Material.Metal
		)
		part(folder, Vector3.new(0.2, 4, 6), stage * CFrame.new(x, 12, -9), color, Enum.Material.Fabric)
	end

	local winners: { Member }, losers: { Member } = {}, {}
	for _, m in members do
		table.insert(if m.team == winner then winners else losers, m)
	end

	local function spawn(m: Member, cf: CFrame): Model?
		local model: Model? = nil
		pcall(function()
			if m.player then
				m.player:SetAttribute("Celebrating", true)
				m.player.CameraMode = Enum.CameraMode.Classic
				model = Rig.spawnPlayer(m.player, m.team, cf)
			else
				model = Rig.spawnBot(m.team, m.name, cf, botsFolder, m.userId)
			end
		end)
		if model then
			(model.PrimaryPart or model:FindFirstChild("HumanoidRootPart") :: BasePart).Anchored = true
		end
		return model
	end

	-- Winners on the podium facing the camera side (+z); losers face down in front of them.
	local jobs = {}
	for i, m in winners do
		local x = (i - (#winners + 1) / 2) * 6
		table.insert(jobs, function()
			local model = spawn(m, stage * CFrame.new(x, 4.6, -6) * CFrame.Angles(0, math.pi, 0))
			if not model then
				return
			end
			play(model, "cheer", false)
			task.wait(1.6)
			local dance = play(model, "dance", true)
			task.wait(2.4)
			if dance then
				dance:Stop(0.3)
			end
			equip(model, m.primary)
			play(model, "hold", true)
			play(model, "point", false)
		end)
	end
	for i, m in losers do
		local x = (i - (#losers + 1) / 2) * 7
		local blade = winners[((i - 1) % math.max(#winners, 1)) + 1]
		table.insert(jobs, function()
			local lying = stage * CFrame.new(x, 0.6, 2) * CFrame.Angles(-math.pi / 2, 0, 0)
			local model = spawn(m, lying)
			if not model then
				return
			end
			local humanoid = model:FindFirstChildOfClass("Humanoid")
			if humanoid then
				humanoid.PlatformStand = true
			end
			if blade then
				-- Planted point-down in their back, hilt up (the tip sits just inside the torso).
				plant(folder, blade.melee, (stage * CFrame.new(x, 0.7, 2.3)).Position)
			end
		end)
	end
	for _, job in jobs do
		task.spawn(job)
	end

	-- Confetti over the whole stage and fireworks from its corners.
	local cloud = part(folder, Vector3.new(44, 1, 30), stage * CFrame.new(0, 22, 0), color)
	cloud.Transparency, cloud.CanCollide = 1, false
	local confetti = Instance.new("ParticleEmitter")
	confetti.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, color),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 215, 90)),
		ColorSequenceKeypoint.new(1, Color3.new(1, 1, 1)),
	})
	confetti.Size = NumberSequence.new(0.35)
	confetti.Lifetime = NumberRange.new(3, 4)
	confetti.Rate = 90
	confetti.Speed = NumberRange.new(2, 5)
	confetti.Acceleration = Vector3.new(0, -9, 0)
	confetti.RotSpeed = NumberRange.new(-200, 200)
	confetti.Rotation = NumberRange.new(0, 360)
	confetti.SpreadAngle = Vector2.new(30, 30)
	confetti.EmissionDirection = Enum.NormalId.Bottom
	confetti.Parent = cloud
	local running = true
	task.spawn(function()
		local corners =
			{ Vector3.new(-20, 0, -12), Vector3.new(20, 0, -12), Vector3.new(-20, 0, 12), Vector3.new(20, 0, 12) }
		local n = 0
		while running do
			n += 1
			task.spawn(firework, folder, (stage * CFrame.new(corners[(n % 4) + 1])).Position, color)
			task.wait(0.6)
		end
	end)

	return stage.Position + Vector3.new(0, 3, 0),
		function()
			running = false
			for _, m in members do
				if m.player then
					m.player:SetAttribute("Celebrating", nil)
				end
			end
			folder:Destroy()
		end
end

return Celebration
