local PUG = PUG
local math = math
local u = PUG.util

local hooks = {}
local timers = {}
local settings = {
	["skipCount"] = 8,
	["skipCountPanic"] = 16,
	["DetectionTolerance"] = 7,
	["DetectionTrigger"] = 13,
	["DetectionPanicTrigger"] = 42,
	["DetectionCooldown"] = 2,
	["CleanupMethod"] = "unfrozen",
	["PanicMethod"] = "reset",
}

settings = u.getSettings( settings )

local runOnce = true
local skips = 0

local sample = {
	data = {},
	index = 0,
	mean = 0,
}

local lag = {
	skips = settings["skipCount"],
	pSkips = settings["skipCountPanic"],
	tolerance = settings["DetectionTolerance"],
	trigger = settings["DetectionTrigger"] / 10,
	panic = settings["DetectionPanicTrigger"] / 10,
	cooldown = settings["DetectionCooldown"],
	timeout = 0,
	threshold = math.huge,
	delta = 0,
	lastTick = 0,
}

local function getMean()
	local count = 0
	local total = 0

	for _, v in next, sample.data do
		total = total + v
		count = count + 1
	end

	sample.mean = ( total / count )
end

local function addSample( delta )
	sample.index = ( sample.index % 120 ) + 1
	sample.data[ sample.index ] = delta

	if ( sample.index % 10 ) == 0 then
		getMean()
	end

	if ( sample.index ) == 120 then
		PUG.lagGatherSamples = false
	end
end

local clean = include("pug/bin/cleanups.lua")

lag.fClean = clean[ settings[ "CleanupMethod" ] ]
lag.fPanic = clean[ settings[ "PanicMethod" ] ]

assert( type( lag.fClean ) == "function", "Invalid CleanupMethod variable" )
assert( type( lag.fPanic ) == "function", "Invalid PanicMethod variable" )

u.addTimer("LagDetection", 2, 0, function()
	PUG.lagDetectionInit = true
	addSample( lag.delta )

	skips = skips - 1
	if skips < 0 then
		skips = 0
	end
end, timers)

u.addHook("Tick", "LagDetection", function()
	if not PUG.lagDetectionInit then
		return
	end

	if runOnce then
		PUG:getLagSamples()
		runOnce = nil
	end

	local sysTime = SysTime()
	lag.delta = ( sysTime - lag.lastTick )
	lag.lastTick = sysTime

	if PUG.lagGatherSamples then
		addSample( lag.delta )
	end

	if sample.mean == 0 then
		return
	end

	local tol = ( sample.mean * 100 ) + lag.tolerance
	lag.threshold = tol / 100

	if ( lag.delta > lag.threshold ) and ( lag.timeout < sysTime ) then
		skips = skips + 1

		if ( lag.delta > lag.trigger ) or ( skips > lag.skips ) then
			ServerLog( "LAG: ", lag.delta, "Th: ", lag.threshold )
			ServerLog( "Average: ", sample.mean, "Skips: ",
			skips, "/", lag.skips )

			lag.fClean()
			lag.timeout = sysTime + lag.cooldown

			PUG:Notify( "pug_lagdetected", 3, 5, nil )

			if ( lag.delta > lag.panic ) or ( skips > lag.pSkips )  then
				lag.fPanic()
				PUG:Notify( "pug_lagpanic", 3, 5, nil )
			end
		end
	end
end, hooks)

function PUG:getLagSamples()
	self.lagGatherSamples = true
end

function PUG:printLagSamples()
	PrintTable( sample )
end

_G.PUG = PUG -- Pass to global.

return {
	hooks = hooks,
	timers = timers,
	settings = settings,
}