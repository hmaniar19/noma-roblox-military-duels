--!strict
-- Report button recorder: each arena keeps a rolling log of positions and shots, saved on a report.
local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")

local Combatants = require(script.Parent.Combatants)
local Net = require(script.Parent.Net)

type Ring = { rows: { { any } }, n: number }

local PRACTICE = "Practice" -- the lobby range is not a match
local SAMPLE_SECONDS = 0.2
local KEEP_SECONDS = 150
-- 150 s of 2v2 positions plus as many shots: about 120 bytes a row, far under the 4 MB value cap.
local CAPACITY = 2 * KEEP_SECONDS / SAMPLE_SECONDS * 4
local UNITS = "t: 0.1 s server time; pos: 0.1 studs; dir: 0.001. p = {t, name, userId (0 = bot), team, x, y, z, "
	.. "alive}; s = {t, name, ox, oy, oz, dx, dy, dz, hit, zone}"

local Report = {}

local okStore, store = pcall(function()
	return DataStoreService:GetDataStore("MilitaryDuels_Reports")
end)
local rings: { [string]: Ring } = {}
local lastArena: { [Player]: string } = setmetatable({}, { __mode = "k" }) :: any

local function now(): number
	return math.round(workspace:GetServerTimeNow() * 10)
end

local function ints(v: Vector3, scale: number): (number, number, number)
	return math.round(v.X * scale), math.round(v.Y * scale), math.round(v.Z * scale)
end

local function push(arenaId: string, row: { any })
	local ring = rings[arenaId] or { rows = {}, n = 0 }
	rings[arenaId] = ring
	ring.n += 1
	ring.rows[(ring.n - 1) % CAPACITY + 1] = row
end

function Report.shot(c: Combatants.Combatant, origin: Vector3, dir: Vector3, hitName: string?, zone: string?)
	if c.arena.id ~= PRACTICE then
		local ox, oy, oz = ints(origin, 10)
		local dx, dy, dz = ints(dir, 1000)
		push(c.arena.id, { "s", now(), c.name, ox, oy, oz, dx, dy, dz, hitName or "", zone or "" })
	end
end

local function record()
	while true do
		task.wait(SAMPLE_SECONDS)
		local t = now()
		for _, c in Combatants.all() do
			local id = c.arena.id
			if id ~= PRACTICE then
				local x, y, z = ints(c.root.Position, 10)
				push(id, { "p", t, c.name, if c.player then c.player.UserId else 0, c.team, x, y, z, c.alive })
				if c.player then
					lastArena[c.player] = id
				end
			end
		end
	end
end

-- Only rows newer than `since` (an older match on the same map may still be in the ring).
local function snapshot(ring: Ring, since: number): { { any } }
	local out = {}
	for i = math.max(1, ring.n - CAPACITY + 1), ring.n do
		local row = ring.rows[(i - 1) % CAPACITY + 1]
		if row[2] >= since then
			table.insert(out, row)
		end
	end
	return out
end

-- Saves the reporter's arena log, or the last arena they played in when back in the lobby.
local function submit(player: Player, target: number?): boolean
	local c = Combatants.byPlayer(player)
	local arenaId = if c and c.arena.id ~= PRACTICE then c.arena.id else lastArena[player]
	local ring = if arenaId then rings[arenaId] else nil
	if not arenaId or not ring then
		return false
	end
	local time = os.time()
	local rows = snapshot(ring, now() - KEEP_SECONDS * 10)
	local payload =
		{ reporter = player.UserId, target = target, time = time, map = arenaId, units = UNITS, rows = rows }
	local key = `report_{time}_{player.UserId}`
	local saved = okStore and pcall((store :: DataStore).SetAsync, store :: DataStore, key, payload)
	if not saved and RunService:IsStudio() then
		local size = #HttpService:JSONEncode(payload)
		warn(`[Report] {key}: {size} bytes, {#rows} rows (no DataStore access in Studio)`)
		return true
	end
	return saved
end

function Report.bind()
	Net.Report.OnServerEvent:Connect(function(player, target)
		local malformed = typeof(target) ~= "number" or target ~= target // 1 or target < 1 or target > 2 ^ 53
		if not Net.allow(player, "Report", 1 / 60, 1) or (target ~= nil and malformed) then
			return
		end
		local title = if submit(player, target :: number?)
			then "Report sent. Thank you!"
			else "Couldn't send the report"
		pcall(Net.Toast.FireClient, Net.Toast, player, title, "")
	end)
	task.spawn(record)
end

return Report
