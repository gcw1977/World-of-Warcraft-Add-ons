-- Goblinomicon Forever: only this module commits monetary movements.
local Addon = GoblinomiconForever
Addon.Ledger = {}
local Ledger = Addon.Ledger
-- Disposable caches never replace or delete the canonical append-only rows.
Ledger.statsCache = setmetatable({}, { __mode = "k" })
Ledger.indexCache = setmetatable({}, { __mode = "k" })
Ledger.integrityCache = setmetatable({}, { __mode = "k" })

local function Accumulate(result, movement, category)
    local delta = movement.deltaCopper
    local entry = result.categories[category]
    if not entry then
        entry = { amount = 0, count = 0, sign = delta > 0 and "CREDIT" or "DEBIT" }
        result.categories[category] = entry
    end
    entry.amount = entry.amount + math.abs(delta)
    entry.count = entry.count + 1
    if delta > 0 then result.credits = result.credits + delta
    else result.debits = result.debits - delta end
    result.count = result.count + 1
end

local function UpdateIndex(index, movement)
    local monthKey = Addon.DateLabel(movement.at, "%Y-%m")
    local dayKey = Addon.DateLabel(movement.at, "%Y-%m-%d")
    local month = index.months[monthKey]
    if not month then
        month = { key = monthKey, days = {}, dayOrder = {}, count = 0 }
        index.months[monthKey] = month
        index.monthOrder[#index.monthOrder + 1] = monthKey
        table.sort(index.monthOrder, function(left, right) return left > right end)
    end
    local day = month.days[dayKey]
    if not day then
        day = { key = dayKey, sequences = {} }
        month.days[dayKey] = day
        month.dayOrder[#month.dayOrder + 1] = dayKey
        table.sort(month.dayOrder, function(left, right) return left > right end)
    end
    day.sequences[#day.sequences + 1] = movement.sequence
    month.count = month.count + 1
end

function Ledger.CaptureOpening(character, copper, timestamp)
    if character.opening then return false, "BASELINE_EXISTS" end
    if not Addon.ValidCopper(copper) then return nil, "INVALID_BALANCE" end
    character.opening = { copper = copper, at = timestamp, source = "GetMoney" }
    character.lastCopper = copper
    return true
end

-- A single observed snapshot transition may combine several underlying actions.
-- Commit immutable movement first; update cursor only after the row is inserted.
function Ledger.Append(character, afterCopper, trigger, isGap)
    if not character or not character.opening or not Addon.ValidCopper(afterCopper)
        or not Addon.ValidCopper(character.lastCopper) then
        return nil, "INVALID_LEDGER_STATE"
    end
    local beforeCopper = character.lastCopper
    local deltaCopper = afterCopper - beforeCopper
    if deltaCopper == 0 then return false end
    if not Addon.ValidSignedCopper(deltaCopper)
        or character.nextSequence ~= #character.movements + 1 then
        return nil, "LEDGER_INVARIANT"
    end
    local sequence = character.nextSequence
    local observedAt = Addon.Now()
    local category, confidence, evidence = Addon.Attribution.Resolve(deltaCopper, observedAt, isGap)
    local movement = { sequence = sequence, at = observedAt, beforeCopper = beforeCopper,
        deltaCopper = deltaCopper, afterCopper = afterCopper, category = category,
        confidence = confidence, evidence = evidence, trigger = trigger,
        sessionId = Addon.runtime.currentSessionId or "UNKNOWN",
        isGap = isGap == true }
    character.movements[sequence] = movement
    character.nextSequence = sequence + 1
    character.lastCopper = afterCopper
    character.lastObservedAt = observedAt
    character.indexRevision = (character.indexRevision or 0) + 1
    local cachedIndex = Ledger.indexCache[character]
    if cachedIndex and cachedIndex.count == sequence - 1 then
        UpdateIndex(cachedIndex.index, movement)
        cachedIndex.count = sequence
    end
    local cachedStatistics = Ledger.statsCache[character]
    if cachedStatistics then
        for _, cached in pairs(cachedStatistics) do
            if cached.movementCount == sequence - 1
                and cached.annotationRevision == (character.annotationRevision or 0) then
                if cached.period == "LIFETIME" or cached.sessionId == movement.sessionId then
                    Accumulate(cached.result, movement, movement.category)
                end
                cached.movementCount = sequence
            else
                cached.movementCount = -1
            end
        end
    end
    local integrityCache = Ledger.integrityCache[character]
    if integrityCache and integrityCache.valid and integrityCache.count == sequence - 1 then
        integrityCache.count = sequence
        integrityCache.after = afterCopper
        integrityCache.nextSequence = character.nextSequence
    end
    return sequence
end

function Ledger.Observe(character, walletCopper, trigger, reconciliation)
    if not character.opening then
        return Ledger.CaptureOpening(character, walletCopper, Addon.Now())
    end
    return Ledger.Append(character, walletCopper, trigger,
        reconciliation == true and walletCopper ~= character.lastCopper)
end

-- Read-only validation. Never silently repair or reset an inconsistent chain.
function Ledger.Verify(character, force)
    if not character or type(character.movements) ~= "table" then return false, "NO_LEDGER" end
    local cached = Ledger.integrityCache[character]
    if force ~= true and cached and cached.count == #character.movements
        and cached.after == character.lastCopper and cached.nextSequence == character.nextSequence then
        return cached.valid, cached.reason
    end
    local expected = character.opening and character.opening.copper
    if expected == nil then
        if #character.movements == 0 and character.lastCopper == nil then return true, "NO_BASELINE" end
        return false, "MISSING_BASELINE"
    end
    for index, movement in ipairs(character.movements) do
        if movement.sequence ~= index or movement.beforeCopper ~= expected
            or not Addon.ValidSignedCopper(movement.deltaCopper)
            or movement.afterCopper ~= expected + movement.deltaCopper then
            return false, "CHAIN_MISMATCH_AT_" .. tostring(index)
        end
        expected = movement.afterCopper
    end
    if character.lastCopper ~= expected or character.nextSequence ~= #character.movements + 1 then
        return false, "CURSOR_MISMATCH"
    end
    Ledger.integrityCache[character] = { valid = true, reason = "MATCH",
        count = #character.movements, after = character.lastCopper,
        nextSequence = character.nextSequence }
    return true, "MATCH"
end

-- Aggregates are derived, never substituted for canonical movement rows.
function Ledger.Statistics(character, period)
    local selectedSession = period == "SESSION" and character.activeSessionId or nil
    local cacheKey = period .. ":" .. (selectedSession or "ALL")
    local caches = Ledger.statsCache[character]
    if not caches then caches = {} Ledger.statsCache[character] = caches end
    local cached = caches[cacheKey]
    local revision = character.annotationRevision or 0
    if cached and cached.movementCount == #character.movements
        and cached.annotationRevision == revision then return cached.result end
    local result = { credits = 0, debits = 0, count = 0, categories = {} }
    for _, movement in ipairs(character.movements) do
        if not selectedSession or movement.sessionId == selectedSession then
            local category = Addon.Attribution.EffectiveCategory(character, movement)
            Accumulate(result, movement, category)
        end
    end
    caches[cacheKey] = { result = result, period = period, sessionId = selectedSession,
        movementCount = #character.movements, annotationRevision = revision }
    return result
end

-- Derived month/day index, rebuilt only when movement count changes. The ledger
-- itself remains append-ordered and is never reordered for presentation.
function Ledger.MonthIndex(character)
    local cached = Ledger.indexCache[character]
    if cached and cached.count == #character.movements then return cached.index end
    local index = { months = {}, monthOrder = {} }
    for _, movement in ipairs(character.movements) do UpdateIndex(index, movement) end
    Ledger.indexCache[character] = { index = index, count = #character.movements }
    return index
end
