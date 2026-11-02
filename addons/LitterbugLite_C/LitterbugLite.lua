-- Litterbug Lite Classic 0.2.0-dev.1
-- Visual inventory-space reserve, not an item destruction addon.
-- Only explicit player drag from a verified virtual slot can pick up an item.
local module = CreateFrame("Frame")
local inventory = {candidates = {}, free = 0, total = 0, unknownBags = 0,
    protected = 0, pending = 0, scanned = false, revision = 0}
local ui = {buttons = {}, forcedVisible = false, status = ""}
local MIN_RESERVE, MAX_RESERVE, DEFAULT_RESERVE = 3, 5, 3
local function IsInteger(number)
    return type(number) == "number" and number == math.floor(number) and number >= 0
end
local function Slots(bagIndex)
    if C_Container and C_Container.GetContainerNumSlots then
        return C_Container.GetContainerNumSlots(bagIndex)
    elseif type(GetContainerNumSlots) == "function" then
        return GetContainerNumSlots(bagIndex)
    end
end
local function FreeAndFamily(bagIndex)
    if C_Container and C_Container.GetContainerNumFreeSlots then
        return C_Container.GetContainerNumFreeSlots(bagIndex)
    elseif type(GetContainerNumFreeSlots) == "function" then
        return GetContainerNumFreeSlots(bagIndex)
    end
end
local function ReadSlot(bagIndex, slotIndex)
    if C_Container and C_Container.GetContainerItemInfo then
        local data = C_Container.GetContainerItemInfo(bagIndex, slotIndex)
        if not data then return nil end
        return {id = data.itemID, link = data.hyperlink, count = data.stackCount,
            quality = data.quality, locked = data.isLocked,
            icon = data.iconFileID}
    elseif type(GetContainerItemInfo) == "function" then
        local icon, count, locked, quality, _, _, link, _, _, itemID =
            GetContainerItemInfo(bagIndex, slotIndex)
        if not link then return nil end
        return {id = itemID, link = link, count = count, quality = quality,
            locked = locked, icon = icon}
    end
end
local function QuestInformation(bagIndex, slotIndex)
    if not C_Container or not C_Container.GetContainerItemQuestInfo then
        return nil
    end
    local ok, info = pcall(C_Container.GetContainerItemQuestInfo, bagIndex, slotIndex)
    if not ok or type(info) ~= "table" then return nil end
    if info.isQuestItem == true or (type(info.questID) == "number" and
        info.questID > 0) then return "PROTECTED" end
    return "CLEAR"
end
local function BasicBag(bagIndex, family)
    -- Generic bags have family mask zero. Quivers (arrows), ammunition
    -- pouches (bullets), herb bags, etc. must never inflate ordinary space.
    if bagIndex == 0 then return family == nil or family == 0 end
    if type(family) == "number" then return family == 0 end
    -- Only use an API-confirmed generic-container class as a fallback.
    if type(ContainerIDToInventoryID) ~= "function" or
        type(GetInventoryItemLink) ~= "function" then return false end
    local itemLink = GetInventoryItemLink("player", ContainerIDToInventoryID(bagIndex))
    if not itemLink or type(GetItemInfoInstant) ~= "function" then return false end
    local _, _, _, _, _, classID, subClassID = GetItemInfoInstant(itemLink)
    return classID == 1 and subClassID == 0
end
local function CachedValue(itemIdentifier)
    if not IsInteger(itemIdentifier) or itemIdentifier == 0 then return nil end
    if type(GetItemInfo) ~= "function" then return nil end
    local name, _, quality, _, _, _, _, _, _, _, price, classID =
        GetItemInfo(itemIdentifier)
    if type(name) ~= "string" or quality ~= 0 or not IsInteger(price) then
        return nil
    end
    if classID == nil and type(GetItemInfoInstant) == "function" then
        local _, _, _, _, _, instantClass = GetItemInfoInstant(itemIdentifier)
        classID = instantClass
    end
    if type(classID) ~= "number" or classID == 12 then return nil end
    return name, price
