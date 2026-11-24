--!strict
-- Team uniform rig: every player keeps their own Roblox avatar (face, skin, hair and accessories)
-- on the standard R15 body, dressed in their team's military uniform: team-colored body, helmet,
-- vest and armbands. Hats come off for the helmet; clothing comes off so the uniform shows. Body
-- parts and size are standard so the look matches the hitbox; hit detection uses Config.Hitboxes.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local Rig = {}

-- Layered accessories that are clothing; they would cover the uniform.
local CLOTHING = {
	[Enum.AccessoryType.TShirt] = true,
	[Enum.AccessoryType.Shirt] = true,
	[Enum.AccessoryType.Pants] = true,
	[Enum.AccessoryType.Jacket] = true,
	[Enum.AccessoryType.Sweater] = true,
	[Enum.AccessoryType.Shorts] = true,
	[Enum.AccessoryType.DressSkirt] = true,
}

local descriptions: { [number]: HumanoidDescription } = {}

-- The avatar on the standard R15 body at standard size, without hats (the helmet takes their
-- place) or clothing.
local function normalized(source: HumanoidDescription?): HumanoidDescription
	local desc = if source then source:Clone() else Instance.new("HumanoidDescription")
	desc.HeightScale, desc.WidthScale, desc.DepthScale, desc.HeadScale = 1, 1, 1, 1
	desc.BodyTypeScale, desc.ProportionScale = 0, 0
	desc.Head, desc.Torso = 0, 0
	desc.LeftArm, desc.RightArm, desc.LeftLeg, desc.RightLeg = 0, 0, 0, 0
	desc.HatAccessory = ""
	pcall(function()
		local keep = {}
		for _, accessory in desc:GetAccessories(true) do
			if accessory.AccessoryType ~= Enum.AccessoryType.Hat and not CLOTHING[accessory.AccessoryType] then
				table.insert(keep, accessory)
			end
		end
		desc:SetAccessories(keep, true)
	end)
	desc.Shirt, desc.Pants, desc.GraphicTShirt = 0, 0, 0
	return desc
end

-- Anyone's avatar by user id (players, and the friends bots dress up as), cached for the session.
local function avatarDescription(userId: number): HumanoidDescription
	local cached = descriptions[userId]
	if cached then
		return cached
	end
	local ok, desc = pcall(Players.GetHumanoidDescriptionFromUserId, Players, math.max(userId, 1))
	local result = normalized(if ok then desc else nil)
	descriptions[userId] = result
	return result
end

local function teamDescription(base: HumanoidDescription, team: Config.TeamId): HumanoidDescription
	local colors = Config.Teams[team]
	local d = base:Clone()
	local trousers = colors.uniform:Lerp(Color3.new(0, 0, 0), 0.25)
	d.TorsoColor, d.LeftArmColor, d.RightArmColor = colors.uniform, colors.uniform, colors.uniform
	d.LeftLegColor, d.RightLegColor = trousers, trousers
	return d
end

local function gear(model: Model, partName: string, size: Vector3, offset: CFrame, color: Color3)
	local attachTo = model:FindFirstChild(partName)
	if not attachTo or not attachTo:IsA("BasePart") then
		return
	end
	local p = Instance.new("Part")
	p.Name = "Gear"
	p.Size = size
	p.Color = color
	p.Material = Enum.Material.Fabric
	p.CanCollide, p.CanQuery, p.CanTouch, p.Massless = false, false, false, true
	p.CFrame = attachTo.CFrame * offset
	local weld = Instance.new("WeldConstraint")
	weld.Part0, weld.Part1 = attachTo, p
	weld.Parent = p
	p.Parent = model
end

-- Gear and humanoid settings. Call once the model is in the workspace; Combat.arm adds weapons.
function Rig.outfit(model: Model, team: Config.TeamId)
	local colors = Config.Teams[team]
	local humanoid = model:FindFirstChildOfClass("Humanoid") :: Humanoid
	humanoid.MaxHealth = Config.MaxHealth
	humanoid.Health = Config.MaxHealth
	humanoid.WalkSpeed = Config.WalkSpeed
	humanoid.UseJumpPower = true
	humanoid.JumpPower = Config.JumpPower
	humanoid.BreakJointsOnDeath = false
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff

	gear(
		model,
		"Head",
		Vector3.new(1.35, 0.6, 1.35),
		CFrame.new(0, 0.45, 0),
		colors.uniform:Lerp(Color3.fromRGB(60, 70, 50), 0.35)
	)
	gear(
		model,
		"UpperTorso",
		Vector3.new(2.1, 1.3, 1.2),
		CFrame.new(0, -0.05, 0),
		colors.uniform:Lerp(Color3.new(0, 0, 0), 0.4)
	)
	gear(model, "LeftUpperArm", Vector3.new(1.08, 0.3, 1.08), CFrame.new(0, 0.1, 0), colors.armband)
	gear(model, "RightUpperArm", Vector3.new(1.08, 0.3, 1.08), CFrame.new(0, 0.1, 0), colors.armband)
end

-- Spawns the player's standardized, team-colored character at `cf`. Yields; returns nil if they left.
function Rig.spawnPlayer(player: Player, team: Config.TeamId, cf: CFrame): Model?
	local desc = teamDescription(avatarDescription(player.UserId), team)
	if not player:IsDescendantOf(Players) then
		return nil
	end
	-- Stream the destination to their client before the character exists: a new character starts at
	-- the default spawn point, so the move below must follow the load with no wait in between.
	pcall(player.RequestStreamAroundAsync, player, cf.Position)
	player:LoadCharacterWithHumanoidDescriptionAsync(desc)
	local model = player.Character
	if not model or not model:FindFirstChild("HumanoidRootPart") or not player:IsDescendantOf(Players) then
		return nil
	end
	model:PivotTo(cf)
	Rig.outfit(model, team)
	return model
