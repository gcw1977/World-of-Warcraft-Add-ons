-- GatherLedger Shopping, v0.4.8. Shopping/inventory remain independent of gathering observations.
-- Classic Era. No networking, timers, third-party dependencies, or cross-character communication.
-- SAVED DATA CONTRACT (keep keys stable across upgrades):
-- GatherLedgerDB.shopping.goals[itemID] = {itemID, name, requiredQuantity}
--   Required crafting amounts are independent of gathering observations.
-- GatherLedgerDB.shopping.characters[realmAndName].bags/.bank = {items, observedAt}
-- GatherLedgerDB.shopping.learnedItems[itemID] = itemName
-- Statistics live in GatherLedgerDB.records and are never inferred from item catalog entries.
local inventoryWatcher = CreateFrame("Frame")
local shoppingWindow
-- One permanent scroll child owns all reusable rows; never replace its parent.
local materialRows = {}
local firstVisibleRowOffset = 0
local maxVisibleMaterialRows = 4
-- Bundled offline index is loaded by the TOC before this module.
local bundledCraftingItemNamesByID = GatherLedgerCraftingItems or {}
-- Entries the client identifies during play extend the bundled index in SavedVariables.
local function getLearnedItemNamesByID()
    GatherLedgerDB = GatherLedgerDB or {}
    GatherLedgerDB.shopping = GatherLedgerDB.shopping or {goals = {}, characters = {}}
    GatherLedgerDB.shopping.learnedItems = GatherLedgerDB.shopping.learnedItems or {}
    return GatherLedgerDB.shopping.learnedItems
end
local function rememberItemName(itemID)
    if not itemID or bundledCraftingItemNamesByID[itemID] then return end
    local itemName = GetItemInfo(itemID)
    if itemName and itemName ~= "" then getLearnedItemNamesByID()[itemID] = itemName end
end
local function getCatalogItemName(itemID)
    return bundledCraftingItemNamesByID[itemID] or getLearnedItemNamesByID()[itemID]
end
local function getDisplayNameForItem(itemID)
    return getCatalogItemName(itemID) or GetItemInfo(itemID) or ("Item " .. tostring(itemID))
end
local activeBagNumbers = {0, 1, 2, 3, 4}
local activeBankNumbers = {-1, 5, 6, 7, 8, 9, 10, 11}
local bankIsOpen = false
local updateShoppingDisplay
local refreshShoppingAfterChange
local updateDisplayedMaterialQuantity
local editingItemID = nil
local editingItemName = nil

local function characterIdentifier()
    return (GetRealmName() or "UnknownRealm") .. ":" .. (UnitName("player") or "Unknown")
end

-- Shopping migration touches only shopping goals. It never reads gathering records.
-- Inventory remains snapshots of observed item counts; gathering does not inform ownership.
local function migrateShoppingGoalQuantities()
    GatherLedgerDB = GatherLedgerDB or {}
    GatherLedgerDB.shopping = GatherLedgerDB.shopping or {}
    local goals = GatherLedgerDB.shopping.goals or {}
    for _, goal in pairs(goals) do
        if goal.requiredQuantity == nil and goal.quantity ~= nil then
            goal.requiredQuantity = goal.quantity
        end
        if goal.requiredQuantity ~= nil then goal.quantity = nil end
    end
    GatherLedgerDB.shopping.schemaVersion = 3
end

local function getShoppingSavedData()
    GatherLedgerDB = GatherLedgerDB or {}
    GatherLedgerDB.shopping = GatherLedgerDB.shopping or {goals = {}, characters = {}}
    GatherLedgerDB.shopping.goals = GatherLedgerDB.shopping.goals or {}
    GatherLedgerDB.shopping.characters = GatherLedgerDB.shopping.characters or {}
    migrateShoppingGoalQuantities()
    return GatherLedgerDB.shopping
end

local function getContainerSlotCount(bagNumber)
    if C_Container and C_Container.GetContainerNumSlots then
        return C_Container.GetContainerNumSlots(bagNumber) or 0
    end
    return GetContainerNumSlots and GetContainerNumSlots(bagNumber) or 0
end

