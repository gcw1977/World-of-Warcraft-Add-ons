-- LootHoarder 0.2.1 - Classic Era. Ordinary loot only; gathering belongs to GL.
local detector = CreateFrame("Frame")
local currentLoot
local pendingMoneyLoot
local lastObservedCopper = nil
local MONEY_WINDOW_GRACE_SECONDS = 3
-- PLAYER_MONEY is an actual wallet change, rather than a displayed loot offer.
-- We only attribute positive changes during a money-bearing loot window.
local function observeMoneyChange()
    local currentCopper = GetMoney()
    if lastObservedCopper == nil then lastObservedCopper = currentCopper; return end
    local copperGained = currentCopper - lastObservedCopper
    lastObservedCopper = currentCopper
    if copperGained <= 0 then return end
    local window = currentLoot and currentLoot.hasMoney and currentLoot or pendingMoneyLoot
    if not window or not window.hasMoney or GetTime() > (window.moneyExpiration or 0) then return end
    if window.gathered then return end
    local database = LootHoarderDatabase
    if not database then return end
    database.moneyLootedCopper = (database.moneyLootedCopper or 0) + copperGained
    database.moneyLootEvents = (database.moneyLootEvents or 0) + 1
    local sourceGUID = window.candidateGUID
    if sourceGUID then
        local sourceType = sourceGUID:match("^([^%-]+)") or "Unknown"
        local key = sourceType .. ":" .. sourceGUID
        local source = database.sources[key]
        if not source then
            source = {sourceType=sourceType,sourceGUID=sourceGUID,sourceName=window.candidateName,
                zone=window.zone,subzone=window.subzone,observations=0,zeroLootObservations=0,items={}}
            database.sources[key] = source
        end
        source.moneyLootedCopper = (source.moneyLootedCopper or 0) + copperGained
    else
        database.unattributedMoneyCopper = (database.unattributedMoneyCopper or 0) + copperGained
    end
end
local recentGatheringCastAt = -100
local recentGatheringSpell = nil
local MAX_EXCLUSION_RECORDS = 60
local recentSourceGUIDs = {}
local recentSourceOrder = {}
local MAX_RECENT_SOURCES = 600
local function announce(message)
    DEFAULT_CHAT_FRAME:AddMessage("|cffffc46b[LH]|r " .. message)
end
local function currentCharacterKey()
    return (UnitName("player") or "Unknown") .. "@" .. (GetRealmName() or "Unknown")
end
local function sourceKind(sourceGUID)
    return sourceGUID and (sourceGUID:match("^([^%-]+)") or "Unknown") or "Unknown"
end
local function isGatheringSpell(spellName)
    local text = spellName and spellName:lower() or ""
    return text == "skinning" or text == "mining" or text == "herb gathering" or
        text == "herbalism" or text == "fishing" or text == "prospecting" or
        text == "disenchant" or text == "milling" or
        text == "opening - mining" or text == "opening - herb gathering"
end
local function observeCasting(spellName)
    if isGatheringSpell(spellName) then
        recentGatheringCastAt = GetTime()
        recentGatheringSpell = spellName
    end
end
local function findCorpseCandidate()
    for _, unitToken in ipairs({"mouseover", "target"}) do
        if UnitExists(unitToken) and UnitIsDead(unitToken) and not UnitIsPlayer(unitToken) then
            local sourceGUID = UnitGUID(unitToken)
            if sourceKind(sourceGUID) == "Creature" then
                return sourceGUID, UnitName(unitToken)
            end
        end
    end
end
local function lootSourceEntries(slotIndex, fallbackQuantity)
    local returnedValues = {GetLootSourceInfo(slotIndex)}
    local entries = {}
    for valueIndex = 1, #returnedValues, 2 do
        if returnedValues[valueIndex] then
            entries[#entries + 1] = {
                guid = returnedValues[valueIndex],
                quantity = tonumber(returnedValues[valueIndex + 1]) or fallbackQuantity or 1
            }
        end
    end
    return entries
