
local window
local lines = {}
local function makeText(parent, font, justify)
    local label = parent:CreateFontString(nil, "OVERLAY", font or "GameFontNormal")
    label:SetJustifyH(justify or "LEFT")
    return label
end
local function addLine(contents, lineNumber, displayedText, color)
    local label = lines[lineNumber]
    if not label then
        label = makeText(contents, "GameFontHighlightSmall")
        label:SetPoint("TOPLEFT", contents, "TOPLEFT", 4, -(lineNumber - 1) * 20 - 4)
        label:SetWidth(485)
        label:SetHeight(18)
        lines[lineNumber] = label
    end
    label:SetText(displayedText)
    if color then label:SetTextColor(color[1],color[2],color[3]) else label:SetTextColor(0.91, 0.88, 0.78) end
    label:Show()
end
local function makeWindow(heading)
    window = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    window:SetSize(555, 510)
    window:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    window:SetFrameStrata("DIALOG")
    window:SetClampedToScreen(true)
    window:SetMovable(true)
    window:EnableMouse(true)
    window:RegisterForDrag("LeftButton")
    window:SetScript("OnDragStart", function(self) self:StartMoving() end)
    window:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    window:SetBackdrop({ bgFile="Interface\\DialogFrame\\UI-DialogBox-Background", edgeFile="Interface\\DialogFrame\\UI-DialogBox-Border", tile=true, tileSize=32, edgeSize=32, insets={left=11,right=11,top=11,bottom=11} })
    local title = makeText(window,"GameFontNormalLarge","CENTER")
    title:SetPoint("TOP", window,"TOP",0,-20)
    title:SetText(heading)
    local close = CreateFrame("Button",nil,window,"UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", window,"TOPRIGHT",-5,-7)
    local scroll = CreateFrame("ScrollFrame",nil,window,"UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT",window,"TOPLEFT",22,-116)
    scroll:SetPoint("BOTTOMRIGHT",window,"BOTTOMRIGHT",-40,58)
    local content = CreateFrame("Frame",nil,scroll)
    content:SetSize(485,20)
    scroll:SetScrollChild(content)
    local summary=makeText(window,"GameFontHighlightSmall")
    summary:SetPoint("TOPLEFT", window,"TOPLEFT",24,-52)
    summary:SetWidth(500)
    summary:SetHeight(47)
    summary:SetJustifyV("TOP")
    local refresh=CreateFrame("Button",nil,window,"UIPanelButtonTemplate")
    refresh:SetSize(90,25)
    refresh:SetPoint("BOTTOMLEFT",window,"BOTTOMLEFT",24,18)
    refresh:SetText("Refresh")
    window:Hide()
    return summary, content, refresh
end