local function getContainerItem(bagNumber, slotNumber)
    if C_Container and C_Container.GetContainerItemInfo then
        local info = C_Container.GetContainerItemInfo(bagNumber, slotNumber)
        if info then return info.itemID, info.stackCount or 1 end
        return nil
    end
    local link = GetContainerItemLink and GetContainerItemLink(bagNumber, slotNumber)
    local itemID = link and tonumber(link:match("item:(%d+)"))
    local _, count = GetContainerItemInfo(bagNumber, slotNumber)
    return itemID, count or 1
end

local function countInventoryItemsInContainers(bagNumbers)
    local totals = {}
    for _, bagNumber in ipairs(bagNumbers) do
        for slotNumber = 1, getContainerSlotCount(bagNumber) do
            local itemID, count = getContainerItem(bagNumber, slotNumber)
            if itemID then
                rememberItemName(itemID)
                totals[itemID] = (totals[itemID] or 0) + (tonumber(count) or 1)
            end
        end
    end
    return totals
end

local function saveObservedInventorySnapshot(isBank)
    local shopping = getShoppingSavedData()
    local key = characterIdentifier()
    shopping.characters[key] = shopping.characters[key] or {}
    local currentCharacter = shopping.characters[key]
    local snapshotKey = isBank and "bank" or "bags"
    currentCharacter[snapshotKey] = {items = countInventoryItemsInContainers(isBank and activeBankNumbers or activeBagNumbers), observedAt = time()}
    if updateShoppingDisplay then refreshShoppingAfterChange() end
end

local function getOwnedQuantityAcrossCharacters(itemID)
    local total = 0
    for _, character in pairs(getShoppingSavedData().characters) do
        for _, locationName in ipairs({"bags", "bank"}) do
            local snapshot = character[locationName]
            if snapshot and snapshot.items then total = total + (snapshot.items[itemID] or 0) end
        end
    end
    return total
end

local function makeButton(parent, title, x, y, width, clickHandler)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetSize(width, 23)
    button:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    button:SetText(title)
    button:SetScript("OnClick", clickHandler)
    return button
end

local function makeInput(parent, x, y, width, defaultText, numeric)
    local input = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    input:SetSize(width, 22)
    input:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    input:SetAutoFocus(false)
    input:SetText(defaultText or "")
    if numeric then input:SetNumeric(true) end
    input:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    input:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    return input
end

local function showGatherLedgerTab(isShopping)
    if not shoppingWindow then return end
    shoppingWindow.activeTab = isShopping and "shopping" or "statistics"
    shoppingWindow.shoppingPanel:SetShown(isShopping)
    shoppingWindow.content:GetParent():SetShown(not isShopping)
    shoppingWindow.summary:SetShown(not isShopping)
    shoppingWindow.statisticsHeader:SetShown(not isShopping)
    shoppingWindow.statisticsQuantityHeader:SetShown(not isShopping)
    if isShopping then updateShoppingDisplay()
    elseif GatherLedgerRefreshStatistics then GatherLedgerRefreshStatistics() end
end

local function resolveShoppingItemID(text)
    -- Item links and explicit IDs have priority over names.
    local numberFromLink = text:match("item:(%d+)")
    if numberFromLink then return tonumber(numberFromLink) end
    if text:match("^%d+$") then return tonumber(text) end
    local nameLower = text:lower()
    for itemID, name in pairs(bundledCraftingItemNamesByID) do
        if name:lower() == nameLower then return itemID end
    end
    for itemID, name in pairs(getLearnedItemNamesByID()) do
        if name:lower() == nameLower then return tonumber(itemID) end
    end
    for itemID, goal in pairs(getShoppingSavedData().goals) do
        if type(goal.name) == "string" and goal.name:lower() == nameLower then
            return tonumber(itemID)
        end
    end
    local _, link = GetItemInfo(text)
    return link and tonumber(link:match("item:(%d+)"))
end

