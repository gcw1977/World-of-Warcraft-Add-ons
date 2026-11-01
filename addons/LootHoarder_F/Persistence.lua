-- Separate Forever-only character data. Never reads Classic SavedVariables.
local addon = LootHoarderForever
local validHumorModes = {}
for _, humorMode in ipairs(addon.humorModes) do
    validHumorModes[string.lower(humorMode)] = humorMode
end
function addon.InitializePersistence()
    if type(LootHoarderForeverDB) ~= "table" then
        LootHoarderForeverDB = { schemaVersion = addon.schemaVersion, characters = {} }
    end
    local database = LootHoarderForeverDB
    if database.schemaVersion ~= addon.schemaVersion or type(database.characters) ~= "table" then
        addon.RecordDiagnostic("incompatible_database")
        addon.persistenceAvailable = false
        return false
    end
    local realmName = type(GetRealmName) == "function" and GetRealmName() or nil
    local characterName = type(UnitName) == "function" and UnitName("player") or nil
    if type(realmName) ~= "string" or realmName == ""
        or type(characterName) ~= "string" or characterName == "" then
        addon.RecordDiagnostic("character_identity_unavailable")
        addon.persistenceAvailable = false
        return false
    end
    local characterKey = realmName .. ":" .. characterName
    local characterRecord = database.characters[characterKey]
    if characterRecord == nil then
        characterRecord = { categoryTotals = {}, totalUnits = 0, announcedMilestones = {}, humorMode = "Silent" }
        database.characters[characterKey] = characterRecord
    end
    if type(characterRecord) ~= "table"
        or type(characterRecord.categoryTotals) ~= "table"
        or type(characterRecord.totalUnits) ~= "number"
        or type(characterRecord.announcedMilestones) ~= "table" then
        addon.RecordDiagnostic("character_record_invalid")
        addon.persistenceAvailable = false
        return false
    end
    if not validHumorModes[string.lower(tostring(characterRecord.humorMode))] then
        characterRecord.humorMode = "Silent"
    end
    addon.characterKey = characterKey
    addon.characterRecord = characterRecord
    addon.persistenceAvailable = true
    return true
end
function addon.SetHumorMode(requestedMode)
    if not addon.persistenceAvailable then return false end
    local normalizedMode = string.lower(tostring(requestedMode or ""))
    local acceptedMode = validHumorModes[normalizedMode]
    if not acceptedMode then return false end
    addon.characterRecord.humorMode = acceptedMode
    return true
end
function addon.RecordConfirmedAcquisition(categoryName, acquiredUnits)
    if not addon.persistenceAvailable then return false end
    if type(acquiredUnits) ~= "number" or acquiredUnits < 1
        or acquiredUnits ~= math.floor(acquiredUnits) then
        addon.RecordDiagnostic("invalid_acquisition_quantity")
        return false
    end
    local isKnownCategory = false
    for _, configuredCategory in ipairs(addon.categoryNames) do
        if categoryName == configuredCategory then isKnownCategory = true; break end
    end
    if not isKnownCategory then categoryName = "Other" end
    local characterRecord = addon.characterRecord
    local previousCategoryTotal = characterRecord.categoryTotals[categoryName] or 0
    local previousOverallTotal = characterRecord.totalUnits
    characterRecord.categoryTotals[categoryName] = previousCategoryTotal + acquiredUnits
    characterRecord.totalUnits = previousOverallTotal + acquiredUnits
    if type(addon.EvaluateMilestones) == "function" then
        addon.EvaluateMilestones("total", previousOverallTotal, characterRecord.totalUnits)
        addon.EvaluateMilestones(categoryName, previousCategoryTotal, characterRecord.categoryTotals[categoryName])
    end
    if type(addon.RefreshWindow) == "function" then addon.RefreshWindow() end
    return true
end
