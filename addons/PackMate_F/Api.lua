local addonName, packMate = ...
packMate.Api = {}

local function unavailable(reasonCode, apiName)
    return {availabilityState = "UNAVAILABLE", reasonCode = reasonCode, sourceApiName = apiName}
end

local function callFirstAvailable(apiName, primaryFunction, fallbackName, fallbackFunction)
    if type(primaryFunction) == "function" then
        local success, first, second = packMate.Safe.Call(primaryFunction)
        if success then return true, first, second, apiName end
        return false, nil, nil, apiName
    end
    if type(fallbackFunction) == "function" then
        local success, first, second = packMate.Safe.Call(fallbackFunction)
        if success then return true, first, second, fallbackName end
        return false, nil, nil, fallbackName
    end
    return false, nil, nil, apiName
end

function packMate.Api.ReadIdentity()
    local successClass, _, classToken = packMate.Safe.Call(UnitClass, "player")
    if not successClass or classToken ~= "HUNTER" then return unavailable("NOT_HUNTER", "UnitClass") end
    local existsSuccess, exists = packMate.Safe.Call(UnitExists, "pet")
    if not existsSuccess or exists ~= true then return unavailable("NO_PET", "UnitExists") end
    if type(HasPetUI) == "function" then
        local hasUiSuccess, hasPetUi = packMate.Safe.Call(HasPetUI)
        if not hasUiSuccess or hasPetUi ~= true then return unavailable("PET_UI_NOT_CONFIRMED", "HasPetUI") end
    end
    local guidSuccess, petGuid = packMate.Safe.Call(UnitGUID, "pet")
    local nameSuccess, petName = packMate.Safe.Call(UnitName, "pet")
    local levelSuccess, petLevel = packMate.Safe.Call(UnitLevel, "pet")
    petGuid = guidSuccess and packMate.Safe.Text(petGuid) or nil
    petName = nameSuccess and packMate.Safe.Text(petName) or nil
    petLevel = levelSuccess and packMate.Safe.Integer(petLevel, 1, 999) or nil
    if not petGuid or not petName or not petLevel then
        return unavailable("PET_IDENTITY_UNSAFE", "UnitGUID/UnitName/UnitLevel")
    end
    return {availabilityState = "AVAILABLE", petGuid = petGuid, petName = petName, petLevel = petLevel}
end

function packMate.Api.ReadExperience()
    local success, current, required = packMate.Safe.Call(GetPetExperience)
    if not success then return unavailable("EXPERIENCE_API_ABSENT_OR_ERROR", "GetPetExperience") end
    current = packMate.Safe.Integer(current, 0, 100000000)
    required = packMate.Safe.Integer(required, 1, 100000000)
    if not current or not required or current > required then
        return unavailable("EXPERIENCE_INVALID_OR_RESTRICTED", "GetPetExperience")
    end
    return {availabilityState = "AVAILABLE", current = current, required = required, sourceApiName = "GetPetExperience"}
end

function packMate.Api.ReadHappiness()
    local namespaced = type(C_PetInfo) == "table" and C_PetInfo.GetPetHappiness or nil
    local success, value, _, source = callFirstAvailable("C_PetInfo.GetPetHappiness", namespaced, "GetPetHappiness", GetPetHappiness)
    if not success then return unavailable("HAPPINESS_API_ABSENT_OR_ERROR", source) end
    value = packMate.Safe.Integer(value, 1, 3)
    if not value then return unavailable("HAPPINESS_INVALID_OR_RESTRICTED", source) end
    return {availabilityState = "AVAILABLE", value = value, sourceApiName = source}
end

function packMate.Api.ReadLoyalty()
    local namespaced = type(C_PetInfo) == "table" and C_PetInfo.GetPetLoyalty or nil
    local success, value, _, source = callFirstAvailable("C_PetInfo.GetPetLoyalty", namespaced, "GetPetLoyalty", GetPetLoyalty)
    if not success then return unavailable("LOYALTY_API_ABSENT_OR_ERROR", source) end
    -- Loyalty APIs do not establish a validated min/max progression scale.
    -- A string description is safe to show; never infer a percentage from a label.
    local description = packMate.Safe.Text(value)
    if not description then return unavailable("LOYALTY_FORMAT_UNVERIFIED", source) end
    return {availabilityState = "AVAILABLE", description = description, sourceApiName = source}
end

function packMate.Api.ReadPoints()
    local namespaced = type(C_PetInfo) == "table" and C_PetInfo.GetPetTrainingPoints or nil
    local success, total, spent, source = callFirstAvailable("C_PetInfo.GetPetTrainingPoints", namespaced, "GetPetTrainingPoints", GetPetTrainingPoints)
    if not success then return unavailable("POINTS_API_ABSENT_OR_ERROR", source) end
    total = packMate.Safe.Integer(total, 0, 100000)
    spent = packMate.Safe.Integer(spent, 0, 100000)
    if not total or not spent or spent > total then return unavailable("POINTS_SEMANTICS_UNVERIFIED", source) end
    return {availabilityState = "AVAILABLE", availablePoints = total - spent, pointSystemKind = "TRAINING", sourceApiName = source}
end

function packMate.Api.ReadBuild()
    local result = "UNKNOWN"
    if type(GetBuildInfo) == "function" then
        local success, version, build, date, interface = packMate.Safe.Call(GetBuildInfo)
        local safeVersion = success and packMate.Safe.Text(version) or nil
        local safeInterface = success and packMate.Safe.Integer(interface, 1, 999999) or nil
        if safeVersion then result = safeVersion end
        if safeInterface then result = result .. " interface " .. tostring(safeInterface) end
    end
    return result
end
