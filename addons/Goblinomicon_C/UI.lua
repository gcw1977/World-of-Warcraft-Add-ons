-- Goblinomicon Classic: anchored parchment accounting interface.
-- Presentation-only module. No ledger mutation, synthetic income, or data migration.
local addonName, addon = ...
local state = {
    page = "OVERVIEW", period = "LIFETIME", characterKey = nil,
    rowCount = 5, pageNumber = 1, overviewPageNumber = 1,
    expandedMonths = {}, expandedDays = {}, selectedMonth = nil,
    selectedDay = nil, initialExpansionSet = false, expandAll = false,
    expandScope = "ALL"
}
local function Paint(texture, red, green, blue, alpha)
    if texture.SetColorTexture then
        texture:SetColorTexture(red, green, blue, alpha)
    else
        texture:SetTexture(red, green, blue, alpha)
    end
end
local function Text(parent, font, width, height, x, y)
    local label = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
    label:SetSize(width, height)
    label:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    label:SetJustifyH("LEFT")
    label:SetJustifyV("MIDDLE")
    return label
end
local function Button(parent, caption, x, y, width, callback)
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(width, 27)
    button:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    local fill = button:CreateTexture(nil, "BACKGROUND")
    fill:SetAllPoints(button)
    Paint(fill, 0.29, 0.21, 0.115, 0.98)
    local edge = button:CreateTexture(nil, "BORDER")
    edge:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", 0, 0)
    edge:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 0, 0)
    edge:SetHeight(2)
    Paint(edge, 0.66, 0.48, 0.22, 0.95)
    button.caption = Text(button, "GameFontNormalSmall", width - 8, 22, 4, -2)
    button.caption:SetJustifyH("CENTER")
    button.caption:SetText(caption)
    button:SetScript("OnClick", callback)
    return button
end
local function SelectedCharacter()
    if not addon.accountData or not addon.accountData.characters then return nil end
    return addon.accountData.characters[state.characterKey or addon.characterKey]
