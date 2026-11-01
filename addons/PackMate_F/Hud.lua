local addonName, packMate = ...
packMate.Hud = {}
local hudFrame
local experienceBar
local loyaltyBar
local borderTextures = {}
local tooltipModel
local moodColors = {
    [1] = {1.00, 0.20, 0.20}, [2] = {1.00, 0.85, 0.12},
    [3] = {0.20, 0.95, 0.30}, unknown = {0.50, 0.55, 0.62}
}

local function paint(texture, red, green, blue, alpha)
    if type(texture.SetColorTexture) == "function" then
        texture:SetColorTexture(red, green, blue, alpha or 1)
    else
        texture:SetTexture(red, green, blue, alpha or 1)
    end
end

local function saveGeometry()
    if not hudFrame then return end
    local _, _, _, horizontal, vertical = hudFrame:GetPoint(1)
    local safeX = packMate.Safe.Integer(math.floor(horizontal or 0), -4000, 4000)
    local safeY = packMate.Safe.Integer(math.floor(vertical or 0), -4000, 4000)
    local safeWidth = packMate.Safe.Integer(math.floor(hudFrame:GetWidth()), 110, 320)
    local safeHeight = packMate.Safe.Integer(math.floor(hudFrame:GetHeight()), 28, 100)
    if safeX and safeY and safeWidth and safeHeight then
        packMate.Storage.SaveGeometry({anchor = "CENTER", relativeAnchor = "CENTER",
            x = safeX, y = safeY, width = safeWidth, height = safeHeight})
    else
        packMate.RecordDiagnostic("HUD", "WARN", "GEOMETRY_NOT_SAVED")
    end
end

local function addTooltipLine(value)
    if value ~= nil and type(value) == "string" then GameTooltip:AddLine(value, 1, 1, 1, true) end
end

local function showTooltip()
    if not tooltipModel or not GameTooltip then return end
    local model = tooltipModel
    local success = pcall(function()
        GameTooltip:SetOwner(hudFrame, "ANCHOR_RIGHT")
        addTooltipLine("PackMate Forever " .. packMate.Version)
        addTooltipLine("Pet: " .. model.petName .. " (level " .. tostring(model.petLevel) .. ")")
        if model.experience and model.experience.availabilityState == "AVAILABLE" then
            local current, required = model.experience.current, model.experience.required
            addTooltipLine("XP: " .. tostring(current) .. "/" .. tostring(required)
                .. " (" .. string.format("%.1f", current * 100 / required) .. "%)")
        else
            addTooltipLine("XP: unavailable (" .. (model.experience and model.experience.reasonCode or "UNKNOWN") .. ")")
        end
        if model.loyalty and model.loyalty.availabilityState == "AVAILABLE" then
            addTooltipLine("Loyalty: " .. model.loyalty.description)
        else
            addTooltipLine("Loyalty: unavailable (" .. (model.loyalty and model.loyalty.reasonCode or "UNKNOWN") .. ")")
        end
        addTooltipLine("Loyalty progress: unavailable (no validated numerical scale)")
        if model.points and model.points.availabilityState == "AVAILABLE" then
            addTooltipLine("Available training points: " .. tostring(model.points.availablePoints))
        else
            addTooltipLine("Points: unavailable (" .. (model.points and model.points.reasonCode or "UNKNOWN") .. ")")
        end
        addTooltipLine("Happiness: " .. packMate.Happiness.Name(model.happiness))
        if model.observedTotal ~= nil then
            addTooltipLine("Observed pet XP total: " .. tostring(model.observedTotal))
        else
            addTooltipLine("Observed XP total: unavailable (identity/persistence)")
        end
        GameTooltip:Show()
    end)
    if not success then packMate.RecordDiagnostic("HUD", "WARN", "TOOLTIP_FAILED") end
end

local function createBorder(parent, side)
    local texture = parent:CreateTexture(nil, "BORDER")
    if side == "TOP" then
        texture:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
        texture:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, 0)
        texture:SetHeight(2)
    elseif side == "BOTTOM" then
        texture:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", 0, 0)
        texture:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 0)
        texture:SetHeight(2)
    elseif side == "LEFT" then
        texture:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
        texture:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", 0, 0)
        texture:SetWidth(2)
    else
        texture:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, 0)
        texture:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 0)
        texture:SetWidth(2)
    end
    table.insert(borderTextures, texture)
end

