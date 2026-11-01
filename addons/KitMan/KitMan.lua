-- KitMan v0.1.0 - Classic Era equipment set interface.
-- Uses Blizzard's native equipment-set system so /equipset macros continue to work.
local addonName = ...
local mainWindow, setNameInput, listContent, listScrollFrame, statusText
local buttonRows = {}
local promptPending = false

local function Announce(message)
    DEFAULT_CHAT_FRAME:AddMessage('|cff74caff[KitMan]|r ' .. tostring(message))
end

local function EquipmentAPI()
    if C_EquipmentSet and C_EquipmentSet.GetEquipmentSetIDs
        and C_EquipmentSet.GetEquipmentSetInfo and C_EquipmentSet.UseEquipmentSet
        and C_EquipmentSet.CreateEquipmentSet and C_EquipmentSet.SaveEquipmentSet then
        return C_EquipmentSet
    end
    return nil
end

local function ReportStatus(message)
    if statusText then statusText:SetText(message) end
    Announce(message)
end

local function FindSetByName(name)
    local api = EquipmentAPI()
    if not api then return nil end
    for _, id in ipairs(api.GetEquipmentSetIDs() or {}) do
        local currentName = api.GetEquipmentSetInfo(id)
        if currentName and string.lower(currentName) == string.lower(name) then
            return id, currentName
        end
    end
    return nil
end

local function CanChangeEquipment()
    if InCombatLockdown() or UnitAffectingCombat('player') then
        ReportStatus('Cannot change equipment sets while in combat.')
        return false
    end
    if not EquipmentAPI() then
        ReportStatus('The native equipment-set API is unavailable in this client.')
        return false
    end
    return true
end

local function CleanName(name)
    name = (name or ''):match('^%s*(.-)%s*$')
    if name == '' then return nil end
    return name
end

local function CreateButton(parent, label, width, height, clickHandler)
    local button = CreateFrame('Button', nil, parent, 'UIPanelButtonTemplate')
    button:SetSize(width, height)
    button:SetText(label)
    button:SetScript('OnClick', clickHandler)
    return button
end

local function SetCount()
    local api = EquipmentAPI()
    return api and #(api.GetEquipmentSetIDs() or {}) or 0
end

