-- Goblinomicon Forever 0.1.0-dev.1: shared, addon-local namespace and guarded utilities.
-- This is not a shared framework or a dependency of any other BI addon.
GoblinomiconForever = GoblinomiconForever or {}
local Addon = GoblinomiconForever
Addon.version = "0.1.0-dev.1"
Addon.product = "Goblinomicon_F"
Addon.schemaVersion = 1
Addon.runtime = { ready = false, currentGuid = nil, currentSessionId = nil,
    captureStatus = "NOT_TESTED", lastObservedCopper = nil, lastObservedAt = nil,
    errors = {}, eventStatus = {}, recentEvent = "NONE" }

-- Store bounded diagnostic metadata, never raw error stacks or private event arguments.
function Addon.Note(severity, component, reason)
    local records = Addon.runtime.errors
    records[#records + 1] = { severity = tostring(severity), component = tostring(component),
        reason = tostring(reason), at = Addon.Now() }
    if #records > 64 then table.remove(records, 1) end
end

function Addon.Now()
    if type(GetServerTime) == "function" then
        local ok, value = pcall(GetServerTime)
        if ok and type(value) == "number" and value > 0 and value == math.floor(value) then
            return value
        end
    end
    if type(time) == "function" then
        local ok, value = pcall(time)
        if ok and type(value) == "number" and value > 0 and value == math.floor(value) then
            return value
        end
    end
    return nil
end

-- Never compare or stringify an inaccessible Forever secret; failure is an unknown value.
function Addon.IsAccessible(value)
    if type(issecretvalue) == "function" then
        local ok, secret = pcall(issecretvalue, value)
        if not ok or secret then return false end
    end
    if type(canaccessvalue) == "function" then
        local ok, accessible = pcall(canaccessvalue, value)
        if not ok or accessible == false then return false end
    end
    return true
end

function Addon.ValidCopper(value)
    if not Addon.IsAccessible(value) then return false end
    local ok, valid = pcall(function()
        return type(value) == "number" and value == value and value >= 0
            and value < math.huge and value == math.floor(value)
    end)
    return ok and valid or false
end

function Addon.ValidSignedCopper(value)
    if not Addon.IsAccessible(value) then return false end
    local ok, valid = pcall(function()
        return type(value) == "number" and value == value
            and value > -math.huge and value < math.huge
            and value == math.floor(value) and value ~= 0
    end)
    return ok and valid or false
end

function Addon.FormatCoins(copper)
    if not Addon.ValidCopper(copper) then return "UNKNOWN" end
    local gold = math.floor(copper / 10000)
    local silver = math.floor((copper % 10000) / 100)
    local bronze = copper % 100
    return string.format("%dg %02ds %02dc", gold, silver, bronze)
end

function Addon.SignedCoins(delta)
    if delta == 0 then return Addon.FormatCoins(0) end
    if not Addon.ValidSignedCopper(delta) then return "UNKNOWN" end
    return (delta > 0 and "+" or "-") .. Addon.FormatCoins(math.abs(delta))
end

function Addon.Print(message)
    if DEFAULT_CHAT_FRAME and type(DEFAULT_CHAT_FRAME.AddMessage) == "function" then
        DEFAULT_CHAT_FRAME:AddMessage("|cffc9a25cGoblinomicon|r " .. tostring(message))
    end
end

-- Date is a display/grouping choice only. Stored timestamps remain UTC epoch.
function Addon.DateLabel(timestamp, formatString)
    if type(timestamp) ~= "number" then return "UNKNOWN" end
    local formatter = date or (os and os.date)
    if type(formatter) ~= "function" then return "UNKNOWN" end
    local ok, result = pcall(formatter, formatString, timestamp)
    if ok and type(result) == "string" then return result end
    return "UNKNOWN"
end
