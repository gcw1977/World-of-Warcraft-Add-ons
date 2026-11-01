-- GatherLedger v0.4.6 - Classic Era; skinning observations + inventory shopping list.
-- No network communications, no external libraries, no automatic installation.
local addon = CreateFrame("Frame")
local pending, captured = nil, false
-- Forward declaration: loot capture refreshes the visible window after each new record.
local refreshLedger
local ledgerWindow
local refreshShoppingWindow
local initializeShoppingWindow
local SKINNING_SPELL_ID = 8613
local SKINNING_NAME = GetSpellInfo and GetSpellInfo(SKINNING_SPELL_ID) or "Skinning"
local COLORS = { normal = "|cff76dd91", bonus = "|cffffc857", warn = "|cffff8c69", base = "|cffbfc9d6" }

local function say(message, color)
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage((color or COLORS.base) .. "[GatherLedger] " .. message .. "|r")
    end
end
local function now() return GetTime() end
local function getCurrentCharacterKey()
    local name = UnitName("player") or "Unknown"
    local realm = GetRealmName() or "UnknownRealm"
    return realm .. ":" .. name
end
local function extractCreatureIDFromGUID(guid)
    if type(guid) ~= "string" then return nil end
    return tonumber(guid:match("^Creature%-%d+%-%d+%-%d+%-%d+%-(%d+)%-"))
end
local function isSkinningSpell(spellID)
    if tonumber(spellID) == SKINNING_SPELL_ID then return true end
    local name = spellID and GetSpellInfo and GetSpellInfo(spellID)
    return name ~= nil and name == SKINNING_NAME
end
local function spellIDFromEvent(...)
    local a, b, c, d, e = ...
    -- Modern Classic: unit, castGUID, spellID. Older variants: unit, spell, rank, lineID, spellID.
    if type(c) == "number" then return c end
    if type(e) == "number" then return e end
    return nil
end
local function isExpectedSkinningMaterial(itemID, itemName)
    -- Conservative initial classification: only leather and leather scraps are expected.
    -- Hides, scales, specialty reagents and unknown items are highlighted as bonus.
    local normalizedItemName = (itemName or ""):lower()
    return normalizedItemName:find("leather", 1, true) ~= nil or normalizedItemName:find("scraps", 1, true) ~= nil
end
local function snapshotTarget()
    local guid = UnitGUID("target")
    if not guid or not guid:match("^Creature%-") then return nil end
    return {guid = guid, name = UnitName("target") or "Unknown Creature",
       level = UnitLevel("target"), creatureID = extractCreatureIDFromGUID(guid)}
end
local function beginAttempt()
    local target = snapshotTarget()
    pending = { target = target, started = now(), succeeded = false }
    captured = false
end
local function markSuccess()
    if not pending or now() - pending.started > 15 then beginAttempt() end
    if not pending then return end
    if not pending.target then pending.target = snapshotTarget() end
    pending.succeeded = true
    pending.finished = now()
end
-- One-time, additive migration. Historical observations are independent of inventory and goals.
-- Legacy values remain available for rollback until migration is validated in game.
local function migrateGatheringObservationQuantities()
    GatherLedgerDB = GatherLedgerDB or {}
    GatherLedgerDB.records = GatherLedgerDB.records or {}
    local migrated = 0
    for _, record in ipairs(GatherLedgerDB.records) do
        for _, item in ipairs(record.items or {}) do
            if item.observedQuantity == nil and item.quantity ~= nil then
                item.observedQuantity = item.quantity
                migrated = migrated + 1
            end
            if item.observedQuantity ~= nil then item.quantity = nil end
        end
    end
    GatherLedgerDB.gatheringSchemaVersion = 3
    return migrated
end