local summaryLabel,scrollContent,refreshButton,filterButton,reviewButton
local displayExclusions = false
local reviewTooltips = {}
local function refresh()
    if not LootHoarderDatabase then return end
    local database=LootHoarderDatabase
    local copper = database.moneyLootedCopper or 0
    local coinDisplay = string.format("%dg %ds %dc",math.floor(copper/10000),math.floor(copper/100)%100,copper%100)
    summaryLabel:SetText(string.format("Windows: %d  |  Empty: %d  |  Sources: %d  |  Item offers: %d\nCoins looted: %s  |  Gathering excluded: %d  |  Gray filter: %s", database.lootWindows or 0,database.emptyLootWindows or 0,database.uniqueSourcesObserved or 0,database.totalAvailableItemEvents or 0,coinDisplay,database.excludedGatheringWindows or 0,database.filterLowValueGray and "ON" or "OFF"))
    if filterButton then filterButton:SetText(database.filterLowValueGray and "Gray filter: ON" or "Gray filter: OFF") end
    if reviewButton then reviewButton:SetText(displayExclusions and "Back to loot" or "Review exclusions") end
    local index = 1
    if displayExclusions then
        local records = database.exclusionRecords or {}
        addLine(scrollContent,index,"EXCLUDED LOOT WINDOWS — most recent first",{1,0.82,0.3})
        index=index+1
        addLine(scrollContent,index,"Past exclusions before this update have no saved details.")
        index=index+1
        if #records == 0 then
            addLine(scrollContent,index,"No detailed exclusions recorded yet.")
            index=index+1
        end
        for _,record in ipairs(records) do
            local occurred = record.at and date("%m/%d %H:%M",record.at) or "Unknown time"
            local location = record.subzone ~= "" and record.subzone or record.zone or "Unknown"
            local itemText = record.itemCount > 0 and table.concat(record.items or {}, ", ") or "No item slots"
            local moneyNote = record.hasMoney and " | Money slot present" or ""
            local summary = string.format("%s | %s | %s", occurred,record.source or "Unknown",record.reason or "Unknown")
            addLine(scrollContent,index,summary,{1,0.84,0.55})
            index=index+1
            addLine(scrollContent,index,"    " .. location .. " | " .. itemText .. moneyNote)
            index=index+1
        end
        for unused=index,#lines do lines[unused]:Hide() end
        scrollContent:SetHeight(math.max(20,index*20))
        return
    end
    local aggregates={}
    local items={}
    for _,source in pairs(database.sources or {}) do
        local name=source.sourceName or (source.sourceType or "Unknown")
        local record=aggregates[name]
        if not record then record={name=name,observations=0,empty=0,money=0,zone=source.zone};aggregates[name]=record end
        record.observations=record.observations+(source.observations or 0)
        record.empty=record.empty+(source.zeroLootObservations or 0)
        record.money=record.money+(source.moneyLootedCopper or 0)
        for itemKey,material in pairs(source.items or {}) do
            local item=items[itemKey]
            if not item then item={name=material.name or "Unknown item",quantity=0,observations=0};items[itemKey]=item end
            item.quantity=item.quantity+(material.observedQuantity or 0)
            item.observations=item.observations+(material.positiveObservations or 0)
        end
    end
    local sortedItems={}
    for _,item in pairs(items) do table.insert(sortedItems,item) end
    table.sort(sortedItems,function(left,right)
        if left.quantity==right.quantity then return left.name<right.name end
        return left.quantity>right.quantity
    end)
    local sortedSources={}
    for _,source in pairs(aggregates) do table.insert(sortedSources,source) end
    table.sort(sortedSources,function(left,right)
        if left.observations==right.observations then return left.name<right.name end
        return left.observations>right.observations
    end)
    local index=1
    addLine(scrollContent,index,string.format("ITEMS OBSERVED (%d types)",#sortedItems),{1,0.82,0.3})
    index=index+1
    if #sortedItems==0 then addLine(scrollContent,index,"No ordinary loot observations yet.");index=index+1 end
    for _,item in ipairs(sortedItems) do
        addLine(scrollContent,index,string.format("%s   |   Available: %d   |   Observations: %d",item.name,item.quantity,item.observations))
        index=index+1
    end
    addLine(scrollContent,index,"LOOT SOURCES (grouped by name)",{1,0.82,0.3})
    index=index+1
    for _,source in ipairs(sortedSources) do
        addLine(scrollContent,index,string.format("%s   |   Observed: %d   |   Empty: %d   |   Coin: %dg %ds %dc",source.name,source.observations,source.empty,math.floor(source.money/10000),math.floor(source.money/100)%100,source.money%100))
        index=index+1
    end
    for unused=index,#lines do lines[unused]:Hide() end
    scrollContent:SetHeight(math.max(20,index*20))
end
local function showWindow()
    if not window then
        summaryLabel,scrollContent,refreshButton=makeWindow("LootHoarder — Loot Ledger")
        refreshButton:SetScript("OnClick",refresh)
        filterButton=CreateFrame("Button",nil,window,"UIPanelButtonTemplate")
        filterButton:SetSize(145,25)
        filterButton:SetPoint("LEFT",refreshButton,"RIGHT",10,0)
        reviewButton=CreateFrame("Button",nil,window,"UIPanelButtonTemplate")
        reviewButton:SetSize(155,25)
        reviewButton:SetPoint("LEFT",filterButton,"RIGHT",10,0)
        reviewButton:SetText("Review exclusions")
        reviewButton:SetScript("OnClick",function()
            displayExclusions=not displayExclusions
            refresh()
        end)
        filterButton:SetScript("OnClick",function()
            local database=LootHoarderDatabase
            database.filterLowValueGray=not database.filterLowValueGray
            database.warnedAutoLootConflict=nil
            if database.filterLowValueGray then
                DEFAULT_CHAT_FRAME:AddMessage("|cffffc46b[LH]|r Gray filter ON. Blizzard Auto Loot must be disabled for this filter to work.")
            end
            refresh()
        end)
    end
    refresh()
    window:Show()
end
local originalCommand=SlashCmdList.LOOTHOARDER
SlashCmdList.LOOTHOARDER=function(input)
    local command=(input or ""):lower():match("^%s*(.-)%s*$")
    if command=="" or command=="show" then showWindow()
    elseif command=="exclusions" or command=="excluded" then
        showWindow()
        displayExclusions=true
        refresh()
    elseif command=="hide" then if window then window:Hide() end
    elseif command=="toggle" then if window and window:IsShown() then window:Hide() else showWindow() end
    elseif command=="reset" then if window then window:ClearAllPoints();window:SetPoint("CENTER") end;showWindow()
    elseif command=="help" then
        originalCommand("help")
        DEFAULT_CHAT_FRAME:AddMessage("|cffffc46b[LH]|r Window: /lh  |  /lh show  |  /lh hide  |  /lh reset  |  /lh exclusions")
    else
        originalCommand(command)
        if window and window:IsShown() then refresh() end
    end
end
