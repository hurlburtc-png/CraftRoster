local ADDON_NAME, CraftRoster = ...
local Reporter = {}
CraftRoster.ErrorReporter = Reporter

local MAX_ERRORS, MAX_MESSAGE, MAX_STACK = 10, 2048, 6000
local errors = {}
local handling = false
local lastNotice = -math.huge

local function Now()
	return type(time) == "function" and time() or 0
end

local function Text(value, limit)
	local ok, text = pcall(tostring, value)
	if not ok then text = "Unprintable Lua error" end
	return text:sub(1, limit)
end

function Reporter:Restore()
	local saved = CraftRosterDB and CraftRosterDB.errorReports
	if type(saved) == "table" and saved ~= errors then
		local current = errors
		errors = {}
		for i = 1, math.min(MAX_ERRORS, #saved) do
			local entry = saved[i]
			if type(entry) == "table" and type(entry.message) == "string" then
				table.insert(errors, {message=Text(entry.message, MAX_MESSAGE), stack=Text(entry.stack or "", MAX_STACK),
					count=type(entry.count)=="number" and entry.count==entry.count and math.floor(math.max(1, math.min(entry.count, 1000000))) or 1,
					firstSeen=type(entry.firstSeen)=="number" and entry.firstSeen or Now(),
					lastSeen=type(entry.lastSeen)=="number" and entry.lastSeen or Now()})
			end
		end
		for i = #current, 1, -1 do
			local entry = current[i]
			for index, savedEntry in ipairs(errors) do
				if savedEntry.message == entry.message then
					entry.count = math.min(1000000, entry.count + savedEntry.count)
					entry.firstSeen = math.min(entry.firstSeen, savedEntry.firstSeen)
					table.remove(errors, index); break
				end
			end
			table.insert(errors, 1, entry)
		end
		while #errors > MAX_ERRORS do table.remove(errors) end
	end
	if CraftRosterDB then CraftRosterDB.errorReports = errors end
end

function Reporter:Capture(err, trace)
	local message = Text(err, MAX_MESSAGE)
	local duplicate
	for i, entry in ipairs(errors) do if entry.message == message then duplicate = i; break end end
	if trace == nil and duplicate then trace = errors[duplicate].stack end
	if trace == nil and type(debugstack) == "function" then
		local ok, value = pcall(debugstack, 3, 16, 0)
		if ok then trace = value end
	end
	trace = Text(trace or "", MAX_STACK)
	-- Our wrapper's own filename cannot attribute an unrelated addon error to us.
	local relevant = message:find("CraftRoster", 1, true) ~= nil
	for line in trace:gmatch("[^\n]+") do
		if not line:find("ErrorReporter.lua", 1, true) and line:find("CraftRoster", 1, true) then relevant = true end
	end
	if not relevant then return false end
	local existing
	for i, entry in ipairs(errors) do
		if entry.message == message then existing = table.remove(errors, i); break end
	end
	local entry = existing or {message=message, stack=trace, firstSeen=Now(), count=0}
	entry.count = math.min(1000000, entry.count + 1); entry.lastSeen = Now()
	if trace ~= "" then entry.stack = trace end
	table.insert(errors, 1, entry)
	if #errors > MAX_ERRORS then table.remove(errors) end
	if CraftRosterDB then CraftRosterDB.errorReports = errors end
	if Now() - lastNotice >= 10 then
		lastNotice = Now()
		print("|cffff0000CraftRoster|r Lua error captured. Use /cr bug or the beetle in /cr settings to copy a report.")
	end
	return true
end

function Reporter:GetReport()
	local version = "unknown"
	local metadata = C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata
	if type(metadata) == "function" then
		local ok, value = pcall(metadata, ADDON_NAME, "Version")
		if ok and value then version = Text(value, 80) end
	end
	local build, interface = "unknown", "unknown"
	if type(GetBuildInfo) == "function" then
		local ok, value, buildID, _, api = pcall(GetBuildInfo)
		if ok then build, interface = Text(value, 80) .. " (build " .. Text(buildID, 80) .. ")", Text(api, 80) end
	end
	local lines = {"CraftRoster bug report", "Addon version: " .. version,
		"Client: " .. build .. " / interface " .. interface,
		"Project ID: " .. tostring(WOW_PROJECT_ID or "unknown"),
		"Captured errors: " .. #errors,
		"What were you doing? (add steps, expected result and actual result before sending)", ""}
	if #errors == 0 then table.insert(lines, "No CraftRoster Lua errors captured. This report can still accompany a behavior bug.") end
	for i, entry in ipairs(errors) do
		table.insert(lines, ("Error %d · occurrences: %d · first: %s · last: %s"):format(i, entry.count, tostring(entry.firstSeen), tostring(entry.lastSeen)))
		table.insert(lines, entry.message)
		table.insert(lines, entry.stack ~= "" and entry.stack or "Stack trace unavailable on this client.")
		table.insert(lines, "")
	end
	return table.concat(lines, "\n")
end

-- Preserve the game's/other addon's handler. A capture failure must not hide the original error.
if type(geterrorhandler) == "function" and type(seterrorhandler) == "function" then
	local original = geterrorhandler()
	if type(original) == "function" then
		seterrorhandler(function(err, ...)
			if not handling then
				handling = true
				pcall(Reporter.Capture, Reporter, err)
				handling = false
			end
			return original(err, ...)
		end)
	end
end
