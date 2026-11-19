--!strict
-- Trigger, aim and reload input; the first-person viewmodel; look updates for the server's aim
-- check; tracers and sounds for every shot the server confirms. The client never decides hits.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)
local Gun = require(ReplicatedStorage.Shared.Gun)

local player = Players.LocalPlayer :: Player
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local state = ReplicatedStorage:WaitForChild("GameState")
local Fire = remotes:WaitForChild("Fire") :: RemoteEvent
local Reload = remotes:WaitForChild("Reload") :: RemoteEvent
local Aim = remotes:WaitForChild("Aim") :: RemoteEvent
local Look = remotes:WaitForChild("Look") :: RemoteEvent
local ShotFx = remotes:WaitForChild("ShotFx") :: RemoteEvent
local Banner = remotes:WaitForChild("Banner") :: RemoteEvent

local WEAPON = Config.AssaultRifle
local HIP = CFrame.new(0.5, -0.5, -1.1)
local ADS = CFrame.new(0, -0.42, -0.95)
local LOOK_INTERVAL = 1 / (Config.AntiCheat.LookRate * 0.8)

local Weapon = {}
Weapon.aiming = false
Weapon.lastFire = 0

local firing = false
local aimBlend = 0
local recoil = 0
local lastLook = 0

local viewmodel = Instance.new("Model")
viewmodel.Name = "Viewmodel"
local vmHandle = Gun.build(viewmodel)
viewmodel.PrimaryPart = vmHandle
viewmodel:ScaleTo(0.42)
-- Cosmetic only: anchored, or gravity builds velocity between PivotTo calls until the parts are destroyed.
for _, d in viewmodel:GetDescendants() do
	if d:IsA("BasePart") then
		d.Anchored = true
	end
end
local muzzle = vmHandle:FindFirstChild("Muzzle") :: Attachment
local flash = Instance.new("PointLight")
flash.Color = Color3.fromRGB(255, 200, 120)
flash.Range = 12
flash.Brightness = 0
flash.Parent = muzzle

local fxFolder = Instance.new("Folder")
fxFolder.Name = "LocalFx"
fxFolder.Parent = workspace

local function sound(id: string, parent: Instance, volume: number)
	local s = Instance.new("Sound")
	s.SoundId = id
	s.Volume = volume
	s.Parent = parent
	s:Play()
	s.Ended:Once(function()
		s:Destroy()
	end)
	task.delay(4, function()
		if s.Parent then
			s:Destroy()
		end
	end)
end
Weapon.sound = sound

function Weapon.inCombat(): boolean
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	return player:GetAttribute("Team") ~= nil and humanoid ~= nil and humanoid.Health > 0
end

local function canShoot(): boolean
	return Weapon.inCombat()
		and state:GetAttribute("Phase") == "Live"
		and not player:GetAttribute("Reloading")
		and (player:GetAttribute("Ammo") or 0) > 0
end

local function setAiming(on: boolean)
	if Weapon.aiming ~= on then
		Weapon.aiming = on
		Aim:FireServer(on)
	end
end

local function tryFire()
	local now = os.clock()
	if now - Weapon.lastFire < WEAPON.fireInterval then
		return
	end
	if not canShoot() then
		if firing and Weapon.inCombat() and (player:GetAttribute("Ammo") or 0) <= 0 then
			sound(Config.Sounds.Empty, workspace.CurrentCamera, 0.4)
			firing = false
		end
		return
	end
	Weapon.lastFire = now
	local camera = workspace.CurrentCamera
	Look:FireServer(camera.CFrame.LookVector)
	lastLook = now
	Fire:FireServer(camera.CFrame.Position, camera.CFrame.LookVector)
	recoil = math.min(recoil + 0.35, 1.2)
	flash.Brightness = 4
	sound(Config.Sounds.Shot, camera, 0.5)
end

local function hideTool()
	local character = player.Character
	if not character then
		return
	end
	for _, d in character:GetDescendants() do
		if d:IsA("BasePart") and d:FindFirstAncestorOfClass("Tool") then
			d.LocalTransparencyModifier = 1
		end
	end
end