end
local function CharacterKeys()
    local keys = {}
    if not addon.accountData or not addon.accountData.characters then return keys end
    for key in pairs(addon.accountData.characters) do keys[#keys + 1] = key end
    table.sort(keys)
    return keys
end
local function ChangeCharacter(direction)
    local keys = CharacterKeys()
    if #keys == 0 then return end
    local current = state.characterKey or addon.characterKey
    local position = 1
    for index, key in ipairs(keys) do
        if key == current then position = index; break end
    end
    state.characterKey = keys[((position - 1 + direction) % #keys) + 1]
    state.pageNumber = 1
    state.overviewPageNumber = 1
    state.expandedMonths = {}
    state.expandedDays = {}
    state.expandAll = false
    state.initialExpansionSet = false
    state.selectedMonth = nil
    state.selectedDay = nil
    addon.RefreshVisibleUI()
end
local function SetRow(row, record, clickHandler)
    if not record then
        row:Hide()
        row:SetScript("OnClick", nil)
        return
    end
    row:Show()
    row.description:SetText(record.description or "")
    row.amount:SetText(record.amount or "")
    row.balance:SetText(record.balance or "")
    row.amount:SetTextColor(record.negative and 0.95 or 0.58,
        record.negative and 0.44 or 0.88, record.negative and 0.42 or 0.54)
    row:SetScript("OnClick", clickHandler)
end
local function MoneyPanel(frame, title, x, width)
    local panel = CreateFrame("Frame", nil, frame)
    panel:SetSize(width, 56)
    panel:SetPoint("TOPLEFT", frame, "TOPLEFT", x, -95)
    local background = panel:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints(panel)
    Paint(background, 0.27, 0.20, 0.11, 0.95)
    local caption = Text(panel, "GameFontNormalSmall", width - 12, 17, 6, -3)
    caption:SetText(title)
    local value = Text(panel, "GameFontHighlightSmall", width - 12, 23, 6, -26)
    return caption, value
end
local function RefreshWallet(characterData)
    if not characterData then return end
    local isCurrent = characterData == addon.characterData
    local balance = characterData.lastCommittedBalanceCopper
    if isCurrent and type(addon.ReadWallet) == "function" then
        balance = addon.ReadWallet()
    end
    local firstEpoch = characterData.epochs and characterData.epochs[1]
    state.walletTitle:SetText(isCurrent and "CURRENT WALLET" or "LAST SEEN WALLET")
    state.walletValue:SetText(type(balance) == "number" and
        string.gsub(addon.FormatCopper(balance), "^%+", "") or "Waiting for wallet")
    local corrected = characterData.accountingCorrection
    local openingCopper = corrected and corrected.confirmedOpeningCopper or
        (firstEpoch and firstEpoch.openingBalanceCopper)
    state.openingValue:SetText(type(openingCopper) == "number" and
        string.gsub(addon.FormatCopper(openingCopper), "^%+", "")
        or "Not established")
    local gaps = characterData.gapCount or 0
    state.coverage:SetText(gaps > 0 and ("Coverage gaps: " .. gaps) or "Journal active")
    if isCurrent and type(balance) == "number" and
        balance ~= characterData.lastCommittedBalanceCopper then
        state.coverage:SetText("Wallet differs from checkpoint; review baseline")
    end
end
local function RefreshOverview(characterData)
    local sessionOnly = state.period == "SESSION"
    local totals = addon.GetTotals(characterData, sessionOnly)
    if not totals then
        state.subtitle:SetText("Session unavailable for inactive character")
        for _, row in ipairs(state.rows) do SetRow(row, nil) end
        return
    end
    state.incomeValue:SetText(addon.FormatCopper(totals.income))
    state.expensesValue:SetText(addon.FormatCopper(-totals.expenses))
    state.netValue:SetText(addon.FormatCopper(totals.net))
    state.subtitle:SetText(characterData.accountingCorrection and
        "Owner-corrected opening; raw ledger retained" or
        "Recorded transactions by category")
    local records = {}
    for category, copper in pairs(totals.incomeCategories) do
        records[#records + 1] = {
            description = category, amount = addon.FormatCopper(copper)
        }
    end
    for category, copper in pairs(totals.expenseCategories) do
        records[#records + 1] = {
            description = category, amount = addon.FormatCopper(-copper), negative = true
        }
    end
    table.sort(records, function(left, right) return left.description < right.description end)
    if #records == 0 then
        records[1] = {description = "No observed wallet movements yet"}
    end
    local first = (state.overviewPageNumber - 1) * state.rowCount + 1
    for index, row in ipairs(state.rows) do
        SetRow(row, records[first + index - 1])
    end
    state.totalPages = math.max(1, math.ceil(#records / state.rowCount))
    state.footer:SetText("Overview " .. state.overviewPageNumber .. "/" ..
        state.totalPages .. "    Opening balance is not income")
end
-- Build only the current page. Historical rows never become individual frames.
local function LedgerRows(characterData, index, firstOrdinal)
    local result, ordinal = {}, 0
    local function Include(record, kind, key, parentKey, transactionIndex)
        ordinal = ordinal + 1
        if ordinal >= firstOrdinal and ordinal < firstOrdinal + state.rowCount then
            result[#result + 1] = {
                record = record, kind = kind, key = key, parentKey = parentKey,
                transactionIndex = transactionIndex
            }
        end
    end
    for _, monthKey in ipairs(index.monthOrder) do
        local month = index.months[monthKey]
        local monthOpen = state.expandAll or state.expandedMonths[monthKey]
        Include({
            description = (monthOpen and "[-] " or "[+] ") .. monthKey,
            amount = addon.FormatCopper(month.income - month.expenses)
        }, "MONTH", monthKey)
        if monthOpen then
            for _, dayKey in ipairs(month.dayOrder) do
                local day = month.days[dayKey]
                local dayOpen = state.expandAll or state.expandedDays[dayKey]
                Include({
                    description = (dayOpen and "    [-] " or "    [+] ") .. dayKey,
                    amount = addon.FormatCopper(day.income - day.expenses)
                }, "DAY", dayKey, monthKey)
                if dayOpen then
                    local count = #day.transactionIndices
                    if ordinal + count < firstOrdinal or
                        ordinal >= firstOrdinal + state.rowCount then
                        ordinal = ordinal + count
                    else
                        for reverseIndex = count, 1, -1 do
                            local transactionIndex = day.transactionIndices[reverseIndex]
                            local transaction = characterData.transactions[transactionIndex]
                            Include({
                                description = "    #" .. tostring(transaction.sequence) ..
                                    "  " .. tostring(transaction.category or "Unclassified"),
                                amount = addon.FormatCopper(
                                    addon.EffectiveTransactionDelta(characterData, transaction)),
                                balance = addon.FormatCopper(transaction.afterCopper),
                                negative = addon.EffectiveTransactionDelta(characterData, transaction) < 0
                            }, "TRANSACTION", nil, nil, transactionIndex)
                        end
                    end
                end
            end
        end
    end
    return result, ordinal
end
local function RefreshLedger(characterData)
    local selectedKey = state.characterKey or addon.characterKey
    local index = addon.GetLedgerIndex(selectedKey)
    if not index then
        for _, row in ipairs(state.rows) do SetRow(row, nil) end
        return
    end
    if not state.initialExpansionSet and #index.monthOrder > 0 then
        local monthKey = index.monthOrder[1]
        state.expandedMonths[monthKey] = true
        local dayKey = index.months[monthKey].dayOrder[1]
        if dayKey then state.expandedDays[dayKey] = true end
        state.initialExpansionSet = true
    end
    state.subtitle:SetText(tostring(#characterData.transactions) .. " recorded transactions")
    state.incomeValue:SetText("—")
    state.expensesValue:SetText("—")
    state.netValue:SetText("—")
    local first = (state.pageNumber - 1) * state.rowCount + 1
    local records, total = LedgerRows(characterData, index, first)
    state.totalPages = math.max(1, math.ceil(total / state.rowCount))
    if state.pageNumber > state.totalPages then
        state.pageNumber = state.totalPages
        return RefreshLedger(characterData)
    end
    for rowIndex, row in ipairs(state.rows) do
        local item = records[rowIndex]
        if not item then
            SetRow(row, nil)
        else
            SetRow(row, item.record, function()
                if item.kind == "MONTH" then
                    state.selectedMonth = item.key
                    state.expandAll = false
                    state.expandedMonths[item.key] = not state.expandedMonths[item.key]
                elseif item.kind == "DAY" then
                    state.selectedDay = item.key
                    state.selectedMonth = item.parentKey
                    state.expandAll = false
                    state.expandedMonths[item.parentKey] = true
                    state.expandedDays[item.key] = not state.expandedDays[item.key]
                else
                    local transaction = characterData.transactions[item.transactionIndex]
                    state.detail:SetText("Entry #" .. transaction.sequence ..
                        "   " .. tostring(transaction.category or "Unclassified") ..
                        "   Before " .. addon.FormatCopper(transaction.beforeCopper) ..
                        "   After " .. addon.FormatCopper(transaction.afterCopper))
                end
                addon.RefreshVisibleUI()
            end)
        end
    end
    state.footer:SetText("Ledger " .. state.pageNumber .. "/" .. state.totalPages ..
        "    " .. total .. " logical rows    Read-only")
end
function addon.RefreshVisibleUI()
    if not state.frame or not state.frame:IsShown() then return end
    local characterData = SelectedCharacter()
    state.characterLabel:SetText(characterData and
        ((characterData.name or "Unknown") .. " - " .. (characterData.realm or "?"))
        or "Character unavailable")
    state.periodButton.caption:SetText("Period: " .. state.period)
    state.scopeButton.caption:SetText("Expand: " .. state.expandScope)
    state.periodButton:SetShown(state.page == "OVERVIEW")
    state.scopeButton:SetShown(state.page == "LEDGER")
    state.expandButton:SetShown(state.page == "LEDGER")
    state.collapseButton:SetShown(state.page == "LEDGER")
    state.pageTitle:SetText(state.page)
    state.baselineButton:SetShown(state.page == "OVERVIEW" and
        (state.characterKey or addon.characterKey) == addon.characterKey and
        SelectedCharacter() ~= nil and
        #SelectedCharacter().transactions == 0 and
        #SelectedCharacter().epochs == 1 and
        SelectedCharacter().epochs[1].reason == "INITIAL_BASELINE")
    if not characterData then
        state.subtitle:SetText("Waiting for valid character data")
        for _, row in ipairs(state.rows) do SetRow(row, nil) end
        return
    end
    RefreshWallet(characterData)
    if state.page == "OVERVIEW" then RefreshOverview(characterData)
    else RefreshLedger(characterData) end
end
local function ChangePage(page)
    state.page = page
    state.detail:SetText("")
    state.baselineConfirmationArmed = false
    if state.baselineButton then
        state.baselineButton.caption:SetText("CONFIRM OPENING BALANCE")
    end
    addon.RefreshVisibleUI()
end
local function ExpandSelection()
    local index = addon.GetLedgerIndex(state.characterKey or addon.characterKey)
    if not index then return end
    if state.expandScope == "ALL" then
        state.expandAll = true
    else
        local monthKey = state.selectedMonth or index.monthOrder[1]
        if monthKey then
            state.expandAll = false
            state.expandedMonths[monthKey] = true
            if state.expandScope == "DAY" then
                local month = index.months[monthKey]
                local dayKey = state.selectedDay or (month and month.dayOrder[1])
                if dayKey then state.expandedDays[dayKey] = true end
            end
        end
    end
    state.pageNumber = 1
    addon.RefreshVisibleUI()
end
function addon.OpenWindow(requestedPage)
    if not state.frame then
        if type(CreateFrame) ~= "function" or not UIParent then
            addon.NoteError("UI_API_UNAVAILABLE")
            return false
        end
        local frame = CreateFrame("Frame", "GoblinomiconClassicDashboard", UIParent)
        frame:SetSize(700, 378)
        frame:SetFrameStrata("DIALOG")
        if frame.SetClampedToScreen then frame:SetClampedToScreen(true) end
        frame:SetMovable(true)
        frame:EnableMouse(true)
        frame:RegisterForDrag("LeftButton")
        frame:SetScript("OnDragStart", frame.StartMoving)
        frame:SetScript("OnDragStop", function(self)
            self:StopMovingOrSizing()
            local centerX, centerY = self:GetCenter()
            local parentX, parentY = UIParent:GetCenter()
            if addon.accountData and centerX and parentX then
                addon.accountData.displaySettings = addon.accountData.displaySettings or {}
                addon.accountData.displaySettings.windowGeometry =
                    {x = centerX - parentX, y = centerY - parentY}
            end
        end)
        local background = frame:CreateTexture(nil, "BACKGROUND")
        background:SetAllPoints(frame)
        Paint(background, 0.15, 0.115, 0.075, 0.985)
        local topTrim = frame:CreateTexture(nil, "BORDER")
        topTrim:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
        topTrim:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
        topTrim:SetHeight(5)
        Paint(topTrim, 0.76, 0.54, 0.24, 1)
        local storedGeometry = addon.accountData and addon.accountData.displaySettings
            and addon.accountData.displaySettings.windowGeometry
        if type(storedGeometry) == "table" and type(storedGeometry.x) == "number"
            and type(storedGeometry.y) == "number" then
            frame:SetPoint("CENTER", UIParent, "CENTER",
                math.max(-400, math.min(400, storedGeometry.x)),
                math.max(-250, math.min(250, storedGeometry.y)))
        else
            frame:SetPoint("CENTER", UIParent, "CENTER")
        end
        state.frame = frame
        Text(frame, "GameFontNormalLarge", 270, 29, 16, -12):SetText("GOBLINOMICON")
        Button(frame, "X", 661, -14, 26, function() frame:Hide() end)
        Button(frame, "<", 300, -15, 27, function() ChangeCharacter(-1) end)
        state.characterLabel = Text(frame, "GameFontNormalSmall", 250, 26, 333, -14)
        Button(frame, ">", 590, -15, 27, function() ChangeCharacter(1) end)
        Button(frame, "OVERVIEW", 16, -54, 118, function() ChangePage("OVERVIEW") end)
        Button(frame, "LEDGER", 140, -54, 118, function() ChangePage("LEDGER") end)
        state.periodButton = Button(frame, "Period: LIFETIME", 267, -54, 139,
            function()
                state.period = state.period == "LIFETIME" and "SESSION" or "LIFETIME"
                state.overviewPageNumber = 1
                addon.RefreshVisibleUI()
            end)
        state.scopeButton = Button(frame, "Expand: ALL", 270, -54, 114, function()
            if state.expandScope == "ALL" then state.expandScope = "MONTH"
            elseif state.expandScope == "MONTH" then state.expandScope = "DAY"
            else state.expandScope = "ALL" end
            addon.RefreshVisibleUI()
        end)
        state.expandButton = Button(frame, "Expand", 391, -54, 93, ExpandSelection)
        state.collapseButton = Button(frame, "Collapse All", 491, -54, 126, function()
            state.expandAll = false
            state.expandedMonths = {}
            state.expandedDays = {}
            state.initialExpansionSet = true
            state.pageNumber = 1
            addon.RefreshVisibleUI()
        end)
        state.baselineButton = Button(frame, "CONFIRM OPENING BALANCE", 16, -308, 226,
            function()
                if not state.baselineConfirmationArmed then
                    state.baselineConfirmationArmed = true
                    state.baselineButton.caption:SetText("CONFIRM: USE CURRENT WALLET?")
                    return
                end
                state.baselineConfirmationArmed = false
                state.baselineButton.caption:SetText("CONFIRM OPENING BALANCE")
                local success, message = addon.ConfirmOpeningBalance()
                state.detail:SetText(message or (success and "Baseline updated" or "Unable to update"))
                addon.RefreshVisibleUI()
            end)
        state.walletTitle, state.walletValue = MoneyPanel(frame, "CURRENT WALLET", 14, 164)
        local openingTitle
        openingTitle, state.openingValue = MoneyPanel(frame, "OPENING BALANCE", 182, 164)
        local incomeTitle
        incomeTitle, state.incomeValue = MoneyPanel(frame, "INCOME", 350, 105)
        local expenseTitle
        expenseTitle, state.expensesValue = MoneyPanel(frame, "EXPENSES", 459, 105)
        local netTitle
        netTitle, state.netValue = MoneyPanel(frame, "NET CHANGE", 568, 118)
        state.pageTitle = Text(frame, "GameFontNormal", 125, 23, 16, -159)
        state.subtitle = Text(frame, "GameFontHighlightSmall", 515, 23, 145, -159)
        Text(frame, "GameFontNormalSmall", 390, 19, 21, -183):SetText("ENTRY / CATEGORY")
        Text(frame, "GameFontNormalSmall", 135, 19, 427, -183):SetText("AMOUNT / NET")
        Text(frame, "GameFontNormalSmall", 122, 19, 565, -183):SetText("BALANCE")
        state.rows = {}
        for rowNumber = 1, state.rowCount do
            local row = CreateFrame("Button", nil, frame)
            row:SetSize(672, 18)
            row:SetPoint("TOPLEFT", frame, "TOPLEFT", 14, -204 - (rowNumber - 1) * 19)
            local tint = row:CreateTexture(nil, "BACKGROUND")
            tint:SetAllPoints(row)
            if rowNumber % 2 == 0 then Paint(tint, 0.24, 0.18, 0.11, 0.92)
            else Paint(tint, 0.20, 0.15, 0.095, 0.82) end
            row.description = Text(row, "GameFontHighlightSmall", 401, 18, 6, 0)
            row.amount = Text(row, "GameFontHighlightSmall", 132, 18, 412, 0)
            row.amount:SetJustifyH("RIGHT")
            row.balance = Text(row, "GameFontHighlightSmall", 118, 18, 549, 0)
            row.balance:SetJustifyH("RIGHT")
            state.rows[#state.rows + 1] = row
        end
        state.detail = Text(frame, "GameFontHighlightSmall", 662, 18, 17, -337)
        state.coverage = Text(frame, "GameFontNormalSmall", 355, 17, 16, -357)
        state.footer = Text(frame, "GameFontNormalSmall", 230, 17, 382, -357)
        Button(frame, "<", 619, -350, 28, function()
            if state.page == "LEDGER" then
                state.pageNumber = math.max(1, state.pageNumber - 1)
            else
                state.overviewPageNumber = math.max(1, state.overviewPageNumber - 1)
            end
            addon.RefreshVisibleUI()
        end)
        Button(frame, ">", 653, -350, 28, function()
            if state.page == "LEDGER" then
                state.pageNumber = math.min(state.totalPages or 1, state.pageNumber + 1)
            else
                state.overviewPageNumber = math.min(state.totalPages or 1,
                    state.overviewPageNumber + 1)
            end
            addon.RefreshVisibleUI()
        end)
    end
    state.characterKey = state.characterKey or addon.characterKey
    if requestedPage == "LEDGER" or requestedPage == "OVERVIEW" then
        state.page = requestedPage
    end
    state.frame:Show()
    addon.RefreshVisibleUI()
    return true
end