end
local function observeAvailableLoot()
    local candidateGUID, candidateName = findCorpseCandidate()
    local gatheringRecent = GetTime() - recentGatheringCastAt <= 4
    local fishingLoot = type(IsFishingLoot) == "function" and IsFishingLoot() or false
    -- A nearby spellcast alone is weak evidence: don't throw away ordinary loot.
    -- A dead, identifiable creature can be skinned, however, so a matching
    -- Skinning cast is the stronger signal for a gathering window.
    local strongSkinningEvidence = gatheringRecent and recentGatheringSpell
        and recentGatheringSpell:lower() == "skinning" and candidateGUID ~= nil
    local strongProfessionEvidence = gatheringRecent and not candidateGUID
        and recentGatheringSpell and recentGatheringSpell:lower() ~= "fishing"
    local gatheringExcluded = fishingLoot or strongSkinningEvidence or strongProfessionEvidence
    local exclusionReason
    if fishingLoot then exclusionReason = "Fishing loot flag"
    elseif strongSkinningEvidence then exclusionReason = "Recent Skinning cast (inferred)"
    elseif strongProfessionEvidence then exclusionReason = "Recent gathering cast (inferred): " .. recentGatheringSpell end
    currentLoot = {
        openedAt = time(),
        zone = GetRealZoneText() or GetZoneText() or "Unknown",
        subzone = GetSubZoneText() or "",
        candidateGUID = candidateGUID, candidateName = candidateName,
        slots = {}, sourceGUIDs = {}, hasMoney = false,
        gathered = gatheringExcluded,
        exclusionReason = exclusionReason,
        suspectedGathering = gatheringRecent and not gatheringExcluded,
        recentGatheringSpell = gatheringRecent and recentGatheringSpell or nil,
        cleared = {},
        controlledLootStarted = false,
        moneyExpiration = GetTime() + MONEY_WINDOW_GRACE_SECONDS,
    }
    for slotIndex = 1, GetNumLootItems() do
        local slotType = GetLootSlotType(slotIndex)
        if slotType == LOOT_SLOT_ITEM then
            local _, itemName, observedQuantity, _, observedQuality, _, isQuestItem = GetLootSlotInfo(slotIndex)
            local itemLink = GetLootSlotLink(slotIndex)
            local itemID = itemLink and tonumber(itemLink:match("item:(%d+)"))
            local sources = lootSourceEntries(slotIndex, observedQuantity)
            for _, entry in ipairs(sources) do currentLoot.sourceGUIDs[entry.guid] = true end
            currentLoot.slots[slotIndex] = {
                itemID = itemID, name = itemName or "Unknown item", quantity = observedQuantity or 1,
                quality = observedQuality, questItem = isQuestItem, sources = sources,
            }
        elseif slotType == LOOT_SLOT_MONEY then
            currentLoot.hasMoney = true
        end
    end
end
local function alreadyObserved(sourceGUID)
    return recentSourceGUIDs[sourceGUID] ~= nil