local function tracer(from: Vector3, to: Vector3, hitWall: boolean)
	local length = (to - from).Magnitude
	if length < 0.5 then
		return
	end
	local p = Instance.new("Part")
	p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
	p.Material = Enum.Material.Neon
	p.Color = Color3.fromRGB(255, 214, 120)
	p.Size = Vector3.new(0.07, 0.07, length)
	p.CFrame = CFrame.lookAt((from + to) / 2, to)
	p.Parent = fxFolder
	TweenService:Create(p, TweenInfo.new(0.08), { Transparency = 1 }):Play()
	task.delay(0.1, p.Destroy, p)
	if hitWall then
		local puff = Instance.new("Part")
		puff.Anchored, puff.CanCollide, puff.CanQuery, puff.CanTouch = true, false, false, false
		puff.Shape = Enum.PartType.Ball
		puff.Material = Enum.Material.SmoothPlastic
		puff.Color = Color3.fromRGB(150, 140, 120)
		puff.Size = Vector3.new(0.4, 0.4, 0.4)
		puff.Position = to
		puff.Parent = fxFolder
		TweenService:Create(puff, TweenInfo.new(0.35), { Size = Vector3.new(1.6, 1.6, 1.6), Transparency = 1 }):Play()
		task.delay(0.4, puff.Destroy, puff)
	end
end

-- The camera keeps its orientation across respawns; face it the way the new spawn faces.
Banner.OnClientEvent:Connect(function(kind: string)
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if kind == "RoundStart" and root then
		local camera = workspace.CurrentCamera
		camera.CFrame = CFrame.lookAt(camera.CFrame.Position, camera.CFrame.Position + root.CFrame.LookVector)
	end
end)

ShotFx.OnClientEvent:Connect(function(shooter: Model, origin: Vector3, hitPos: Vector3, hitWall: boolean)
	if shooter == player.Character then
		tracer(muzzle.WorldPosition, hitPos, hitWall)
		return
	end
	local from = origin
	local tool = shooter and shooter:FindFirstChildOfClass("Tool")
	local handle = tool and tool:FindFirstChild("Handle")
	local m = handle and handle:FindFirstChild("Muzzle")
	if m and m:IsA("Attachment") then
		from = m.WorldPosition
		sound(Config.Sounds.Shot, handle :: Instance, 0.8)
	end
	tracer(from, hitPos, hitWall)
end)

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then
		return
	end
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		firing = true
		tryFire()
	elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
		setAiming(true)
	elseif input.KeyCode == Enum.KeyCode.R then
		if Weapon.inCombat() and (player:GetAttribute("Ammo") or 0) < WEAPON.magazine then
			Reload:FireServer()
		end
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		firing = false
	elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
		setAiming(false)
	end
end)

player:GetAttributeChangedSignal("Reloading"):Connect(function()
	if player:GetAttribute("Reloading") then
		sound(Config.Sounds.Reload, workspace.CurrentCamera, 0.5)
	end
end)

RunService.RenderStepped:Connect(function(dt: number)
	local camera = workspace.CurrentCamera
	local active = Weapon.inCombat()
	if not active then
		viewmodel.Parent = nil
		firing = false
		setAiming(false)
		camera.FieldOfView = 70
		UserInputService.MouseIconEnabled = true
		return
	end
	UserInputService.MouseIconEnabled = false
	hideTool()
	if firing then
		tryFire()
	end
	local now = os.clock()
	if now - lastLook >= LOOK_INTERVAL then
		lastLook = now
		Look:FireServer(camera.CFrame.LookVector)
	end

	aimBlend += ((if Weapon.aiming then 1 else 0) - aimBlend) * math.min(dt * 14, 1)
	recoil = math.max(recoil - dt * 6, 0)
	flash.Brightness = math.max(flash.Brightness - dt * 60, 0)
	camera.FieldOfView = 70 - 20 * aimBlend
	local reloading = player:GetAttribute("Reloading") == true
	local offset = HIP:Lerp(ADS, aimBlend)
	local kick = CFrame.new(0, 0, recoil * 0.25) * CFrame.Angles(recoil * 0.08, 0, 0)
	local dip = if reloading then CFrame.new(0, -0.5, 0) * CFrame.Angles(-0.6, 0, 0.3) else CFrame.identity
	viewmodel.Parent = camera
	viewmodel:PivotTo(camera.CFrame * offset * kick * dip)
end)

return Weapon
