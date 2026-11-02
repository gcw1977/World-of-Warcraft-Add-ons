-- BICore_F Dashboard.lua | 0.1.0-dev.1
-- Exactly one movable diagnostic dashboard. No target addon windows or actions.
local addonIdentifier, addonNamespace = ...
local dashboard = {}
addonNamespace.Dashboard = dashboard
local registry = addonNamespace.Registry
local diagnostics = addonNamespace.Diagnostics
local dashboardFrame, buttonScrollContent, reportEditBox, copyHint
local reportPartLabel, previousPartButton, nextPartButton
local addonButtons = {}
local summaryByIdentifier = {}
local selectedIdentifier, frozenReport, reportParts, currentPart = nil, nil, {}, 1
local selectionGeneration = 0
local maximumCopyPartBytes = 4096

local function splitIntoParts(report)
    local parts = {}
    local nextByte = 1
    while nextByte <= #report do
        local lastByte = math.min(#report, nextByte + maximumCopyPartBytes - 1)
        -- Avoid splitting a UTF-8 continuation byte between selectable parts.
        if lastByte < #report then
            while lastByte > nextByte do
                local followingByte = report:byte(lastByte + 1)
                if not followingByte or followingByte < 128 or followingByte > 191 then break end
                lastByte = lastByte - 1
            end
        end
        parts[#parts + 1] = report:sub(nextByte, lastByte)
        nextByte = lastByte + 1
    end
    if #parts == 0 then parts[1] = "" end
    return parts
end

local function applySavedPosition()
    dashboardFrame:ClearAllPoints()
    local database = BICoreForeverDB
    local position = type(database) == "table" and database.position
    local width = UIParent:GetWidth() or 0
    local height = UIParent:GetHeight() or 0
    if type(position) == "table" and type(position.left) == "number"
        and type(position.top) == "number"
        and position.left == position.left and position.top == position.top
        and position.left >= -100 and position.left <= width - 100
        and position.top >= 100 and position.top <= height + 100 then
        dashboardFrame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", position.left, position.top)
    else
        dashboardFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end
end

function dashboard.ResetPosition()
    if type(BICoreForeverDB) == "table" then BICoreForeverDB.position = nil end
    if dashboardFrame then applySavedPosition() end
end

local function showPart(partNumber)
    if not reportEditBox then return end
    currentPart = math.max(1, math.min(partNumber, #reportParts))
    reportEditBox:ClearFocus()
    reportEditBox:SetText(reportParts[currentPart] or "")
    reportEditBox:SetCursorPosition(0)
    reportPartLabel:SetText("Report part " .. currentPart .. " of " .. #reportParts)
    previousPartButton:SetEnabled(currentPart > 1)
    nextPartButton:SetEnabled(currentPart < #reportParts)
    if #reportParts > 1 then
        copyHint:SetText("Multi-part report: copy each numbered part separately.")
    else
        copyHint:SetText("Select Copy Report, then press Ctrl+C.")
    end
end

local function setSelectedReport(result)
    selectionGeneration = selectionGeneration + 1
    if reportEditBox then reportEditBox:ClearFocus(); reportEditBox:SetText("") end
    frozenReport = result
    reportParts = splitIntoParts(result.text or "")
    currentPart = 1
    showPart(1)
end

local function refreshSelected()
    if not selectedIdentifier then return end
    local descriptor = registry.GetDescriptor(selectedIdentifier)
    if not descriptor then return end
    local result = diagnostics.Capture(descriptor, "FULL")
    summaryByIdentifier[selectedIdentifier] = result
    setSelectedReport(result)
    dashboard.RenderButtons()
end

local function selectAddon(targetIdentifier)
    selectedIdentifier = targetIdentifier
    setSelectedReport({text="", complete=false})
    refreshSelected()
end

function dashboard.RefreshSummaries()
    registry.DiscoverMetadata()
    for _, descriptor in ipairs(registry.GetDescriptors()) do
        summaryByIdentifier[descriptor.addonIdentifier] = diagnostics.Capture(descriptor, "SUMMARY")
    end
    dashboard.RenderButtons()
end

function dashboard.Refresh()
    if selectedIdentifier then refreshSelected() else dashboard.RefreshSummaries() end
end

local function createAddonButton(parent)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetSize(292, 28)
    button:SetScript("OnClick", function(self)
        selectAddon(self.targetAddonIdentifier)
    end)
    button:SetScript("OnEnter", function(self)
        local status = summaryByIdentifier[self.targetAddonIdentifier]
        if GameTooltip then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(status and status.reason or "Not checked")
            GameTooltip:Show()
        end
    end)
    button:SetScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)
    return button
end

function dashboard.RenderButtons()
    if not buttonScrollContent then return end
    local descriptors = registry.GetDescriptors()
    for descriptorIndex, descriptor in ipairs(descriptors) do
        local button = addonButtons[descriptorIndex]
        if not button then
            button = createAddonButton(buttonScrollContent)
            addonButtons[descriptorIndex] = button
        end
        local columnIndex = (descriptorIndex - 1) % 2
        local rowIndex = math.floor((descriptorIndex - 1) / 2)
        button:ClearAllPoints()
        button:SetPoint("TOPLEFT", buttonScrollContent, "TOPLEFT",
            columnIndex * 302 + 3, -rowIndex * 32 - 3)
        button.targetAddonIdentifier = descriptor.addonIdentifier
        local status = summaryByIdentifier[descriptor.addonIdentifier]
        local color = status and status.color or "GRAY"
        local symbol = color == "GREEN" and "[+]" or (color == "RED" and "[!]" or "[?]")
        button:SetText(symbol .. " " .. descriptor.displayName .. " - " .. color)
        local fontString = button:GetFontString()
        if fontString then
            if color == "GREEN" then fontString:SetTextColor(0.35, 1, 0.35)
            elseif color == "RED" then fontString:SetTextColor(1, 0.4, 0.4)
            else fontString:SetTextColor(0.75, 0.75, 0.75) end
        end
        button:Show()
    end
    for buttonIndex = #descriptors + 1, #addonButtons do
        addonButtons[buttonIndex]:Hide()
    end
    buttonScrollContent:SetHeight(math.max(125, math.ceil(#descriptors / 2) * 32 + 8))
end

local function createLabel(parent, labelText, xOffset, yOffset)
    local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("TOPLEFT", parent, "TOPLEFT", xOffset, yOffset)
    label:SetText(labelText)
    return label
end

local function createActionButton(parent, labelText, width, xOffset, yOffset, callback)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetSize(width, 25)
    button:SetPoint("TOPLEFT", parent, "TOPLEFT", xOffset, yOffset)
    button:SetText(labelText)
    button:SetScript("OnClick", callback)
    return button
end

local function createDashboard()
    if dashboardFrame then return end
    dashboardFrame = CreateFrame("Frame", "BICoreDashboard", UIParent, "BasicFrameTemplateWithInset")
    dashboardFrame:SetSize(680, 560)
    dashboardFrame:SetFrameStrata("DIALOG")
    dashboardFrame:SetClampedToScreen(true)
    dashboardFrame:SetMovable(true)
    dashboardFrame:EnableMouse(true)
    dashboardFrame:RegisterForDrag("LeftButton")
    dashboardFrame:SetScript("OnDragStart", dashboardFrame.StartMoving)
    dashboardFrame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local left, top = self:GetLeft(), self:GetTop()
        if type(BICoreForeverDB) == "table" and type(left) == "number"
            and type(top) == "number" then
            BICoreForeverDB.position = {left=left, top=top}
        end
    end)
    if dashboardFrame.TitleText then
        dashboardFrame.TitleText:SetText("BEESTWOOD INDUSTRIES - BI CORE")
    else
        createLabel(dashboardFrame, "BEESTWOOD INDUSTRIES - BI CORE", 20, -10)
    end
    if not dashboardFrame.CloseButton then
        local closeButton = CreateFrame("Button", nil, dashboardFrame, "UIPanelCloseButton")
        closeButton:SetPoint("TOPRIGHT", dashboardFrame, "TOPRIGHT", -4, -4)
        closeButton:SetScript("OnClick", function() dashboard.Close() end)
    end

    createLabel(dashboardFrame, "Addon health (select a report)", 22, -40)
    local buttonScrollFrame = CreateFrame("ScrollFrame", nil, dashboardFrame, "UIPanelScrollFrameTemplate")
    buttonScrollFrame:SetPoint("TOPLEFT", dashboardFrame, "TOPLEFT", 22, -63)
    buttonScrollFrame:SetSize(612, 139)
    buttonScrollContent = CreateFrame("Frame", nil, buttonScrollFrame)
    buttonScrollContent:SetSize(606, 139)
    buttonScrollFrame:SetScrollChild(buttonScrollContent)

    createActionButton(dashboardFrame, "Refresh", 90, 22, -214, function() dashboard.Refresh() end)
    createActionButton(dashboardFrame, "Copy Report", 125, 120, -214, function()
        if not frozenReport or not selectedIdentifier then
            copyHint:SetText("Select an addon before copying.")
            return
        end
        local reportPart = reportParts[currentPart]
        if not reportPart or reportPart == "" then
            copyHint:SetText("No report text is available.")
            return
        end
        -- Restore canonical frozen content before focus; typing never changes it.
        reportEditBox:SetText(reportPart)
        reportEditBox:SetFocus()
        reportEditBox:HighlightText(0, -1)
        if frozenReport.complete then
            copyHint:SetText("Text selected - press Ctrl+C. Clipboard not verified.")
        else
            copyHint:SetText("INCOMPLETE report part selected - press Ctrl+C.")
        end
    end)
    previousPartButton = createActionButton(dashboardFrame, "Previous", 92, 265, -214,
        function() showPart(currentPart - 1) end)
    nextPartButton = createActionButton(dashboardFrame, "Next", 75, 363, -214,
        function() showPart(currentPart + 1) end)
    reportPartLabel = createLabel(dashboardFrame, "No report selected", 448, -220)
    copyHint = createLabel(dashboardFrame, "Select an addon to view its diagnostics.", 24, -250)

    local reportScrollFrame = CreateFrame("ScrollFrame", nil, dashboardFrame, "UIPanelScrollFrameTemplate")
    reportScrollFrame:SetPoint("TOPLEFT", dashboardFrame, "TOPLEFT", 25, -277)
    reportScrollFrame:SetSize(602, 240)
    reportEditBox = CreateFrame("EditBox", nil, reportScrollFrame)
    reportEditBox:SetMultiLine(true)
    reportEditBox:SetAutoFocus(false)
    reportEditBox:SetFontObject(ChatFontNormal)
    reportEditBox:SetWidth(590)
    reportEditBox:SetHeight(300)
    reportEditBox:SetTextInsets(4, 4, 4, 4)
    reportEditBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    reportScrollFrame:SetScrollChild(reportEditBox)
    applySavedPosition()
    dashboardFrame:Hide()
end

function dashboard.Open()
    createDashboard()
    selectedIdentifier, frozenReport, reportParts = nil, nil, {}
    if reportEditBox then reportEditBox:ClearFocus(); reportEditBox:SetText("") end
    reportPartLabel:SetText("No report selected")
    copyHint:SetText("Select an addon to view its diagnostics.")
    dashboard.RefreshSummaries()
    dashboardFrame:Show()
end

function dashboard.Close()
    if dashboardFrame then
        if reportEditBox then reportEditBox:ClearFocus() end
        dashboardFrame:Hide()
    end
end

function dashboard.IsVisible()
    return dashboardFrame and dashboardFrame:IsShown() or false
end

function dashboard.OnAddonLoaded(loadedIdentifier)
    if dashboard.IsVisible() then
        registry.DiscoverMetadata()
        local descriptor = registry.GetDescriptor(loadedIdentifier)
        if descriptor then
            summaryByIdentifier[loadedIdentifier] = diagnostics.Capture(descriptor, "SUMMARY")
            dashboard.RenderButtons()
        end
    end
end
