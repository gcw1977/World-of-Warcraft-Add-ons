-- BodyCount 0.3.0 UI: Recent / This Session / Last Session / Lifetime
local window,heading,summary,scrollContent,refreshButton,filterButton,sortButton
local lineLabels={}
local selectedTab="recent"
local tabs={"Recent","This Session","Last Session","Lifetime"}
local availableSorts={"kills","damage","encounters","name"}
local availableFilters={"all","Beast","Humanoid","Undead","Demon","Dragonkin","Elemental","Mechanical","Critter","Other"}
local function label(parent,font)
    local item=parent:CreateFontString(nil,"OVERLAY",font or "GameFontHighlightSmall")
    item:SetJustifyH("LEFT")
    return item
end
local function line(index,value,r,g,b)
    local item=lineLabels[index]
    if not item then
        item=label(scrollContent)
        item:SetPoint("TOPLEFT",scrollContent,"TOPLEFT",5,-(index-1)*21-4)
        item:SetWidth(510)
        item:SetHeight(19)
        lineLabels[index]=item
    end
    item:SetText(value)
    item:SetTextColor(r or .88,g or .86,b or .78)
    item:Show()
end
local function makeWindow()
    window=CreateFrame("Frame","BodyCountLedgerWindow",UIParent,"BackdropTemplate")
    window:SetSize(580,440)
    window:SetPoint("CENTER")
    window:SetFrameStrata("DIALOG")
    window:SetClampedToScreen(true)
    window:SetMovable(true)
    window:EnableMouse(true)
    window:RegisterForDrag("LeftButton")
    window:SetScript("OnDragStart",function(self) self:StartMoving() end)
    window:SetScript("OnDragStop",function(self) self:StopMovingOrSizing() end)
    window:SetBackdrop({bgFile="Interface\\DialogFrame\\UI-DialogBox-Background",edgeFile="Interface\\DialogFrame\\UI-DialogBox-Border",tile=true,tileSize=32,edgeSize=32,insets={left=11,right=11,top=11,bottom=11}})
    heading=label(window,"GameFontNormalLarge")
    heading:SetPoint("TOPLEFT",window,"TOPLEFT",23,-17)
    heading:SetText("BodyCount — Encounter Ledger")
    local close=CreateFrame("Button",nil,window,"UIPanelCloseButton")
    close:SetPoint("TOPRIGHT",window,"TOPRIGHT",-6,-5)
    summary=label(window,"GameFontHighlightSmall")
    summary:SetPoint("TOPLEFT",window,"TOPLEFT",24,-90)
    summary:SetWidth(525)
    summary:SetHeight(43)
    summary:SetJustifyV("TOP")
    local buttons={}
    for index,name in ipairs(tabs) do
        local button=CreateFrame("Button",nil,window,"UIPanelButtonTemplate")
        button:SetSize(126,24)
        button:SetPoint("TOPLEFT",window,"TOPLEFT",22+(index-1)*133,-49)
        button:SetText(name)
        button:SetScript("OnClick",function() selectedTab=({"recent","session","last","lifetime"})[index];BodyCountRefreshUI() end)
        buttons[index]=button
    end
    local scroll=CreateFrame("ScrollFrame",nil,window,"UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT",window,"TOPLEFT",23,-160)
    scroll:SetPoint("BOTTOMRIGHT",window,"BOTTOMRIGHT",-38,50)
    scrollContent=CreateFrame("Frame",nil,scroll)
    scrollContent:SetSize(515,24)
    scroll:SetScrollChild(scrollContent)
    refreshButton=CreateFrame("Button",nil,window,"UIPanelButtonTemplate")
    refreshButton:SetSize(85,23)
    refreshButton:SetPoint("BOTTOMLEFT",window,"BOTTOMLEFT",24,17)
    refreshButton:SetText("Refresh")
    refreshButton:SetScript("OnClick",function() BodyCountRefreshUI() end)
    sortButton=CreateFrame("Button",nil,window,"UIPanelButtonTemplate")
    sortButton:SetSize(124,23)
    sortButton:SetPoint("BOTTOMRIGHT",window,"BOTTOMRIGHT",-25,17)
    sortButton:SetScript("OnClick",function()
        local pref=BodyCountDatabase.preferences
        local selected=1
        for i,value in ipairs(availableSorts) do if value==pref.sort then selected=i end end
        pref.sort=availableSorts[selected % #availableSorts+1]
        BodyCountRefreshUI()
    end)
    filterButton=CreateFrame("Button",nil,window,"UIPanelButtonTemplate")
    filterButton:SetSize(150,23)
    filterButton:SetPoint("RIGHT",sortButton,"LEFT",-8,0)
    filterButton:SetScript("OnClick",function()
        local pref=BodyCountDatabase.preferences
        local selected=1
        for i,value in ipairs(availableFilters) do if value==pref.filter then selected=i end end
        pref.filter=availableFilters[selected % #availableFilters+1]
        BodyCountRefreshUI()
    end)
    window:Hide()
end
local function emitSession(session)
    if not session then
        summary:SetText("No previous session saved yet.")
        line(1,"Your previous session will appear after the next logout and login.")
        return 1
    end
    summary:SetText(string.format("Encounters %d    Credited kills %d    Assists %d    Damage %d",session.encounters or 0,session.kills or 0,session.assists or 0,session.damage or 0))
    local records=session.records or {}
    local index=1
    line(index,string.format("Recent records (last %d; session totals include all)",#records),1,.82,.35)
    index=index+1
    for recordIndex=#records,1,-1 do
        local record=records[recordIndex]
        line(index,string.format("%s | %s | %s | %d damage (you %d, pet %d)",record.name or "Unknown",record.outcome or "unknown",record.tag or "unknown",record.damage or 0,record.playerDamage or 0,record.petDamage or 0))
        index=index+1
    end
    if #records==0 then line(index,"No completed encounters in this session.");index=index+1 end
    return index-1
end
local function creatureType(recordedType)
    -- Creature type is sampled only when Blizzard exposes the relevant unit; old records may lack it.
    return recordedType or "Other"
end
function BodyCountRefreshUI()
    if not window or not window:IsShown() or not BodyCountDatabase then return end
    local database=BodyCountDatabase
    local index=1
    sortButton:SetShown(selectedTab=="lifetime")
    filterButton:SetShown(selectedTab=="lifetime")
    if selectedTab=="recent" then
        local record=database.recentEncounter
        if record then
            summary:SetText(string.format("Latest: %s   |   Outcome: %s",record.name or "Unknown",record.outcome or "unknown"))
            line(index,"Tag: "..(record.tag or "unknown"),1,.82,.35);index=index+1
            line(index,string.format("Your damage: %d    Pet damage: %d    Combined: %d",record.playerDamage or 0,record.petDamage or 0,record.damage or 0));index=index+1
            line(index,string.format("Overkill: %d    Recorded: %s",record.overkill or 0,date("%H:%M:%S",record.ended or time())));index=index+1
            line(index,"An observed death without reliable tag/credit evidence stays UNKNOWN.",.72,.78,.83);index=index+1
        else
            summary:SetText("Most recent completed encounter")
            line(index,"No encounters recorded during this login yet.");index=index+1
        end
    elseif selectedTab=="session" then index=emitSession(database.currentSession)+1
    elseif selectedTab=="last" then index=emitSession(database.lastSession)+1
    else
        summary:SetText(string.format("Lifetime encounters: %d    Bodies stacked: %d    Damage: %d    Assists: %d",database.lifetimeEncounters or 0,database.kills or 0,database.damage or 0,database.lifetimeAssists or 0))
        local pref=database.preferences or {sort="kills",filter="all"}
        local creatures={}
        for _,record in pairs(database.creatures or {}) do
            local kind=creatureType(record.creatureType)
            if pref.filter=="all" or kind==pref.filter then table.insert(creatures,record) end
        end
        table.sort(creatures,function(a,b)
            local key=pref.sort or "kills"
            if key=="name" then return (a.name or "")<(b.name or "") end
            local av,bv=a[key] or 0,b[key] or 0
            if av==bv then return (a.name or "")<(b.name or "") end
            return av>bv
        end)
        sortButton:SetText("Sort: "..(pref.sort or "kills"))
        filterButton:SetText("Type: "..(pref.filter or "all"))
        line(index,"Creature   |   Encounters   |   Kills   |   Assists   |   Damage",1,.82,.35);index=index+1
        for _,record in ipairs(creatures) do
            line(index,string.format("%s | %d | %d | %d | %d",record.name or "Unknown",record.encounters or 0,record.kills or 0,record.assists or 0,record.damage or 0));index=index+1
        end
        if #creatures==0 then line(index,"No matching creature records.");index=index+1 end
        line(index,"Note: pre-0.3 kills/damage are preserved; encounter counts start with 0.3.",.7,.75,.8);index=index+1
    end
    for i=index,#lineLabels do lineLabels[i]:Hide() end
    scrollContent:SetHeight(math.max(24,index*21+8))
end
local previousCommand=SlashCmdList.BODYCOUNT
SlashCmdList.BODYCOUNT=function(input)
    local cmd=(input or ""):lower():match("^%s*(.-)%s*$")
    if cmd=="" or cmd=="show" or cmd=="toggle" then
        if not window then makeWindow() end
        if cmd=="toggle" and window:IsShown() then window:Hide() else window:Show();BodyCountRefreshUI() end
    elseif cmd=="hide" then if window then window:Hide() end
    elseif cmd=="reset" then
        if not window then makeWindow() end
        window:ClearAllPoints();window:SetPoint("CENTER");window:Show();BodyCountRefreshUI()
    else previousCommand(cmd) end
end
