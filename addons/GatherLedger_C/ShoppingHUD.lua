-- GatherLedger Shopping HUD: presentation of current-character bag contents against goals.
-- Historical gathering records and other characters' snapshots are never consulted.
local shoppingHUD = CreateFrame("Frame", "GatherLedgerShoppingHUD", UIParent)
shoppingHUD:SetFrameStrata("MEDIUM")
shoppingHUD:SetClampedToScreen(true)
shoppingHUD:SetMovable(true)
shoppingHUD:SetResizable(true)
shoppingHUD:EnableMouse(true)
shoppingHUD:SetSize(215, 125)
shoppingHUD:SetPoint("CENTER", UIParent, "CENTER", 0, 140)
shoppingHUD:Hide()

local heading = shoppingHUD:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
heading:SetPoint("TOPLEFT", shoppingHUD, "TOPLEFT", 4, -3)
heading:SetText("Shopping List")

local resizeGrip = CreateFrame("Button", nil, shoppingHUD)
resizeGrip:SetSize(17, 17)
resizeGrip:SetPoint("BOTTOMRIGHT", shoppingHUD, "BOTTOMRIGHT", 0, 0)
resizeGrip:EnableMouse(true)
local resizeIcon = resizeGrip:CreateTexture(nil, "OVERLAY")
resizeIcon:SetAllPoints()
resizeIcon:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
resizeGrip:SetNormalTexture(resizeIcon)
resizeGrip:SetScript("OnMouseDown", function(_, mouseButton)
    if mouseButton == "LeftButton" then shoppingHUD:StartSizing("BOTTOMRIGHT") end
end)

local MAX_DISPLAY_ROWS = 18
local rows = {}
for rowNumber = 1, MAX_DISPLAY_ROWS do
    local row = CreateFrame("Frame", nil, shoppingHUD)
    row:SetHeight(15)
    row:SetPoint("TOPLEFT", shoppingHUD, "TOPLEFT", 4, -18 - (rowNumber - 1) * 15)
    row:SetPoint("RIGHT", shoppingHUD, "RIGHT", -6, 0)
    row.itemName = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.itemName:SetPoint("LEFT", row, "LEFT", 0, 0)
    row.itemName:SetJustifyH("LEFT")
    row.itemName:SetWordWrap(false)
    row.amount = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.amount:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    row.amount:SetJustifyH("RIGHT")
    row:Hide()
    rows[rowNumber] = row
end

local function getCurrentCharacterKey()
    return (GetRealmName() or "UnknownRealm") .. ":" .. (UnitName("player") or "Unknown")
end

local function getShoppingHUDData()
    local shoppingData = GatherLedgerDB and GatherLedgerDB.shopping
    if not shoppingData then return {}, {} end
    local characterData = shoppingData.characters and shoppingData.characters[getCurrentCharacterKey()]
    local bagItems = characterData and characterData.bags and characterData.bags.items or {}
    return shoppingData.goals or {}, bagItems
end

local function getItemDisplayName(itemID, goal)
    local itemName = goal.name or (GatherLedgerCraftingItems and GatherLedgerCraftingItems[itemID])
    if (not itemName or itemName == "") and GetItemInfo then itemName = GetItemInfo(itemID) end
    return itemName or ("Item " .. tostring(itemID))
end

