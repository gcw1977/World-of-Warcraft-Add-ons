-- Goblinomicon Classic 0.0.1-dev.3 - account schema and append-only ledger.
-- SavedVariables are only serialized by the WoW client on reload/logout; they are
-- not an independently durable database. Never invent transactions for downtime.
local addonName, addon = ...
addon.version = "0.0.1-dev.4"
addon.schemaVersion = 1
addon.safeMode = false
addon.lastErrorCode = nil
addon.characterKey = nil
addon.characterData = nil
addon.indexCache = {}
addon.summaryCache = {}
addon.sessionContinued = false

local function IsCopper(value)
    return type(value) == "number" and value == value and
        value >= 0 and value < 9007199254740992 and value == math.floor(value)
end
addon.IsCopper = IsCopper

local function CurrentTimestamp()
    if type(GetServerTime) == "function" then
        local success, value = pcall(GetServerTime)
        if success and IsCopper(value) then return value, "SERVER" end
    end
    if type(time) == "function" then
        local success, value = pcall(time)
        if success and IsCopper(value) then return value, "FALLBACK" end
    end
    return nil, "UNKNOWN"
end
addon.CurrentTimestamp = CurrentTimestamp

function addon.NoteError(errorCode)
    addon.lastErrorCode = errorCode
end

-- Do not overwrite unknown or damaged saved data: the owner must recover a copy.
function addon.InitializeSavedData()
    local existing = GoblinomiconClassicAccountData
    if existing == nil then
        existing = {schemaVersion = addon.schemaVersion, characters = {},
            nextSessionNumber = 1, displaySettings = {period = "LIFETIME"}}
        GoblinomiconClassicAccountData = existing
    elseif type(existing) ~= "table" or existing.schemaVersion ~= addon.schemaVersion
        or type(existing.characters) ~= "table"
        or (existing.nextSessionNumber ~= nil and not IsCopper(existing.nextSessionNumber)) then
        addon.safeMode = true
        addon.NoteError("UNSUPPORTED_OR_DAMAGED_SAVED_SCHEMA")
        return false
    end
    addon.accountData = existing
    return true
end

