--!strict
-- Trigger, aim, reload, slot and gadget input; the first-person viewmodel for whatever is in hand;
-- look updates for the server's aim check; tracers and sounds for every shot the server confirms;
-- and following a teammate after you're eliminated. The client never decides hits.
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
local Equip = remotes:WaitForChild("Equip") :: RemoteEvent
local Gadget = remotes:WaitForChild("Gadget") :: RemoteEvent
local Reload = remotes:WaitForChild("Reload") :: RemoteEvent
local Aim = remotes:WaitForChild("Aim") :: RemoteEvent
local Look = remotes:WaitForChild("Look") :: RemoteEvent
local ShotFx = remotes:WaitForChild("ShotFx") :: RemoteEvent
local Banner = remotes:WaitForChild("Banner") :: RemoteEvent

local HIP = CFrame.new(0.5, -0.5, -1.1)
local ADS = CFrame.new(0, -0.42, -0.95)
local LOOK_INTERVAL = 2 / Config.AntiCheat.LookRate

local Weapon = {}
Weapon.aiming = false
Weapon.menuOpen = false -- set by Menu; keeps the cursor visible while a picker is open

local firing = false
local aimBlend = 0
local recoil = 0
local swing = 0
local lastLook = 0
local lastFire = 0

local viewmodel = Instance.new("Model")
viewmodel.Name = "Viewmodel"
local vmId: Config.WeaponId? = nil
local muzzle: Attachment? = nil
local flash = Instance.new("PointLight")
flash.Color = Color3.fromRGB(255, 200, 120)
flash.Range = 12
flash.Brightness = 0

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

function Weapon.current(): (Config.WeaponId?, Config.Weapon?)
	local id = player:GetAttribute("Weapon") :: Config.WeaponId?
	return id, if id then Config.Weapons[id] else nil
end

function Weapon.inCombat(): boolean
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	return player:GetAttribute("Team") ~= nil and humanoid ~= nil and humanoid.Health > 0
end

-- Rebuilds the first-person model when the weapon in hand changes.
local function refreshViewmodel(id: Config.WeaponId)
	flash.Parent = nil -- the light is reused; detach it before the old model is destroyed
	-- A fresh model each time: ScaleTo is relative to the model's current scale, so reusing one
	-- would leave every weapon after the first at full size.
	viewmodel:Destroy()
	viewmodel = Instance.new("Model")
	viewmodel.Name = "Viewmodel"
	local handle = Gun.build(viewmodel, id)
	viewmodel.PrimaryPart = handle
	viewmodel:ScaleTo(0.42)
	-- Cosmetic only: anchored, or gravity builds velocity between PivotTo calls until the parts are destroyed.
	for _, d in viewmodel:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
		end
	end
	muzzle = handle:FindFirstChild("Muzzle") :: Attachment
	flash.Parent = muzzle
	vmId = id
end

local function setAiming(on: boolean)
	if Weapon.aiming ~= on then
		Weapon.aiming = on
		Aim:FireServer(on)
	end
end

local function tryFire()
	local _, w = Weapon.current()
	local now = os.clock()
	if not w or now - lastFire < w.fireInterval then
		return
	end
	if not w.auto then
		firing = false -- semi-automatic: one shot per click
	end
	local live = Weapon.inCombat() and state:GetAttribute("Phase") == "Live"
	if not live or player:GetAttribute("Reloading") or player:GetAttribute("Healing") then
		return
	end
	if w.kind == "gun" and (player:GetAttribute("Ammo") or 0) <= 0 then
		sound(Config.Sounds.Empty, workspace.CurrentCamera, 0.4)
		firing = false
		return
	end
	lastFire = now
	local camera = workspace.CurrentCamera
	Look:FireServer(camera.CFrame.LookVector)
	lastLook = now
	Fire:FireServer(camera.CFrame.Position, camera.CFrame.LookVector)
	if w.kind == "melee" then
		swing = 1
		sound(Config.Sounds.Slash, camera, 0.5)
	else
		recoil = math.min(recoil + (if w.pellets > 1 or not w.auto then 1 else 0.35), 1.6)
		flash.Brightness = 4
		sound(Config.Sounds.Shot, camera, 0.5)
	end
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

ShotFx.OnClientEvent:Connect(
	function(shooter: Model, origin: Vector3, hitPos: Vector3, hitWall: boolean, melee: boolean)
		local tool = shooter and shooter:FindFirstChildOfClass("Tool")
		local handle = tool and tool:FindFirstChild("Handle")
		if shooter == player.Character then
			if not melee and muzzle then
				tracer(muzzle.WorldPosition, hitPos, hitWall)
			end
			return
		end
		if handle then
			sound(if melee then Config.Sounds.Slash else Config.Sounds.Shot, handle, 0.8)
		end
		local m = handle and handle:FindFirstChild("Muzzle")
		if not melee then
			tracer(if m and m:IsA("Attachment") then m.WorldPosition else origin, hitPos, hitWall)
		end
	end
)