local function refreshShoppingHUD()
    if not shoppingHUD:IsShown() then return end
    local goals, bagItems = getShoppingHUDData()
    local sortedGoals = {}
    for itemID, goal in pairs(goals) do
        local requiredQuantity = tonumber(goal.requiredQuantity) or 0
        if requiredQuantity > 0 then
            local numericItemID = tonumber(itemID)
            sortedGoals[#sortedGoals + 1] = {
                itemName = getItemDisplayName(numericItemID or itemID, goal),
                ownedQuantity = numericItemID and (tonumber(bagItems[numericItemID]) or 0) or 0,
                requiredQuantity = requiredQuantity,
            }
        end
    end
    table.sort(sortedGoals, function(first, second) return first.itemName:lower() < second.itemName:lower() end)
    local visibleRowCount = math.max(0, math.min(MAX_DISPLAY_ROWS, math.floor((shoppingHUD:GetHeight() - 23) / 15)))
    local nameWidth = math.max(35, shoppingHUD:GetWidth() - 86)
    for rowNumber, row in ipairs(rows) do
        local entry = rowNumber <= visibleRowCount and sortedGoals[rowNumber] or nil
        if entry then
            row.itemName:SetWidth(nameWidth)
            row.itemName:SetText(entry.itemName)
            local countText = string.format("%d/%d", entry.ownedQuantity, entry.requiredQuantity)
            row.amount:SetText(countText)
            row.amount:SetTextColor(entry.ownedQuantity >= entry.requiredQuantity and 0.52 or 1,
                                    entry.ownedQuantity >= entry.requiredQuantity and 0.9 or 0.82,
                                    entry.ownedQuantity >= entry.requiredQuantity and 0.55 or 0.47)
            row:Show()
        else
            row:Hide()
        end
    end
    heading:SetText("Shopping List" .. ((#sortedGoals > visibleRowCount) and (" (" .. visibleRowCount .. "/" .. #sortedGoals .. ")") or ""))
end

local function saveShoppingHUDSettings()
    if not GatherLedgerDB then return end
    GatherLedgerDB.shopping = GatherLedgerDB.shopping or {}
    local anchor, _, _, offsetX, offsetY = shoppingHUD:GetPoint(1)
    GatherLedgerDB.shopping.hud = {
        width = shoppingHUD:GetWidth(), height = shoppingHUD:GetHeight(),
        anchor = anchor or "CENTER", offsetX = offsetX or 0, offsetY = offsetY or 0,
        shown = shoppingHUD:IsShown(),
    }
end

shoppingHUD:RegisterForDrag("LeftButton")
shoppingHUD:SetScript("OnDragStart", function(frame) frame:StartMoving() end)
shoppingHUD:SetScript("OnDragStop", function(frame) frame:StopMovingOrSizing(); saveShoppingHUDSettings() end)
resizeGrip:SetScript("OnMouseUp", function(_, mouseButton)
    if mouseButton ~= "LeftButton" then return end
    shoppingHUD:StopMovingOrSizing()
    local width = math.max(150, math.min(480, shoppingHUD:GetWidth()))
    local height = math.max(45, math.min(300, shoppingHUD:GetHeight()))
    shoppingHUD:SetSize(width, height)
    saveShoppingHUDSettings()
    refreshShoppingHUD()
end)
shoppingHUD:SetScript("OnShow", refreshShoppingHUD)

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("BAG_UPDATE_DELAYED")
events:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_ENTERING_WORLD" then
        local saved = GatherLedgerDB and GatherLedgerDB.shopping and GatherLedgerDB.shopping.hud
        if saved then
            shoppingHUD:SetSize(math.max(150, math.min(480, saved.width or 215)),
                                math.max(45, math.min(300, saved.height or 125)))
            shoppingHUD:ClearAllPoints()
            shoppingHUD:SetPoint(saved.anchor or "CENTER", UIParent, saved.anchor or "CENTER", saved.offsetX or 0, saved.offsetY or 0)
            if saved.shown then shoppingHUD:Show() end
        end
    end
    refreshShoppingHUD()
end)

-- Shopping goals may change without a bag event. Poll only while the HUD is visible.
local secondsSinceRefresh = 0
shoppingHUD:SetScript("OnUpdate", function(_, elapsedSeconds)
    secondsSinceRefresh = secondsSinceRefresh + elapsedSeconds
    if secondsSinceRefresh < 0.25 then return end
    secondsSinceRefresh = 0
    refreshShoppingHUD()
end)

-- Open the compact overlay from recipe import without toggling an already open HUD.
GatherLedgerShowShoppingHUD = function()
    if not shoppingHUD:IsShown() then
        shoppingHUD:Show()
    end
    refreshShoppingHUD()
    saveShoppingHUDSettings()
end

SLASH_GATHERLEDGERHUD1 = "/ghud"
SlashCmdList.GATHERLEDGERHUD = function()
    if shoppingHUD:IsShown() then shoppingHUD:Hide() else shoppingHUD:Show() end
    saveShoppingHUDSettings()
end