end
local function Candidate(bagIndex, slotIndex)
    local item = ReadSlot(bagIndex, slotIndex)
    if not item then return nil end
    if not IsInteger(item.id) or item.id == 0 or type(item.link) ~= "string"
        or not IsInteger(item.count) or item.count == 0 or
        item.quality ~= 0 or item.locked ~= false then
        return nil, "UNSAFE"
    end
    if QuestInformation(bagIndex, slotIndex) ~= "CLEAR" then
        return nil, "QUEST_UNKNOWN"
    end
    local name, unitPrice = CachedValue(item.id)
    if not name then return nil, "METADATA" end
    local totalValue = unitPrice * item.count
    if not IsInteger(totalValue) then return nil, "PRICE" end
    return {bag = bagIndex, slot = slotIndex, id = item.id,
        link = item.link, count = item.count, icon = item.icon,
        name = name, unitPrice = unitPrice, value = totalValue}
end
local function CopperText(value)
    local gold = math.floor(value / 10000)
    local silver = math.floor((value % 10000) / 100)
    local copper = value % 100
    if gold > 0 then return gold .. "g " .. silver .. "s " .. copper .. "c" end
    if silver > 0 then return silver .. "s " .. copper .. "c" end
    return copper .. "c"
end
local function Scan()
    local snapshot = {candidates = {}, free = 0, total = 0, unknownBags = 0,
        protected = 0, pending = 0, scanned = true,
        revision = inventory.revision + 1}
    for bagIndex = 0, (NUM_BAG_SLOTS or 4) do
        local freeSlots, family = FreeAndFamily(bagIndex)
        local slots = Slots(bagIndex)
        if IsInteger(slots) and IsInteger(freeSlots) and
            BasicBag(bagIndex, family) then
            snapshot.total = snapshot.total + slots
            snapshot.free = snapshot.free + freeSlots
            for slotIndex = 1, slots do
                local candidate, reason = Candidate(bagIndex, slotIndex)
                if candidate then
                    snapshot.candidates[#snapshot.candidates + 1] = candidate
                elseif reason == "QUEST_UNKNOWN" then
                    snapshot.protected = snapshot.protected + 1
                elseif reason then
                    snapshot.pending = snapshot.pending + 1
                end
            end
        elseif not IsInteger(slots) or not IsInteger(freeSlots) then
            snapshot.unknownBags = snapshot.unknownBags + 1
        end
    end
    table.sort(snapshot.candidates, function(first, second)
        if first.value ~= second.value then return first.value < second.value end
        if first.bag ~= second.bag then return first.bag < second.bag end
        return first.slot < second.slot
    end)
    inventory = snapshot
end
local function UpdateStatus(message)
    ui.status = message
    if ui.statusLabel then ui.statusLabel:SetText(message) end
end
local function SaveGeometry()
    if not ui.frame or type(LitterbugLiteDB) ~= "table" then return end
    LitterbugLiteDB.hudLeft = ui.frame:GetLeft()
    LitterbugLiteDB.hudBottom = ui.frame:GetBottom()
end
local function ReadReserve()
    local value = type(LitterbugLiteDB) == "table" and LitterbugLiteDB.reserveSlots
    if not IsInteger(value) then return DEFAULT_RESERVE end
    return math.max(MIN_RESERVE, math.min(MAX_RESERVE, value))
end
local function ReadOnlyRow(candidate, button)
    button.candidate = candidate
    if not candidate then
        button:Hide()
        return
    end
    button:Show()
    button.icon:SetTexture(candidate.icon or "Interface\Icons\INV_Misc_QuestionMark")
    button.count:SetText(candidate.count > 1 and candidate.count or "")
    button.value:SetText(CopperText(candidate.value))
end
local function OnMouseDrag(button)
    local candidate = button.candidate
    if not candidate or (InCombatLockdown and InCombatLockdown()) then
        UpdateStatus("Cannot pick up that item right now")
        return
    end
    if type(GetCursorInfo) ~= "function" or GetCursorInfo() ~= nil then
        UpdateStatus("Cursor occupied: return its contents first")
        return
    end
    local current = Candidate(candidate.bag, candidate.slot)
    if not current or current.id ~= candidate.id or
        current.link ~= candidate.link or current.count ~= candidate.count or
        current.value ~= candidate.value then
        UpdateStatus("Inventory changed; rescan first")
        Scan()
        if ui.refresh then ui.refresh() end
        return
    end
    local pickup = C_Container and C_Container.PickupContainerItem or
        PickupContainerItem
    if type(pickup) ~= "function" then
        UpdateStatus("Bag pickup API unavailable")
        return
    end
    local success = pcall(pickup, candidate.bag, candidate.slot)
    if success then
        UpdateStatus("Item picked up; drop it using WoW's inventory UI")
    else
        UpdateStatus("Item pickup blocked by game client")
    end
end
local function CreateItemButton(parent, index)
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(54, 54)
    button:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -10 - (MAX_RESERVE-index)*60, -92)
    local background = button:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints(button)
    background:SetTexture("Interface\Buttons\UI-Quickslot2")
    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetPoint("TOPLEFT", 5, -5)
    button.icon:SetPoint("BOTTOMRIGHT", -5, 5)
    button.count = button:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    button.count:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -5, 5)
    button.value = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    button.value:SetPoint("TOP", button, "BOTTOM", 0, -3)
    button:RegisterForDrag("LeftButton")
    button:SetScript("OnDragStart", OnMouseDrag)
    button:SetScript("OnEnter", function(self)
        if self.candidate and GameTooltip then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetBagItem(self.candidate.bag, self.candidate.slot)
            GameTooltip:AddLine("Total vendor value: " ..
                CopperText(self.candidate.value), 1, 0.82, 0.25)
            GameTooltip:Show()
        end
    end)
    button:SetScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)
    button:Hide()
    return button
