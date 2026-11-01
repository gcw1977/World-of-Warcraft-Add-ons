-- Litterbug Lite 0.1.0 (WoW Classic Era)
-- Only the player's own deliberate second click can discard one verified gray stack.
local addon = CreateFrame("Frame")
local addonName = "Litterbug Lite"
local maximumDiscardValueCopper = 100 -- strict comparison: less than 1 silver
local equippedBagStart = 0
local equippedBagEnd = NUM_BAG_SLOTS or 4
local pendingCandidate = nil
local hud
local itemLabel
local bagSpaceLabel
local valueLabel
local actionButton

local function getNumberOfSlots(bagID)
    if C_Container and C_Container.GetContainerNumSlots then
        return C_Container.GetContainerNumSlots(bagID) or 0
    end
    return GetContainerNumSlots and (GetContainerNumSlots(bagID) or 0) or 0
end

local function getFreeSlots(bagID)
    if C_Container and C_Container.GetContainerNumFreeSlots then
        return C_Container.GetContainerNumFreeSlots(bagID) or 0
    end
    return GetContainerNumFreeSlots and (GetContainerNumFreeSlots(bagID) or 0) or 0
end

local function getItemInBag(bagID, slotID)
    if C_Container and C_Container.GetContainerItemInfo then
        local info = C_Container.GetContainerItemInfo(bagID, slotID)
        if not info then return nil end
        return {itemID = info.itemID, itemLink = info.hyperlink, stackCount = info.stackCount,
            quality = info.quality, isLocked = info.isLocked}
    end
    if GetContainerItemInfo then
        local _, count, locked, quality, _, _, link, _, _, itemID = GetContainerItemInfo(bagID, slotID)
        if not link then return nil end
        return {itemID = itemID, itemLink = link, stackCount = count, quality = quality, isLocked = locked}
    end
end

local function pickupItem(bagID, slotID)
    if C_Container and C_Container.PickupContainerItem then
        C_Container.PickupContainerItem(bagID, slotID)
    elseif PickupContainerItem then
        PickupContainerItem(bagID, slotID)
    end
end

local function getVendorPrice(itemID)
    if not itemID then return nil end
    local itemName, _, itemQuality, _, _, _, _, _, _, _, itemSellPrice = GetItemInfo(itemID)
    return itemName, itemQuality, itemSellPrice
end

local function getBagSpace()
    local freeSlots, totalSlots = 0, 0
    for bagID = equippedBagStart, equippedBagEnd do
        totalSlots = totalSlots + getNumberOfSlots(bagID)
        freeSlots = freeSlots + getFreeSlots(bagID)
    end
    return freeSlots, totalSlots
end

local function findCheapestGrayStack()
    local cheapestCandidate
    for bagID = equippedBagStart, equippedBagEnd do
        for slotID = 1, getNumberOfSlots(bagID) do
            local item = getItemInBag(bagID, slotID)
            if item and item.quality == 0 and item.itemID and not item.isLocked then
                local itemName, cachedQuality, unitVendorValue = getVendorPrice(item.itemID)
                local stackCount = tonumber(item.stackCount) or 1
                if itemName and cachedQuality == 0 and type(unitVendorValue) == "number" then
                    local stackVendorValue = unitVendorValue * stackCount
                    if stackVendorValue < maximumDiscardValueCopper and
                        (not cheapestCandidate or stackVendorValue < cheapestCandidate.stackVendorValue) then
                        cheapestCandidate = {
                            bagID = bagID, slotID = slotID, itemID = item.itemID,
                            itemLink = item.itemLink, itemName = itemName,
                            stackCount = stackCount, unitVendorValue = unitVendorValue,
                            stackVendorValue = stackVendorValue,
                        }
                    end
                end
            end
        end
    end
    return cheapestCandidate
end

