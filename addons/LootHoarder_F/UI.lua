-- Single lifetime totals screen. No history, source dashboard or account aggregation.
local addon = LootHoarderForever
local statisticsWindow
local categoryValueLabels = {}
local totalValueLabel
local modeValueLabel
local function CreateWindowLabel(parentFrame, textValue, fontObject, anchorPoint, relativeFrame, relativePoint, offsetX, offsetY)
    local label = parentFrame:CreateFontString(nil, "OVERLAY", fontObject)
    label:SetPoint(anchorPoint, relativeFrame, relativePoint, offsetX, offsetY)
    label:SetText(textValue)
    return label
end
local function BuildStatisticsWindow()
    if type(CreateFrame) ~= "function" or not UIParent then
        addon.RecordDiagnostic("ui_api_unavailable")
        return nil
    end
    local window = CreateFrame("Frame", "LootHoarderForeverStatistics", UIParent)
    window:SetSize(490, 535)
    window:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    window:SetFrameStrata("DIALOG")
    window:SetMovable(true)
    window:EnableMouse(true)
    window:RegisterForDrag("LeftButton")
    window:SetScript("OnDragStart", function(self) self:StartMoving() end)
    window:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    local backgroundTexture = window:CreateTexture(nil, "BACKGROUND")
    backgroundTexture:SetAllPoints(window)
    if type(backgroundTexture.SetColorTexture) == "function" then
        backgroundTexture:SetColorTexture(0.035, 0.04, 0.055, 0.95)
    elseif type(backgroundTexture.SetTexture) == "function" then
        backgroundTexture:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Background")
    end
    CreateWindowLabel(window, "LootHoarder Forever — Lifetime", "GameFontNormalLarge", "TOPLEFT", window, "TOPLEFT", 18, -16)
    local closeButton = CreateFrame("Button", nil, window)
    closeButton:SetSize(28, 28)
    closeButton:SetPoint("TOPRIGHT", window, "TOPRIGHT", -8, -7)
    local closeLabel = CreateWindowLabel(closeButton, "X", "GameFontNormalLarge", "CENTER", closeButton, "CENTER", 0, 0)
    closeButton:SetScript("OnClick", function() window:Hide() end)
    for categoryIndex, categoryName in ipairs(addon.categoryNames) do
        local rowOffset = -49 - ((categoryIndex - 1) * 22)
        CreateWindowLabel(window, categoryName, "GameFontHighlight", "TOPLEFT", window, "TOPLEFT", 22, rowOffset)
        local valueLabel = CreateWindowLabel(window, "0", "GameFontHighlight", "TOPRIGHT", window, "TOPRIGHT", -25, rowOffset)
        categoryValueLabels[categoryName] = valueLabel
    end
    totalValueLabel = CreateWindowLabel(window, "Total: 0", "GameFontNormal", "TOPLEFT", window, "TOPLEFT", 22, -392)
    modeValueLabel = CreateWindowLabel(window, "Commentary: Silent", "GameFontHighlightSmall", "TOPLEFT", window, "TOPLEFT", 22, -419)
    local nextModeButton = CreateFrame("Button", nil, window)
    nextModeButton:SetSize(110, 24)
    nextModeButton:SetPoint("TOPRIGHT", window, "TOPRIGHT", -22, -411)
    CreateWindowLabel(nextModeButton, "Change mode >", "GameFontNormal", "CENTER", nextModeButton, "CENTER", 0, 0)
    nextModeButton:SetScript("OnClick", function()
        if not addon.persistenceAvailable then return end
        local currentMode = addon.characterRecord.humorMode
        local nextMode = addon.humorModes[1]
        for modeIndex, humorMode in ipairs(addon.humorModes) do
            if humorMode == currentMode then
                nextMode = addon.humorModes[(modeIndex % #addon.humorModes) + 1]
                break
            end
        end
        addon.SetHumorMode(nextMode)
        addon.RefreshWindow()
    end)
    local disclaimerLabel = CreateWindowLabel(window, addon.disclaimer, "GameFontHighlightSmall", "TOPLEFT", window, "TOPLEFT", 22, -459)
    disclaimerLabel:SetWidth(446)
    disclaimerLabel:SetJustifyH("LEFT")
    disclaimerLabel:SetWordWrap(true)
    window:Hide()
    return window
end
function addon.RefreshWindow()
    if not statisticsWindow then return end
    local characterRecord = addon.characterRecord
    for _, categoryName in ipairs(addon.categoryNames) do
        local totalUnits = characterRecord and characterRecord.categoryTotals[categoryName] or 0
        categoryValueLabels[categoryName]:SetText(tostring(totalUnits))
    end
    totalValueLabel:SetText("Total: " .. tostring(characterRecord and characterRecord.totalUnits or 0))
    modeValueLabel:SetText("Commentary: " .. tostring(characterRecord and characterRecord.humorMode or "Silent"))
end
function addon.ToggleStatisticsWindow()
    if not statisticsWindow then statisticsWindow = BuildStatisticsWindow() end
    if not statisticsWindow then return end
    if statisticsWindow:IsShown() then
        statisticsWindow:Hide()
    else
        addon.RefreshWindow()
        statisticsWindow:Show()
    end
end
