-- Passive acquisition evidence: no loot actions, bag mutations, or currency tracking.
local addon = LootHoarderForever
local activeWindow
local nextWindowSequence = 0
local lastProfessionCastTime
local professionSpellIDs = { [8613] = true, [2575] = true, [2366] = true }
local maximumWindowAgeSeconds = 8
local function ReadItemCount(itemIdentifier)
    if type(GetItemCount) ~= "function" then return nil end
    local succeeded, itemCount = pcall(GetItemCount, itemIdentifier, false, false)
    if succeeded and type(itemCount) == "number" then return itemCount end
    addon.RecordDiagnostic("bag_count_unavailable")
    return nil
end
local function IsConfirmedDeadUnitSource(sourceGUID)
    if type(sourceGUID) ~= "string" then return false end
    if type(UnitGUID) ~= "function" or type(UnitIsDead) ~= "function" then
        addon.RecordDiagnostic("unit_source_api_unavailable")
        return false
    end
    for _, unitToken in ipairs({ "target", "mouseover" }) do
        local succeeded, matchesDeadUnit = pcall(function()
            return UnitIsDead(unitToken) and UnitGUID(unitToken) == sourceGUID
        end)
        if succeeded and matchesDeadUnit then return true end
    end
    return false
end
local function ReadSourceEligibility(lootSlotIndex, offeredQuantity)
    if type(GetLootSourceInfo) ~= "function" then
        addon.RecordDiagnostic("loot_source_api_unavailable")
        return false
    end
    local succeeded, sourceGUID, sourceQuantity, secondSourceGUID =
        pcall(GetLootSourceInfo, lootSlotIndex)
    if not succeeded then
        addon.RecordDiagnostic("loot_source_api_error")
        return false
    end
    -- Multi-source slots, unknown GUIDs and world containers are NOT guessed.
    if secondSourceGUID ~= nil or type(sourceQuantity) ~= "number" or sourceQuantity ~= offeredQuantity then
        addon.RecordDiagnostic("ambiguous_source")
        return false
    end
    if IsConfirmedDeadUnitSource(sourceGUID) then return true end
    addon.RecordDiagnostic("unverified_container_or_source")
    return false
end
local function IsRecentProfessionGathering()
    if type(lastProfessionCastTime) ~= "number" then return false end
    local now = addon.GetNow()
    return now > 0 and now - lastProfessionCastTime >= 0
        and now - lastProfessionCastTime <= 8
end
local function GetItemSlotType()
    if type(Enum) == "table" and type(Enum.LootSlotType) == "table"
        and type(Enum.LootSlotType.Item) == "number" then
        return Enum.LootSlotType.Item
    end
    return 1 -- Historical item slot constant; owner must verify Forever.
end
local function ReadLootWindow()
    if type(GetNumLootItems) ~= "function" or type(GetLootSlotType) ~= "function"
        or type(GetLootSlotLink) ~= "function" then
        addon.RecordDiagnostic("loot_window_api_unavailable")
        return nil
    end
    local succeeded, numberOfLootSlots = pcall(GetNumLootItems)
    if not succeeded or type(numberOfLootSlots) ~= "number" then
        addon.RecordDiagnostic("loot_slot_count_unavailable")
        return nil
    end
    nextWindowSequence = nextWindowSequence + 1
    local window = {
        sequence = nextWindowSequence,
        openedAt = addon.GetNow(),
        closedAt = nil,
        excluded = IsRecentProfessionGathering(),
        slots = {},
        bagDeltas = {},
        receiptQuantities = {},
        confirmedItems = {}
    }
    if window.excluded then
        addon.runtime.excludedWindows = addon.runtime.excludedWindows + 1
    end
    for lootSlotIndex = 1, numberOfLootSlots do
        local slotSucceeded, lootSlotType = pcall(GetLootSlotType, lootSlotIndex)
        if slotSucceeded and lootSlotType == GetItemSlotType() then
            local linkSucceeded, itemLink = pcall(GetLootSlotLink, lootSlotIndex)
            local itemIdentifier = linkSucceeded and type(itemLink) == "string"
                and tonumber(string.match(itemLink, "item:(%d+)")) or nil
            if itemIdentifier then
                local offeredQuantity = nil
                if type(GetLootSlotInfo) == "function" then
                    local infoSucceeded, slotIcon, slotName, slotQuantity =
                        pcall(GetLootSlotInfo, lootSlotIndex)
                    if infoSucceeded and type(slotQuantity) == "number" then
                        offeredQuantity = slotQuantity
                    end
                end
                if offeredQuantity and offeredQuantity > 0 then
                    window.slots[lootSlotIndex] = {
                        itemIdentifier = itemIdentifier,
                        itemLink = itemLink,
                        offeredQuantity = offeredQuantity,
                        eligibleSource = not window.excluded and ReadSourceEligibility(lootSlotIndex, offeredQuantity),
                        startingBagCount = ReadItemCount(itemIdentifier)
                    }
                else
                    addon.RecordDiagnostic("loot_quantity_unknown")
                end
            else
                addon.RecordDiagnostic("loot_item_identity_unknown")
            end
        end
    end
    addon.runtime.windowsSeen = addon.runtime.windowsSeen + 1
    return window
