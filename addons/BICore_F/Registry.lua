-- BICore_F Registry.lua | 0.1.0-dev.1
-- Catalog and opt-in discovery only. No other addon is loaded or modified.
local addonIdentifier, addonNamespace = ...
local registry = {}
addonNamespace.Registry = registry

local descriptorsByIdentifier = {}
local descriptorOrder = {}
local maximumDescriptors = 64
local builtinDescriptors = {
    {"PackMate_F", "PackMate", "PackMate_GetBeestwoodDiagnosticSnapshot"},
    {"Litterbug_F", "Litterbug", "Litterbug_GetBeestwoodDiagnosticSnapshot"},
    {"LootHoarder_F", "LootHoarder", "LootHoarder_GetBeestwoodDiagnosticSnapshot"},
    {"ResourceHog_F", "ResourceHog", "ResourceHog_GetBeestwoodDiagnosticSnapshot"},
    {"Goblinomicon_F", "Goblinomicon", "Goblinomicon_GetBeestwoodDiagnosticSnapshot"},
    {"BodyCount_F", "BodyCount (parked)", "BodyCount_GetBeestwoodDiagnosticSnapshot"},
    {"Completionist_F", "Completionist", nil},
    {"KitMan_F", "KitMan", nil},
}

local function isSafeIdentifier(value)
    return type(value) == "string" and #value >= 2 and #value <= 64
        and value:match("^[A-Za-z][A-Za-z0-9_%-]*$") ~= nil
end

local function isSafeDisplayName(value)
    return type(value) == "string" and #value >= 2 and #value <= 48
        and value:match("^[A-Za-z0-9 _%-]+$") ~= nil
end

local function isSafeExportName(value)
    return type(value) == "string" and #value <= 96
        and value:match("^[A-Za-z][A-Za-z0-9_]*_GetBeestwoodDiagnosticSnapshot$") ~= nil
end

