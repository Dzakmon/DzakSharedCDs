local addonName, ns = ...

local Debug = {}
ns.Debug = Debug


function Debug:isEnabled()
	return DzakSharedCDsDB and DzakSharedCDsDB.debug == true
end


local function safeStr(v)
	if v == nil then return "nil" end
	local t = type(v)
	if t == "number" then
		return tostring(v)
	elseif t == "string" then
		local n = tonumber(v)
		if n then return tostring(n) end
		return v
	elseif t == "boolean" then
		return v and "true" or "false"
	end
	local ok, s = pcall(tostring, v)
	if not ok then return "<unprintable>" end
	local n = tonumber(s)
	if n then return tostring(n) end
	return s
end


function Debug:print(label, ...)
	if not self:isEnabled() then return end
	local parts = {}
	for i = 1, select("#", ...) do
		parts[i] = safeStr(select(i, ...))
	end
	local ok, msg = pcall(table.concat, parts, " ")
	if not ok then msg = "<args contain protected values>" end
	print(string.format("|cff00ffaa[DSCD:%s]|r %s", label or "?", msg))
end


SLASH_DSCDDEBUG1 = "/dscddebug"
SlashCmdList["DSCDDEBUG"] = function(arg)
	DzakSharedCDsDB = DzakSharedCDsDB or {}
	if arg == "on" then
		DzakSharedCDsDB.debug = true
	elseif arg == "off" then
		DzakSharedCDsDB.debug = false
	else
		DzakSharedCDsDB.debug = not DzakSharedCDsDB.debug
	end
	print(string.format("|cff00ffaa[DzakSharedCDs]|r Debug %s", DzakSharedCDsDB.debug and "|cff00ff00ON|r" or "|cffff5555OFF|r"))
end
