-- Game test, client side (test place only). Plays like a person: checks the lobby screen and
-- ownership, queues for the Shooting Range, and shoots the bot when it is in plain sight.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild("Remotes")

local function result(name: string, ok: boolean, why: string?)
	print(if ok then `PLAYTEST PASS {name}` else `PLAYTEST FAIL {name}: {why or "?"}`)
end

local ok, err = pcall(function()
	local character = player.Character or player.CharacterAdded:Wait()
	task.wait(4)
	local gui = player.PlayerGui:FindFirstChild("CampMoreManiar")
	result("lobby: bottom bar visible", gui ~= nil and gui:FindFirstChildWhichIsA("Frame") ~= nil)
	result("economy: coins published", typeof(player:GetAttribute("Coins")) == "number")
	result(
		"economy: developer owns shop weapons",
		player:GetAttribute("Owns_MothersWrath") == true and player:GetAttribute("Owns_DoubleTrouble") == true
	)

	remotes.Loadout:FireServer("Primary", "AR")
	remotes.Queue:FireServer("Join", "ShootingRange", "1v1")
	task.wait(1)
	result("queue: joined Shooting Range", player:GetAttribute("Queued") == "ShootingRange")

	local state = ReplicatedStorage:WaitForChild("Arenas"):WaitForChild("ShootingRange")
	local t0 = os.clock()
	while state:GetAttribute("Phase") ~= "Live" and os.clock() - t0 < 60 do
		task.wait(0.25)
	end
	result(
		"match: in the arena with a weapon",
		player:GetAttribute("Weapon") == "AR",
		tostring(player:GetAttribute("Weapon"))
	)

	-- Shoot the bot whenever it is in plain sight, for up to 25 seconds.
	local folder = workspace:WaitForChild("Bots"):WaitForChild("ShootingRange")
	local camera = workspace.CurrentCamera
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local hit = false
	local deadline = os.clock() + 25
	while os.clock() < deadline and not hit and state:GetAttribute("Phase") == "Live" do
		task.wait(0.3)
		character = player.Character
		local bot = folder:FindFirstChildWhichIsA("Model")
		local head = character and character:FindFirstChild("Head") :: BasePart?
		local target = bot and bot:FindFirstChild("UpperTorso") :: BasePart?
		local humanoid = bot and bot:FindFirstChildOfClass("Humanoid")
		local mine = character and character:FindFirstChildOfClass("Humanoid")
		if head and target and humanoid and mine and humanoid.Health > 0 then
			params.FilterDescendantsInstances = { character, bot :: Model }
			local los = workspace:Raycast(head.Position, target.Position - head.Position, params)
			if not los then
				-- Turn the body toward the bot (the server checks the facing), then aim and fire.
				mine:Move((target.Position - head.Position) * Vector3.new(1, 0, 1), false)
				task.wait(0.25)
				mine:Move(Vector3.zero)
				local before = humanoid.Health
				for _ = 1, 6 do
					local dir = (target.Position - camera.CFrame.Position).Unit
					camera.CFrame = CFrame.lookAt(camera.CFrame.Position, target.Position)
					remotes.Look:FireServer(dir)
					remotes.Fire:FireServer(camera.CFrame.Position, dir)
					task.wait(0.12)
				end
				task.wait(0.4)
				hit = humanoid.Health < before
			end
		end
	end
	if hit then
		result("shooting: player's shots damage the bot", true)
	else
		print("PLAYTEST INFO shooting: the bot never stood in plain sight long enough to test a hit")
	end
end)
if not ok then
	result("client test ran", false, tostring(err))
end
print("PLAYTEST CLIENT DONE")
