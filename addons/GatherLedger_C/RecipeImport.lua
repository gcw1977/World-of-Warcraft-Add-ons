-- GatherLedger recipe importer for WoW Classic Era.
-- Reads selected profession recipe; sends its reagents to the Shopping module.
-- Does not read gathering observations or infer inventory ownership.
local recipeImportWatcher = CreateFrame("Frame")
local professionControls = {}

-- Adjustable visual alignment. Independent of gathering, inventory, and shopping data.
local function getPanelAlignment()
    GatherLedgerDB = GatherLedgerDB or {}
    GatherLedgerDB.recipePanelAlignment = GatherLedgerDB.recipePanelAlignment or {horizontalOffset = -2, widthAdjustment = 4}
    return GatherLedgerDB.recipePanelAlignment
end


local function informUser(message)
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage("|cffefca69[GatherLedger]|r " .. message)
    end
end

local function extractItemIDFromLink(itemLink)
    return itemLink and tonumber(itemLink:match("item:(%d+)")) or nil
end

local function getSelectedProfessionRecipe(isEnchanting)
    if isEnchanting then
        if not GetCraftSelectionIndex or not GetCraftNumReagents or not GetCraftReagentInfo then return nil, "Enchanting recipe API unavailable." end
        local selectedIndex = GetCraftSelectionIndex()
        if not selectedIndex or selectedIndex < 1 then return nil, "Select a recipe first." end
        local recipeName, _, recipeDifficulty = GetCraftInfo(selectedIndex)
        if not recipeName or recipeDifficulty == "header" then return nil, "Select an actual recipe, not a heading." end
        local reagents = {}
        for reagentIndex = 1, (GetCraftNumReagents(selectedIndex) or 0) do
            local reagentName, _, requiredPerCraft = GetCraftReagentInfo(selectedIndex, reagentIndex)
            local reagentLink = GetCraftReagentItemLink and GetCraftReagentItemLink(selectedIndex, reagentIndex)
            reagents[#reagents+1] = {name = reagentName, itemID = extractItemIDFromLink(reagentLink), requiredPerCraft = requiredPerCraft}
        end
        return {name = recipeName, reagents = reagents}
    end
    if not GetTradeSkillSelectionIndex or not GetTradeSkillNumReagents or not GetTradeSkillReagentInfo then return nil, "Trade skill recipe API unavailable." end
    local selectedIndex = GetTradeSkillSelectionIndex()
    if not selectedIndex or selectedIndex < 1 then return nil, "Select a recipe first." end
    local recipeName, recipeDifficulty = GetTradeSkillInfo(selectedIndex)
    if not recipeName or recipeDifficulty == "header" then return nil, "Select an actual recipe, not a heading." end
    local reagents = {}
    for reagentIndex = 1, (GetTradeSkillNumReagents(selectedIndex) or 0) do
        local reagentName, _, requiredPerCraft = GetTradeSkillReagentInfo(selectedIndex, reagentIndex)
        local reagentLink = GetTradeSkillReagentItemLink and GetTradeSkillReagentItemLink(selectedIndex, reagentIndex)
        reagents[#reagents+1] = {name = reagentName, itemID = extractItemIDFromLink(reagentLink), requiredPerCraft = requiredPerCraft}
    end
    return {name = recipeName, reagents = reagents}
end

local function importSelectedRecipe(isEnchanting, quantityInput)
    local craftCount = tonumber(quantityInput:GetText())
    if not craftCount or craftCount < 1 or craftCount > 9999 or craftCount ~= math.floor(craftCount) then
        informUser("Enter a whole number of crafts from 1 to 9999.")
        return
    end
    local recipe, recipeError = getSelectedProfessionRecipe(isEnchanting)
    if not recipe then informUser(recipeError); return end
    if #recipe.reagents == 0 then informUser("This recipe has no item reagents to add."); return end
    if type(GatherLedgerAddRecipeIngredients) ~= "function" then informUser("Shopping module is unavailable."); return end
    local success, message = GatherLedgerAddRecipeIngredients(recipe.name, recipe.reagents, craftCount)
    informUser(message)
    if success and type(GatherLedgerShowShoppingHUD) == "function" then
        GatherLedgerShowShoppingHUD()
    end
end

local function removeSelectedRecipeReagents(isEnchanting, craftCountInput)
    local craftCount = tonumber(craftCountInput:GetText())
    if not craftCount or craftCount < 1 or craftCount > 9999 or
        craftCount ~= math.floor(craftCount) then
        informUser("Enter a whole number of crafts from 1 to 9999.")
        return
    end

    local recipe, recipeError = getSelectedProfessionRecipe(isEnchanting)
    if not recipe then informUser(recipeError); return end
    if #recipe.reagents == 0 then
        informUser("This recipe has no item reagents to remove.")
        return
    end
    if type(GatherLedgerRemoveRecipeIngredients) ~= "function" then
        informUser("Shopping module is unavailable.")
        return
    end

    local success, message = GatherLedgerRemoveRecipeIngredients(
        recipe.name, recipe.reagents, craftCount
    )
    informUser(message)
end

local function getVisibleProfessionPanelMetrics(professionFrame, isEnchanting)
    local createAllButton = isEnchanting and CraftCreateAllButton or TradeSkillCreateAllButton
    local exitButton = isEnchanting and CraftCancelButton or TradeSkillCancelButton

    local leftOffset = 10
    local panelWidth = professionFrame:GetWidth() - 20
    local verticalOffset = 82

    if professionFrame.GetLeft and createAllButton and createAllButton.GetLeft and exitButton and exitButton.GetRight then
        local frameLeft = professionFrame:GetLeft()
        local createLeft = createAllButton:GetLeft()
        local exitRight = exitButton:GetRight()
        if frameLeft and createLeft and exitRight then
            leftOffset = math.floor((createLeft - frameLeft) - 6 + 0.5)
            local rightOffset = math.floor((exitRight - frameLeft) + 6 + 0.5)
            panelWidth = math.max(300, rightOffset - leftOffset)
        end
    end

    if professionFrame.GetBottom and exitButton and exitButton.GetBottom then
        local frameBottom = professionFrame:GetBottom()
        local exitBottom = exitButton:GetBottom()
        if frameBottom and exitBottom then
            verticalOffset = math.floor((exitBottom - frameBottom) - 3 + 0.5)
        end
    end

    return leftOffset, panelWidth, verticalOffset
end

-- Position below the visible profession window, attached like a bolt-on module.
local function positionProfessionControls(professionFrame, importPanel, isEnchanting)
    local leftOffset, panelWidth, verticalOffset = getVisibleProfessionPanelMetrics(professionFrame, isEnchanting)
    local alignment = getPanelAlignment()
    importPanel:ClearAllPoints()
    importPanel:SetWidth(panelWidth + alignment.widthAdjustment)
    importPanel:SetPoint("TOPLEFT", professionFrame, "BOTTOMLEFT", leftOffset + alignment.horizontalOffset, verticalOffset)
end

-- Reuse Blizzard's dialog box artwork, rather than drawing imitation borders.
-- A child frame of the profession window keeps the panel attached during movement
-- and hides it automatically when the profession window closes.
local function createProfessionControls(professionFrame, isEnchanting)
    local existingPanel = professionControls[professionFrame]
    if existingPanel then
        positionProfessionControls(professionFrame, existingPanel, isEnchanting)
        existingPanel:Show()
        return
    end

    local _, visiblePanelWidth = getVisibleProfessionPanelMetrics(professionFrame, isEnchanting)

    local panelHeight = 62
    local templateName = BackdropTemplateMixin and "BackdropTemplate" or nil
    local importPanel = CreateFrame("Frame", nil, professionFrame, templateName)
    importPanel:SetSize(visiblePanelWidth, panelHeight)
    positionProfessionControls(professionFrame, importPanel, isEnchanting)
    importPanel:SetFrameStrata(professionFrame:GetFrameStrata())
    importPanel:SetFrameLevel(professionFrame:GetFrameLevel() + 5)
    importPanel:EnableMouse(true)

    if importPanel.SetBackdrop then
        importPanel:SetBackdrop({
            bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile = true,
            tileSize = 32,
            edgeSize = 24,
            insets = { left = 7, right = 7, top = 7, bottom = 7 },
        })
        importPanel:SetBackdropColor(0.18, 0.14, 0.10, 0.96)
        importPanel:SetBackdropBorderColor(0.85, 0.77, 0.60, 1)
    else
        -- Compatibility fallback for a client without backdrop support.
        local backgroundTexture = importPanel:CreateTexture(nil, "BACKGROUND")
        backgroundTexture:SetAllPoints(importPanel)
        backgroundTexture:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Background")
    end

    local titleText = importPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    titleText:SetPoint("TOPLEFT", importPanel, "TOPLEFT", 19, -12)
    titleText:SetText("Add to Shopping List")

    local craftsLabel = importPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    craftsLabel:SetPoint("TOPLEFT", importPanel, "TOPLEFT", 20, -35)
    craftsLabel:SetText("Crafts")

    local craftCountInput = CreateFrame("EditBox", nil, importPanel, "InputBoxTemplate")
    craftCountInput:SetSize(34, 20)
    craftCountInput:SetPoint("LEFT", craftsLabel, "RIGHT", 10, 0)
    craftCountInput:SetAutoFocus(false)
    craftCountInput:SetNumeric(true)
    craftCountInput:SetMaxLetters(4)
    craftCountInput:SetText("1")
    craftCountInput:SetFrameLevel(importPanel:GetFrameLevel() + 2)

    local addRecipeButton = CreateFrame("Button", nil, importPanel, "UIPanelButtonTemplate")
    addRecipeButton:SetSize(65, 22)
    addRecipeButton:SetPoint("LEFT", craftCountInput, "RIGHT", 12, 0)
    addRecipeButton:SetText("Add")
    addRecipeButton:SetFrameLevel(importPanel:GetFrameLevel() + 2)
    addRecipeButton:SetScript("OnClick", function()
        importSelectedRecipe(isEnchanting, craftCountInput)
    end)

    local removeRecipeButton = CreateFrame("Button", nil, importPanel, "UIPanelButtonTemplate")
    removeRecipeButton:SetSize(75, 22)
    removeRecipeButton:SetPoint("LEFT", addRecipeButton, "RIGHT", 4, 0)
    removeRecipeButton:SetText("Remove")
    removeRecipeButton:SetFrameLevel(importPanel:GetFrameLevel() + 2)
    removeRecipeButton:SetScript("OnClick", function()
        removeSelectedRecipeReagents(isEnchanting, craftCountInput)
    end)

    professionControls[professionFrame] = importPanel
end

recipeImportWatcher:RegisterEvent("TRADE_SKILL_SHOW")
recipeImportWatcher:RegisterEvent("CRAFT_SHOW")
recipeImportWatcher:SetScript("OnEvent", function(_, event)
    if event == "TRADE_SKILL_SHOW" and TradeSkillFrame then
        createProfessionControls(TradeSkillFrame, false)
    elseif event == "CRAFT_SHOW" and CraftFrame then
        createProfessionControls(CraftFrame, true)
    end
end)

-- Fine-adjust the horizontal seam without requiring a reinstall.
-- Usage: /glpanel -2 4   (horizontal offset, width adjustment, UI units)
SLASH_GATHERLEDGERPANEL1 = "/glpanel"
SlashCmdList.GATHERLEDGERPANEL = function(arguments)
    local offsetText, widthText = (arguments or ""):match("^%s*([+-]?%d+)%s+([+-]?%d+)%s*$")
    if not offsetText or not widthText then
        local alignment = getPanelAlignment()
        informUser("Panel alignment: horizontal " .. alignment.horizontalOffset .. ", width " .. alignment.widthAdjustment .. ". Use /glpanel <horizontal> <width>.")
        return
    end
    local horizontalOffset = tonumber(offsetText)
    local widthAdjustment = tonumber(widthText)
    if math.abs(horizontalOffset) > 40 or math.abs(widthAdjustment) > 80 then
        informUser("Adjustments must be within 40 horizontal and 80 width UI units.")
        return
    end
    local alignment = getPanelAlignment()
    alignment.horizontalOffset = horizontalOffset
    alignment.widthAdjustment = widthAdjustment
    for professionFrame, importPanel in pairs(professionControls) do
        positionProfessionControls(professionFrame, importPanel, professionFrame == CraftFrame)
    end
    informUser("Panel aligned: horizontal " .. horizontalOffset .. ", width " .. widthAdjustment .. ". Saved for future sessions.")
end