end
local function rememberSource(sourceGUID)
    if recentSourceGUIDs[sourceGUID] then return end
    recentSourceGUIDs[sourceGUID] = true
    recentSourceOrder[#recentSourceOrder + 1] = sourceGUID
    if #recentSourceOrder > MAX_RECENT_SOURCES then
        local expiredGUID = table.remove(recentSourceOrder, 1)
        recentSourceGUIDs[expiredGUID] = nil
    end
end
local function getSourceAggregate(sourceGUID, sourceName)
    local database = LootHoarderDatabase
    local sourceType = sourceKind(sourceGUID)
    local sourceID = sourceType .. ":" .. tostring(sourceGUID)
    local aggregate = database.sources[sourceID]
    if not aggregate then
        aggregate = {sourceType = sourceType, sourceGUID = sourceGUID, sourceName = sourceName,
            zone = currentLoot.zone, subzone = currentLoot.subzone, observations = 0,
            zeroLootObservations = 0, items = {}}
        database.sources[sourceID] = aggregate
    elseif sourceName and not aggregate.sourceName then
        aggregate.sourceName = sourceName
    end
    return aggregate
end
local function recordAvailableItems()
    local observation = currentLoot
    local database = LootHoarderDatabase
    local candidates = {}
    for sourceGUID in pairs(observation.sourceGUIDs) do candidates[sourceGUID] = true end
    if not next(candidates) and observation.candidateGUID then
        candidates[observation.candidateGUID] = true
    end
    local newSources = {}
    for sourceGUID in pairs(candidates) do
        if not alreadyObserved(sourceGUID) then
            newSources[sourceGUID] = true
            rememberSource(sourceGUID)
            local aggregate = getSourceAggregate(sourceGUID,
                sourceGUID == observation.candidateGUID and observation.candidateName or nil)
            aggregate.observations = aggregate.observations + 1
            database.uniqueSourcesObserved = database.uniqueSourcesObserved + 1
        else
            database.reopenedSourceWindows = database.reopenedSourceWindows + 1
        end
    end
    local itemCount = 0
    for _, slot in pairs(observation.slots) do
        itemCount = itemCount + 1
        local entries = slot.sources
        if #entries == 0 and observation.candidateGUID then
            entries = {{guid = observation.candidateGUID, quantity = slot.quantity}}
        end
        if #entries == 0 then
            database.unattributedItemSlots = database.unattributedItemSlots + 1
        end
        for _, entry in ipairs(entries) do
            if newSources[entry.guid] then
                local aggregate = getSourceAggregate(entry.guid)
                local itemKey = slot.itemID and tostring(slot.itemID) or slot.name
                local material = aggregate.items[itemKey] or {name = slot.name, observedQuantity = 0, positiveObservations = 0}
                material.observedQuantity = material.observedQuantity + entry.quantity
                material.positiveObservations = material.positiveObservations + 1
                aggregate.items[itemKey] = material
                database.totalAvailableItemEvents = database.totalAvailableItemEvents + 1
            end
        end
    end
    if itemCount == 0 and not observation.hasMoney then
        database.emptyLootWindows = database.emptyLootWindows + 1
        local sourceGUID = observation.candidateGUID
        if sourceGUID and newSources[sourceGUID] then
            getSourceAggregate(sourceGUID, observation.candidateName).zeroLootObservations =
                getSourceAggregate(sourceGUID, observation.candidateName).zeroLootObservations + 1
        elseif not sourceGUID then
            database.unattributedEmptyWindows = database.unattributedEmptyWindows + 1
        end
    end
end
local function recordExclusionDetails(observation)
    local database = LootHoarderDatabase
    database.exclusionRecords = database.exclusionRecords or {}
    local names = {}
    for _, slot in pairs(observation.slots or {}) do
        names[#names + 1] = string.format("%s x%d", slot.name or "Unknown", slot.quantity or 1)
    end
    table.sort(names)
    -- Source GUIDs can be found in the actual loot slots, even if the cursor
    -- moved away from the creature before this window opened.
    local sourceName = observation.candidateName or "Unknown source"
    local record = {
        at = observation.openedAt,
        zone = observation.zone or "Unknown",
        subzone = observation.subzone or "",
        source = sourceName,
        sourceGUID = observation.candidateGUID,
        reason = observation.exclusionReason or "Unspecified gathering signal",
        hasMoney = observation.hasMoney or false,
        items = names,
        itemCount = #names,
        classification = "Excluded",
    }
    table.insert(database.exclusionRecords, 1, record)
    if #database.exclusionRecords > MAX_EXCLUSION_RECORDS then
        table.remove(database.exclusionRecords)
    end
end
local function closeCurrentLoot()
    if not currentLoot then return end
    observeMoneyChange()
    if currentLoot.gathered then
        LootHoarderDatabase.excludedGatheringWindows = LootHoarderDatabase.excludedGatheringWindows + 1
        recordExclusionDetails(currentLoot)
    else
        LootHoarderDatabase.lootWindows = LootHoarderDatabase.lootWindows + 1
        recordAvailableItems()
        for slotIndex in pairs(currentLoot.cleared) do
            if currentLoot.slots[slotIndex] then
                LootHoarderDatabase.clearedItemSlots = LootHoarderDatabase.clearedItemSlots + 1
            end
        end
    end
    if currentLoot.hasMoney and not currentLoot.gathered then
        currentLoot.moneyExpiration = GetTime() + MONEY_WINDOW_GRACE_SECONDS
        pendingMoneyLoot = currentLoot
    end
    currentLoot = nil
end
local function isLowValueGray(slot)
    if slot.questItem then return false end
    local itemReference = slot.itemID or slot.name
    local itemName, _, itemQuality, _, _, _, _, _, _, _, sellPrice = GetItemInfo(itemReference)
    -- Unknown item cache or vendor price: fail open; do not silently skip it.
    if not itemName or sellPrice == nil then return false end
    local quality = slot.quality or itemQuality
    return quality == 0 and sellPrice * slot.quantity < 100
end
local function performControlledLoot()
    if not currentLoot or currentLoot.gathered or currentLoot.controlledLootStarted then return end
    local database = LootHoarderDatabase
    if not database.filterLowValueGray then return end
    if GetCVar("autoLootDefault") == "1" then
        if not database.warnedAutoLootConflict then
            announce("Gray-item filter needs Blizzard Auto Loot disabled (Options > Controls > Auto Loot). Filter is inactive until then.")
            database.warnedAutoLootConflict = true
        end
        return
    end
    currentLoot.controlledLootStarted = true
    for slotIndex = 1, GetNumLootItems() do
        local slotType = GetLootSlotType(slotIndex)
        local slot = currentLoot.slots[slotIndex]
        if slotType == LOOT_SLOT_MONEY then
            LootSlot(slotIndex)
        elseif slotType == LOOT_SLOT_ITEM and slot then
            if isLowValueGray(slot) then
                database.skippedLowValueGraySlots = database.skippedLowValueGraySlots + 1
            else
                LootSlot(slotIndex)
            end
        end
    end
    -- The default loot window remains available for manually collecting skipped items.
end

detector:RegisterEvent("ADDON_LOADED")
detector:RegisterEvent("PLAYER_MONEY")
detector:RegisterEvent("PLAYER_ENTERING_WORLD")
detector:RegisterEvent("LOOT_READY")
detector:RegisterEvent("LOOT_OPENED")
detector:RegisterEvent("LOOT_SLOT_CLEARED")
detector:RegisterEvent("LOOT_CLOSED")
detector:RegisterEvent("UNIT_SPELLCAST_START")
detector:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
detector:SetScript("OnEvent", function(_, eventName, ...)
    if eventName == "ADDON_LOADED" then
        if ... ~= "LootHoarder" then return end
        LootHoarderDatabase = LootHoarderDatabase or {}
        local database = LootHoarderDatabase
        database.sources = database.sources or {}
        database.moneyLootedCopper = database.moneyLootedCopper or 0
        database.moneyLootEvents = database.moneyLootEvents or 0
        database.unattributedMoneyCopper = database.unattributedMoneyCopper or 0
        database.lootWindows = database.lootWindows or 0
        database.emptyLootWindows = database.emptyLootWindows or 0
        database.unattributedEmptyWindows = database.unattributedEmptyWindows or 0
        database.excludedGatheringWindows = database.excludedGatheringWindows or 0
        database.exclusionRecords = database.exclusionRecords or {}
        database.uniqueSourcesObserved = database.uniqueSourcesObserved or 0
        database.reopenedSourceWindows = database.reopenedSourceWindows or 0
        database.totalAvailableItemEvents = database.totalAvailableItemEvents or 0
        database.unattributedItemSlots = database.unattributedItemSlots or 0
        database.clearedItemSlots = database.clearedItemSlots or 0
        database.skippedLowValueGraySlots = database.skippedLowValueGraySlots or 0
        if database.filterLowValueGray == nil then database.filterLowValueGray = false end
    elseif eventName == "PLAYER_ENTERING_WORLD" then
        lastObservedCopper = GetMoney()
    elseif eventName == "PLAYER_MONEY" then
        observeMoneyChange()
    elseif eventName == "UNIT_SPELLCAST_START" then
        local unitToken = ...
        if unitToken == "player" then observeCasting(UnitCastingInfo("player")) end
    elseif eventName == "UNIT_SPELLCAST_SUCCEEDED" then
        local unitToken, _, spellID = ...
        if unitToken == "player" and type(spellID) == "number" then
            observeCasting(GetSpellInfo(spellID))
        end
    elseif eventName == "LOOT_READY" then
        closeCurrentLoot()
        observeAvailableLoot()
    elseif eventName == "LOOT_OPENED" then
        if not currentLoot then observeAvailableLoot() end
        performControlledLoot()
    elseif eventName == "LOOT_SLOT_CLEARED" then
        local clearedSlotIndex = ...
        if currentLoot and type(clearedSlotIndex) == "number" then currentLoot.cleared[clearedSlotIndex] = true end
    elseif eventName == "LOOT_CLOSED" then
        closeCurrentLoot()
    end
end)
SLASH_LOOTHOARDER1 = "/lh"
SLASH_LOOTHOARDER2 = "/loothoarder"
SlashCmdList.LOOTHOARDER = function(input)
    local command = input and input:lower():match("^%s*(.-)%s*$") or ""
    if not LootHoarderDatabase then return end
    local database = LootHoarderDatabase
    if command == "" or command == "status" then
        announce(string.format("%d loot windows, %d empty, %d unique source observations, %d item offers, %d gathered excluded, %d reopened.",
            database.lootWindows, database.emptyLootWindows, database.uniqueSourcesObserved,
            database.totalAvailableItemEvents, database.excludedGatheringWindows, database.reopenedSourceWindows))
        announce(string.format("Coin collected from loot: %d copper (%d wallet updates).", database.moneyLootedCopper, database.moneyLootEvents))
        announce("Gray <1s filter: " .. (database.filterLowValueGray and "ON" or "OFF") .. ". Skipped slots: " .. database.skippedLowValueGraySlots)
    elseif command == "filter on" then
        database.filterLowValueGray = true
        database.warnedAutoLootConflict = nil
        announce("Gray-item filter ON. Disable Blizzard Auto Loot in Options; LH will loot eligible slots automatically.")
    elseif command == "filter off" then
        database.filterLowValueGray = false
        announce("Gray-item filter OFF. Blizzard Auto Loot may be re-enabled.")
    elseif command == "help" then
        announce("/lh status | /lh filter on | /lh filter off")
    else
        announce("Unknown command. Use /lh help")
    end
end
