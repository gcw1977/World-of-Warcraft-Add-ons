-- BICore_F Main.lua | 0.1.0-dev.1
-- Entry points are opt-in and do not modify or load other addons.
local addonIdentifier, addonNamespace = ...
local registry = addonNamespace.Registry
local dashboard = addonNamespace.Dashboard

-- Other addons may call this when BI Core is already loaded. They MUST NOT
-- depend on its existence; the TOC metadata discovery path covers earlier loads.
_G.BICore_RegisterAddon = function(descriptor)
    local successful, accepted, reason = pcall(registry.Register, descriptor)
    if not successful then return false, "INVALID_REGISTRATION" end
    if accepted and dashboard.IsVisible() then dashboard.RefreshSummaries() end
    return accepted, reason
end

SLASH_BICORE1 = "/bicore"
SlashCmdList.BICORE = function(commandText)
    local command = type(commandText) == "string" and commandText:lower():match("^%s*(.-)%s*$") or ""
    if command == "" or command == "show" then
        dashboard.Open()
    elseif command == "hide" then
        dashboard.Close()
    elseif command == "refresh" then
        if dashboard.IsVisible() then dashboard.Refresh() else dashboard.Open() end
    elseif command == "reset" then
        dashboard.ResetPosition()
        if DEFAULT_CHAT_FRAME then
            DEFAULT_CHAT_FRAME:AddMessage("BI Core: window position reset.")
        end
    elseif DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage("BI Core: /bicore [show|hide|refresh|reset]")
    end
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:SetScript("OnEvent", function(self, eventName, loadedAddonIdentifier)
    if eventName == "ADDON_LOADED" then
        if loadedAddonIdentifier == addonIdentifier then
            if type(BICoreForeverDB) ~= "table" then
                BICoreForeverDB = {schemaVersion=1}
            end
        end
        dashboard.OnAddonLoaded(loadedAddonIdentifier)
    end
end)
