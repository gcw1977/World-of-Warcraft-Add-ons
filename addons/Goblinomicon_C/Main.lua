-- Goblinomicon Classic - lifecycle, diagnostics and standalone slash launcher.
local addonName, addon = ...
local lifecycleFrame = CreateFrame("Frame")
local initialized = false
local reloadRequested = false

local function Chat(message)
    if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
        DEFAULT_CHAT_FRAME:AddMessage("|cffffd100Goblinomicon:|r " .. message)
    end
end

-- Read-only diagnostics. PASS describes performed local assertions only;
-- there is no in-client certification until the owner runs field tests.
function addon.PrintDiagnostics()
    local characterData = addon.characterData
    local observer = addon.observer
    local versionLabel, buildLabel, interfaceLabel = "UNKNOWN", "UNKNOWN", "UNKNOWN"
    if type(GetBuildInfo) == "function" then
        local success, version, build, _, interface = pcall(GetBuildInfo)
        if success then
            versionLabel = tostring(version or "UNKNOWN")
            buildLabel = tostring(build or "UNKNOWN")
            interfaceLabel = tostring(interface or "UNKNOWN")
        end
    end
    Chat("Classic " .. addon.version .. " | Client " .. versionLabel ..
        " build " .. buildLabel .. " interface " .. interfaceLabel)
    Chat("Observer " .. (observer.eventRegistered and "REGISTERED" or "NOT_REGISTERED") ..
        " | Wallet API " .. (type(GetMoney) == "function" and "AVAILABLE" or "MISSING") ..
        " | Mode " .. (addon.safeMode and "READ_ONLY_SAFE" or "ACTIVE"))
    if characterData then
        local valid, reason = addon.VerifyCharacter(characterData)
        Chat("Ledger " .. #characterData.transactions .. " rows, " ..
            #characterData.epochs .. " epochs, " .. (characterData.gapCount or 0) ..
            " gaps | Integrity " .. (valid and "PASS" or ("FAIL:" .. tostring(reason))))
        Chat("Checkpoint " .. addon.FormatCopper(characterData.lastCommittedBalanceCopper) ..
            " | Pending " .. #observer.pending .. " | Context " .. #observer.evidence ..
            " | Session continued after reload " .. tostring(addon.sessionContinued))
    else
        Chat("Character GUID not resolved; no transaction attribution is permitted")
    end
    Chat("Last error " .. tostring(addon.lastErrorCode or "none recorded") ..
        " | Owner field tests NOT_TESTED")
end

local function HandleSlashCommand(arguments)
    local command = type(arguments) == "string" and
        string.lower(string.match(arguments, "^%s*(%S+)") or "") or ""
    if command == "diag" then
        addon.PrintDiagnostics()
    elseif command == "ledger" then
        local success = pcall(addon.OpenWindow, "LEDGER")
        if not success then addon.NoteError("UI_LAUNCH_FAILED"); Chat("UI unavailable; observer remains active") end
    elseif command == "" or command == "overview" then
        local success = pcall(addon.OpenWindow, "OVERVIEW")
        if not success then addon.NoteError("UI_LAUNCH_FAILED"); Chat("UI unavailable; observer remains active") end
    elseif command == "baseline" then
        Chat("Opening balance can only be confirmed in the Overview with an empty ledger")
    elseif command == "help" then
        Chat("/gob [overview|ledger|diag|help] (also /goblinomicon)")
    else
        Chat("Unknown command. /goblinomicon help")
    end
end

-- Register only events supported by this client. Missing optional evidence
-- never prevents PLAYER_MONEY from being observed.
local function RegisterEventSafely(eventName, required)
    local success = pcall(lifecycleFrame.RegisterEvent, lifecycleFrame, eventName)
    if not success then
        addon.NoteError("EVENT_UNAVAILABLE_" .. eventName)
        if required then Chat("Required event unavailable: " .. eventName) end
    end
    return success
end

local function Initialize()
    if initialized then return end
    initialized = true
    if not addon.InitializeSavedData() then
        Chat("Saved data invalid or newer than this candidate; read-only safe mode")
    end
    addon.observer.eventRegistered = RegisterEventSafely("PLAYER_MONEY", true)
    RegisterEventSafely("PLAYER_ENTERING_WORLD", true)
    RegisterEventSafely("PLAYER_LOGOUT", true)
    RegisterEventSafely("QUEST_TURNED_IN", false)
    if type(hooksecurefunc) == "function" and type(ReloadUI) == "function" then
        local success = pcall(hooksecurefunc, "ReloadUI", function()
            reloadRequested = true
        end)
        if not success then addon.NoteError("RELOAD_HOOK_UNAVAILABLE") end
    else
        addon.NoteError("RELOAD_HOOK_UNAVAILABLE")
    end
    -- A valid pre-world zero is not evidence of an empty wallet.
    -- Wait for PLAYER_ENTERING_WORLD to establish the first baseline.
end

lifecycleFrame:SetScript("OnEvent", function(self, eventName, ...)
    if eventName == "ADDON_LOADED" then
        local loadedAddonName = ...
        if loadedAddonName == addonName then Initialize() end
    elseif not initialized then
        return
    elseif eventName == "PLAYER_ENTERING_WORLD" then
        addon.BeginWalletObservation()
        -- Defer a second observation until world money has populated.
        if type(C_Timer) == "table" and type(C_Timer.After) == "function" then
            C_Timer.After(1.0, function()
                if addon.characterData then addon.ReconcileWorldWallet() end
                if addon.RefreshVisibleUI then addon.RefreshVisibleUI() end
            end)
        end
    elseif eventName == "PLAYER_MONEY" then
        if not addon.characterData then
            -- Avoid creating an initial zero baseline before world entry.
            if type(IsLoggedIn) == "function" and IsLoggedIn() then
                addon.BeginWalletObservation()
            end
        else addon.ObserveMoneyEvent() end
    elseif eventName == "QUEST_TURNED_IN" then
        local questIdentifier, experienceReward, moneyReward = ...
        addon.RecordQuestEvidence(moneyReward)
    elseif eventName == "PLAYER_LOGOUT" then
        addon.ShutdownObserver(reloadRequested)
    end
end)
RegisterEventSafely("ADDON_LOADED", true)

SLASH_GOBLINOMICONCLASSIC1 = "/goblinomicon"
SLASH_GOBLINOMICONCLASSIC2 = "/gob"
SlashCmdList["GOBLINOMICONCLASSIC"] = HandleSlashCommand
