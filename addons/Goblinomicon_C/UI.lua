-- Goblinomicon Classic - two-page parchment dashboard with fixed reusable rows.
-- This UI never changes the wallet or edits/deletes historical transactions.
local addonName, addon = ...
local dashboard = {page = "OVERVIEW", period = "LIFETIME", characterKey = nil,
    pageNumber = 1, overviewPageNumber = 1, expandScope = "ALL",
    expandedAll = false, expandedMonths = {}, expandedDays = {},
    selectedMonth = nil, selectedDay = nil, rowCount = 20}
local parchment = {0.72, 0.62, 0.40, 0.98}
local brass = {0.75, 0.56, 0.21, 1}

local function MakeText(parent, fontObject, width, height, anchor, relative, x, y)
    local label = parent:CreateFontString(nil, "OVERLAY", fontObject or "GameFontNormal")
    label:SetSize(width, height)
    label:SetPoint(anchor, relative or parent, anchor, x or 0, y or 0)
    label:SetJustifyH("LEFT")
    label:SetJustifyV("MIDDLE")
    return label
end

local function MakeButton(parent, caption, width, height, x, y, callback)
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(width, height)
    button:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    local texture = button:CreateTexture(nil, "BACKGROUND")
    texture:SetAllPoints(button)
    texture:SetColorTexture(0.25, 0.19, 0.09, 0.95)
    local label = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetAllPoints(button)
    label:SetText(caption)
    button.caption = label
    button:SetScript("OnClick", callback)
    return button
end

local function GetSelectedCharacter()
    if not addon.accountData then return nil end
    local selectedKey = dashboard.characterKey or addon.characterKey
    return selectedKey and addon.accountData.characters[selectedKey] or nil
end

local function GetSortedCharacterKeys()
    local keys = {}
    if not addon.accountData then return keys end
    for characterKey in pairs(addon.accountData.characters) do
        table.insert(keys, characterKey)
    end
    table.sort(keys, function(left, right)
        local first = addon.accountData.characters[left]
        local second = addon.accountData.characters[right]
        local firstLabel = tostring(first.name or left) .. tostring(first.realm or "")
        local secondLabel = tostring(second.name or right) .. tostring(second.realm or "")
        return firstLabel < secondLabel
    end)
    return keys
end

