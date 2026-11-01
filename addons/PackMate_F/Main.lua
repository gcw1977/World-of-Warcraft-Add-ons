local addonName, packMate = ...
local eventFrame = CreateFrame("Frame", "PackMateForeverEventFrame")
local elapsedSinceTick = 0
local supportedEvents = {
    "PLAYER_ENTERING_WORLD", "UNIT_PET", "UNIT_LEVEL",
    "UNIT_PET_EXPERIENCE", "PET_BAR_UPDATE", "PET_TALENT_UPDATE"
}

local function observeComponent(componentName, functionReference)
    local result, successful = packMate.RunIsolated(componentName, functionReference)
    if not successful or not result then
        return {availabilityState = "UNAVAILABLE", reasonCode = "COMPONENT_ERROR"}
    end
    packMate.Diagnostics.capabilities[componentName] = result.availabilityState
    return result
end

local function refreshPet()
    local identity = observeComponent("IDENTITY", packMate.Api.ReadIdentity)
    local now = packMate.Now()
    local experience, loyalty, points, happiness
    if identity.availabilityState == "AVAILABLE" then
        experience = observeComponent("EXPERIENCE", packMate.Api.ReadExperience)
        loyalty = observeComponent("LOYALTY", packMate.Api.ReadLoyalty)
        points = observeComponent("POINTS", packMate.Api.ReadPoints)
        happiness = observeComponent("HAPPINESS", packMate.Api.ReadHappiness)
    else
        experience = {availabilityState = "UNAVAILABLE", reasonCode = "NO_ELIGIBLE_PET"}
        loyalty = experience
        points = experience
        happiness = experience
    end
    local delta, ledgerOkay = packMate.RunIsolated("LEDGER", packMate.Ledger.Observe, identity, experience)
    if not ledgerOkay then packMate.Ledger.ResetBaseline() end
    packMate.RunIsolated("HAPPINESS", packMate.Happiness.Evaluate, identity, happiness, now)
    if delta and delta.observedGain and packMate.Storage.Settings().happinessAnnouncementMode ~= "mute"
        and packMate.Storage.Settings().shouldAnnouncePetExperience then
        packMate.Chat(identity.petName .. " observed +" .. tostring(delta.observedGain)
            .. " pet XP (" .. tostring(experience.current) .. "/" .. tostring(experience.required) .. ")")
    end
    if delta and delta.levelIncreased and packMate.Storage.Settings().happinessAnnouncementMode ~= "mute" then
        packMate.Chat(identity.petName .. " reached level " .. tostring(identity.petLevel) .. "!")
    end
    local observedTotal
    if identity.availabilityState == "AVAILABLE" then
        observedTotal = packMate.Storage.GetPetTotal(identity.petGuid)
    end
    local model = {
        petName = identity.availabilityState == "AVAILABLE" and identity.petName or nil,
        petLevel = identity.petLevel,
        experience = experience, loyalty = loyalty, points = points,
        happiness = happiness, observedTotal = observedTotal
    }
    packMate.State.lastObservation = model
    local _, hudOkay = packMate.RunIsolated("HUD", packMate.Hud.Render, model)
    if not hudOkay then packMate.Hud.Hide() end
end

local function registerOptionalEvent(eventName)
    local successful = pcall(eventFrame.RegisterEvent, eventFrame, eventName)
    packMate.Diagnostics.eventRegistrations[eventName] = successful and "REGISTERED" or "UNSUPPORTED"
    if not successful then packMate.RecordDiagnostic("EVENTS", "WARN", eventName .. "_UNSUPPORTED") end
end