for _, builtin in ipairs(builtinDescriptors) do
    local descriptor = {
        addonIdentifier = builtin[1], displayName = builtin[2],
        providerExport = builtin[3], builtin = true,
    }
    descriptorsByIdentifier[descriptor.addonIdentifier] = descriptor
    descriptorOrder[#descriptorOrder + 1] = descriptor
end

-- Register accepts an explicit, versioned descriptor. A caller cannot replace a
-- different addon's existing provider; registration is not a security boundary.
function registry.Register(candidate)
    if type(candidate) ~= "table" or candidate.protocolVersion ~= "BI-REG-1"
        or not isSafeIdentifier(candidate.addonIdentifier)
        or not isSafeDisplayName(candidate.displayName) then
        return false, "INVALID_REGISTRATION"
    end
    if candidate.providerFunction ~= nil and type(candidate.providerFunction) ~= "function" then
        return false, "INVALID_PROVIDER"
    end
    if candidate.providerExport ~= nil and not isSafeExportName(candidate.providerExport) then
        return false, "INVALID_EXPORT"
    end
    local existing = descriptorsByIdentifier[candidate.addonIdentifier]
    if existing and existing.registered then
        return false, "DUPLICATE_REGISTRATION"
    end
    if not existing and #descriptorOrder >= maximumDescriptors then
        return false, "REGISTRY_FULL"
    end
    if not existing then
        existing = {addonIdentifier = candidate.addonIdentifier}
        descriptorsByIdentifier[candidate.addonIdentifier] = existing
        descriptorOrder[#descriptorOrder + 1] = existing
    end
    existing.displayName = candidate.displayName
    existing.providerCallback = candidate.providerFunction
    existing.providerExport = candidate.providerExport or existing.providerExport
    existing.registered = true
    return true, "REGISTERED"
end

-- GetAddOnInfo has changed shape across clients. Never infer a loaded addon
-- from metadata alone; only a positive IsAddOnLoaded permits provider calls.
local function getAddonInfo(addonNameOrIndex)
    local function query()
        if type(C_AddOns) == "table" and type(C_AddOns.GetAddOnInfo) == "function" then
            return C_AddOns.GetAddOnInfo(addonNameOrIndex)
        end
        if type(GetAddOnInfo) == "function" then
            return GetAddOnInfo(addonNameOrIndex)
        end
    end
    local successful, first, second = pcall(query)
    if not successful then return nil end
    if type(first) == "table" then return first.name, true end
    if type(first) == "string" then return first, true end
    if type(second) == "string" then return second, true end
    return nil
end

local function getAddonMetadata(targetIdentifier, field)
    local function query()
        if type(C_AddOns) == "table" and type(C_AddOns.GetAddOnMetadata) == "function" then
            return C_AddOns.GetAddOnMetadata(targetIdentifier, field)
        end
        if type(GetAddOnMetadata) == "function" then
            return GetAddOnMetadata(targetIdentifier, field)
        end
    end
    local successful, value = pcall(query)
    if successful and type(value) == "string" then return value end
    return nil
end

-- Metadata opt-in allows future addons to join without a Core source update,
-- even when they loaded before Core. It never executes a discovered function.
function registry.DiscoverMetadata()
    local function countAddons()
        if type(C_AddOns) == "table" and type(C_AddOns.GetNumAddOns) == "function" then
            return C_AddOns.GetNumAddOns()
        end
        if type(GetNumAddOns) == "function" then return GetNumAddOns() end
    end
    local successful, count = pcall(countAddons)
    if not successful or type(count) ~= "number" or count < 0 then return end
    for addonIndex = 1, math.min(count, 512) do
        local name = getAddonInfo(addonIndex)
        if isSafeIdentifier(name) and not (descriptorsByIdentifier[name] and descriptorsByIdentifier[name].registered) then
            local protocol = getAddonMetadata(name, "X-BICore-Registration")
            local displayName = getAddonMetadata(name, "X-BICore-Name")
            local exportName = getAddonMetadata(name, "X-BICore-Provider")
            if protocol == "BI-REG-1" and isSafeDisplayName(displayName)
                and isSafeExportName(exportName) then
                registry.Register({
                    protocolVersion = protocol, addonIdentifier = name,
                    displayName = displayName, providerExport = exportName,
                })
            end
        end
    end
end

function registry.GetDescriptors()
    return descriptorOrder
end

function registry.GetDescriptor(targetIdentifier)
    return descriptorsByIdentifier[targetIdentifier]
end

-- A negative loaded query is not a failure. Unknown API results remain gray.
function registry.GetLoadState(targetIdentifier)
    local function queryLoaded()
        if type(C_AddOns) == "table" and type(C_AddOns.IsAddOnLoaded) == "function" then
            return C_AddOns.IsAddOnLoaded(targetIdentifier)
        end
        if type(IsAddOnLoaded) == "function" then return IsAddOnLoaded(targetIdentifier) end
    end
    local successful, loaded = pcall(queryLoaded)
    if successful and loaded == true then return "LOADED", "ADDON_LOADED" end
    if not successful or type(loaded) ~= "boolean" then
        return "UNKNOWN", "LOAD_STATE_UNKNOWN"
    end
    local discoveredName = getAddonInfo(targetIdentifier)
    if not discoveredName then return "NOT_INSTALLED", "ADDON_NOT_INSTALLED" end
    local function queryEnableState()
        if type(C_AddOns) == "table" and type(C_AddOns.GetAddOnEnableState) == "function" then
            return C_AddOns.GetAddOnEnableState(targetIdentifier)
        end
        if type(GetAddOnEnableState) == "function" then
            return GetAddOnEnableState(nil, targetIdentifier)
        end
    end
    local enableSuccess, enableState = pcall(queryEnableState)
    if enableSuccess and enableState == 0 then return "DISABLED", "ADDON_DISABLED" end
    return "NOT_LOADED", "ADDON_NOT_LOADED"
end

function registry.ResolveProvider(descriptor)
    if type(descriptor.providerCallback) == "function" then
        return descriptor.providerCallback
    end
    if isSafeExportName(descriptor.providerExport) then
        local candidate = _G[descriptor.providerExport]
        if type(candidate) == "function" then return candidate end
    end
    return nil
end
