--!strict
-- All RemoteEvents, created by the server. Inbound payloads are type-checked and rate-limited here,
-- so handlers only ever see well-formed values.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = {}

local folder = Instance.new("Folder")
folder.Name = "Remotes"
folder.Parent = ReplicatedStorage

local function event(name: string): RemoteEvent
	local e = Instance.new("RemoteEvent")
	e.Name = name
	e.Parent = folder
	return e
end

-- client -> server
Net.Fire = event("Fire")
Net.Equip = event("Equip")
Net.Gadget = event("Gadget")
Net.Loadout = event("Loadout")
Net.Mode = event("Mode")
Net.Reload = event("Reload")
Net.Aim = event("Aim")
Net.Look = event("Look")
-- server -> client
Net.ShotFx = event("ShotFx")
Net.HitConfirm = event("HitConfirm")
Net.Damaged = event("Damaged")
Net.Banner = event("Banner")

type Bucket = { tokens: number, at: number }
local buckets: { [Player]: { [string]: Bucket } } = {}

-- Token bucket: `rate` events per second with a burst of `burst`.
function Net.allow(player: Player, key: string, rate: number, burst: number): boolean
	local perPlayer = buckets[player]
	if not perPlayer then
		perPlayer = {}
		buckets[player] = perPlayer
	end
	local now = os.clock()
	local b = perPlayer[key]
	if not b then
		b = { tokens = burst, at = now }
		perPlayer[key] = b
	end
	b.tokens = math.min(burst, b.tokens + (now - b.at) * rate)
	b.at = now
	if b.tokens < 1 then
		return false
	end
	b.tokens -= 1
	return true
end

function Net.isVector(v: unknown, limit: number): boolean
	if typeof(v) ~= "Vector3" then
		return false
	end
	local vec = v :: Vector3
	for _, n in { vec.X, vec.Y, vec.Z } do
		if n ~= n or math.abs(n) > limit then
			return false
		end
	end
	return true
end

function Net.isDirection(v: unknown): boolean
	return Net.isVector(v, 2) and math.abs((v :: Vector3).Magnitude - 1) < 0.05
end

Players.PlayerRemoving:Connect(function(player)
	buckets[player] = nil
end)

return Net
