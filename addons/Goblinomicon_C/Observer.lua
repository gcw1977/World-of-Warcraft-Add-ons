-- Goblinomicon Classic - passive wallet observation and conservative attribution.
local addonName, addon = ...
addon.observer = {lastObservedCopper = nil, pending = {}, evidence = {},
    nextEvidenceNumber = 1, flushScheduled = false, eventRegistered = false}

local function RuntimeSeconds()
    if type(GetTime) == "function" then
        local success, value = pcall(GetTime)
        if success and type(value) == "number" and value == value then return value end
    end
    return nil
end

-- Only a valid GetMoney return is a financial observation; events have no delta.
function addon.ReadWallet()
    if type(GetMoney) ~= "function" then
        addon.NoteError("GET_MONEY_API_MISSING")
        return nil
    end
    local success, balance = pcall(GetMoney)
    if not success or not addon.IsCopper(balance) then
        addon.NoteError("GET_MONEY_INVALID")
        return nil
    end
    return balance
end

-- Context is ephemeral and never creates a financial transaction on its own.
function addon.RecordQuestEvidence(moneyReward)
    if type(moneyReward) ~= "number" or not addon.IsCopper(moneyReward)
        or moneyReward == 0 then return end
    local observedAt = RuntimeSeconds()
    if observedAt == nil then return end
    local observer = addon.observer
    local evidence = {kind = "QUEST_REWARD", amountCopper = moneyReward,
        observedAt = observedAt, number = observer.nextEvidenceNumber}
    observer.nextEvidenceNumber = observer.nextEvidenceNumber + 1
    table.insert(observer.evidence, evidence)
    while #observer.evidence > 128 do table.remove(observer.evidence, 1) end
end

local function ResolveAttribution(candidate)
    -- A quest amount is strong evidence only when exactly one eligible quest
    -- event matches. Merchant proximity alone is NOT proof of a purchase.
    local matchingEvidence = nil
    local matchCount = 0
    local now = RuntimeSeconds()
    if now == nil or candidate.observedAt == nil then
        return candidate.afterCopper > candidate.beforeCopper and
            "Unclassified Income" or "Unclassified Expense", "UNKNOWN"
    end
    for _, evidence in ipairs(addon.observer.evidence) do
        if evidence.kind == "QUEST_REWARD"
            and candidate.afterCopper - candidate.beforeCopper == evidence.amountCopper
            and math.abs(candidate.observedAt - evidence.observedAt) <= 1.5
            and math.abs(now - evidence.observedAt) <= 10 then
            matchingEvidence = evidence
            matchCount = matchCount + 1
        end
    end
    if matchCount == 1 then
        -- Consume matched evidence so two equal wallet transitions cannot both
        -- claim the same quest completion.
        for evidenceIndex, evidence in ipairs(addon.observer.evidence) do
            if evidence == matchingEvidence then
                table.remove(addon.observer.evidence, evidenceIndex)
                break
            end
        end
        return "Quest Reward", "CORRELATED"
    end
    if candidate.afterCopper > candidate.beforeCopper then
        return "Unclassified Income", "UNKNOWN"
    end
    return "Unclassified Expense", "UNKNOWN"
end

-- Flush strictly in observation order. A failed append leaves the candidate
-- in memory, records a critical diagnostic and blocks subsequent commits.
function addon.FlushObservedMoney()
    local observer = addon.observer
    observer.flushScheduled = false
    while #observer.pending > 0 do
        local candidate = observer.pending[1]
        local category, confidence = ResolveAttribution(candidate)
        local success, reason = addon.AppendTransaction(candidate, category, confidence)
        if not success then
            addon.NoteError(reason or "PENDING_COMMIT_FAILED")
            return false
        end
        table.remove(observer.pending, 1)
    end
    -- Evidence TTL bounds only transient context, not historical records.
    local now = RuntimeSeconds()
    for evidenceIndex = #observer.evidence, 1, -1 do
        if now == nil or now - observer.evidence[evidenceIndex].observedAt > 10 then
            table.remove(observer.evidence, evidenceIndex)
        end
    end
    if addon.RefreshVisibleUI then
        pcall(addon.RefreshVisibleUI)
    end
    return true
end

local function ScheduleFlush()
    local observer = addon.observer
    if observer.flushScheduled then return end
    observer.flushScheduled = true
    if type(C_Timer) == "table" and type(C_Timer.After) == "function" then
        local success = pcall(C_Timer.After, 0.45, function()
            addon.FlushObservedMoney()
        end)
        if success then return end
    end
    -- Without a supported timer, commit immediately rather than risk losing
    -- a money transition while waiting for speculative context events.
    addon.FlushObservedMoney()
end

-- Called synchronously by PLAYER_MONEY, not by a delayed UI update.
function addon.ObserveMoneyEvent()
    if addon.safeMode or not addon.characterData then return end
    local currentCopper = addon.ReadWallet()
    if currentCopper == nil then return end
    local observer = addon.observer
    if observer.lastObservedCopper == nil then
        observer.lastObservedCopper = currentCopper
        return
    end
    if currentCopper == observer.lastObservedCopper then return end
    local timestamp, timestampQuality = addon.CurrentTimestamp()
    local candidate = {beforeCopper = observer.lastObservedCopper,
        afterCopper = currentCopper, timestamp = timestamp,
        timestampQuality = timestampQuality, observedAt = RuntimeSeconds()}
    observer.lastObservedCopper = currentCopper
    table.insert(observer.pending, candidate)
    ScheduleFlush()
end

-- At initial character entry the first wallet read is an opening baseline,
-- not income. Existing checkpoint differences become a coverage gap epoch.
function addon.BeginWalletObservation()
    if addon.safeMode or addon.characterData then return end
    local walletCopper = addon.ReadWallet()
    if walletCopper == nil then return end
    if type(UnitGUID) ~= "function" then
        addon.NoteError("PLAYER_GUID_API_MISSING")
        return
    end
    local success, playerGuid = pcall(UnitGUID, "player")
    if not success or type(playerGuid) ~= "string" or playerGuid == "" then
        addon.NoteError("PLAYER_GUID_UNAVAILABLE")
        return
    end
    local characterName = type(UnitName) == "function" and UnitName("player") or nil
    local realmName = type(GetRealmName) == "function" and GetRealmName() or nil
    if addon.SelectCharacter(playerGuid, characterName, realmName, walletCopper) then
        addon.observer.lastObservedCopper = walletCopper
    end
end

function addon.ShutdownObserver(isReload)
    if addon.characterData then
        addon.FlushObservedMoney()
    end
    addon.EndSession(isReload)
end