end

-- A bot in team uniform. With `userId` it wears that user's avatar (a player's friend); otherwise a
-- standard blocky recruit.
function Rig.spawnBot(team: Config.TeamId, name: string, cf: CFrame, parent: Instance, userId: number?): Model
	local base: HumanoidDescription
	if userId then
		base = avatarDescription(userId)
	else
		base = normalized(nil)
		base.HeadColor = Color3.fromRGB(204, 142, 105)
	end
	local model = Players:CreateHumanoidModelFromDescription(teamDescription(base, team), Enum.HumanoidRigType.R15)
	model.Name = name
	local regen = model:FindFirstChild("Health")
	if regen then
		regen:Destroy()
	end
	model:PivotTo(cf)
	model.Parent = parent
	Rig.outfit(model, team)
	return model
end

Players.PlayerRemoving:Connect(function(player)
	descriptions[player.UserId] = nil
end)

-- Roblox's default R15 animations by name (emotes add their ids), for the celebration, cutscene and
-- lobby stand-ins.
local ANIMATIONS: { [string]: string } = {
	cheer = "rbxassetid://507770677",
	dance = "rbxassetid://507771019",
	point = "rbxassetid://507770453",
	hold = "rbxassetid://507768375",
	run = "rbxassetid://913376220",
}

-- Loaded tracks per animator, so replays never pile up LoadAnimation tracks (the limit is 256).
local tracks: { [Animator]: { [string]: AnimationTrack } } = setmetatable({}, { __mode = "k" }) :: any

function Rig.animate(model: Model, name: string, looped: boolean): AnimationTrack?
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
	local id = ANIMATIONS[name]
	if not id then
		return nil
	end
	local cache = tracks[animator] or {}
	tracks[animator] = cache
	local track = cache[id]
	if not track then
		local anim = Instance.new("Animation")
		anim.AnimationId = id
		local ok, loaded = pcall(animator.LoadAnimation, animator, anim)
		if not ok or not loaded then
			return nil
		end
		track = loaded
		cache[id] = loaded
	end
	assert(track, "track")
	track.Priority = Enum.AnimationPriority.Action
	track.Looped = looped
	track:Play(0.2)
	return track
end

-- Poses built from code: the right shoulder's turn, held for two seconds.
local POSES: { [string]: CFrame } = {
	salute = CFrame.Angles(math.rad(150), math.rad(-35), math.rad(40)), -- hand raised to the brow
	goldsalute = CFrame.Angles(math.rad(150), math.rad(-35), math.rad(40)),
	handshake = CFrame.Angles(math.rad(75), 0, 0), -- right hand held out in front
}

-- Plays an emote from Config.Emotes: an animation id, or "pose:<name>" from POSES. The gold salute
-- adds a gold glint.
function Rig.emote(model: Model, anim: string)
	if anim:sub(1, 5) ~= "pose:" then
		ANIMATIONS[anim] = anim
		Rig.animate(model, anim, false)
		return
	end
	local name = anim:sub(6)
	local turn = POSES[name]
	local arm = model:FindFirstChild("RightUpperArm")
	local joint = arm and arm:FindFirstChild("RightShoulder")
	if not turn or not joint or not joint:IsA("Motor6D") or model:GetAttribute("Posing") then
		return
	end
	model:SetAttribute("Posing", true)
	local rest = joint.C0
	joint.C0 = rest * turn
	local glint: Sparkles? = nil
	if name == "goldsalute" then
		local sparkles = Instance.new("Sparkles")
		sparkles.SparkleColor = Color3.fromRGB(235, 190, 60)
		sparkles.Parent = model:FindFirstChild("RightHand")
		glint = sparkles
	end
	task.delay(2, function()
		joint.C0 = rest
		if glint then
			glint:Destroy()
		end
		model:SetAttribute("Posing", nil)
	end)
end

-- The "EDDIE'S HONOR" name tag over a level-200 player's head, on every character (lobby, arenas,
-- celebration). Hidden from its owner, whose first-person camera sits right under it.
local function titleTag(player: Player, character: Model)
	local head = character:WaitForChild("Head", 5)
	if not head or player.Character ~= character then
		return
	end
	local old = head:FindFirstChild("TitleTag")
	if old then
		old:Destroy()
	end
	if player:GetAttribute("Title") ~= "EddiesHonor" then
		return
	end
	local tag = Instance.new("BillboardGui")
	tag.Name = "TitleTag"
	tag.Size = UDim2.fromScale(4, 0.6)
	tag.StudsOffset = Vector3.new(0, 2.4, 0)
	tag.AlwaysOnTop = false
	tag.MaxDistance = 60
	tag.LightInfluence = 0
	tag.PlayerToHideFrom = player
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = "EDDIE'S HONOR"
	label.TextScaled = true
	label.Font = Enum.Font.GothamBold
	label.TextColor3 = Color3.fromRGB(235, 190, 60)
	label.TextStrokeColor3 = Color3.fromRGB(60, 40, 0)
	label.TextStrokeTransparency = 0.2
	label.Parent = tag
	tag.Parent = head
end

local function watchTitle(player: Player)
	player.CharacterAdded:Connect(function(character)
		titleTag(player, character)
	end)
	player:GetAttributeChangedSignal("Title"):Connect(function()
		local character = player.Character
		if character then
			titleTag(player, character)
		end
	end)
	local character = player.Character
	if character then
		titleTag(player, character)
	end
end
Players.PlayerAdded:Connect(watchTitle)
for _, player in Players:GetPlayers() do
	task.spawn(watchTitle, player)
end

return Rig