local function collectLoot()
    if not pending or not pending.succeeded or captured then return end
    if now() - (pending.finished or pending.started) > 8 then return end
    local target = pending.target
    local entries = {}
    local matchedSource = false
    local ambiguousSource = false
    for i = 1, (GetNumLootItems() or 0) do
        local slotType = GetLootSlotType and GetLootSlotType(i)
        -- LOOT_SLOT_ITEM = 1; avoid money and currencies.
        if slotType == 1 then
            local _, itemName, lootedItemQuantity = GetLootSlotInfo(i)
            local link = GetLootSlotLink(i)
            local id = link and tonumber(link:match("item:(%d+)"))
            if itemName then
                local sources = GetLootSourceInfo and {GetLootSourceInfo(i)} or {}
                local hasSource = #sources > 0
                local sourceMatches = false
                if hasSource and target then
                    for j = 1, #sources, 2 do
                        if sources[j] == target.guid then sourceMatches = true end
                    end
                end
                if hasSource and target and not sourceMatches then
                    ambiguousSource = true
                else
                    if sourceMatches then matchedSource = true end
                    table.insert(entries, {itemID = id, name = itemName,
                        observedQuantity = tonumber(lootedItemQuantity) or 1,
                        classification = isExpectedSkinningMaterial(id, itemName) and "expected" or "bonus"})
                end
            end
        end
    end
    if #entries == 0 then return end
    captured = true
    local confidence = (target and matchedSource and not ambiguousSource) and "matched" or "provisional"
    local p = getCurrentCharacterKey()
    GatherLedgerDB = GatherLedgerDB or {schema = 1, records = {}, settings = {chat = true}}
    GatherLedgerDB.records = GatherLedgerDB.records or {}
    GatherLedgerDB.settings = GatherLedgerDB.settings or {chat = true}
    local zone = GetZoneText and GetZoneText() or ""
    local record = {time = time(), character = p, creature = target and target.name or "Unknown",
        creatureID = target and target.creatureID, creatureGUID = target and target.guid,
        creatureLevel = target and target.level, zone = zone, confidence = confidence,
        items = entries}
    table.insert(GatherLedgerDB.records, record)
    if ledgerWindow and ledgerWindow:IsShown() then
        if ledgerWindow.activeTab == "shopping" and refreshShoppingWindow then
            refreshShoppingWindow()
        elseif refreshLedger then
            refreshLedger()
        end
    end
    if GatherLedgerDB.settings.chat then
        say("Skinned: " .. record.creature .. (record.creatureLevel and (" (Lv " .. record.creatureLevel .. ")") or "") ..
            (confidence ~= "matched" and " [source unverified]" or ""))
        for _, item in ipairs(entries) do
            local isBonus = item.classification == "bonus"
            say((isBonus and "BONUS: " or "+ ") .. item.observedQuantity .. " " .. item.name,
                isBonus and COLORS.bonus or COLORS.normal)
        end
    end
    pending = nil
