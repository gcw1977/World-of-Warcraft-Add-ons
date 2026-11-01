local addonName, packMate = ...
local defaults = {
    desiredHudVisibility = true,
    shouldAnnouncePetExperience = true,
    happinessAnnouncementMode = "sassy",
    hudGeometry = {anchor = "CENTER", relativeAnchor = "CENTER", x = 0, y = -155, width = 155, height = 35}
}
local sessionDatabase
local activeCharacterKey
local persistenceAvailable = false
packMate.Storage = {}

local function validGeometry(geometry)
    if type(geometry) ~= "table" then return false end
    if geometry.anchor ~= "CENTER" or geometry.relativeAnchor ~= "CENTER" then return false end
    local horizontal = packMate.Safe.Integer(geometry.x, -4000, 4000)
    local vertical = packMate.Safe.Integer(geometry.y, -4000, 4000)
    local width = packMate.Safe.Integer(geometry.width, 110, 320)
    local height = packMate.Safe.Integer(geometry.height, 28, 100)
    return horizontal ~= nil and vertical ~= nil and width ~= nil and height ~= nil
end

local function copyDefaultSettings()
    return {
        desiredHudVisibility = defaults.desiredHudVisibility,
        shouldAnnouncePetExperience = defaults.shouldAnnouncePetExperience,
        happinessAnnouncementMode = defaults.happinessAnnouncementMode,
        hudGeometry = {anchor = "CENTER", relativeAnchor = "CENTER", x = 0, y = -155, width = 155, height = 35}
    }
end

local function validDatabase(database)
    if type(database) ~= "table" then return false end
    if database.schemaVersion ~= 1 or type(database.settings) ~= "table" or type(database.characters) ~= "table" then return false end
    local settings = database.settings
    if type(settings.desiredHudVisibility) ~= "boolean" or type(settings.shouldAnnouncePetExperience) ~= "boolean" then return false end
    if settings.happinessAnnouncementMode ~= "sassy" and settings.happinessAnnouncementMode ~= "stoic" and settings.happinessAnnouncementMode ~= "mute" then return false end
    if not validGeometry(settings.hudGeometry) then return false end
    for characterKey, characterRecord in pairs(database.characters) do
        if type(characterKey) ~= "string" or type(characterRecord) ~= "table" or type(characterRecord.petRecords) ~= "table" then return false end
        for petGuid, petRecord in pairs(characterRecord.petRecords) do
            if type(petGuid) ~= "string" or type(petRecord) ~= "table" or petRecord.recordSchemaVersion ~= 1 then return false end
            if not packMate.Safe.Integer(petRecord.totalObservedExperiencePoints, 0, 9007199254740991) then return false end
        end
    end
    return true
end

function packMate.Storage.Initialize()
    local existing = PackMateForeverDatabase
    if existing == nil then
        PackMateForeverDatabase = {schemaVersion = 1, settings = copyDefaultSettings(), characters = {}}
        existing = PackMateForeverDatabase
    end
    local schemaCheckSucceeded, schemaValid = pcall(validDatabase, existing)
    if schemaCheckSucceeded and schemaValid then
        sessionDatabase = existing
        persistenceAvailable = true
        packMate.Diagnostics.persistence = "PERSISTENT"
    else
        -- Preserve malformed SavedVariables untouched for owner recovery.
        sessionDatabase = {schemaVersion = 1, settings = copyDefaultSettings(), characters = {}}
        persistenceAvailable = false
        packMate.Diagnostics.persistence = "SESSION_ONLY_INVALID_SCHEMA"
        packMate.RecordDiagnostic("STORAGE", "WARN", "PRESERVED_INVALID_DATABASE")
    end
    activeCharacterKey = nil
    packMate.Storage.ResolveCharacterIdentity()
end

function packMate.Storage.ResolveCharacterIdentity()
    if activeCharacterKey then return true end
    local success, characterGuid = packMate.Safe.Call(UnitGUID, "player")
    if success then activeCharacterKey = packMate.Safe.Text(characterGuid) end
    if not activeCharacterKey then
        persistenceAvailable = false
        packMate.Diagnostics.persistence = "SESSION_ONLY_CHARACTER_ID_UNAVAILABLE"
        return false
    end
    persistenceAvailable = sessionDatabase == PackMateForeverDatabase
    packMate.Diagnostics.persistence = persistenceAvailable and "PERSISTENT" or "SESSION_ONLY_INVALID_SCHEMA"
    return true
end

function packMate.Storage.Settings()
    return sessionDatabase and sessionDatabase.settings or copyDefaultSettings()
end

function packMate.Storage.SetSetting(settingName, value)
    local settings = packMate.Storage.Settings()
    if settingName == "desiredHudVisibility" or settingName == "shouldAnnouncePetExperience" then
        if type(value) ~= "boolean" then return false end
    elseif settingName == "happinessAnnouncementMode" then
        if value ~= "sassy" and value ~= "stoic" and value ~= "mute" then return false end
    else
        return false
    end
    settings[settingName] = value
    return true
end

function packMate.Storage.SaveGeometry(geometry)
    if not validGeometry(geometry) then return false end
    packMate.Storage.Settings().hudGeometry = {
        anchor = "CENTER", relativeAnchor = "CENTER", x = geometry.x, y = geometry.y,
        width = geometry.width, height = geometry.height
    }
    return true
end

function packMate.Storage.ResetGeometry()
    packMate.Storage.Settings().hudGeometry = copyDefaultSettings().hudGeometry
    packMate.Storage.Settings().desiredHudVisibility = true
end

function packMate.Storage.GetPetTotal(petGuid)
    if not activeCharacterKey then return nil end
    local characterRecord = sessionDatabase.characters[activeCharacterKey]
    local record = characterRecord and characterRecord.petRecords[petGuid]
    return record and record.totalObservedExperiencePoints or 0
end

function packMate.Storage.AddObservedExperience(petGuid, petName, petLevel, observedGain)
    if not activeCharacterKey then return false, "CHARACTER_ID_UNAVAILABLE" end
    if not packMate.Safe.Text(petGuid) or not packMate.Safe.Text(petName) then return false, "IDENTITY_INVALID" end
    if not packMate.Safe.Integer(petLevel, 1, 999) or not packMate.Safe.Integer(observedGain, 1, 100000000) then return false, "GAIN_INVALID" end
    local characters = sessionDatabase.characters
    if not characters[activeCharacterKey] then characters[activeCharacterKey] = {petRecords = {}} end
    local petRecords = characters[activeCharacterKey].petRecords
    local previous = petRecords[petGuid]
    local previousTotal = previous and previous.totalObservedExperiencePoints or 0
    local nextTotal = packMate.Safe.Integer(previousTotal + observedGain, 0, 9007199254740991)
    if not nextTotal then return false, "TOTAL_OVERFLOW" end
    petRecords[petGuid] = {
        recordSchemaVersion = 1, petProperName = petName, lastObservedPetLevel = petLevel,
        totalObservedExperiencePoints = nextTotal
    }
    if not persistenceAvailable then return false, "SESSION_ONLY_NOT_PERSISTED" end
    return true, "COMMITTED"
end

function packMate.Storage.PersistenceStatus()
    return packMate.Diagnostics.persistence
end