end
local function Refresh()
    if not ui.frame then return end
    local reserve = ReadReserve()
    ui.reserveValue:SetText("Reserve " .. reserve)
    ui.bagLabel:SetText("Ordinary bag slots: " .. inventory.free .. "/" ..
        inventory.total)
    local needed = math.max(0, reserve - inventory.free)
    local displayCount = math.min(needed, #inventory.candidates, MAX_RESERVE)
    -- All virtual cells retain their physical x positions: cheapest on left
    -- among the displayed entries, with empty slots remaining to the left.
    for index, button in ipairs(ui.buttons) do
        local first = MAX_RESERVE - displayCount + 1
        local candidateIndex = index - first + 1
        ReadOnlyRow(candidateIndex > 0 and
            candidateIndex <= displayCount and inventory.candidates[candidateIndex]
            or nil, button)
    end
    local fullAndNoTrash = inventory.free == 0 and
        #inventory.candidates == 0 and inventory.unknownBags == 0
    if fullAndNoTrash then
        ui.statusLabel:SetTextColor(1, 0.22, 0.22)
        UpdateStatus("BAGS FULL. NO VERIFIED SAFE GRAY ITEMS.")
    elseif inventory.unknownBags > 0 then
        ui.statusLabel:SetTextColor(1, 0.55, 0.25)
        UpdateStatus("Bag capacity unavailable; check inventory")
    else
        ui.statusLabel:SetTextColor(1, 0.82, 0.35)
        UpdateStatus(ui.status ~= "" and ui.status or
            (#inventory.candidates .. " safely eligible gray stacks"))
    end
    local show = ui.forcedVisible or fullAndNoTrash or
        (needed > 0 and displayCount > 0)
    if show then ui.frame:Show() else ui.frame:Hide() end
end
local function Button(parent, text, x, y, width, callback)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetSize(width, 22)
    button:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    button:SetText(text)
    button:SetScript("OnClick", callback)
    return button
end
local function CreateUI()
    local frame = CreateFrame("Frame", "LitterbugLiteHUD", UIParent, "BackdropTemplate")
    frame:SetSize(350, 184)
    frame:SetClampedToScreen(true)
    frame:SetFrameStrata("MEDIUM")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:SetBackdrop({bgFile = "Interface\Buttons\WHITE8X8",
        edgeFile = "Interface\Tooltips\UI-Tooltip-Border", edgeSize = 12,
        insets = {left=3,right=3,top=3,bottom=3}})
    frame:SetBackdropColor(0.04,0.06,0.045,0.94)
    frame:SetBackdropBorderColor(0.58,0.54,0.37,1)
    if type(LitterbugLiteDB.hudLeft) == "number" and
        type(LitterbugLiteDB.hudBottom) == "number" then
        frame:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT",
            LitterbugLiteDB.hudLeft, LitterbugLiteDB.hudBottom)
    else
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, -130)
    end
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        SaveGeometry()
    end)
    ui.frame = frame
    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -11)
    title:SetText("Litterbug Lite")
    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -2, -2)
    close:SetScript("OnClick", function()
        ui.forcedVisible = false
        frame:Hide()
    end)
    ui.bagLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    ui.bagLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -36)
    ui.reserveValue = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    ui.reserveValue:SetPoint("TOPLEFT", frame, "TOPLEFT", 210, -36)
    local function AdjustReserve(change)
        LitterbugLiteDB.reserveSlots = math.max(MIN_RESERVE,
            math.min(MAX_RESERVE, ReadReserve() + change))
        ui.status = ""
        Refresh()
    end
    Button(frame, "-", 281, -29, 23, function() AdjustReserve(-1) end)
    Button(frame, "+", 310, -29, 23, function() AdjustReserve(1) end)
    for index = 1, MAX_RESERVE do
        ui.buttons[index] = CreateItemButton(frame, index)
    end
    ui.statusLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    ui.statusLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -62)
    ui.statusLabel:SetWidth(325)
    ui.statusLabel:SetJustifyH("LEFT")
    Button(frame, "Sort Trash", 10, -154, 114, function()
        -- No stock Classic API promises safe trash-only physical sorting.
        -- Sort the virtual ranking and re-scan; never move or destroy items.
        ui.status = "Virtual trash order refreshed; bags not rearranged"
        Scan()
        Refresh()
    end)
    Button(frame, "Refresh", 130, -154, 93, function()
        ui.status = ""
        Scan()
        Refresh()
    end)
    Button(frame, "Hide", 229, -154, 106, function()
        ui.forcedVisible = false
        frame:Hide()
    end)
    ui.refresh = Refresh