local function ChangeCharacter(direction)
    local keys = GetSortedCharacterKeys()
    if #keys == 0 then return end
    local selectedKey = dashboard.characterKey or addon.characterKey
    local currentIndex = 1
    for index, key in ipairs(keys) do
        if key == selectedKey then currentIndex = index; break end
    end
    local nextIndex = ((currentIndex - 1 + direction) % #keys) + 1
    dashboard.characterKey = keys[nextIndex]
    dashboard.pageNumber = 1
    dashboard.overviewPageNumber = 1
    dashboard.expandedAll = false
    dashboard.expandedMonths = {}
    dashboard.expandedDays = {}
    dashboard.selectedMonth = nil
    dashboard.selectedDay = nil
    addon.RefreshVisibleUI()
end

local function SetRow(row, text, onClick)
    row.caption:SetText(text or "")
    row:SetScript("OnClick", onClick)
    if text then row:Show() else row:Hide() end
end

local function RefreshOverview()
    local characterData = GetSelectedCharacter()
    if not characterData then
        dashboard.summary:SetText("Waiting for a valid character GUID and wallet")
        for _, row in ipairs(dashboard.rows) do SetRow(row, nil) end
        return
    end
    local sessionOnly = dashboard.period == "SESSION"
    local totals = addon.GetTotals(characterData, sessionOnly)
    if not totals then
        dashboard.summary:SetText("Session totals unavailable for an inactive character")
        for _, row in ipairs(dashboard.rows) do SetRow(row, nil) end
        return
    end
    local walletLabel = characterData == addon.characterData and "Current checkpoint" or "Last seen"
    dashboard.summary:SetText(string.format(
        "%s: %s    Income: %s    Expenses: %s    Net: %s",
        walletLabel, addon.FormatCopper(characterData.lastCommittedBalanceCopper),
        addon.FormatCopper(totals.income), addon.FormatCopper(-totals.expenses),
        addon.FormatCopper(totals.net)))
    local incomeCategories, expenseCategories = {}, {}
    for category, copper in pairs(totals.categories) do
        local categoryEntry = {name = category, copper = copper}
        if string.find(category, "Expense", 1, true) or
            category == "Vendor Purchase" or category == "Repair" or
            category == "Travel" or category == "Training" then
            table.insert(expenseCategories, categoryEntry)
        else
            table.insert(incomeCategories, categoryEntry)
        end
    end
    table.sort(incomeCategories, function(a,b) return a.name < b.name end)
    table.sort(expenseCategories, function(a,b) return a.name < b.name end)
    local overviewLines = {"INCOME - all recorded categories"}
    for _, entry in ipairs(incomeCategories) do
        table.insert(overviewLines, entry.name .. "    " .. addon.FormatCopper(entry.copper))
    end
    table.insert(overviewLines, "EXPENSES - all recorded categories")
    for _, entry in ipairs(expenseCategories) do
        table.insert(overviewLines, entry.name .. "    " .. addon.FormatCopper(-entry.copper))
    end
    if #incomeCategories + #expenseCategories == 0 then
        table.insert(overviewLines, "No observed wallet movements yet")
    end
    local startIndex = (dashboard.overviewPageNumber - 1) * dashboard.rowCount + 1
    for rowIndex, row in ipairs(dashboard.rows) do
        SetRow(row, overviewLines[startIndex + rowIndex - 1])
    end
    dashboard.totalPages = math.max(1, math.ceil(#overviewLines / dashboard.rowCount))
    dashboard.footer:SetText("Overview " .. dashboard.overviewPageNumber .. "/" ..
        dashboard.totalPages .. "  |  Tracked since installation; baseline is not income")
end

-- Generate only the visible ledger page. Expanded days are skipped by count
-- rather than allocating one UI widget or temporary row for each transaction.
local function BuildLedgerPage(characterData, index, firstOrdinal, maxRows)
    local rows, ordinal = {}, 0
    local function AddRow(kind, key, parentKey, transactionIndex, label)
        ordinal = ordinal + 1
        if ordinal >= firstOrdinal and #rows < maxRows then
            table.insert(rows, {kind = kind, key = key, parentKey = parentKey,
                transactionIndex = transactionIndex, label = label})
        end
    end
    for _, monthKey in ipairs(index.monthOrder) do
        local month = index.months[monthKey]
        local monthOpen = dashboard.expandedAll or dashboard.expandedMonths[monthKey]
        AddRow("MONTH", monthKey, nil, nil,
            (monthOpen and "v " or "> ") .. monthKey ..
            "    +" .. addon.FormatCopper(month.income) ..
            "    " .. addon.FormatCopper(-month.expenses))
        if monthOpen then
            for _, dayKey in ipairs(month.dayOrder) do
                local day = month.days[dayKey]
                local dayOpen = dashboard.expandedAll or dashboard.expandedDays[dayKey]
                AddRow("DAY", dayKey, monthKey, nil,
                    "  " .. (dayOpen and "v " or "> ") .. dayKey ..
                    "    +" .. addon.FormatCopper(day.income) ..
                    "    " .. addon.FormatCopper(-day.expenses))
                if dayOpen then
                    local count = #day.transactionIndices
                    -- Skip entire unseen day blocks without visiting each entry.
                    if ordinal + count < firstOrdinal or #rows >= maxRows then
                        ordinal = ordinal + count
                    else
                        for reverseIndex = count, 1, -1 do
                            ordinal = ordinal + 1
                            if ordinal >= firstOrdinal and #rows < maxRows then
                                local transactionIndex = day.transactionIndices[reverseIndex]
                                local transaction = characterData.transactions[transactionIndex]
                                table.insert(rows, {kind = "TRANSACTION",
                                    transactionIndex = transactionIndex,
                                    label = string.format("    #%d  %s  %s  balance %s",
                                        transaction.sequence, transaction.category or "Unknown",
                                        addon.FormatCopper(transaction.deltaCopper),
                                        addon.FormatCopper(transaction.afterCopper))})
                            end
                        end
                    end
                end
            end
        end
    end
    return rows, ordinal
end

local function RefreshLedger()
    local characterData = GetSelectedCharacter()
    if not characterData then
        dashboard.summary:SetText("Waiting for character data")
        for _, row in ipairs(dashboard.rows) do SetRow(row, nil) end
        return
    end
    dashboard.summary:SetText(string.format("Ledger: %d permanent entries, %d coverage gaps",
        #characterData.transactions, characterData.gapCount or 0))
    local selectedKey = dashboard.characterKey or addon.characterKey
    local index = addon.GetLedgerIndex(selectedKey)
    if not index then return end
    if not dashboard.initialExpansionSet and #index.monthOrder > 0 then
        local latestMonth = index.monthOrder[1]
        dashboard.expandedMonths[latestMonth] = true
        local firstDay = index.months[latestMonth].dayOrder[1]
        if firstDay then dashboard.expandedDays[firstDay] = true end
        dashboard.initialExpansionSet = true
    end
    local firstOrdinal = (dashboard.pageNumber - 1) * dashboard.rowCount + 1
    local visibleRows, totalRows = BuildLedgerPage(characterData, index,
        firstOrdinal, dashboard.rowCount)
    dashboard.totalPages = math.max(1, math.ceil(totalRows / dashboard.rowCount))
    if dashboard.pageNumber > dashboard.totalPages then
        dashboard.pageNumber = dashboard.totalPages
        return RefreshLedger()
    end
    for rowIndex, row in ipairs(dashboard.rows) do
        local rowData = visibleRows[rowIndex]
        if not rowData then
            SetRow(row, nil)
        else
            SetRow(row, rowData.label, function()
                if rowData.kind == "MONTH" then
                    dashboard.selectedMonth = rowData.key
                    dashboard.expandedAll = false
                    dashboard.expandedMonths[rowData.key] =
                        not dashboard.expandedMonths[rowData.key]
                elseif rowData.kind == "DAY" then
                    dashboard.selectedDay = rowData.key
                    dashboard.selectedMonth = rowData.parentKey
                    dashboard.expandedAll = false
                    dashboard.expandedMonths[rowData.parentKey] = true
                    dashboard.expandedDays[rowData.key] =
                        not dashboard.expandedDays[rowData.key]
                else
                    local transaction = characterData.transactions[rowData.transactionIndex]
                    dashboard.detail:SetText(string.format(
                        "#%d | %s | %s | Before %s | After %s | Session %s | Epoch %d",
                        transaction.sequence, transaction.category,
                        transaction.confidence or "UNKNOWN",
                        addon.FormatCopper(transaction.beforeCopper),
                        addon.FormatCopper(transaction.afterCopper),
                        tostring(transaction.sessionId), transaction.epochId))
                end
                addon.RefreshVisibleUI()
            end)
        end
    end
    dashboard.footer:SetText("Ledger " .. dashboard.pageNumber .. "/" ..
        dashboard.totalPages .. " | " .. totalRows .. " visible logical rows | No records deleted")
end

function addon.RefreshVisibleUI()
    if not dashboard.frame or not dashboard.frame:IsShown() then return end
    local characterData = GetSelectedCharacter()
    dashboard.characterLabel:SetText(characterData and
        ((characterData.name or "Unknown") .. " - " .. (characterData.realm or "?")) or
        "Character unavailable")
    dashboard.periodButton.caption:SetText("Period: " .. dashboard.period)
    dashboard.scopeButton.caption:SetText("Expand: " .. dashboard.expandScope)
    dashboard.pageLabel:SetText(dashboard.page)
    if dashboard.page == "OVERVIEW" then RefreshOverview()
    else RefreshLedger() end
end

local function ChangePage(nextPage)
    dashboard.page = nextPage
    dashboard.pageNumber = 1
    dashboard.overviewPageNumber = 1
    dashboard.detail:SetText("")
    addon.RefreshVisibleUI()
end

local function ExpandSelection()
    if dashboard.expandScope == "ALL" then
        dashboard.expandedAll = true
    elseif dashboard.expandScope == "MONTH" then
        local index = addon.GetLedgerIndex(dashboard.characterKey or addon.characterKey)
        local monthKey = dashboard.selectedMonth or (index and index.monthOrder[1])
        if monthKey then
            dashboard.expandedAll = false
            dashboard.expandedMonths[monthKey] = true
        end
    else
        local index = addon.GetLedgerIndex(dashboard.characterKey or addon.characterKey)
        local monthKey = dashboard.selectedMonth or (index and index.monthOrder[1])
        local dayKey = dashboard.selectedDay or
            (monthKey and index.months[monthKey].dayOrder[1])
        if dayKey then
            dashboard.expandedAll = false
            dashboard.expandedMonths[monthKey] = true
            dashboard.expandedDays[dayKey] = true
        end
    end
    dashboard.pageNumber = 1
    addon.RefreshVisibleUI()
end

-- Lazy UI creation means a missing template/art error never blocks the observer.
function addon.OpenWindow(requestedPage)
    if not dashboard.frame then
        if type(CreateFrame) ~= "function" or not UIParent then
            addon.NoteError("UI_API_UNAVAILABLE")
            return false
        end
        local frame = CreateFrame("Frame", "GoblinomiconClassicDashboard", UIParent)
        frame:SetSize(760, 580)
        frame:SetClampedToScreen(true)
        frame:SetMovable(true)
        frame:EnableMouse(true)
        frame:RegisterForDrag("LeftButton")
        frame:SetScript("OnDragStart", frame.StartMoving)
        frame:SetScript("OnDragStop", function(self)
            self:StopMovingOrSizing()
            local centerX, centerY = self:GetCenter()
            local parentX, parentY = UIParent:GetCenter()
            if addon.accountData and centerX and parentX then
                addon.accountData.displaySettings =
                    addon.accountData.displaySettings or {}
                addon.accountData.displaySettings.windowGeometry =
                    {x = centerX - parentX, y = centerY - parentY}
            end
        end)
        local background = frame:CreateTexture(nil, "BACKGROUND")
        background:SetAllPoints(frame)
        background:SetColorTexture(unpack(parchment))
        local border = frame:CreateTexture(nil, "BORDER")
        border:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
        border:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
        border:SetHeight(5)
        border:SetColorTexture(unpack(brass))
        local geometry = addon.accountData and addon.accountData.displaySettings
            and addon.accountData.displaySettings.windowGeometry
        if type(geometry) == "table" and type(geometry.x) == "number"
            and type(geometry.y) == "number" then
            frame:SetPoint("CENTER", UIParent, "CENTER",
                math.max(-400, math.min(400, geometry.x)),
                math.max(-250, math.min(250, geometry.y)))
        else frame:SetPoint("CENTER") end
        frame:SetFrameStrata("DIALOG")
        dashboard.frame = frame
        local title = MakeText(frame, "GameFontNormalLarge", 270, 28,
            "TOPLEFT", frame, 15, -12)
        title:SetText("GOBLINOMICON - CLASSIC")
        MakeButton(frame, "X", 30, 25, 715, -12, function() frame:Hide() end)
        MakeButton(frame, "<", 26, 24, 320, -15, function() ChangeCharacter(-1) end)
        dashboard.characterLabel = MakeText(frame, "GameFontNormal", 260, 26,
            "TOPLEFT", frame, 355, -14)
        MakeButton(frame, ">", 26, 24, 625, -15, function() ChangeCharacter(1) end)
        MakeButton(frame, "OVERVIEW", 120, 28, 16, -54,
            function() ChangePage("OVERVIEW") end)
        MakeButton(frame, "LEDGER", 120, 28, 145, -54,
            function() ChangePage("LEDGER") end)
        dashboard.periodButton = MakeButton(frame, "Period: LIFETIME", 140, 28,
            280, -54, function()
                dashboard.period = dashboard.period == "LIFETIME" and "SESSION" or "LIFETIME"
                addon.RefreshVisibleUI()
            end)
        dashboard.scopeButton = MakeButton(frame, "Expand: ALL", 110, 28,
            430, -54, function()
                if dashboard.expandScope == "ALL" then dashboard.expandScope = "MONTH"
                elseif dashboard.expandScope == "MONTH" then dashboard.expandScope = "DAY"
                else dashboard.expandScope = "ALL" end
                addon.RefreshVisibleUI()
            end)
        MakeButton(frame, "Expand", 75, 28, 545, -54, ExpandSelection)
        MakeButton(frame, "Collapse All", 110, 28, 625, -54, function()
            dashboard.expandedAll = false
            dashboard.expandedMonths = {}
            dashboard.expandedDays = {}
            dashboard.initialExpansionSet = true
            dashboard.pageNumber = 1
            addon.RefreshVisibleUI()
        end)
        dashboard.pageLabel = MakeText(frame, "GameFontNormal", 160, 24,
            "TOPLEFT", frame, 16, -95)
        dashboard.summary = MakeText(frame, "GameFontNormalSmall", 730, 34,
            "TOPLEFT", frame, 16, -118)
        dashboard.rows = {}
        for rowIndex = 1, dashboard.rowCount do
            local row = MakeButton(frame, "", 730, 18, 15,
                -164 - (rowIndex - 1) * 17, function() end)
            row.caption:SetJustifyH("LEFT")
            table.insert(dashboard.rows, row)
        end
        dashboard.detail = MakeText(frame, "GameFontHighlightSmall", 730, 36,
            "TOPLEFT", frame, 16, -510)
        dashboard.footer = MakeText(frame, "GameFontNormalSmall", 550, 22,
            "TOPLEFT", frame, 16, -550)
        MakeButton(frame, "<", 30, 25, 650, -545, function()
            if dashboard.page == "LEDGER" then
                dashboard.pageNumber = math.max(1, dashboard.pageNumber - 1)
            else
                dashboard.overviewPageNumber =
                    math.max(1, dashboard.overviewPageNumber - 1)
            end
            addon.RefreshVisibleUI()
        end)
        MakeButton(frame, ">", 30, 25, 688, -545, function()
            if dashboard.page == "LEDGER" then
                dashboard.pageNumber = math.min(dashboard.totalPages or 1,
                    dashboard.pageNumber + 1)
            else
                dashboard.overviewPageNumber = math.min(dashboard.totalPages or 1,
                    dashboard.overviewPageNumber + 1)
            end
            addon.RefreshVisibleUI()
        end)
    end
    dashboard.characterKey = dashboard.characterKey or addon.characterKey
    if requestedPage == "LEDGER" then dashboard.page = "LEDGER"
    elseif requestedPage == "OVERVIEW" then dashboard.page = "OVERVIEW" end
    dashboard.frame:Show()
    addon.RefreshVisibleUI()
    return true
end