end
local function ParseSelfLootReceipt(chatMessage)
    if type(chatMessage) ~= "string" then return nil end
    local lootTemplates = {
        { formatText = LOOT_ITEM_SELF_MULTIPLE, hasQuantity = true },
        { formatText = LOOT_ITEM_SELF, hasQuantity = false }
    }
    for _, templateRecord in ipairs(lootTemplates) do
        if type(templateRecord.formatText) == "string" then
            local luaPattern = templateRecord.formatText
                :gsub("([%^%$%(%)%.%[%]%*%+%-%?])", "%%%1")
                :gsub("%%s", "(.+)")
                :gsub("%%d", "(%%d+)")
            local firstCapture, secondCapture = string.match(chatMessage, "^" .. luaPattern .. "$")
            if firstCapture then
                local itemIdentifier = tonumber(string.match(firstCapture, "item:(%d+)"))
                local acquiredQuantity = templateRecord.hasQuantity and tonumber(secondCapture) or 1
                if itemIdentifier and acquiredQuantity and acquiredQuantity > 0 then
                    return itemIdentifier, acquiredQuantity
                end
            end
        end
    end
    return nil
end
local function TryConfirmAcquisition(window, itemIdentifier)
    if not window or window.excluded or not addon.persistenceAvailable then return end
    local receiptQuantity = window.receiptQuantities[itemIdentifier]
    local bagIncrease = window.bagDeltas[itemIdentifier]
    if not receiptQuantity or not bagIncrease or bagIncrease ~= receiptQuantity then return end
    local matchingSlot
    local matchingSlotCount = 0
    for lootSlotIndex, slotRecord in pairs(window.slots) do
        if slotRecord.itemIdentifier == itemIdentifier and slotRecord.eligibleSource then
            matchingSlot = slotRecord
            matchingSlotCount = matchingSlotCount + 1
        elseif slotRecord.itemIdentifier == itemIdentifier then
            -- Any ineligible slot with same item makes attribution ambiguous.
            matchingSlotCount = matchingSlotCount + 1
        end
    end
    if matchingSlotCount ~= 1 or not matchingSlot
        or window.confirmedItems[itemIdentifier]
        or receiptQuantity > matchingSlot.offeredQuantity then
        addon.runtime.ambiguousReceipts = addon.runtime.ambiguousReceipts + 1
        return
    end
    local itemCategory = addon.ClassifyItem(itemIdentifier, matchingSlot.itemLink)
    if addon.RecordConfirmedAcquisition(itemCategory, receiptQuantity) then
        window.confirmedItems[itemIdentifier] = true
        addon.runtime.confirmedReceipts = addon.runtime.confirmedReceipts + 1
    end
end
function addon.HandleLootEvent(eventName, ...)
    if eventName == "UNIT_SPELLCAST_SUCCEEDED" then
        local unitToken, castIdentifier, spellIdentifier = ...
        if unitToken == "player" and professionSpellIDs[spellIdentifier] then
            lastProfessionCastTime = addon.GetNow()
            if activeWindow and not activeWindow.closedAt then
                activeWindow.excluded = true
            end
        end
        return
    end
    if eventName == "LOOT_READY" or eventName == "LOOT_OPENED" then
        local nativeAutoLoot, isFromItem = ...
        if not activeWindow or activeWindow.closedAt then
            activeWindow = ReadLootWindow()
        end
        if activeWindow and isFromItem == true then activeWindow.excluded = true end
        return
    end
    if eventName == "LOOT_CLOSED" then
        if activeWindow then activeWindow.closedAt = addon.GetNow() end
        return
    end
    if not activeWindow then return end
    local currentTime = addon.GetNow()
    if currentTime <= 0 or currentTime - activeWindow.openedAt > maximumWindowAgeSeconds then
        activeWindow = nil
        addon.RecordDiagnostic("expired_unresolved_window")
        return
    end
    if eventName == "CHAT_MSG_LOOT" then
        local chatMessage = ...
        local itemIdentifier, acquiredQuantity = ParseSelfLootReceipt(chatMessage)
        if itemIdentifier then
            if activeWindow.receiptQuantities[itemIdentifier] then
                -- Two receipts for one item/window are not safely attributable.
                activeWindow.receiptQuantities[itemIdentifier] = nil
                activeWindow.confirmedItems[itemIdentifier] = true
                addon.RecordDiagnostic("duplicate_receipt_ambiguous")
            else
                activeWindow.receiptQuantities[itemIdentifier] = acquiredQuantity
                TryConfirmAcquisition(activeWindow, itemIdentifier)
            end
        end
    elseif eventName == "BAG_UPDATE_DELAYED" then
        for _, slotRecord in pairs(activeWindow.slots) do
            local itemIdentifier = slotRecord.itemIdentifier
            if not activeWindow.confirmedItems[itemIdentifier] and slotRecord.startingBagCount then
                local currentBagCount = ReadItemCount(itemIdentifier)
                if currentBagCount then
                    local bagIncrease = currentBagCount - slotRecord.startingBagCount
                    if bagIncrease > 0 then
                        activeWindow.bagDeltas[itemIdentifier] = bagIncrease
                        TryConfirmAcquisition(activeWindow, itemIdentifier)
                    end
                end
            end
        end
    end
end
