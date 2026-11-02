-- Goblinomicon Forever: guarded bootstrap, passive events, read-only diagnostics.
local Addon = GoblinomiconForever

function Addon.OpenGoblinomiconWindow(optionalPage)
    if not Addon.Persistence.database then return false, "NOT_READY" end
    return Addon.UI.Open(optionalPage)
end

function Addon.DiagnosticSnapshot()
    local character = Addon.Persistence.GetCurrentCharacter()
    local valid, integrityReason = Addon.Ledger.Verify(character)
    return { addon = Addon.product, version = Addon.version,
        capture = Addon.runtime.captureStatus, character = character and "GUID_RESOLVED" or "UNAVAILABLE",
        movements = character and #character.movements or 0,
        integrity = valid and integrityReason or (integrityReason or "NOT_READY"),
        fieldStatus = "NOT_TESTED" }
end

local function PrintDiagnostics(detailed)
    local snapshot = Addon.DiagnosticSnapshot()
    Addon.Print("v" .. snapshot.version .. " / Forever FIELD NOT TESTED / capture=" .. snapshot.capture
        .. " / GUID=" .. snapshot.character .. " / rows=" .. tostring(snapshot.movements)
        .. " / integrity=" .. snapshot.integrity)
    if detailed then
        for eventName, state in pairs(Addon.runtime.eventStatus) do
            Addon.Print("event " .. eventName .. " = " .. state)
        end
        local recent = Addon.runtime.errors
        for index = math.max(1, #recent - 7), #recent do
            local record = recent[index]
            if record then Addon.Print(record.severity .. " " .. record.component .. " " .. record.reason) end
        end
    end
end

local function SlashHandler(message)
    local command = type(message) == "string" and string.lower(message) or ""
    command = command:match("^%s*(.-)%s*$")
    if command == "diag" then PrintDiagnostics(false)
    elseif command == "diag detail" then PrintDiagnostics(true)
    elseif command == "help" then
        Addon.Print("/goblinomicon [overview|ledger|diag|diag detail|help]")
    elseif command == "overview" or command == "ledger" then
        local opened, reason = Addon.OpenGoblinomiconWindow(string.upper(command))
        if not opened then Addon.Print("Window unavailable: " .. tostring(reason)) end
    elseif command == "" then
        local opened, reason = Addon.UI.Toggle()
        if not opened then Addon.Print("Window unavailable: " .. tostring(reason)) end
    else Addon.Print("Unknown command. Try /goblinomicon help") end
end

local function RegisterEvent(frame, eventName)
    local ok = pcall(frame.RegisterEvent, frame, eventName)
    Addon.runtime.eventStatus[eventName] = ok and "REGISTERED_NOT_FIELD_TESTED" or "UNAVAILABLE"
    if not ok then Addon.Note("WARN", "Events", "EVENT_UNAVAILABLE_" .. eventName) end
    return ok
end

local function OnWorldReady(isInitialLogin, isReloadingUi)
    if not Addon.Persistence.database then return end
    local identity, identityError = Addon.Persistence.ResolveIdentity()
    if not identity then
        Addon.runtime.captureStatus = "WAIT_IDENTITY"
        Addon.Note("WARN", "Identity", identityError)
        return
    end
    local character, characterError = Addon.Persistence.EnsureCharacter(identity)
    if not character then
        Addon.runtime.captureStatus = "WAIT_IDENTITY"
        Addon.Note("FAIL", "Identity", characterError)
        return
    end
    Addon.runtime.currentGuid = identity.guid
    Addon.Persistence.OpenSession(character, identity.guid, isReloadingUi)
    Addon.runtime.ready = true
    Addon.Wallet.Observe(isReloadingUi and "RELOAD_RECONCILIATION" or "LOGIN_RECONCILIATION", true)
end

local function OnEvent(frame, eventName, ...)
    if eventName == "ADDON_LOADED" then
        local loadedAddonName = ...
        if loadedAddonName ~= "Goblinomicon_F" then return end
        local database, reason = Addon.Persistence.Load()
        if not database then
            Addon.Note("FAIL", "Bootstrap", reason)
            return
        end
        Addon.runtime.captureStatus = "WAIT_WORLD"
        if not RegisterEvent(frame, "PLAYER_ENTERING_WORLD") then
            Addon.runtime.captureStatus = "FAIL"
            return
        end
        if not RegisterEvent(frame, "PLAYER_MONEY") then
            Addon.runtime.captureStatus = "FAIL"
            return
        end
        RegisterEvent(frame, "PLAYER_LOGOUT")
        RegisterEvent(frame, "QUEST_TURNED_IN")
        RegisterEvent(frame, "MERCHANT_SHOW")
        RegisterEvent(frame, "MERCHANT_CLOSED")
    elseif eventName == "PLAYER_ENTERING_WORLD" then
        local isInitialLogin, isReloadingUi = ...
        OnWorldReady(isInitialLogin, isReloadingUi)
    elseif eventName == "PLAYER_MONEY" then
        if Addon.runtime.captureStatus == "WAIT_IDENTITY" then
            OnWorldReady(false, false)
        else
            Addon.Wallet.Observe("PLAYER_MONEY", false)
        end
    elseif eventName == "PLAYER_LOGOUT" then
        Addon.Persistence.MarkLogout()
    elseif eventName == "QUEST_TURNED_IN" then
        local questIdentifier, experienceReward, moneyReward = ...
        Addon.Attribution.RecordQuest(questIdentifier, moneyReward)
    elseif eventName == "MERCHANT_SHOW" then
        Addon.Attribution.MerchantVisible(true)
    elseif eventName == "MERCHANT_CLOSED" then
        Addon.Attribution.MerchantVisible(false)
    end
end

if type(CreateFrame) == "function" then
    local eventFrame = CreateFrame("Frame")
    eventFrame:SetScript("OnEvent", function(frame, eventName, ...)
        local ok = pcall(OnEvent, frame, eventName, ...)
        if not ok then
            Addon.Note("FAIL", "Events", "HANDLER_THROWN_" .. eventName)
            if eventName == "PLAYER_MONEY" or eventName == "PLAYER_ENTERING_WORLD" then
                Addon.runtime.captureStatus = "FAIL"
            end
        end
    end)
    RegisterEvent(eventFrame, "ADDON_LOADED")
    Addon.runtime.eventFrame = eventFrame
else
    Addon.runtime.captureStatus = "FAIL"
    Addon.Note("FAIL", "Bootstrap", "CREATEFRAME_UNAVAILABLE")
end

SLASH_GOBLINOMICONFOREVER1 = "/goblinomicon"
SlashCmdList["GOBLINOMICONFOREVER"] = SlashHandler