function packMate.Hud.Initialize()
    hudFrame = CreateFrame("Frame", "PackMateForeverStatusHud", UIParent)
    hudFrame:SetFrameStrata("MEDIUM")
    hudFrame:SetMovable(true)
    hudFrame:EnableMouse(true)
    hudFrame:SetClampedToScreen(true)
    hudFrame:RegisterForDrag("LeftButton")
    if type(hudFrame.SetResizable) == "function" then hudFrame:SetResizable(true) end
    if type(hudFrame.SetResizeBounds) == "function" then
        hudFrame:SetResizeBounds(110, 28, 320, 100)
    elseif type(hudFrame.SetMinResize) == "function" and type(hudFrame.SetMaxResize) == "function" then
        hudFrame:SetMinResize(110, 28)
        hudFrame:SetMaxResize(320, 100)
    end
    local background = hudFrame:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints(hudFrame)
    paint(background, 0, 0, 0, 0.66)
    createBorder(hudFrame, "TOP")
    createBorder(hudFrame, "BOTTOM")
    createBorder(hudFrame, "LEFT")
    createBorder(hudFrame, "RIGHT")
    experienceBar = CreateFrame("StatusBar", nil, hudFrame)
    experienceBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    experienceBar:SetPoint("TOPLEFT", hudFrame, "TOPLEFT", 6, -6)
    experienceBar:SetPoint("TOPRIGHT", hudFrame, "TOPRIGHT", -6, -6)
    experienceBar:SetHeight(8)
    experienceBar:SetMinMaxValues(0, 1)
    experienceBar:SetValue(0)
    experienceBar:SetStatusBarColor(0.25, 0.70, 1)
    loyaltyBar = CreateFrame("StatusBar", nil, hudFrame)
    loyaltyBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    loyaltyBar:SetPoint("BOTTOMLEFT", hudFrame, "BOTTOMLEFT", 6, 6)
    loyaltyBar:SetPoint("BOTTOMRIGHT", hudFrame, "BOTTOMRIGHT", -6, 6)
    loyaltyBar:SetHeight(8)
    loyaltyBar:SetMinMaxValues(0, 1)
    loyaltyBar:SetValue(0.5)
    loyaltyBar:SetStatusBarColor(0.45, 0.45, 0.45)
    local grip = CreateFrame("Button", nil, hudFrame)
    grip:SetSize(14, 14)
    grip:SetPoint("BOTTOMRIGHT", hudFrame, "BOTTOMRIGHT", 1, -1)
    grip:SetFrameLevel(hudFrame:GetFrameLevel() + 2)
    local gripTexture = grip:CreateTexture(nil, "OVERLAY")
    gripTexture:SetAllPoints(grip)
    gripTexture:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetNormalTexture(gripTexture)
    grip:SetScript("OnMouseDown", function(_, mouseButton)
        if mouseButton == "LeftButton" and type(hudFrame.StartSizing) == "function" then
            hudFrame:StartSizing("BOTTOMRIGHT")
        end
    end)
    grip:SetScript("OnMouseUp", function(_, mouseButton)
        if mouseButton == "LeftButton" then
            hudFrame:StopMovingOrSizing()
            saveGeometry()
        end
    end)
    hudFrame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    hudFrame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        saveGeometry()
    end)
    hudFrame:SetScript("OnEnter", showTooltip)
    hudFrame:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    packMate.Hud.ApplyGeometry()
    hudFrame:Hide()
end

function packMate.Hud.ApplyGeometry()
    if not hudFrame then return end
    local geometry = packMate.Storage.Settings().hudGeometry
    hudFrame:SetSize(geometry.width, geometry.height)
    hudFrame:ClearAllPoints()
    hudFrame:SetPoint("CENTER", UIParent, "CENTER", geometry.x, geometry.y)
end

function packMate.Hud.Render(model)
    if not hudFrame then return end
    tooltipModel = model
    if not model or not model.petName or not packMate.Storage.Settings().desiredHudVisibility then
        hudFrame:Hide()
        return
    end
    local happiness = model.happiness
    local color = happiness and happiness.availabilityState == "AVAILABLE"
        and moodColors[happiness.value] or moodColors.unknown
    for _, border in ipairs(borderTextures) do paint(border, color[1], color[2], color[3], 1) end
    if model.experience and model.experience.availabilityState == "AVAILABLE" then
        experienceBar:SetMinMaxValues(0, model.experience.required)
        experienceBar:SetValue(model.experience.current)
        experienceBar:SetStatusBarColor(0.25, 0.70, 1)
    else
        experienceBar:SetMinMaxValues(0, 1)
        experienceBar:SetValue(0)
        experienceBar:SetStatusBarColor(0.40, 0.40, 0.40)
    end
    loyaltyBar:SetMinMaxValues(0, 1)
    loyaltyBar:SetValue(0.5)
    loyaltyBar:SetStatusBarColor(0.45, 0.45, 0.45)
    hudFrame:Show()
end

function packMate.Hud.Hide()
    if hudFrame then hudFrame:Hide() end
end
