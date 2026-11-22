--!strict
-- Report button recorder. Each arena records its current round (positions 5 times a second and every
-- trigger pull); when a round ends it becomes that arena's "last round". A report saves the reporter's
-- last completed round (or the one in progress if none has finished yet), tagged by match and round.
local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")

local Combatants = require(script.Parent.Combatants)
local Net = require(script.Parent.Net)

type Log = { match: string, round: number, rows: { { any } } }

local SAMPLE_SECONDS = 0.2
-- A 2:00 round plus its ride is ~130 s; 4 fighters at 5 Hz plus shots stays far under this cap, and
-- at about 120 bytes a row far under DataStore's 4 MB value limit.
local MAX_ROWS = 6000
local UNITS = "t: 0.1 s server time; pos: 0.1 studs; dir: 0.001. p = {t, name, userId (0 = bot), team, x, y, z, "
	.. "alive}; s = {t, name, ox, oy, oz, dx, dy, dz, hit, zone}"

local Report = {}

local okStore, store = pcall(function()
	return DataStoreService:GetDataStore("MilitaryDuels_Reports")
end)
local current: { [string]: Log } = {}
local last: { [string]: Log } = {}
local lastArena: { [Player]: string } = setmetatable({}, { __mode = "k" }) :: any

local function now(): number
	return math.round(workspace:GetServerTimeNow() * 10)
end

local function ints(v: Vector3, scale: number): (number, number, number)
	return math.round(v.X * scale), math.round(v.Y * scale), math.round(v.Z * scale)
end

local function push(arenaId: string, row: { any })
	local log = current[arenaId]
	if log and #log.rows < MAX_ROWS then
		table.insert(log.rows, row)
	end
end

-- Called by the arena when a round starts and when it ends.
function Report.roundStart(arenaId: string, match: string, round: number)
	current[arenaId] = { match = match, round = round, rows = {} }
end

function Report.roundEnd(arenaId: string)
	if current[arenaId] then
		last[arenaId], current[arenaId] = current[arenaId], nil
	end
end

function Report.shot(c: Combatants.Combatant, origin: Vector3, dir: Vector3, hitName: string?, zone: string?)
	local ox, oy, oz = ints(origin, 10)
	local dx, dy, dz = ints(dir, 1000)
	push(c.arena.id, { "s", now(), c.name, ox, oy, oz, dx, dy, dz, hitName or "", zone or "" })
end

local function record()
	while true do
		task.wait(SAMPLE_SECONDS)
		local t = now()
		for _, c in Combatants.all() do
			local id = c.arena.id
			if current[id] then
				local x, y, z = ints(c.root.Position, 10)
				push(id, { "p", t, c.name, if c.player then c.player.UserId else 0, c.team, x, y, z, c.alive })
				if c.player then
					lastArena[c.player] = id
				end
			end
		end
	end
end

local function submit(player: Player, target: number?): boolean
	local arenaId = lastArena[player]
	local log = if arenaId then last[arenaId] or current[arenaId] else nil
	if not arenaId or not log then
		return false
	end
	local seen = false -- only someone who was actually in the logged round can be the target
	for _, row in log.rows do
		seen = seen or (row[1] == "p" and row[4] == target)
	end
	local time = os.time()
	local payload = {
		reporter = player.UserId,
		target = if seen then target else nil,
		time = time,
		map = arenaId,
		match = log.match,
		round = log.round,
		units = UNITS,
		rows = log.rows,
	}
	local key = `report_{time}_{player.UserId}`
	local saved = okStore and pcall((store :: DataStore).SetAsync, store :: DataStore, key, payload)
	if not saved and RunService:IsStudio() then
		local size = #HttpService:JSONEncode(payload)
		warn(`[Report] {key}: {size} bytes, {#log.rows} rows (no DataStore access in Studio)`)
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