end
SLASH_LITTERBUGLITE1 = "/lbl"
SLASH_LITTERBUGLITE2 = "/litterbug"
SlashCmdList.LITTERBUGLITE = function(argument)
    argument = string.lower(string.match(argument or "", "^%s*(.-)%s*$"))
    if argument == "diag" then
        if DEFAULT_CHAT_FRAME then
            DEFAULT_CHAT_FRAME:AddMessage("Litterbug Lite v0.2.0-dev.1: normal " ..
                inventory.free .. "/" .. inventory.total .. ", excluded bags not counted," ..
                " candidates " .. #inventory.candidates ..
                ", protected/unknown " .. inventory.protected .. "/" ..
                inventory.pending .. ", bag unknown " .. inventory.unknownBags)
        end
        return
    elseif argument == "reset" then
        ui.frame:ClearAllPoints()
        ui.frame:SetPoint("CENTER", UIParent, "CENTER", 0, -130)
        SaveGeometry()
        ui.forcedVisible = true
    elseif argument == "show" then
        ui.forcedVisible = true
    elseif argument == "hide" then
        ui.forcedVisible = false
        ui.frame:Hide()
        return
    else
        ui.forcedVisible = not ui.forcedVisible
    end
    ui.status = ""
    Scan()
    Refresh()
end
module:RegisterEvent("ADDON_LOADED")
module:RegisterEvent("BAG_UPDATE_DELAYED")
module:SetScript("OnEvent", function(_, event, loaded)
    if event == "ADDON_LOADED" and loaded == "LitterbugLite" then
        LitterbugLiteDB = LitterbugLiteDB or {}
        LitterbugLiteDB.reserveSlots = ReadReserve()
        CreateUI()
        Scan()
        Refresh()
    elseif event == "BAG_UPDATE_DELAYED" and ui.frame then
        ui.status = ""
        Scan()
        Refresh()
    end
end)
