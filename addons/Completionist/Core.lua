-- Completionist 0.1.0 - Classic Era foundation
-- Data source: installed QuestieDB; no Questie UI or quest routing.
local addon = CreateFrame("Frame")
local rowsByZone = {}
local allQuestRows = {}
local currentZone = 0
local displayFrame
local contentText
local currentMode = "exploration"
local initialized = false
local lastQuestLog = {}
local completedSnapshot = {}
local validModes = {exploration=true, discovery=true, audit=true}
local zoneOverrides = {} -- [questId] = originZoneId (future audited corrections)
local excludedDonationIds = {} -- intentionally empty until authoritative classification
local repeatableOverrides = {} -- intentionally empty until authoritative classification

local function PrintMessage(message)
    DEFAULT_CHAT_FRAME:AddMessage("|cff7ad59aCompletionist|r: " .. message)
end

local function IsQuestComplete(questId)
    if CompletionistDB.completed[questId] then return true end
    if C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted then
        return C_QuestLog.IsQuestFlaggedCompleted(questId) == true
    end
    if IsQuestFlaggedCompleted then return IsQuestFlaggedCompleted(questId) == true end
    return false
end

local function SnapshotQuestLog()
    local active = {}
    local count = GetNumQuestLogEntries and GetNumQuestLogEntries() or 0
    for index = 1, count do
        local title, _, _, isHeader, _, _, _, questId = GetQuestLogTitle(index)
        if not isHeader and type(questId) == "number" and questId > 0 then
            active[questId] = true
            if not CompletionistDB.started[questId] then
                CompletionistDB.started[questId] = time()
            end
        end
    end
    lastQuestLog = active
end

local function GetStatus(quest)
    if IsQuestComplete(quest.id) then return "Completed", nil end
    local raceId = select(3, UnitRace("player"))
    local requiredRaceMask = quest.races
    local raceMasks = LibQuestieDB.Enum and LibQuestieDB.Enum.raceMaskById
    if requiredRaceMask and requiredRaceMask ~= 0 and raceMasks and raceMasks[raceId] then
        local characterMask = raceMasks[raceId]
        if math.floor(requiredRaceMask / characterMask) % 2 == 0 then
            return "Ineligible", "Race restriction"
        end
    end
    local classId = select(3, UnitClass("player"))
    if quest.classes and quest.classes ~= 0 and classId then
        local classMask = 2 ^ (classId - 1)
        if math.floor(quest.classes / classMask) % 2 == 0 then
            return "Ineligible", "Class restriction"
        end
    end
    local playerLevel = UnitLevel("player")
    if quest.level and quest.level > playerLevel then
        return "Locked", "Requires level " .. quest.level
    end
    -- Prerequisites, profession and faction eligibility remain unverified.
    -- Do not label a quest fully eligible when this data has not been evaluated.
    return "Unverified", "Further prerequisites not yet evaluated"
end

local function GetZoneLabel(zoneId)
    if C_Map and C_Map.GetMapInfo then
        local mapInfo = C_Map.GetMapInfo(zoneId)
        if mapInfo and mapInfo.name then return mapInfo.name end
    end
    return "Zone " .. tostring(zoneId)
end

local function GetZoneSummary(zoneId)
    local summary = {completed=0,eligible=0,locked=0,ineligible=0,unverified=0,donations=0,repeatables=0,total=0}
    for _, quest in ipairs(rowsByZone[zoneId] or {}) do
        if excludedDonationIds[quest.id] then
            summary.donations = summary.donations + 1
        else
            summary.total = summary.total + 1
            local status = GetStatus(quest)
            local key = string.lower(status)
            summary[key] = summary[key] + 1
            if repeatableOverrides[quest.id] then summary.repeatables = summary.repeatables + 1 end
        end
    end
    local eligiblePool = summary.completed + summary.eligible
    summary.percent = eligiblePool > 0 and math.floor(summary.completed * 100 / eligiblePool + .5) or nil
    return summary
end

