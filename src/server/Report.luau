--!strict
-- Report button recorder. Each arena records its current round (positions 5 times a second and every
-- trigger pull); when a round ends it becomes that arena's "last round". A report saves the reporter's
-- last completed round (or the one in progress if none has finished yet), tagged by match and round.
-- Like the HUD's button, a report is accepted only during a match and for a minute after it.
local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Combatants = require(script.Parent.Combatants)
local Net = require(script.Parent.Net)

type Log = { map: string, match: string, round: number, rows: { { any } }, done: boolean }

local SAMPLE_SECONDS = 0.2
-- A 2:00 round plus its ride is ~130 s; 4 fighters at 5 Hz plus shots stays far under this cap, and
-- at about 120 bytes a row far under DataStore's 4 MB value limit.
local MAX_ROWS = 6000
local REPORT_WINDOW = 62 -- seconds after leaving a match: the HUD's minute plus replication slack
local UNITS = "t: 0.1 s server time; pos: 0.1 studs; dir: 0.001. p = {t, name, userId (0 = bot), team, x, y, z, "
	.. "alive}; s = {t, name, ox, oy, oz, dx, dy, dz, hit, zone}"

local Report = {
	-- Studio without DataStore access: the newest 10 reports, so a tester can inspect them.
	saved = {} :: { { key: string, payload: { [string]: any } } },
}

local okStore, store = pcall(function()
	return DataStoreService:GetDataStore("MilitaryDuels_Reports")
end)
local current: { [string]: Log } = {}
-- The newest round each player appeared in, and the one before it: a report always carries a round
-- the reporter actually played, never a later match on the same map.
local newest: { [Player]: Log } = setmetatable({}, { __mode = "k" }) :: any
local previous: { [Player]: Log } = setmetatable({}, { __mode = "k" }) :: any
local lastInMatch: { [Player]: number } = setmetatable({}, { __mode = "k" }) :: any -- os.clock()

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
	current[arenaId] = { map = arenaId, match = match, round = round, rows = {}, done = false }
end

function Report.roundEnd(arenaId: string)
	local log = current[arenaId]
	if log then
		log.done = true
		current[arenaId] = nil
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
		for _, player in Players:GetPlayers() do
			local arena = player:GetAttribute("Arena")
			if arena ~= nil and arena ~= "Practice" then
				lastInMatch[player] = os.clock()
			end
		end
		for _, c in Combatants.all() do
			local id = c.arena.id
			if current[id] then
				local x, y, z = ints(c.root.Position, 10)
				push(id, { "p", t, c.name, if c.player then c.player.UserId else 0, c.team, x, y, z, c.alive })
				local player = c.player
				if player and newest[player] ~= current[id] then
					previous[player], newest[player] = newest[player], current[id]
				end
			end
		end
	end
end

local function submit(player: Player, target: number?): boolean
	-- The last completed round; while one is still in progress, the round before it (or, in the first
	-- round of a match, the one in progress).
	local log = newest[player]
	if log and not log.done and previous[player] and previous[player].match == log.match then
		log = previous[player]
	end
	if not log or os.clock() - (lastInMatch[player] or -math.huge) > REPORT_WINDOW then
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
		map = log.map,
		match = log.match,
		round = log.round,
		units = UNITS,
		rows = table.clone(log.rows), -- a copy: a round still in progress keeps recording
		complete = log.done, -- false: the reporter's first round, still in progress
	}
	local key = `report_{time}_{player.UserId}`
	local ok = okStore and pcall((store :: DataStore).SetAsync, store :: DataStore, key, payload)
	if not ok and RunService:IsStudio() then
		table.insert(Report.saved, 1, { key = key, payload = payload })
		Report.saved[11] = nil
		local size = #HttpService:JSONEncode(payload)
		warn(`[Report] {key}: {size} bytes, {#log.rows} rows, kept in Report.saved (no DataStore access in Studio)`)
		return true
	end
	return ok
end

function Report.bind()
	Net.Report.OnServerEvent:Connect(function(player, target)
		local malformed = typeof(target) ~= "number" or target ~= target // 1 or target < 1 or target > 2 ^ 53
		if not Net.allow(player, "Report", 1 / 60, 1) or (target ~= nil and malformed) then
			return
		end
		local ok = submit(player, target :: number?)
		pcall(Net.Report.FireClient, Net.Report, player, ok)
		local title = if ok then "Report sent. Thank you!" else "Couldn't send the report"
		pcall(Net.Toast.FireClient, Net.Toast, player, title, "")
	end)
	task.spawn(record)
end

return Report
