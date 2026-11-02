-- Goblinomicon Forever: two read-only book pages with 50-row virtualized ledger display.
-- No UI handler writes a monetary row, observes wallet, or changes game currency.
local Addon = GoblinomiconForever
Addon.UI = { page = "OVERVIEW", period = "LIFETIME", selectedGuid = nil,
    offset = 0, expandAll = false, expandedMonths = {}, expandedDays = {},
    expandedMovements = {}, rows = {} }
local UI = Addon.UI
local PARCHMENT = { 0.82, 0.73, 0.51 }
local BRASS = { 0.82, 0.63, 0.27 }

local function CreateButton(parent, label, width, height)
    local ok, button = pcall(CreateFrame, "Button", nil, parent, "UIPanelButtonTemplate")
    if not ok or not button then
        button = CreateFrame("Button", nil, parent)
        local texture = button:CreateTexture(nil, "BACKGROUND")
        texture:SetAllPoints()
        texture:SetColorTexture(0.20, 0.15, 0.08, 0.95)
        local caption = button:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        caption:SetAllPoints()
        button:SetFontString(caption)
    end
    button:SetSize(width, height)
    button:SetText(label)
    return button
end

local function SetButtonText(button, label)
    if button and type(button.SetText) == "function" then button:SetText(label) end
end

local function SelectedCharacter()
    if not Addon.Persistence.database then return nil end
    local guid = UI.selectedGuid or Addon.runtime.currentGuid
    return Addon.Persistence.database.characters[guid], guid
end

local function IsExpanded(overrides, key)
    if overrides[key] ~= nil then return overrides[key] end
    return UI.expandAll
end

local function ResetExpansion()
    UI.offset = 0
    UI.expandAll = false
    UI.expandedMonths = {}
    UI.expandedDays = {}
    UI.expandedMovements = {}
    UI.selectedMonthKey = nil
    UI.selectedDayKey = nil
    local character = SelectedCharacter()
    if character then
        local index = Addon.Ledger.MonthIndex(character)
        local newestMonth = index.monthOrder[1]
        if newestMonth then
            UI.expandedMonths[newestMonth] = true
            local newestDay = index.months[newestMonth].dayOrder[1]
            if newestDay then UI.expandedDays[newestDay] = true end
        end
    end
end

