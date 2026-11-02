-- Goblinomicon Forever: GUID partitioning, non-destructive validation and login sessions.
local Addon = GoblinomiconForever
Addon.Persistence = {}
local Persistence = Addon.Persistence

local function IsPositiveInteger(value)
    return type(value) == "number" and value > 0 and value < math.huge
        and value == math.floor(value)
end

-- Fail closed on an unsupported/corrupt database; never replace existing user history.
function Persistence.Load()
    local stored = GoblinomiconForeverDB
    if stored == nil then
        stored = { schemaVersion = 1, productLine = "Forever", characters = {},
            uiPreferences = { period = "LIFETIME" }, createdAt = Addon.Now() }
        GoblinomiconForeverDB = stored
    elseif type(stored) ~= "table" or stored.schemaVersion ~= 1
        or stored.productLine ~= "Forever" or type(stored.characters) ~= "table" then
        Addon.runtime.captureStatus = "QUARANTINED"
        Addon.Note("FAIL", "Persistence", "UNSUPPORTED_OR_CORRUPT_ROOT")
        return nil, "UNSUPPORTED_OR_CORRUPT_ROOT"
    end
    for characterGuid, character in pairs(stored.characters) do
        if type(characterGuid) ~= "string" or type(character) ~= "table"
            or type(character.identity) ~= "table"
            or character.identity.guid ~= characterGuid
            or type(character.movements) ~= "table"
            or type(character.sessions) ~= "table"
            or type(character.annotations) ~= "table"
            or not IsPositiveInteger(character.nextSequence) then
            Addon.runtime.captureStatus = "QUARANTINED"
            Addon.Note("FAIL", "Persistence", "INVALID_CHARACTER_SCHEMA")
            return nil, "INVALID_CHARACTER_SCHEMA"
        end
        local expected = character.opening and character.opening.copper or nil
        if expected ~= nil and not Addon.ValidCopper(expected) then
            Addon.runtime.captureStatus = "QUARANTINED"
            return nil, "INVALID_OPENING_BALANCE"
        end
        for _, session in ipairs(character.sessions) do
            if type(session) ~= "table" or type(session.id) ~= "string"
                or not IsPositiveInteger(session.startSequence) then
                Addon.runtime.captureStatus = "QUARANTINED"
                return nil, "INVALID_SESSION_SCHEMA"
            end
        end
        for _, annotation in ipairs(character.annotations) do
            if type(annotation) ~= "table" or not IsPositiveInteger(annotation.sequence)
                or type(annotation.category) ~= "string"
                or type(annotation.confidence) ~= "string" then
                Addon.runtime.captureStatus = "QUARANTINED"
                return nil, "INVALID_ANNOTATION_SCHEMA"
            end
        end
        for sequence, movement in ipairs(character.movements) do
            if type(movement) ~= "table" or movement.sequence ~= sequence
                or not Addon.ValidCopper(movement.beforeCopper)
                or not Addon.ValidSignedCopper(movement.deltaCopper)
                or not Addon.ValidCopper(movement.afterCopper)
                or expected == nil or movement.beforeCopper ~= expected
                or movement.afterCopper ~= expected + movement.deltaCopper then
                Addon.runtime.captureStatus = "QUARANTINED"
                Addon.Note("FAIL", "Persistence", "LEDGER_CHAIN_INVALID")
                return nil, "LEDGER_CHAIN_INVALID"
            end
            expected = movement.afterCopper
        end
        if character.nextSequence ~= #character.movements + 1
            or (expected ~= nil and character.lastCopper ~= expected)
            or (expected == nil and character.lastCopper ~= nil) then
            Addon.runtime.captureStatus = "QUARANTINED"
            return nil, "LEDGER_CURSOR_INVALID"
        end
    end
    if type(stored.uiPreferences) ~= "table" then stored.uiPreferences = { period = "LIFETIME" } end
    Persistence.database = stored
    return stored
end

-- GUID is authoritative. Name/realm are labels, never fallback partition keys.
function Persistence.ResolveIdentity()
    if type(UnitGUID) ~= "function" then return nil, "GUID_API_UNAVAILABLE" end
    local ok, guid = pcall(UnitGUID, "player")
    if not ok or not Addon.IsAccessible(guid) or type(guid) ~= "string" or guid == "" then
        return nil, "GUID_UNAVAILABLE"
    end
    local characterName = "Unknown"
    local realmName = "Unknown"
    if type(UnitName) == "function" then
        local nameOk, name = pcall(UnitName, "player")
        if nameOk and Addon.IsAccessible(name) and type(name) == "string" then characterName = name end
    end
    if type(GetRealmName) == "function" then
        local realmOk, realm = pcall(GetRealmName)
        if realmOk and Addon.IsAccessible(realm) and type(realm) == "string" then realmName = realm end
    end
    return { guid = guid, name = characterName, realm = realmName }
end

function Persistence.EnsureCharacter(identity)
    if not Persistence.database or type(identity) ~= "table" or type(identity.guid) ~= "string" then
        return nil, "IDENTITY_UNAVAILABLE"
    end
    local character = Persistence.database.characters[identity.guid]
    if not character then
        character = { identity = { guid = identity.guid, name = identity.name, realm = identity.realm },
            movements = {}, annotations = {}, sessions = {}, nextSequence = 1,
            lastCopper = nil, opening = nil, sessionCounter = 0 }
        Persistence.database.characters[identity.guid] = character
    else
        character.identity.name = identity.name
        character.identity.realm = identity.realm
    end
    return character
end

-- PLAYER_LOGOUT also occurs during /reload. A pending close is resumed only if
-- PLAYER_ENTERING_WORLD explicitly confirms same-character UI reload.
function Persistence.OpenSession(character, characterGuid, isReloadingUi)
    local active = character.activeSessionId
    if isReloadingUi == true and type(active) == "string" then
        for _, session in ipairs(character.sessions) do
            if session.id == active and session.pendingCloseAt then
                session.pendingCloseAt = nil
                session.endedAt = nil
                Addon.runtime.currentSessionId = active
                return active
            end
        end
    end
    if active then
        for _, session in ipairs(character.sessions) do
            if session.id == active and not session.endedAt then
                session.endedAt = session.pendingCloseAt or Addon.Now() or session.startedAt
                session.pendingCloseAt = nil
            end
        end
    end
    character.sessionCounter = (character.sessionCounter or 0) + 1
    local sessionId = characterGuid .. ":" .. tostring(character.sessionCounter)
    local session = { id = sessionId, startedAt = Addon.Now(), startSequence = character.nextSequence }
    character.sessions[#character.sessions + 1] = session
    character.activeSessionId = sessionId
    Addon.runtime.currentSessionId = sessionId
    return sessionId
end

function Persistence.MarkLogout()
    local character = Persistence.GetCurrentCharacter()
    if not character then return end
    for _, session in ipairs(character.sessions) do
        if session.id == character.activeSessionId and not session.endedAt then
            session.pendingCloseAt = Addon.Now() or session.startedAt
            return
        end
    end
end

function Persistence.GetCurrentCharacter()
    if not Persistence.database or not Addon.runtime.currentGuid then return nil end
    return Persistence.database.characters[Addon.runtime.currentGuid]
end

function Persistence.ListCharacters()
    local result = {}
    if not Persistence.database then return result end
    for guid, character in pairs(Persistence.database.characters) do
        result[#result + 1] = { guid = guid,
            label = (character.identity.name or "Unknown") .. " - " .. (character.identity.realm or "Unknown") }
    end
    table.sort(result, function(left, right) return left.label < right.label end)
    return result
end
