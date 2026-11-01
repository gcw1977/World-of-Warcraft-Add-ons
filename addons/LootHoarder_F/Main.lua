-- Event lifecycle and slash commands. Forever-only, no BI Core dependency.
local addon = LootHoarderForever
local listenerFrame = CreateFrame("Frame")
local eventNames = {
    "LOOT_READY", "LOOT_OPENED", "LOOT_CLOSED",
    "CHAT_MSG_LOOT", "BAG_UPDATE_DELAYED", "UNIT_SPELLCAST_SUCCEEDED"
}
local captureStarted = false
local function RegisterOptionalEvent(eventName)
    local succeeded = pcall(listenerFrame.RegisterEvent, listenerFrame, eventName)
    if not succeeded then addon.RecordDiagnostic("unsupported_event_" .. eventName) end
end
local function StartLootCapture()
    if captureStarted then return end
    if not addon.InitializePersistence() then
        addon.Print("Saved data or character identity unavailable; capture is disabled.")
        return
    end
    captureStarted = true
    for _, eventName in ipairs(eventNames) do RegisterOptionalEvent(eventName) end
end
local function PrintDiagnostics()
    addon.Print("Version " .. addon.version .. "; character " .. tostring(addon.characterKey or "unknown"))
    addon.Print("Windows " .. addon.runtime.windowsSeen .. "; confirmed receipts "
        .. addon.runtime.confirmedReceipts .. "; excluded windows " .. addon.runtime.excludedWindows
        .. "; ambiguous receipts " .. addon.runtime.ambiguousReceipts)
    for diagnosticKey, occurrenceCount in pairs(addon.diagnosticCounts) do
        addon.Print(diagnosticKey .. ": " .. occurrenceCount)
    end
    addon.Print("Forever gameplay validation: NOT_TESTED; world containers unverified.")
end
local function HandleSlashCommand(commandText)
    local requestedCommand, argumentText = string.match(commandText or "", "^(%S*)%s*(.-)%s*$")
    requestedCommand = string.lower(requestedCommand or "")
    if requestedCommand == "mode" then
        if addon.SetHumorMode(argumentText) then
            addon.Print("Commentary mode: " .. addon.characterRecord.humorMode)
            addon.RefreshWindow()
        else
            addon.Print("Modes: Deadpan, Sassy, Goblin, Epic, Unhinged, Silent.")
        end
    elseif requestedCommand == "diagnostics" or requestedCommand == "diag" then
        PrintDiagnostics()
    elseif requestedCommand == "help" then
        addon.Print("/lh — lifetime totals; /lh mode <name>; /lh diagnostics")
    else
        addon.ToggleStatisticsWindow()
    end
end
SLASH_LOOTHOARDERFOREVER1 = "/lh"
SLASH_LOOTHOARDERFOREVER2 = "/loothoarder"
SlashCmdList["LOOTHOARDERFOREVER"] = HandleSlashCommand
listenerFrame:SetScript("OnEvent", function(self, eventName, ...)
    if eventName == "PLAYER_LOGIN" then
        StartLootCapture()
        return
    end
    if not captureStarted then return end
    local succeeded = pcall(addon.HandleLootEvent, eventName, ...)
    if not succeeded then addon.RecordDiagnostic("event_handler_error_" .. eventName) end
end)
RegisterOptionalEvent("PLAYER_LOGIN")
if type(IsLoggedIn) == "function" and IsLoggedIn() then StartLootCapture() end
