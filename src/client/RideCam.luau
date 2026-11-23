--!strict
-- Chase camera for the Freeze drop-in ride: riders are anchored aboard the vehicle, where first
-- person would only show its walls behind the loadout picker. The mouse is left alone; the picker's
-- Modal buttons free it.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Weapon: any = require(script.Parent.Weapon)
local state = require(script.Parent.ArenaState)

local player = Players.LocalPlayer

local RideCam = {}

function RideCam.start()
	local riding = false

	local function stop(root: BasePart?)
		riding = false
		-- A running cutscene owns the camera; leave it be.
		if Weapon.cutscene then
			return
		end
		local camera = workspace.CurrentCamera
		camera.CameraType = Enum.CameraType.Custom
		if root then
			-- Hand back first person facing the way the landing spot faces, as the RoundStart snap does.
			local eye = root.Position + Vector3.new(0, 1.5, 0)
			camera.CFrame = CFrame.lookAt(eye, eye + root.CFrame.LookVector)
		end
	end

	RunService.RenderStepped:Connect(function(dt: number)
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		local active = root ~= nil and root.Anchored and state:GetAttribute("Phase") == "Freeze" and not Weapon.cutscene
		if not root or not active then
			if riding then
				stop(if root and root.Parent then root else nil)
			end
			return
		end
		local camera = workspace.CurrentCamera
		camera.CameraType = Enum.CameraType.Scriptable
		local wide = state:GetAttribute("Drop") == "Parachute"
		local back, up = if wide then 18 else 12, if wide then 8 else 5
		local flat = root.CFrame.LookVector * Vector3.new(1, 0, 1)
		flat = if flat.Magnitude > 0.01 then flat.Unit else Vector3.new(0, 0, -1)
		local target = root.Position + Vector3.new(0, 2, 0)
		local goal = CFrame.lookAt(root.Position - flat * back + Vector3.new(0, up, 0), target)
		camera.CFrame = if riding then camera.CFrame:Lerp(goal, 1 - math.exp(-dt * 6)) else goal
		-- Focus at the rider so the default transparency logic shows their character.
		camera.Focus = CFrame.new(target)
		riding = true
	end)
end

return RideCam