local function RefreshDisplay()
    if not displayFrame or not displayFrame:IsShown() then return end
    local zoneId = currentZone
    local summary = GetZoneSummary(zoneId)
    local lines = {
        "|cffffd56a" .. GetZoneLabel(zoneId) .. "|r  -  " .. string.upper(currentMode),
        string.format("Completed %d  |  Eligible %d  |  Locked %d",summary.completed,summary.eligible,summary.locked),
        string.format("Ineligible %d  |  Unverified %d  |  Total %d",summary.ineligible,summary.unverified,summary.total),
        "Completion: " .. (summary.percent and tostring(summary.percent).."%" or "N/A (eligibility pending)"),
        "|cffaaaaaaUnverified quests are excluded from the percentage.|r",
        " "
    }
    local quests = rowsByZone[zoneId] or {}
    local displayed = 0
    for _, quest in ipairs(quests) do
        local status, reason = GetStatus(quest)
        local show = currentMode == "audit" or status == "Completed" or (currentMode == "discovery" and status == "Unverified")
        if show and displayed < 24 and not excludedDonationIds[quest.id] then
            local extra = reason and (" - " .. reason) or ""
            lines[#lines+1] = string.format("[%s] %s (#%d)%s",status,quest.name,quest.id,extra)
            displayed = displayed + 1
        end
    end
    if #quests == 0 then lines[#lines+1] = "No catalog quests mapped to this zone." end
    if currentMode == "discovery" then
        lines[#lines+1] = "|cffaaaaaaGeneral quest-giver areas: not implemented yet.|r"
    end
    if currentMode == "audit" then
        lines[#lines+1] = "|cffaaaaaaSome statuses and origin subzones require further validation.|r"
    end
    contentText:SetText(table.concat(lines,"\n"))
end

local function BuildCatalog()
    if not QuestDB or not QuestDB.GetAllIds then
        PrintMessage("QuestieDB API unavailable; quest catalog not loaded.")
        return
    end
    local questIds = QuestDB.GetAllIds()
    for _, questId in ipairs(questIds) do
        local zoneId = zoneOverrides[questId] or QuestDB.Get(questId,"zoneOrSort")
        if type(zoneId) == "number" and zoneId > 0 then
            local record = {
                id = questId,
                name = QuestDB.Get(questId,"name") or ("Quest "..questId),
                zone = zoneId,
                level = QuestDB.Get(questId,"requiredLevel") or 0,
                races = QuestDB.Get(questId,"requiredRaces") or 0,
                classes = QuestDB.Get(questId,"requiredClasses") or 0,
            }
            rowsByZone[zoneId] = rowsByZone[zoneId] or {}
            table.insert(rowsByZone[zoneId],record)
            allQuestRows[questId] = record
        end
    end
    initialized = true
    PrintMessage("Loaded " .. tostring(#questIds) .. " quest IDs; zone classifications are provisional.")
end

local function CreateWindow()
    displayFrame = CreateFrame("Frame","CompletionistMainFrame",UIParent,"BasicFrameTemplateWithInset")
    displayFrame:SetSize(600,520)
    displayFrame:SetPoint("CENTER")
    displayFrame:SetMovable(true)
    displayFrame:EnableMouse(true)
    displayFrame:RegisterForDrag("LeftButton")
    displayFrame:SetScript("OnDragStart",displayFrame.StartMoving)
    displayFrame:SetScript("OnDragStop",displayFrame.StopMovingOrSizing)
    displayFrame.TitleText:SetText("Completionist 0.1.0")
    local scroll = CreateFrame("ScrollFrame",nil,displayFrame,"UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT",14,-34)
    scroll:SetPoint("BOTTOMRIGHT",-31,14)
    local inner = CreateFrame("Frame",nil,scroll)
    inner:SetSize(540,1100)
    scroll:SetScrollChild(inner)
    contentText = inner:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    contentText:SetPoint("TOPLEFT",4,-4)
    contentText:SetWidth(524)
    contentText:SetJustifyH("LEFT")
    contentText:SetJustifyV("TOP")
    displayFrame:Hide()
end

local function SetMode(mode)
    if not validModes[mode] then return end
    CompletionistDB.mode = mode
    currentMode = mode
    PrintMessage("Mode: " .. mode)
    RefreshDisplay()
end

SLASH_COMPLETIONIST1 = "/completionist"
SLASH_COMPLETIONIST2 = "/comp"
SlashCmdList.COMPLETIONIST = function(input)
    local command, argument = (input or ""):match("^(%S*)%s*(.-)%s*$")
    command = string.lower(command or "")
    if validModes[command] then SetMode(command)
    elseif command == "zone" and tonumber(argument) then
        currentZone = tonumber(argument)
        RefreshDisplay()
    elseif command == "help" then
        PrintMessage("/comp [exploration|discovery|audit|zone <mapID>] - change view or open window")
    else
        if not initialized then PrintMessage("Catalog has not loaded.") end
        if displayFrame:IsShown() then displayFrame:Hide() else RefreshDisplay(); displayFrame:Show(); RefreshDisplay() end
    end
end

addon:RegisterEvent("ADDON_LOADED")
addon:RegisterEvent("PLAYER_ENTERING_WORLD")
addon:RegisterEvent("QUEST_LOG_UPDATE")
addon:RegisterEvent("QUEST_TURNED_IN")
addon:RegisterEvent("ZONE_CHANGED_NEW_AREA")
addon:SetScript("OnEvent",function(_,event,argument1)
    if event == "ADDON_LOADED" and argument1 == "Completionist" then
        CompletionistDB = CompletionistDB or {}
        CompletionistDB.completed = CompletionistDB.completed or {}
        CompletionistDB.started = CompletionistDB.started or {}
        CompletionistDB.turnIns = CompletionistDB.turnIns or {}
        CompletionistDB.mode = validModes[CompletionistDB.mode] and CompletionistDB.mode or "exploration"
        currentMode = CompletionistDB.mode
        CreateWindow()
    elseif event == "PLAYER_ENTERING_WORLD" then
        if not initialized then BuildCatalog() end
        currentZone = (C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")) or currentZone
        SnapshotQuestLog()
        RefreshDisplay()
    elseif event == "ZONE_CHANGED_NEW_AREA" then
        currentZone = (C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")) or currentZone
        RefreshDisplay()
    elseif event == "QUEST_LOG_UPDATE" then
        SnapshotQuestLog()
        RefreshDisplay()
    elseif event == "QUEST_TURNED_IN" and type(argument1)=="number" then
        CompletionistDB.completed[argument1] = true
        CompletionistDB.turnIns[argument1] = (CompletionistDB.turnIns[argument1] or 0) + 1
        CompletionistDB.finishedAt = CompletionistDB.finishedAt or {}
        CompletionistDB.finishedAt[argument1] = CompletionistDB.finishedAt[argument1] or time()
        RefreshDisplay()
    end
end)
