local addonName, packMate = ...
packMate.Version = "0.1.0-dev.1"
packMate.State = {initialized = false, refreshRequested = true, lastObservation = nil, activePet = nil}
packMate.Diagnostics = {entries = {}, capabilities = {}, eventRegistrations = {}, persistence = "NOT_INITIALIZED"}
packMate.Safe = {}

function packMate.Safe.Value(value, expectedType)
    if type(issecretvalue) == "function" then
        local checked, isSecret = pcall(issecretvalue, value)
        if not checked or isSecret then return false, "RESTRICTED" end
    end
    local checked, actualType = pcall(type, value)
    if not checked then return false, "RESTRICTED" end
    if actualType ~= expectedType then return false, "INVALID_TYPE" end
    return true
end

function packMate.Safe.Integer(value, minimum, maximum)
    local safe, reason = packMate.Safe.Value(value, "number")
    if not safe then return nil, reason end
    local checked, valid = pcall(function()
        return value == value and value ~= math.huge and value ~= -math.huge
            and value == math.floor(value) and value >= minimum
            and (maximum == nil or value <= maximum)
    end)
    if not checked then return nil, "RESTRICTED" end
    if not valid then return nil, "INVALID_RANGE" end
    return value
end

function packMate.Safe.Text(value)
    local safe, reason = packMate.Safe.Value(value, "string")
    if not safe then return nil, reason end
    local checked, valid = pcall(function() return #value > 0 and #value <= 512 end)
    if not checked then return nil, "RESTRICTED" end
    if not valid then return nil, "INVALID_TEXT" end
    return value
end

function packMate.Safe.Call(functionReference, ...)
    if type(functionReference) ~= "function" then return false, "API_ABSENT" end
    local results = {pcall(functionReference, ...)}
    if not results[1] then return false, "API_ERROR" end
    return true, results[2], results[3], results[4]
end

function packMate.RecordDiagnostic(componentName, severity, reasonCode)
    local diagnostics = packMate.Diagnostics
    local entry = tostring(componentName) .. " [" .. tostring(severity) .. "] " .. tostring(reasonCode)
    table.insert(diagnostics.entries, entry)
    if #diagnostics.entries > 20 then table.remove(diagnostics.entries, 1) end
end

function packMate.RunIsolated(componentName, functionReference, ...)
    local success, result = pcall(functionReference, ...)
    if not success then
        packMate.RecordDiagnostic(componentName, "ERROR", "CALL_FAILED")
        return nil, false
    end
    return result, true
end

function packMate.Chat(message, repetitionCount)
    if type(message) ~= "string" then return end
    local chatFrame = DEFAULT_CHAT_FRAME
    if not chatFrame or type(chatFrame.AddMessage) ~= "function" then
        packMate.RecordDiagnostic("CHAT", "WARN", "CHAT_FRAME_UNAVAILABLE")
        return
    end
    local count = packMate.Safe.Integer(repetitionCount or 1, 1, 3) or 1
    for repetition = 1, count do
        local delivered = pcall(chatFrame.AddMessage, chatFrame, "|cff76c9ee[PM-F]|r " .. message)
        if not delivered then
            packMate.RecordDiagnostic("CHAT", "WARN", "DELIVERY_FAILED")
            return
        end
    end
end

function packMate.Now()
    local success, value = packMate.Safe.Call(GetTime)
    if not success then return nil end
    local safe, reason = packMate.Safe.Value(value, "number")
    if not safe then return nil end
    if value ~= value or value < 0 then return nil end
    return value
end