local function AddRow(rows, kind, text, key, color)
    rows[#rows + 1] = { kind = kind, text = text, key = key, color = color }
end

local function OverviewRows(character, guid)
    local rows = {}
    if not character then
        AddRow(rows, "info", "No character history available. Tracking begins at first readable wallet snapshot.")
        return rows
    end
    local isCurrent = guid == Addon.runtime.currentGuid
    AddRow(rows, "header", isCurrent and "CURRENT CHARACTER WALLET (LAST OBSERVED)" or "OFFLINE CHARACTER - LAST OBSERVED WALLET", nil, BRASS)
    AddRow(rows, "info", "Character: " .. (character.identity.name or "Unknown") .. " - " .. (character.identity.realm or "Unknown"))
    AddRow(rows, "info", "Balance: " .. Addon.FormatCoins(character.lastCopper) .. "  |  Last observation: " .. Addon.DateLabel(character.lastObservedAt, "%Y-%m-%d %H:%M"))
    AddRow(rows, "info", "Tracking began with: " .. Addon.FormatCoins(character.opening and character.opening.copper) .. " (not income)")
    local stats = Addon.Ledger.Statistics(character, UI.period)
    AddRow(rows, "header", UI.period .. " - RECORDED WALLET MOVEMENTS", nil, BRASS)
    AddRow(rows, "credit", "CREDITS: +" .. Addon.FormatCoins(stats.credits) .. "  |  " .. tostring(stats.count) .. " movements", nil, { 0.22, 0.57, 0.28 })
    AddRow(rows, "debit", "DEBITS: -" .. Addon.FormatCoins(stats.debits), nil, { 0.72, 0.25, 0.22 })
    AddRow(rows, "info", "NET CHANGE: " .. Addon.SignedCoins(stats.credits - stats.debits))
    AddRow(rows, "info", "Includes transfers and unattributed gaps; not a claim of economic profit.")
    local categoryNames = {}
    for category in pairs(stats.categories) do categoryNames[#categoryNames + 1] = category end
    table.sort(categoryNames)
    AddRow(rows, "header", "ALL RECORDED CATEGORIES", nil, BRASS)
    if #categoryNames == 0 then AddRow(rows, "info", "No movements recorded for this period.") end
    for _, category in ipairs(categoryNames) do
        local entry = stats.categories[category]
        local prefix = entry.sign == "CREDIT" and "+" or "-"
        AddRow(rows, "info", prefix .. " " .. category .. ": " .. Addon.FormatCoins(entry.amount) .. " (" .. tostring(entry.count) .. ")")
    end
    local integrity, reason = Addon.Ledger.Verify(character)
    AddRow(rows, "header", "RECONCILIATION: " .. (integrity and "MATCH" or "FAIL: " .. reason), nil,
        integrity and { 0.22, 0.57, 0.28 } or { 0.72, 0.25, 0.22 })
    if UI.period == "SESSION" and not isCurrent then
        AddRow(rows, "info", "Showing this character's last recorded session; not an active session.")
    end
    return rows
end

-- Iterate logical hierarchy and materialize ONLY the current 50-row page.
-- Expand All changes logical state, never instantiates all transaction widgets.
local function LedgerRows(character)
    local rows = {}
    if not character then return rows, 0 end
    local index = Addon.Ledger.MonthIndex(character)
    local count = 0
    local startOffset = UI.offset
    local function Offer(kind, text, key, color)
        count = count + 1
        if count > startOffset and count <= startOffset + 50 then
            AddRow(rows, kind, text, key, color)
        end
    end
    for _, monthKey in ipairs(index.monthOrder) do
        local month = index.months[monthKey]
        local monthExpanded = IsExpanded(UI.expandedMonths, monthKey)
        Offer("month", (monthExpanded and "v " or "> ") .. monthKey .. " (" .. tostring(month.count) .. " movements)", monthKey, BRASS)
        if monthExpanded then
            for _, dayKey in ipairs(month.dayOrder) do
                local day = month.days[dayKey]
                local dayExpanded = IsExpanded(UI.expandedDays, dayKey)
                Offer("day", "  " .. (dayExpanded and "v " or "> ") .. dayKey .. " (" .. tostring(#day.sequences) .. ")", dayKey)
                if dayExpanded then
                    for position = #day.sequences, 1, -1 do
                        local movement = character.movements[day.sequences[position]]
                        local expanded = IsExpanded(UI.expandedMovements, movement.sequence)
                        local description = movement.category
                        local sign = movement.deltaCopper > 0 and "CREDIT" or "DEBIT"
                        local label = "    " .. (expanded and "v " or "> ")
                            .. Addon.DateLabel(movement.at, "%H:%M:%S") .. "  " .. sign .. " "
                            .. Addon.SignedCoins(movement.deltaCopper) .. "  " .. description
                            .. "  -> " .. Addon.FormatCoins(movement.afterCopper)
                        Offer("movement", label, movement.sequence,
                            movement.deltaCopper > 0 and { 0.22, 0.57, 0.28 } or { 0.72, 0.25, 0.22 })
                        if expanded then
                            Offer("detail", "       #" .. tostring(movement.sequence) .. " "
                                .. movement.confidence .. " / " .. movement.evidence
                                .. " | " .. (movement.isGap and "UNATTRIBUTED GAP" or movement.trigger)
                                .. " | session " .. tostring(movement.sessionId), movement.sequence)
                        end
                    end
                end
            end
        end
    end
    return rows, count
end

local function RenderRowWidgets(rows)
    local content = UI.scrollContent
    for index, descriptor in ipairs(rows) do
        local button = UI.rows[index]
        if not button then
            button = CreateFrame("Button", nil, content)
            button:SetHeight(22)
            button:SetPoint("RIGHT", content, "RIGHT", -4, 0)
            button:SetPoint("LEFT", content, "LEFT", 4, 0)
            button.caption = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            button.caption:SetPoint("LEFT", button, "LEFT", 2, 0)
            button.caption:SetPoint("RIGHT", button, "RIGHT", -2, 0)
            button.caption:SetJustifyH("LEFT")
            UI.rows[index] = button
        end
        button:ClearAllPoints()
        button:SetPoint("TOPLEFT", content, "TOPLEFT", 4, -(index - 1) * 23)
        button:SetPoint("RIGHT", content, "RIGHT", -4, 0)
        button.caption:SetText(descriptor.text)
        local color = descriptor.color or PARCHMENT
        button.caption:SetTextColor(color[1], color[2], color[3])
        button:SetScript("OnClick", function()
            if descriptor.kind == "month" then
                UI.selectedMonthKey = descriptor.key
                UI.expandedMonths[descriptor.key] = not IsExpanded(UI.expandedMonths, descriptor.key)
            elseif descriptor.kind == "day" then
                UI.selectedDayKey = descriptor.key
                UI.expandedDays[descriptor.key] = not IsExpanded(UI.expandedDays, descriptor.key)
            elseif descriptor.kind == "movement" then
                UI.expandedMovements[descriptor.key] = not IsExpanded(UI.expandedMovements, descriptor.key)
            else return end
            UI.offset = 0
            UI.Render()
        end)
        button:Show()
    end
    for index = #rows + 1, #UI.rows do UI.rows[index]:Hide() end
    content:SetHeight(math.max(1, #rows * 23))
    if UI.scroll and UI.scroll.SetVerticalScroll then UI.scroll:SetVerticalScroll(0) end
end

function UI.Render()
    if not UI.window or not UI.window:IsShown() then return end
    local character, guid = SelectedCharacter()
    local identityLabel = character and (character.identity.name or "Unknown") or "No character"
    UI.characterCaption:SetText(identityLabel)
    UI.walletCaption:SetText("Wallet " .. Addon.FormatCoins(character and character.lastCopper))
    SetButtonText(UI.periodButton, "Period: " .. UI.period)
    UI.expandAllButton:SetShown(UI.page == "LEDGER")
    UI.expandMonthButton:SetShown(UI.page == "LEDGER")
    UI.expandDayButton:SetShown(UI.page == "LEDGER")
    UI.collapseButton:SetShown(UI.page == "LEDGER")
    UI.previousButton:SetShown(UI.page == "LEDGER")
    UI.nextButton:SetShown(UI.page == "LEDGER")
    UI.periodButton:SetShown(UI.page == "OVERVIEW")
    local rows, total
    if UI.page == "LEDGER" then
        rows, total = LedgerRows(character)
        UI.pageCaption:SetText("The Ledger  |  rows " .. tostring(total == 0 and 0 or UI.offset + 1)
            .. "-" .. tostring(math.min(UI.offset + #rows, total)) .. " of " .. tostring(total))
    else
        rows = OverviewRows(character, guid)
        total = #rows
        UI.pageCaption:SetText("Financial Overview - since tracking began")
    end
    RenderRowWidgets(rows)
    UI.statusCaption:SetText("Capture: " .. Addon.runtime.captureStatus
        .. "  |  Stored movements: " .. tostring(character and #character.movements or 0)
        .. "  |  FOREVER FIELD NOT TESTED")
end

function UI.RefreshIfVisible()
    if UI.window and UI.window:IsShown() then UI.Render() end
end

local function CycleCharacter(direction)
    local characters = Addon.Persistence.ListCharacters()
    if #characters == 0 then return end
    local currentIndex = 1
    for index, entry in ipairs(characters) do
        if entry.guid == (UI.selectedGuid or Addon.runtime.currentGuid) then currentIndex = index break end
    end
    local nextIndex = ((currentIndex - 1 + direction) % #characters) + 1
    UI.selectedGuid = characters[nextIndex].guid
    ResetExpansion()
    UI.Render()
end

function UI.Open(optionalPage)
    if not UI.window then
        if type(CreateFrame) ~= "function" or not UIParent then return false, "UI_UNAVAILABLE" end
        local frame = CreateFrame("Frame", "GoblinomiconForeverWindow", UIParent)
        frame:SetSize(790, 530)
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        frame:SetFrameStrata("DIALOG")
        frame:SetMovable(true)
        frame:EnableMouse(true)
        frame:RegisterForDrag("LeftButton")
        frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
        frame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
        local background = frame:CreateTexture(nil, "BACKGROUND")
        background:SetAllPoints()
        background:SetColorTexture(0.13, 0.10, 0.06, 0.97)
        local parchment = frame:CreateTexture(nil, "BORDER")
        parchment:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -74)
        parchment:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -12, 34)
        parchment:SetColorTexture(0.20, 0.16, 0.09, 0.95)
        local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        title:SetPoint("TOPLEFT", frame, "TOPLEFT", 18, -13)
        title:SetText("GOBLINOMICON  |  FOREVER")
        local close = CreateButton(frame, "X", 30, 24)
        close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -10, -10)
        close:SetScript("OnClick", function() frame:Hide() end)
        local charPrevious = CreateButton(frame, "<", 24, 22)
        charPrevious:SetPoint("TOPLEFT", frame, "TOPLEFT", 18, -43)
        charPrevious:SetScript("OnClick", function() CycleCharacter(-1) end)
        UI.characterCaption = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        UI.characterCaption:SetPoint("LEFT", charPrevious, "RIGHT", 6, 0)
        UI.characterCaption:SetWidth(140)
        local charNext = CreateButton(frame, ">", 24, 22)
        charNext:SetPoint("LEFT", UI.characterCaption, "RIGHT", 6, 0)
        charNext:SetScript("OnClick", function() CycleCharacter(1) end)
        UI.walletCaption = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        UI.walletCaption:SetPoint("LEFT", charNext, "RIGHT", 18, 0)
        UI.walletCaption:SetWidth(260)
        UI.overviewButton = CreateButton(frame, "OVERVIEW", 115, 25)
        UI.overviewButton:SetPoint("TOPLEFT", frame, "TOPLEFT", 18, -80)
        UI.overviewButton:SetScript("OnClick", function() UI.page = "OVERVIEW" UI.Render() end)
        UI.ledgerButton = CreateButton(frame, "THE LEDGER", 115, 25)
        UI.ledgerButton:SetPoint("LEFT", UI.overviewButton, "RIGHT", 8, 0)
        UI.ledgerButton:SetScript("OnClick", function() UI.page = "LEDGER" ResetExpansion() UI.Render() end)
        UI.periodButton = CreateButton(frame, "Period: LIFETIME", 145, 24)
        UI.periodButton:SetPoint("LEFT", UI.ledgerButton, "RIGHT", 16, 0)
        UI.periodButton:SetScript("OnClick", function()
            UI.period = UI.period == "LIFETIME" and "SESSION" or "LIFETIME"
            UI.Render()
        end)
        UI.expandAllButton = CreateButton(frame, "Expand All", 92, 24)
        UI.expandAllButton:SetPoint("LEFT", UI.ledgerButton, "RIGHT", 8, 0)
        UI.expandAllButton:SetScript("OnClick", function()
            UI.expandAll = true
            UI.expandedMonths = {} UI.expandedDays = {} UI.expandedMovements = {}
            UI.offset = 0 UI.Render()
        end)
        UI.expandMonthButton = CreateButton(frame, "Month", 68, 24)
        UI.expandMonthButton:SetPoint("LEFT", UI.expandAllButton, "RIGHT", 4, 0)
        UI.expandMonthButton:SetScript("OnClick", function()
            local character = SelectedCharacter()
            if character then
                local index = Addon.Ledger.MonthIndex(character)
                local monthKey = UI.selectedMonthKey or index.monthOrder[1]
                if index.months[monthKey] then UI.expandedMonths[monthKey] = true end
            end
            UI.offset = 0 UI.Render()
        end)
        UI.expandDayButton = CreateButton(frame, "Day", 55, 24)
        UI.expandDayButton:SetPoint("LEFT", UI.expandMonthButton, "RIGHT", 4, 0)
        UI.expandDayButton:SetScript("OnClick", function()
            local character = SelectedCharacter()
            if character then
                local index = Addon.Ledger.MonthIndex(character)
                local monthKey = UI.selectedMonthKey or index.monthOrder[1]
                if index.months[monthKey] then
                    UI.expandedMonths[monthKey] = true
                    local dayKey = UI.selectedDayKey or index.months[monthKey].dayOrder[1]
                    if index.months[monthKey].days[dayKey] then UI.expandedDays[dayKey] = true end
                end
            end
            UI.offset = 0 UI.Render()
        end)
        UI.collapseButton = CreateButton(frame, "Collapse All", 105, 24)
        UI.collapseButton:SetPoint("LEFT", UI.expandDayButton, "RIGHT", 4, 0)
        UI.collapseButton:SetScript("OnClick", function()
            UI.expandAll = false UI.expandedMonths = {} UI.expandedDays = {}
            UI.expandedMovements = {} UI.offset = 0 UI.Render()
        end)
        UI.pageCaption = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        UI.pageCaption:SetPoint("TOPLEFT", frame, "TOPLEFT", 20, -114)
        UI.pageCaption:SetWidth(700)
        UI.pageCaption:SetJustifyH("LEFT")
        UI.scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
        UI.scroll:SetPoint("TOPLEFT", frame, "TOPLEFT", 20, -139)
        UI.scroll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -40, 73)
        UI.scrollContent = CreateFrame("Frame", nil, UI.scroll)
        UI.scrollContent:SetWidth(720)
        UI.scrollContent:SetHeight(1)
        UI.scroll:SetScrollChild(UI.scrollContent)
        UI.previousButton = CreateButton(frame, "Previous", 88, 24)
        UI.previousButton:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 20, 42)
        UI.previousButton:SetScript("OnClick", function()
            UI.offset = math.max(0, UI.offset - 50) UI.Render()
        end)
        UI.nextButton = CreateButton(frame, "Next", 88, 24)
        UI.nextButton:SetPoint("LEFT", UI.previousButton, "RIGHT", 8, 0)
        UI.nextButton:SetScript("OnClick", function()
            local character = SelectedCharacter()
            local _, total = LedgerRows(character)
            if UI.offset + 50 < total then UI.offset = UI.offset + 50 end
            UI.Render()
        end)
        UI.statusCaption = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        UI.statusCaption:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 20, 17)
        UI.statusCaption:SetWidth(740)
        UI.statusCaption:SetJustifyH("LEFT")
        UI.window = frame
    end
    if optionalPage == "OVERVIEW" or optionalPage == "LEDGER" then UI.page = optionalPage end
    UI.selectedGuid = UI.selectedGuid or Addon.runtime.currentGuid
    if UI.page == "LEDGER" then ResetExpansion() end
    UI.window:Show()
    UI.Render()
    return true
end

function UI.Toggle()
    if UI.window and UI.window:IsShown() then UI.window:Hide() return true end
    return UI.Open()
end
