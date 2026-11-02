-- Goblinomicon Forever: bounded ephemeral hints. Hints never create wallet rows.
local Addon = GoblinomiconForever
Addon.Attribution = { candidates = {}, merchantOpen = false }
local Attribution = Addon.Attribution

function Attribution.RecordQuest(questIdentifier, moneyReward)
    if not Addon.ValidCopper(moneyReward) or moneyReward == 0 then return end
    local now = Addon.Now()
    if not now then return end
    local queue = Attribution.candidates
    queue[#queue + 1] = { category = "Quest Reward", amount = moneyReward,
        observedAt = now, evidence = "QUEST_TURNED_IN" }
    if #queue > 64 then table.remove(queue, 1) end
end

function Attribution.MerchantVisible(visible)
    Attribution.merchantOpen = visible == true
    Attribution.merchantSeenAt = Addon.Now()
end

-- Unique amount-and-time correlation is evidence, not proof of causation.
-- No repair inference from a repair quote or merchant window alone.
function Attribution.Resolve(deltaCopper, observedAt, isGap)
    if isGap then
        return deltaCopper > 0 and "Unclassified Income (Gap)" or "Unclassified Expense (Gap)", "UNKNOWN", "RECONCILIATION"
    end
    local matchedQuest = nil
    local matchCount = 0
    local queue = Attribution.candidates
    for index = #queue, 1, -1 do
        local candidate = queue[index]
        if not observedAt or observedAt - candidate.observedAt > 15 then
            table.remove(queue, index)
        elseif deltaCopper > 0 and candidate.amount == deltaCopper then
            matchedQuest = candidate
            matchCount = matchCount + 1
        end
    end
    if matchCount == 1 then
        for index = #queue, 1, -1 do
            if queue[index] == matchedQuest then table.remove(queue, index) break end
        end
        return "Quest Reward", "CORRELATED", "QUEST_TURNED_IN"
    end
    if matchCount > 1 then
        return deltaCopper > 0 and "Unclassified Income" or "Unclassified Expense", "UNKNOWN", "AMBIGUOUS_QUEST"
    end
    if Attribution.merchantOpen and observedAt and Attribution.merchantSeenAt
        and observedAt - Attribution.merchantSeenAt <= 120 then
        if deltaCopper < 0 then return "Vendor Expense", "CORRELATED", "MERCHANT_WINDOW" end
        return "Vendor Sale", "CORRELATED", "MERCHANT_WINDOW"
    end
    return deltaCopper > 0 and "Unclassified Income" or "Unclassified Expense", "UNKNOWN", "WALLET_DELTA"
end

-- Immutable annotation revisions; never alter an existing monetary row.
function Attribution.AppendRevision(character, movementSequence, newCategory, confidence, evidence)
    if type(character) ~= "table" or type(movementSequence) ~= "number"
        or not character.movements[movementSequence] or type(newCategory) ~= "string"
        or type(confidence) ~= "string" or type(evidence) ~= "string" then
        return nil, "INVALID_ANNOTATION"
    end
    local revisions = character.annotations
    revisions[#revisions + 1] = { sequence = movementSequence, category = newCategory,
        confidence = confidence, evidence = evidence, at = Addon.Now() }
    character.annotationRevision = (character.annotationRevision or 0) + 1
    return true
end

function Attribution.EffectiveCategory(character, movement)
    for index = #character.annotations, 1, -1 do
        local revision = character.annotations[index]
        if revision.sequence == movement.sequence then
            return revision.category, revision.confidence
        end
    end
    return movement.category, movement.confidence
end