local function candidateStillMatches(candidate)
    local item = getItemInBag(candidate.bagID, candidate.slotID)
    if not item or item.isLocked or item.quality ~= 0 or item.itemID ~= candidate.itemID or
        (tonumber(item.stackCount) or 1) ~= candidate.stackCount or
        item.itemLink ~= candidate.itemLink then
        return false
    end
    local _, quality, unitVendorValue = getVendorPrice(item.itemID)
    return quality == 0 and unitVendorValue == candidate.unitVendorValue and
        unitVendorValue * candidate.stackCount < maximumDiscardValueCopper
end

local function refreshBagSpace()
    if not bagSpaceLabel then return end
    local freeSlots, totalSlots = getBagSpace()
    bagSpaceLabel:SetText(string.format("Empty slots: %d/%d", freeSlots, totalSlots))
end

local function setStatus(status)
    if itemLabel then itemLabel:SetText(status) end
end

local function resetPreview(status)
    pendingCandidate = nil
    if actionButton then actionButton:SetText("Find Trash") end
    if valueLabel then valueLabel:SetText("Gray stacks under 1 silver") end
    setStatus(status or "Ready")
    refreshBagSpace()
end

local function previewCheapestCandidate()
    if CursorHasItem and CursorHasItem() then
        resetPreview("Clear your cursor first")
        return
    end
    pendingCandidate = findCheapestGrayStack()
    if not pendingCandidate then
        resetPreview("Nothing worth littering")
        return
    end
    setStatus(string.format("%s x%d", pendingCandidate.itemName, pendingCandidate.stackCount))
    valueLabel:SetText(string.format("Vendor value lost: %dc", pendingCandidate.stackVendorValue))
    actionButton:SetText("Confirm Discard")
end

local function discardPreviewedCandidate()
    local candidate = pendingCandidate
    if not candidate then return end
    if InCombatLockdown and InCombatLockdown() then
        resetPreview("Try again outside combat")
        return
    end
    if CursorHasItem and CursorHasItem() then
        resetPreview("Clear your cursor first")
        return
    end
    if not candidateStillMatches(candidate) then
        resetPreview("Bag changed; preview again")
        return
    end
    -- A real button click supplies the hardware event required by DeleteCursorItem.
    pickupItem(candidate.bagID, candidate.slotID)
    if not (CursorHasItem and CursorHasItem()) then
        resetPreview("Couldn't pick up item")
        return
    end
    -- Cursor is now holding exactly the prevalidated stack from this bag slot.
    DeleteCursorItem()
    resetPreview("Discard requested: " .. candidate.itemName)
end

local function saveHudGeometry()
    if not hud or not LitterbugLiteDB then return end
    local left, bottom = hud:GetLeft(), hud:GetBottom()
    if left and bottom then
        LitterbugLiteDB.hudLeft = left
        LitterbugLiteDB.hudBottom = bottom
    end
    LitterbugLiteDB.hudWidth = hud:GetWidth()
    LitterbugLiteDB.hudHeight = hud:GetHeight()
end