local function updateCraftingMaterialSuggestions()
    if not shoppingWindow or not shoppingWindow.suggestionButtons then return end
    local typed = shoppingWindow.itemInput:GetText():lower():match("^%s*(.-)%s*$")
    local matches = {}
    local visited = {}
    local function considerItem(itemID, itemName)
        if visited[itemID] or type(itemName) ~= "string" then return end
        visited[itemID] = true
        local lowerName = itemName:lower()
        local location = lowerName:find(typed, 1, true)
        if location then
            table.insert(matches, {itemID = itemID, name = itemName, prefix = location == 1})
        end
    end
    if #typed >= 2 and not typed:match("^%d+$") and not typed:find("item:", 1, true) then
        for itemID, itemName in pairs(bundledCraftingItemNamesByID) do considerItem(itemID, itemName) end
        for itemID, itemName in pairs(getLearnedItemNamesByID()) do considerItem(tonumber(itemID), itemName) end
        for itemID, goal in pairs(getShoppingSavedData().goals) do
            considerItem(tonumber(itemID), goal.name)
        end
        table.sort(matches, function(first, second)
            if first.prefix ~= second.prefix then return first.prefix end
            if first.name ~= second.name then return first.name < second.name end
            return first.itemID < second.itemID
        end)
    end
    for buttonIndex, button in ipairs(shoppingWindow.suggestionButtons) do
        local match = matches[buttonIndex]
        if match then
            button:SetText(match.name)
            button:SetScript("OnClick", function()
                shoppingWindow.itemInput:SetText(match.name)
                shoppingWindow.itemInput:ClearFocus()
                shoppingWindow.suggestionPanel:Hide()
            end)
            button:Show()
        else
            button:Hide()
        end
    end
    shoppingWindow.suggestionPanel:SetShown(#matches > 0)
end

local function addToShoppingListTarget()
    local itemText = shoppingWindow.itemInput:GetText():match("^%s*(.-)%s*$")
    local requiredQuantity = tonumber(shoppingWindow.quantityInput:GetText())
    local itemID = (editingItemID and itemText == editingItemName) and editingItemID or resolveShoppingItemID(itemText)
    if not itemID or not requiredQuantity or requiredQuantity < 1 or requiredQuantity > 999999 or requiredQuantity ~= math.floor(requiredQuantity) then
        shoppingWindow.message:SetText("Enter a known item (or item ID) and a positive quantity.")
        return
    end
    local shopping = getShoppingSavedData()
    local goal = shopping.goals[itemID] or {itemID = itemID, requiredQuantity = 0, name = itemText}
    goal.requiredQuantity = (goal.requiredQuantity or 0) + requiredQuantity
    rememberItemName(itemID)
    local itemName = getDisplayNameForItem(itemID)
    if itemName then goal.name = itemName end
    shopping.goals[itemID] = goal
    shoppingWindow.message:SetText("Added " .. requiredQuantity .. " to shopping list. Target: " .. goal.requiredQuantity)
    shoppingWindow.itemInput:SetText("")
    shoppingWindow.quantityInput:SetText("1")
    editingItemID = nil
    editingItemName = nil
    shoppingWindow.suggestionPanel:Hide()
    if updateDisplayedMaterialQuantity then updateDisplayedMaterialQuantity(itemID) end
    refreshShoppingAfterChange()
end

-- Unlike the + button, OK replaces a goal rather than increasing it.
local function setShoppingListTargetQuantity()
    local itemText = shoppingWindow.itemInput:GetText():match("^%s*(.-)%s*$")
    local requiredQuantity = tonumber(shoppingWindow.quantityInput:GetText())
    local itemID = (editingItemID and itemText == editingItemName) and editingItemID or resolveShoppingItemID(itemText)
    if not itemID or not requiredQuantity or requiredQuantity < 1 or requiredQuantity > 999999 or requiredQuantity ~= math.floor(requiredQuantity) then
        shoppingWindow.message:SetText("Enter an existing material and a positive whole-number target.")
        return
    end
    local existingGoal = getShoppingSavedData().goals[itemID]
    if not existingGoal then
        shoppingWindow.message:SetText("Material isn't on your list. Use + to add it first.")
        return
    end
    existingGoal.requiredQuantity = requiredQuantity
    shoppingWindow.message:SetText((existingGoal.name or itemText) .. " target updated to " .. requiredQuantity .. ".")
    shoppingWindow.itemInput:SetText("")
    shoppingWindow.quantityInput:SetText("1")
    editingItemID = nil
    editingItemName = nil
    shoppingWindow.suggestionPanel:Hide()
    if updateDisplayedMaterialQuantity then updateDisplayedMaterialQuantity(itemID) end
    refreshShoppingAfterChange()
end

updateShoppingDisplay = function()
    if not shoppingWindow or not shoppingWindow.shoppingPanel then return end
    local panel = shoppingWindow.shoppingPanel
    local goals = {}
    for itemID, goal in pairs(getShoppingSavedData().goals) do
        if (tonumber(goal.requiredQuantity) or 0) > 0 then
            table.insert(goals, {itemID = tonumber(itemID), name = goal.name, requiredQuantity = tonumber(goal.requiredQuantity)})
        end
    end
    table.sort(goals, function(first, second)
        return getDisplayNameForItem(first.itemID) < getDisplayNameForItem(second.itemID)
    end)
    firstVisibleRowOffset = math.min(firstVisibleRowOffset, math.max(0, #goals - maxVisibleMaterialRows))
    panel.summary:SetText(string.format("%d materials on shopping list | Last observed inventory", #goals))
    for rowIndex = 1, maxVisibleMaterialRows do
        local row = materialRows[rowIndex]
        local goal = goals[firstVisibleRowOffset + rowIndex]
        if goal then
            local resolvedName = getDisplayNameForItem(goal.itemID)
            getShoppingSavedData().goals[goal.itemID].name = resolvedName
            local ownedQuantity = getOwnedQuantityAcrossCharacters(goal.itemID)
            local missingQuantity = math.max(0, (goal.requiredQuantity) - ownedQuantity)
            row.label:SetText((missingQuantity == 0 and "|cff76dd91" or "|cffffc857") .. resolvedName .. "|r")
            row.detail:SetText(string.format("Owned %d / Need %d | Missing %d", ownedQuantity, (goal.requiredQuantity), missingQuantity))
            row.itemID = goal.itemID
            local selectedItemID = goal.itemID
            row.editButton:SetScript("OnClick", function()
                local selectedGoal = getShoppingSavedData().goals[selectedItemID]
                if not selectedGoal then return end
                editingItemID = selectedItemID
                editingItemName = getDisplayNameForItem(selectedItemID)
                shoppingWindow.itemInput:SetText(editingItemName)
                shoppingWindow.quantityInput:SetText(tostring(selectedGoal.requiredQuantity))
                shoppingWindow.message:SetText("Editing " .. editingItemName .. ". Set REPLACES the target.")
                shoppingWindow.suggestionPanel:Hide()
                shoppingWindow.quantityInput:SetFocus()
                shoppingWindow.quantityInput:HighlightText()
            end)
            row.removeButton:SetScript("OnClick", function()
                getShoppingSavedData().goals[selectedItemID] = nil
                if editingItemID == selectedItemID then editingItemID = nil; editingItemName = nil end
                refreshShoppingAfterChange()
            end)
            row:Show()
        else row.itemID = nil; row:Hide() end
    end
    if #goals > maxVisibleMaterialRows then
        panel.pageLabel:SetText(string.format("%d-%d of %d", firstVisibleRowOffset + 1, math.min(#goals, firstVisibleRowOffset + maxVisibleMaterialRows), #goals))
    else panel.pageLabel:SetText("") end
    panel.previousButton:SetEnabled(firstVisibleRowOffset > 0)
    panel.nextButton:SetEnabled(firstVisibleRowOffset + maxVisibleMaterialRows < #goals)
end

-- When editing an existing entry, change the actual on-screen row immediately.
-- Rebuilding/paging the full table remains a separate operation.
updateDisplayedMaterialQuantity = function(itemID)
    for _, row in ipairs(materialRows) do
        if row.itemID == itemID and row:IsShown() then
            local goal = getShoppingSavedData().goals[itemID]
            if goal then
                local ownedQuantity = getOwnedQuantityAcrossCharacters(itemID)
                local missingQuantity = math.max(0, (goal.requiredQuantity) - ownedQuantity)
                row.label:SetText((missingQuantity == 0 and "|cff76dd91" or "|cffffc857") .. getDisplayNameForItem(itemID) .. "|r")
                row.detail:SetText(string.format("Owned %d / Need %d | Missing %d", ownedQuantity, (goal.requiredQuantity), missingQuantity))
            end
            return
        end
    end
end

-- Adding or deleting a row must also update the displayed page.
refreshShoppingAfterChange = function()
    -- Update immediately; the visible-panel change detector also verifies the
    -- view matches saved shopping goals on the following UI frame.
    updateShoppingDisplay()
end

-- The shopping list is a view of saved goals and observed inventory, never of
-- historical gathering records. Keep the displayed rows synchronized while the
-- panel is visible, even when a UI callback changes data during an edit click.
-- A lightweight signature avoids rebuilding unchanged rows every frame.
local function getShoppingDisplaySignature()
    local goalParts = {}
    for itemID, goal in pairs(getShoppingSavedData().goals) do
        local requiredQuantity = tonumber(goal.requiredQuantity) or 0
        if requiredQuantity > 0 then
            local numericItemID = tonumber(itemID)
            local ownedQuantity = numericItemID and getOwnedQuantityAcrossCharacters(numericItemID) or 0
            goalParts[#goalParts + 1] = tostring(itemID) .. ":" .. tostring(requiredQuantity) .. ":" .. tostring(ownedQuantity)
        end
    end
    table.sort(goalParts)
    return tostring(firstVisibleRowOffset) .. "|" .. table.concat(goalParts, "|")
end

local function initializeShoppingWindow(window)
    shoppingWindow = window
    window.activeTab = "statistics"
    -- Reference existing statistics controls rather than duplicating their data or layout.
    for _, region in ipairs({window:GetRegions()}) do
        if region.GetText and region:GetText() == "Material" then window.statisticsHeader = region end
        if region.GetText and region:GetText() == "Collected" then window.statisticsQuantityHeader = region end
    end
    makeButton(window, "Statistics", 17, -290, 100, function() showGatherLedgerTab(false) end)
    makeButton(window, "Shopping List", 125, -290, 115, function() showGatherLedgerTab(true) end)
    -- Overlay only the stats summary/list area; the tabs remain at the bottom.
    local panel = CreateFrame("Frame", nil, window)
    panel:SetPoint("TOPLEFT", 18, -44)
    panel:SetSize(340, 238)
    panel:Hide()
    window.shoppingPanel = panel
    -- This runs only while the shopping panel is visible. Checks are throttled
    -- to ten per second; drawing occurs only after the underlying data changes.
    local shoppingRefreshElapsedSeconds = 0
    local lastDisplayedShoppingSignature = nil
    panel:SetScript("OnShow", function()
        shoppingRefreshElapsedSeconds = 0
        lastDisplayedShoppingSignature = nil
        updateShoppingDisplay()
    end)
    panel:SetScript("OnUpdate", function(_, elapsedSeconds)
        shoppingRefreshElapsedSeconds = shoppingRefreshElapsedSeconds + (elapsedSeconds or 0)
        if shoppingRefreshElapsedSeconds < 0.10 then return end
        shoppingRefreshElapsedSeconds = 0
        local currentShoppingSignature = getShoppingDisplaySignature()
        if currentShoppingSignature ~= lastDisplayedShoppingSignature then
            lastDisplayedShoppingSignature = currentShoppingSignature
            updateShoppingDisplay()
        end
    end)
    panel.summary = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    panel.summary:SetPoint("TOPLEFT", 1, -3)
    panel.summary:SetWidth(322)
    panel.summary:SetJustifyH("LEFT")
    -- Explicit labels distinguish the selected crafting item from its requested count.
    -- These are purely visual controls; Add and Set retain their existing behavior.
    local materialInputLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    materialInputLabel:SetPoint("TOPLEFT", panel, "TOPLEFT", 8, -16)
    materialInputLabel:SetText("Material")
    local quantityInputLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    quantityInputLabel:SetPoint("TOPLEFT", panel, "TOPLEFT", 186, -16)
    quantityInputLabel:SetText("Quantity")
    panel.itemInput = makeInput(panel, 8, -34, 168, "", false)
    panel.quantityInput = makeInput(panel, 186, -34, 46, "1", true)
    window.itemInput = panel.itemInput
    window.quantityInput = panel.quantityInput
    makeButton(panel, "+", 244, -33, 32, addToShoppingListTarget)
    makeButton(panel, "OK", 280, -33, 38, setShoppingListTargetQuantity)
    panel.message = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    panel.message:SetPoint("TOPLEFT", 3, -65)
    panel.message:SetWidth(310)
    panel.message:SetJustifyH("LEFT")
    panel.message:SetText("+ adds to a target. Edit then OK replaces it.")
    -- Four permanent rows are directly parented to the visible shopping panel.
    -- Updating these FontStrings immediately avoids stale scroll-frame child layers.
    for rowIndex = 1, maxVisibleMaterialRows do
        local row = CreateFrame("Frame", nil, panel)
        row:SetSize(302, 32)
        row:SetPoint("TOPLEFT", panel, "TOPLEFT", 2, -84 - (rowIndex - 1) * 34)
        row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.label:SetPoint("TOPLEFT", 2, -2)
        row.label:SetWidth(205)
        row.label:SetJustifyH("LEFT")
        row.detail = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        row.detail:SetPoint("BOTTOMLEFT", 2, 2)
        row.detail:SetWidth(210)
        row.detail:SetJustifyH("LEFT")
        row.editButton = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        row.editButton:SetSize(41, 22)
        row.editButton:SetPoint("RIGHT", -39, 0)
        row.editButton:SetText("Edit")
        row.removeButton = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        row.removeButton:SetSize(35, 22)
        row.removeButton:SetPoint("RIGHT", -2, 0)
        row.removeButton:SetText("X")
        materialRows[rowIndex] = row
    end
    panel.previousButton = makeButton(panel, "<", 2, -216, 24, function()
        firstVisibleRowOffset = math.max(0, firstVisibleRowOffset - maxVisibleMaterialRows)
        updateShoppingDisplay()
    end)
    panel.nextButton = makeButton(panel, ">", 280, -216, 24, function()
        firstVisibleRowOffset = firstVisibleRowOffset + maxVisibleMaterialRows
        updateShoppingDisplay()
    end)
    panel.pageLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    panel.pageLabel:SetPoint("TOP", panel, "TOP", 0, -218)
    -- A short, local suggestion list for known crafting materials. No external libraries.
    local suggestionPanel = CreateFrame("Frame", nil, panel, "BackdropTemplate")
    suggestionPanel:SetFrameStrata("TOOLTIP")
    suggestionPanel:SetPoint("TOPLEFT", panel.itemInput, "BOTTOMLEFT", 0, -2)
    suggestionPanel:SetSize(170, 115)
    suggestionPanel:SetBackdrop({bgFile="Interface\\DialogFrame\\UI-DialogBox-Background", edgeFile="Interface\\Tooltips\\UI-Tooltip-Border", edgeSize=12, insets={left=3,right=3,top=3,bottom=3}})
    suggestionPanel:Hide()
    window.suggestionPanel = suggestionPanel
    window.suggestionButtons = {}
    for suggestionIndex = 1, 5 do
        local suggestionButton = CreateFrame("Button", nil, suggestionPanel)
        suggestionButton:SetSize(160, 21)
        suggestionButton:SetPoint("TOPLEFT", 5, -4 - (suggestionIndex - 1) * 21)
        local label = suggestionButton:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        label:SetPoint("LEFT", 4, 0)
        suggestionButton:SetFontString(label)
        suggestionButton:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
        window.suggestionButtons[suggestionIndex] = suggestionButton
    end
    panel.itemInput:SetScript("OnTextChanged", updateCraftingMaterialSuggestions)
    updateShoppingDisplay()
end

if GatherLedgerRegisterShopping then
    GatherLedgerRegisterShopping(initializeShoppingWindow, updateShoppingDisplay)
end

inventoryWatcher:RegisterEvent("PLAYER_ENTERING_WORLD")
inventoryWatcher:RegisterEvent("BAG_UPDATE_DELAYED")
inventoryWatcher:RegisterEvent("BANKFRAME_OPENED")
inventoryWatcher:RegisterEvent("BANKFRAME_CLOSED")
inventoryWatcher:RegisterEvent("PLAYERBANKSLOTS_CHANGED")
inventoryWatcher:RegisterEvent("PLAYERBANKBAGSLOTS_CHANGED")
inventoryWatcher:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_ENTERING_WORLD" or event == "BAG_UPDATE_DELAYED" then
        saveObservedInventorySnapshot(false)
        if bankIsOpen then saveObservedInventorySnapshot(true) end
    elseif event == "BANKFRAME_OPENED" then
        bankIsOpen = true
        saveObservedInventorySnapshot(true)
    elseif event == "BANKFRAME_CLOSED" then
        bankIsOpen = false
    elseif bankIsOpen then
        saveObservedInventorySnapshot(true)
    end
end)

-- Batch recipe import is exclusively a Shopping List operation.
-- Validate all reagents before changing saved goals; never partially import a recipe.
GatherLedgerAddRecipeIngredients = function(recipeName, recipeReagents, craftCount)
    local resolvedRequirements = {}
    local invalidReagentNames = {}
    for _, reagent in ipairs(recipeReagents) do
        local reagentName = reagent.name or "Unknown ingredient"
        local itemID = tonumber(reagent.itemID) or resolveShoppingItemID(reagentName)
        local requiredPerCraft = tonumber(reagent.requiredPerCraft)
        if not itemID or not requiredPerCraft or requiredPerCraft <= 0 then
            invalidReagentNames[#invalidReagentNames + 1] = reagentName
        else
            local requiredQuantity = requiredPerCraft * craftCount
            resolvedRequirements[itemID] = resolvedRequirements[itemID] or {name = reagentName, requiredQuantity = 0}
            resolvedRequirements[itemID].requiredQuantity = resolvedRequirements[itemID].requiredQuantity + requiredQuantity
        end
    end
    if #invalidReagentNames > 0 then
        return false, "Nothing added. Cannot identify: " .. table.concat(invalidReagentNames, ", ") .. "."
    end
    local shoppingData = getShoppingSavedData()
    local uniqueIngredientCount = 0
    for itemID, requirement in pairs(resolvedRequirements) do
        local savedGoal = shoppingData.goals[itemID] or {itemID = itemID, name = requirement.name, requiredQuantity = 0}
        savedGoal.requiredQuantity = (tonumber(savedGoal.requiredQuantity) or 0) + requirement.requiredQuantity
        savedGoal.name = getDisplayNameForItem(itemID) or requirement.name
        shoppingData.goals[itemID] = savedGoal
        rememberItemName(itemID)
        uniqueIngredientCount = uniqueIngredientCount + 1
    end
    refreshShoppingAfterChange()
    return true, string.format("Added ingredients for %d x %s (%d materials).", craftCount, recipeName, uniqueIngredientCount)
end

-- Remove a recipe's reagents from the shopping list without altering gathering history.
-- Validate the entire selected recipe before changing any shopping goals.
GatherLedgerRemoveRecipeIngredients = function(recipeName, recipeReagents, craftCount)
    local resolvedRequirements = {}
    local invalidReagentNames = {}

    for _, reagent in ipairs(recipeReagents) do
        local reagentName = reagent.name or "Unknown ingredient"
        local itemID = tonumber(reagent.itemID) or resolveShoppingItemID(reagentName)
        local requiredPerCraft = tonumber(reagent.requiredPerCraft)

        if not itemID or not requiredPerCraft or requiredPerCraft <= 0 then
            invalidReagentNames[#invalidReagentNames + 1] = reagentName
        else
            resolvedRequirements[itemID] = (resolvedRequirements[itemID] or 0) +
                (requiredPerCraft * craftCount)
        end
    end

    if #invalidReagentNames > 0 then
        return false, "Nothing removed. Cannot identify: " ..
            table.concat(invalidReagentNames, ", ") .. "."
    end

    local shoppingData = getShoppingSavedData()
    local changedMaterialCount = 0

    for itemID, quantityToRemove in pairs(resolvedRequirements) do
        local savedGoal = shoppingData.goals[itemID]
        if savedGoal then
            local existingRequirement = tonumber(savedGoal.requiredQuantity) or 0
            local remainingRequirement = math.max(0, existingRequirement - quantityToRemove)

            if remainingRequirement == 0 then
                shoppingData.goals[itemID] = nil
            else
                savedGoal.requiredQuantity = remainingRequirement
            end
            changedMaterialCount = changedMaterialCount + 1
        end
    end

    refreshShoppingAfterChange()
    return true, string.format(
        "Removed reagents for %d x %s (%d materials adjusted).",
        craftCount, recipeName, changedMaterialCount
    )
end

-- Show the existing Shopping List panel without accidentally toggling a visible window closed.
-- Both the recipe Add button and /gshop share this entry point.
GatherLedgerShowShoppingList = function()
    if not shoppingWindow or not shoppingWindow:IsShown() then
        if type(GatherLedgerOpenWindow) ~= "function" then return end
        GatherLedgerOpenWindow()
    end
    showGatherLedgerTab(true)
end

-- Provide shortcut without replacing the original /gledger macro.
SLASH_GATHERLEDGERSHOP1 = "/gshop"
SlashCmdList.GATHERLEDGERSHOP = GatherLedgerShowShoppingList
