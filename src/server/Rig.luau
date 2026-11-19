--!strict
-- Standard uniform rig: every combatant is a scale-1 blocky R15 body in team colors with helmet, vest
-- and armbands, whatever avatar they wear. Hit detection uses Config.Hitboxes, never these parts.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Gun = require(ReplicatedStorage.Shared.Gun)

local Rig = {}

local ACCESSORY_FIELDS = {
	"HatAccessory",
	"HairAccessory",
	"FaceAccessory",
	"NeckAccessory",
	"ShouldersAccessory",
	"FrontAccessory",
	"BackAccessory",
	"WaistAccessory",
}
local BODY_FIELDS = { "Torso", "LeftArm", "RightArm", "LeftLeg", "RightLeg", "Head" }

local descriptions: { [number]: HumanoidDescription } = {}

-- The player's own face and skin tone on a standard blocky body: no packages, no scaling, no accessories.
local function normalized(source: HumanoidDescription?): HumanoidDescription
	local desc = if source then source:Clone() else Instance.new("HumanoidDescription")
	desc.HeightScale, desc.WidthScale, desc.DepthScale, desc.HeadScale = 1, 1, 1, 1
	desc.BodyTypeScale, desc.ProportionScale = 0, 0
	for _, field in BODY_FIELDS do
		(desc :: any)[field] = 0
	end
	for _, field in ACCESSORY_FIELDS do
		(desc :: any)[field] = ""
	end
	pcall(function()
		desc:SetAccessories({}, true)
	end)
	desc.Shirt, desc.Pants, desc.GraphicTShirt = 0, 0, 0
	return desc
end

local function playerDescription(player: Player): HumanoidDescription
	local cached = descriptions[player.UserId]
	if cached then
		return cached
	end
	local ok, desc = pcall(Players.GetHumanoidDescriptionFromUserId, Players, math.max(player.UserId, 1))
	local result = normalized(if ok then desc else nil)
	descriptions[player.UserId] = result
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

-- Gear, humanoid settings and the rifle. Call once the model is in the workspace.
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

	local tool = Instance.new("Tool")
	tool.Name = Config.AssaultRifle.name
	tool.CanBeDropped = false
	tool.ManualActivationOnly = true
	tool.Grip = CFrame.new(0, -0.1, 0.2) * CFrame.Angles(0, math.rad(180), 0)
	Gun.build(tool)
	tool.Parent = model
	humanoid:EquipTool(tool)
end

-- Spawns the player's standardized, team-colored character at `cf`. Yields; returns nil if they left.
function Rig.spawnPlayer(player: Player, team: Config.TeamId, cf: CFrame): Model?
	local desc = teamDescription(playerDescription(player), team)
	if not player:IsDescendantOf(Players) then
		return nil
	end
	player:LoadCharacterWithHumanoidDescriptionAsync(desc)
	local model = player.Character
	if not model or not player:IsDescendantOf(Players) then
		return nil
	end
	model:PivotTo(cf)
	Rig.outfit(model, team)
	return model
end

function Rig.spawnBot(team: Config.TeamId, name: string, cf: CFrame, parent: Instance): Model
	local base = normalized(nil)
	base.HeadColor = Color3.fromRGB(204, 142, 105)
	local model = Players:CreateHumanoidModelFromDescription(teamDescription(base, team), Enum.HumanoidRigType.R15)
	model.Name = name
	local regen = model:FindFirstChild("Health")
	if regen then
		regen:Destroy()
	end
	model:PivotTo(cf)
	model.Parent = parent
	Rig.outfit(model, team)
	local root = model:FindFirstChild("HumanoidRootPart") :: BasePart
	root:SetNetworkOwner(nil)
	return model
end

Players.PlayerRemoving:Connect(function(player)
	descriptions[player.UserId] = nil
end)

return Rig