end
-- Lightweight, on-demand ledger window. Nothing updates while hidden.
local function openLedger()
    if not ledgerWindow then
        local w = CreateFrame("Frame", "GatherLedgerWindow", UIParent, "BackdropTemplate")
        w:SetSize(380, 355)
        w:SetPoint("CENTER")
        w:SetFrameStrata("DIALOG")
        w:SetMovable(true)
        w:EnableMouse(true)
        w:RegisterForDrag("LeftButton")
        w:SetScript("OnDragStart", w.StartMoving)
        w:SetScript("OnDragStop", w.StopMovingOrSizing)
        w:SetClampedToScreen(true)
        w:SetBackdrop({bgFile="Interface\\DialogFrame\\UI-DialogBox-Background", edgeFile="Interface\\DialogFrame\\UI-DialogBox-Border", edgeSize=24,
            insets={left=7,right=7,top=7,bottom=7}})
        local title = w:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        title:SetPoint("TOPLEFT", 18, -17)
        title:SetText("GatherLedger  |  Skinning")
        local close = CreateFrame("Button", nil, w, "UIPanelCloseButton")
        close:SetPoint("TOPRIGHT", -3, -3)
        local summary = w:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        summary:SetPoint("TOPLEFT", 19, -45)
        summary:SetPoint("TOPRIGHT", -19, -45)
        summary:SetJustifyH("LEFT")
        w.summary = summary
        local header = w:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        header:SetPoint("TOPLEFT", 20, -73)
        header:SetText("Material")
        local qty = w:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        qty:SetPoint("TOPRIGHT", -40, -73)
        qty:SetText("Collected")
        local scroll = CreateFrame("ScrollFrame", "GatherLedgerScroll", w, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", 18, -93)
        scroll:SetPoint("BOTTOMRIGHT", -42, 75)
        local content = CreateFrame("Frame", nil, scroll)
        content:SetSize(310, 1)
        scroll:SetScrollChild(content)
        w.content = content
        w.rows = {}
        local foot = w:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        foot:SetPoint("BOTTOMLEFT", 19, 15)
        foot:SetText("/gledger toggle     Drag to move     Counts are lifetime loot")
        w:Hide()
        ledgerWindow = w
        if initializeShoppingWindow then initializeShoppingWindow(w) end
    end
    if ledgerWindow:IsShown() then
        ledgerWindow:Hide()
    else
        if ledgerWindow.activeTab == "shopping" and refreshShoppingWindow then refreshShoppingWindow()
        else refreshLedger() end
        ledgerWindow:Show()
    end
end
refreshLedger = function()
    if not ledgerWindow then return end
    if ledgerWindow.activeTab == "shopping" then return end
    local records = GatherLedgerDB and GatherLedgerDB.records or {}
    local totals, skinCount, matched = {}, #records, 0
    for _, record in ipairs(records) do
        if record.confidence == "matched" then matched = matched + 1 end
        for _, item in ipairs(record.items or {}) do
            local key = item.itemID and ("id:" .. item.itemID) or ("name:" .. (item.name or "Unknown"))
            local entry = totals[key]
            if not entry then
                entry = {name = item.name or "Unknown", count = 0, bonus = item.classification == "bonus"}
                totals[key] = entry
            end
            entry.count = entry.count + (tonumber(item.observedQuantity) or 1)
            if item.classification == "bonus" then entry.bonus = true end
        end
    end
    local items = {}
    for _, entry in pairs(totals) do table.insert(items, entry) end
    table.sort(items, function(a,b) if a.count ~= b.count then return a.count > b.count end return a.name < b.name end)
    ledgerWindow.summary:SetText(string.format("%d skins recorded  |  %d matched  |  %d material types", skinCount, matched, #items))
    if #items == 0 then items[1] = {name = "No observations yet. Go skin something!", count = 0} end
    local content = ledgerWindow.content
    content:SetHeight(math.max(1, #items * 22 + 5))
    for i, entry in ipairs(items) do
        local row = ledgerWindow.rows[i]
        if not row then
            row = CreateFrame("Frame", nil, content)
            row:SetSize(300, 22)
            row:SetPoint("TOPLEFT", 0, -(i-1)*22)
            row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.name:SetPoint("LEFT", 2, 0)
            row.name:SetWidth(230)
            row.name:SetJustifyH("LEFT")
            row.count = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.count:SetPoint("RIGHT", -8, 0)
            row.count:SetJustifyH("RIGHT")
            ledgerWindow.rows[i] = row
        end
        row:Show()
        row.name:SetText((entry.bonus and COLORS.bonus or COLORS.normal) .. entry.name .. "|r")
        row.count:SetText(entry.count > 0 and tostring(entry.count) or "")
    end
    for i = #items + 1, #ledgerWindow.rows do ledgerWindow.rows[i]:Hide() end
end

addon:RegisterEvent("ADDON_LOADED")
addon:RegisterEvent("UNIT_SPELLCAST_SENT")
addon:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
addon:RegisterEvent("LOOT_READY")
addon:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        local name = ...
        if name == "GatherLedger" then
            GatherLedgerDB = GatherLedgerDB or {schema = 1, records = {}, settings = {chat = true}}
            GatherLedgerDB.records = GatherLedgerDB.records or {}
            GatherLedgerDB.settings = GatherLedgerDB.settings or {chat = true}
            migrateGatheringObservationQuantities()
        end
    elseif event == "UNIT_SPELLCAST_SENT" then
        local unit, targetName, castGUID, spellID = ...
        if unit == "player" and isSkinningSpell(spellID) then beginAttempt() end
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        local unit = ...
        if unit == "player" and isSkinningSpell(spellIDFromEvent(...)) then markSuccess() end
    elseif event == "LOOT_READY" then
        collectLoot()
    end
end)
SLASH_GATHERLEDGER1 = "/gledger"
SlashCmdList.GATHERLEDGER = function(arg)
    arg = (arg or ""):lower():match("^%s*(.-)%s*$")
    if arg == "off" then GatherLedgerDB.settings.chat = false; say("Chat output disabled; logging continues.")
    elseif arg == "on" then GatherLedgerDB.settings.chat = true; say("Chat output enabled.")
    elseif arg == "toggle" or arg == "show" or arg == "ui" or arg == "" then openLedger()
    elseif arg == "count" then say("Recorded " .. #(GatherLedgerDB.records or {}) .. " skinning observations.")
    else say("Commands: /gledger (window) | toggle | on | off | count | shop | stats") end
end

-- Shopping.lua assigns these callbacks after loading. Export the existing window toggler
-- without changing the skinning collection event handling.
GatherLedgerOpenWindow = openLedger
GatherLedgerRefreshStatistics = refreshLedger
GatherLedgerRegisterShopping = function(initializer, refresher)
    initializeShoppingWindow = initializer
    refreshShoppingWindow = refresher
end