local function registerSlashAliases()
    if type(SlashCmdList) ~= "table" then
        packMate.RecordDiagnostic("COMMANDS", "ERROR", "SLASH_LIST_MISSING")
        return
    end
    SlashCmdList.PACKMATEFOREVER = function(command)
        local normalized = string.lower((command or ""):match("^%s*(.-)%s*$"))
        local settings = packMate.Storage.Settings()
        if normalized == "show" then
            packMate.Storage.SetSetting("desiredHudVisibility", true)
            refreshPet()
        elseif normalized == "hide" then
            packMate.Storage.SetSetting("desiredHudVisibility", false)
            packMate.Hud.Hide()
        elseif normalized == "reset" then
            packMate.Storage.ResetGeometry()
            packMate.RunIsolated("HUD", packMate.Hud.ApplyGeometry)
            refreshPet()
            packMate.Chat("HUD geometry and visibility reset; statistics preserved.")
        elseif normalized == "sassy" or normalized == "stoic" or normalized == "mute" then
            packMate.Storage.SetSetting("happinessAnnouncementMode", normalized)
            packMate.Happiness.Reanchor(packMate.Now())
            packMate.Chat("Happiness announcements: " .. normalized .. ".")
        elseif normalized == "xp on" or normalized == "xp off" then
            packMate.Storage.SetSetting("shouldAnnouncePetExperience", normalized == "xp on")
            packMate.Chat("Observed XP announcements " .. (normalized == "xp on" and "enabled." or "disabled."))
        elseif normalized == "status" then
            refreshPet()
            local observation = packMate.State.lastObservation
            if not observation or not observation.petName then
                packMate.Chat("No eligible Hunter pet. Pet data unavailable.")
            else
                packMate.Chat(observation.petName .. " level " .. tostring(observation.petLevel)
                    .. "; observed XP total: " .. (observation.observedTotal ~= nil
                        and tostring(observation.observedTotal) or "unavailable"))
                if observation.experience.availabilityState == "AVAILABLE" then
                    packMate.Chat("Current XP: " .. tostring(observation.experience.current)
                        .. "/" .. tostring(observation.experience.required))
                else
                    packMate.Chat("Current XP unavailable: " .. observation.experience.reasonCode)
                end
                packMate.Chat("Loyalty: " .. (observation.loyalty.description or "unavailable")
                    .. "; points: " .. (observation.points.availablePoints ~= nil
                        and tostring(observation.points.availablePoints) .. " training" or "unavailable"))
            end
        elseif normalized == "diag" then
            packMate.Chat("Build: " .. packMate.Version .. "; client: " .. packMate.Api.ReadBuild())
            packMate.Chat("Persistence: " .. packMate.Storage.PersistenceStatus())
            for _, featureName in ipairs({"IDENTITY", "EXPERIENCE", "LOYALTY", "POINTS", "HAPPINESS"}) do
                packMate.Chat(featureName .. ": " .. tostring(packMate.Diagnostics.capabilities[featureName] or "NOT_OBSERVED"))
            end
            for _, eventName in ipairs(supportedEvents) do
                packMate.Chat("Event " .. eventName .. ": " .. tostring(packMate.Diagnostics.eventRegistrations[eventName] or "NOT_REGISTERED"))
            end
            local entries = packMate.Diagnostics.entries
            for index = math.max(1, #entries - 3), #entries do packMate.Chat(entries[index]) end
        elseif normalized == "" or normalized == "help" then
            packMate.Chat("Mode: " .. settings.happinessAnnouncementMode
                .. "; /pm show | hide | reset | status | diag | sassy | stoic | mute | xp on | xp off")
        else
            packMate.Chat("Unknown command. Use /pm help.")
        end
    end
    local aliases = {"/pm", "/packmate", "/petledger"}
    local aliasIndex = 0
    for _, alias in ipairs(aliases) do
        local collision = false
        for globalName, globalValue in pairs(_G) do
            if type(globalName) == "string" and string.match(globalName, "^SLASH_")
                and globalValue == alias then
                collision = true
                break
            end
        end
        if collision then
            packMate.RecordDiagnostic("COMMANDS", "WARN", "ALIAS_CONFLICT_" .. alias)
        else
            aliasIndex = aliasIndex + 1
            _G["SLASH_PACKMATEFOREVER" .. aliasIndex] = alias
        end
    end
end

local function initialize(addonLoadedName)
    if addonLoadedName ~= addonName or packMate.State.initialized then return end
    packMate.Storage.Initialize()
    packMate.RunIsolated("HUD", packMate.Hud.Initialize)
    registerSlashAliases()
    for _, eventName in ipairs(supportedEvents) do registerOptionalEvent(eventName) end
    packMate.State.initialized = true
    packMate.State.refreshRequested = true
end

eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:SetScript("OnEvent", function(_, eventName, unitToken)
    if eventName == "ADDON_LOADED" then
        initialize(unitToken)
        return
    end
    if not packMate.State.initialized then return end
    if eventName == "UNIT_PET" and unitToken ~= "player" then return end
    if eventName == "UNIT_LEVEL" and unitToken ~= "pet" then return end
    packMate.State.refreshRequested = true
end)
eventFrame:SetScript("OnUpdate", function(_, elapsed)
    if not packMate.State.initialized then return end
    if type(elapsed) ~= "number" or elapsed < 0 then return end
    elapsedSinceTick = elapsedSinceTick + elapsed
    if elapsedSinceTick < 1 then return end
    elapsedSinceTick = 0
    packMate.State.refreshRequested = false
    packMate.RunIsolated("REFRESH", refreshPet)
end)

function OpenPackMateStatusHud()
    if not packMate.State.initialized then return {opened = false, reasonCode = "NOT_INITIALIZED"} end
    packMate.Storage.SetSetting("desiredHudVisibility", true)
    local _, successful = packMate.RunIsolated("REFRESH", refreshPet)
    if not successful then return {opened = false, reasonCode = "REFRESH_FAILED"} end
    local observation = packMate.State.lastObservation
    return {opened = observation and observation.petName ~= nil or false,
        reasonCode = observation and observation.petName and nil or "NO_ELIGIBLE_PET"}
end
