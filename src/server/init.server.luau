local AntiCheat = require(script.AntiCheat)
local Combat = require(script.Combat)
local Map = require(script.Map)
local Match = require(script.Match)

local info = Map.build()
AntiCheat.start(info.boundsMin, info.boundsMax)
Combat.bind()
Match.run(info)