-- Verify append-only arithmetic before accepting new writes to an existing ledger.
-- This is an O(N) startup check; very large histories require owner performance testing.
function addon.VerifyCharacter(characterData)
    if type(characterData) ~= "table" or type(characterData.transactions) ~= "table"
        or type(characterData.epochs) ~= "table" or #characterData.epochs == 0
        or not IsCopper(characterData.lastCommittedBalanceCopper)
        or not IsCopper(characterData.nextSequenceNumber) then
        return false, "CHARACTER_SCHEMA_INVALID"
    end
    local expectedBalances = {}
    for epochIndex, epoch in ipairs(characterData.epochs) do
        if type(epoch) ~= "table" or epoch.id ~= epochIndex
            or not IsCopper(epoch.openingBalanceCopper)
            or not IsCopper(epoch.lastBalanceCopper) then
            return false, "EPOCH_INVALID"
        end
        expectedBalances[epochIndex] = epoch.openingBalanceCopper
    end
    local previousSequence, previousEpochId = 0, 0
    for _, transaction in ipairs(characterData.transactions) do
        if type(transaction) ~= "table" or transaction.sequence ~= previousSequence + 1
            or not IsCopper(transaction.beforeCopper) or not IsCopper(transaction.afterCopper)
            or type(transaction.deltaCopper) ~= "number" or transaction.deltaCopper == 0
            or transaction.afterCopper - transaction.beforeCopper ~= transaction.deltaCopper
            or type(transaction.epochId) ~= "number"
            or transaction.epochId < previousEpochId
            or not expectedBalances[transaction.epochId]
            or transaction.beforeCopper ~= expectedBalances[transaction.epochId] then
            return false, "TRANSACTION_INTEGRITY_INVALID"
        end
        expectedBalances[transaction.epochId] = transaction.afterCopper
        previousSequence = transaction.sequence
        previousEpochId = transaction.epochId
    end
    for epochIndex, epoch in ipairs(characterData.epochs) do
        if expectedBalances[epochIndex] ~= epoch.lastBalanceCopper then
            return false, "EPOCH_BALANCE_INVALID"
        end
    end
    if characterData.nextSequenceNumber ~= previousSequence + 1 then
        return false, "SEQUENCE_COUNTER_INVALID"
    end
    local lastEpoch = characterData.epochs[#characterData.epochs]
    if lastEpoch and characterData.lastCommittedBalanceCopper ~= lastEpoch.lastBalanceCopper then
        return false, "CHECKPOINT_INVALID"
    end
    return true
end

local function OpenEpoch(characterData, openingCopper, reason, gapBeforeCopper)
    local timestamp = CurrentTimestamp()
    local epoch = {id = #characterData.epochs + 1, openingBalanceCopper = openingCopper,
        lastBalanceCopper = openingCopper, openedAt = timestamp, reason = reason,
        gapBeforeCopper = gapBeforeCopper}
    table.insert(characterData.epochs, epoch)
    characterData.lastCommittedBalanceCopper = openingCopper
end

-- Resolve stable identity ONLY by GUID. Never merge records by name or realm.
function addon.SelectCharacter(playerGuid, characterName, realmName, openingCopper)
    if addon.safeMode or type(playerGuid) ~= "string" or playerGuid == ""
        or not IsCopper(openingCopper) then
        addon.NoteError("IDENTITY_OR_WALLET_UNAVAILABLE")
        return false
    end
    local characterData = addon.accountData.characters[playerGuid]
    if characterData == nil then
        characterData = {guid = playerGuid, name = characterName, realm = realmName,
            transactions = {}, epochs = {}, nextSequenceNumber = 1,
            lastCommittedBalanceCopper = openingCopper}
        addon.accountData.characters[playerGuid] = characterData
        OpenEpoch(characterData, openingCopper, "INITIAL_BASELINE")
    else
        local valid, reason = addon.VerifyCharacter(characterData)
        if not valid then
            addon.safeMode = true
            addon.NoteError(reason)
            return false
        end
        characterData.name = characterName or characterData.name
        characterData.realm = realmName or characterData.realm
        if characterData.lastCommittedBalanceCopper ~= openingCopper then
            OpenEpoch(characterData, openingCopper, "STARTUP_GAP",
                openingCopper - characterData.lastCommittedBalanceCopper)
            characterData.gapCount = (characterData.gapCount or 0) + 1
        end
    end
    addon.characterKey = playerGuid
    addon.characterData = characterData
    addon.summaryCache[playerGuid] = nil
    local session = characterData.activeSession
    if type(session) == "table" and session.reloadPending == true
        and type(session.id) == "string" then
        session.reloadPending = false
        addon.sessionContinued = true
    else
        local nextNumber = addon.accountData.nextSessionNumber or 1
        local timestamp = CurrentTimestamp()
        session = {id = playerGuid .. ":" .. tostring(nextNumber),
            startedAt = timestamp, reloadPending = false}
        characterData.activeSession = session
        addon.accountData.nextSessionNumber = nextNumber + 1
        addon.sessionContinued = false
    end
    return true
end

-- Rebase an EMPTY initial journal on explicit user confirmation only.
-- Never manufacture a credit, delete historical rows, or rewrite a nonempty journal.
function addon.ConfirmOpeningBalance()
    if addon.safeMode or not addon.characterData or not addon.accountData then
        return false, "Journal not available"
    end
    local characterData = addon.characterData
    local epochs = characterData.epochs
    local original = epochs and epochs[1]
    if not original or #epochs ~= 1 or #characterData.transactions ~= 0
        or original.reason ~= "INITIAL_BASELINE"
        or characterData.lastCommittedBalanceCopper ~= original.lastBalanceCopper
        or original.openingBalanceCopper ~= original.lastBalanceCopper
        or #addon.observer.pending > 0 then
        return false, "Only an empty, unchanged initial journal can be corrected"
    end
    local valid, errorCode = addon.VerifyCharacter(characterData)
    if not valid then return false, errorCode end
    local currentlyObserved = addon.ReadWallet()
    if currentlyObserved == nil then return false, "Wallet unavailable" end
    if currentlyObserved == original.openingBalanceCopper then
        return false, "Opening balance already matches wallet"
    end
    local timestamp = addon.CurrentTimestamp()
    original.originalUnconfirmedOpeningCopper = original.openingBalanceCopper
    original.correctedAt = timestamp
    original.reason = "OWNER_CONFIRMED_INITIAL_BASELINE"
    original.openingBalanceCopper = currentlyObserved
    original.lastBalanceCopper = currentlyObserved
    characterData.lastCommittedBalanceCopper = currentlyObserved
    addon.observer.lastObservedCopper = currentlyObserved
    addon.indexCache[addon.characterKey] = nil
    addon.summaryCache[addon.characterKey] = nil
    return true, "Opening balance set to the current wallet; no income recorded"
end

-- Called at logout. ReloadUI is hooked separately; a missing hook means a
-- reload may be treated as a new session, which must be checked in Classic.
function addon.EndSession(isReload)
    if not addon.characterData then return end
    local session = addon.characterData.activeSession
    if type(session) ~= "table" then return end
    if isReload then
        session.reloadPending = true
    else
        addon.characterData.activeSession = nil
    end
end

-- Only this function appends financial records. A failed write freezes further
-- mutation rather than silently losing or reordering observed money changes.
function addon.AppendTransaction(candidate, category, confidence)
    if addon.safeMode or not addon.characterData then return false, "READ_ONLY" end
    local characterData = addon.characterData
    if candidate.beforeCopper ~= characterData.lastCommittedBalanceCopper
        or not IsCopper(candidate.afterCopper)
        or candidate.afterCopper == candidate.beforeCopper then
        addon.NoteError("OBSERVATION_CHAIN_MISMATCH")
        return false, "OBSERVATION_CHAIN_MISMATCH"
    end
    local epoch = characterData.epochs[#characterData.epochs]
    if not epoch then return false, "EPOCH_MISSING" end
    local record = {sequence = characterData.nextSequenceNumber, epochId = epoch.id,
        sessionId = characterData.activeSession and characterData.activeSession.id or "UNKNOWN",
        timestamp = candidate.timestamp, timestampQuality = candidate.timestampQuality,
        beforeCopper = candidate.beforeCopper, afterCopper = candidate.afterCopper,
        deltaCopper = candidate.afterCopper - candidate.beforeCopper,
        category = category, confidence = confidence}
    local success = pcall(table.insert, characterData.transactions, record)
    if not success then
        addon.safeMode = true
        addon.NoteError("JOURNAL_APPEND_FAILED")
        return false, "JOURNAL_APPEND_FAILED"
    end
    -- These are simple assignments after successful append. The journal itself
    -- remains authoritative; derived indexes are disposable and rebuilt.
    characterData.nextSequenceNumber = record.sequence + 1
    characterData.lastCommittedBalanceCopper = record.afterCopper
    epoch.lastBalanceCopper = record.afterCopper
    addon.indexCache[addon.characterKey] = nil
    addon.summaryCache[addon.characterKey] = nil
    return true
end

-- Read-only summary; baseline wealth is deliberately excluded from income.
function addon.GetTotals(characterData, sessionOnly)
    local activeSessionId = characterData.activeSession and characterData.activeSession.id
    if sessionOnly and (characterData ~= addon.characterData or not activeSessionId) then
        return nil
    end
    local characterKey = characterData.guid
    local cacheKey = sessionOnly and ("SESSION:" .. activeSessionId) or "LIFETIME"
    local characterCache = addon.summaryCache[characterKey] or {}
    if characterCache[cacheKey] then return characterCache[cacheKey] end
    local income, expenses, categories = 0, 0, {}
    local incomeCategories, expenseCategories = {}, {}
    for _, transaction in ipairs(characterData.transactions) do
        if not sessionOnly or transaction.sessionId == activeSessionId then
            local delta = transaction.deltaCopper
            local category = transaction.category or
                (delta > 0 and "Unclassified Income" or "Unclassified Expense")
            categories[category] = (categories[category] or 0) + math.abs(delta)
            if delta > 0 then
                income = income + delta
                incomeCategories[category] = (incomeCategories[category] or 0) + delta
            else
                expenses = expenses - delta
                expenseCategories[category] = (expenseCategories[category] or 0) - delta
            end
        end
    end
    local totals = {income = income, expenses = expenses,
        net = income - expenses, categories = categories,
        incomeCategories = incomeCategories, expenseCategories = expenseCategories}
    characterCache[cacheKey] = totals
    addon.summaryCache[characterKey] = characterCache
    return totals
end

-- Cache a read-only month/day index. Indexes are never authoritative ledger data.
-- Rebuild is O(N), never done per-frame; large-history load cost is untested.
function addon.GetLedgerIndex(characterKey)
    if addon.indexCache[characterKey] then return addon.indexCache[characterKey] end
    local characterData = addon.accountData.characters[characterKey]
    if not characterData then return nil end
    local index = {months = {}, monthOrder = {}}
    for transactionIndex, transaction in ipairs(characterData.transactions) do
        local monthKey, dayKey = "Unknown date", "Unknown date"
        if type(transaction.timestamp) == "number" and type(date) == "function" then
            local okMonth, monthValue = pcall(date, "%Y-%m", transaction.timestamp)
            local okDay, dayValue = pcall(date, "%Y-%m-%d", transaction.timestamp)
            if okMonth and okDay and type(monthValue) == "string"
                and type(dayValue) == "string" then
                monthKey, dayKey = monthValue, dayValue
            end
        end
        local month = index.months[monthKey]
        if not month then
            month = {key = monthKey, days = {}, dayOrder = {}, income = 0, expenses = 0}
            index.months[monthKey] = month
            table.insert(index.monthOrder, monthKey)
        end
        local day = month.days[dayKey]
        if not day then
            day = {key = dayKey, transactionIndices = {}, income = 0, expenses = 0}
            month.days[dayKey] = day
            table.insert(month.dayOrder, dayKey)
        end
        table.insert(day.transactionIndices, transactionIndex)
        if transaction.deltaCopper > 0 then
            month.income = month.income + transaction.deltaCopper
            day.income = day.income + transaction.deltaCopper
        else
            month.expenses = month.expenses - transaction.deltaCopper
            day.expenses = day.expenses - transaction.deltaCopper
        end
    end
    table.sort(index.monthOrder, function(left, right) return left > right end)
    for _, month in pairs(index.months) do
        table.sort(month.dayOrder, function(left, right) return left > right end)
    end
    addon.indexCache[characterKey] = index
    return index
end

function addon.FormatCopper(copper)
    if type(copper) ~= "number" then return "Unknown" end
    local sign = copper < 0 and "-" or "+"
    local absoluteCopper = math.abs(copper)
    local gold = math.floor(absoluteCopper / 10000)
    local silver = math.floor(absoluteCopper % 10000 / 100)
    local bronze = absoluteCopper % 100
    return string.format("%s%dg %02ds %02dc", sign, gold, silver, bronze)
end