local function equipSlot(index: number)
	local slots = string.split((player:GetAttribute("Slots") or "") :: string, ",")
	if Weapon.inCombat() and slots[index] and slots[index] ~= "" then
		firing = false
		Equip:FireServer(index)
	end
end

local function slotIndex(): (number, number)
	local slots = string.split((player:GetAttribute("Slots") or "") :: string, ",")
	return table.find(slots, player:GetAttribute("Weapon") :: string) or 1, #slots
end

local KEY_SLOTS = { [Enum.KeyCode.One] = 1, [Enum.KeyCode.Two] = 2, [Enum.KeyCode.Three] = 3 }

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then
		return
	end
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		firing = true
		tryFire()
	elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
		setAiming(true)
	elseif KEY_SLOTS[input.KeyCode] then
		equipSlot(KEY_SLOTS[input.KeyCode])
	elseif input.KeyCode == Enum.KeyCode.G or input.KeyCode == Enum.KeyCode.Four then
		if Weapon.inCombat() and (player:GetAttribute("GadgetLeft") or 0) > 0 then
			Gadget:FireServer(workspace.CurrentCamera.CFrame.LookVector)
		end
	elseif input.KeyCode == Enum.KeyCode.R then
		local id, w = Weapon.current()
		if Weapon.inCombat() and id and w and w.kind == "gun" and (player:GetAttribute("Ammo") or 0) < w.magazine then
			Reload:FireServer()
		end
	end
end)

UserInputService.InputChanged:Connect(function(input, processed)
	if not processed and input.UserInputType == Enum.UserInputType.MouseWheel then
		local index, count = slotIndex()
		if count > 1 then
			equipSlot((index - 1 + (if input.Position.Z < 0 then 1 else -1)) % count + 1)
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

-- After you're eliminated, watch a teammate who is still fighting.
local function followTeammate(camera: Camera)
	local team = player:GetAttribute("Team")
	if not team or state:GetAttribute("Phase") ~= "Live" then
		return
	end
	local current = camera.CameraSubject
	if current and current:IsA("Humanoid") and current.Health > 0 and current.Parent ~= player.Character then
		return
	end
	local candidates: { Instance } = {}
	for _, other in Players:GetPlayers() do
		table.insert(candidates, other.Character :: any)
	end
	local bots = workspace:FindFirstChild("Bots")
	for _, bot in (if bots then bots:GetChildren() else {}) :: { Instance } do
		table.insert(candidates, bot)
	end
	for _, model in candidates do
		if model:GetAttribute("Team") == team and model ~= player.Character then
			local humanoid = model:FindFirstChildOfClass("Humanoid")
			if humanoid and humanoid.Health > 0 then
				camera.CameraSubject = humanoid
				return
			end
		end
	end
end

local nextFollowCheck = 0
RunService.RenderStepped:Connect(function(dt: number)
	local camera = workspace.CurrentCamera
	if not Weapon.inCombat() then
		viewmodel.Parent = nil
		firing = false
		setAiming(false)
		camera.FieldOfView = 70
		UserInputService.MouseIconEnabled = true
		if os.clock() > nextFollowCheck then
			nextFollowCheck = os.clock() + 0.5
			followTeammate(camera)
		end
		return
	end
	local id, w = Weapon.current()
	if not id or not w then
		viewmodel.Parent = nil
		return
	end
	if id ~= vmId then
		refreshViewmodel(id)
	end
	UserInputService.MouseIconEnabled = Weapon.menuOpen
	hideTool()
	if firing then
		tryFire()
	end
	local now = os.clock()
	if now - lastLook >= LOOK_INTERVAL then
		lastLook = now
		Look:FireServer(camera.CFrame.LookVector)
	end

	local scoped = id == "Sniper" and aimBlend > 0.9
	aimBlend += ((if Weapon.aiming and w.kind == "gun" then 1 else 0) - aimBlend) * math.min(dt * 14, 1)
	recoil = math.max(recoil - dt * 6, 0)
	swing = math.max(swing - dt * 5, 0)
	flash.Brightness = math.max(flash.Brightness - dt * 60, 0)
	camera.FieldOfView = 70 - (if id == "Sniper" then 50 else 20) * aimBlend
	local reloading = player:GetAttribute("Reloading") == true or player:GetAttribute("Healing") == true
	local offset = HIP:Lerp(ADS, aimBlend)
	local kick = CFrame.new(0, 0, recoil * 0.25) * CFrame.Angles(recoil * 0.08, 0, 0)
	local stab = CFrame.new(-0.3 * swing, 0.1 * swing, -0.9 * swing) * CFrame.Angles(0, 0, -0.6 * swing)
	local dip = if reloading then CFrame.new(0, -0.5, 0) * CFrame.Angles(-0.6, 0, 0.3) else CFrame.identity
	viewmodel.Parent = if scoped then nil else camera
	viewmodel:PivotTo(camera.CFrame * offset * kick * stab * dip)
end)

return Weapon