local function createHud()
    hud = CreateFrame("Frame", "LitterbugLiteHUD", UIParent, "BackdropTemplate")
    hud:SetSize(LitterbugLiteDB.hudWidth or 242, LitterbugLiteDB.hudHeight or 126)
    -- Modern Classic clients use SetResizeBounds instead of the removed resize methods.
    if hud.SetResizeBounds then
        hud:SetResizeBounds(220, 116, 410, 240)
    elseif hud.SetMinResize and hud.SetMaxResize then
        hud:SetMinResize(220, 116)
        hud:SetMaxResize(410, 240)
    end
    hud:SetClampedToScreen(true)
    hud:SetMovable(true)
    hud:SetResizable(true)
    hud:EnableMouse(true)
    hud:SetFrameStrata("MEDIUM")
    hud:SetBackdrop({bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12,
        insets = {left = 3, right = 3, top = 3, bottom = 3}})
    hud:SetBackdropColor(0.04, 0.05, 0.07, 0.78)
    hud:SetBackdropBorderColor(0.48, 0.5, 0.52, 0.8)
    hud:ClearAllPoints()
    if LitterbugLiteDB.hudLeft and LitterbugLiteDB.hudBottom then
        hud:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", LitterbugLiteDB.hudLeft, LitterbugLiteDB.hudBottom)
    else
        hud:SetPoint("CENTER", UIParent, "CENTER", 0, -120)
    end
    hud:RegisterForDrag("LeftButton")
    hud:SetScript("OnDragStart", function(self) self:StartMoving() end)
    hud:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); saveHudGeometry() end)
    hud:SetScript("OnSizeChanged", function() if LitterbugLiteDB then saveHudGeometry() end end)

    local title = hud:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", 12, -10)
    title:SetText("Litterbug Lite")
    local close = CreateFrame("Button", nil, hud, "UIPanelCloseButton")
    close:SetSize(24, 24)
    close:SetPoint("TOPRIGHT", -1, 0)
    close:SetScript("OnClick", function() LitterbugLiteDB.visible = false; hud:Hide() end)

    bagSpaceLabel = hud:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    bagSpaceLabel:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    bagSpaceLabel:SetJustifyH("LEFT")
    itemLabel = hud:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    itemLabel:SetPoint("TOPLEFT", bagSpaceLabel, "BOTTOMLEFT", 0, -6)
    itemLabel:SetPoint("RIGHT", hud, "RIGHT", -9, 0)
    itemLabel:SetJustifyH("LEFT")
    itemLabel:SetText("Ready")
    valueLabel = hud:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    valueLabel:SetPoint("TOPLEFT", itemLabel, "BOTTOMLEFT", 0, -4)
    valueLabel:SetText("Gray stacks under 1 silver")

    actionButton = CreateFrame("Button", nil, hud, "UIPanelButtonTemplate")
    actionButton:SetSize(150, 23)
    actionButton:SetPoint("BOTTOM", hud, "BOTTOM", 0, 10)
    actionButton:SetText("Find Trash")
    actionButton:SetScript("OnClick", function()
        if pendingCandidate then discardPreviewedCandidate() else previewCheapestCandidate() end
    end)

    local resizeGrip = CreateFrame("Button", nil, hud)
    resizeGrip:SetSize(17, 17)
    resizeGrip:SetPoint("BOTTOMRIGHT", -3, 3)
    resizeGrip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    resizeGrip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    resizeGrip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    resizeGrip:SetScript("OnMouseDown", function() hud:StartSizing("BOTTOMRIGHT") end)
    resizeGrip:SetScript("OnMouseUp", function() hud:StopMovingOrSizing(); saveHudGeometry() end)
    refreshBagSpace()
    if LitterbugLiteDB.visible == false then hud:Hide() end
end

SLASH_LITTERBUGLITE1 = "/lbl"
SLASH_LITTERBUGLITE2 = "/litterbug"
SlashCmdList.LITTERBUGLITE = function(message)
    message = (message or ""):lower():match("^%s*(.-)%s*$")
    if message == "reset" then
        hud:ClearAllPoints()
        hud:SetSize(242, 126)
        hud:SetPoint("CENTER", UIParent, "CENTER", 0, -120)
        saveHudGeometry()
        hud:Show()
        LitterbugLiteDB.visible = true
    elseif message == "show" then
        hud:Show()
        LitterbugLiteDB.visible = true
    elseif message == "hide" then
        hud:Hide()
        LitterbugLiteDB.visible = false
    else
        if hud:IsShown() then hud:Hide() else hud:Show() end
        LitterbugLiteDB.visible = hud:IsShown()
    end
end

addon:RegisterEvent("ADDON_LOADED")
addon:RegisterEvent("BAG_UPDATE_DELAYED")
addon:SetScript("OnEvent", function(_, eventName, loadedAddonName)
    if eventName == "ADDON_LOADED" and loadedAddonName == "LitterbugLite" then
        LitterbugLiteDB = LitterbugLiteDB or {}
        createHud()
    elseif eventName == "BAG_UPDATE_DELAYED" then
        refreshBagSpace()
        if pendingCandidate and not candidateStillMatches(pendingCandidate) then
            resetPreview("Bag changed; preview again")
        end
    end
end)