local function RefreshList()
    if not listContent then return end
    for _, row in ipairs(buttonRows) do row:Hide() end
    local api = EquipmentAPI()
    if not api then
        if statusText then statusText:SetText('Native equipment sets are unavailable on this client.') end
        return
    end
    local ids = api.GetEquipmentSetIDs() or {}
    table.sort(ids, function(first, second)
        local firstName = api.GetEquipmentSetInfo(first) or ''
        local secondName = api.GetEquipmentSetInfo(second) or ''
        return string.lower(firstName) < string.lower(secondName)
    end)
    local rowHeight = 36
    for index, setID in ipairs(ids) do
        local row = buttonRows[index]
        if not row then
            row = CreateFrame('Frame', nil, listContent)
            row:SetHeight(rowHeight)
            row.name = row:CreateFontString(nil, 'OVERLAY', 'GameFontNormal')
            row.name:SetPoint('LEFT', 8, 0)
            row.name:SetWidth(214)
            row.name:SetJustifyH('LEFT')
            row.equip = CreateButton(row, 'Equip', 70, 25, function()
                if not CanChangeEquipment() then return end
                local success = EquipmentAPI().UseEquipmentSet(row.setID)
                if success then ReportStatus('Equipping ' .. row.setName .. '.')
                else ReportStatus('Could not equip ' .. row.setName .. '. Check your bags and equipment.') end
                RefreshList()
            end)
            row.equip:SetPoint('LEFT', row, 'LEFT', 228, 0)
            row.save = CreateButton(row, 'Update', 76, 25, function()
                if not CanChangeEquipment() then return end
                StaticPopup_Show('KITMAN_CONFIRM_UPDATE', row.setName, nil, { id = row.setID, name = row.setName })
            end)
            row.save:SetPoint('LEFT', row.equip, 'RIGHT', 5, 0)
            row.delete = CreateButton(row, 'Delete', 74, 25, function()
                if not CanChangeEquipment() then return end
                StaticPopup_Show('KITMAN_CONFIRM_DELETE', row.setName, nil, { id = row.setID, name = row.setName })
            end)
            row.delete:SetPoint('LEFT', row.save, 'RIGHT', 5, 0)
            buttonRows[index] = row
        end
        local name, _, _, isEquipped = api.GetEquipmentSetInfo(setID)
        row.setID = setID
        row.setName = name or ('Set ' .. tostring(setID))
        row.name:SetText((isEquipped and '|cff55ff55' or '|cffffd100') .. row.setName .. '|r')
        row:SetWidth(490)
        row:ClearAllPoints()
        row:SetPoint('TOPLEFT', listContent, 'TOPLEFT', 0, -((index - 1) * rowHeight))
        row:Show()
    end
    listContent:SetHeight(math.max(1, #ids * rowHeight))
    if statusText and #ids == 0 then statusText:SetText('No sets saved yet. Equip your gear, enter Fighting or Fishing, then Save New Set.') end
end

local function SaveSet(name)
    if not CanChangeEquipment() then return end
    name = CleanName(name)
    if not name then ReportStatus('Enter a set name first (for example, Fighting or Fishing).') return end
    local oldID = FindSetByName(name)
    if oldID then
        StaticPopup_Show('KITMAN_CONFIRM_UPDATE', name, nil, { id = oldID, name = name })
        return
    end
    local id = EquipmentAPI().CreateEquipmentSet(name)
    if id then ReportStatus('Saved equipment set: ' .. name .. '.')
    else ReportStatus('Could not create set. Its name might already exist, or the set limit was reached.') end
    RefreshList()
end

local function EquipSet(name)
    if not CanChangeEquipment() then return end
    local id, realName = FindSetByName(name)
    if not id then ReportStatus('No saved set named ' .. tostring(name) .. '.') return end
    local success = EquipmentAPI().UseEquipmentSet(id)
    if success then ReportStatus('Equipping ' .. realName .. '.')
    else ReportStatus('Could not equip ' .. realName .. '. Check that its items are in your bags.') end
    RefreshList()
end

StaticPopupDialogs['KITMAN_CONFIRM_UPDATE'] = {
    text = 'Overwrite the saved equipment in %s with your currently equipped items?',
    button1 = 'Update', button2 = 'Cancel', timeout = 0, whileDead = true, hideOnEscape = true,
    OnAccept = function(_, data)
        if not data or not CanChangeEquipment() then return end
        EquipmentAPI().SaveEquipmentSet(data.id)
        ReportStatus('Updated equipment set: ' .. data.name .. '.')
        RefreshList()
    end,
}
StaticPopupDialogs['KITMAN_CONFIRM_DELETE'] = {
    text = 'Permanently delete equipment set %s? This will not delete any items.',
    button1 = 'Delete', button2 = 'Cancel', timeout = 0, whileDead = true, hideOnEscape = true,
    OnAccept = function(_, data)
        if not data or not CanChangeEquipment() then return end
        local api = EquipmentAPI()
        if not api.DeleteEquipmentSet then ReportStatus('Deleting sets is unavailable on this client.') return end
        api.DeleteEquipmentSet(data.id)
        ReportStatus('Deleted equipment set: ' .. data.name .. '.')
        RefreshList()
    end,
}

local function CreateWindow()
    mainWindow = CreateFrame('Frame', 'KitManMainWindow', UIParent, 'BasicFrameTemplateWithInset')
    mainWindow:SetSize(555, 425)
    mainWindow:SetPoint('CENTER', UIParent, 'CENTER', 0, 0)
    mainWindow:SetMovable(true)
    mainWindow:EnableMouse(true)
    mainWindow:RegisterForDrag('LeftButton')
    mainWindow:SetScript('OnDragStart', function(self) self:StartMoving() end)
    mainWindow:SetScript('OnDragStop', function(self)
        self:StopMovingOrSizing()
        local point, _, relativePoint, x, y = self:GetPoint(1)
        KitManDB.window = { point = point, relativePoint = relativePoint, x = x, y = y }
    end)
    mainWindow:SetClampedToScreen(true)
    mainWindow.TitleText:SetText('KitMan — Equipment Sets')
    mainWindow:Hide()

    local instruction = mainWindow:CreateFontString(nil, 'OVERLAY', 'GameFontHighlightSmall')
    instruction:SetPoint('TOPLEFT', 18, -37)
    instruction:SetWidth(515)
    instruction:SetJustifyH('LEFT')
    instruction:SetText('Equip your desired gear first, then save it as a named set. Set switching is disabled during combat.')

    setNameInput = CreateFrame('EditBox', nil, mainWindow, 'InputBoxTemplate')
    setNameInput:SetSize(258, 30)
    setNameInput:SetPoint('TOPLEFT', 24, -72)
    setNameInput:SetAutoFocus(false)
    setNameInput:SetMaxLetters(40)
    setNameInput:SetText('Fighting')
    setNameInput:SetScript('OnEscapePressed', function(self) self:ClearFocus() end)
    setNameInput:SetScript('OnEnterPressed', function(self) SaveSet(self:GetText()); self:ClearFocus() end)

    local saveButton = CreateButton(mainWindow, 'Save New Set', 126, 28, function() SaveSet(setNameInput:GetText()) end)
    saveButton:SetPoint('LEFT', setNameInput, 'RIGHT', 12, 0)

    local refreshButton = CreateButton(mainWindow, 'Refresh', 80, 26, RefreshList)
    refreshButton:SetPoint('TOPRIGHT', mainWindow, 'TOPRIGHT', -18, -113)

    local heading = mainWindow:CreateFontString(nil, 'OVERLAY', 'GameFontNormal')
    heading:SetPoint('TOPLEFT', 22, -123)
    heading:SetText('Saved equipment sets (' .. tostring(SetCount()) .. ' at startup)')

    listScrollFrame = CreateFrame('ScrollFrame', 'KitManListScrollFrame', mainWindow, 'UIPanelScrollFrameTemplate')
    listScrollFrame:SetPoint('TOPLEFT', 16, -150)
    listScrollFrame:SetPoint('BOTTOMRIGHT', -38, 54)
    listContent = CreateFrame('Frame', nil, listScrollFrame)
    listContent:SetSize(490, 1)
    listScrollFrame:SetScrollChild(listContent)

    statusText = mainWindow:CreateFontString(nil, 'OVERLAY', 'GameFontHighlightSmall')
    statusText:SetPoint('BOTTOMLEFT', 19, 20)
    statusText:SetWidth(510)
    statusText:SetJustifyH('LEFT')
    statusText:SetText('KitMan ready. /km help for commands.')

    if KitManDB.window then
        local position = KitManDB.window
        mainWindow:ClearAllPoints()
        mainWindow:SetPoint(position.point or 'CENTER', UIParent, position.relativePoint or 'CENTER', position.x or 0, position.y or 0)
    end
end

local function ShowWindow()
    if not mainWindow then CreateWindow() end
    RefreshList()
    mainWindow:Show()
end

local function ProcessCommand(message)
    local action, argument = (message or ''):match('^%s*(%S*)%s*(.-)%s*$')
    action = string.lower(action or '')
    if action == '' or action == 'show' then ShowWindow(); return end
    if action == 'hide' then if mainWindow then mainWindow:Hide() end; return end
    if action == 'help' then
        Announce('/km — window | /km save NAME | /km equip NAME | /km list | /km help')
        return
    end
    if action == 'list' then
        local api = EquipmentAPI()
        if not api then Announce('Equipment-set API unavailable.') return end
        local names = {}
        for _, id in ipairs(api.GetEquipmentSetIDs() or {}) do
            table.insert(names, api.GetEquipmentSetInfo(id) or tostring(id))
        end
        Announce(#names > 0 and table.concat(names, ', ') or 'No equipment sets saved.')
        return
    end
    if action == 'save' then SaveSet(argument); return end
    if action == 'equip' then EquipSet(argument); return end
    Announce('Unknown command. Type /km help.')
end

SLASH_KITMAN1 = '/km'
SLASH_KITMAN2 = '/kitman'
SlashCmdList['KITMAN'] = ProcessCommand

local events = CreateFrame('Frame')
events:RegisterEvent('ADDON_LOADED')
events:RegisterEvent('PLAYER_ENTERING_WORLD')
events:RegisterEvent('EQUIPMENT_SETS_CHANGED')
events:SetScript('OnEvent', function(_, event, loadedName)
    if event == 'ADDON_LOADED' and loadedName == addonName then
        KitManDB = KitManDB or {}
        if not mainWindow then CreateWindow() end
    elseif event == 'PLAYER_ENTERING_WORLD' or event == 'EQUIPMENT_SETS_CHANGED' then
        if mainWindow and mainWindow:IsShown() then RefreshList() end
    end
end)
